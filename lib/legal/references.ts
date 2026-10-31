/**
 * Legal references in an answer, and whether each one is backed by a source
 * retrieved for it.
 *
 * The model is told to give an article, law or case number only when a
 * retrieved source contains it. This is the check that does not depend on
 * it listening: every reference in the finished answer is matched against
 * what was actually retrieved (library passages, official pages read, the
 * user's own documents, and references verified in earlier answers), and
 * the ones that match nothing are shown to the reader as unverified and
 * counted in the provenance log.
 *
 * Keys:  art:5            an article number
 *        law:11/1994      a law, regulation or instructions by number and year
 *        case:1234/2019   a judgment by case number and year
 *        art:5@law:11/1994  an article named together with its law
 * An article named with its law must be found in that law, not merely in
 * some law.
 */

export type Reference = { text: string; key: string };

const latin = (s: string) =>
  s.replace(/[٠-٩]/g, d => String(d.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, d => String(d.charCodeAt(0) - 0x06f0));
const num = (s: string) => String(Number(latin(s)));

const D = "[0-9٠-٩۰-۹]";

type Pattern = { re: RegExp; kind: "art" | "law" | "case" };

const PATTERNS: Pattern[] = [
  // Law No. 11 of 1994 · Regulation No (3) for the year 2020 · Law No. 11/1994
  { kind: "law", re: new RegExp(`\\b(?:law|regulation|by-?law|instructions?|decree|code)\\s+no\\.?\\s*\\(?\\s*(${D}{1,4})\\s*\\)?\\s*(?:(?:of|for)\\s*(?:the\\s+year\\s+)?|\\/\\s*)(${D}{4})`, "gi") },
  // رقم (11) لسنة 1994
  { kind: "law", re: new RegExp(`رقم\\s*\\(?\\s*(${D}{1,4})\\s*\\)?\\s*لسن[ةه]\\s*\\(?\\s*(${D}{4})`, "g") },
  // قانون ... رقم 11/1994
  { kind: "law", re: new RegExp(`(?:قانون|نظام|تعليمات)[^.\\n؛]{0,40}?رقم\\s*\\(?\\s*(${D}{1,4})\\s*\\)?\\s*\\/\\s*(${D}{4})`, "g") },
  // Article 5 · Articles (5) · Art. 5
  { kind: "art", re: new RegExp(`\\b(?:articles?|art\\.)\\s*\\(?\\s*(${D}{1,4})(?:\\s*\\))?`, "gi") },
  // المادة 5 · المادة (5) · للمادة · بالمادة · والمادة · مادة · المواد
  { kind: "art", re: new RegExp(`(?<![ء-ي])(?:[وفبل]{0,2}(?:ال)?ماد[ةه]|[وفبل]{0,2}المواد|[وفبل]{0,2}المادتين)\\s*\\(?\\s*(${D}{1,4})(?:\\s*\\))?`, "g") },
  // A judgment: a case number and year near a word for a court or a ruling.
  {
    kind: "case",
    re: new RegExp(
      `(?:تمييز|التمييز|محكمة|قرار|القرار|حكم|الحكم|القضية|قضية|الدعوى|دعوى|cassation|court|case|judgment|judgement|decision|ruling)[^.\\n؛]{0,40}?(?:^|[^0-9٠-٩۰-۹])(${D}{1,6})\\s*\\/\\s*(${D}{4})(?![0-9٠-٩۰-۹])`,
      "gi"
    ),
  },
];

// "Article 5 of the lease", "المادة 5 من العقد": the document's own numbering,
// not a law's.
const OF_CONTRACT =
  /^\s*\)?\s*(?:من\s+(?:هذا\s+)?(?:العقد|عقد|الاتفاقي[ةه]|اتفاقي[ةه]|المستند)|في\s+(?:العقد|عقدك)|of\s+(?:the|your|this)\s+(?:contract|lease|agreement|document))/i;

/** Every reference in a text, in order, with the words that make it. */
export function findReferences(text: string): Reference[] {
  const hits: { at: number; end: number; ref: Reference }[] = [];
  for (const { re, kind } of PATTERNS) {
    re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text))) {
      if (kind === "art" && OF_CONTRACT.test(text.slice(m.index + m[0].length, m.index + m[0].length + 40))) continue;
      const shown = m[0].replace(/^[^\p{L}]+/u, "").trim();
      const key = kind === "art" ? `art:${num(m[1])}` : `${kind}:${num(m[1])}/${num(m[2])}`;
      hits.push({ at: m.index, end: m.index + m[0].length, ref: { text: kind === "case" ? caseText(shown) : shown, key } });
      if (m[0].length === 0) re.lastIndex++;
    }
  }
  hits.sort((a, b) => a.at - b.at);

  // An article is that law's article when the law follows closely, in the
  // same sentence, joined by "of" ("من", "of", "under"): "Article 5 of Law
  // No. 11 of 1994". "Article 12, and Law No. 3 of 2020" lists two things.
  const out: Reference[] = [];
  for (let i = 0; i < hits.length; i++) {
    const h = hits[i];
    if (h.ref.key.startsWith("art:")) {
      const law = hits.slice(i + 1).find(x => x.ref.key.startsWith("law:"));
      const gap = law ? text.slice(h.end, law.at) : "";
      if (law && law.at - h.end <= 90 && !/[.؟?!\n]/.test(gap) && /^\s*\)?\s*(?:(?:of|from|under|in)\b|من|في|بموجب)/i.test(gap)) {
        out.push({ text: h.ref.text, key: `${h.ref.key}@${law.ref.key}` });
        continue;
      }
    }
    out.push(h.ref);
  }
  return out;
}

// For a case, the number itself is what the reader needs to see marked.
function caseText(shown: string): string {
  const m = new RegExp(`${D}{1,6}\\s*\\/\\s*${D}{4}`).exec(shown);
  return m ? m[0] : shown;
}

/** What has been retrieved, as reference keys. */
export class RefIndex {
  private keys = new Set<string>();

  add(key: string) {
    if (/^(art:\d+|law:\d+\/\d{4}|case:\d+\/\d{4}|art:\d+@law:\d+\/\d{4})$/.test(key)) this.keys.add(key);
  }

  /** A retrieved text: every reference in it, and every article paired with every law it names. */
  addText(text: string) {
    if (!text) return;
    const refs = findReferences(text);
    const arts = new Set<string>();
    const laws = new Set<string>();
    for (const r of refs) {
      const [base, law] = r.key.split("@");
      this.add(base);
      if (law) this.add(law);
      if (base.startsWith("art:")) arts.add(base);
      if (law) laws.add(law);
      if (base.startsWith("law:")) laws.add(base);
    }
    // A page of one law: its articles belong to it. A page naming several
    // laws pairs each article with each, which is lenient but bounded.
    if (laws.size <= 12) for (const a of arts) for (const l of laws) this.add(`${a}@${l}`);
  }

  supports(key: string): boolean {
    if (this.keys.has(key)) return true;
    // A bare article or law is supported by any pair that contains it.
    if (!key.includes("@")) {
      for (const k of this.keys) if (k.startsWith(`${key}@`) || k.endsWith(`@${key}`)) return true;
    }
    return false;
  }

  all(): string[] {
    return [...this.keys];
  }
}

/** The references in an answer that nothing retrieved supports, each once. */
export function unverifiedReferences(answer: string, index: RefIndex): Reference[] {
  const seen = new Set<string>();
  const out: Reference[] = [];
  for (const r of findReferences(answer)) {
    if (index.supports(r.key) || seen.has(r.text)) continue;
    seen.add(r.text);
    out.push(r);
  }
  return out;
}
