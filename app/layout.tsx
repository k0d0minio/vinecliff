import type { Metadata, Viewport } from "next";
import { Analytics } from "@vercel/analytics/next";
import { fraunces, inter } from "./fonts/fonts";
import { site } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: `${site.fullName} — ${site.tagline}`,
    template: `%s · ${site.fullName}`,
  },
  description: site.description,
  keywords: [
    "Vine Cliff",
    "Lake Erie holiday rental",
    "Brocton NY vacation rental",
    "farmhouse rental New York",
    "wedding venue Lake Erie",
    "event space Chautauqua",
    "New York wine country stay",
  ],
  authors: [{ name: site.fullName }],
  creator: site.fullName,
  // Open Graph image, Twitter image and icons are provided by the file
  // conventions in app/ (opengraph-image.jpg, twitter-image.jpg, icon.svg,
  // apple-icon.png). Next infers their exact dimensions, type and absolute
  // URLs from metadataBase automatically.
  openGraph: {
    type: "website",
    locale: "en_US",
    url: site.url,
    siteName: site.fullName,
    title: `${site.fullName} — ${site.tagline}`,
    description: site.description,
  },
  twitter: {
    card: "summary_large_image",
    title: `${site.fullName} — ${site.tagline}`,
    description: site.description,
  },
  alternates: {
    canonical: "/",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large" },
  },
};

export const viewport: Viewport = {
  themeColor: "#294032",
  colorScheme: "light",
  width: "device-width",
  initialScale: 1,
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "LodgingBusiness",
  name: site.fullName,
  description: site.description,
  telephone: site.phone,
  url: site.url,
  address: {
    "@type": "PostalAddress",
    streetAddress: site.address.line1,
    addressLocality: site.address.city,
    addressRegion: site.address.region,
    postalCode: site.address.postalCode,
    addressCountry: "US",
  },
  amenityFeature: [
    { "@type": "LocationFeatureSpecification", name: "Event space" },
    { "@type": "LocationFeatureSpecification", name: "Lake Erie waterfront" },
    { "@type": "LocationFeatureSpecification", name: "Vineyard grounds" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${fraunces.variable} ${inter.variable}`}>
      <body className="antialiased">
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        {children}
        <Analytics />
      </body>
    </html>
  );
}
