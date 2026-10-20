import type { MetadataRoute } from "next";
import { listActiveListings } from "../lib/listing-server";

/**
 * Dynamic sitemap.
 *
 * Without this, nothing links to a property page from anywhere a crawler can
 * reach: the marketplace grid is client-rendered, so its cards do not exist in
 * the served HTML. The sitemap is how listings get discovered at all.
 */
export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const SITE = "https://akarat.ai";
  const now = new Date();

  const roots: MetadataRoute.Sitemap = [
    { url: `${SITE}/en`, lastModified: now, changeFrequency: "daily", priority: 1 },
    { url: `${SITE}/ar`, lastModified: now, changeFrequency: "daily", priority: 1 },
    // The policy pages are listed because things ask for their URL — an app
    // store, a payment provider, a partner onboarding form — and a URL that
    // nothing links to is one a crawler never confirms exists.
    { url: `${SITE}/en/privacy`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: `${SITE}/ar/privacy`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: `${SITE}/en/terms`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: `${SITE}/ar/terms`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: `${SITE}/en/data-deletion`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: `${SITE}/ar/data-deletion`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
  ];

  const rows = await listActiveListings();

  const listings = rows.flatMap((row) => {
    const at = new Date(row.updated_at || row.published_at || row.created_at);
    return (["en", "ar"] as const).map((lang) => ({
      url: `${SITE}/${lang}/property/${row.id}`,
      lastModified: at,
      changeFrequency: "weekly" as const,
      priority: 0.8,
    }));
  });

  return [...roots, ...listings];
}
