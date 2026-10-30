// The browser side of the AI property advisor (POST /api/ai/advisor).
//
// Four jobs, none of which needs the page's state:
//   streamAdvisor   reads the reply as it is written, one event per line
//   renderReply     draws the reply's text into an element, safely
//   createVoice     speech to text, in Arabic or English
//   saveThread /    keeps the conversation for this browser tab
//   loadThread
//
// No key lives here. The browser sends text to our own route and gets text,
// cards and links back; it never talks to a model or a third party itself.

/* ── The stream ──────────────────────────────────────────────────────────
   application/x-ndjson: one JSON object per line. A line that will not parse
   is skipped rather than ending the reply; the server never sends one, so a
   bad line means a proxy mangled something, and the rest is still worth
   showing. */
export async function streamAdvisor({ message, lang, transcript, signal, onEvent, endpoint = '/api/ai/advisor' }) {
  let res;
  try {
    res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/x-ndjson' },
      credentials: 'same-origin',
      body: JSON.stringify({ message, lang, transcript: transcript || undefined }),
      signal
    });
  } catch (e) {
    if (signal && signal.aborted) return { ended: 'stopped' };
    onEvent({ t: 'error', code: 'offline' });
    return { ended: 'error' };
  }

  if (!res.body) {
    onEvent({ t: 'error', code: res.ok ? 'unavailable' : statusCode(res.status) });
    return { ended: 'error' };
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let ended = null;
  const handle = line => {
    if (!line.trim()) return;
    let ev;
    try { ev = JSON.parse(line); } catch { return; }
    if (!ev || typeof ev.t !== 'string') return;
    if (ev.t === 'done') ended = 'done';
    if (ev.t === 'error') ended = 'error';
    onEvent(ev);
  };
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        handle(buffer.slice(0, nl));
        buffer = buffer.slice(nl + 1);
      }
    }
    buffer += decoder.decode();
    handle(buffer);
  } catch (e) {
    if (signal && signal.aborted) return { ended: 'stopped' };
    if (!ended) onEvent({ t: 'error', code: 'interrupted' });
    return { ended: 'error' };
  }
  // A response that closed without saying how it ended was cut off on the way.
  if (!ended) {
    onEvent({ t: 'error', code: res.ok ? 'interrupted' : statusCode(res.status) });
    return { ended: 'error' };
  }
  return { ended };
}

function statusCode(status) {
  if (status === 429) return 'rate_limited';
  if (status === 503) return 'not_configured';
  if (status === 413) return 'too_long';
  if (status === 400) return 'bad_request';
  return 'unavailable';
}

/* ── Rendering a reply ───────────────────────────────────────────────────
   The model's text is Markdown-ish. It is drawn with createElement and text
   nodes only: never innerHTML, so nothing the model writes (or a web page it
   read persuades it to write) can become markup or script.

   Supported: paragraphs, line breaks, **bold**, *italic*, `code`, bullet and
   numbered lists, simple tables, and [label](url) links. A link is only a
   link when it points somewhere the reply has a reason to send people: this
   site, or a host in `hosts` (the reply's own sources and listings). Anything
   else stays plain text.

   Citations arrive as \ue000 1,2 \ue001 markers, put there by the page from
   the server's cite events; the server strips that range from model text, so
   no marker can be forged. */
const CITE = /\ue000([\d,]+)\ue001/g;

export function renderReply(el, text, { sources = [], hosts = [], citeLabel = 'Source' } = {}) {
  if (!el) return;
  const key = text + '\u0000' + sources.length + '\u0000' + hosts.join(',');
  if (el.__rendered === key) return;
  el.__rendered = key;
  while (el.firstChild) el.removeChild(el.firstChild);
  const allowed = new Set(['akarat.ai', ...hosts.map(h => String(h).replace(/^www\./, '').toLowerCase())]);
  const bySource = new Map(sources.map(s => [s.n, s]));
  const ctx = { allowed, bySource, citeLabel };
  for (const block of blocks(String(text || ''))) el.appendChild(renderBlock(block, ctx));
}

function blocks(text) {
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  let para = [];
  const flush = () => { if (para.length) { out.push({ type: 'p', lines: para }); para = []; } };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    if (!trimmed) { flush(); continue; }
    // A table: a header row, a |---| separator, then rows.
    if (/^\|.*\|$/.test(trimmed) && i + 1 < lines.length && /^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$/.test(lines[i + 1].trim())) {
      flush();
      const rows = [cells(trimmed)];
      i += 2;
      while (i < lines.length && /^\|.*\|$/.test(lines[i].trim())) { rows.push(cells(lines[i].trim())); i++; }
      i--;
      out.push({ type: 'table', rows });
      continue;
    }
    const bullet = /^\s*[-*•]\s+(.*)$/.exec(line);
    const number = /^\s*(\d{1,3})[.)]\s+(.*)$/.exec(line);
    if (bullet || number) {
      flush();
      const type = bullet ? 'ul' : 'ol';
      const last = out[out.length - 1];
      const item = bullet ? bullet[1] : number[2];
      if (last && last.type === type) last.items.push(item);
      else out.push({ type, items: [item], start: number ? Number(number[1]) : 1 });
      continue;
    }
    const heading = /^#{1,6}\s+(.*)$/.exec(trimmed);
    if (heading) { flush(); out.push({ type: 'h', text: heading[1] }); continue; }
    para.push(line);
  }
  flush();
  return out;
}

const cells = row => row.replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());

function renderBlock(b, ctx) {
  if (b.type === 'p') {
    const p = document.createElement('p');
    p.setAttribute('dir', 'auto');
    b.lines.forEach((line, i) => {
      if (i) p.appendChild(document.createElement('br'));
      inline(p, line.trim(), ctx);
    });
    return p;
  }
  if (b.type === 'h') {
    const p = document.createElement('p');
    p.setAttribute('dir', 'auto');
    p.setAttribute('data-md', 'h');
    const strong = document.createElement('strong');
    inline(strong, b.text, ctx);
    p.appendChild(strong);
    return p;
  }
  if (b.type === 'ul' || b.type === 'ol') {
    const list = document.createElement(b.type);
    list.setAttribute('dir', 'auto');
    if (b.type === 'ol' && b.start > 1) list.setAttribute('start', String(b.start));
    for (const item of b.items) {
      const li = document.createElement('li');
      inline(li, item, ctx);
      list.appendChild(li);
    }
    return list;
  }
  // table
  const wrap = document.createElement('div');
  wrap.setAttribute('data-md', 'tablewrap');
  const table = document.createElement('table');
  table.setAttribute('dir', 'auto');
  b.rows.forEach((row, r) => {
    const tr = document.createElement('tr');
    for (const cell of row) {
      const td = document.createElement(r === 0 ? 'th' : 'td');
      inline(td, cell, ctx);
      tr.appendChild(td);
    }
    if (r === 0) {
      const thead = document.createElement('thead');
      thead.appendChild(tr);
      table.appendChild(thead);
    } else {
      let tbody = table.querySelector('tbody');
      if (!tbody) { tbody = document.createElement('tbody'); table.appendChild(tbody); }
      tbody.appendChild(tr);
    }
  });
  wrap.appendChild(table);
  return wrap;
}

// Inline spans, left to right. Each pattern is tried at the earliest position
// it matches; text between matches is plain text.
const INLINE = [
  { re: /\ue000([\d,]+)\ue001/y, kind: 'cite' },
  { re: /\*\*([^*\n]+?)\*\*/y, kind: 'strong' },
  { re: /__([^_\n]+?)__/y, kind: 'strong' },
  { re: /\*([^*\s][^*\n]*?)\*/y, kind: 'em' },
  { re: /`([^`\n]+)`/y, kind: 'code' },
  { re: /\[([^\]\n]{1,200})\]\((https?:\/\/[^\s)]{1,500})\)/y, kind: 'link' }
];
const STARTS = /[\ue000*_`[]/g;

function inline(parent, text, ctx) {
  let i = 0;
  let plain = '';
  const flushPlain = () => { if (plain) { parent.appendChild(document.createTextNode(plain)); plain = ''; } };
  while (i < text.length) {
    STARTS.lastIndex = i;
    const m = STARTS.exec(text);
    if (!m) { plain += text.slice(i); break; }
    plain += text.slice(i, m.index);
    i = m.index;
    let matched = false;
    for (const { re, kind } of INLINE) {
      re.lastIndex = i;
      const hit = re.exec(text);
      if (!hit) continue;
      // Read the end before span() recurses: the nested pass reuses these
      // same regex objects and moves their lastIndex.
      const end = re.lastIndex;
      flushPlain();
      parent.appendChild(span(kind, hit, ctx));
      i = end;
      matched = true;
      break;
    }
    if (!matched) { plain += text[i]; i += 1; }
  }
  flushPlain();
}

function span(kind, hit, ctx) {
  if (kind === 'cite') {
    const sup = document.createElement('sup');
    sup.setAttribute('data-md', 'cite');
    hit[1].split(',').map(Number).filter(Boolean).forEach(n => {
      const s = ctx.bySource.get(n);
      const a = document.createElement(s ? 'a' : 'span');
      a.textContent = String(n);
      if (s) {
        a.setAttribute('href', s.url);
        a.setAttribute('target', '_blank');
        a.setAttribute('rel', 'noopener noreferrer nofollow');
        a.setAttribute('title', `${ctx.citeLabel} ${n}: ${s.title}`);
      }
      sup.appendChild(a);
    });
    return sup;
  }
  if (kind === 'link') {
    const [, label, href] = hit;
    let host = '';
    try { host = new URL(href).hostname.replace(/^www\./, '').toLowerCase(); } catch { /* not a URL */ }
    const ok = host && [...ctx.allowed].some(h => host === h || host.endsWith('.' + h));
    if (!ok) return document.createTextNode(label);
    const a = document.createElement('a');
    a.textContent = label;
    a.setAttribute('href', href);
    a.setAttribute('target', '_blank');
    a.setAttribute('rel', 'noopener noreferrer nofollow');
    return a;
  }
  const el = document.createElement(kind);
  if (kind === 'code') el.textContent = hit[1];
  else inline(el, hit[1], ctx);
  return el;
}

/* ── Voice ───────────────────────────────────────────────────────────────
   The browser's own speech recognition (Chrome, Edge, Safari, Samsung
   Internet): no audio reaches our server. Recognition happens in the
   browser's speech service, which for Chrome is Google's and for Safari is
   Apple's. Jordanian Arabic is asked for first; a browser that has no
   Jordanian model falls back to Saudi, then generic Arabic.

   Firefox and most in-app browsers have no recognition, and createVoice
   returns null there: the page hides the microphone rather than offering
   one that cannot work. */
const VOICE_LANGS = { ar: ['ar-JO', 'ar-SA', 'ar'], en: ['en-US', 'en-GB', 'en'] };

export function voiceSupported() {
  return typeof window !== 'undefined' && !!(window.SpeechRecognition || window.webkitSpeechRecognition)
    && (window.isSecureContext !== false);
}

export function createVoice({ onInterim, onFinal, onError, onState }) {
  if (!voiceSupported()) return null;
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  let rec = null;
  let tries = [];
  let finalText = '';
  let listening = false;
  let stopped = false;

  const begin = () => {
    rec = new SR();
    rec.lang = tries[0];
    rec.interimResults = true;
    rec.continuous = false;
    rec.maxAlternatives = 1;
    rec.onstart = () => { listening = true; onState && onState('listening'); };
    rec.onresult = e => {
      let interim = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        if (r.isFinal) finalText += (finalText ? ' ' : '') + r[0].transcript.trim();
        else interim += r[0].transcript;
      }
      onInterim && onInterim((finalText + (interim ? ' ' + interim : '')).trim());
    };
    rec.onerror = e => {
      const code = e && e.error;
      // No model for this dialect: try the next one quietly.
      if ((code === 'language-not-supported' || code === 'bad-grammar') && tries.length > 1) {
        tries = tries.slice(1);
        rec.onend = null;
        try { rec.abort(); } catch { /* already stopped */ }
        begin();
        return;
      }
      if (code === 'aborted' && stopped) return;
      onError && onError(code === 'service-not-allowed' ? 'not-allowed' : code || 'unknown');
    };
    rec.onend = () => {
      listening = false;
      onState && onState('idle');
      if (finalText) onFinal && onFinal(finalText);
    };
    try {
      rec.start();
    } catch (e) {
      onError && onError('busy');
      onState && onState('idle');
    }
  };

  return {
    start(lang) {
      if (listening) return;
      tries = (VOICE_LANGS[lang] || VOICE_LANGS.en).slice();
      finalText = '';
      stopped = false;
      begin();
    },
    stop() {
      stopped = true;
      if (rec) { try { rec.stop(); } catch { /* not running */ } }
    },
    abort() {
      stopped = true;
      finalText = '';
      if (rec) { rec.onend = null; try { rec.abort(); } catch { /* not running */ } }
      listening = false;
      onState && onState('idle');
    },
    get listening() { return listening; }
  };
}

/* ── Keeping the conversation ────────────────────────────────────────────
   sessionStorage: this tab, until it closes. Long enough for "back" from a
   listing to find the conversation where it was, short enough that a shared
   computer does not keep someone's search. Storage can be full, blocked or
   absent (private windows, embedded browsers); every access is guarded and
   the page works without it. */
const KEY = 'akarat.advisor.v1';
const MAX_BYTES = 900_000;

export function saveThread(state) {
  try {
    let json = JSON.stringify(state);
    // Too big: drop the oldest exchanges until it fits.
    let thread = state.thread || [];
    while (json.length > MAX_BYTES && thread.length > 2) {
      thread = thread.slice(2);
      json = JSON.stringify({ ...state, thread });
    }
    sessionStorage.setItem(KEY, json);
  } catch { /* storage unavailable: the conversation lives in memory only */ }
}

export function loadThread() {
  try {
    const raw = sessionStorage.getItem(KEY);
    if (!raw) return null;
    const v = JSON.parse(raw);
    return v && Array.isArray(v.thread) ? v : null;
  } catch {
    return null;
  }
}

export function clearThread() {
  try { sessionStorage.removeItem(KEY); } catch { /* nothing to clear */ }
}
