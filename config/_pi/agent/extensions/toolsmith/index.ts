// toolsmith for pi: stop agents from writing throwaway helper scripts.
//
// Instead of a heredoc or a long `python3 -c`, the agent searches a shared
// catalog of CLI tools (toolsmith_search) or asks a toolsmith subagent to
// build, verify and catalog a reusable one (toolsmith). A bash/write hook
// nudges the agent once when it starts writing a helper script anyway.
//
// Adapted from Jesse Vincent's toolsmith plugin (MIT),
// https://github.com/prime-radiant-inc/toolsmith @ 7e45f7f. bin/toolsmith-repo
// is vendored unchanged; instructions/ are the plugin's agent prompt and
// references rewritten for pi. See README.md.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { bashScriptSmell, codemodeScriptSmell, writeScriptSmell } from "./smells.ts";

const EXT_DIR = path.dirname(fileURLToPath(import.meta.url));
const BIN_DIR = path.join(EXT_DIR, "bin");
const REPO_TOOL = path.join(BIN_DIR, "toolsmith-repo");
const INSTRUCTIONS = path.join(EXT_DIR, "instructions");
const AGENT_PROMPT = path.join(INSTRUCTIONS, "toolsmith-agent.md");
const STANDARDS = path.join(INSTRUCTIONS, "authoring-standards.md");
const REPLY_FORMAT = path.join(INSTRUCTIONS, "reply-format.md");

const SUBAGENT_TIMEOUT_MS = 20 * 60 * 1000;

// ---------- small helpers ----------

type Usage = {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	totalTokens: number;
	cost: { input: number; output: number; cacheRead: number; cacheWrite: number; total: number };
};

function emptyUsage(): Usage {
	return {
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: 0,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
}

function addUsage(total: Usage, u: Partial<Usage> | undefined) {
	if (!u) return;
	total.input += u.input ?? 0;
	total.output += u.output ?? 0;
	total.cacheRead += u.cacheRead ?? 0;
	total.cacheWrite += u.cacheWrite ?? 0;
	total.totalTokens += u.totalTokens ?? 0;
	for (const k of ["input", "output", "cacheRead", "cacheWrite", "total"] as const) {
		total.cost[k] += u.cost?.[k] ?? 0;
	}
}

function text(t: string) {
	return [{ type: "text" as const, text: t }];
}

function firstLine(s: string, max = 100): string {
	const line = (s.split("\n")[0] ?? "").trim();
	return line.length > max ? `${line.slice(0, max - 1)}…` : line;
}

// The pi binary to spawn for the subagent (same logic as pi's subagent example).
function piInvocation(args: string[]): { command: string; args: string[] } {
	const script = process.argv[1];
	const virtual = script?.startsWith("/$bunfs/root/") ?? false;
	if (script && !virtual && fs.existsSync(script)) return { command: process.execPath, args: [script, ...args] };
	const exe = path.basename(process.execPath).toLowerCase();
	if (!/^(node|bun)(\.exe)?$/.test(exe)) return { command: process.execPath, args };
	return { command: "pi", args };
}

// toolsmith-repo prints key=value lines; keys like note= can repeat.
function parseKV(out: string): Record<string, string[]> {
	const kv: Record<string, string[]> = {};
	for (const line of out.split("\n")) {
		const i = line.indexOf("=");
		if (i <= 0) continue;
		(kv[line.slice(0, i)] ??= []).push(line.slice(i + 1));
	}
	return kv;
}

// ---------- catalogs ----------

async function locateCatalogs(pi: ExtensionAPI, cwd: string): Promise<string[]> {
	const r = await pi.exec("bash", [REPO_TOOL, "locate", "--project", cwd], { cwd, timeout: 10_000 });
	// Exit 8: cwd is not in a git repo; the global paths are still printed.
	if (r.code !== 0 && r.code !== 8) throw new Error(`toolsmith-repo locate failed (exit ${r.code}): ${r.stderr.trim()}`);
	const kv = parseKV(r.stdout);
	return [...(kv.global_catalog ?? []), ...(kv.project_catalog ?? [])];
}

function readCatalogLines(catalogs: string[]): string[] {
	const lines: string[] = [];
	for (const c of catalogs) {
		let body: string;
		try {
			body = fs.readFileSync(c, "utf8");
		} catch {
			continue; // A catalog that doesn't exist yet means no tools yet.
		}
		for (const l of body.split("\n")) if (l.startsWith("- ")) lines.push(l);
	}
	return lines;
}

function searchCatalog(lines: string[], query: string): string[] {
	const words = query
		.toLowerCase()
		.split(/[^a-z0-9]+/)
		.filter((w) => w.length > 1);
	if (words.length === 0) return lines;
	return lines
		.map((l) => {
			const hay = l.toLowerCase();
			return { l, score: words.filter((w) => hay.includes(w)).length };
		})
		.filter((x) => x.score > 0)
		.sort((a, b) => b.score - a.score)
		.map((x) => x.l);
}

// ---------- helper-script detection for the nudge ----------

// Detectors live in smells.ts (pure, testable with plain node).

const NUDGE = (why: string, codemode = false) =>
	[
		`toolsmith: held this call once. It looks like a throwaway helper script (it ${why}).`,
		...(codemode
			? [
					"codemode is for orchestrating tool calls. Parsing files, transforming or merging records, and generating edits in JavaScript is a helper script like any other. Rewriting it next time costs as much as it did this time.",
				]
			: []),
		"Instead of writing a one-off script:",
		"1. Call toolsmith_search with a few words for the job; if a listed tool fits, run it by its absolute path (check --help first).",
		"2. Otherwise call toolsmith with a brief. It builds, verifies and catalogs a reusable CLI tool and replies with the command to run.",
		"If this is mission work (code that ships with the project), a throwaway of at most five lines, or the user explicitly asked you to write a script, re-run the identical call and it will go through.",
	].join("\n");

// ---------- the subagent ----------

type SubagentDetails = {
	status: "running" | "done" | "failed" | "aborted";
	steps: string[];
	model?: string;
	usage: Usage;
	exitCode?: number | null;
	stderr?: string;
};

function buildBrief(p: { task: string; io: string; example?: string; closest?: string; context?: string }, cwd: string) {
	return [
		`Task: ${p.task.trim()}`,
		`Inputs and outputs: ${p.io.trim()}`,
		`Example invocation: ${p.example?.trim() || "(none given)"}`,
		`Closest catalog tool: ${p.closest?.trim() || "none"}`,
		p.context?.trim() ? `Context: ${p.context.trim()}` : "",
		`Caller's working directory: ${cwd}`,
	]
		.filter(Boolean)
		.join("\n");
}

function describeStep(toolName: string, args: any): string {
	if (toolName === "bash") return `$ ${firstLine(String(args?.command ?? ""), 90)}`;
	if (args?.path) return `${toolName} ${args.path}`;
	return toolName;
}

// ---------- extension ----------

export default function toolsmith(pi: ExtensionAPI) {
	// Make sure the vendored repo tool is executable even if a copy dropped the bit.
	try {
		fs.chmodSync(REPO_TOOL, 0o755);
	} catch {
		/* read-only install: we always call it through bash anyway */
	}

	let nudgeEnabled = process.env.TOOLSMITH_NUDGE !== "off";
	const heldOnce = new Set<string>();

	pi.on("session_start", async () => {
		heldOnce.clear();
	});

	pi.registerTool({
		name: "toolsmith_search",
		label: "Toolsmith search",
		description:
			"Search the shared catalog of reusable command-line tools (global, plus the current git project's) by keywords. Returns matching catalog lines: '- <absolute path> -- <purpose>'. An empty query lists every tool.",
		promptSnippet: "Search the shared catalog of reusable CLI helper tools",
		parameters: Type.Object({
			query: Type.String({ description: "A few words for the job, e.g. 'pdf images combine'. Empty lists all." }),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const catalogs = await locateCatalogs(pi, ctx.cwd);
			const all = readCatalogLines(catalogs);
			if (all.length === 0) {
				return {
					content: text("No tools in the catalog yet. Call toolsmith with a brief to build one."),
					details: { matches: 0, total: 0 },
				};
			}
			const hits = searchCatalog(all, params.query);
			const shown = hits.slice(0, 25);
			const body = shown.length
				? `${shown.join("\n")}${hits.length > shown.length ? `\n(${hits.length - shown.length} more; refine the query)` : ""}`
				: `No tool matches "${params.query}" among ${all.length} tools. Call toolsmith with a brief to build one.`;
			return { content: text(body), details: { matches: hits.length, total: all.length } };
		},
	});

	pi.registerTool({
		name: "toolsmith",
		label: "Toolsmith",
		description:
			"Delegate a helper script to the toolsmith subagent instead of writing it yourself. It reuses, extends or writes a parameterized CLI tool in the shared tools repo (~/.local/share/toolsmith/tools), verifies it against your example, catalogs it, and replies with a block: tool:, catalog:, usage:, status:, mutates:, verified:, assumed:, note:. Takes a few minutes. Not for mission work (code that ships with the project).",
		promptSnippet: "Have a subagent build (or find) a reusable, cataloged CLI tool instead of writing a one-off script",
		promptGuidelines: [
			"Before writing a helper script that isn't part of the project's deliverable (a saved script, or a multi-line heredoc, python3 -c or node -e for data conversion, image/PDF manipulation, log trawling, API calls, fixtures, one-off data fixes), call toolsmith_search with a few words for the job and use a fitting tool by its absolute path.",
			"If no catalog tool fits, call toolsmith with a brief instead of writing the script yourself, then run the tool path it returns. If its reply says mutates: yes, run the tool with --dry-run first.",
			"After using a toolsmith tool, tell the user in one line which tool you used or got built, quoting its catalog: line.",
			"codemode scripts count too: use codemode to orchestrate tool calls (batch, chain, trim output), but parsing files, transforming or merging records, or generating edits programmatically in a codemode script is a helper script. Search the catalog or call toolsmith for that logic.",
			"Write code yourself instead of calling toolsmith only for mission work (code that ships with the project), single command lines, throwaway inspection snippets of at most five lines, or when the user explicitly asks for a script.",
		],
		parameters: Type.Object({
			task: Type.String({ description: "What the tool must do, in one or two sentences. Describe the general capability, not just today's files." }),
			io: Type.String({ description: "Inputs and outputs: files, stdin/stdout, formats, flags you expect." }),
			example: Type.Optional(
				Type.String({ description: "The invocation you wish you could run, against your real files, e.g. 'images-to-pdf --out cards.pdf a.jpg b.jpg'." }),
			),
			closest: Type.Optional(Type.String({ description: "Closest existing catalog tool from toolsmith_search, if any." })),
			context: Type.Optional(
				Type.String({ description: "Anything else useful: relevant file paths, what you observed about the inputs, constraints." }),
			),
		}),
		async execute(_id, params, signal, onUpdate, ctx) {
			const model = process.env.TOOLSMITH_MODEL || (ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined);
			const thinking = pi.getThinkingLevel?.();
			const details: SubagentDetails = { status: "running", steps: [], model, usage: emptyUsage() };

			const args = [
				"--mode", "json", "-p", "--no-session",
				// A clean child: no extensions (no recursion into toolsmith, no herdr),
				// no skills, prompts, AGENTS.md, MCP or project-local resources.
				"--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files",
				"--no-themes", "--no-mcp", "--no-approve", "--offline",
				"--tools", "read,bash,edit,write",
				"--system-prompt", fs.readFileSync(AGENT_PROMPT, "utf8"),
				"--append-system-prompt", STANDARDS,
				"--append-system-prompt", REPLY_FORMAT,
			];
			if (model) args.push("--model", model);
			if (thinking && !process.env.TOOLSMITH_MODEL?.includes(":")) args.push("--thinking", thinking);
			args.push("--", buildBrief(params, ctx.cwd));

			const progress = () =>
				onUpdate?.({
					content: text(
						`toolsmith working (${details.steps.length} steps)…\n${details.steps.slice(-6).join("\n")}`,
					),
					details: { ...details },
				});
			progress();

			let finalText = "";
			let stopReason: string | undefined;
			let errorMessage: string | undefined;
			let stderr = "";
			let aborted = false;

			const outcome = await new Promise<{ code: number | null; error?: Error; timedOut?: boolean }>((resolve) => {
				const inv = piInvocation(args);
				const proc = spawn(inv.command, inv.args, {
					cwd: ctx.cwd,
					stdio: ["ignore", "pipe", "pipe"],
					env: { ...process.env, PATH: `${BIN_DIR}${path.delimiter}${process.env.PATH ?? ""}`, TOOLSMITH_CHILD: "1" },
				});
				let buf = "";
				let settled = false;
				let timedOut = false;
				const kill = () => {
					if (proc.exitCode !== null || proc.signalCode !== null) return;
					proc.kill("SIGTERM");
					setTimeout(() => proc.exitCode === null && proc.kill("SIGKILL"), 5000).unref?.();
				};
				const timer = setTimeout(() => {
					timedOut = true;
					kill();
				}, SUBAGENT_TIMEOUT_MS);
				const onAbort = () => {
					aborted = true;
					kill();
				};
				const done = (r: { code: number | null; error?: Error }) => {
					if (settled) return;
					settled = true;
					clearTimeout(timer);
					signal?.removeEventListener("abort", onAbort);
					resolve({ ...r, timedOut });
				};
				const handle = (line: string) => {
					if (!line.trim()) return;
					let ev: any;
					try {
						ev = JSON.parse(line);
					} catch {
						return;
					}
					if (ev.type === "tool_execution_start") {
						details.steps.push(describeStep(ev.toolName, ev.args));
						progress();
					} else if (ev.type === "message_end" && ev.message?.role === "assistant") {
						const m = ev.message;
						addUsage(details.usage, m.usage);
						stopReason = m.stopReason;
						errorMessage = m.errorMessage;
						const t = (m.content ?? [])
							.filter((c: any) => c.type === "text")
							.map((c: any) => c.text)
							.join("\n")
							.trim();
						if (t) finalText = t;
					}
				};
				proc.stdout.setEncoding("utf8");
				proc.stdout.on("data", (d: string) => {
					buf += d;
					const lines = buf.split("\n");
					buf = lines.pop() ?? "";
					for (const l of lines) handle(l.replace(/\r$/, ""));
				});
				proc.stderr.on("data", (d) => {
					stderr = (stderr + d.toString()).slice(-4000);
				});
				proc.on("error", (error) => done({ code: null, error }));
				proc.on("close", (code) => {
					if (buf.trim()) handle(buf);
					done({ code });
				});
				if (signal?.aborted) onAbort();
				else signal?.addEventListener("abort", onAbort, { once: true });
			});

			details.exitCode = outcome.code;
			const failed = (why: string) => {
				details.status = aborted ? "aborted" : "failed";
				details.stderr = stderr.trim() || undefined;
				return {
					content: text(
						`toolsmith ${details.status}: ${why}${stderr.trim() ? `\nstderr (tail):\n${stderr.trim().slice(-1500)}` : ""}${finalText ? `\nlast message:\n${finalText}` : ""}`,
					),
					details,
					usage: details.usage,
					isError: true,
				};
			};

			if (aborted) return failed("aborted by the caller");
			if (outcome.error) return failed(`could not start pi: ${outcome.error.message}`);
			if (outcome.timedOut) return failed(`timed out after ${SUBAGENT_TIMEOUT_MS / 60000} minutes`);
			if (outcome.code !== 0) return failed(`subagent exited with code ${outcome.code}`);
			if (stopReason === "error") return failed(errorMessage || "model error");
			if (!finalText) return failed("subagent finished without a reply");

			details.status = "done";
			const isNone = /^tool:\s*none\b/m.test(finalText);
			return {
				content: text(finalText),
				details,
				usage: details.usage,
				...(isNone ? { isError: true } : {}),
			};
		},
	});

	// Nudge: hold the first attempt at a helper script; an identical retry passes.
	pi.on("tool_call", async (event, ctx) => {
		if (!nudgeEnabled) return;
		// Calls made from inside a codemode script were vetted with the script.
		// Holding one mid-script would make the agent re-run the whole script,
		// repeating its earlier side effects.
		if ((event as any).parentToolCallId) return;
		let why: string | null = null;
		const input: any = event.input;
		const isCodemode = event.toolName === "codemode" && typeof input?.code === "string";
		if (isCodemode) {
			why = codemodeScriptSmell(input.code);
		} else if (event.toolName === "bash" && typeof input?.command === "string") {
			why = bashScriptSmell(input.command);
		} else if (event.toolName === "write" && typeof input?.path === "string" && typeof input?.content === "string") {
			why = writeScriptSmell(input.path, input.content, ctx.cwd);
		}
		if (!why) return;
		const key = createHash("sha1").update(`${event.toolName}\0${JSON.stringify(input)}`).digest("hex");
		if (heldOnce.has(key)) {
			heldOnce.delete(key);
			return;
		}
		heldOnce.add(key);
		return { block: true, reason: NUDGE(why, isCodemode) };
	});

	pi.registerCommand("toolsmith", {
		description: "List cataloged tools, or turn the helper-script nudge on/off: /toolsmith [search words] | nudge on|off",
		handler: async (args, ctx) => {
			const a = (args ?? "").trim();
			const nudge = a.match(/^nudge(?:\s+(on|off))?$/);
			if (nudge) {
				if (nudge[1]) nudgeEnabled = nudge[1] === "on";
				ctx.ui.notify(`toolsmith nudge is ${nudgeEnabled ? "on" : "off"}`, "info");
				return;
			}
			const lines = readCatalogLines(await locateCatalogs(pi, ctx.cwd));
			const hits = a ? searchCatalog(lines, a) : lines;
			ctx.ui.notify(
				hits.length ? hits.map((l) => l.replace(/^- \S*\/bin\//, "- ")).join("\n") : lines.length ? `No tool matches "${a}".` : "No tools cataloged yet.",
				"info",
			);
		},
	});
}
