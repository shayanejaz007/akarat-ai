// Corrections to GeoNames for scripts/build-locations.mjs, by GeoNames id.
// Each entry may set:
//   en / ar    the name to show instead
//   city       the id of the city a place belongs to (makes it a neighbourhood)
//   kind       'town' or 'hood', when GeoNames classed it wrongly
//   drop: true leaves it out (a duplicate, a camp that is gone, a wrong entry)
// Core places (data/market.js) are corrected there, not here.
export const FIXES = {
  // Karak city filed under Ma'an under an old transliteration; Karak is core.
  250624: { drop: true },
  // The village of Rum is the core place Wadi Rum.
  247399: { drop: true },
  250267: { ar: 'غور الصافي', en: 'Ghor as Safi' },
  250187: { ar: 'الطيبة (خنزيرة)', en: 'At Tayyibah (Khinzirah)' },
  247308: { ar: 'رويسة الخالدي', en: 'Ruwaysat al Khalidi' },
};
