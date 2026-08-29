import type { ReactNode } from 'react';

export { metadata, viewport } from './metadata';

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
