import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { IBM_Plex_Sans_Arabic, Inter, Poppins } from "next/font/google";
import { AdminApp } from "./_components/AdminApp";
import "./admin.css";

// Inter for the interface and its figures, Poppins (the website's face) for
// headings, IBM Plex Sans Arabic for Arabic titles and names. Self-hosted by
// next/font: nothing is fetched from Google when the panel opens.
const ui = Inter({ subsets: ["latin"], variable: "--adm-font-ui", display: "swap" });
const display = Poppins({ subsets: ["latin"], weight: ["500", "600"], variable: "--adm-font-display", display: "swap" });
const arabic = IBM_Plex_Sans_Arabic({ subsets: ["arabic"], weight: ["400", "500", "600"], variable: "--adm-font-ar", display: "swap" });

// Private: kept out of search results. Nothing here is useful without the
// admin password anyway; every /api/admin route checks the session.
export const metadata: Metadata = {
  title: { absolute: "Admin · Akarat.ai" },
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#F7F2E7" },
    { media: "(prefers-color-scheme: dark)", color: "#0F0F0C" },
  ],
  colorScheme: "light dark",
};

// Applies a saved light or dark choice before the first paint, so the panel
// never flashes the other theme. Mirrors THEME_KEY in AdminApp.tsx.
const THEME = `try{var t=localStorage.getItem("akarat-admin-theme");if(t==="light"||t==="dark")document.currentScript.parentElement.setAttribute("data-adm-theme",t)}catch(e){}`;

export default function AdminLayout({ children }: { children: ReactNode }) {
  return (
    <div id="adm-root" className={`${ui.variable} ${display.variable} ${arabic.variable}`} suppressHydrationWarning>
      <script dangerouslySetInnerHTML={{ __html: THEME }} />
      <AdminApp>{children}</AdminApp>
    </div>
  );
}
