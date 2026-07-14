import type { Metadata } from "next";
import { Nav } from "../components/nav";
import { Footer } from "../components/footer";
import {
  HistoryHero,
  HistoryLede,
  HistoryTimeline,
  HistoryFigures,
  HistoryVineyards,
  HistoryToday,
  HistorySources,
} from "./sections";

export const metadata: Metadata = {
  title: "History of the Estate",
  description:
    "The history of Vine Cliff, Brocton NY — once “Salem-on-Erie,” the utopian vineyard colony of Thomas Lake Harris and the Brotherhood of the New Life, home to Laurence Oliphant and the Satsuma vintner Kanaye Nagasawa.",
  alternates: { canonical: "/history" },
  openGraph: {
    type: "article",
    title: "History of the Estate · Vine Cliff",
    description:
      "Once “Salem-on-Erie,” the 2,000-acre vineyard colony of Thomas Lake Harris and the Brotherhood of the New Life on the shores of Lake Erie.",
  },
};

export default function HistoryPage() {
  return (
    <>
      <Nav />
      <main>
        <HistoryHero />
        <HistoryLede />
        <HistoryTimeline />
        <HistoryFigures />
        <HistoryVineyards />
        <HistoryToday />
        <HistorySources />
      </main>
      <Footer />
    </>
  );
}
