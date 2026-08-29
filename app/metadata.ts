import type { Metadata, Viewport } from "next";

/**
 * Canonical SEO metadata.
 *
 * The design component carries a copy of the important tags so previews look
 * right, but this is the source of truth for the shipped pages: Next renders
 * the full alternates map reliably, where sibling <link rel="alternate"> tags
 * in a client-side head can collapse.
 */

const SITE = "https://akarat.ai";

/**
 * Next 14 moved themeColor, colorScheme and the viewport tag out of the
 * metadata export into their own `viewport` export. Leaving themeColor in
 * metadata logs an "Unsupported metadata" warning on every compile.
 */
export const viewport: Viewport = {
  themeColor: "#F7F2E7",
  colorScheme: "light",
  width: "device-width",
  initialScale: 1,
};

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: {
    default: "Akarat.ai: Property search across Jordan",
    template: "%s | Akarat.ai",
  },
  description:
    "Describe the property you want in English or Arabic. Akarat.ai reads your requirements, searches its own verified listings and the wider Jordanian market, and shows how each result was matched.",
  applicationName: "Akarat.ai",
  referrer: "strict-origin-when-cross-origin",
  alternates: {
    canonical: "/en",
    languages: {
      "en-JO": "/en",
      "ar-JO": "/ar",
      "x-default": "/en",
    },
  },
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/assets/favicon-16.png", sizes: "16x16", type: "image/png" },
      { url: "/assets/favicon-32.png", sizes: "32x32", type: "image/png" },
      { url: "/assets/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/assets/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: { url: "/assets/apple-touch-icon.png", sizes: "180x180" },
  },
  openGraph: {
    type: "website",
    siteName: "Akarat.ai",
    title: "Akarat.ai: Property search across Jordan",
    description:
      "Search the usual way, or say what you are looking for in English or Arabic.",
    url: "/en",
    locale: "en_JO",
    alternateLocale: ["ar_JO"],
  },
  twitter: { card: "summary_large_image" },
  robots: { index: true, follow: true },
};

/** Per-listing metadata. Only ever built from stored facts. */
export function propertyMetadata(p: {
  id: string;
  title_en: string;
  title_ar?: string | null;
  price_jod: number;
  city?: string | null;
  deal: "sale" | "rent";
  lang: "en" | "ar";
}): Metadata {
  const ar = p.lang === "ar";
  const title = ar && p.title_ar ? p.title_ar : p.title_en;
  const price = p.price_jod.toLocaleString("en-US");
  const suffix = p.deal === "rent"
    ? (ar ? `${price} د.أ/شهر` : `${price} JOD/month`)
    : (ar ? `${price} دينار` : `${price} JOD`);

  return {
    title: `${title}, ${suffix}`,
    alternates: {
      canonical: `/${p.lang}/property/${p.id}`,
      languages: {
        "en-JO": `/en/property/${p.id}`,
        "ar-JO": `/ar/property/${p.id}`,
      },
    },
    openGraph: {
      title: `${title}, ${suffix}`,
      url: `/${p.lang}/property/${p.id}`,
      locale: ar ? "ar_JO" : "en_JO",
    },
  };
}

/**
 * schema.org for a listing page. Emit only fields the record actually holds:
 * an absent value is omitted, never guessed, which is the same rule the
 * crawler applies when reading other people's structured data.
 */
export function propertyJsonLd(p: {
  id: string;
  title_en: string;
  price_jod: number;
  currency?: string;
  deal: "sale" | "rent";
  bedrooms?: number | null;
  bathrooms?: number | null;
  area_sqm?: number | null;
  city?: string | null;
  neighborhood?: string | null;
  lat?: number | null;
  lng?: number | null;
  image?: string | null;
  published_at?: string | null;
}) {
  const node: Record<string, unknown> = {
    "@context": "https://schema.org",
    "@type": "RealEstateListing",
    name: p.title_en,
    url: `${SITE}/en/property/${p.id}`,
    offers: {
      "@type": "Offer",
      price: p.price_jod,
      priceCurrency: p.currency ?? "JOD",
      businessFunction: p.deal === "rent"
        ? "http://purl.org/goodrelations/v1#LeaseOut"
        : "http://purl.org/goodrelations/v1#Sell",
    },
  };
  if (p.bedrooms != null) node.numberOfBedrooms = p.bedrooms;
  if (p.bathrooms != null) node.numberOfBathroomsTotal = p.bathrooms;
  if (p.area_sqm != null) {
    node.floorSize = { "@type": "QuantitativeValue", value: p.area_sqm, unitCode: "MTK" };
  }
  if (p.city || p.neighborhood) {
    node.address = {
      "@type": "PostalAddress",
      addressCountry: "JO",
      addressLocality: p.city ?? undefined,
      addressRegion: p.neighborhood ?? undefined,
    };
  }
  // Coordinates are omitted unless the owner has allowed an exact location.
  if (p.lat != null && p.lng != null) {
    node.geo = { "@type": "GeoCoordinates", latitude: p.lat, longitude: p.lng };
  }
  if (p.image) node.image = p.image;
  if (p.published_at) node.datePosted = p.published_at;
  return node;
}
