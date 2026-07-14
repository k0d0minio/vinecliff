import type { Metadata, Viewport } from "next";
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
  openGraph: {
    type: "website",
    locale: "en_US",
    url: site.url,
    siteName: site.fullName,
    title: `${site.fullName} — ${site.tagline}`,
    description: site.description,
    images: [
      {
        url: "/img/aerial-shot.jpg",
        width: 1200,
        height: 800,
        alt: "Aerial view of the Vine Cliff estate above Lake Erie",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: `${site.fullName} — ${site.tagline}`,
    description: site.description,
    images: ["/img/aerial-shot.jpg"],
  },
  icons: {
    icon: [{ url: "/favicon.svg", type: "image/svg+xml" }],
  },
  alternates: {
    canonical: site.url,
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
      </body>
    </html>
  );
}
