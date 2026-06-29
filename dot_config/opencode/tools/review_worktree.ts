import fs from "node:fs"
import path from "node:path"
import cp from "node:child_process"
import { tool } from "@opencode-ai/plugin"

export type WorktreeRecord = {
  worktree: string
  head?: string
  branch?: string
}

export type ReviewWorktreeSuccess = {
  ok: true
  mode: "in_place" | "isolated"
  reviewBranch: string
  reviewRef: string
  reviewPath: string
  head: string
  created: boolean
  reused: boolean
}

export type ReviewWorktreeFailure = {
  ok: false
  error: string
  details?: unknown
}

function execGit(args: string[], cwd: string): string {
  const result = cp.spawnSync("git", args, {
    cwd,
    encoding: "utf8",
  })

  if (result.error) {
    throw result.error
  }

  if (result.status !== 0) {
    const message = (result.stderr || result.stdout || `git ${args.join(" ")} failed`).trim()
    throw new Error(message)
  }

  return (result.stdout || "").trim()
}

function tryGit(args: string[], cwd: string) {
  const result = cp.spawnSync("git", args, {
    cwd,
    encoding: "utf8",
  })

  return {
    ok: result.status === 0,
    stdout: (result.stdout || "").trim(),
    stderr: (result.stderr || "").trim(),
  }
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

function errorResponse(error: string, details?: unknown): ReviewWorktreeFailure {
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

function deriveWorktreePath(cwd: string, reviewBranch: string): string {
  const repoRoot = absoluteGitPath(cwd, execGit(["rev-parse", "--show-toplevel"], cwd))
  const commonDir = absoluteGitPath(cwd, execGit(["rev-parse", "--git-common-dir"], cwd))
  const commonBase = path.basename(commonDir) === ".git"
    ? `${path.basename(repoRoot)}.git`
    : path.basename(commonDir)
  const parentDir = path.basename(commonDir) === ".git"
    ? path.dirname(repoRoot)
    : path.dirname(commonDir)

  return path.join(parentDir, `${commonBase}.${slugBranch(reviewBranch)}`)
}

function findBranchWorktree(cwd: string, reviewBranch: string): WorktreeRecord | null {
  const worktrees = parseGitWorktreeList(execGit(["worktree", "list", "--porcelain"], cwd))
  return worktrees.find((record) => record.branch === `refs/heads/${reviewBranch}`) || null
}

export function ensureReviewWorktree(input: {
  cwd: string
  mode: "in_place" | "isolated"
  reviewBranch: string
  reviewRef: string
  activeWorktree: string
}): ReviewWorktreeSuccess | ReviewWorktreeFailure {
  const { cwd, mode, reviewBranch, reviewRef, activeWorktree } = input

  try {
    if (mode === "in_place") {
      return {
        ok: true,
        mode,
        reviewBranch,
        reviewRef,
        reviewPath: activeWorktree,
        head: execGit(["rev-parse", "HEAD"], activeWorktree),
        created: false,
        reused: true,
      }
    }

    const existing = findBranchWorktree(cwd, reviewBranch)
    if (existing) {
      return {
        ok: true,
        mode,
        reviewBranch,
        reviewRef,
        reviewPath: existing.worktree,
        head: execGit(["rev-parse", "HEAD"], existing.worktree),
        created: false,
        reused: true,
      }
    }

    const targetPath = deriveWorktreePath(cwd, reviewBranch)
    const localBranchExists = tryGit(["rev-parse", "--verify", reviewBranch], cwd).ok
    const remoteBranchExists = tryGit(["rev-parse", "--verify", `origin/${reviewBranch}`], cwd).ok

    if (!localBranchExists && !remoteBranchExists) {
      return errorResponse(`Review branch ${reviewBranch} does not exist locally or on origin.`)
    }

    if (fs.existsSync(targetPath)) {
      return errorResponse(
        `Target worktree path ${targetPath} already exists but is not registered as a branch worktree. Clean it up manually, then rerun /review.`,
      )
    }

    const addArgs = localBranchExists
      ? ["worktree", "add", targetPath, reviewBranch]
      : ["worktree", "add", "-b", reviewBranch, targetPath, reviewRef]

    execGit(addArgs, cwd)

    const created = findBranchWorktree(cwd, reviewBranch)
    if (!created) {
      return errorResponse(`Created worktree for ${reviewBranch}, but could not resolve its final path.`)
    }

    return {
      ok: true,
      mode,
      reviewBranch,
      reviewRef,
      reviewPath: created.worktree,
      head: execGit(["rev-parse", "HEAD"], created.worktree),
      created: true,
      reused: false,
    }
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : String(error))
  }
}

export default tool({
  description: "Ensure the correct worktree exists for a review branch.",
  args: {
    mode: tool.schema.string(),
    reviewBranch: tool.schema.string(),
    reviewRef: tool.schema.string(),
    activeWorktree: tool.schema.string(),
  },
  async execute(args, context) {
    if (args.mode !== "in_place" && args.mode !== "isolated") {
      return JSON.stringify(errorResponse(`Invalid review mode ${args.mode}.`), null, 2)
    }

    const cwd = context.directory || process.cwd()
    const result = ensureReviewWorktree({
      cwd,
      mode: args.mode,
      reviewBranch: args.reviewBranch,
      reviewRef: args.reviewRef,
      activeWorktree: args.activeWorktree,
    })

    if (result.ok) {
      context.metadata({
        title: "Review worktree ready",
        metadata: {
          mode: result.mode,
          reviewBranch: result.reviewBranch,
          created: result.created,
          reviewPath: result.reviewPath,
        },
      })
    }

    return JSON.stringify(result, null, 2)
  },
})
