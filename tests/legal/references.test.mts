import assert from "node:assert/strict";
import { test } from "node:test";
import { RefIndex, findReferences, unverifiedReferences } from "../../lib/legal/references.ts";

const keys = (t: string) => findReferences(t).map(r => r.key);

test("Arabic references: articles, laws by number and year, and judgments", () => {
  assert.deepEqual(keys("وفقاً للمادة (5) من قانون المالكين والمستأجرين رقم 11 لسنة 1994"), ["art:5@law:11/1994", "law:11/1994"]);
  assert.deepEqual(keys("المادة ١٥ تنص على ذلك"), ["art:15"]);
  assert.deepEqual(keys("بالمادة 7 والمادة 8"), ["art:7", "art:8"]);
  assert.deepEqual(keys("قرار محكمة التمييز رقم 1234/2019"), ["case:1234/2019"]);
  assert.deepEqual(keys("تمييز حقوق ٢٢٥٠/٢٠٢٠"), ["case:2250/2020"]);
  assert.deepEqual(keys("نظام رقم (3) لسنة 2020"), ["law:3/2020"]);
});

test("English references", () => {
  assert.deepEqual(keys("Article 5 of the Landlords and Tenants Law No. 11 of 1994"), ["art:5@law:11/1994", "law:11/1994"]);
  assert.deepEqual(keys("see Art. 12, and Regulation No (3) for the year 2020"), ["art:12", "law:3/2020"]);
  assert.deepEqual(keys("Law No. 11/1994"), ["law:11/1994"]);
  assert.deepEqual(keys("Court of Cassation decision 1234/2019"), ["case:1234/2019"]);
});

test("an article and a law in different sentences are not paired", () => {
  assert.deepEqual(keys("Article 5 applies. Law No. 11 of 1994 is the main statute."), ["art:5", "law:11/1994"]);
});

test("a contract's own numbering is not a reference to law", () => {
  assert.deepEqual(keys("المادة 5 من العقد تلزمك بالدفع"), []);
  assert.deepEqual(keys("Article 7 of the lease says"), []);
  assert.deepEqual(keys("Article 7 of the Civil Code"), ["art:7"]);
});

test("dates and money are not references", () => {
  assert.deepEqual(keys("Signed on 12/05/2024 for 450 JOD; paid 3/2025."), []);
});

test("a reference is supported only by what was retrieved", () => {
  const idx = new RefIndex();
  idx.add("law:11/1994");
  idx.add("art:5@law:11/1994");
  idx.add("art:5");
  idx.addText("قضت محكمة التمييز في القرار 1234/2019 بأن ...");
  const answer =
    "وفقاً للمادة 5 من قانون المالكين والمستأجرين رقم 11 لسنة 1994، ولا تنطبق المادة 9 من القانون رقم 11 لسنة 1994. " +
    "انظر قرار التمييز 1234/2019 والقرار 999/2018. Article 5 applies.";
  const missing = unverifiedReferences(answer, idx).map(r => r.text);
  assert.ok(missing.some(t => t.includes("9")), JSON.stringify(missing));
  assert.ok(missing.includes("999/2018"), JSON.stringify(missing));
  assert.ok(!missing.some(t => t.includes("1234")), JSON.stringify(missing));
  assert.ok(!missing.some(t => /المادة 5|Article 5/.test(t)), JSON.stringify(missing));
});

test("an article named with the wrong law is unverified even if that article exists elsewhere", () => {
  const idx = new RefIndex();
  idx.add("art:5@law:11/1994");
  const missing = unverifiedReferences("Article 5 of Law No. 43 of 1976", idx);
  assert.equal(missing.length, 2);
  assert.deepEqual(missing.map(r => r.key).sort(), ["art:5@law:43/1976", "law:43/1976"]);
});

test("a retrieved page pairs its articles with its law", () => {
  const idx = new RefIndex();
  idx.addText("قانون المالكين والمستأجرين رقم 11 لسنة 1994\nالمادة 1 ...\nالمادة 5: لا يجوز ...");
  assert.ok(idx.supports("art:5@law:11/1994"));
  assert.ok(idx.supports("art:5"));
  assert.ok(idx.supports("law:11/1994"));
  assert.ok(!idx.supports("art:6@law:11/1994"));
  assert.ok(!idx.supports("case:1/2000"));
});

test("malformed keys are not accepted into the index", () => {
  const idx = new RefIndex();
  idx.add("art:NaN");
  idx.add("law:1/19");
  idx.add("anything");
  assert.deepEqual(idx.all(), []);
});
