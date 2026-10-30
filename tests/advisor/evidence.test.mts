import { test } from "node:test";
import assert from "node:assert/strict";
import {
  Evidence,
  normalizeUrl,
  pageMentionsCount,
  pageMentionsPrice,
  pageSaysGone,
  verifyExternal,
  type ExternalClaim,
} from "../../lib/advisor/evidence.ts";

const BAYUT = "https://www.bayut.jo/en/property/details-53780.html";
const SOOQ = "https://jo.opensooq.com/en/search/282199094";

const claim = (over: Partial<ExternalClaim> = {}): ExternalClaim => ({
  url: BAYUT,
  title: "Villa in Dabouq",
  price: 450000,
  basis: "total",
  beds: 4,
  baths: 5,
  size: 420,
  location: "Dabouq, Amman",
  why: "Within budget, four bedrooms.",
  ...over,
});

test("normalizeUrl: one page however it is written, and nothing that is not a web page", () => {
  assert.equal(normalizeUrl("https://www.Bayut.jo/en/property/details-53780.html/?utm_source=x&utm_medium=y#gallery"), "bayut.jo/en/property/details-53780.html");
  assert.equal(normalizeUrl("http://bayut.jo/en/property/details-53780.html"), "bayut.jo/en/property/details-53780.html");
  assert.equal(normalizeUrl("javascript:alert(1)"), null);
  assert.equal(normalizeUrl("ftp://bayut.jo/x"), null);
  assert.equal(normalizeUrl("https://user:pass@bayut.jo/x"), null);
  assert.equal(normalizeUrl("not a url"), null);
});

test("pageMentionsPrice: every way a portal prints a price, and no partial matches", () => {
  assert.ok(pageMentionsPrice("Price: 120,000 JOD", 120000));
  assert.ok(pageMentionsPrice("السعر ١٢٠٬٠٠٠ دينار", 120000));
  assert.ok(pageMentionsPrice("120.000 JD", 120000));
  assert.ok(pageMentionsPrice("بسعر 120 ألف دينار", 120000));
  assert.ok(pageMentionsPrice("asking 1.2 million", 1200000));
  assert.ok(!pageMentionsPrice("Price: 1,200,000 JOD", 120000), "120,000 is not inside 1,200,000");
  assert.ok(!pageMentionsPrice("Price on request", 120000));
  assert.ok(!pageMentionsPrice("Ref 120000123", 120000));
});

test("pageMentionsCount: a figure only counts next to its unit", () => {
  assert.ok(pageMentionsCount("3 Bedrooms · 2 Bathrooms", 3, "beds"));
  assert.ok(pageMentionsCount("Bedrooms: 3", 3, "beds"));
  assert.ok(pageMentionsCount("غرف النوم: 3", 3, "beds"));
  assert.ok(pageMentionsCount("شقة 3 غرف نوم", 3, "beds"));
  assert.ok(pageMentionsCount("عدد الحمامات ٢", 2, "baths"));
  assert.ok(pageMentionsCount("Area 150 m²", 150, "size"));
  assert.ok(pageMentionsCount("المساحة 150 متر مربع", 150, "size"));
  assert.ok(!pageMentionsCount("Floor 3, building 12", 3, "beds"));
  assert.ok(!pageMentionsCount("1500 m² land", 150, "size"));
});

test("pageSaysGone: removed and expired listings, in both languages", () => {
  assert.ok(pageSaysGone("Sorry, this property is no longer available."));
  assert.ok(pageSaysGone("This ad has expired"));
  assert.ok(pageSaysGone("عذراً، الإعلان غير متوفر حالياً"));
  assert.ok(pageSaysGone("تم حذف الإعلان"));
  assert.ok(!pageSaysGone("Bright villa with garden, 4 bedrooms, available for viewing on weekends"));
});

test("verifyExternal: a URL that never came back from a search is refused", () => {
  const ev = new Evidence();
  const v = verifyExternal(claim(), ev);
  assert.ok("error" in v && /did not appear/.test(v.error));
});

test("verifyExternal: only listing portals can be listing cards", () => {
  const ev = new Evidence();
  ev.addResult({ url: "https://www.dls.gov.jo/en/fees", title: "Fees", pageAge: null });
  const v = verifyExternal(claim({ url: "https://www.dls.gov.jo/en/fees" }), ev);
  assert.ok("error" in v && /not on an approved listing portal/.test(v.error));
});

test("verifyExternal: seen only in search results, the card keeps no figures", () => {
  const ev = new Evidence();
  ev.addResult({ url: BAYUT, title: "Villa for sale in Dabouq | Bayut", pageAge: "March 3, 2026" });
  const v = verifyExternal(claim(), ev);
  assert.ok("card" in v);
  assert.equal(v.card.price, null);
  assert.equal(v.card.beds, null);
  assert.equal(v.card.size, null);
  assert.equal(v.card.checked, false);
  assert.equal(v.card.source.name, "Bayut");
  assert.equal(v.card.seen, "March 3, 2026");
  assert.ok(v.dropped.some(d => /price/.test(d)));
});

test("verifyExternal: read with web_fetch, figures on the page stay and the rest go", () => {
  const ev = new Evidence();
  ev.addResult({ url: BAYUT, title: "Villa", pageAge: null });
  ev.addPage({
    url: BAYUT,
    title: "Villa for sale in Dabouq",
    text: "Villa for sale in Dabouq, Amman. Price 450,000 JOD. 4 Bedrooms. 5 Bathrooms. Built-up area 400 m².",
    retrievedAt: "2026-10-29T09:00:00Z",
  });
  const v = verifyExternal(claim(), ev);
  assert.ok("card" in v);
  assert.equal(v.card.price, 450000);
  assert.equal(v.card.beds, 4);
  assert.equal(v.card.baths, 5);
  assert.equal(v.card.size, null, "420 m² is not on the page; 400 is");
  assert.equal(v.card.location, "Dabouq, Amman");
  assert.equal(v.card.checked, true);
  assert.deepEqual(v.dropped, ["size (not found on the page)"]);
});

test("verifyExternal: a page that says the listing is gone is refused", () => {
  const ev = new Evidence();
  ev.addPage({ url: SOOQ, title: "OpenSooq", text: "This ad is no longer available. Similar ads: ...", retrievedAt: null });
  const v = verifyExternal(claim({ url: SOOQ }), ev);
  assert.ok("error" in v && /no longer available/.test(v.error));
});

test("verifyExternal: a page web_fetch could not open is refused", () => {
  const ev = new Evidence();
  ev.addResult({ url: SOOQ, title: "x", pageAge: null });
  ev.addFailure(SOOQ);
  const v = verifyExternal(claim({ url: SOOQ }), ev);
  assert.ok("error" in v && /could not be opened/.test(v.error));
});

test("verifyExternal: a listing shown in an earlier turn can be shown again", () => {
  const ev = new Evidence();
  ev.shownExternal.set(normalizeUrl(SOOQ)!, { url: SOOQ, title: "Flat" });
  const v = verifyExternal(claim({ url: SOOQ, price: null, beds: null, baths: null, size: null, location: null }), ev);
  assert.ok("card" in v);
  assert.equal(v.card.source.host, "jo.opensooq.com");
});
