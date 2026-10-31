/**
 * Identifiers masked wherever text leaves the person's own conversation:
 * feedback notes, the question-and-answer snapshot a reviewer's report
 * carries to the admin panel, and conversation titles in the history list.
 * The conversation itself is not redacted: the person needs their own facts,
 * and it is sealed and theirs alone.
 *
 * Masked: email addresses, phone numbers (Jordanian and international),
 * Jordanian national numbers (ten digits), IBANs, and payment card numbers.
 */

const latin = (s: string) =>
  s.replace(/[٠-٩]/g, d => String(d.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, d => String(d.charCodeAt(0) - 0x06f0));

const RULES: [RegExp, string][] = [
  [/[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}/gu, "[email]"],
  [/\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){3,7}(?:\s?[A-Z0-9]{1,4})?\b/g, "[IBAN]"],
  [/\b(?:\d[ -]?){13,19}\b/g, "[card number]"],
  [/(?:\+|00)\d{1,3}[\s-]?\(?\d{1,4}\)?(?:[\s-]?\d{2,4}){2,4}/g, "[phone]"],
  [/\b0?7[789]\d{7}\b/g, "[phone]"],
  [/\b\d{10}\b/g, "[ID number]"],
];

export function redact(text: string): string {
  let s = latin(text);
  for (const [re, label] of RULES) s = s.replace(re, label);
  return s;
}
