import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { test } from "node:test";
import { AAD, dataKeyReady, fingerprint, open, openBytes, openText, resetKeys, seal, sealBytes } from "../../lib/legal/crypto.ts";
import { redact } from "../../lib/legal/redact.ts";

const KEY_A = randomBytes(32).toString("base64");
const KEY_B = randomBytes(32).toString("hex");

function useKeys(current?: string, previous?: string) {
  if (current) process.env.LEGAL_DATA_KEY = current;
  else delete process.env.LEGAL_DATA_KEY;
  if (previous) process.env.LEGAL_DATA_KEY_PREVIOUS = previous;
  else delete process.env.LEGAL_DATA_KEY_PREVIOUS;
  resetKeys();
}

test("sealed text opens only with the same key and the same binding", () => {
  useKeys(KEY_A);
  const aad = AAD.message("c1", "user");
  const s = seal("سؤالي عن عقد الإيجار", aad);
  assert.ok(!s.includes("عقد"));
  assert.equal(openText(s, aad), "سؤالي عن عقد الإيجار");
  // Moved to another conversation, or relabelled as the assistant's: refused.
  assert.equal(openText(s, AAD.message("c2", "user")), null);
  assert.equal(openText(s, AAD.message("c1", "assistant")), null);
});

test("two seals of the same text differ, and any change to one is caught", () => {
  useKeys(KEY_A);
  const a = seal("same", "x");
  const b = seal("same", "x");
  assert.notEqual(a, b);
  const flipped = a.slice(0, -2) + (a.at(-2) === "A" ? "B" : "A") + a.at(-1);
  assert.equal(open(flipped, "x"), null);
  assert.equal(open("garbage", "x"), null);
  assert.equal(open(null, "x"), null);
});

test("a new key takes over while the previous one still opens old rows", () => {
  useKeys(KEY_A);
  const old = seal("kept from before", "x");
  useKeys(KEY_B, KEY_A);
  assert.equal(openText(old, "x"), "kept from before");
  const fresh = seal("written now", "x");
  useKeys(KEY_B);
  assert.equal(openText(fresh, "x"), "written now");
  assert.equal(openText(old, "x"), null);
});

test("files are sealed as bytes, without base64 growth", () => {
  useKeys(KEY_A);
  const data = randomBytes(100_000);
  const sealed = sealBytes(data, AAD.docBody("c1", "d1"));
  assert.equal(sealed.length, data.length + 8 + 28);
  assert.deepEqual(openBytes(sealed, AAD.docBody("c1", "d1")), data);
  assert.equal(openBytes(sealed, AAD.docBody("c1", "d2")), null);
  assert.equal(openBytes(null, "x"), null);
});

test("no key, or a key of the wrong length, means nothing is sealed", () => {
  useKeys();
  assert.equal(dataKeyReady(), false);
  assert.throws(() => seal("x", "y"));
  useKeys(randomBytes(16).toString("base64"));
  assert.equal(dataKeyReady(), false);
  useKeys(KEY_A);
  assert.equal(dataKeyReady(), true);
});

test("fingerprints are keyed", () => {
  useKeys(KEY_A);
  const doc = Buffer.from("the same lease");
  const a = fingerprint(doc);
  assert.equal(a, fingerprint(doc));
  useKeys(KEY_B);
  assert.notEqual(fingerprint(doc), a);
});

test("redaction masks identifiers and leaves the rest", () => {
  const out = redact(
    "My landlord (ahmad.k@example.jo, 0791234567, +962 6 555 1234) wants my national number 9876543210, IBAN JO71 CBJO 0000 0000 0000 1234 5678 90 and card 4111 1111 1111 1111. Rent is 450 JOD since 2021."
  );
  assert.ok(!out.includes("ahmad"));
  assert.ok(!out.includes("0791234567"));
  assert.ok(!out.includes("555 1234"));
  assert.ok(!out.includes("9876543210"));
  assert.ok(!out.includes("CBJO"));
  assert.ok(!out.includes("4111"));
  assert.match(out, /\[email\]/);
  assert.match(out, /\[phone\]/);
  assert.match(out, /\[ID number\]/);
  assert.match(out, /\[IBAN\]/);
  assert.match(out, /\[card number\]/);
  assert.match(out, /Rent is 450 JOD since 2021\./);
});

test("redaction reads Arabic-Indic digits too", () => {
  assert.equal(redact("رقمي ٠٧٩١٢٣٤٥٦٧"), "رقمي [phone]");
  assert.equal(redact("الرقم الوطني ٩٨٧٦٥٤٣٢١٠"), "الرقم الوطني [ID number]");
});
