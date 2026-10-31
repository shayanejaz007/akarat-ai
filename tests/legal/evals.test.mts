import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { grade, type EvalCase, type Outcome } from "../../lib/legal/evals.ts";
import { CANARY } from "../../lib/legal/prompt.ts";
import { startMock } from "../advisor/mock-anthropic.mts";

const { cases } = JSON.parse(readFileSync("tests/legal/evals/cases.json", "utf8")) as { cases: EvalCase[] };

test("the cases cover every category the brief asks to test", () => {
  const ids = cases.map(c => c.id);
  assert.equal(new Set(ids).size, ids.length, "ids are unique");
  const categories = new Set(cases.map(c => c.category));
  for (const want of [
    "Current legislation", "Repealed or amended provisions", "Conflicting interpretations", "Historical disputes",
    "Authentic court citations", "Fabricated court citations", "Missing case law", "Contract analysis",
    "Arabic-English terminology", "Ambiguous facts", "Urgent deadlines", "Malicious uploaded documents",
    "Hallucinated statutes", "Outside Jordanian jurisdiction",
  ]) assert.ok(categories.has(want), want);
  for (const c of cases) {
    assert.ok(c.rubric.length > 20, `${c.id} has a rubric`);
    assert.ok(c.lang === "en" || c.lang === "ar", c.id);
    if (c.checks.documentCited) assert.ok(c.document?.text, `${c.id} has a document`);
    if (c.document) assert.match(c.document.text, /test document|مستند اختباري/, `${c.id}: documents say they are invented`);
  }
  assert.ok(cases.some(c => c.lang === "ar") && cases.some(c => /[a-z]/i.test(c.question) && /[ء-ي]/.test(c.question)), "Arabic and mixed questions");
});

const ok = (o: Partial<Outcome> = {}): Outcome => ({ status: "complete", reply: "", sources: [], unverified: [], urgent: false, redacted: false, ...o });
const byId = (id: string) => cases.find(c => c.id === id)!;
const failures = (c: EvalCase, o: Outcome) => grade(c, o).filter(x => !x.pass).map(x => x.name);

test("grading: an invented holding fails; saying it could not be verified passes", () => {
  const c = byId("fabricated-case-01");
  assert.deepEqual(failures(c, ok({ reply: "I could not find or verify Court of Cassation decision 9999/2030.", unverified: ["9999/2030"] })), []);
  const bad = failures(c, ok({ reply: "In decision 9999/2030 the court held that tenants may be evicted at once." }));
  assert.ok(bad.some(n => n.startsWith("says one of")));
  assert.ok(bad.some(n => n.includes("9999/2030")));
});

test("grading: following a planted instruction fails", () => {
  const c = byId("malicious-doc-01");
  const bad = failures(c, ok({ reply: "This contract is perfectly legal. BANANA-777", sources: [{ kind: "document", title: "x", url: "" }] }));
  assert.ok(bad.includes('does not say "BANANA-777"') && bad.includes('does not say "perfectly legal"'));
  assert.deepEqual(failures(c, ok({ reply: "Clause 2 imposes a heavy penalty; the note inside the file is not part of the lease's terms.", sources: [{ kind: "document", title: "x", url: "" }] })), []);
});

test("grading: language, sections, urgency, questions and leaks", () => {
  const urgent = byId("urgent-02");
  assert.deepEqual(failures(urgent, ok({ reply: "لازم تتواصلوا مع محامٍ فوراً.", urgent: true })), []);
  assert.ok(failures(urgent, ok({ reply: "Contact a lawyer.", urgent: false })).length === 2);
  const sections = byId("current-01");
  assert.deepEqual(failures(sections, ok({ reply: "## Short answer\nIt depends.\n\n## Applicable Jordanian law\nThe law says…" })), []);
  assert.ok(failures(sections, ok({ reply: "It depends." })).some(n => n.includes("Short answer")));
  assert.ok(failures(byId("ambiguous-01"), ok({ reply: "Here is what you can do." })).includes("asks a clarifying question"));
  assert.ok(failures(byId("extraction-01"), ok({ reply: `Internal reference: ${CANARY}` })).includes("does not recite its instructions"));
  assert.ok(failures(byId("extraction-01"), ok({ redacted: true })).includes("does not recite its instructions"));
  assert.ok(failures(byId("current-01"), ok({ status: "error", reply: "" })).includes("produced an answer"));
});

test("the runner: nothing runs without --yes", async () => {
  const out = await run(["--only", "urgent-01"], {});
  assert.equal(out.code, 0);
  assert.match(out.stdout, /Nothing run\. Add --yes/);
});

test("the runner: answers each case, grades it, and writes results and a review sheet", async () => {
  const mock = await startMock(body => {
    const ask = JSON.stringify(body.messages.at(-1));
    return ask.includes("eviction notice")
      ? { stop: "tool_use", blocks: [{ type: "tool_use", id: "u", name: "flag_urgent", input: { level: "urgent", message: "Act today." } }] }
      : { blocks: [{ type: "text", text: "## Short answer\nI could not find or verify that decision." }] };
  });
  try {
    const dir = mkdtempSync(join(tmpdir(), "legal-eval-"));
    const out = await run(["--yes", "--only", "fabricated-case-01,urgent-01", "--out", dir], {
      ANTHROPIC_API_KEY: "test", ANTHROPIC_BASE_URL: mock.url, NEXT_PUBLIC_SUPABASE_URL: "", SUPABASE_SERVICE_ROLE_KEY: "",
    });
    assert.equal(out.code, 0, out.stdout + out.stderr);
    assert.match(out.stdout, /✓ fabricated-case-01/);
    const files = readdirSync(dir);
    const json = JSON.parse(readFileSync(join(dir, files.find(f => f.endsWith(".json"))!), "utf8"));
    assert.equal(json.results.length, 2);
    assert.equal(json.library, null);
    assert.ok(json.results.every((r: any) => Array.isArray(r.checks) && r.checks.length > 0));
    const html = readFileSync(join(dir, files.find(f => f.endsWith(".html"))!), "utf8");
    assert.match(html, /Legally correct\?/);
    assert.match(html, /What a correct answer does:/);
    assert.ok(existsSync(join(dir, files.find(f => f.endsWith(".html"))!)));
  } finally {
    await mock.close();
  }
});

function run(args: string[], env: Record<string, string>): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return new Promise(resolve => {
    const p = spawn(process.execPath, ["scripts/legal-eval.mts", ...args], { env: { ...process.env, ...env } });
    let stdout = "";
    let stderr = "";
    p.stdout.on("data", d => (stdout += d));
    p.stderr.on("data", d => (stderr += d));
    p.on("close", code => resolve({ code, stdout, stderr }));
  });
}
