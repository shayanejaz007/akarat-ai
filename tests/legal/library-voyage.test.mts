// Embeddings and reranking, against a stand-in for Voyage's API. The key is
// set before the library is loaded, because config.ts reads it once.
import assert from "node:assert/strict";
import { test } from "node:test";
import { FakeLibrary, hit } from "./fixtures.mts";

process.env.VOYAGE_API_KEY = "test-voyage-key";
const { embed, searchLibrary } = await import("../../lib/legal/library.ts");

type Call = { url: string; body: any; auth: string | null };
const calls: Call[] = [];
let mode: "ok" | "down" | "bad" = "ok";

globalThis.fetch = (async (url: string, init: RequestInit) => {
  const body = JSON.parse(String(init.body));
  calls.push({ url, body, auth: new Headers(init.headers).get("authorization") });
  if (mode === "down") return new Response("{}", { status: 503 });
  if (url.endsWith("/embeddings")) {
    const vec = (i: number) => Array.from({ length: mode === "bad" ? 3 : 1024 }, (_, k) => (k === i ? 1 : 0));
    return Response.json({ data: body.input.map((_: string, i: number) => ({ index: i, embedding: vec(i) })) });
  }
  if (url.endsWith("/rerank")) {
    // The second document first.
    return Response.json({ data: [{ index: 1, relevance_score: 0.9 }, { index: 0, relevance_score: 0.2 }] });
  }
  return new Response("{}", { status: 404 });
}) as typeof fetch;

test("a search sends the query's embedding and reranks what comes back", async () => {
  calls.length = 0;
  mode = "ok";
  const db = new FakeLibrary([hit({ passageId: 1 }), hit({ passageId: 2, body: "نص اختباري آخر عن إخلاء المأجور" })]);
  const hits = await searchLibrary(db, "إخلاء المأجور", null, 2);
  const emb = calls.find(c => c.url.endsWith("/embeddings"))!;
  assert.equal(emb.auth, "Bearer test-voyage-key");
  assert.equal(emb.body.input_type, "query");
  assert.equal(emb.body.model, "voyage-3.5");
  const sent = String(db.calls[0].args.p_embedding);
  assert.ok(sent.startsWith("[1,0,0") && sent.split(",").length === 1024);
  assert.equal(db.calls[0].args.p_limit, 6);
  assert.deepEqual(hits?.map(h => h.passageId), [2, 1]);
});

test("if Voyage is down, search carries on with full text alone", async () => {
  mode = "down";
  const db = new FakeLibrary([hit({ passageId: 3 })]);
  const hits = await searchLibrary(db, "إخلاء", null, 3);
  assert.equal(db.calls[0].args.p_embedding, null);
  assert.deepEqual(hits?.map(h => h.passageId), [3]);
});

test("an embedding of the wrong size is never used", async () => {
  mode = "bad";
  assert.equal(await embed(["x"], "document"), null);
});
