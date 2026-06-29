import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import cp from "node:child_process"
import { describe, expect, it } from "bun:test"

import { parseRawArguments, prepareReviewContext } from "../tools/review_context"
import { ensureReviewWorktree } from "../tools/review_worktree"

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

  fs.writeFileSync(path.join(repo, "README.md"), "base\n")
  execGit(["add", "README.md"], repo)
  execGit(["commit", "-m", "base commit"], repo)
  execGit(["branch", "-M", "develop"], repo)
  execGit(["push", "-u", "origin", "develop"], repo)

  execGit(["checkout", "-b", "feat/performance-tracker"], repo)
  fs.writeFileSync(path.join(repo, "performance.txt"), "performance\n")
  execGit(["add", "performance.txt"], repo)
  execGit(["commit", "-m", "performance branch"], repo)
  execGit(["push", "-u", "origin", "feat/performance-tracker"], repo)

  execGit(["checkout", "develop"], repo)

  return { root, repo }
}

describe("review workflow helpers", () => {
  it("parses one positional argument as the branch to review", () => {
    expect(parseRawArguments("")).toEqual({
      reviewBranchInput: null,
      targetBranch: "develop",
      requestedFeatures: [],
    })

    expect(parseRawArguments("feat/performance-tracker")).toEqual({
      reviewBranchInput: "feat/performance-tracker",
      targetBranch: "develop",
      requestedFeatures: [],
    })

    expect(parseRawArguments("feat/performance-tracker main features=auth,billing")).toEqual({
      reviewBranchInput: "feat/performance-tracker",
      targetBranch: "main",
      requestedFeatures: ["auth", "billing"],
    })
  })

  it("allows in-place review of dirty local changes", () => {
    const { repo } = setupRepo()

    execGit(["checkout", "-b", "feat/local-current"], repo)
    fs.writeFileSync(path.join(repo, "dirty.txt"), "dirty\n")

    const result = prepareReviewContext({
      cwd: repo,
      worktree: repo,
      rawArguments: "",
    })

    expect(result.ok).toBe(true)
    if (!result.ok) {
      return
    }

    expect(result.mode).toBe("in_place")
    expect(result.reviewBranch).toBe("feat/local-current")
    expect(result.branchChangedFiles).toEqual([])
    expect(result.hasLocalChanges).toBe(true)
    expect(result.localChangedFiles).toContain("dirty.txt")
    expect(result.changedFiles).toContain("dirty.txt")
  })

  it("isolates another branch even when the caller worktree is dirty", () => {
    const { repo } = setupRepo()

    execGit(["branch", "-D", "feat/performance-tracker"], repo)
    execGit(["checkout", "-b", "feat/current-work"], repo)
    fs.writeFileSync(path.join(repo, "current.txt"), "current\n")

    const context = prepareReviewContext({
      cwd: repo,
      worktree: repo,
      rawArguments: "feat/performance-tracker",
    })

    expect(context.ok).toBe(true)
    if (!context.ok) {
      return
    }

    expect(context.mode).toBe("isolated")
    expect(context.reviewBranch).toBe("feat/performance-tracker")
    expect(context.reviewRef).toBe("origin/feat/performance-tracker")
    expect(context.changedFiles).toContain("performance.txt")
    expect(context.changedFiles).not.toContain("current.txt")
    expect(context.hasLocalChanges).toBe(false)

    const ensured = ensureReviewWorktree({
      cwd: repo,
      mode: context.mode,
      reviewBranch: context.reviewBranch,
      reviewRef: context.reviewRef,
      activeWorktree: context.activeWorktree,
    })

    expect(ensured.ok).toBe(true)
    if (!ensured.ok) {
      return
    }

    expect(ensured.created).toBe(true)
    expect(ensured.reused).toBe(false)
    expect(ensured.reviewPath).not.toBe(repo)
    expect(execGit(["branch", "--show-current"], ensured.reviewPath)).toBe("feat/performance-tracker")

    const reused = ensureReviewWorktree({
      cwd: repo,
      mode: context.mode,
      reviewBranch: context.reviewBranch,
      reviewRef: context.reviewRef,
      activeWorktree: context.activeWorktree,
    })

    expect(reused.ok).toBe(true)
    if (!reused.ok) {
      return
    }

    expect(reused.created).toBe(false)
    expect(reused.reused).toBe(true)
    expect(reused.reviewPath).toBe(ensured.reviewPath)
  })
})
