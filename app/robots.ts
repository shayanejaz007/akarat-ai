import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // Nothing here is secret — RLS is what protects data — but there is
        // no reason to spend crawl budget on endpoints that return JSON.
        disallow: ["/api/"],
      },
    ],
    sitemap: "https://akarat.ai/sitemap.xml",
  };
}
