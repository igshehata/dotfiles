import { tool } from "@opencode-ai/plugin";

function transitionTool(client, targetAgent, description, prompt) {
  return tool({
    description,
    args: {},
    async execute(_args, context) {
      const result = await client.session.prompt({
        path: { id: context.sessionID },
        query: { directory: context.directory },
        body: {
          agent: targetAgent,
          noReply: true,
          parts: [{ type: "text", text: prompt }],
        },
      });

      if (result.error) {
        const detail = typeof result.error === "string" ? result.error : JSON.stringify(result.error);
        throw new Error(`Could not switch to ${targetAgent} agent: ${detail}`);
      }

      context.metadata({
        title: `Switching to ${targetAgent} agent`,
        metadata: { targetAgent },
      });

      return `Queued the next session turn for the ${targetAgent} agent.`;
    },
  });
}

export const AgentModeTransitionPlugin = async ({ client }) => ({
  tool: {
    switch_to_build: transitionTool(
      client,
      "build",
      "Switch an approved plan to the build agent. Use only after the user explicitly approves implementation.",
      "The plan has been approved. Continue in execution mode and implement the approved plan.",
    ),
    switch_to_plan: transitionTool(
      client,
      "plan",
      "Switch execution back to the plan agent when the approved plan requires fundamental revision.",
      "Execution has paused because the plan needs revision. Re-enter planning mode, update the plan, and request approval before resuming implementation.",
    ),
  },
});
