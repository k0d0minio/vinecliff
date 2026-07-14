import localFont from "next/font/local";

export const fraunces = localFont({
  src: "./Fraunces-latin.woff2",
  variable: "--font-serif",
  weight: "300 600",
  display: "swap",
  fallback: ["Georgia", "Cambria", "Times New Roman", "serif"],
});

export const inter = localFont({
  src: "./Inter-latin.woff2",
  variable: "--font-sans",
  weight: "300 700",
  display: "swap",
  fallback: [
    "ui-sans-serif",
    "system-ui",
    "-apple-system",
    "Segoe UI",
    "Roboto",
    "Helvetica Neue",
    "Arial",
    "sans-serif",
  ],
});
