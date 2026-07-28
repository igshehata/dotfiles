import cp from "node:child_process"
import { tool } from "@opencode-ai/plugin"

export function execGit(args: string[], cwd: string): string {
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

export function tryGit(args: string[], cwd: string) {
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

function tokenize(raw: string): string[] {
  const tokens: string[] = []
  let current = ""
  let quote: string | null = null
  let isEscaped = false

  for (const char of raw.trim()) {
    if (isEscaped) {
      current += char
      isEscaped = false
      continue
    }

    if (char === "\\") {
      isEscaped = true
      continue
    }

    if (quote) {
      if (char === quote) {
        quote = null
      } else {
        current += char
      }
      continue
    }

    if (char === '"' || char === "'") {
      quote = char
      continue
    }

    if (/\s/.test(char)) {
      if (current) {
        tokens.push(current)
        current = ""
      }
      continue
    }

    current += char
  }

  if (current) {
    tokens.push(current)
  }

  return tokens
}

export type ParsedArguments = {
  branchInput: string | null
  targetBranch: string
}

export function parseRawArguments(rawArguments: string): ParsedArguments {
  const tokens = tokenize(rawArguments)
  const positional: string[] = []
  const explicit: Record<string, string> = {}

  for (const token of tokens) {
    const match = token.match(/^(branch|target)=(.*)$/)
    if (!match) {
      positional.push(token)
      continue
    }

    explicit[match[1]] = match[2]
  }

  let branchInput: string | null = null
  let targetBranch = "develop"

  if (positional.length >= 1) {
    branchInput = positional[0]
  }

  if (positional.length >= 2) {
    targetBranch = positional[1]
  }

  if (explicit.branch) {
    branchInput = explicit.branch.trim() || null
  }

  if (explicit.target) {
    targetBranch = explicit.target.trim() || "develop"
  }

  return { branchInput, targetBranch }
}

function unique(values: string[]): string[] {
  return [...new Set(values)]
}

function parsePorcelainPath(line: string): string | null {
  const payload = line.slice(3).trim()
  if (!payload) {
    return null
  }

  if (payload.includes(" -> ")) {
    return payload.split(" -> ").pop() || null
  }

  return payload
}

export function collectStatusFiles(statusOutput: string): string[] {
  if (!statusOutput.trim()) {
    return []
  }

  return unique(
    statusOutput
      .split("\n")
      .map((line) => parsePorcelainPath(line))
      .filter((file): file is string => Boolean(file)),
  ).sort()
}

export function fetchOriginRefs(cwd: string, refs: string[]): { ok: boolean; warning: string | null } {
  const branches = [...new Set(refs.filter(Boolean))]
  if (branches.length === 0) {
    return { ok: true, warning: null }
  }

  const result = tryGit([
    "fetch",
    "--quiet",
    "--no-tags",
    "origin",
    ...branches.map((branch) => `+refs/heads/${branch}:refs/remotes/origin/${branch}`),
  ], cwd)

  if (result.ok) {
    return { ok: true, warning: null }
  }

  const detail = (result.stderr || "").replace(/\s+/g, " ").trim()
  return {
    ok: false,
    warning: `git fetch origin ${branches.join(" ")} failed; proceeding with existing refs${detail ? ` (${detail})` : ""}.`,
  }
}

export function resolveRef(cwd: string, activeBranch: string, requestedBranch: string | null) {
  if (!requestedBranch || requestedBranch === activeBranch) {
    return {
      branch: activeBranch,
      ref: activeBranch,
    }
  }

  const remoteRef = `origin/${requestedBranch}`
  const localSha = tryGit(["rev-parse", "--verify", `${requestedBranch}^{commit}`], cwd)
  const remoteSha = tryGit(["rev-parse", "--verify", `${remoteRef}^{commit}`], cwd)

  if (!localSha.ok && !remoteSha.ok) {
    throw new Error(
      `Branch ${requestedBranch} does not exist locally or on origin. Push or fetch the branch, then retry.`,
    )
  }

  if (!remoteSha.ok) {
    return { branch: requestedBranch, ref: requestedBranch }
  }

  if (!localSha.ok) {
    return { branch: requestedBranch, ref: remoteRef }
  }

  if (localSha.stdout === remoteSha.stdout) {
    return { branch: requestedBranch, ref: remoteRef }
  }

  const aheadRaw = tryGit(["rev-list", "--count", `${remoteRef}..${requestedBranch}`], cwd).stdout
  const behindRaw = tryGit(["rev-list", "--count", `${requestedBranch}..${remoteRef}`], cwd).stdout
  const ahead = Number(aheadRaw)
  const behind = Number(behindRaw)

  if (Number.isFinite(ahead) && Number.isFinite(behind) && ahead > 0 && behind === 0) {
    return { branch: requestedBranch, ref: requestedBranch }
  }

  const describeDivergence =
    Number.isFinite(ahead) && Number.isFinite(behind) && behind > 0 && ahead === 0
      ? `behind ${remoteRef} by ${behind} commit(s)`
      : `diverged from ${remoteRef} (ahead ${aheadRaw || "?"}, behind ${behindRaw || "?"})`

  throw new Error(
    `Local ${requestedBranch} is ${describeDivergence}. ` +
      `Reconcile with the remote before proceeding (fetch + fast-forward, or reset to origin).`,
  )
}

export type GitContextSuccess = {
  ok: true
  mode: "in_place" | "isolated"
  reviewScope: "changed_files" | "full_project"
  requestedBranch: string | null
  branch: string
  ref: string
  targetBranch: string
  targetRef: string
  changedFiles: string[]
  branchChangedFiles: string[]
  localChangedFiles: string[]
  hasLocalChanges: boolean
  activeBranch: string
  activeWorktree: string
  fetchWarning: string | null
}

export type GitContextFailure = {
  ok: false
  error: string
  details?: unknown
}

function errorResponse(error: string, details?: unknown): GitContextFailure {
  return {
    ok: false,
    error,
    ...(details === undefined ? {} : { details }),
  }
}

export function resolveGitContext(input: {
  cwd: string
  worktree: string
  rawArguments: string
  fullProjectBranches?: readonly string[]
}): GitContextSuccess | GitContextFailure {
  const { cwd, worktree, rawArguments, fullProjectBranches = [] } = input

  try {
    const inside = execGit(["rev-parse", "--is-inside-work-tree"], cwd)
    if (inside !== "true") {
      return errorResponse("Not inside a git repository or worktree.")
    }

    const activeBranch = execGit(["branch", "--show-current"], cwd)
    if (!activeBranch) {
      return errorResponse("Could not determine the active branch for this worktree.")
    }

    const parsed = parseRawArguments(rawArguments || "")
    const requestedBranch = parsed.branchInput || activeBranch
    const reviewScope = fullProjectBranches.includes(requestedBranch)
      ? "full_project"
      : "changed_files"
    const targetBranch = reviewScope === "full_project"
      ? requestedBranch
      : parsed.targetBranch || "develop"

    if (
      reviewScope === "changed_files" &&
      targetBranch === activeBranch &&
      (!parsed.branchInput || parsed.branchInput === activeBranch)
    ) {
      return errorResponse(
        `Branch and target both resolve to ${targetBranch}. Need a feature branch against a different target.`,
      )
    }

    const refsToFetch = reviewScope === "full_project" ? [] : [targetBranch]
    if (parsed.branchInput && parsed.branchInput !== activeBranch) {
      refsToFetch.push(parsed.branchInput)
    }
    const fetchWarning = fetchOriginRefs(cwd, refsToFetch).warning

    const { branch, ref } = resolveRef(cwd, activeBranch, parsed.branchInput)
    const targetRef = reviewScope === "full_project" ? ref : `origin/${targetBranch}`

    if (reviewScope === "changed_files") {
      const targetExists = tryGit(["rev-parse", "--verify", targetRef], cwd)
      if (!targetExists.ok) {
        return errorResponse(
          `Target ref ${targetRef} is not available locally${
            fetchWarning ? ` (${fetchWarning})` : ""
          }. Ensure the target branch exists on origin and your network is reachable.`,
        )
      }
    }

    if (reviewScope === "changed_files" && branch === targetBranch) {
      return errorResponse(
        `Branch and target both resolve to ${targetBranch}. Need a feature branch against a different target.`,
      )
    }

    const mode = branch === activeBranch ? "in_place" : "isolated"
    const branchChangedFiles = reviewScope === "full_project"
      ? []
      : execGit([
          "diff",
          "--name-only",
          `${targetRef}...${ref}`,
        ], cwd).split("\n").filter(Boolean)

    const statusOutput = execGit(["status", "--porcelain"], cwd)
    const localChangedFiles = mode === "in_place"
      ? collectStatusFiles(statusOutput)
      : []

    const changedFiles = unique([...branchChangedFiles, ...localChangedFiles]).sort()
    if (reviewScope === "changed_files" && changedFiles.length === 0) {
      return errorResponse(
        `No changes found for ${branch} against ${targetRef}. The branch may already be merged.`,
      )
    }

    return {
      ok: true,
      mode,
      reviewScope,
      requestedBranch: parsed.branchInput,
      branch,
      ref,
      targetBranch,
      targetRef,
      changedFiles,
      branchChangedFiles,
      localChangedFiles,
      hasLocalChanges: localChangedFiles.length > 0,
      activeBranch,
      activeWorktree: worktree,
      fetchWarning,
    }
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : String(error))
  }
}

export default tool({
  description: "Resolve branches, compute diffs, and return structured git context for any workflow.",
  args: {
    rawArguments: tool.schema.string().default(""),
  },
  async execute(args, context) {
    const cwd = context.directory || process.cwd()
    const worktree = context.worktree || cwd
    const result = resolveGitContext({
      cwd,
      worktree,
      rawArguments: args.rawArguments || "",
    })

    if (result.ok) {
      context.metadata({
        title: "Git context resolved",
        metadata: {
          mode: result.mode,
          branch: result.branch,
          targetBranch: result.targetBranch,
          changedFiles: result.changedFiles.length,
        },
      })
    }

    return JSON.stringify(result, null, 2)
  },
})
