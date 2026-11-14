// The location search behind every picker and filter (lib/places.js), on the
// real data (data/locations.js): Arabic and English, the spellings people
// type, every governorate, and an admin's changes laid over the file.
import { test } from "node:test";
import assert from "node:assert/strict";
import * as LOCATIONS from "../../data/locations.js";
import * as MARKET from "../../data/market.js";
import { createPlaces, foldAr, foldEn, withEdits } from "../../lib/places.js";

const places = createPlaces(LOCATIONS);
const top = (q: string, o: Record<string, unknown> = {}) => places.search(q, { lang: /[؀-ۿ]/.test(q) ? "ar" : "en", ...o })[0];

test("folding: Arabic article, hamza, taa marbuta and marks; English accents and articles", () => {
  assert.equal(foldAr("الزرقاء"), foldAr("الزرقا"));
  assert.equal(foldAr("إربد"), foldAr("اربد"));
  assert.equal(foldAr("حي الشميساني"), foldAr("الشميساني"));
  assert.equal(foldAr("عمّان"), foldAr("عمان"));
  assert.equal(foldEn("Aş Şuwayfiyah"), foldEn("as suwayfiyah"));
  assert.equal(foldEn("Al-Jubaiha"), foldEn("jubaiha"));
});

test("all 12 governorates, each with cities, each city in a governorate", () => {
  assert.equal(places.governorates.length, 12);
  for (const g of places.governorates) assert.ok(places.citiesOf(g.id).length > 5, g.id);
  for (const c of places.cities) assert.ok(places.gov(c.gov), c.id);
  for (const h of places.hoods) assert.ok(places.city(h.city), h.id);
});

test("every governorate is found by its English and Arabic name", () => {
  const names: [string, string][] = [
    ["Amman", "عمان"], ["Irbid", "إربد"], ["Zarqa", "الزرقاء"], ["Balqa", "البلقاء"], ["Mafraq", "المفرق"],
    ["Karak", "الكرك"], ["Jerash", "جرش"], ["Madaba", "مادبا"], ["Ajloun", "عجلون"], ["Aqaba", "العقبة"],
    ["Ma'an", "معان"], ["Tafilah", "الطفيلة"],
  ];
  for (const [en, ar] of names) {
    for (const q of [en, ar]) {
      const hits = places.search(q, { lang: /[؀-ۿ]/.test(q) ? "ar" : "en", kinds: ["gov"] });
      assert.ok(hits.length && foldEn(places.gov(hits[0].id)!.en) === foldEn(en), `${q} → ${hits[0]?.id}`);
    }
  }
});

test("the spellings people type find the right place", () => {
  const cases: [string, string, string][] = [
    ["abdoun", "hood", "abdoun"], ["abdoon", "hood", "abdoun"], ["عبدون", "hood", "abdoun"],
    ["swaifieh", "hood", "sweifieh"], ["sweifieh", "hood", "sweifieh"], ["الصويفية", "hood", "sweifieh"],
    ["shmeisani", "hood", "shmeisani"], ["الشميساني", "hood", "shmeisani"],
    ["jabal amman", "hood", "jabalamman"], ["um uthaina", "hood", "umuthaina"], ["dabouq", "hood", "dabouq"],
    ["irbid", "city", "irbid"], ["اربد", "city", "irbid"], ["الزرقا", "city", "zarqa"], ["zarka", "city", "zarqa"],
    ["petra", "city", "wadimusa"], ["salt", "city", "salt"], ["السلط", "city", "salt"],
    ["kufranja", "city", "kufrinjah"], ["ajlun", "city", "ajloun"], ["aqaba", "city", "aqaba"],
  ];
  for (const [q, kind, id] of cases) {
    const h = top(q);
    assert.ok(h, `nothing for ${q}`);
    assert.equal(`${h.kind}:${h.id}`, `${kind}:${id}`, q);
  }
});

test("picking a neighbourhood fills in its city and governorate", () => {
  const h = top("abdoun")!;
  assert.deepEqual({ g: h.governorate_id, c: h.city_id, n: h.neighborhood_id }, { g: "amman", c: "amman", n: "abdoun" });
  assert.match(h.path, /Amman/);
  const c = top("ramtha")!;
  assert.deepEqual({ g: c.governorate_id, c: c.city_id, n: c.neighborhood_id }, { g: "irbid", c: "ramtha", n: null });
});

test("a search can stay inside a governorate or a city, or a level", () => {
  assert.equal(places.search("abdoun", { gov: "irbid" }).length, 0);
  assert.ok(places.search("abdoun", { city: "amman" }).length > 0);
  assert.ok(places.search("amman", { kinds: ["hood"] }).every(h => h.kind === "hood"));
  // No levels given, or null, means every level (the website passes null).
  assert.equal(places.search("abdoun", { kinds: null })[0]?.id, "abdoun");
  assert.equal(places.search("abdoun", { kinds: [] })[0]?.id, "abdoun");
  // A governorate's hit is named as one, so it reads apart from its city.
  const gov = places.search("aqaba", { kinds: ["gov"] })[0];
  assert.equal(gov?.label, "Aqaba governorate");
  assert.equal(places.search("العقبة", { lang: "ar", kinds: ["gov"] })[0]?.label, "محافظة العقبة");
  // Typing the word asks for the governorate.
  for (const q of ["irbid governorate", "irbid gov", "محافظة إربد", "محافظه اربد"]) {
    const h = places.search(q, { lang: /[؀-ۿ]/.test(q) ? "ar" : "en" })[0];
    assert.deepEqual([h?.kind, h?.id], ["gov", "irbid"], q);
  }
});

test("every core place from data/market.js is still there, same id and city", () => {
  for (const c of MARKET.CITIES) assert.ok(places.city(c.id), c.id);
  for (const n of MARKET.NEIGHBORHOODS) assert.equal(places.hood(n.id)?.city, n.city, n.id);
});

test("no two places share an id, and same-named villages are told apart", () => {
  const ids = places.cities.map(c => c.id);
  assert.equal(new Set(ids).size, ids.length);
  const key = (gov: string, ar: string) => `${gov}|${foldAr(ar)}`;
  const seen = new Set<string>();
  for (const c of places.cities) {
    const k = key(c.gov, c.ar);
    assert.ok(!seen.has(k), `two cities called ${c.ar} in ${c.gov}`);
    seen.add(k);
  }
});

test("a listing filter on any level", () => {
  const row = { city_id: "amman", neighborhood_id: "abdoun" };
  assert.ok(places.inArea(row, { governorate_id: "amman", city_id: null, neighborhood_id: null }));
  assert.ok(places.inArea(row, { governorate_id: "amman", city_id: "amman", neighborhood_id: null }));
  assert.ok(places.inArea(row, { governorate_id: "amman", city_id: "amman", neighborhood_id: "abdoun" }));
  assert.ok(!places.inArea(row, { governorate_id: "irbid", city_id: null, neighborhood_id: null }));
  assert.ok(!places.inArea(row, { governorate_id: "amman", city_id: "amman", neighborhood_id: "khalda" }));
  assert.ok(places.inArea(row, null));
});

test("an admin's changes: a rename, a new area, a place switched off", () => {
  const edited = createPlaces(withEdits(LOCATIONS, {
    cities: [{ id: "sahab", governorate_id: "amman", name_en: "Sahab City", name_ar: "مدينة سحاب", aliases: ["sahhab"], active: true }],
    neighborhoods: [
      { id: "new-hood", city_id: "amman", name_en: "Green Hills", name_ar: "التلال الخضراء", aliases: [], active: true },
      { id: "dabouq", city_id: "amman", name_en: "Dabouq", name_ar: "دابوق", active: false },
    ],
  }));
  assert.equal(edited.city("sahab")!.en, "Sahab City");
  assert.equal(edited.search("sahhab")[0]?.id, "sahab");
  assert.equal(edited.search("green hills")[0]?.id, "new-hood");
  assert.equal(edited.search("التلال الخضراء", { lang: "ar" })[0]?.city_id, "amman");
  assert.equal(edited.hood("dabouq"), null);
  assert.ok(!edited.search("dabouq").some(h => h.id === "dabouq"));
  // Switched off is hidden from pickers, but a listing already there still reads.
  assert.equal(edited.placeLabel("amman", "dabouq", "en"), "Dabouq · Amman");
  assert.ok(!edited.hoodsOf("amman").some(h => h.id === "dabouq"));
});

test("place labels in both languages", () => {
  assert.equal(places.placeLabel("amman", "abdoun", "en"), "Abdoun · Amman");
  assert.equal(places.placeLabel("amman", "abdoun", "ar"), "عبدون · عمان");
  assert.equal(places.placeLabel("ramtha", null, "en"), "Ramtha");
  assert.equal(places.placeLabel(null, null, "en"), "");
  assert.equal(places.govLabel("irbid", "en"), "Irbid governorate");
  assert.equal(places.govLabel("irbid", "ar"), "محافظة إربد");
});
