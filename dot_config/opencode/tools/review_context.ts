import { tool } from "@opencode-ai/plugin"
import {
  execGit,
  resolveGitContext,
  type GitContextFailure,
  type GitContextSuccess,
} from "./git_context"

const FULL_PROJECT_BRANCHES = ["main", "develop"] as const

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

export type ReviewContextSuccess = GitContextSuccess & {
  reviewFileCount: number
  shouldLoadVercelReactBestPractices: boolean
}

function collectTreeFiles(cwd: string, ref: string): string[] {
  const output = execGit(["ls-tree", "-r", "--name-only", ref], cwd)
  return output ? output.split("\n").filter(Boolean) : []
}

export function resolveReviewContext(input: {
  cwd: string
  worktree: string
  rawArguments: string
}): ReviewContextSuccess | GitContextFailure {
  const git = resolveGitContext({
    ...input,
    fullProjectBranches: FULL_PROJECT_BRANCHES,
  })

  if (!git.ok) {
    return git
  }

  const reviewFiles = git.reviewScope === "full_project"
    ? [...new Set([...collectTreeFiles(input.cwd, git.ref), ...git.localChangedFiles])].sort()
    : git.changedFiles

  return {
    ...git,
    reviewFileCount: reviewFiles.length,
    shouldLoadVercelReactBestPractices: isFrontendRelevant(reviewFiles),
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
    const result = resolveReviewContext({
      cwd,
      worktree,
      rawArguments: args.rawArguments || "",
    })

    if (!result.ok) {
      return JSON.stringify(result, null, 2)
    }

    context.metadata({
      title: "Review context prepared",
      metadata: {
        mode: result.mode,
        reviewScope: result.reviewScope,
        branch: result.branch,
        targetBranch: result.targetBranch,
        reviewFiles: result.reviewFileCount,
      },
    })

    return JSON.stringify(result, null, 2)
  },
})
