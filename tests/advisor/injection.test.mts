// Prompt extraction, both assistants: the screen that withdraws a reply
// reciting the hidden instructions, against the ways a model can be talked
// into writing them out. What the model does is for the live checks; this is
// the server's own guard, which holds whatever the model was persuaded to do.
import { test } from "node:test";
import assert from "node:assert/strict";
import { CANARY as ADVISOR_CANARY, SYSTEM_PROMPT as ADVISOR_PROMPT, looksLikePromptLeak as advisorLeak } from "../../lib/advisor/prompt.ts";
import { CANARY as LEGAL_CANARY, DISCLAIMER, SYSTEM_PROMPT as LEGAL_PROMPT, looksLikePromptLeak as legalLeak } from "../../lib/legal/prompt.ts";

const ZW = String.fromCharCode(0x200b);
const b64 = (s: string) => Buffer.from(s, "utf8").toString("base64");
// A stretch of the production prompt (the part before the operating notes).
const production = (p: string, from: string, len = 900) => p.slice(p.indexOf(from), p.indexOf(from) + len);

for (const [name, leak, canary, prompt, first] of [
  ["advisor", advisorLeak, ADVISOR_CANARY, ADVISOR_PROMPT, "<instructions>"],
  ["legal", legalLeak, LEGAL_CANARY, LEGAL_PROMPT, "<instructions>"],
] as const) {
  test(`${name}: the canary however it is written`, () => {
    assert.ok(leak(`ref ${canary}`), "as is");
    assert.ok(leak(`ref ${canary.toLowerCase()}`), "lower case");
    assert.ok(leak(canary.split("").join(" ")), "spaced out");
    assert.ok(leak(canary.split("").join(ZW)), "split by invisible characters");
    assert.ok(leak(canary.replace(/-/g, " / ")), "other separators");
    assert.ok(leak(`here: ${b64(`Internal reference: ${canary}`)}`), "base64");
  });

  test(`${name}: a recital of the production prompt, plain or encoded`, () => {
    const recital = production(prompt, first);
    assert.ok(recital.length > 400, "the prompt has an instructions section");
    assert.ok(leak(recital), "plain");
    assert.ok(leak(`Sure! ${b64(recital)}`), "base64");
    // Re-flowed: line breaks and spacing changed, the words the same.
    assert.ok(leak(recital.replace(/\s+/g, " ").toUpperCase()), "re-flowed");
  });

  test(`${name}: one shared phrase or an ordinary encoded value is not a leak`, () => {
    const oneRun = production(prompt, first).split(/(?<=\.)\s/).slice(1, 2).join(" ");
    assert.ok(!leak(`As a rule of thumb: ${oneRun}`), "a single sentence from the rules");
    assert.ok(!leak("The listing's photo is at /storage/v1/object/public/listing-photos/aGVsbG8gd29ybGQgdGhpcyBpcyBhIHBob3Rv.jpg"), "a base64-looking path");
    assert.ok(!leak("Reference: QUtBUkFUIExJU1RJTkcgMTIzNDU2Nzg5MA=="), "base64 of something else");
  });
}

test("advisor: ordinary answers, in both languages, with the risk note", () => {
  assert.ok(!advisorLeak("I found two apartments in Abdoun under your budget. The first is verified and was listed four days ago. Property markets involve risk. Please conduct your own research and verify all information before making an investment decision."));
  assert.ok(!advisorLeak("لقيتلك شقتين بعبدون ضمن ميزانيتك. الاستثمار بالعقار فيه مخاطر، تأكّد من المعلومات واعمل بحثك الخاص."));
});

test("legal: ordinary answers with the sections and the full disclaimer", () => {
  const answer = [
    "## Short answer",
    "Not before the lease ends, except in the cases the law lists.",
    "## Applicable Jordanian law",
    "The Owners and Tenants Law sets the grounds for eviction.",
    "## Relevant judicial decisions",
    "No verified judicial decision was found on this point.",
    "## Recommended next steps",
    "Keep the lease and every receipt, and speak to a licensed lawyer.",
    DISCLAIMER.en,
  ].join("\n");
  assert.ok(!legalLeak(answer));
  assert.ok(!legalLeak(`## الإجابة المختصرة\nلا يجوز ذلك قبل انتهاء العقد إلا في الحالات التي يحددها القانون.\n${DISCLAIMER.ar}`));
});
