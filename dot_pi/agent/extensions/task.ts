import { existsSync } from "node:fs";
import { mkdtemp, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { StringEnum } from "@earendil-works/pi-ai";
import {
  createLocalBashOperations,
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
  formatSize,
  getMarkdownTheme,
  keyHint,
  truncateHead,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import {
  Container,
  Markdown,
  Spacer,
  Text,
  truncateToWidth,
  visibleWidth,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";

// Soft safety rail only. Set PI_TASK_MAX_CONCURRENCY=0 (or unset) for unlimited.
// Historical default was 4; that hard cap is gone.
const envCap = process.env.PI_TASK_MAX_CONCURRENCY;
const MAX_CONCURRENCY =
  envCap === undefined || envCap === "" || envCap === "0"
    ? Number.POSITIVE_INFINITY
    : Math.max(1, Number.parseInt(envCap, 10) || Number.POSITIVE_INFINITY);
const DEFAULT_TIMEOUT_SECONDS = 600;
const MAX_TIMEOUT_SECONDS = 1800;
const TASK_CHILD_ENV = "PI_TASK_CHILD";
const COLLAPSED_ITEM_COUNT = 10;
const MAX_DISPLAY_ITEMS = 400;
const MAX_TEXT_PREVIEW = 4000;
const MAX_RETAINED_TASKS = 50;

const CHILD_SYSTEM_PROMPT = `You are a delegated subagent with an isolated context window.
Complete only the task given to you and return a concise, self-contained result to the parent agent.
Do not delegate to another agent or launch Pi, tmux, Herdr workspaces, background jobs, detached processes, servers, or watchers.
Do not ask the user questions; state any blocking ambiguity in your result.
You may inspect and modify the shared working directory when the task requires it. Never claim work you did not verify.`;

const taskSchema = Type.Object({
  description: Type.Optional(
    Type.String({ description: "Short label for the delegated task", maxLength: 120 }),
  ),
  prompt: Type.String({ description: "Complete instructions for the subagent" }),
  cwd: Type.Optional(
    Type.String({
      description: "Working directory for the subagent; defaults to the current directory",
    }),
  ),
  model: Type.Optional(
    Type.String({ description: "Optional Pi model pattern, such as openai-codex/gpt-5.6-sol" }),
  ),
  thinking: Type.Optional(
    StringEnum(["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const, {
      description: "Optional thinking level; defaults to the parent's current level",
    }),
  ),
  tools: Type.Optional(
    Type.Array(Type.String(), {
      description: "Optional tool allowlist; defaults to the parent's active tools except task",
      minItems: 1,
      maxItems: 32,
    }),
  ),
  timeoutSeconds: Type.Optional(
    Type.Integer({
      description: `Hard timeout in seconds (default ${DEFAULT_TIMEOUT_SECONDS}, maximum ${MAX_TIMEOUT_SECONDS})`,
      minimum: 1,
      maximum: MAX_TIMEOUT_SECONDS,
    }),
  ),
});

type DisplayItem =
  | { type: "text"; text: string }
  | { type: "toolCall"; name: string; args: Record<string, unknown> };

interface TaskDetails {
  status: "running" | "completed" | "failed";
  description: string;
  prompt: string;
  cwd: string;
  model?: string;
  thinking?: string;
  tools: string[];
  timeoutSeconds: number;
  durationMs?: number;
  turns?: number;
  toolCalls?: string[];
  displayItems?: DisplayItem[];
  finalOutput?: string;
  childSessionId?: string;
  fullOutputPath?: string;
  error?: string;
  toolCallId?: string;
}

interface LiveTask {
  id: string;
  toolCallId: string;
  description: string;
  prompt: string;
  cwd: string;
  model?: string;
  thinking?: string;
  status: "running" | "completed" | "failed";
  startedAt: number;
  finishedAt?: number;
  turns: number;
  toolCalls: string[];
  displayItems: DisplayItem[];
  finalOutput: string;
  childSessionId?: string;
  error?: string;
  controller: AbortController;
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function getPiInvocation(): { command: string; args: string[] } {
  const currentScript = process.argv[1];
  const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
  if (currentScript && !isBunVirtualScript && existsSync(currentScript)) {
    return { command: process.execPath, args: [currentScript] };
  }

  const executable = basename(process.execPath).toLowerCase();
  if (!/^(node|bun)(\.exe)?$/.test(executable)) {
    return { command: process.execPath, args: [] };
  }
  return { command: "pi", args: [] };
}

async function resolveTaskCwd(parentCwd: string, requested?: string): Promise<string> {
  let value = requested?.startsWith("@") ? requested.slice(1) : requested;
  if (!value) value = parentCwd;
  if (value === "~") value = homedir();
  else if (value.startsWith("~/")) value = join(homedir(), value.slice(2));

  const absolute = resolve(parentCwd, value);
  const info = await stat(absolute);
  if (!info.isDirectory()) throw new Error(`Task cwd is not a directory: ${absolute}`);
  return realpath(absolute);
}

function messageText(message: any): string {
  if (!Array.isArray(message?.content)) return "";
  return message.content
    .filter((part: any) => part?.type === "text" && typeof part.text === "string")
    .map((part: any) => part.text)
    .join("\n")
    .trim();
}

function childEnvironment(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    [TASK_CHILD_ENV]: "1",
    PI_OFFLINE: "1",
    PI_SKIP_VERSION_CHECK: "1",
  };
  for (const key of [
    "PI_SESSION_ID",
    "PI_SESSION_FILE",
    "PI_PROVIDER",
    "PI_MODEL",
    "PI_REASONING_LEVEL",
    "HERDR_ENV",
    "HERDR_PANE_ID",
    "HERDR_SOCKET_PATH",
  ]) {
    delete env[key];
  }
  return env;
}

function formatToolCall(
  toolName: string,
  args: Record<string, unknown>,
  themeFg: (color: any, text: string) => string,
): string {
  const shortenPath = (p: string) => {
    const home = homedir();
    return p.startsWith(home) ? `~${p.slice(home.length)}` : p;
  };

  switch (toolName) {
    case "bash": {
      const command = (args.command as string) || "...";
      const preview = command.length > 60 ? `${command.slice(0, 60)}...` : command;
      return themeFg("muted", "$ ") + themeFg("toolOutput", preview);
    }
    case "read": {
      const rawPath = (args.file_path || args.path || "...") as string;
      const filePath = shortenPath(rawPath);
      const offset = args.offset as number | undefined;
      const limit = args.limit as number | undefined;
      let text = themeFg("accent", filePath);
      if (offset !== undefined || limit !== undefined) {
        const startLine = offset ?? 1;
        const endLine = limit !== undefined ? startLine + limit - 1 : "";
        text += themeFg("warning", `:${startLine}${endLine ? `-${endLine}` : ""}`);
      }
      return themeFg("muted", "read ") + text;
    }
    case "write": {
      const rawPath = (args.file_path || args.path || "...") as string;
      return themeFg("muted", "write ") + themeFg("accent", shortenPath(rawPath));
    }
    case "edit": {
      const rawPath = (args.file_path || args.path || "...") as string;
      return themeFg("muted", "edit ") + themeFg("accent", shortenPath(rawPath));
    }
    case "grep": {
      const pattern = String(args.pattern ?? "...");
      const path = args.path ? shortenPath(String(args.path)) : ".";
      return (
        themeFg("muted", "grep ") +
        themeFg("accent", `/${pattern}/`) +
        themeFg("dim", ` in ${path}`)
      );
    }
    case "find": {
      const pattern = String(args.pattern ?? "*");
      const path = args.path ? shortenPath(String(args.path)) : ".";
      return (
        themeFg("muted", "find ") +
        themeFg("accent", pattern) +
        themeFg("dim", ` in ${path}`)
      );
    }
    case "ls": {
      const path = args.path ? shortenPath(String(args.path)) : ".";
      return themeFg("muted", "ls ") + themeFg("accent", path);
    }
    default: {
      const keys = Object.keys(args ?? {}).slice(0, 3);
      const summary =
        keys.length > 0
          ? keys
              .map((k) => {
                let value: string;
                try {
                  value = JSON.stringify(args[k]) ?? "";
                } catch {
                  value = String(args[k]);
                }
                return `${k}=${value.slice(0, 28)}`;
              })
              .join(" ")
          : "";
      return (
        themeFg("muted", `${toolName} `) +
        themeFg("dim", summary.length > 60 ? `${summary.slice(0, 60)}...` : summary)
      );
    }
  }
}

function pushDisplayItem(items: DisplayItem[], item: DisplayItem): void {
  if (item.type === "text") {
    const text =
      item.text.length > MAX_TEXT_PREVIEW
        ? `${item.text.slice(0, MAX_TEXT_PREVIEW)}\n…`
        : item.text;
    const last = items[items.length - 1];
    if (last?.type === "text") {
      last.text = text;
      return;
    }
    items.push({ type: "text", text });
  } else {
    items.push(item);
  }
  if (items.length > MAX_DISPLAY_ITEMS) {
    items.splice(0, items.length - MAX_DISPLAY_ITEMS);
  }
}

function statusIcon(
  status: TaskDetails["status"] | LiveTask["status"],
  theme: { fg: (c: any, t: string) => string },
): string {
  if (status === "running") return theme.fg("warning", "⏳");
  if (status === "failed") return theme.fg("error", "✗");
  return theme.fg("success", "✓");
}

function formatDuration(ms?: number): string {
  if (ms === undefined) return "";
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  const minutes = Math.floor(ms / 60_000);
  const seconds = Math.round((ms % 60_000) / 1000);
  return `${minutes}m${seconds}s`;
}

function shorten(text: string, max: number): string {
  const oneLine = text.replace(/\s+/g, " ").trim();
  return oneLine.length > max ? `${oneLine.slice(0, max - 1)}…` : oneLine;
}

/** Every custom TUI line must be <= terminal width or Pi hard-crashes. */
function safeLines(lines: Array<string | false | null | undefined>, width: number): string[] {
  const maxWidth = Math.max(1, width);
  const out: string[] = [];
  for (const line of lines) {
    if (!line) continue;
    // wrapTextWithAnsi preserves ANSI and keeps each line <= width.
    for (const wrapped of wrapTextWithAnsi(line, maxWidth)) {
      // Defensive: still clamp in case a theme/emoji edge case slips through.
      out.push(
        visibleWidth(wrapped) > maxWidth ? truncateToWidth(wrapped, maxWidth, "…") : wrapped,
      );
    }
  }
  return out;
}

function ruleLine(theme: { fg: (c: any, t: string) => string }, width: number): string {
  const w = Math.max(8, Math.min(Math.max(1, width), 80));
  return theme.fg("muted", "─".repeat(w));
}

function pruneLiveTasks(liveTasks: Map<string, LiveTask>): void {
  if (liveTasks.size <= MAX_RETAINED_TASKS) return;
  const finished = [...liveTasks.values()]
    .filter((t) => t.status !== "running")
    .sort((a, b) => (a.finishedAt ?? 0) - (b.finishedAt ?? 0));
  while (liveTasks.size > MAX_RETAINED_TASKS && finished.length > 0) {
    const oldest = finished.shift();
    if (oldest) liveTasks.delete(oldest.id);
  }
}

async function openTaskViewer(
  ctx: ExtensionContext,
  liveTasks: Map<string, LiveTask>,
  preferredId?: string,
): Promise<void> {
  if (ctx.mode !== "tui" || !ctx.ui?.custom) {
    ctx.ui?.notify?.("Task viewer requires interactive TUI mode", "warning");
    return;
  }

  const snapshot = [...liveTasks.values()].sort((a, b) => b.startedAt - a.startedAt);
  if (snapshot.length === 0) {
    ctx.ui.notify("No task subagents in this session yet", "info");
    return;
  }

  let selectedId =
    (preferredId && liveTasks.has(preferredId) && preferredId) ||
    snapshot.find((t) => t.status === "running")?.id ||
    snapshot[0].id;

  if (snapshot.length > 1 && !(preferredId && liveTasks.has(preferredId))) {
    const options = snapshot.map((t) => {
      const mark = t.status === "running" ? "running" : t.status === "failed" ? "failed" : "done";
      return `${t.id} [${mark}] ${t.description}`;
    });
    const pick = await ctx.ui.select("Inspect task subagent", options);
    if (!pick) return;
    selectedId = pick.split(" ")[0] ?? selectedId;
  }

  await ctx.ui.custom<void>((tui, theme, _keybindings, done) => {
    let closed = false;
    let timer: ReturnType<typeof setInterval> | undefined;
    let scroll = 0;

    const close = () => {
      if (closed) return;
      closed = true;
      if (timer) clearInterval(timer);
      done();
    };

    const component = {
      invalidate() {},
      dispose() {
        if (timer) clearInterval(timer);
      },
      render(width: number): string[] {
        const live = liveTasks.get(selectedId) ?? snapshot.find((t) => t.id === selectedId);
        if (!live) return safeLines([theme.fg("muted", "Task no longer available")], width);

        const icon = statusIcon(live.status, theme);
        const duration = formatDuration((live.finishedAt ?? Date.now()) - live.startedAt);
        const termRows = tui.terminal?.rows ?? 24;
        const rule = ruleLine(theme, width);

        // Build logical sections first, then wrap every line to `width`.
        const headerRaw: string[] = [
          `${icon} ${theme.fg("toolTitle", theme.bold(live.description))} ${theme.fg("muted", `[${live.status}]`)} ${theme.fg("dim", duration)}`,
          theme.fg("dim", `cwd ${live.cwd}`),
        ];
        if (live.model) {
          headerRaw.push(
            theme.fg(
              "dim",
              `model ${live.model}${live.thinking ? ` · thinking ${live.thinking}` : ""}`,
            ),
          );
        }
        if (live.childSessionId) {
          headerRaw.push(theme.fg("dim", `session ${live.childSessionId}`));
        }
        headerRaw.push(rule, theme.fg("muted", "Task"), theme.fg("dim", live.prompt), rule, theme.fg("muted", "Live transcript"));

        const bodyRaw: string[] = [];
        for (const item of live.displayItems) {
          if (item.type === "toolCall") {
            bodyRaw.push(
              theme.fg("muted", "→ ") + formatToolCall(item.name, item.args, theme.fg.bind(theme)),
            );
          } else {
            for (const line of item.text.split("\n")) {
              bodyRaw.push(theme.fg("toolOutput", line));
            }
          }
        }
        if (live.finalOutput) {
          bodyRaw.push(rule, theme.fg("muted", "Final output"));
          for (const line of live.finalOutput.split("\n")) {
            bodyRaw.push(theme.fg("toolOutput", line));
          }
        }
        if (live.error) {
          bodyRaw.push(theme.fg("error", `Error: ${live.error}`));
        }
        if (bodyRaw.length === 0) {
          bodyRaw.push(
            theme.fg(
              "muted",
              live.status === "running" ? "(waiting for first output…)" : "(no output)",
            ),
          );
        }

        const footerRaw: string[] = [
          rule,
          theme.fg(
            "dim",
            `turns ${live.turns} · tools ${live.toolCalls.length} · j/k scroll · g/G top/end · esc/q close · ${keyHint("app.tools.expand", "expands tool rows")}`,
          ),
        ];

        // Wrap first so scroll math is in terminal rows, not raw source lines.
        const header = safeLines(headerRaw, width);
        const body = safeLines(bodyRaw, width);
        const footerBase = safeLines(footerRaw, width);

        const maxBody = Math.max(4, termRows - header.length - footerBase.length - 2);
        if (scroll > Math.max(0, body.length - maxBody)) {
          scroll = Math.max(0, body.length - maxBody);
        }
        const visibleBody = body.slice(scroll, scroll + maxBody);
        const footer =
          body.length > maxBody
            ? safeLines(
                [
                  theme.fg(
                    "muted",
                    `… showing ${scroll + 1}-${scroll + visibleBody.length} of ${body.length} lines`,
                  ),
                  ...footerRaw,
                ],
                width,
              )
            : footerBase;

        return safeLines([...header, ...visibleBody, ...footer], width);
      },
      handleInput(data: string) {
        const s = data.toString();
        if (s === "\u001b" || s === "q" || s === "Q") {
          close();
          return;
        }
        if (s === "j" || s === "\u001b[B") {
          scroll += 1;
          tui.requestRender();
          return;
        }
        if (s === "k" || s === "\u001b[A") {
          scroll = Math.max(0, scroll - 1);
          tui.requestRender();
          return;
        }
        if (s === "g") {
          scroll = 0;
          tui.requestRender();
          return;
        }
        if (s === "G") {
          scroll = 10_000;
          tui.requestRender();
        }
      },
    };

    timer = setInterval(() => {
      tui.requestRender();
    }, 200);

    return component;
  });
}

export default function taskExtension(pi: ExtensionAPI) {
  // A delegated child loads the user's normal extensions, but cannot recursively delegate.
  if (process.env[TASK_CHILD_ENV] === "1") return;

  const operations = createLocalBashOperations();
  const activeControllers = new Set<AbortController>();
  const liveTasks = new Map<string, LiveTask>();
  let taskSeq = 0;

  pi.on("session_shutdown", () => {
    for (const controller of activeControllers) controller.abort();
  });

  pi.registerCommand("tasks", {
    description: "Inspect live/completed task subagents (transcript viewer)",
    handler: async (args, ctx) => {
      const preferred = args.trim() || undefined;
      await openTaskViewer(ctx, liveTasks, preferred);
    },
  });

  pi.registerShortcut("ctrl+shift+t", {
    description: "Open task subagent viewer",
    handler: async (ctx) => {
      await openTaskViewer(ctx, liveTasks);
    },
  });

  pi.registerTool({
    name: "task",
    label: "Task",
    description:
      "Delegate one bounded task to an isolated Pi subagent and wait for its result. Calls may run in parallel with no hard concurrency cap (override with PI_TASK_MAX_CONCURRENCY). Each child is ephemeral, cannot delegate recursively, inherits the parent's active tools by default, and is killed with its process tree on abort or timeout. User can inspect live transcripts with Ctrl+O on the tool row, /tasks, or Ctrl+Shift+T.",
    promptSnippet: "Delegate a self-contained task to an isolated, foreground Pi subagent",
    promptGuidelines: [
      "Use task when independent work benefits from parallel execution or an isolated context window.",
      "For independent work, call task multiple times in one response so Pi runs them concurrently. There is no fixed 4-call cap unless PI_TASK_MAX_CONCURRENCY is set.",
      "Never emulate task by launching Pi through bash, tmux, Herdr, nohup, or background shell processes.",
    ],
    parameters: taskSchema,

    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const runningCount = [...liveTasks.values()].filter((t) => t.status === "running").length;
      if (Number.isFinite(MAX_CONCURRENCY) && runningCount >= MAX_CONCURRENCY) {
        throw new Error(
          `At most ${MAX_CONCURRENCY} task subagents may run concurrently (PI_TASK_MAX_CONCURRENCY).`,
        );
      }

      const controller = new AbortController();
      activeControllers.add(controller);
      const relayAbort = () => controller.abort();
      if (signal?.aborted) relayAbort();
      else signal?.addEventListener("abort", relayAbort, { once: true });

      const startedAt = Date.now();
      let tempDirectory: string | undefined;
      const id = `task-${++taskSeq}-${toolCallId.slice(-8)}`;

      try {
        const cwd = await resolveTaskCwd(ctx.cwd, params.cwd);
        const description =
          params.description?.trim() ||
          params.prompt.trim().split("\n", 1)[0].slice(0, 120) ||
          "delegated task";
        const timeoutSeconds = params.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS;
        const model =
          params.model ?? (ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined);
        const thinking = params.thinking ?? ctx.thinkingLevel;
        const requestedTools: string[] = params.tools ?? pi.getActiveTools();
        const tools = [...new Set(requestedTools.filter((name) => name !== "task"))];

        const live: LiveTask = {
          id,
          toolCallId,
          description,
          prompt: params.prompt,
          cwd,
          model,
          thinking,
          status: "running",
          startedAt,
          turns: 0,
          toolCalls: [],
          displayItems: [],
          finalOutput: "",
          controller,
        };
        liveTasks.set(id, live);

        const emitProgress = (extra?: Partial<TaskDetails>) => {
          const details: TaskDetails = {
            status: live.status,
            description,
            prompt: params.prompt,
            cwd,
            model,
            thinking,
            tools,
            timeoutSeconds,
            durationMs: Date.now() - startedAt,
            turns: live.turns,
            toolCalls: [...live.toolCalls],
            displayItems: [...live.displayItems],
            finalOutput: live.finalOutput,
            childSessionId: live.childSessionId,
            error: live.error,
            toolCallId,
            ...extra,
          };
          const recent = live.toolCalls.slice(-5);
          const preview =
            live.finalOutput ||
            (recent.length > 0
              ? `Running: ${description}\nRecent tools: ${recent.join(", ")}`
              : `Running subagent: ${description}`);
          onUpdate?.({
            content: [{ type: "text", text: preview }],
            details,
          });
        };

        emitProgress();

        tempDirectory = await mkdtemp(join(tmpdir(), "pi-task-"));
        const stderrPath = join(tempDirectory, "stderr.log");
        const invocation = getPiInvocation();
        const args = [
          ...invocation.args,
          "--mode",
          "json",
          "--no-session",
          "--offline",
          "--exclude-tools",
          "task",
        ];
        if (model) args.push("--model", model);
        if (thinking) args.push("--thinking", thinking);
        if (tools.length > 0) args.push("--tools", tools.join(","));
        else args.push("--no-tools");
        args.push(
          "--append-system-prompt",
          CHILD_SYSTEM_PROMPT,
          `Task delegated by the parent agent:\n\n${params.prompt}`,
        );

        const command =
          [invocation.command, ...args].map(shellQuote).join(" ") + ` 2>${shellQuote(stderrPath)}`;

        let streamBuffer = "";
        let stopReason: string | undefined;
        let errorMessage: string | undefined;
        const diagnostics: string[] = [];

        const processLine = (line: string) => {
          if (!line.trim()) return;
          let event: any;
          try {
            event = JSON.parse(line);
          } catch {
            diagnostics.push(line);
            return;
          }

          if (event.type === "session" && typeof event.id === "string") {
            live.childSessionId = event.id;
            emitProgress();
            return;
          }

          if (event.type === "tool_execution_start") {
            const name = String(event.toolName ?? "unknown");
            const toolArgs =
              event.args && typeof event.args === "object"
                ? (event.args as Record<string, unknown>)
                : {};
            live.toolCalls.push(name);
            pushDisplayItem(live.displayItems, {
              type: "toolCall",
              name,
              args: toolArgs,
            });
            emitProgress();
            return;
          }

          if (event.type === "message_update" && event.message?.role === "assistant") {
            const text = messageText(event.message);
            if (text) {
              pushDisplayItem(live.displayItems, { type: "text", text });
              emitProgress();
            }
            return;
          }

          if (event.type === "message_end" && event.message) {
            if (event.message.role === "assistant") {
              live.turns += 1;
              const text = messageText(event.message);
              if (text) {
                live.finalOutput = text;
                pushDisplayItem(live.displayItems, { type: "text", text });
              }
              stopReason = event.message.stopReason;
              errorMessage = event.message.errorMessage;
              emitProgress();
            }
            return;
          }

          if (event.type === "tool_execution_end" && event.isError) {
            pushDisplayItem(live.displayItems, {
              type: "text",
              text: `tool error: ${String(event.toolName ?? "unknown")}`,
            });
            emitProgress();
          }
        };

        let executionError: unknown;
        let exitCode: number | null = null;
        try {
          const result = await operations.exec(command, cwd, {
            onData(data) {
              streamBuffer += data.toString();
              const lines = streamBuffer.split("\n");
              streamBuffer = lines.pop() ?? "";
              for (const line of lines) processLine(line);
            },
            signal: controller.signal,
            timeout: timeoutSeconds,
            env: childEnvironment(),
          });
          exitCode = result.exitCode;
        } catch (error) {
          executionError = error;
        }
        if (streamBuffer.trim()) processLine(streamBuffer);

        const stderr = await readFile(stderrPath, "utf8").catch(() => "");
        const diagnostic = [stderr.trim(), diagnostics.join("\n").trim()]
          .filter(Boolean)
          .join("\n")
          .slice(-8000);

        if (executionError) {
          const raw =
            executionError instanceof Error ? executionError.message : String(executionError);
          if (signal?.aborted || controller.signal.aborted) {
            live.status = "failed";
            live.error = "aborted";
            live.finishedAt = Date.now();
            pruneLiveTasks(liveTasks);
            throw new Error("Subagent task was aborted; its process tree was terminated.");
          }
          if (raw.startsWith("timeout:")) {
            live.status = "failed";
            live.error = `timeout after ${timeoutSeconds}s`;
            live.finishedAt = Date.now();
            pruneLiveTasks(liveTasks);
            throw new Error(
              `Subagent exceeded its ${timeoutSeconds}s hard timeout; its process tree was terminated.${diagnostic ? `\n${diagnostic}` : ""}`,
            );
          }
          live.status = "failed";
          live.error = raw;
          live.finishedAt = Date.now();
          pruneLiveTasks(liveTasks);
          throw new Error(
            `Subagent execution failed: ${raw}${diagnostic ? `\n${diagnostic}` : ""}`,
          );
        }
        if (exitCode !== 0) {
          live.status = "failed";
          live.error = `exit ${exitCode}`;
          live.finishedAt = Date.now();
          pruneLiveTasks(liveTasks);
          throw new Error(
            `Subagent exited with code ${exitCode}.${diagnostic ? `\n${diagnostic}` : ""}`,
          );
        }
        if (stopReason === "error" || stopReason === "aborted") {
          live.status = "failed";
          live.error = errorMessage || stopReason;
          live.finishedAt = Date.now();
          pruneLiveTasks(liveTasks);
          throw new Error(errorMessage || diagnostic || `Subagent stopped: ${stopReason}`);
        }

        const output = live.finalOutput || "(subagent completed without a text response)";
        const truncation = truncateHead(output, {
          maxBytes: DEFAULT_MAX_BYTES,
          maxLines: DEFAULT_MAX_LINES,
        });
        let resultText = truncation.content;
        let fullOutputPath: string | undefined;
        if (truncation.truncated) {
          const outputDirectory = await mkdtemp(join(tmpdir(), "pi-task-output-"));
          fullOutputPath = join(outputDirectory, "result.md");
          await writeFile(fullOutputPath, output, "utf8");
          resultText += `\n\n[Output truncated to ${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)}. Full output: ${fullOutputPath}]`;
        }

        live.status = "completed";
        live.finishedAt = Date.now();
        live.finalOutput = output;
        pruneLiveTasks(liveTasks);

        const details: TaskDetails = {
          status: "completed",
          description,
          prompt: params.prompt,
          cwd,
          model,
          thinking,
          tools,
          timeoutSeconds,
          durationMs: Date.now() - startedAt,
          turns: live.turns,
          toolCalls: [...live.toolCalls],
          displayItems: [...live.displayItems],
          finalOutput: output,
          childSessionId: live.childSessionId,
          fullOutputPath,
          toolCallId,
        };
        return { content: [{ type: "text", text: resultText }], details };
      } finally {
        signal?.removeEventListener("abort", relayAbort);
        activeControllers.delete(controller);
        if (tempDirectory)
          await rm(tempDirectory, { recursive: true, force: true }).catch(() => undefined);
      }
    },

    renderCall(args, theme) {
      const description =
        args.description?.trim() ||
        (args.prompt ? shorten(String(args.prompt), 80) : "delegated task");
      let text =
        theme.fg("toolTitle", theme.bold("task ")) + theme.fg("accent", description);
      if (args.model) text += theme.fg("muted", ` · ${args.model}`);
      if (args.cwd) text += `\n  ${theme.fg("dim", `cwd ${args.cwd}`)}`;
      return new Text(text, 0, 0);
    },

    renderResult(result, { expanded, isPartial }, theme) {
      const details = result.details as TaskDetails | undefined;
      const textPart = result.content?.[0];
      const fallback =
        textPart && textPart.type === "text" ? textPart.text : "(no output)";

      if (!details) {
        return new Text(fallback, 0, 0);
      }

      const icon = statusIcon(details.status, theme);
      const duration = formatDuration(details.durationMs);
      const metaParts = [
        details.status,
        duration,
        details.turns ? `${details.turns} turn${details.turns === 1 ? "" : "s"}` : undefined,
        details.toolCalls?.length ? `${details.toolCalls.length} tools` : undefined,
        details.model,
      ].filter(Boolean);

      if (expanded) {
        const container = new Container();
        container.addChild(
          new Text(
            `${icon} ${theme.fg("toolTitle", theme.bold(details.description))} ${theme.fg("muted", metaParts.join(" · "))}`,
            0,
            0,
          ),
        );
        container.addChild(new Text(theme.fg("dim", `cwd ${details.cwd}`), 0, 0));
        if (details.childSessionId) {
          container.addChild(
            new Text(theme.fg("dim", `session ${details.childSessionId}`), 0, 0),
          );
        }
        container.addChild(new Spacer(1));
        container.addChild(new Text(theme.fg("muted", "─── Task ───"), 0, 0));
        container.addChild(new Text(theme.fg("dim", details.prompt), 0, 0));
        container.addChild(new Spacer(1));
        container.addChild(new Text(theme.fg("muted", "─── Transcript ───"), 0, 0));

        const items = details.displayItems ?? [];
        if (items.length === 0) {
          container.addChild(
            new Text(
              theme.fg(
                "muted",
                isPartial || details.status === "running"
                  ? "(waiting for first output…)"
                  : "(no tool activity)",
              ),
              0,
              0,
            ),
          );
        } else {
          for (const item of items) {
            if (item.type === "toolCall") {
              container.addChild(
                new Text(
                  theme.fg("muted", "→ ") +
                    formatToolCall(item.name, item.args, theme.fg.bind(theme)),
                  0,
                  0,
                ),
              );
            } else {
              container.addChild(new Text(theme.fg("toolOutput", item.text), 0, 0));
            }
          }
        }

        if (details.finalOutput) {
          container.addChild(new Spacer(1));
          container.addChild(new Text(theme.fg("muted", "─── Final output ───"), 0, 0));
          try {
            container.addChild(new Markdown(details.finalOutput.trim(), 0, 0, getMarkdownTheme()));
          } catch {
            container.addChild(new Text(details.finalOutput.trim(), 0, 0));
          }
        }

        if (details.error) {
          container.addChild(new Spacer(1));
          container.addChild(new Text(theme.fg("error", `Error: ${details.error}`), 0, 0));
        }

        if (details.fullOutputPath) {
          container.addChild(
            new Text(theme.fg("dim", `Full output: ${details.fullOutputPath}`), 0, 0),
          );
        }

        container.addChild(new Spacer(1));
        container.addChild(
          new Text(
            theme.fg(
              "dim",
              `Inspect: /tasks · ${keyHint("app.tools.expand", "collapse")} · Ctrl+Shift+T`,
            ),
            0,
            0,
          ),
        );
        return container;
      }

      // Collapsed / streaming view
      let text = `${icon} ${theme.fg("toolTitle", theme.bold(details.description))}`;
      text += theme.fg("muted", ` ${metaParts.join(" · ")}`);

      const items = details.displayItems ?? [];
      if (items.length === 0) {
        text += `\n${theme.fg("muted", details.status === "running" ? "(starting…)" : "(no output)")}`;
      } else {
        const toShow = items.slice(-COLLAPSED_ITEM_COUNT);
        const skipped = items.length - toShow.length;
        if (skipped > 0) text += `\n${theme.fg("muted", `… ${skipped} earlier items`)}`;
        for (const item of toShow) {
          if (item.type === "toolCall") {
            text += `\n${theme.fg("muted", "→ ")}${formatToolCall(item.name, item.args, theme.fg.bind(theme))}`;
          } else {
            const preview = item.text.split("\n").slice(0, 3).join("\n");
            text += `\n${theme.fg("toolOutput", preview)}`;
          }
        }
      }

      if (details.error) {
        text += `\n${theme.fg("error", details.error)}`;
      } else if (details.status === "completed" && details.finalOutput && items.length === 0) {
        text += `\n${theme.fg("toolOutput", shorten(details.finalOutput, 200))}`;
      }

      text += `\n${theme.fg("muted", `(${keyHint("app.tools.expand", "expand")} · /tasks · Ctrl+Shift+T)`)}`;
      return new Text(text, 0, 0);
    },
  });
}
