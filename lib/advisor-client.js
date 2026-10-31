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
// `body` and `headers` let another route reuse the reader: Ask a Lawyer
// (lib/legal-client.js) sends its own fields and the session token.
export async function streamAdvisor({ message, lang, transcript, signal, onEvent, endpoint = '/api/ai/advisor', body, headers }) {
  let res;
  try {
    res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/x-ndjson', ...(headers || {}) },
      credentials: 'same-origin',
      body: JSON.stringify(body || { message, lang, transcript: transcript || undefined }),
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
  if (status === 401) return 'sign_in';
  if (status === 403) return 'not_open';
  if (status === 404) return 'not_found';
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
      // A source without a web address (the reader's own document) is a
      // badge, not a link; its title carries the passage cited.
      const linkable = !!(s && /^https?:\/\//i.test(s.url || ''));
      const a = document.createElement(linkable ? 'a' : 'span');
      a.textContent = String(n);
      if (s) {
        if (linkable) {
          a.setAttribute('href', s.url);
          a.setAttribute('target', '_blank');
          a.setAttribute('rel', 'noopener noreferrer nofollow');
        }
        a.setAttribute('title', `${ctx.citeLabel} ${n}: ${s.title}${s.quote ? ` — “${String(s.quote).slice(0, 240)}”` : ''}`);
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
   Dictation the way people expect it: tap the microphone, say the whole
   thing, and the text arrives in the box at once, when they pause or tap
   Done. Nothing is typed into the box word by word while they speak.

   The browser's own speech recognition (Chrome, Edge, Safari, Samsung
   Internet): no audio reaches our server. Recognition happens in the
   browser's speech service, which for Chrome is Google's and for Safari is
   Apple's. Jordanian Arabic is asked for first; a browser that has no
   Jordanian model falls back to Saudi, then generic Arabic.

   Browsers differ: desktop Chrome keeps listening through pauses, Android
   Chrome and Safari often end on their own after one, and Android can
   repeat earlier words in later results. So the transcript is rebuilt from
   every result each time, a result that repeats the text before it replaces
   it, and a session that ends early is restarted while the person is still
   speaking. A pause of SILENCE_MS after speech finishes the dictation.

   Firefox and most in-app browsers have no recognition, and createVoice
   returns null there: the page hides the microphone rather than offering
   one that cannot work. */
const VOICE_LANGS = { ar: ['ar-JO', 'ar-SA', 'ar'], en: ['en-US', 'en-GB', 'en'] };
const SILENCE_MS = 2600;
const NO_SPEECH_MS = 9000;
const MAX_MS = 120_000;

export function voiceSupported() {
  return typeof window !== 'undefined' && !!(window.SpeechRecognition || window.webkitSpeechRecognition)
    && (window.isSecureContext !== false);
}

// Two stretches of speech as one text. A later stretch that repeats the
// earlier one (Android sends the whole utterance again) replaces it.
export function joinSpeech(a, b) {
  const x = (a || '').trim();
  const y = (b || '').trim();
  if (!x) return y;
  if (!y) return x;
  const lx = x.toLocaleLowerCase();
  const ly = y.toLocaleLowerCase();
  if (ly.startsWith(lx)) return y;
  if (lx.endsWith(ly)) return x;
  return `${x} ${y}`;
}

/**
 * One dictation at a time. onState reports 'listening', 'hearing' (speech
 * is coming in), 'finishing' and 'idle'; onFinal gets the whole transcript
 * once; onError gets a code when nothing usable was heard.
 *   start(lang)    begin listening ('ar' or 'en')
 *   done()         finish now and deliver what was heard
 *   cancel()       stop and discard
 *   setLang(lang)  carry on in the other language, keeping what was heard
 */
export function createVoice({ onFinal, onError, onState, silenceMs = SILENCE_MS, noSpeechMs = NO_SPEECH_MS }) {
  if (!voiceSupported()) return null;
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  let rec = null;
  let tries = [];
  let kept = '';        // from earlier sessions of this dictation
  let finals = '';      // this session's finished results
  let interim = '';     // this session's words still being recognised
  let active = false;
  let finishing = false;
  let startedAt = 0;
  let lastHeard = 0;
  let restarts = 0;
  let state = 'idle';
  let tick = null;
  let endWait = null;

  const say = st => { if (st !== state) { state = st; onState && onState(st); } };
  const heard = () => joinSpeech(kept, joinSpeech(finals, interim));
  const clear = () => {
    clearInterval(tick); tick = null;
    clearTimeout(endWait); endWait = null;
  };
  const quiet = r => {
    if (!r) return;
    r.onstart = r.onresult = r.onerror = r.onend = r.onspeechstart = null;
  };

  const deliver = () => {
    if (!active) return;
    const text = heard();
    clear();
    quiet(rec);
    active = false;
    finishing = false;
    say('idle');
    if (text) onFinal && onFinal(text);
    else onError && onError('no-speech');
  };

  const fail = code => {
    // What was said before a failure is still the person's: keep it.
    if (heard()) { deliver(); return; }
    clear();
    quiet(rec);
    try { rec && rec.abort(); } catch { /* not running */ }
    active = false;
    finishing = false;
    say('idle');
    onError && onError(code);
  };

  const begin = () => {
    finals = '';
    interim = '';
    const r = new SR();
    rec = r;
    r.lang = tries[0];
    r.interimResults = true;
    r.continuous = true;
    r.maxAlternatives = 1;
    r.onstart = () => { if (rec === r) say('listening'); };
    r.onspeechstart = () => { if (rec === r) { lastHeard = Date.now(); say('hearing'); } };
    r.onresult = e => {
      if (rec !== r) return;
      // Rebuilt from every result, not appended: browsers revise earlier ones.
      let f = '';
      let t = '';
      for (let i = 0; i < e.results.length; i++) {
        const res = e.results[i];
        const words = res && res[0] ? String(res[0].transcript || '') : '';
        if (res.isFinal) f = joinSpeech(f, words);
        else t = `${t} ${words}`.trim();
      }
      finals = f;
      interim = t;
      lastHeard = Date.now();
      if (!finishing) say('hearing');
    };
    r.onerror = e => {
      if (rec !== r) return;
      const code = e && e.error;
      // No model for this dialect: try the next one quietly.
      if ((code === 'language-not-supported' || code === 'bad-grammar') && tries.length > 1) {
        tries = tries.slice(1);
        quiet(r);
        try { r.abort(); } catch { /* already stopped */ }
        kept = joinSpeech(kept, joinSpeech(finals, interim));
        begin();
        return;
      }
      if (code === 'aborted' || code === 'no-speech') return; // onend decides
      fail(code === 'service-not-allowed' ? 'not-allowed' : code || 'other');
    };
    r.onend = () => {
      if (rec !== r) return;
      kept = joinSpeech(kept, joinSpeech(finals, interim));
      finals = '';
      interim = '';
      if (finishing) { deliver(); return; }
      const since = Date.now() - startedAt;
      // Ended by itself after the person spoke and paused: that is the end.
      if (kept && Date.now() - lastHeard >= silenceMs - 400) { deliver(); return; }
      // Ended early (a browser that stops at every pause, or a hiccup):
      // listen again while there is reason to.
      if (restarts < 8 && since < MAX_MS && (kept || since < noSpeechMs)) {
        restarts += 1;
        begin();
        return;
      }
      if (kept) deliver();
      else fail('no-speech');
    };
    try {
      r.start();
    } catch {
      fail('busy');
    }
  };

  const api = {
    start(lang) {
      if (active) return;
      tries = (VOICE_LANGS[lang] || VOICE_LANGS.en).slice();
      kept = '';
      finals = '';
      interim = '';
      active = true;
      finishing = false;
      restarts = 0;
      startedAt = Date.now();
      lastHeard = 0;
      state = 'idle';
      say('listening');
      begin();
      tick = setInterval(() => {
        if (!active || finishing) return;
        const now = Date.now();
        if (heard() && lastHeard && now - lastHeard > silenceMs) api.done();
        else if (!heard() && now - startedAt > noSpeechMs) fail('no-speech');
        else if (now - startedAt > MAX_MS) api.done();
        else if (state === 'hearing' && now - lastHeard > 900) say('listening');
      }, 200);
    },
    done() {
      if (!active || finishing) return;
      finishing = true;
      say('finishing');
      try { rec && rec.stop(); } catch { /* not running */ }
      // A recogniser that never reports its end still delivers.
      endWait = setTimeout(deliver, 1500);
    },
    cancel() {
      if (!active) return;
      clear();
      quiet(rec);
      try { rec && rec.abort(); } catch { /* not running */ }
      active = false;
      finishing = false;
      kept = finals = interim = '';
      say('idle');
    },
    setLang(lang) {
      if (!active || finishing) return;
      quiet(rec);
      try { rec && rec.abort(); } catch { /* not running */ }
      kept = heard();
      tries = (VOICE_LANGS[lang] || VOICE_LANGS.en).slice();
      begin();
    },
    // Earlier names, kept for callers that use them.
    stop() { api.done(); },
    abort() { api.cancel(); },
    get listening() { return active; },
    get startedAt() { return startedAt; }
  };
  return api;
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
