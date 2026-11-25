// Heuristics that spot a throwaway helper script about to run.
// Pure functions with no pi imports, so tests can load them with plain node.

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export const MAX_INLINE_LINES = 5;

// ---------- bash ----------

const INTERP = String.raw`(?:python[0-9.]*|node|ruby|perl|php|deno|bun|lua|Rscript|osascript)`;
const HEREDOC_TO_INTERP = new RegExp(String.raw`(?:^|[\s;&|(/])${INTERP}\b[^\n]*<<-?\s*['"]?\w+`, "m");
const INLINE_CODE = new RegExp(String.raw`(?:^|[\s;&|(/])${INTERP}\s+(?:-[A-Za-z]*\s+)*(?:-c|-e|--eval|-p)\s`, "m");
const SCRIPT_EXT_ALT = "py|js|mjs|cjs|ts|rb|pl|php|sh|bash|lua|r";
const HEREDOC_TO_FILE = new RegExp(
	String.raw`(?:\bcat|\btee)\b[^\n]*?\S+\.(?:${SCRIPT_EXT_ALT})\b[^\n]*<<|<<[^\n]*>\s*\S+\.(?:${SCRIPT_EXT_ALT})\b`,
	"i",
);
// Long one-liners dodge a line count, so code size counts too.
const MAX_INLINE_CHARS = 600;

export function bashScriptSmell(cmd: string): string | null {
	const lines = cmd.split("\n").length;
	const big = lines > MAX_INLINE_LINES || cmd.length > MAX_INLINE_CHARS;
	if (!big) return null;
	const size = lines > MAX_INLINE_LINES ? `${lines}-line` : `${cmd.length}-character`;
	if (HEREDOC_TO_FILE.test(cmd)) return `writes a ${size} script file through a heredoc`;
	if (HEREDOC_TO_INTERP.test(cmd)) return `feeds a ${size} heredoc to an interpreter`;
	if (INLINE_CODE.test(cmd)) return `passes ${size} inline code to an interpreter (-c/-e)`;
	return null;
}

// ---------- write ----------

const SCRIPT_EXT = new RegExp(String.raw`\.(?:${SCRIPT_EXT_ALT}|zsh)$`, "i");

function inGitRepo(p: string): boolean {
	let dir = path.dirname(p);
	for (;;) {
		if (fs.existsSync(path.join(dir, ".git"))) return true;
		const up = path.dirname(dir);
		if (up === dir) return false;
		dir = up;
	}
}

export function writeScriptSmell(filePath: string, content: string, cwd: string): string | null {
	if (!SCRIPT_EXT.test(filePath)) return null;
	const lines = content.split("\n").length;
	if (lines <= MAX_INLINE_LINES) return null;
	const abs = path.resolve(cwd, filePath.replace(/^@/, ""));
	const tmpRoots = [os.tmpdir(), "/tmp", "/private/tmp", "/var/folders", "/private/var/folders"];
	if (tmpRoots.some((r) => abs.startsWith(r.endsWith("/") ? r : `${r}/`))) {
		return `writes a ${lines}-line script to a temp directory`;
	}
	// Inside a git repo a script file is most likely the project's own code.
	if (!inGitRepo(abs)) return `writes a ${lines}-line script outside any project repository`;
	return null;
}

// ---------- codemode ----------
//
// codemode exists to orchestrate tools: batch calls, chain them, trim their
// output. That is fine. It becomes a helper script when the JavaScript does
// the work itself: parsing files, transforming or merging records, building
// edits. We measure the code with string, template and regex literals and
// comments removed (a long shell command or a block of data passed to a tool
// is orchestration, not logic). Then we count data-processing constructs.

/** Replace string/template/regex literals and comments with short placeholders. */
export function skeleton(code: string): string {
	let out = "";
	let i = 0;
	const n = code.length;
	let prevSignificant = ""; // last non-space char emitted, to tell regex from division
	while (i < n) {
		const c = code[i];
		const d = code[i + 1];
		if (c === "/" && d === "/") {
			while (i < n && code[i] !== "\n") i++;
			continue;
		}
		if (c === "/" && d === "*") {
			i += 2;
			while (i < n && !(code[i] === "*" && code[i + 1] === "/")) i++;
			i += 2;
			continue;
		}
		if (c === '"' || c === "'" || c === "`") {
			const q = c;
			i++;
			while (i < n && code[i] !== q) {
				if (code[i] === "\\") i++;
				else if (q === "`" && code[i] === "$" && code[i + 1] === "{") {
					// Keep the code inside ${...}; it can carry logic.
					let depth = 1;
					i += 2;
					let inner = "";
					while (i < n && depth > 0) {
						if (code[i] === "{") depth++;
						else if (code[i] === "}") depth--;
						if (depth > 0) inner += code[i];
						i++;
					}
					out += ` ${skeleton(inner)} `;
					continue;
				}
				i++;
			}
			i++;
			out += "S";
			prevSignificant = "S";
			continue;
		}
		if (c === "/" && /[(,=:[!&|?{};+\-*%<>~^]|^$/.test(prevSignificant)) {
			// Regex literal.
			i++;
			let inClass = false;
			while (i < n && (code[i] !== "/" || inClass) && code[i] !== "\n") {
				if (code[i] === "\\") i++;
				else if (code[i] === "[") inClass = true;
				else if (code[i] === "]") inClass = false;
				i++;
			}
			i++;
			while (i < n && /[a-z]/i.test(code[i])) i++;
			out += "R";
			prevSignificant = "R";
			continue;
		}
		out += c;
		if (!/\s/.test(c)) prevSignificant = c;
		i++;
	}
	return out;
}

const LOGIC_PATTERNS: [string, RegExp][] = [
	["JSON.parse", /\bJSON\.parse\b/g],
	["JSON.stringify", /\bJSON\.stringify\b/g],
	["regex", /\bR\b|new RegExp\b/g],
	["replace/split/match", /\.(?:replace|replaceAll|split|match|matchAll)\(/g],
	["filter/reduce/sort/flatMap/find", /\.(?:filter|reduce|sort|flatMap|find|findIndex|some|every)\(/g],
	["push/splice/Object.assign", /\.(?:push|splice|unshift)\(|\bObject\.(?:assign|entries|fromEntries)\b/g],
	["loops", /\b(?:for|while)\s*\(/g],
	["conditionals", /\bif\s*\(|\?[^.?]/g],
	["functions", /=>\s*\{|\bfunction\b/g],
];

export type CodemodeAnalysis = { size: number; logic: number; toolCalls: number; signals: string[] };

export function analyzeCodemode(code: string): CodemodeAnalysis {
	const sk = skeleton(code);
	const compact = sk.replace(/\s+/g, " ");
	let logic = 0;
	const signals: string[] = [];
	for (const [name, re] of LOGIC_PATTERNS) {
		const m = compact.match(re)?.length ?? 0;
		if (m) {
			logic += m;
			signals.push(`${name}×${m}`);
		}
	}
	const toolCalls = compact.match(/\btools\.\w+\(/g)?.length ?? 0;
	return { size: compact.length, logic, toolCalls, signals };
}

// Calibrated on ~370 codemode scripts from real sessions: orchestration
// stays well under these; record-merging and edit generation goes over.
export const CODEMODE_MIN_SIZE = 900;
export const CODEMODE_MIN_LOGIC = 14;

/** Contents of the string and template literals in JavaScript source, unescaped. */
export function stringLiterals(code: string): string[] {
	const out: string[] = [];
	const re = /"((?:\\.|[^"\\\n])*)"|'((?:\\.|[^'\\\n])*)'|`((?:\\.|[^`\\])*)`/g;
	for (const m of code.matchAll(re)) {
		const raw = m[1] ?? m[2] ?? m[3] ?? "";
		out.push(
			raw.replace(/\\(u[0-9a-fA-F]{4}|.)/g, (_, e: string) =>
				e.length > 1 ? String.fromCharCode(parseInt(e.slice(1), 16)) : ({ n: "\n", t: "\t", r: "\r" } as Record<string, string>)[e] ?? e,
			),
		);
	}
	return out;
}

export function codemodeScriptSmell(code: string): string | null {
	const a = analyzeCodemode(code);
	if (a.size >= CODEMODE_MIN_SIZE && a.logic >= CODEMODE_MIN_LOGIC) {
		return `is a codemode script with ${a.size} characters of logic outside strings (${a.signals.slice(0, 4).join(", ")}): data processing, not tool orchestration`;
	}
	// Shell commands passed to tools.bash() are string literals in the script.
	for (const s of stringLiterals(code)) {
		const why = bashScriptSmell(s);
		if (why) return `is a codemode script whose bash command ${why}`;
	}
	return null;
}
