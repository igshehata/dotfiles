import fs from "node:fs"
import path from "node:path"
import cp from "node:child_process"
import { tool } from "@opencode-ai/plugin"

export type ParsedArguments = {
  reviewBranchInput: string | null
  targetBranch: string
  requestedFeatures: string[]
}

export type ReviewContextSuccess = {
  ok: true
  mode: "in_place" | "isolated"
  requestedBranch: string | null
  reviewBranch: string
  reviewRef: string
  targetBranch: string
  targetRef: string
  requestedFeatures: string[]
  changedFiles: string[]
  branchChangedFiles: string[]
  localChangedFiles: string[]
  hasLocalChanges: boolean
  activeBranch: string
  activeWorktree: string
  inferredFeatures: string[]
  availableFeatureFolders: string[]
  repoContext: {
    root: string
    coreDocs: string[]
    repoConventionPresent: boolean
  }
  fallbackContextFiles: string[]
  fetchWarning: string | null
  shouldLoadProjectContext: true
  shouldLoadVercelReactBestPractices: boolean
}

export type ReviewContextFailure = {
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

function tokenize(raw: string): string[] {
  const tokens: string[] = []
  let current = ""
  let quote: string | null = null
  let escape = false

  for (const char of raw.trim()) {
    if (escape) {
      current += char
      escape = false
      continue
    }

    if (char === "\\") {
      escape = true
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

export function parseRawArguments(rawArguments: string): ParsedArguments {
  const tokens = tokenize(rawArguments)
  const positional: string[] = []
  const explicit: Record<string, string> = {}

  for (const token of tokens) {
    const match = token.match(/^(branch|target|features)=(.*)$/)
    if (!match) {
      positional.push(token)
      continue
    }

    explicit[match[1]] = match[2]
  }

  let reviewBranchInput: string | null = null
  let targetBranch = "develop"
  let requestedFeatures: string[] = []

  if (positional.length >= 1) {
    reviewBranchInput = positional[0]
  }

  if (positional.length >= 2) {
    targetBranch = positional[1]
  }

  if (explicit.branch) {
    reviewBranchInput = explicit.branch.trim() || null
  }

  if (explicit.target) {
    targetBranch = explicit.target.trim() || "develop"
  }

  if (Object.prototype.hasOwnProperty.call(explicit, "features")) {
    requestedFeatures = explicit.features
      .split(",")
      .map((feature) => feature.trim())
      .filter(Boolean)
  }

  return {
    reviewBranchInput,
    targetBranch,
    requestedFeatures,
  }
}

function walkMarkdownFiles(root: string): string[] {
  if (!fs.existsSync(root)) {
    return []
  }

  const results: string[] = []
  const stack = [root]

  while (stack.length > 0) {
    const current = stack.pop()
    if (!current) {
      continue
    }

    const entries = fs.readdirSync(current, { withFileTypes: true })

    for (const entry of entries) {
      const entryPath = path.join(current, entry.name)
      if (entry.isDirectory()) {
        stack.push(entryPath)
        continue
      }

      if (entry.isFile() && entry.name.endsWith(".md")) {
        results.push(entryPath)
      }
    }
  }

  return results.sort()
}

function walkFilesMatching(root: string, predicate: (filePath: string, name: string) => boolean): string[] {
  if (!fs.existsSync(root)) {
    return []
  }

  const results: string[] = []
  const stack = [root]

  while (stack.length > 0) {
    const current = stack.pop()
    if (!current) {
      continue
    }

    const entries = fs.readdirSync(current, { withFileTypes: true })

    for (const entry of entries) {
      const entryPath = path.join(current, entry.name)
      if (entry.isDirectory()) {
        stack.push(entryPath)
        continue
      }

      if (entry.isFile() && predicate(entryPath, entry.name)) {
        results.push(entryPath)
      }
    }
  }

  return results.sort()
}

function toRelative(worktree: string, filePath: string): string {
  return path.relative(worktree, filePath) || "."
}

function unique(values: string[]): string[] {
  return [...new Set(values)]
}

function listFeatureFolders(projectContextRoot: string): string[] {
  const featuresRoot = path.join(projectContextRoot, "features")
  if (!fs.existsSync(featuresRoot)) {
    return []
  }

  return fs
    .readdirSync(featuresRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort()
}

function inferFeatures(changedFiles: string[], availableFeatures: string[]): string[] {
  if (availableFeatures.length === 0) {
    return []
  }

  const lowerChanged = changedFiles.map((file) => file.toLowerCase())
  const matches: string[] = []

  for (const feature of availableFeatures) {
    const featureLower = feature.toLowerCase()
    const featureToken = featureLower.replace(/[-_]/g, " ").trim()
    const patterns = unique([
      `/${featureLower}/`,
      `/${featureLower}-`,
      `/${featureLower}_`,
      `/${featureLower}.`,
      `/${featureLower}`,
      featureToken,
    ])

    if (lowerChanged.some((file) => patterns.some((pattern) => file.includes(pattern)))) {
      matches.push(feature)
    }
  }

  return matches.sort()
}

function isFrontendRelevant(changedFiles: string[]): boolean {
  return changedFiles.some((file) => {
    const lower = file.toLowerCase()
    return [
      ".tsx",
      ".jsx",
      ".css",
      ".scss",
      ".sass",
      ".less",
      ".mdx",
    ].some((suffix) => lower.endsWith(suffix)) ||
      lower.includes("next.config") ||
      lower.startsWith("app/") ||
      lower.startsWith("src/app/") ||
      lower.includes("/components/") ||
      lower.includes("/pages/") ||
      lower.includes("/hooks/")
  })
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

function fetchOriginRefs(cwd: string, refs: string[]): { ok: boolean; warning: string | null } {
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

function resolveReviewRef(cwd: string, activeBranch: string, requestedBranch: string | null) {
  if (!requestedBranch || requestedBranch === activeBranch) {
    return {
      reviewBranch: activeBranch,
      reviewRef: activeBranch,
    }
  }

  const remoteRef = `origin/${requestedBranch}`
  const localSha = tryGit(["rev-parse", "--verify", `${requestedBranch}^{commit}`], cwd)
  const remoteSha = tryGit(["rev-parse", "--verify", `${remoteRef}^{commit}`], cwd)

  if (!localSha.ok && !remoteSha.ok) {
    throw new Error(
      `Review branch ${requestedBranch} does not exist locally or on origin. Push or fetch the branch, then rerun /review.`,
    )
  }

  if (!remoteSha.ok) {
    // Local-only branch (never pushed, or remote unreachable).
    return { reviewBranch: requestedBranch, reviewRef: requestedBranch }
  }

  if (!localSha.ok) {
    return { reviewBranch: requestedBranch, reviewRef: remoteRef }
  }

  if (localSha.stdout === remoteSha.stdout) {
    return { reviewBranch: requestedBranch, reviewRef: remoteRef }
  }

  const aheadRaw = tryGit(["rev-list", "--count", `${remoteRef}..${requestedBranch}`], cwd).stdout
  const behindRaw = tryGit(["rev-list", "--count", `${requestedBranch}..${remoteRef}`], cwd).stdout
  const ahead = Number(aheadRaw)
  const behind = Number(behindRaw)

  // Ahead-only: user is reviewing their own unpushed work. Use local so the worktree
  // (which review_worktree.ts checks out from the local branch) and the diff ref agree.
  if (Number.isFinite(ahead) && Number.isFinite(behind) && ahead > 0 && behind === 0) {
    return { reviewBranch: requestedBranch, reviewRef: requestedBranch }
  }

  const describeDivergence =
    Number.isFinite(ahead) && Number.isFinite(behind) && behind > 0 && ahead === 0
      ? `behind ${remoteRef} by ${behind} commit(s)`
      : `diverged from ${remoteRef} (ahead ${aheadRaw || "?"}, behind ${behindRaw || "?"})`

  throw new Error(
    `Local ${requestedBranch} is ${describeDivergence}. ` +
      `Reconcile with the remote before reviewing (fetch + fast-forward, or reset to origin). ` +
      `/review refuses to diff against a stale local branch.`,
  )
}

function errorResponse(error: string, details?: unknown): ReviewContextFailure {
  return {
    ok: false,
    error,
    ...(details === undefined ? {} : { details }),
  }
}

export function prepareReviewContext(input: {
  cwd: string
  worktree: string
  rawArguments: string
}): ReviewContextSuccess | ReviewContextFailure {
  const { cwd, worktree, rawArguments } = input

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
    const targetBranch = parsed.targetBranch || "develop"

    if (targetBranch === activeBranch && (!parsed.reviewBranchInput || parsed.reviewBranchInput === activeBranch)) {
      return errorResponse(
        `Review branch and target branch both resolve to ${targetBranch}. /review needs a feature branch against a different target branch.`,
      )
    }

    const refsToFetch = [targetBranch]
    if (parsed.reviewBranchInput && parsed.reviewBranchInput !== activeBranch) {
      refsToFetch.push(parsed.reviewBranchInput)
    }
    const fetchWarning = fetchOriginRefs(cwd, refsToFetch).warning

    const targetRef = `origin/${targetBranch}`
    const targetExists = tryGit(["rev-parse", "--verify", targetRef], cwd)
    if (!targetExists.ok) {
      return errorResponse(
        `Target ref ${targetRef} is not available locally${
          fetchWarning ? ` (${fetchWarning})` : ""
        }. Ensure the target branch exists on origin and your network is reachable, then rerun /review.`,
      )
    }

    const { reviewBranch, reviewRef } = resolveReviewRef(cwd, activeBranch, parsed.reviewBranchInput)
    if (reviewBranch === targetBranch) {
      return errorResponse(
        `Review branch and target branch both resolve to ${targetBranch}. /review needs a feature branch against a different target branch.`,
      )
    }

    const mode = reviewBranch === activeBranch ? "in_place" : "isolated"
    const branchChangedFilesOutput = execGit([
      "diff",
      "--name-only",
      `${targetRef}...${reviewRef}`,
    ], cwd)
    const branchChangedFiles = branchChangedFilesOutput ? branchChangedFilesOutput.split("\n").filter(Boolean) : []

    const statusOutput = execGit(["status", "--porcelain"], cwd)
    const localChangedFiles = mode === "in_place"
      ? collectStatusFiles(statusOutput)
      : []

    const changedFiles = unique([...branchChangedFiles, ...localChangedFiles]).sort()
    if (changedFiles.length === 0) {
      return errorResponse(
        `No changes to review for ${reviewBranch} against ${targetRef}. The branch may already be merged, or there may be nothing unique to review.`,
      )
    }

    const projectContextRoot = path.join(worktree, "project-context")
    const coreRoot = path.join(projectContextRoot, "core")
    const featuresRoot = path.join(projectContextRoot, "features")
    const coreDocs = walkMarkdownFiles(coreRoot).map((file) => toRelative(worktree, file))
    const availableFeatures = listFeatureFolders(projectContextRoot)
    const inferredFeatures = inferFeatures(changedFiles, availableFeatures)

    const fallbackContextFiles: string[] = []
    const agentsFile = path.join(worktree, "AGENTS.md")
    const readmeFile = path.join(worktree, "README.md")
    const rulesRoot = path.join(worktree, ".claude", "rules")

    if (fs.existsSync(agentsFile)) {
      fallbackContextFiles.push(toRelative(worktree, agentsFile))
    }

    if (fs.existsSync(readmeFile)) {
      fallbackContextFiles.push(toRelative(worktree, readmeFile))
    }

    for (const file of walkFilesMatching(rulesRoot, (filePath) => filePath.endsWith(".md"))) {
      fallbackContextFiles.push(toRelative(worktree, file))
    }

    const repoConventionPresent = fs.existsSync(coreRoot) || fs.existsSync(featuresRoot)

    return {
      ok: true,
      mode,
      requestedBranch: parsed.reviewBranchInput,
      reviewBranch,
      reviewRef,
      targetBranch,
      targetRef,
      requestedFeatures: parsed.requestedFeatures,
      changedFiles,
      branchChangedFiles,
      localChangedFiles,
      hasLocalChanges: localChangedFiles.length > 0,
      activeBranch,
      activeWorktree: worktree,
      inferredFeatures,
      availableFeatureFolders: availableFeatures,
      repoContext: {
        root: toRelative(worktree, projectContextRoot),
        coreDocs,
        repoConventionPresent,
      },
      fallbackContextFiles,
      fetchWarning,
      shouldLoadProjectContext: true,
      shouldLoadVercelReactBestPractices: isFrontendRelevant(changedFiles),
    }
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : String(error))
  }
}

export default tool({
  description: "Resolve review branches, review scope, and routing hints.",
  args: {
    rawArguments: tool.schema.string().default(""),
  },
  async execute(args, context) {
    const cwd = context.directory || process.cwd()
    const worktree = context.worktree || cwd
    const result = prepareReviewContext({
      cwd,
      worktree,
      rawArguments: args.rawArguments || "",
    })

    if (result.ok) {
      context.metadata({
        title: "Review context prepared",
        metadata: {
          mode: result.mode,
          reviewBranch: result.reviewBranch,
          targetBranch: result.targetBranch,
          changedFiles: result.changedFiles.length,
        },
      })
    }

    return JSON.stringify(result, null, 2)
  },
})
