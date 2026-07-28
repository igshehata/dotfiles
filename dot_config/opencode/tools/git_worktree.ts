import fs from "node:fs"
import path from "node:path"
import { tool } from "@opencode-ai/plugin"
import { execGit, tryGit } from "./git_context"

export type WorktreeRecord = {
  worktree: string
  head?: string
  branch?: string
}

export type WorktreeSuccess = {
  ok: true
  mode: "in_place" | "isolated"
  branch: string
  ref: string
  path: string
  head: string
  created: boolean
  reused: boolean
}

export type WorktreeFailure = {
  ok: false
  error: string
  details?: unknown
}

export function parseGitWorktreeList(output: string): WorktreeRecord[] {
  if (!output.trim()) {
    return []
  }

  const records: WorktreeRecord[] = []
  let current: WorktreeRecord | null = null

  for (const line of output.split("\n")) {
    if (!line.trim()) {
      if (current) {
        records.push(current)
        current = null
      }
      continue
    }

    const [key, ...rest] = line.split(" ")
    const value = rest.join(" ")

    if (key === "worktree") {
      if (current) {
        records.push(current)
      }
      current = { worktree: value }
      continue
    }

    if (!current) {
      continue
    }

    if (key === "HEAD") {
      current.head = value
      continue
    }

    if (key === "branch") {
      current.branch = value
    }
  }

  if (current) {
    records.push(current)
  }

  return records
}

function errorResponse(error: string, details?: unknown): WorktreeFailure {
  return {
    ok: false,
    error,
    ...(details === undefined ? {} : { details }),
  }
}

function slugBranch(branch: string): string {
  return branch.replace(/[^A-Za-z0-9._-]+/g, "-")
}

function absoluteGitPath(cwd: string, gitPathOutput: string): string {
  return path.isAbsolute(gitPathOutput)
    ? gitPathOutput
    : path.resolve(cwd, gitPathOutput)
}

function deriveWorktreePath(cwd: string, branch: string): string {
  const repoRoot = absoluteGitPath(cwd, execGit(["rev-parse", "--show-toplevel"], cwd))
  const commonDir = absoluteGitPath(cwd, execGit(["rev-parse", "--git-common-dir"], cwd))
  const commonBase = path.basename(commonDir) === ".git"
    ? `${path.basename(repoRoot)}.git`
    : path.basename(commonDir)
  const parentDir = path.basename(commonDir) === ".git"
    ? path.dirname(repoRoot)
    : path.dirname(commonDir)

  return path.join(parentDir, `${commonBase}.${slugBranch(branch)}`)
}

function findBranchWorktree(cwd: string, branch: string): WorktreeRecord | null {
  const worktrees = parseGitWorktreeList(execGit(["worktree", "list", "--porcelain"], cwd))
  return worktrees.find((record) => record.branch === `refs/heads/${branch}`) || null
}

export function ensureWorktree(input: {
  cwd: string
  mode: "in_place" | "isolated"
  branch: string
  ref: string
  activeWorktree: string
}): WorktreeSuccess | WorktreeFailure {
  const { cwd, mode, branch, ref, activeWorktree } = input

  try {
    if (mode === "in_place") {
      return {
        ok: true,
        mode,
        branch,
        ref,
        path: activeWorktree,
        head: execGit(["rev-parse", "HEAD"], activeWorktree),
        created: false,
        reused: true,
      }
    }

    const existing = findBranchWorktree(cwd, branch)
    if (existing) {
      return {
        ok: true,
        mode,
        branch,
        ref,
        path: existing.worktree,
        head: execGit(["rev-parse", "HEAD"], existing.worktree),
        created: false,
        reused: true,
      }
    }

    const targetPath = deriveWorktreePath(cwd, branch)
    const localBranchExists = tryGit(["rev-parse", "--verify", branch], cwd).ok
    const remoteBranchExists = tryGit(["rev-parse", "--verify", `origin/${branch}`], cwd).ok

    if (!localBranchExists && !remoteBranchExists) {
      return errorResponse(`Branch ${branch} does not exist locally or on origin.`)
    }

    if (fs.existsSync(targetPath)) {
      return errorResponse(
        `Target worktree path ${targetPath} already exists but is not registered as a branch worktree. Clean it up manually, then retry.`,
      )
    }

    const addArgs = localBranchExists
      ? ["worktree", "add", targetPath, branch]
      : ["worktree", "add", "-b", branch, targetPath, ref]

    execGit(addArgs, cwd)

    const created = findBranchWorktree(cwd, branch)
    if (!created) {
      return errorResponse(`Created worktree for ${branch}, but could not resolve its final path.`)
    }

    return {
      ok: true,
      mode,
      branch,
      ref,
      path: created.worktree,
      head: execGit(["rev-parse", "HEAD"], created.worktree),
      created: true,
      reused: false,
    }
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : String(error))
  }
}

export default tool({
  description: "Ensure an isolated worktree exists for a given branch.",
  args: {
    mode: tool.schema.string(),
    branch: tool.schema.string(),
    ref: tool.schema.string(),
    activeWorktree: tool.schema.string(),
  },
  async execute(args, context) {
    if (args.mode !== "in_place" && args.mode !== "isolated") {
      return JSON.stringify(errorResponse(`Invalid mode ${args.mode}.`), null, 2)
    }

    const cwd = context.directory || process.cwd()
    const result = ensureWorktree({
      cwd,
      mode: args.mode,
      branch: args.branch,
      ref: args.ref,
      activeWorktree: args.activeWorktree,
    })

    if (result.ok) {
      context.metadata({
        title: "Worktree ready",
        metadata: {
          mode: result.mode,
          branch: result.branch,
          created: result.created,
          path: result.path,
        },
      })
    }

    return JSON.stringify(result, null, 2)
  },
})
