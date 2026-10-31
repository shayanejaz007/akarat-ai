/**
 * Ask a Lawyer's evaluation: every case in tests/legal/evals/cases.json,
 * answered by the real model with the real tools, graded on behaviour, and
 * written out as a review sheet for a licensed Jordanian lawyer.
 *
 *   node scripts/legal-eval.mts --yes [--only id,id] [--out folder]
 *
 * Needs ANTHROPIC_API_KEY. With NEXT_PUBLIC_SUPABASE_URL and
 * SUPABASE_SERVICE_ROLE_KEY it searches the real legal library too; without
 * them the library is absent and the answers rely on official websites,
 * which the sheet says.
 *
 * It costs money: each case is one full answer (the estimate is printed
 * first, and nothing runs without --yes). The automated checks are about
 * behaviour; whether the law in an answer is right is the reviewing
 * lawyer's call, recorded on the sheet (LEGAL-AI.md, "Before launch").
 */
import Anthropic from "@anthropic-ai/sdk";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { estimateCostUsd } from "../lib/advisor/config.ts";
import { runTurn, type ClientEvent, type DocInput } from "../lib/legal/agent.ts";
import { MODEL } from "../lib/legal/config.ts";
import { grade, type Check, type EvalCase } from "../lib/legal/evals.ts";
import { libraryCounts } from "../lib/legal/library.ts";
import { ammanDate } from "../lib/legal/prompt.ts";
import { libraryDb, serviceClient } from "../lib/legal/store.ts";

const args = process.argv.slice(2);
const opt = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const only = opt("--only")?.split(",").map(s => s.trim()).filter(Boolean);
const outDir = opt("--out") ?? "eval-results";

const all = (JSON.parse(readFileSync("tests/legal/evals/cases.json", "utf8")) as { cases: EvalCase[] }).cases;
const cases = only ? all.filter(c => only.includes(c.id)) : all;
if (!cases.length) {
  console.log("No cases match --only.");
  process.exit(1);
}
const estimate = cases.length * 0.25;
console.log(`${cases.length} case(s) with ${MODEL}. Rough cost: up to about $${estimate.toFixed(2)}.`);
if (!args.includes("--yes")) {
  console.log("Nothing run. Add --yes to run them (this uses the Anthropic API and costs money).");
  process.exit(0);
}
if (!process.env.ANTHROPIC_API_KEY) {
  console.log("Set ANTHROPIC_API_KEY to run the evaluation.");
  process.exit(1);
}

const client = new Anthropic({ maxRetries: 2, timeout: 60_000 });
const db = libraryDb(serviceClient());
const counts = db ? await libraryCounts(db) : null;
const today = ammanDate();

type Result = {
  id: string; category: string; lang: string; question: string; document: string | null; rubric: string;
  status: string; answer: string; sources: { n: number; kind: string; title: string; url: string; status?: string | null }[];
  unverified: string[]; urgent: string | null; checks: Check[]; costUsd: number | null; ms: number;
};
const results: Result[] = [];

for (const c of cases) {
  const events: ClientEvent[] = [];
  const docs: DocInput[] = c.document
    ? [{ id: `eval-${c.id}`, n: 1, name: c.document.name, kind: "txt", mediaType: "text/plain", body: Buffer.from(c.document.text, "utf8"), pages: null, scanned: false }]
    : [];
  const started = Date.now();
  const r = await runTurn({
    client,
    history: [],
    message: c.question,
    docs,
    context: { today, uiLang: c.lang, library: counts, documents: docs.map(d => ({ n: d.n, name: d.name, kind: d.kind, pages: null, scanned: false })) },
    env: { db },
    knownRefs: [],
    emit: e => events.push(e),
    signal: new AbortController().signal,
  });
  const checks = grade(c, {
    status: r.status,
    reply: r.reply,
    sources: r.sources,
    unverified: r.unverified,
    urgent: !!r.urgent,
    redacted: events.some(e => e.t === "redact"),
  });
  const cost = estimateCostUsd(r.usage, MODEL);
  results.push({
    id: c.id, category: c.category, lang: c.lang, question: c.question, document: c.document?.name ?? null, rubric: c.rubric,
    status: r.status, answer: r.reply,
    sources: r.sources.map(s => ({ n: s.n, kind: s.kind, title: s.title, url: s.url, status: s.status ?? null })),
    unverified: r.unverified, urgent: r.urgent?.text ?? null, checks,
    costUsd: cost == null ? null : Math.round(cost * 1000) / 1000, ms: Date.now() - started,
  });
  const passed = checks.filter(x => x.pass).length;
  console.log(`${passed === checks.length ? "✓" : "✗"} ${c.id.padEnd(22)} ${passed}/${checks.length} checks  ${r.sources.length} sources  ${r.unverified.length} unverified  ${cost == null ? "" : `$${cost.toFixed(3)}`}`);
  for (const x of checks.filter(x => !x.pass)) console.log(`    ✗ ${x.name}${x.detail ? ` (${x.detail})` : ""}`);
}

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]!);
const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
const totals = {
  cases: results.length,
  allChecksPassed: results.filter(r => r.checks.every(c => c.pass)).length,
  answersWithUnverified: results.filter(r => r.unverified.length).length,
  sourcesCited: results.reduce((n, r) => n + r.sources.length, 0),
  costUsd: Math.round(results.reduce((n, r) => n + (r.costUsd ?? 0), 0) * 100) / 100,
};

mkdirSync(outDir, { recursive: true });
const jsonPath = join(outDir, `legal-eval-${stamp}.json`);
writeFileSync(jsonPath, JSON.stringify({ model: MODEL, date: today, library: counts, totals, results }, null, 2));

const sheet = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>Ask a Lawyer — review sheet ${esc(today)}</title>
<style>
  body { font: 13px/1.55 -apple-system, "Segoe UI", Tahoma, sans-serif; color: #17170F; max-width: 900px; margin: 24px auto; padding: 0 18px; }
  h1 { font-size: 20px; } h2 { font-size: 15px; margin: 0 0 4px; } .meta { color: #666; font-size: 12px; }
  section { border: 1px solid #ccc; border-radius: 10px; padding: 14px 16px; margin: 18px 0; page-break-inside: avoid; }
  .q { background: #F4F1EA; padding: 8px 10px; border-radius: 6px; } .a { white-space: pre-wrap; border-inline-start: 3px solid #007A3D; padding-inline-start: 10px; }
  .ok { color: #00693A; } .bad { color: #B00F20; } .form p { margin: 6px 0; } .line { border-bottom: 1px solid #999; height: 22px; }
  .rubric { background: #FFF7E6; padding: 8px 10px; border-radius: 6px; }
</style></head><body>
<h1>Ask a Lawyer — review sheet</h1>
<p class="meta">${esc(today)} · ${esc(MODEL)} · library: ${counts ? `${counts.total} verified sources` : "not connected"} · ${totals.cases} cases · automated checks all passed on ${totals.allChecksPassed} · ${totals.answersWithUnverified} answers named an unverified reference · estimated cost $${totals.costUsd}</p>
<p>The automated checks cover behaviour only. Please judge each answer's law against the official texts and record it below.</p>
${results.map(r => `<section>
<h2>${esc(r.id)} · ${esc(r.category)}</h2>
<p class="q" dir="auto"><b>Question:</b> ${esc(r.question)}${r.document ? `<br><b>Document:</b> ${esc(r.document)}` : ""}</p>
${r.urgent ? `<p><b>Urgent notice shown:</b> <span dir="auto">${esc(r.urgent)}</span></p>` : ""}
<div class="a" dir="auto">${esc(r.answer.replace(/[\ue000-\uf8ff]/g, "")) || "<i>(no answer: " + esc(r.status) + ")</i>"}</div>
${r.sources.length ? `<p><b>Sources:</b></p><ol>${r.sources.map(s => `<li dir="auto">[${esc(s.kind)}${s.status ? `, ${esc(s.status)}` : ""}] ${esc(s.title)} ${s.url ? `<br><span class="meta">${esc(s.url)}</span>` : ""}</li>`).join("")}</ol>` : "<p><b>Sources:</b> none cited.</p>"}
${r.unverified.length ? `<p class="bad"><b>Marked unverified on the page:</b> ${esc(r.unverified.join(", "))}</p>` : ""}
<p><b>Automated checks:</b></p><ul>${r.checks.map(c => `<li class="${c.pass ? "ok" : "bad"}">${c.pass ? "✓" : "✗"} ${esc(c.name)}${c.detail ? ` <span class="meta">(${esc(c.detail)})</span>` : ""}</li>`).join("")}</ul>
<p class="rubric"><b>What a correct answer does:</b> ${esc(r.rubric)}</p>
<div class="form">
<p>Legally correct?&nbsp;&nbsp; ☐ Yes&nbsp;&nbsp; ☐ Partly&nbsp;&nbsp; ☐ No</p>
<p>Citations accurate and current?&nbsp;&nbsp; ☐ Yes&nbsp;&nbsp; ☐ No&nbsp;&nbsp; ☐ None cited</p>
<p>Unsupported or misleading statements:</p><div class="line"></div><div class="line"></div>
<p>Notes:</p><div class="line"></div><div class="line"></div>
<p>Reviewer and date:</p><div class="line"></div>
</div>
</section>`).join("\n")}
</body></html>`;
const htmlPath = join(outDir, `legal-eval-${stamp}.html`);
writeFileSync(htmlPath, sheet);

console.log(`\n${totals.allChecksPassed}/${totals.cases} cases passed every automated check · ${totals.answersWithUnverified} named an unverified reference · about $${totals.costUsd}`);
console.log(`Results: ${jsonPath}\nReview sheet: ${htmlPath}`);
