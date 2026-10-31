/** @type {import('next').NextConfig} */

// Headers applied to every response. None of these change how the app works;
// they close the defaults a browser falls back to when a site says nothing.
const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-Frame-Options', value: 'SAMEORIGIN' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  // microphone=(self): voice input in the AI advisor and Ask a Lawyer uses
  // the browser's speech recognition, which needs the microphone. An empty
  // list, as this had, denies it to this site too and voice input fails with
  // "not allowed". Other origins (embeds, iframes) still get nothing.
  { key: 'Permissions-Policy', value: 'geolocation=(), microphone=(self), camera=(), interest-cohort=()' },
  {
    key: 'Strict-Transport-Security',
    value: 'max-age=31536000; includeSubDomains'
  }
];

const nextConfig = {
  poweredByHeader: false,

  async headers() {
    return [{ source: '/:path*', headers: securityHeaders }];
  },

  async rewrites() {
    // The application itself is a single self-contained document served from
    // public/. Next handles the API routes, auth middleware and metadata.
    //
    // /en and /ar are served the same document. They exist because the
    // canonical and hreflang tags in app/metadata.ts point at them: without
    // these two lines those URLs 404, and a 404 is what search engines index
    // as the canonical page.
    return [
      { source: '/', destination: '/Akarat.dc.html' },
      { source: '/en', destination: '/Akarat.dc.html' },
      { source: '/ar', destination: '/Akarat.dc.html' }
    ];
  },

  async redirects() {
    // The bare paths are what people type, and what gets pasted into a
    // Facebook app's Privacy Policy and Data Deletion fields or an app store
    // submission — none of which know about the /en and /ar prefixes. English
    // is the default for the same reason it is the x-default in metadata: it
    // is what a reader of neither language should land on.
    return [
      { source: '/privacy', destination: '/en/privacy', permanent: false },
      { source: '/terms', destination: '/en/terms', permanent: false },
      { source: '/data-deletion', destination: '/en/data-deletion', permanent: false }
    ];
  }
};

export default nextConfig;
