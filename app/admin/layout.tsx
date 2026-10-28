import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./admin.css";

// Private: kept out of search results, and nothing here is useful to anyone
// without an admin account anyway (every /api/admin route checks the role).
export const metadata: Metadata = {
  title: "Admin · Akarat.ai",
  robots: { index: false, follow: false },
};

export default function AdminLayout({ children }: { children: ReactNode }) {
  return children;
}
