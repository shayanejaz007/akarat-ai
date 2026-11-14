// The service categories' icons, for the website and the admin panel (the
// app draws the same set with Flutter's Material icons, mobile/lib/features/
// services/service_icons.dart). Each is the inside of a 24×24 SVG drawn with
// round 1.8px strokes in currentColor, so it takes the colour of its text.
//
// A category's `icon` (0024_services.sql) names one of these. An unknown
// name, from a category added before its icon was drawn here, falls back
// to the toolbox: never a broken image.
//
// Constant strings, written here: safe to put into innerHTML.

export const SERVICE_ICONS = {
  plumbing:
    '<path d="M3 8h8a4 4 0 0 1 4 4v1.5"/><path d="M3 5v6"/><path d="M8 8V5"/><path d="M6 5h4"/>' +
    '<path d="M15 21a2 2 0 0 1-2-2c0-1.3 2-4 2-4s2 2.7 2 4a2 2 0 0 1-2 2Z"/>',
  bathroom:
    '<path d="M3 12h18v2a5 5 0 0 1-5 5H8a5 5 0 0 1-5-5v-2Z"/><path d="M6 12V5.5A2.5 2.5 0 0 1 10.5 4"/>' +
    '<path d="M7 19l-1 2M17 19l1 2"/>',
  electrical: '<path d="M13 2 4.5 13.5h6.5L10 22l8.5-11.5H12L13 2Z"/>',
  ac:
    '<path d="M12 2.5v19M4 7.2l16 9.6M4 16.8l16-9.6"/><path d="m9 4.2 3 2 3-2M9 19.8l3-2 3 2"/>',
  painting:
    '<rect x="3" y="3" width="14" height="6" rx="1.5"/><path d="M17 6h2.5a1 1 0 0 1 1 1v3.5a1 1 0 0 1-1 1H12v2.5"/>' +
    '<rect x="10.5" y="14" width="3" height="7" rx="1"/>',
  carpentry:
    '<path d="m13.5 6.5 3.5-3.5 4 4-3.5 3.5"/><path d="m14 6 4 4"/><path d="m15.5 8.5-11 11a1.5 1.5 0 0 1-2-2l11-11"/>',
  cleaning:
    '<path d="m11 3 1.8 4.7 4.7 1.8-4.7 1.8L11 16l-1.8-4.7-4.7-1.8 4.7-1.8L11 3Z"/>' +
    '<path d="m18.5 14 .8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2Z"/>',
  appliance:
    '<rect x="4" y="2.5" width="16" height="19" rx="2.5"/><circle cx="12" cy="13.5" r="4.5"/><path d="M7.5 6h.01M10.5 6h3"/>',
  water: '<path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11Z"/><path d="M9.5 14.5A2.5 2.5 0 0 0 12 17"/>',
  maintenance:
    '<path d="M14.7 6.3a4 4 0 0 0 5.2 5.2l-8.6 8.6a2.1 2.1 0 0 1-3-3l8.6-8.6a4 4 0 0 1-2.2-2.2Z"/>' +
    '<path d="M14.7 6.3 17 4a4 4 0 0 1 3 3l-2.3 2.3"/>',
  renovation:
    '<rect x="3" y="4" width="18" height="16" rx="1.5"/><path d="M3 9.3h18M3 14.7h18M9 4v5.3M15 9.3v5.4M9 14.7V20"/>',
  pest:
    '<rect x="8" y="7" width="8" height="13" rx="4"/><path d="M12 7V5M9.5 5.5 8 3.5M14.5 5.5 16 3.5"/>' +
    '<path d="M8 11H4M8 15.5H4.5M16 11h4M16 15.5h3.5M12 11v9"/>',
  moving:
    '<path d="M2.5 6.5h11v10h-11z"/><path d="M13.5 9.5h4l3 3.5v3.5h-7"/><circle cx="6.5" cy="17.5" r="1.8"/>' +
    '<circle cx="17" cy="17.5" r="1.8"/>',
  custom: '<circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/>',
};

export const SERVICE_ICON_NAMES = Object.keys(SERVICE_ICONS);

/** The markup for a category's icon, never empty. */
export const serviceIcon = (name) => (Object.hasOwn(SERVICE_ICONS, name) ? SERVICE_ICONS[name] : SERVICE_ICONS.maintenance);
