import fs from "node:fs"
import path from "node:path"
import { describe, expect, it } from "bun:test"

import { AgentModeTransitionPlugin } from "../plugins/agent-mode-transition.js"

const configRoot = path.resolve(import.meta.dir, "..")

function readAgent(name: string): string {
  return fs.readFileSync(path.join(configRoot, "agents", `${name}.md`), "utf8")
}

async function createPlugin() {
  const prompts: unknown[] = []
  const hooks = await AgentModeTransitionPlugin({
    client: {
      session: {
        prompt: async (input: unknown) => {
          prompts.push(input)
          return { data: true }
        },
      },
    },
    directory: "/repo",
  })

  return { hooks, prompts }
}

function toolContext(agent: string) {
  return {
    sessionID: "session-1",
    messageID: "message-1",
    agent,
    directory: "/repo",
    worktree: "/repo",
    abort: new AbortController().signal,
    metadata() {},
    async ask() {},
  }
}

describe("agent mode transitions", () => {
  it("denies transition tools outside their owning agents", () => {
    const config = fs.readFileSync(path.join(configRoot, "opencode.jsonc"), "utf8")

    expect(config).toContain('"switch_to_build": "deny"')
    expect(config).toContain('"switch_to_plan": "deny"')
  })

  it("hands an approved plan to build mode", async () => {
    const planAgent = readAgent("plan")

    expect(planAgent).toMatch(/switch_to_build:\s+allow/)
    expect(planAgent).toContain("Call `switch_to_build`")

    const { hooks, prompts } = await createPlugin()
    await hooks.tool.switch_to_build.execute({}, toolContext("plan"))

    expect(prompts).toHaveLength(1)
    expect(prompts[0]).toMatchObject({
      path: { id: "session-1" },
      query: { directory: "/repo" },
      body: { agent: "build", noReply: true },
    })
  })

  it("hands execution back to plan mode", async () => {
    const buildAgent = readAgent("build")

    expect(buildAgent).toMatch(/switch_to_plan:\s+allow/)
    expect(buildAgent).toContain("Call `switch_to_plan`")

    const { hooks, prompts } = await createPlugin()
    await hooks.tool.switch_to_plan.execute({}, toolContext("build"))

    expect(prompts).toHaveLength(1)
    expect(prompts[0]).toMatchObject({
      path: { id: "session-1" },
      query: { directory: "/repo" },
      body: { agent: "plan", noReply: true },
    })
  })
})
