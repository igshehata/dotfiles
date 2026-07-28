import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import cp from "node:child_process"
import { describe, expect, it } from "bun:test"

import { parseRawArguments, resolveGitContext } from "../tools/git_context"
import { resolveReviewContext } from "../tools/review_context"
import { ensureWorktree } from "../tools/git_worktree"

function execGit(args: string[], cwd: string) {
  const result = cp.spawnSync("git", args, {
    cwd,
    encoding: "utf8",
  })

  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || `git ${args.join(" ")} failed`).trim())
  }

  return (result.stdout || "").trim()
}

function setupRepo() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "review-workflow-"))
  const remote = path.join(root, "remote.git")
  const repo = path.join(root, "repo")

  execGit(["init", "--bare", remote], root)
  execGit(["clone", remote, repo], root)
  execGit(["config", "user.name", "Review Workflow Test"], repo)
  execGit(["config", "user.email", "review-workflow@example.com"], repo)

  fs.mkdirSync(path.join(repo, "src"))
  fs.writeFileSync(path.join(repo, "README.md"), "base\n")
  fs.writeFileSync(path.join(repo, "src", "App.tsx"), "export const App = () => null\n")
  execGit(["add", "README.md", "src/App.tsx"], repo)
  execGit(["commit", "-m", "base commit"], repo)
  execGit(["branch", "-M", "develop"], repo)
  execGit(["push", "-u", "origin", "develop"], repo)
  execGit(["branch", "main"], repo)
  execGit(["push", "origin", "main"], repo)

  execGit(["checkout", "-b", "feat/performance-tracker"], repo)
  fs.writeFileSync(path.join(repo, "performance.txt"), "performance\n")
  execGit(["add", "performance.txt"], repo)
  execGit(["commit", "-m", "performance branch"], repo)
  execGit(["push", "-u", "origin", "feat/performance-tracker"], repo)

  execGit(["checkout", "develop"], repo)

  return { root, repo }
}

describe("git_context", () => {
  it("parses positional arguments", () => {
    expect(parseRawArguments("")).toEqual({
      branchInput: null,
      targetBranch: "develop",
    })

    expect(parseRawArguments("feat/performance-tracker")).toEqual({
      branchInput: "feat/performance-tracker",
      targetBranch: "develop",
    })

    expect(parseRawArguments("feat/performance-tracker main")).toEqual({
      branchInput: "feat/performance-tracker",
      targetBranch: "main",
    })
  })

  it("parses named arguments", () => {
    expect(parseRawArguments("branch=feat/x target=main")).toEqual({
      branchInput: "feat/x",
      targetBranch: "main",
    })
  })

  it("resolves in-place context for dirty local changes", () => {
    const { repo } = setupRepo()

    execGit(["checkout", "-b", "feat/local-current"], repo)
    fs.writeFileSync(path.join(repo, "dirty.txt"), "dirty\n")

    const result = resolveGitContext({
      cwd: repo,
      worktree: repo,
      rawArguments: "",
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return

    expect(result.mode).toBe("in_place")
    expect(result.branch).toBe("feat/local-current")
    expect(result.branchChangedFiles).toEqual([])
    expect(result.hasLocalChanges).toBe(true)
    expect(result.localChangedFiles).toContain("dirty.txt")
    expect(result.changedFiles).toContain("dirty.txt")
  })

  it("resolves isolated context for another branch", () => {
    const { repo } = setupRepo()

    execGit(["branch", "-D", "feat/performance-tracker"], repo)
    execGit(["checkout", "-b", "feat/current-work"], repo)
    fs.writeFileSync(path.join(repo, "current.txt"), "current\n")

    const result = resolveGitContext({
      cwd: repo,
      worktree: repo,
      rawArguments: "feat/performance-tracker",
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return

    expect(result.mode).toBe("isolated")
    expect(result.branch).toBe("feat/performance-tracker")
    expect(result.ref).toBe("origin/feat/performance-tracker")
    expect(result.changedFiles).toContain("performance.txt")
    expect(result.changedFiles).not.toContain("current.txt")
    expect(result.hasLocalChanges).toBe(false)
  })

  it("errors when branch and target are the same", () => {
    const { repo } = setupRepo()

    const result = resolveGitContext({
      cwd: repo,
      worktree: repo,
      rawArguments: "develop",
    })

    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.error).toContain("both resolve to develop")
  })
})

describe("review_context", () => {
  it("treats an explicit develop branch as a full-project review", () => {
    const { repo } = setupRepo()

    const result = resolveReviewContext({
      cwd: repo,
      worktree: repo,
      rawArguments: "develop",
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return

    expect(result.reviewScope).toBe("full_project")
    expect(result.mode).toBe("in_place")
    expect(result.branch).toBe("develop")
    expect(result.targetBranch).toBe("develop")
    expect(result.changedFiles).toEqual([])
    expect(result.reviewFileCount).toBe(2)
    expect(result.shouldLoadVercelReactBestPractices).toBe(true)
  })

  it("treats the active base branch as a full-project review without arguments", () => {
    const { repo } = setupRepo()

    const result = resolveReviewContext({
      cwd: repo,
      worktree: repo,
      rawArguments: "",
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return

    expect(result.reviewScope).toBe("full_project")
    expect(result.branch).toBe("develop")
  })

  it("treats main with an identical target as a full-project review", () => {
    const { repo } = setupRepo()

    for (const rawArguments of ["main", "main target=main"]) {
      const result = resolveReviewContext({
        cwd: repo,
        worktree: repo,
        rawArguments,
      })

      expect(result.ok).toBe(true)
      if (!result.ok) continue

      expect(result.reviewScope).toBe("full_project")
      expect(result.mode).toBe("isolated")
      expect(result.branch).toBe("main")
      expect(result.targetBranch).toBe("main")
      expect(result.reviewFileCount).toBe(2)
    }
  })

  it("still rejects identical non-base review and target branches", () => {
    const { repo } = setupRepo()

    const result = resolveReviewContext({
      cwd: repo,
      worktree: repo,
      rawArguments: "feat/performance-tracker target=feat/performance-tracker",
    })

    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.error).toContain("both resolve to feat/performance-tracker")
  })
})

describe("git_worktree", () => {
  it("returns active worktree for in_place mode", () => {
    const { repo } = setupRepo()

    const result = ensureWorktree({
      cwd: repo,
      mode: "in_place",
      branch: "develop",
      ref: "develop",
      activeWorktree: repo,
    })

    expect(result.ok).toBe(true)
    if (!result.ok) return

    expect(result.mode).toBe("in_place")
    expect(result.path).toBe(repo)
    expect(result.created).toBe(false)
    expect(result.reused).toBe(true)
  })

  it("creates and reuses isolated worktrees", () => {
    const { repo } = setupRepo()

    execGit(["branch", "-D", "feat/performance-tracker"], repo)
    execGit(["checkout", "-b", "feat/current-work"], repo)

    const created = ensureWorktree({
      cwd: repo,
      mode: "isolated",
      branch: "feat/performance-tracker",
      ref: "origin/feat/performance-tracker",
      activeWorktree: repo,
    })

    expect(created.ok).toBe(true)
    if (!created.ok) return

    expect(created.created).toBe(true)
    expect(created.reused).toBe(false)
    expect(created.path).not.toBe(repo)
    expect(execGit(["branch", "--show-current"], created.path)).toBe("feat/performance-tracker")

    const reused = ensureWorktree({
      cwd: repo,
      mode: "isolated",
      branch: "feat/performance-tracker",
      ref: "origin/feat/performance-tracker",
      activeWorktree: repo,
    })

    expect(reused.ok).toBe(true)
    if (!reused.ok) return

    expect(reused.created).toBe(false)
    expect(reused.reused).toBe(true)
    expect(reused.path).toBe(created.path)
  })
})
