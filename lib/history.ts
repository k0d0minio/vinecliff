// Historical research for the Vine Cliff estate history page.
//
// Every substantive claim in the narrative is tied to one or more of the
// numbered sources below. The prose in app/history/* references these by id
// via the <Cite> component so the page can footnote its history and convey
// credibility. Sourcing was assembled from period reference works (the 1912
// Dictionary of National Biography, the 1911 Encyclopædia Britannica), modern
// encyclopaedias, local Chautauqua County history, and Sonoma County wine
// history covering the Brotherhood's later California chapter.

export type Source = {
  id: number;
  /** Author / title / publication, formatted for a footnote line. */
  citation: string;
  url: string;
  /** "Primary" period source, "Reference" work, or "Local / press" account. */
  kind: "Period source" | "Reference" | "Local & press";
};

export const sources: Source[] = [
  {
    id: 1,
    citation:
      "“Harris, Thomas Lake.” Dictionary of National Biography, 1912 supplement (London: Smith, Elder & Co., 1912).",
    url: "https://en.wikisource.org/wiki/Harris,_Thomas_Lake_(DNB12)",
    kind: "Period source",
  },
  {
    id: 2,
    citation:
      "“Harris, Thomas Lake.” Encyclopædia Britannica, 11th ed. (Cambridge University Press, 1911).",
    url: "https://en.wikisource.org/wiki/1911_Encyclop%C3%A6dia_Britannica/Harris,_Thomas_Lake",
    kind: "Period source",
  },
  {
    id: 3,
    citation:
      "“Oliphant, Laurence.” Encyclopædia Britannica, 11th ed. (Cambridge University Press, 1911).",
    url: "https://en.wikisource.org/wiki/1911_Encyclop%C3%A6dia_Britannica/Oliphant,_Laurence",
    kind: "Period source",
  },
  {
    id: 4,
    citation: "“Thomas Lake Harris.” Wikipedia, The Free Encyclopedia.",
    url: "https://en.wikipedia.org/wiki/Thomas_Lake_Harris",
    kind: "Reference",
  },
  {
    id: 5,
    citation: "“Laurence Oliphant (author).” Wikipedia, The Free Encyclopedia.",
    url: "https://en.wikipedia.org/wiki/Laurence_Oliphant_(author)",
    kind: "Reference",
  },
  {
    id: 6,
    citation: "“Nagasawa Kanaye.” Wikipedia, The Free Encyclopedia.",
    url: "https://en.wikipedia.org/wiki/Nagasawa_Kanaye",
    kind: "Reference",
  },
  {
    id: 7,
    citation: "“Thomas Lake Harris.” EBSCO Research Starters — Biography.",
    url: "https://www.ebsco.com/research-starters/biography/thomas-lake-harris",
    kind: "Reference",
  },
  {
    id: 8,
    citation:
      "“Thomas Lake Harris and the Brotherhood of the New Life.” Chautauqua County NYGenWeb (Portland township history).",
    url: "https://chautauqua.nygenweb.net/CHURCH/Portland-Harris.htm",
    kind: "Local & press",
  },
  {
    id: 9,
    citation:
      "“Lecture series explores Brocton’s 19th-century ‘cult’.” Observer Today (Dunkirk, NY), May 2023.",
    url: "https://www.observertoday.com/life/local-entertainment-news/2023/05/lecture-series-explores-broctons-19th-century-cult/",
    kind: "Local & press",
  },
  {
    id: 10,
    citation: "“History — Kanaye Nagasawa & Fountaingrove.” Paradise Ridge Winery, Santa Rosa, CA.",
    url: "https://www.prwinery.com/history/",
    kind: "Local & press",
  },
  {
    id: 11,
    citation:
      "Kaufman, Rebecca. “Sonoma County’s Utopian Vineyards.” The Wine History Project.",
    url: "https://winehistoryproject.org/sonoma-countys-utopian-vineyards/",
    kind: "Local & press",
  },
];

export type TimelineEvent = {
  year: string;
  title: string;
  body: string;
  /** Source ids that back this entry. */
  cites: number[];
};

export const timeline: TimelineEvent[] = [
  {
    year: "1823",
    title: "A prophet is born",
    body:
      "Thomas Lake Harris is born at Fenny Stratford, Buckinghamshire, England. His family emigrates to Utica, New York when he is about five.",
    cites: [1, 8],
  },
  {
    year: "1861",
    title: "The Brotherhood begins",
    body:
      "After years as a Universalist preacher, spiritualist and mystic, Harris founds the Brotherhood of the New Life — a utopian religious community — at Wassaic, New York, drawing about sixty converts.",
    cites: [2, 7],
  },
  {
    year: "1867",
    title: "Salem-on-Erie",
    body:
      "In October the Brotherhood migrates to Brocton, on the shore of Lake Erie in Chautauqua County. The colony becomes known as “Salem-on-Erie,” and its farms are given over to vine-growing and wine-making.",
    cites: [1, 4, 8],
  },
  {
    year: "1868",
    title: "An aristocrat gives it all up",
    body:
      "Laurence Oliphant — celebrated travel writer, diplomat and Member of Parliament — leaves the British House of Commons to follow Harris to Brocton, causing a public scandal, and labours on the estate as a common farm-hand.",
    cites: [3, 5],
  },
  {
    year: "c. 1869",
    title: "The Satsuma students",
    body:
      "Young men from Japan’s Satsuma domain join the colony — among them Kanaye Nagasawa, smuggled out of Japan for a Western education and recruited into the Brotherhood by Oliphant. They learn viticulture in the Brocton vineyards.",
    cites: [6, 10],
  },
  {
    year: "1875",
    title: "West to California",
    body:
      "Harris establishes a second colony at Fountaingrove, near Santa Rosa, California. Nagasawa follows and takes charge of the vineyards, building one of the great wineries of Sonoma County.",
    cites: [4, 6],
  },
  {
    year: "c. 1881",
    title: "The break with Oliphant",
    body:
      "The Oliphants break with Harris, charging him with robbery and recovering many thousands of pounds through the courts. Legal action compels the return of Oliphant’s Brocton property, and Harris sells the colony.",
    cites: [3, 1],
  },
  {
    year: "1906 – 1934",
    title: "The Japanese “Wine King”",
    body:
      "Harris dies in 1906. Kanaye Nagasawa succeeds him as leader of the Brotherhood and runs Fountaingrove until his own death in 1934, becoming one of California’s most celebrated winemakers.",
    cites: [4, 6, 11],
  },
];

export type Figure = {
  id: string;
  name: string;
  life: string;
  role: string;
  image: string;
  alt: string;
  /** Each paragraph may end with citation ids appended by the component. */
  paragraphs: { text: string; cites: number[] }[];
};

export const figures: Figure[] = [
  {
    id: "harris",
    name: "Thomas Lake Harris",
    life: "1823 – 1906",
    role: "Founder & prophet",
    image: "/img/history/harris.jpg",
    alt: "Portrait photograph of Thomas Lake Harris, founder of the Brotherhood of the New Life",
    paragraphs: [
      {
        text:
          "English-born and Utica-raised, Harris was a poet, Universalist preacher and spiritualist who came to see himself as a divine instrument. He taught a mystical doctrine of “divine respiration” — a special mode of breathing said to be the sign of possession by Christ — and of celestial “counterparts,” or heavenly partners.",
        cites: [2, 4],
      },
      {
        text:
          "In 1867 he brought his Brotherhood of the New Life to Brocton and founded Salem-on-Erie. He established a wine-making industry on the estate and, answering the temperance movement, insisted his wine was “filled with the divine breath so that all noxious influences were neutralized.”",
        cites: [2, 1],
      },
    ],
  },
  {
    id: "oliphant",
    name: "Laurence Oliphant",
    life: "1829 – 1888",
    role: "Patron & disciple",
    image: "/img/history/oliphant.jpg",
    alt: "Portrait photograph of Laurence Oliphant, writer, diplomat and Member of Parliament",
    paragraphs: [
      {
        text:
          "Born at Cape Town, Oliphant was a famous travel writer, war correspondent, diplomat and, from 1865, Member of Parliament for Stirling Burghs. He met Harris on the mystic’s 1860 tour of England and fell entirely under his spell.",
        cites: [3, 5],
      },
      {
        text:
          "In 1868 he abandoned his seat in Parliament to live as a labourer at Brocton. He and his mother, Lady Maria Oliphant — with money said to have come largely from the sale of her jewels — financed the purchase of the colony’s farms. He broke with Harris around 1881 and won much of his fortune back through the courts.",
        cites: [5, 3],
      },
    ],
  },
  {
    id: "nagasawa",
    name: "Kanaye Nagasawa",
    life: "1852 – 1934",
    role: "Vintner from Satsuma",
    image: "/img/history/nagasawa.png",
    alt: "Portrait photograph of Kanaye Nagasawa, the Satsuma-born winemaker of Fountaingrove",
    paragraphs: [
      {
        text:
          "Born Isonaga Hikosuke to a Satsuma samurai family, Nagasawa was one of fifteen students smuggled out of Japan in the 1860s to study in the West. Oliphant met him in Scotland and brought him, with fellow Satsuma students, into Harris’s community at Brocton, where he learned to tend the vines.",
        cites: [6, 10],
      },
      {
        text:
          "Following Harris to California in 1875, Nagasawa took charge of the vineyards at Fountaingrove and, after Harris’s death, led the Brotherhood until 1934. Celebrated as California’s “Grape King,” his winemaking career began in the vineyards above Lake Erie.",
        cites: [6, 11],
      },
    ],
  },
];
