// Rank codemode scripts from pi session logs by the toolsmith codemode
// heuristic, to tune CODEMODE_MIN_SIZE / CODEMODE_MIN_LOGIC in smells.ts.
//
//   node test/calibrate-codemode.ts [--top N] [--sessions DIR] [--show INDEX]
//
// Reads ~/.pi/agent/sessions/**/*.jsonl (read-only). Rows marked * would be held.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { analyzeCodemode, CODEMODE_MIN_LOGIC, CODEMODE_MIN_SIZE, codemodeScriptSmell } from "../smells.ts";

const args = process.argv.slice(2);
const opt = (name: string, def: string) => {
	const i = args.indexOf(name);
	return i >= 0 ? args[i + 1] : def;
};
const top = Number(opt("--top", "30"));
const dir = opt("--sessions", join(homedir(), ".pi/agent/sessions"));
const show = opt("--show", "");

function* files(d: string): Generator<string> {
	for (const e of readdirSync(d)) {
		const p = join(d, e);
		if (statSync(p).isDirectory()) {
			if (!e.includes("private-var-folders")) yield* files(p); // skip test-run sessions
		} else if (e.endsWith(".jsonl")) yield p;
	}
}

const scripts: { session: string; code: string }[] = [];
for (const f of files(dir)) {
	for (const line of readFileSync(f, "utf8").split("\n")) {
		if (!line.includes('"codemode"')) continue;
		try {
			const ev = JSON.parse(line);
			for (const c of ev.message?.content ?? []) {
				if (c.type === "toolCall" && c.name === "codemode" && typeof c.arguments?.code === "string") {
					scripts.push({ session: f.split("_").pop()!.replace(".jsonl", ""), code: c.arguments.code });
				}
			}
		} catch {
			/* not JSON */
		}
	}
}

if (show) {
	console.log(scripts[Number(show)]?.code ?? "no such index");
	process.exit(0);
}

const rows = scripts
	.map((s, i) => ({ i, ...s, ...analyzeCodemode(s.code) }))
	.sort((a, b) => b.logic - a.logic || b.size - a.size);
const held = rows.filter((r) => r.size >= CODEMODE_MIN_SIZE && r.logic >= CODEMODE_MIN_LOGIC);
console.log(`${scripts.length} scripts; ${held.length} held by the logic rule (size>=${CODEMODE_MIN_SIZE}, logic>=${CODEMODE_MIN_LOGIC})`);
for (const r of rows) {
	const why = codemodeScriptSmell(r.code);
	if (why?.includes("bash command")) console.log(`  #${r.i} held by the bash rule: ${why}`);
}
for (const r of rows.slice(0, top)) {
	const mark = r.size >= CODEMODE_MIN_SIZE && r.logic >= CODEMODE_MIN_LOGIC ? "*" : " ";
	console.log(`${mark} #${r.i} ${r.session.slice(0, 13)} size=${r.size} raw=${r.code.length} logic=${r.logic} tools=${r.toolCalls} ${r.signals.join(" ")}`);
}
