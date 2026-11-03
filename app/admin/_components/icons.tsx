import type { ReactNode } from "react";

/* The panel's icons: 24px grid, 1.8px round strokes, drawn in currentColor so
   they take the colour of the text beside them. Always decorative here: the
   control or text next to an icon says what it is. */

const PATHS = {
  dashboard: (
    <>
      <rect x="3" y="3" width="7.5" height="9" rx="1.8" />
      <rect x="13.5" y="3" width="7.5" height="5.5" rx="1.8" />
      <rect x="13.5" y="11.5" width="7.5" height="9.5" rx="1.8" />
      <rect x="3" y="15" width="7.5" height="6" rx="1.8" />
    </>
  ),
  building: (
    <>
      <path d="M4 21V5.5A2.5 2.5 0 0 1 6.5 3h7A2.5 2.5 0 0 1 16 5.5V21" />
      <path d="M16 9.5h2.5A1.5 1.5 0 0 1 20 11v10" />
      <path d="M2.5 21h19" />
      <path d="M8 7.5h4M8 11.5h4M8 15.5h4" />
    </>
  ),
  bed: (
    <>
      <path d="M3 5v14" />
      <path d="M3 16h18" />
      <path d="M21 19v-5.5a2.5 2.5 0 0 0-2.5-2.5H11v5" />
      <circle cx="7" cy="12.5" r="2" />
    </>
  ),
  calendar: (
    <>
      <rect x="3" y="4.5" width="18" height="16.5" rx="2.5" />
      <path d="M3 9.5h18M8 2.5v4M16 2.5v4" />
      <path d="M7.5 13.5h2M11 13.5h2M14.5 13.5h2M7.5 17h2M11 17h2" />
    </>
  ),
  inbox: (
    <>
      <path d="M21.5 12.5h-5.5l-2 3h-4l-2-3H2.5" />
      <path d="M5.4 5.1 2.5 12.5v5a2 2 0 0 0 2 2h15a2 2 0 0 0 2-2v-5l-2.9-7.4A2 2 0 0 0 16.7 4H7.3a2 2 0 0 0-1.9 1.1z" />
    </>
  ),
  users: (
    <>
      <circle cx="9" cy="8" r="3.5" />
      <path d="M2.5 20a6.5 6.5 0 0 1 13 0" />
      <path d="M16 4.6a3.5 3.5 0 0 1 0 6.8" />
      <path d="M18.5 14.2a6.5 6.5 0 0 1 3 5.8" />
    </>
  ),
  user: (
    <>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21a8 8 0 0 1 16 0" />
    </>
  ),
  flag: (
    <>
      <path d="M5 21.5V3.5" />
      <path d="M5 4h13l-2.5 4.5L18 13H5" />
    </>
  ),
  sparkles: (
    <>
      <path d="M10.5 3c.6 4.2 2.8 6.4 7 7-4.2.6-6.4 2.8-7 7-.6-4.2-2.8-6.4-7-7 4.2-.6 6.4-2.8 7-7z" />
      <path d="M18.5 14.5c.3 1.9 1.1 2.7 3 3-1.9.3-2.7 1.1-3 3-.3-1.9-1.1-2.7-3-3 1.9-.3 2.7-1.1 3-3z" />
    </>
  ),
  scale: (
    <>
      <path d="M12 3v17.5" />
      <path d="M8 20.5h8" />
      <path d="M5 7h14" />
      <path d="M5 7l-3 7a3 3 0 0 0 6 0z" />
      <path d="M19 7l-3 7a3 3 0 0 0 6 0z" />
    </>
  ),
  sliders: (
    <>
      <path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1" />
      <circle cx="15" cy="6" r="2" />
      <circle cx="9" cy="12" r="2" />
      <circle cx="17" cy="18" r="2" />
    </>
  ),
  search: (
    <>
      <circle cx="11" cy="11" r="7" />
      <path d="m20.5 20.5-4.5-4.5" />
    </>
  ),
  sun: (
    <>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2.5v2M12 19.5v2M4.6 4.6 6 6M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4" />
    </>
  ),
  moon: <path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11z" />,
  monitor: (
    <>
      <rect x="2.5" y="4" width="19" height="13" rx="2" />
      <path d="M8 21h8M12 17v4" />
    </>
  ),
  logout: (
    <>
      <path d="M9 21H5.5A2.5 2.5 0 0 1 3 18.5v-13A2.5 2.5 0 0 1 5.5 3H9" />
      <path d="m16 17 5-5-5-5" />
      <path d="M21 12H9" />
    </>
  ),
  external: (
    <>
      <path d="M14 4h6v6" />
      <path d="M20 4 10.5 13.5" />
      <path d="M19 14v4.5a1.5 1.5 0 0 1-1.5 1.5h-12A1.5 1.5 0 0 1 4 18.5v-12A1.5 1.5 0 0 1 5.5 5H10" />
    </>
  ),
  chevronRight: <path d="m9 6 6 6-6 6" />,
  chevronLeft: <path d="m15 6-6 6 6 6" />,
  chevronDown: <path d="m6 9 6 6 6-6" />,
  menu: <path d="M4 6.5h16M4 12h16M4 17.5h16" />,
  x: <path d="M18 6 6 18M6 6l12 12" />,
  check: <path d="M20 6.5 9 17.5l-5-5" />,
  alert: (
    <>
      <path d="M10.3 3.9 1.9 18a2 2 0 0 0 1.7 3h16.8a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
      <path d="M12 9.5v4M12 17h.01" />
    </>
  ),
  info: (
    <>
      <circle cx="12" cy="12" r="9.5" />
      <path d="M12 11v5.5M12 7.5h.01" />
    </>
  ),
  circleCheck: (
    <>
      <circle cx="12" cy="12" r="9.5" />
      <path d="m8 12.3 2.8 2.8 5.2-5.6" />
    </>
  ),
  circleAlert: (
    <>
      <circle cx="12" cy="12" r="9.5" />
      <path d="M12 7.5v5.5M12 16.5h.01" />
    </>
  ),
  refresh: (
    <>
      <path d="M21 12a9 9 0 1 1-3-6.7L21 8" />
      <path d="M21 3v5h-5" />
    </>
  ),
  more: (
    <>
      <circle cx="5" cy="12" r="1.3" fill="currentColor" stroke="none" />
      <circle cx="12" cy="12" r="1.3" fill="currentColor" stroke="none" />
      <circle cx="19" cy="12" r="1.3" fill="currentColor" stroke="none" />
    </>
  ),
  eye: (
    <>
      <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z" />
      <circle cx="12" cy="12" r="3" />
    </>
  ),
  eyeOff: (
    <>
      <path d="m3 3 18 18" />
      <path d="M10.6 5.1A10.6 10.6 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.2M6.6 6.6C3.9 8.4 2 12 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6" />
      <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" />
    </>
  ),
  heart: <path d="M12 20s-7.5-4.6-9.2-9.3C1.6 7.3 3.9 4 7.3 4c2 0 3.5 1 4.7 2.6C13.2 5 14.7 4 16.7 4c3.4 0 5.7 3.3 4.5 6.7C19.5 15.4 12 20 12 20z" />,
  phone: <path d="M5.5 3H9l1.8 4.5-2.3 1.4a11 11 0 0 0 6.6 6.6l1.4-2.3L21 15v3.5a2.5 2.5 0 0 1-2.5 2.5A15.5 15.5 0 0 1 3 5.5 2.5 2.5 0 0 1 5.5 3z" />,
  mail: (
    <>
      <rect x="2.5" y="4.5" width="19" height="15" rx="2.5" />
      <path d="m3 6.5 9 6.5 9-6.5" />
    </>
  ),
  message: <path d="M20.5 12a8.5 8.5 0 0 1-12.4 7.5L3.5 21l1.5-4.6A8.5 8.5 0 1 1 20.5 12z" />,
  star: <path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z" />,
  shield: (
    <>
      <path d="M12 21.5s8-3.5 8-10V5.3L12 2.5 4 5.3v6.2c0 6.5 8 10 8 10z" />
      <path d="m8.5 12 2.5 2.5 4.5-5" />
    </>
  ),
  trash: (
    <>
      <path d="M3.5 6h17" />
      <path d="M8.5 6V4.5A1.5 1.5 0 0 1 10 3h4a1.5 1.5 0 0 1 1.5 1.5V6" />
      <path d="m18.5 6-.9 13.1a2 2 0 0 1-2 1.9H8.4a2 2 0 0 1-2-1.9L5.5 6" />
      <path d="M10 10.5v6M14 10.5v6" />
    </>
  ),
  pause: (
    <>
      <rect x="6" y="5" width="4" height="14" rx="1" />
      <rect x="14" y="5" width="4" height="14" rx="1" />
    </>
  ),
  play: <path d="M7 4.5v15l12-7.5z" />,
  arrowUp: <path d="M12 19V5M5.5 11.5 12 5l6.5 6.5" />,
  arrowDown: <path d="M12 5v14M18.5 12.5 12 19l-6.5-6.5" />,
  arrowRight: <path d="M5 12h14M12.5 5.5 19 12l-6.5 6.5" />,
  globe: (
    <>
      <circle cx="12" cy="12" r="9.5" />
      <path d="M2.5 12h19" />
      <path d="M12 2.5c2.5 2.6 3.8 5.8 3.8 9.5s-1.3 6.9-3.8 9.5c-2.5-2.6-3.8-5.8-3.8-9.5S9.5 5.1 12 2.5z" />
    </>
  ),
  smartphone: (
    <>
      <rect x="6" y="2.5" width="12" height="19" rx="2.5" />
      <path d="M11 18h2" />
    </>
  ),
  activity: <path d="M2.5 12h4l3-8 5 16 3-8h4" />,
  dollar: (
    <>
      <path d="M12 2.5v19" />
      <path d="M17 6.5H9.8a3 3 0 0 0 0 6h4.4a3 3 0 0 1 0 6H6.5" />
    </>
  ),
  book: <path d="M4 19V5.5A2.5 2.5 0 0 1 6.5 3H20v13.5H6.5A2.5 2.5 0 0 0 4 19a2.5 2.5 0 0 0 2.5 2.5H20" />,
  clock: (
    <>
      <circle cx="12" cy="12" r="9.5" />
      <path d="M12 7v5l3.5 2" />
    </>
  ),
  lock: (
    <>
      <rect x="4" y="10.5" width="16" height="11" rx="2.5" />
      <path d="M8 10.5V7a4 4 0 0 1 8 0v3.5" />
    </>
  ),
  panel: (
    <>
      <rect x="3" y="3.5" width="18" height="17" rx="2.5" />
      <path d="M9.5 3.5v17" />
    </>
  ),
  copy: (
    <>
      <rect x="8.5" y="8.5" width="12" height="12" rx="2" />
      <path d="M15.5 8.5v-3a2 2 0 0 0-2-2h-8a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h3" />
    </>
  ),
  pin: (
    <>
      <path d="M12 21.5s7-6.2 7-12a7 7 0 0 0-14 0c0 5.8 7 12 7 12z" />
      <circle cx="12" cy="9.5" r="2.5" />
    </>
  ),
  image: (
    <>
      <rect x="3" y="3.5" width="18" height="17" rx="2.5" />
      <circle cx="9" cy="9.5" r="1.8" />
      <path d="m21 15.5-5-5L6.5 20.5" />
    </>
  ),
  database: (
    <>
      <ellipse cx="12" cy="5.5" rx="8" ry="3" />
      <path d="M4 5.5v13c0 1.7 3.6 3 8 3s8-1.3 8-3v-13" />
      <path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3" />
    </>
  ),
  home: (
    <>
      <path d="M3 10.5 12 3l9 7.5" />
      <path d="M5.5 9v11.5h13V9" />
    </>
  ),
  key: (
    <>
      <circle cx="8" cy="15" r="4.5" />
      <path d="m11.2 11.8 9.3-9.3M17.5 5.5l2.5 2.5M15 8l2 2" />
    </>
  ),
  layers: (
    <>
      <path d="m12 3 9 5-9 5-9-5z" />
      <path d="m3 13 9 5 9-5" />
    </>
  ),
} satisfies Record<string, ReactNode>;

export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 18, className }: { name: IconName; size?: number; className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      className={className ? `adm-icon ${className}` : "adm-icon"}
    >
      {PATHS[name]}
    </svg>
  );
}
