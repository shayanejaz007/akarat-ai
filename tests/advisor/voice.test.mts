import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";

// A stand-in for the browser's speech recognition, driven by the test.
type Fake = {
  lang: string; continuous: boolean; interimResults: boolean;
  started: boolean; stopped: boolean; aborted: boolean;
  onstart?: () => void; onresult?: (e: unknown) => void; onerror?: (e: unknown) => void; onend?: () => void; onspeechstart?: () => void;
  start(): void; stop(): void; abort(): void;
};
const made: Fake[] = [];
class FakeSR {
  lang = ""; continuous = false; interimResults = false;
  started = false; stopped = false; aborted = false;
  onstart?: () => void; onresult?: (e: unknown) => void; onerror?: (e: unknown) => void; onend?: () => void; onspeechstart?: () => void;
  constructor() { made.push(this as unknown as Fake); }
  start() { this.started = true; setTimeout(() => this.onstart?.(), 1); }
  // Like a browser: stop() finalises what was being recognised, then ends.
  stop() { this.stopped = true; setTimeout(() => this.onend?.(), 5); }
  abort() { this.aborted = true; }
}
(globalThis as any).window = { SpeechRecognition: FakeSR, isSecureContext: true };

const { createVoice, joinSpeech } = await import("../../lib/advisor-client.js");

const last = () => made[made.length - 1];
const results = (...items: [string, boolean][]) => ({ resultIndex: 0, results: items.map(([t, f]) => Object.assign([{ transcript: t }], { isFinal: f })) });
const wait = (ms: number) => new Promise(r => setTimeout(r, ms));

function dictation(o: { silenceMs?: number; noSpeechMs?: number } = {}) {
  const got: { states: string[]; final: string[]; errors: string[] } = { states: [], final: [], errors: [] };
  const v = createVoice({
    onState: (s: string) => got.states.push(s),
    onFinal: (t: string) => got.final.push(t),
    onError: (c: string) => got.errors.push(c),
    silenceMs: o.silenceMs ?? 60_000,
    noSpeechMs: o.noSpeechMs ?? 60_000,
  })!;
  return { v, got };
}

beforeEach(() => { made.length = 0; });

test("joinSpeech: a repeat of the earlier words replaces them; new words are added", () => {
  assert.equal(joinSpeech("", "hello"), "hello");
  assert.equal(joinSpeech("apartments in", "apartments in Khalda"), "apartments in Khalda");
  assert.equal(joinSpeech("apartments in Khalda", "Khalda"), "apartments in Khalda");
  assert.equal(joinSpeech("apartments in Khalda", "with a garden"), "apartments in Khalda with a garden");
  assert.equal(joinSpeech("بدي شقة", "بدي شقة بعبدون"), "بدي شقة بعبدون");
});

test("nothing reaches the page while speaking; Done delivers the whole transcript once", async () => {
  const { v, got } = dictation();
  v.start("en");
  await wait(5);
  const r = last();
  assert.equal(r.lang, "en-US");
  assert.equal(r.continuous, true);
  r.onspeechstart?.();
  r.onresult?.(results(["apartments in", false]));
  r.onresult?.(results(["apartments in Khalda", true], ["with a", false]));
  assert.deepEqual(got.final, [], "no words before the end");
  assert.ok(got.states.includes("hearing"));
  v.done();
  assert.equal(got.states.at(-1), "finishing");
  r.onresult?.(results(["apartments in Khalda", true], ["with a garden", true]));
  await wait(20);
  assert.deepEqual(got.final, ["apartments in Khalda with a garden"]);
  assert.equal(got.states.at(-1), "idle");
  assert.equal(v.listening, false);
});

test("a pause after speech finishes by itself", async () => {
  const { v, got } = dictation({ silenceMs: 300 });
  v.start("ar");
  await wait(5);
  assert.equal(last().lang, "ar-JO");
  last().onresult?.(results(["بدي شقة بعمان بسعر أقل من ٧٠ ألف دينار", true]));
  await wait(700);
  assert.deepEqual(got.final, ["بدي شقة بعمان بسعر أقل من ٧٠ ألف دينار"]);
});

test("Android's repeated results are not doubled", async () => {
  const { v, got } = dictation();
  v.start("en");
  await wait(5);
  last().onresult?.(results(["three bedrooms", true], ["three bedrooms in Abdoun", true]));
  v.done();
  await wait(20);
  assert.deepEqual(got.final, ["three bedrooms in Abdoun"]);
});

test("a browser that stops at every pause is restarted, and the words are kept", async () => {
  const { v, got } = dictation({ silenceMs: 60_000 });
  v.start("en");
  await wait(5);
  const first = last();
  first.onresult?.(results(["a villa in Dabouq", true]));
  first.onend?.();
  await wait(5);
  assert.equal(made.length, 2, "listening again");
  last().onresult?.(results(["under 600,000", true]));
  v.done();
  await wait(20);
  assert.deepEqual(got.final, ["a villa in Dabouq under 600,000"]);
});

test("cancel discards everything", async () => {
  const { v, got } = dictation();
  v.start("en");
  await wait(5);
  last().onresult?.(results(["never mind", true]));
  v.cancel();
  await wait(20);
  assert.deepEqual(got.final, []);
  assert.deepEqual(got.errors, []);
  assert.equal(last().aborted, true);
  assert.equal(got.states.at(-1), "idle");
});

test("silence from the start is reported, not left listening", async () => {
  const { v, got } = dictation({ noSpeechMs: 300 });
  v.start("en");
  await wait(700);
  assert.deepEqual(got.errors, ["no-speech"]);
  assert.equal(v.listening, false);
});

test("a blocked microphone is reported; words heard before a failure are kept", async () => {
  let d = dictation();
  d.v.start("en");
  await wait(5);
  last().onerror?.({ error: "service-not-allowed" });
  assert.deepEqual(d.got.errors, ["not-allowed"]);

  d = dictation();
  d.v.start("en");
  await wait(5);
  last().onresult?.(results(["flats in Khalda", true]));
  last().onerror?.({ error: "network" });
  assert.deepEqual(d.got.final, ["flats in Khalda"]);
  assert.deepEqual(d.got.errors, []);
});

test("an unsupported dialect falls back quietly; switching language keeps what was said", async () => {
  const { v, got } = dictation();
  v.start("ar");
  await wait(5);
  last().onerror?.({ error: "language-not-supported" });
  await wait(5);
  assert.equal(last().lang, "ar-SA");
  last().onresult?.(results(["شقة", true]));
  v.setLang("en");
  await wait(5);
  assert.equal(last().lang, "en-US");
  last().onresult?.(results(["with a garden", true]));
  v.done();
  await wait(20);
  assert.deepEqual(got.final, ["شقة with a garden"]);
});
