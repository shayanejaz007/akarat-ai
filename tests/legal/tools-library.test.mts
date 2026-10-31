import assert from "node:assert/strict";
import { test } from "node:test";
import { OFFICIAL_DOMAINS, SECONDARY_DOMAINS, WEB_DOMAINS, tierOfHost } from "../../lib/legal/config.ts";
import { citationTitle, libraryCounts, resetLibraryCache, toSearchResult } from "../../lib/legal/library.ts";
import { TOOLS, runTool } from "../../lib/legal/tools.ts";
import { FakeLibrary, hit } from "./fixtures.mts";

test("custom tools are strict, with every property required", () => {
  const custom = TOOLS.filter((t: any) => t.input_schema) as any[];
  assert.deepEqual(custom.map(t => t.name), ["search_legal_library", "lookup_citation", "flag_urgent"]);
  assert.deepEqual(TOOLS.map((t: any) => t.name), ["search_legal_library", "lookup_citation", "flag_urgent", "web_search", "web_fetch"]);
  for (const t of custom) {
    assert.equal(t.strict, true, t.name);
    assert.equal(t.input_schema.additionalProperties, false, t.name);
    assert.deepEqual([...t.input_schema.required].sort(), Object.keys(t.input_schema.properties).sort(), t.name);
  }
});

test("web tools reach only the approved Jordanian sources, and cite what they read", () => {
  const search = TOOLS.find((t: any) => t.name === "web_search") as any;
  const fetch = TOOLS.find((t: any) => t.name === "web_fetch") as any;
  assert.deepEqual(search.allowed_domains, WEB_DOMAINS);
  assert.deepEqual(fetch.allowed_domains, WEB_DOMAINS);
  assert.deepEqual(fetch.citations, { enabled: true });
  assert.deepEqual(fetch.url_sources, { client_tool_results: { type: "none" } });
  assert.deepEqual(search.allowed_callers, ["direct"]);
  assert.ok(OFFICIAL_DOMAINS.includes("lob.gov.jo") && OFFICIAL_DOMAINS.includes("jc.jo"));
  assert.ok(SECONDARY_DOMAINS.every(d => !OFFICIAL_DOMAINS.includes(d)));
  assert.equal(tierOfHost("www.lob.gov.jo"), "official");
  assert.equal(tierOfHost("eservices.dls.gov.jo"), "official");
  assert.equal(tierOfHost("jba.org.jo"), "secondary");
  assert.equal(tierOfHost("lob.gov.jo.evil.com"), null);
  assert.equal(tierOfHost("example.com"), null);
});

test("library search returns citable results with their provenance", async () => {
  const db = new FakeLibrary([hit({ passageId: 1 }), hit({ passageId: 2, article: "المادة 6", articleNo: 6, body: "نص اختباري عن بدل الإجارة" })]);
  const out = await runTool("search_legal_library", { query: "إخلاء المأجور", kinds: null, limit: null }, { db });
  assert.ok(!out.isError);
  assert.equal(out.hits?.length, 1);
  const blocks = out.content as any[];
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].type, "search_result");
  assert.equal(blocks[0].source, "https://www.lob.gov.jo/test-law");
  assert.equal(blocks[0].title, "قانون اختبار الإيجار رقم 90 لسنة 2001 — المادة 5");
  assert.deepEqual(blocks[0].citations, { enabled: true });
  assert.match(blocks[0].content[0].text, /Status of this provision: in force\./);
  assert.match(blocks[0].content[0].text, /Last verified 2026-10-01 by Test Reviewer\./);
  assert.match(blocks[0].content[0].text, /Official Gazette: /);
  assert.match(blocks[0].content[1].text, /^المادة 5\nنص اختباري/);
  assert.equal(db.calls[0].args.p_limit, 6);
  assert.equal(db.calls[0].args.p_embedding, null);
});

test("nothing found is a plain note, not an error, and says not to cite", async () => {
  const out = await runTool("search_legal_library", { query: "لا شيء هنا", kinds: ["judgment"], limit: 3 }, { db: new FakeLibrary([hit()]) });
  assert.ok(!out.isError);
  assert.equal((out.content as any[])[0].type, "text");
  assert.match((out.content as any[])[0].text, /Do not cite anything this search did not return/);
});

test("a library that is down or missing is an error the model can work around", async () => {
  const down = new FakeLibrary([hit()]);
  down.failing = true;
  const a = await runTool("search_legal_library", { query: "إخلاء", kinds: null, limit: null }, { db: down });
  assert.equal(a.isError, true);
  assert.equal(a.flag, "library_unavailable");
  const b = await runTool("lookup_citation", { law_number: "90", year: 2001, article: 5, title: null, case_number: null, court: null }, { db: null });
  assert.equal(b.isError, true);
});

test("bad inputs are refused with a reason", async () => {
  const db = new FakeLibrary();
  const cases: [string, unknown][] = [
    ["search_legal_library", { query: "x", kinds: null, limit: null }],
    ["search_legal_library", { query: "إخلاء", kinds: ["statute"], limit: null }],
    ["search_legal_library", { query: "إخلاء", kinds: null, limit: 50 }],
    ["lookup_citation", { law_number: null, year: null, article: null, title: null, case_number: null, court: null }],
    ["lookup_citation", { law_number: "abc", year: null, article: null, title: null, case_number: null, court: null }],
    ["lookup_citation", { law_number: null, year: null, article: null, title: null, case_number: "drop table", court: null }],
    ["flag_urgent", { level: "panic", message: "x" }],
  ];
  for (const [name, input] of cases) {
    const out = await runTool(name, input, { db });
    assert.equal(out.isError, true, `${name} ${JSON.stringify(input)}`);
    assert.equal(out.flag, "bad_tool_input");
  }
  const unknown = await runTool("drop_tables", {}, { db });
  assert.equal(unknown.flag, "unknown_tool");
  // Follow-ups are a separate call after the answer, not a tool.
  const gone = await runTool("suggest_followups", { questions: ["What notice is required?"] }, { db });
  assert.deepEqual([gone.isError, gone.flag], [true, "unknown_tool"]);
});

test("exact lookup reads Arabic-Indic digits and a case number with its year", async () => {
  const judgment = hit({
    passageId: 9,
    slug: "test-judgment",
    kind: "judgment",
    titleAr: "حكم اختبار",
    number: null,
    year: 2019,
    court: "محكمة التمييز",
    caseNumber: "1234",
    decisionDate: "2019-05-01",
    issue: "إخلاء المأجور",
    holding: "نص اختباري لحكم.",
    article: null,
    articleNo: null,
    url: "https://www.jc.jo/test-judgment",
  });
  const db = new FakeLibrary([hit({ passageId: 8 }), judgment]);
  const law = await runTool("lookup_citation", { law_number: "٩٠", year: 2001, article: 5, title: null, case_number: null, court: null }, { db });
  assert.equal(db.calls[0].args.p_number, "90");
  assert.equal((law.content as any[])[0].type, "search_result");
  const c = await runTool("lookup_citation", { law_number: null, year: null, article: null, title: null, case_number: "١٢٣٤/٢٠١٩", court: null }, { db });
  assert.equal(db.calls[1].args.p_case_number, "1234");
  assert.equal(db.calls[1].args.p_year, 2019);
  const block = (c.content as any[])[0];
  assert.equal(block.title, "محكمة التمييز 1234/2019 (2019-05-01)");
  assert.match(block.content[0].text, /Judgment of محكمة التمييز, case 1234\/2019, decided 2019-05-01\./);
  assert.match(block.content[0].text, /Holding: نص اختباري لحكم\./);
  const none = await runTool("lookup_citation", { law_number: "90", year: 2001, article: 77, title: null, case_number: null, court: null }, { db });
  assert.ok(!none.isError);
  assert.match((none.content as any[])[0].text, /do not cite it as verified/);
});

test("a repealed article inside a law in force says both", () => {
  const block = toSearchResult(hit({ passageStatus: "repealed", note: "ألغيت بموجب قانون معدل" }));
  assert.match(block.content[0].text as string, /Status of this provision: repealed\. The instrument as a whole is in force\./);
  assert.match(block.content[0].text as string, /Note: ألغيت/);
  const licensed = toSearchResult(hit({ publicAccess: false }));
  assert.match(licensed.content[0].text as string, /Held under licence/);
  const commentary = toSearchResult(hit({ kind: "commentary", tier: "secondary" }));
  assert.match(commentary.content[0].text as string, /secondary: commentary, not law/);
});

test("urgent notices go to the page, cleaned", async () => {
  const u = await runTool("flag_urgent", { level: "urgent", message: "You have\u202e days to appeal." }, { db: null });
  assert.deepEqual(u.events, [{ t: "urgent", level: "urgent", text: "You have days to appeal." }]);
});

test("citation titles read the way the law is cited", () => {
  assert.equal(citationTitle(hit({ article: null })), "قانون اختبار الإيجار رقم 90 لسنة 2001");
  assert.equal(citationTitle(hit({ number: null, year: null, article: "المادة 2" })), "قانون اختبار الإيجار — المادة 2");
});

test("the library's size is counted once every few minutes", async () => {
  resetLibraryCache();
  const db = new FakeLibrary([hit({ sourceId: "a" }), hit({ sourceId: "b", kind: "judgment" }), hit({ sourceId: "b", kind: "judgment" })]);
  let calls = 0;
  const counting = { rpc: db.rpc.bind(db), counts: async () => (calls++, db.counts()) };
  assert.deepEqual(await libraryCounts(counting), { total: 2, legislation: 1, judgments: 1, commentary: 0 });
  await libraryCounts(counting);
  assert.equal(calls, 1);
});
