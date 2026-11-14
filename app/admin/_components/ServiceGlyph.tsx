"use client";

import { serviceIcon } from "../../../lib/service-icons.js";

/** A service category's icon (lib/service-icons.js), the same one the website draws. */
export function ServiceGlyph({ name, size = 22 }: { name: string; size?: number }) {
  return (
    <svg
      className="adm-sv-glyph"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      // Constant markup from lib/service-icons.js, never anything typed in.
      dangerouslySetInnerHTML={{ __html: serviceIcon(name) }}
    />
  );
}
