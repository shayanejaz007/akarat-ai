import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getListing, type Listing } from "../../../../lib/listing-server";
import { CITIES, NEIGHBORHOODS, TYPES, AMENITIES } from "../../../../lib/reference";

/**
 * Server-rendered listing page.
 *
 * The marketplace itself is a client-rendered document, which means a crawler
 * that does not execute JavaScript sees a page with no listings, titles or
 * prices in it. This route is the answer to that: real HTML per property,
 * with the structured data search engines actually read.
 *
 * It also gives a listing a URL for the first time. Before this, a property
 * existed only as client state, so there was no link to share.
 *
 * Revalidated rather than rendered per request — a listing changes rarely and
 * a crawler should not be able to drive database load.
 */

export const revalidate = 300;
export const dynamicParams = true;

const SITE = "https://akarat.ai";
type Lang = "en" | "ar";

export function generateStaticParams() {
  return [{ lang: "en" }, { lang: "ar" }];
}

function asLang(v: string): Lang {
  return v === "ar" ? "ar" : "en";
}

function loc(list: { id: string; en: string; ar: string }[], id: string | null, lang: Lang) {
  const hit = list.find((x) => x.id === id);
  return hit ? (lang === "ar" ? hit.ar : hit.en) : "";
}

function titleOf(row: Listing, lang: Lang) {
  return (lang === "ar" ? row.title_ar : row.title_en) || row.title_en || row.title_ar || "";
}

function placeOf(row: Listing, lang: Lang) {
  return [
    loc(NEIGHBORHOODS, row.neighborhood_id, lang),
    loc(CITIES, row.city_id, lang),
  ].filter(Boolean).join(lang === "ar" ? " ، " : ", ");
}

function priceOf(row: Listing, lang: Lang) {
  const n = new Intl.NumberFormat(lang === "ar" ? "ar-JO" : "en-JO").format(row.price_jod);
  const jod = lang === "ar" ? "دينار" : "JOD";
  if (row.deal === "rent") return `${n} ${jod}${lang === "ar" ? " / شهرياً" : " / month"}`;
  return `${n} ${jod}`;
}

function descriptionOf(row: Listing, lang: Lang) {
  const p = row.payload || {};
  const written = (lang === "ar" ? p.description_ar : p.description_en)
    || p.description_en || p.description_ar || "";
  if (written.trim()) return written.trim();
  // Listings are not required to carry a description, so build one from the
  // columns rather than shipping an empty meta description.
  const bits = [
    loc(TYPES, row.property_type, lang),
    placeOf(row, lang),
    row.bedrooms ? `${row.bedrooms} ${lang === "ar" ? "غرف نوم" : "bedrooms"}` : "",
    row.area_sqm ? `${row.area_sqm} m²` : "",
    priceOf(row, lang),
  ].filter(Boolean);
  return bits.join(lang === "ar" ? " · " : " · ");
}

function firstImage(row: Listing) {
  return (row.payload.images || []).find(
    (m) => m?.url && m.type !== "video" && !/\.(mp4|webm|mov|m4v)(\?|#|$)/i.test(m.url)
  )?.url;
}

export async function generateMetadata(
  { params }: { params: { lang: string; id: string } }
): Promise<Metadata> {
  const lang = asLang(params.lang);
  const row = await getListing(params.id);
  if (!row) return { title: lang === "ar" ? "الإعلان غير موجود" : "Listing not found" };

  const title = `${titleOf(row, lang)} — ${priceOf(row, lang)}`;
  const description = descriptionOf(row, lang).slice(0, 300);
  const image = firstImage(row);

  return {
    title,
    description,
    alternates: {
      canonical: `/${lang}/property/${row.id}`,
      languages: {
        "en-JO": `/en/property/${row.id}`,
        "ar-JO": `/ar/property/${row.id}`,
        "x-default": `/en/property/${row.id}`,
      },
    },
    openGraph: {
      type: "article",
      title,
      description,
      url: `/${lang}/property/${row.id}`,
      locale: lang === "ar" ? "ar_JO" : "en_JO",
      images: image ? [{ url: image }] : undefined,
    },
    twitter: {
      card: image ? "summary_large_image" : "summary",
      title,
      description,
      images: image ? [image] : undefined,
    },
  };
}

export default async function PropertyPage(
  { params }: { params: { lang: string; id: string } }
) {
  const lang = asLang(params.lang);
  const ar = lang === "ar";
  const row = await getListing(params.id);
  if (!row) notFound();

  const title = titleOf(row, lang);
  const place = placeOf(row, lang);
  const media = (row.payload.images || []).filter((m) => m?.url);
  const cover = firstImage(row);

  const facts = ([
    [ar ? "النوع" : "Type", loc(TYPES, row.property_type, lang)],
    [ar ? "غرف النوم" : "Bedrooms", row.bedrooms ? String(row.bedrooms) : ""],
    [ar ? "الحمامات" : "Bathrooms", row.bathrooms ? String(row.bathrooms) : ""],
    [ar ? "المساحة" : "Area", row.area_sqm ? `${row.area_sqm} m²` : ""],
    [ar ? "مساحة الأرض" : "Land", row.land_sqm ? `${row.land_sqm} m²` : ""],
    [ar ? "سنة البناء" : "Year built", row.year_built ? String(row.year_built) : ""],
  ] as [string, string][]).filter(([, v]) => v);

  const phone = ((row.payload.contact && row.payload.contact.phone) || "").trim();
  const telHref = phone ? `tel:${phone.replace(/[^\d+]/g, "")}` : "";

  const amenities = (row.payload.amenities || [])
    .map((id) => loc(AMENITIES, id, lang))
    .filter(Boolean);

  // schema.org RealEstateListing. This is the part search engines parse into
  // rich results; the visible markup below is for the human who lands here.
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "RealEstateListing",
    "@id": `${SITE}/${lang}/property/${row.id}`,
    url: `${SITE}/${lang}/property/${row.id}`,
    name: title,
    description: descriptionOf(row, lang),
    inLanguage: ar ? "ar-JO" : "en-JO",
    datePosted: row.published_at || row.created_at,
    image: media.filter((m) => m.type !== "video").map((m) => m.url),
    offers: {
      "@type": "Offer",
      price: row.price_jod,
      priceCurrency: "JOD",
      availability: "https://schema.org/InStock",
      businessFunction:
        row.deal === "rent"
          ? "http://purl.org/goodrelations/v1#LeaseOut"
          : "http://purl.org/goodrelations/v1#Sell",
    },
    ...(phone ? { telephone: phone } : {}),
    address: {
      "@type": "PostalAddress",
      addressCountry: "JO",
      addressLocality: loc(CITIES, row.city_id, lang) || undefined,
      addressRegion: loc(NEIGHBORHOODS, row.neighborhood_id, lang) || undefined,
    },
    ...(row.area_sqm
      ? { floorSize: { "@type": "QuantitativeValue", value: row.area_sqm, unitCode: "MTK" } }
      : {}),
    ...(row.bedrooms ? { numberOfBedrooms: row.bedrooms } : {}),
    ...(row.bathrooms ? { numberOfBathroomsTotal: row.bathrooms } : {}),
  };

  const ink = "#17170F";
  const cream = "#F7F2E7";
  const green = "#007A3D";

  return (
    <main
      dir={ar ? "rtl" : "ltr"}
      lang={ar ? "ar" : "en"}
      style={{
        background: cream,
        color: ink,
        minHeight: "100vh",
        margin: 0,
        fontFamily: "system-ui, -apple-system, 'Segoe UI', sans-serif",
        fontWeight: 300,
      }}
    >
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <div style={{ maxWidth: 940, margin: "0 auto", padding: "28px 20px 72px" }}>
        <a
          href={`/${lang}`}
          style={{ display: "inline-flex", alignItems: "center", gap: 10, textDecoration: "none", color: ink }}
        >
          <img src="/assets/akarat-mark.png" alt="" width={26} height={35} />
          <span style={{ fontWeight: 600, fontSize: 17 }}>Akarat.ai</span>
        </a>

        <h1 style={{ fontSize: 30, fontWeight: 600, margin: "26px 0 6px", lineHeight: 1.25 }}>
          {title}
        </h1>
        {place && (
          <p style={{ margin: "0 0 4px", fontSize: 15, color: "rgba(23,23,15,0.62)" }}>{place}</p>
        )}
        <p style={{ margin: "0 0 22px", fontSize: 23, fontWeight: 600, color: green }}>
          {priceOf(row, lang)}
        </p>

        {cover && (
          <img
            src={cover}
            alt={title}
            style={{
              width: "100%", maxHeight: 460, objectFit: "cover",
              borderRadius: 20, display: "block", background: "#EDE7D9",
            }}
          />
        )}

        {media.length > 1 && (
          <div
            style={{
              display: "grid", gap: 10, marginTop: 10,
              gridTemplateColumns: "repeat(auto-fill, minmax(150px, 1fr))",
            }}
          >
            {media.slice(1).map((m, i) =>
              m.type === "video" ? (
                <video
                  key={i}
                  src={m.url}
                  controls
                  preload="metadata"
                  style={{ width: "100%", aspectRatio: "4 / 3", objectFit: "cover", borderRadius: 14, background: ink }}
                />
              ) : (
                <img
                  key={i}
                  src={m.url}
                  alt=""
                  style={{ width: "100%", aspectRatio: "4 / 3", objectFit: "cover", borderRadius: 14, background: "#EDE7D9" }}
                />
              )
            )}
          </div>
        )}

        {facts.length > 0 && (
          <>
            <h2 style={{ fontSize: 18, fontWeight: 600, margin: "30px 0 12px" }}>
              {ar ? "المواصفات" : "Specifications"}
            </h2>
            <dl
              style={{
                display: "grid", gap: 12, margin: 0,
                gridTemplateColumns: "repeat(auto-fill, minmax(150px, 1fr))",
              }}
            >
              {facts.map(([k, v]) => (
                <div key={k}>
                  <dt style={{ fontSize: 12, color: "rgba(23,23,15,0.55)" }}>{k}</dt>
                  <dd style={{ margin: "3px 0 0", fontSize: 15.5, fontWeight: 500 }}>{v}</dd>
                </div>
              ))}
            </dl>
          </>
        )}

        {descriptionOf(row, lang) && (
          <>
            <h2 style={{ fontSize: 18, fontWeight: 600, margin: "30px 0 10px" }}>
              {ar ? "الوصف" : "About this property"}
            </h2>
            <p style={{ margin: 0, fontSize: 15.5, lineHeight: 1.65, whiteSpace: "pre-wrap" }}>
              {descriptionOf(row, lang)}
            </p>
          </>
        )}

        {amenities.length > 0 && (
          <>
            <h2 style={{ fontSize: 18, fontWeight: 600, margin: "30px 0 10px" }}>
              {ar ? "المرافق" : "Amenities"}
            </h2>
            <ul style={{ display: "flex", flexWrap: "wrap", gap: 8, margin: 0, padding: 0, listStyle: "none" }}>
              {amenities.map((a) => (
                <li
                  key={a}
                  style={{
                    padding: "6px 12px", borderRadius: 100, fontSize: 13,
                    border: "1px solid rgba(23,23,15,0.16)", background: "#FFFFFF",
                  }}
                >
                  {a}
                </li>
              ))}
            </ul>
          </>
        )}

        {phone && (
          <p style={{ marginTop: 34, marginBottom: 0 }}>
            <a
              href={telHref}
              style={{
                display: "inline-block", padding: "13px 22px", borderRadius: 100,
                background: green, color: "#FFFFFF", textDecoration: "none",
                fontSize: 15, fontWeight: 500, fontVariantNumeric: "tabular-nums",
              }}
            >
              {ar ? `اتصل: ${phone}` : `Call ${phone}`}
            </a>
          </p>
        )}

        <p style={{ marginTop: phone ? 14 : 34 }}>
          <a
            href={`/${lang}?property=${row.id}`}
            style={{
              display: "inline-block", padding: "13px 22px", borderRadius: 100,
              background: phone ? "transparent" : green,
              color: phone ? green : "#FFFFFF",
              border: phone ? `1px solid ${green}` : "none",
              textDecoration: "none", fontSize: 15, fontWeight: 500,
            }}
          >
            {ar ? "افتح على Akarat.ai" : "Open on Akarat.ai"}
          </a>
        </p>

        <p style={{ marginTop: 18, fontSize: 13 }}>
          <a href={`/${ar ? "en" : "ar"}/property/${row.id}`} style={{ color: green }}>
            {ar ? "View in English" : "اعرض بالعربية"}
          </a>
        </p>
      </div>
    </main>
  );
}
