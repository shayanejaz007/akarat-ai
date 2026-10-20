import type { Metadata } from "next";
import LegalPage, { legalMetadata } from "../legal-page";

export const revalidate = 3600;
export const dynamicParams = true;

export function generateStaticParams() {
  return [{ lang: "en" }, { lang: "ar" }];
}

export async function generateMetadata(
  { params }: { params: Promise<{ lang: string }> }
): Promise<Metadata> {
  const { lang } = await params;
  return legalMetadata("deletion", lang);
}

export default async function DataDeletion({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  return <LegalPage which="deletion" langRaw={lang} />;
}
