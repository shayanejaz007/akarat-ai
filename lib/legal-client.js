// The browser side of Ask a Lawyer (/api/legal/*).
//
//   askLawyer        the answer as it is written, one event per line
//   uploadDocument   a file into the conversation
//   …                history, deletion, feedback and status
//   splitSections    an answer cut at its headings, for the page's sections
//   renderAnswer     a section drawn safely, with unverified references marked
//   saveSummary      a research summary to print, save as PDF, or keep
//
// Every call carries the person's session token: these routes serve signed-in
// accounts only. No key lives here, and nothing here talks to anyone but our
// own server.

import { renderReply, streamAdvisor } from './advisor-client.js';

const auth = token => (token ? { Authorization: `Bearer ${token}` } : {});

export function askLawyer({ token, conversationId, message, lang, signal, onEvent }) {
  return streamAdvisor({
    endpoint: '/api/legal/ask',
    body: { conversationId: conversationId || undefined, message, lang },
    headers: auth(token),
    signal,
    onEvent
  });
}

const STATUS_ERROR = { 401: 'sign_in', 403: 'not_open', 404: 'not_found', 409: 'too_many_documents', 413: 'too_big', 429: 'rate_limited', 503: 'not_configured' };

async function call(method, url, token, body) {
  try {
    const form = typeof FormData !== 'undefined' && body instanceof FormData;
    const res = await fetch(url, {
      method,
      headers: { ...auth(token), ...(body && !form ? { 'Content-Type': 'application/json' } : {}) },
      body: form ? body : body ? JSON.stringify(body) : undefined,
      credentials: 'same-origin'
    });
    let data = null;
    try { data = await res.json(); } catch { /* not JSON */ }
    if (!res.ok) return { error: (data && typeof data.error === 'string' && data.error) || STATUS_ERROR[res.status] || 'unavailable' };
    return data || {};
  } catch {
    return { error: 'offline' };
  }
}

export const legalStatus = token => call('GET', '/api/legal/status', token);
export const listConversations = token => call('GET', '/api/legal/conversations', token);
export const getConversation = (token, id) => call('GET', `/api/legal/conversations?id=${encodeURIComponent(id)}`, token);
export const deleteConversation = (token, id) =>
  call('DELETE', id === 'all' ? '/api/legal/conversations?all=1' : `/api/legal/conversations?id=${encodeURIComponent(id)}`, token);
export const deleteDocument = (token, id) => call('DELETE', `/api/legal/documents?id=${encodeURIComponent(id)}`, token);
export const sendFeedback = (token, messageId, kind, note) => call('POST', '/api/legal/feedback', token, { messageId, kind, note: note || '' });

export function uploadDocument(token, file, conversationId) {
  const fd = new FormData();
  fd.append('file', file, file.name);
  if (conversationId) fd.append('conversationId', conversationId);
  return call('POST', '/api/legal/documents', token, fd);
}

// What the file picker offers. The server reads the bytes, not this list.
export const ACCEPT = '.pdf,.docx,.txt,.jpg,.jpeg,.png,.webp,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,text/plain,image/jpeg,image/png,image/webp';
export const MAX_BYTES = 4_000_000;

/* ── Sections ────────────────────────────────────────────────────────────
   An answer arrives with "## " headings (Short answer, Applicable Jordanian
   law, …). Text before the first heading is a section with no title. */
export function splitSections(text) {
  const out = [];
  let cur = { title: '', body: '' };
  for (const line of String(text || '').split('\n')) {
    const m = /^#{1,3}\s+(.+?)\s*#*\s*$/.exec(line.trim());
    if (m && /^#{1,3}\s/.test(line.trim())) {
      if (cur.title || cur.body.trim()) out.push(cur);
      cur = { title: m[1].replace(/\*\*/g, ''), body: '' };
    } else {
      cur.body += (cur.body ? '\n' : '') + line;
    }
  }
  if (cur.title || cur.body.trim()) out.push(cur);
  return out;
}

/* ── Drawing a section ───────────────────────────────────────────────────
   renderReply draws the text with elements and text nodes only. Then each
   reference the server could not tie to a retrieved source is wrapped, where
   it appears, in a mark the page styles and explains. */
export function renderAnswer(el, text, opts = {}) {
  if (!el) return;
  renderReply(el, text, opts);
  const refs = (opts.unverified || []).filter(r => typeof r === 'string' && r.length >= 2);
  const key = `${el.__rendered}|${refs.join('|')}`;
  if (!refs.length || el.__marked === key) return;
  el.__marked = key;
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (let node of nodes) {
    if (node.parentElement && node.parentElement.closest('[data-unverified]')) continue;
    for (;;) {
      const s = node.nodeValue;
      let at = -1;
      let ref = '';
      for (const r of refs) {
        const i = s.indexOf(r);
        if (i >= 0 && (at < 0 || i < at)) { at = i; ref = r; }
      }
      if (at < 0) break;
      const rest = node.splitText(at);
      const after = rest.splitText(ref.length);
      const mark = document.createElement('mark');
      mark.setAttribute('data-unverified', 'true');
      mark.setAttribute('title', opts.unverifiedLabel || 'Not verified');
      mark.textContent = ref;
      rest.parentNode.replaceChild(mark, rest);
      node = after;
    }
  }
}

/* ── The research summary ────────────────────────────────────────────────
   A standalone page built from escaped text only, with a policy that lets
   it run nothing: printed (or saved as PDF) on a computer, downloaded as a
   file on a phone, where printing from a page is unreliable. */
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// The answer's Markdown, small subset, after escaping: bold, lists, paragraphs.
function mdToHtml(text) {
  const lines = String(text || '').replace(/[\ue000-\uf8ff]/g, '').split('\n');
  const out = [];
  let list = null;
  const inline = s => esc(s).replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  for (const raw of lines) {
    const line = raw.trim();
    const bullet = /^[-*•]\s+(.*)$/.exec(line) || /^\d{1,3}[.)]\s+(.*)$/.exec(line);
    if (bullet) {
      if (!list) { list = []; }
      list.push(`<li>${inline(bullet[1])}</li>`);
      continue;
    }
    if (list) { out.push(`<ul>${list.join('')}</ul>`); list = null; }
    if (line.startsWith('|') && /^\|?\s*:?-{2,}/.test(line)) continue;
    if (line) out.push(`<p>${inline(line.replace(/^\|/, '').replace(/\|$/, '').replace(/\s*\|\s*/g, ' · '))}</p>`);
  }
  if (list) out.push(`<ul>${list.join('')}</ul>`);
  return out.join('\n');
}

export function summaryHtml({ lang, heading, title, date, exchanges, labels }) {
  const dir = lang === 'ar' ? 'rtl' : 'ltr';
  const body = exchanges.map(x => {
    const sections = splitSections(x.answer).map(s =>
      `${s.title ? `<h3>${esc(s.title)}</h3>` : ''}${mdToHtml(s.body)}`).join('\n');
    const sources = x.sources.length
      ? `<h4>${esc(labels.sources)}</h4><ol>${x.sources.map(s =>
          `<li><span class="k">${esc(s.label)}</span> ${esc(s.title)}${s.url ? `<br><span class="u">${esc(s.url)}</span>` : ''}${s.meta ? `<br><span class="m">${esc(s.meta)}</span>` : ''}</li>`).join('')}</ol>`
      : '';
    const unverified = x.unverified.length
      ? `<p class="warn"><strong>${esc(labels.unverified)}</strong> ${esc(x.unverified.join('، '))}</p>`
      : '';
    return `<section><p class="q"><strong>${esc(labels.question)}</strong> ${esc(x.question)}</p>${sections}${unverified}${sources}<p class="d">${esc(x.disclaimer)}</p></section>`;
  }).join('\n<hr>\n');
  return `<!doctype html><html lang="${lang}" dir="${dir}"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(heading)} — ${esc(title)}</title>
<style>
  body { font: 14px/1.6 -apple-system, "Segoe UI", "IBM Plex Sans Arabic", Tahoma, sans-serif; color: #17170F; max-width: 760px; margin: 32px auto; padding: 0 20px; }
  header { border-bottom: 2px solid #007A3D; padding-bottom: 12px; margin-bottom: 20px; }
  header h1 { font-size: 20px; margin: 0 0 4px; } header p { margin: 0; color: #555; font-size: 12px; }
  h3 { font-size: 15px; margin: 18px 0 6px; color: #00693A; } h4 { font-size: 13px; margin: 16px 0 6px; }
  .q { background: #F4F1EA; padding: 10px 12px; border-radius: 8px; }
  ol { padding-inline-start: 20px; } li { margin: 6px 0; font-size: 12.5px; }
  .k { font-weight: 600; } .u { color: #00693A; word-break: break-all; } .m { color: #666; }
  .warn { color: #8A0D1A; font-size: 12.5px; } .d { color: #555; font-size: 11.5px; border-top: 1px solid #ddd; padding-top: 8px; margin-top: 16px; }
  hr { border: 0; border-top: 1px solid #ccc; margin: 28px 0; }
  @media print { body { margin: 0; } a { color: inherit; } }
</style></head><body>
<header><h1>${esc(heading)}</h1><p>${esc(title)} · ${esc(date)}</p></header>
${body}
</body></html>`;
}

export function saveSummary(html, filename) {
  const download = () => {
    const url = URL.createObjectURL(new Blob([html], { type: 'text/html;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  };
  const touch = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
  if (touch) { download(); return 'downloaded'; }
  try {
    const frame = document.createElement('iframe');
    frame.setAttribute('aria-hidden', 'true');
    frame.style.cssText = 'position:fixed;inset-inline-end:0;bottom:0;width:0;height:0;border:0;';
    document.body.appendChild(frame);
    const d = frame.contentDocument;
    d.open();
    d.write(html);
    d.close();
    setTimeout(() => {
      try { frame.contentWindow.focus(); frame.contentWindow.print(); } catch { download(); }
      setTimeout(() => frame.remove(), 60000);
    }, 250);
    return 'printed';
  } catch {
    download();
    return 'downloaded';
  }
}
