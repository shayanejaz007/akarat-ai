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
  return legalMetadata("terms", lang);
}

export default async function Terms({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  return <LegalPage which="terms" langRaw={lang} />;
}
