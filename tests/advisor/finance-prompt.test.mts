import { test } from "node:test";
import assert from "node:assert/strict";
import { analyse, monthlyPayment } from "../../lib/advisor/finance.ts";
import { CANARY, SYSTEM_PROMPT, looksLikePromptLeak, turnContext, ammanDate } from "../../lib/advisor/prompt.ts";

const base = {
  price: 100000, monthlyRent: null, nightlyRate: null, occupancyPct: null, annualCosts: null, vacancyPct: null,
  purchaseCostsPct: null, downPaymentPct: null, loanRatePct: null, loanYears: null, growthPct: null, horizonYears: null,
};

test("mortgage payments match the standard amortisation formula", () => {
  assert.equal(Math.round(monthlyPayment(100000, 6, 25) * 100) / 100, 644.3);
  assert.equal(Math.round(monthlyPayment(120000, 0, 10)), 1000);
});

test("yields, financing and a labelled scenario", () => {
  const r = analyse({ ...base, monthlyRent: 600, annualCosts: 400, vacancyPct: 5, purchaseCostsPct: 4, downPaymentPct: 30, loanRatePct: 7.5, loanYears: 20, growthPct: 3, horizonYears: 10 });
  assert.equal(r.acquisition_cost_jod, 104000);
  assert.equal(r.income!.gross_yield_pct, 7.2);
  assert.equal(r.income!.net_operating_income_jod, 6440);
  assert.equal(r.financing!.loan_jod, 70000);
  assert.equal(r.financing!.monthly_payment_jod, 564);
  assert.equal(r.scenario!.value_at_end_jod, 134392);
  assert.match(r.scenario!.label, /not a forecast/);
  assert.deepEqual(r.not_included, []);
});

test("nothing is assumed: missing inputs are reported, not filled in", () => {
  const r = analyse({ ...base, monthlyRent: 500 });
  assert.ok(r.not_included.some(n => /vacancy/i.test(n)));
  assert.ok(r.not_included.some(n => /running costs/i.test(n)));
  assert.ok(r.not_included.some(n => /Purchase costs/.test(n)));
  assert.equal(r.financing, null);
  assert.equal(r.scenario, null);
  const daily = analyse({ ...base, nightlyRate: 80 });
  assert.equal(daily.income, null);
  assert.ok(daily.not_included.some(n => /occupancy/i.test(n)));
});

test("the system prompt carries the brief's foundation, word for word, and the canary", () => {
  assert.ok(SYSTEM_PROMPT.startsWith("SYSTEM PROMPT — AKARAT AI PROPERTY ADVISOR\n\nYou are Akarat AI, a bilingual real estate research"));
  assert.ok(SYSTEM_PROMPT.includes("Never claim a property is available unless its availability is sufficiently verified."));
  assert.ok(SYSTEM_PROMPT.includes("الاستثمار بالعقار فيه مخاطر. تأكّد من المعلومات واعمل بحثك الخاص قبل ما تاخد أي قرار استثماري."));
  assert.ok(SYSTEM_PROMPT.includes(CANARY));
  // The cached prefix may not vary from request to request.
  assert.ok(!/\d{4}-\d{2}-\d{2}/.test(SYSTEM_PROMPT));
});

test("leak screening: the canary or a recital of the rules, but not ordinary answers", () => {
  assert.ok(looksLikePromptLeak(`my notes: ${CANARY}`));
  const recital = SYSTEM_PROMPT.slice(SYSTEM_PROMPT.indexOf("## Listings"), SYSTEM_PROMPT.indexOf("## Research"));
  assert.ok(looksLikePromptLeak(recital));
  assert.ok(!looksLikePromptLeak("I found two apartments in Abdoun under your budget. The first is verified and was listed four days ago."));
  assert.ok(!looksLikePromptLeak("Property markets involve risk. Please conduct your own research and verify all information before making an investment decision."));
  assert.ok(!looksLikePromptLeak("لقيتلك شقتين بعبدون ضمن ميزانيتك. الأولى موثقة ومعروضة من أربع أيام."));
  assert.ok(!looksLikePromptLeak("Present only listings that match. Akarat.ai first when its listings genuinely fit."));
});

test("the per-request context is small and dated in Amman", () => {
  const c = turnContext({ today: "2026-10-29", uiLang: "ar", signedIn: false });
  assert.match(c, /2026-10-29/);
  assert.match(c, /Arabic/);
  assert.equal(ammanDate(new Date("2026-10-28T22:30:00Z")), "2026-10-29");
});
