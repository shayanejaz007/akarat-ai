/** @type {import('next').NextConfig} */

// Headers applied to every response. None of these change how the app works;
// they close the defaults a browser falls back to when a site says nothing.
const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-Frame-Options', value: 'SAMEORIGIN' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'geolocation=(), microphone=(), camera=(), interest-cohort=()' },
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
  }
};

export default nextConfig;
