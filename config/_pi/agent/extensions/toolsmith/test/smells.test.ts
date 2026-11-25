// node --test test/
import assert from "node:assert/strict";
import { test } from "node:test";
import {
	analyzeCodemode,
	bashScriptSmell,
	codemodeScriptSmell,
	skeleton,
	stringLiterals,
	writeScriptSmell,
} from "../smells.ts";

const lines = (n: number, s = "x = 1") => Array.from({ length: n }, () => s).join("\n");

test("bash: multi-line python heredoc is held", () => {
	assert.match(bashScriptSmell(`python3 - <<'EOF'\n${lines(6)}\nEOF`) ?? "", /heredoc to an interpreter/);
	assert.match(bashScriptSmell(`uv run --with pillow python - <<'EOF'\n${lines(6)}\nEOF`) ?? "", /heredoc/);
});

test("bash: long single-line python -c is held, short is not", () => {
	assert.match(bashScriptSmell(`python3 -c "${"import json;".repeat(60)}"`) ?? "", /character inline code/);
	assert.equal(bashScriptSmell(`python3 -c "print(1)"`), null);
});

test("bash: heredoc into a script file is held", () => {
	assert.match(bashScriptSmell(`cat > /tmp/fix.py <<'EOF'\n${lines(6)}\nEOF`) ?? "", /script file/);
});

test("bash: non-interpreter heredocs and plain pipelines pass", () => {
	assert.equal(bashScriptSmell(`git commit -F - <<'EOF'\n${lines(10, "message line")}\nEOF`), null);
	assert.equal(bashScriptSmell(`cat > notes.md <<'EOF'\n${lines(10, "text")}\nEOF`), null);
	assert.equal(bashScriptSmell(`ls -la | rg foo | head`), null);
});

test("write: script in temp dir is held, docs are not", () => {
	assert.match(writeScriptSmell("/tmp/convert.py", lines(10), "/tmp") ?? "", /temp directory/);
	assert.equal(writeScriptSmell("/tmp/notes.md", lines(10), "/tmp"), null);
	assert.equal(writeScriptSmell("/tmp/tiny.py", lines(3), "/tmp"), null);
});

test("skeleton strips strings, templates, regexes and comments but keeps ${} code", () => {
	const sk = skeleton(`const a = "long string"; // note\nconst b = s.replace(/a+b/g, 'x') / 2; const c = \`v=\${f(x)}\`;`);
	assert.ok(!sk.includes("long string") && !sk.includes("note") && !sk.includes("a+b"));
	assert.ok(sk.includes("f(x)") && sk.includes("/ 2"));
});

test("stringLiterals unescapes newlines", () => {
	assert.deepEqual(stringLiterals(`tools.bash({command:"a\\nb"})`), ["a\nb"]);
});

test("codemode: orchestration passes", () => {
	const orchestration = `const r = await Promise.allSettled(["a.md","b.md","c.md"].map(path => tools.read({path, offset: null, limit: null})));
r.forEach((x, i) => text(x.value ?? x.reason));
text(await tools.bash({command: "${"fireclerk open 'https://example.com/very/long/url' --background --json; ".repeat(10)}", timeout: null}));
for (const id of [152, 153, 154]) text(await tools.bash({command: \`fireclerk markdown \${id}\`, timeout: null}));`;
	assert.equal(codemodeScriptSmell(orchestration), null);
});

test("codemode: record merging and edit generation is held", () => {
	const merge = `const db = JSON.parse(load("raw")), cards = load("cards"), day = "2026-11-25", edits = [];
const block = o => JSON.stringify(o, null, 2).split("\\n").map(l => "    " + l).join("\\n");
let merged = 0, updated = 0;
for (const j of db.jobs) {
  if (j.id === "skip-me") continue;
  const before = block(j); let n = 0;
  for (const c of cards) {
    if (j.sources.some(s => s.source_job_id === c.id) && !j.sources.some(s => s.message_id === c.message_id)) { j.sources.push({ type: "email", url: c.url, observed_on: day }); n++; }
  }
  if (n) { merged += n; updated++; j.history.push({ date: day, event: "merged " + n }); edits.push({ oldText: before, newText: block(j) }); }
}
const make = (id, company, title, url, priority) => ({ id, company, title, url, priority, sources: [], history: [{ date: day, event: "new" }] });
const a = make("a", "A", "T", "u", "p"); Object.assign(a, { summary: "s" });
const b = make("b", "B", "T", "u", "p"); Object.assign(b, { summary: "s" });
for (const j of [a, b]) j.sources.push(...cards.filter(c => c.company === j.company).map(c => ({ url: c.url })));
const sorted = db.jobs.filter(j => j.priority !== "excluded").sort((x, y) => x.id.localeCompare(y.id));
if (sorted.length > 40) edits.push({ oldText: "x", newText: sorted.map(block).join(",\\n") });
store("edits", edits); text(await tools.edit({ path: "jobs.json", edits }));`;
	const a = analyzeCodemode(merge);
	assert.ok(codemodeScriptSmell(merge), `expected hold; size=${a.size} logic=${a.logic}`);
});

test("codemode: bash heredoc inside tools.bash is held", () => {
	const code = `text(await tools.bash({command: "python3 - <<'EOF'\\n${lines(6).replaceAll("\n", "\\n")}\\nEOF", timeout: 60}));`;
	assert.match(codemodeScriptSmell(code) ?? "", /bash command feeds/);
});
