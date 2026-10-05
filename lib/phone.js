// Country dialling codes and E.164 formatting for phone sign-in.
//
// Kept apart from lib/supabase.js because none of it talks to a server: it is
// the dropdown's contents and the rules for turning what someone typed into
// the one shape Supabase and Twilio both require.
//
// E.164 is that shape: a plus, the country code, then the national number,
// digits only, no spaces or dashes, 15 digits at the outside. Twilio rejects
// anything else, and the rejection arrives as a generic failure, so the
// normalising happens here rather than being left to the person typing.

// Jordan first: it is the market, and the default selection. The rest are the
// countries its diaspora and its buyers actually dial from.
export const COUNTRIES = [
  { id: 'jo', dial: '962', en: 'Jordan',               ar: 'الأردن',         flag: '🇯🇴', nsn: [9, 9] },
  { id: 'sa', dial: '966', en: 'Saudi Arabia',         ar: 'السعودية',       flag: '🇸🇦', nsn: [9, 9] },
  { id: 'ae', dial: '971', en: 'United Arab Emirates', ar: 'الإمارات',       flag: '🇦🇪', nsn: [9, 9] },
  { id: 'kw', dial: '965', en: 'Kuwait',               ar: 'الكويت',         flag: '🇰🇼', nsn: [8, 8] },
  { id: 'qa', dial: '974', en: 'Qatar',                ar: 'قطر',            flag: '🇶🇦', nsn: [8, 8] },
  { id: 'bh', dial: '973', en: 'Bahrain',              ar: 'البحرين',        flag: '🇧🇭', nsn: [8, 8] },
  { id: 'om', dial: '968', en: 'Oman',                 ar: 'عُمان',          flag: '🇴🇲', nsn: [8, 8] },
  { id: 'us', dial: '1',   en: 'United States',        ar: 'الولايات المتحدة', flag: '🇺🇸', nsn: [10, 10] },
  { id: 'ca', dial: '1',   en: 'Canada',               ar: 'كندا',           flag: '🇨🇦', nsn: [10, 10] },
  { id: 'gb', dial: '44',  en: 'United Kingdom',       ar: 'المملكة المتحدة', flag: '🇬🇧', nsn: [10, 10] }
];

export const DEFAULT_COUNTRY = 'jo';

export function countryById(id) {
  return COUNTRIES.find(c => c.id === id) || COUNTRIES[0];
}

// Arabic-Indic and Eastern Arabic-Indic digits, which an Arabic keyboard
// produces and which every downstream check would otherwise read as nothing.
const ARABIC_DIGITS = /[٠-٩۰-۹]/g;

function westernise(s) {
  return String(s == null ? '' : s).replace(ARABIC_DIGITS, d => {
    const c = d.charCodeAt(0);
    return String(c >= 0x06F0 ? c - 0x06F0 : c - 0x0660);
  });
}

/** Just the digits someone typed, with Arabic numerals folded to 0-9. */
export function digitsOf(input) {
  return westernise(input).replace(/\D/g, '');
}

/**
 * The national number, with the habits people actually type stripped off:
 * a leading 0 (how a local number is written everywhere in this list), and
 * the country's own dialling code if they typed that too.
 */
export function nationalNumber(input, country) {
  let d = digitsOf(input);
  // 00 is how the whole of this list writes an international call, and people
  // paste numbers in that form constantly: 00962 79... Strip it before
  // anything else, or the 00 is read as part of the number and the result is
  // too long to be valid.
  if (d.startsWith('00')) d = d.slice(2);
  if (country && d.startsWith(country.dial) && d.length > country.dial.length) {
    d = d.slice(country.dial.length);
  }
  return d.replace(/^0+/, '');
}

/** E.164, or null when what was typed cannot be one. */
export function toE164(input, countryId) {
  const c = countryById(countryId);
  const nsn = nationalNumber(input, c);
  if (!nsn) return null;
  const [min, max] = c.nsn;
  if (nsn.length < min || nsn.length > max) return null;
  const full = c.dial + nsn;
  if (full.length > 15) return null;
  return '+' + full;
}

export function isValid(input, countryId) {
  return toE164(input, countryId) !== null;
}

/** For display: +962 79 123 4567 — grouped, never re-parsed. */
export function pretty(input, countryId) {
  const c = countryById(countryId);
  const nsn = nationalNumber(input, c);
  if (!nsn) return '+' + c.dial;
  // Grouped the way each length is actually read aloud: 3-3-4 for the ten
  // digit countries, 2-3-4 for the nine, 4-4 for the eight.
  const groups = nsn.length >= 10 ? [nsn.slice(0, 3), nsn.slice(3, 6), nsn.slice(6)]
    : nsn.length === 9 ? [nsn.slice(0, 2), nsn.slice(2, 5), nsn.slice(5)]
    : nsn.length === 8 ? [nsn.slice(0, 4), nsn.slice(4)]
    : [nsn];
  return ('+' + c.dial + ' ' + groups.filter(Boolean).join(' ')).trim();
}

/** What to tell someone whose number was rejected, in their language. */
export function hintFor(countryId, ar) {
  const c = countryById(countryId);
  const [min, max] = c.nsn;
  const n = min === max ? String(min) : `${min}–${max}`;
  return ar
    ? `أدخل رقماً من ${n} أرقام بعد ${'+' + c.dial}، بدون الصفر الأول.`
    : `Enter the ${n}-digit number after +${c.dial}, without the leading zero.`;
}
