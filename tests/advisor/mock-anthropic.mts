/**
 * A stand-in for the Messages API, for the advisor's tests.
 *
 * Point the SDK at it with baseURL (or ANTHROPIC_BASE_URL for the whole
 * server) and script each reply as a list of content blocks. It streams them
 * back as the real API does: message_start, a start / deltas / stop for every
 * block, message_delta with the stop reason, message_stop. Every request is
 * kept, so a test can check exactly what was sent.
 */
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";

export type Block =
  | { type: "text"; text: string; citations?: unknown[] }
  | { type: "thinking"; thinking?: string }
  | { type: "tool_use"; id: string; name: string; input: unknown }
  | { type: "server_tool_use"; id: string; name: string; input: unknown }
  | { type: "web_search_tool_result"; tool_use_id: string; content: unknown }
  | { type: "web_fetch_tool_result"; tool_use_id: string; content: unknown }
  | { type: "fallback"; from: { model: string }; to: { model: string } };

export type Reply = {
  blocks?: Block[];
  stop?: "end_turn" | "tool_use" | "max_tokens" | "refusal" | "pause_turn";
  /** An HTTP error instead of a stream (429, 500, 529...). */
  status?: number;
  /** Milliseconds between events, to test streaming and stopping. */
  delayMs?: number;
  searches?: number;
  fetches?: number;
};

export type Seen = { body: any; headers: IncomingMessage["headers"] };

const event = (type: string, data: unknown) => `event: ${type}\ndata: ${JSON.stringify({ type, ...(data as object) })}\n\n`;

export function streamOf(reply: Reply, model = "claude-opus-5-5"): string[] {
  const blocks = reply.blocks ?? [];
  const usage = {
    input_tokens: 1200,
    output_tokens: 0,
    cache_read_input_tokens: 5400,
    cache_creation_input_tokens: 0,
    server_tool_use: { web_search_requests: reply.searches ?? 0, web_fetch_requests: reply.fetches ?? 0 },
  };
  const out: string[] = [];
  out.push(
    event("message_start", {
      message: { id: `msg_${Math.random().toString(36).slice(2)}`, type: "message", role: "assistant", model, content: [], stop_reason: null, stop_sequence: null, usage },
    })
  );
  blocks.forEach((b, index) => {
    switch (b.type) {
      case "text": {
        out.push(event("content_block_start", { index, content_block: { type: "text", text: "", ...(b.citations ? { citations: [] } : {}) } }));
        for (const c of b.citations ?? []) out.push(event("content_block_delta", { index, delta: { type: "citations_delta", citation: c } }));
        // Split like a real stream: a few characters at a time.
        for (let i = 0; i < b.text.length; i += 18) {
          out.push(event("content_block_delta", { index, delta: { type: "text_delta", text: b.text.slice(i, i + 18) } }));
        }
        break;
      }
      case "thinking":
        out.push(event("content_block_start", { index, content_block: { type: "thinking", thinking: "", signature: "" } }));
        out.push(event("content_block_delta", { index, delta: { type: "signature_delta", signature: "sig_mock" } }));
        break;
      case "tool_use":
      case "server_tool_use": {
        out.push(event("content_block_start", { index, content_block: { type: b.type, id: b.id, name: b.name, input: {} } }));
        const json = JSON.stringify(b.input);
        for (let i = 0; i < json.length; i += 40) {
          out.push(event("content_block_delta", { index, delta: { type: "input_json_delta", partial_json: json.slice(i, i + 40) } }));
        }
        break;
      }
      default:
        out.push(event("content_block_start", { index, content_block: b }));
    }
    out.push(event("content_block_stop", { index }));
  });
  out.push(
    event("message_delta", {
      delta: { stop_reason: reply.stop ?? "end_turn", stop_sequence: null },
      usage: { output_tokens: 350, server_tool_use: usage.server_tool_use },
    })
  );
  out.push(event("message_stop", {}));
  return out;
}

export async function startMock(
  handler: (body: any, seen: Seen[]) => Reply | Promise<Reply>,
  extra?: (req: IncomingMessage, res: ServerResponse, body: string) => boolean | Promise<boolean>,
  port = 0
) {
  const seen: Seen[] = [];
  const server = createServer(async (req, res) => {
    let raw = "";
    for await (const chunk of req) raw += chunk;
    if (extra && (await extra(req, res, raw))) return;
    if (req.method !== "POST" || !req.url?.startsWith("/v1/messages")) {
      res.writeHead(404, { "content-type": "application/json" }).end(JSON.stringify({ type: "error", error: { type: "not_found_error", message: req.url } }));
      return;
    }
    const body = JSON.parse(raw || "{}");
    seen.push({ body, headers: req.headers });
    let reply: Reply;
    try {
      reply = await handler(body, seen);
    } catch (e) {
      res.writeHead(500, { "content-type": "application/json" }).end(JSON.stringify({ type: "error", error: { type: "api_error", message: String(e) } }));
      return;
    }
    if (reply.status) {
      const type = reply.status === 529 ? "overloaded_error" : reply.status === 429 ? "rate_limit_error" : reply.status === 401 ? "authentication_error" : "api_error";
      res.writeHead(reply.status, { "content-type": "application/json", "request-id": "req_mock" }).end(JSON.stringify({ type: "error", error: { type, message: type } }));
      return;
    }
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", "request-id": "req_mock" });
    for (const chunk of streamOf(reply, body.model)) {
      if (res.destroyed) return;
      res.write(chunk);
      if (reply.delayMs) await new Promise(r => setTimeout(r, reply.delayMs));
    }
    res.end();
  });
  await new Promise<void>(r => server.listen(port, "127.0.0.1", () => r()));
  const bound = (server.address() as { port: number }).port;
  return {
    url: `http://127.0.0.1:${bound}`,
    seen,
    close: () => new Promise<void>(r => server.close(() => r())),
  };
}

/* ── Reading what the advisor sent ───────────────────────────────────── */

/** The tool_result blocks in the last user message of a request, by tool_use_id. */
export function toolResults(body: any): Map<string, { content: any; is_error?: boolean }> {
  const out = new Map();
  const last = [...(body.messages ?? [])].reverse().find((m: any) => m.role === "user");
  for (const b of Array.isArray(last?.content) ? last.content : []) {
    if (b.type === "tool_result") {
      let content: any = b.content;
      try {
        content = JSON.parse(typeof b.content === "string" ? b.content : b.content?.[0]?.text ?? "");
      } catch {
        /* leave as is */
      }
      out.set(b.tool_use_id, { content, is_error: b.is_error });
    }
  }
  return out;
}

/** The text of the conversation's latest user message (not a tool result). */
export function lastUserText(body: any): string {
  for (const m of [...(body.messages ?? [])].reverse()) {
    if (m.role !== "user") continue;
    if (typeof m.content === "string") return m.content;
    const t = m.content?.find?.((b: any) => b.type === "text");
    if (t) return t.text;
  }
  return "";
}

/** How many assistant messages this turn has had so far (0 on its first call). */
export function callsThisTurn(body: any): number {
  const msgs = body.messages ?? [];
  let i = msgs.length - 1;
  let n = 0;
  for (; i >= 0; i--) {
    const m = msgs[i];
    if (m.role === "user" && (typeof m.content === "string" || !m.content.some?.((b: any) => b.type === "tool_result"))) break;
    if (m.role === "assistant") n++;
  }
  return n;
}
