export const site = {
  name: "Vine Cliff",
  fullName: "Vine Cliff Vineyards",
  tagline: "An elegant country estate on the shores of Lake Erie",
  description:
    "Weekly, weekend and event rentals across a farmhouse, carriage house and barn — each over 170 years old — perched on the cliffs above Lake Erie in New York wine country.",
  phone: "+1 415-200-9142",
  phoneHref: "tel:+14152009142",
  email: "hello@vinecliff.com",
  address: {
    line1: "6153 Rte. 5",
    city: "Brocton",
    region: "NY",
    postalCode: "14716",
    country: "United States",
    full: "6153 Rte. 5, Brocton, NY 14716, United States",
  },
  mapUrl:
    "https://www.google.com/maps/search/?api=1&query=6153+Rte.+5+Brocton+NY+14716",
  url: "https://vinecliff.com",
} as const;

export type Space = {
  id: string;
  name: string;
  kind: string;
  age: string;
  image: string;
  blurb: string;
  features: string[];
};

export const spaces: Space[] = [
  {
    id: "farmhouse",
    name: "The Farmhouse",
    kind: "Weekly & weekend stays",
    age: "Built c. 1850",
    image: "/img/house.jpg",
    blurb:
      "A stately Greek Revival farmhouse with wraparound porch, wide lawns and views out toward the lake. Sleeps a gathering of family or friends in classic country comfort.",
    features: ["Wraparound porch", "Sleeps 8+", "Full country kitchen", "Fire pit & lawn games"],
  },
  {
    id: "carriage-house",
    name: "The Carriage House",
    kind: "Intimate retreats",
    age: "Built c. 1850",
    image: "/img/front-porch.jpg",
    blurb:
      "A charming, light-filled retreat tucked among the pines — perfect for couples and small parties who want quiet, character and a porch made for slow mornings.",
    features: ["Private porch", "Cozy for 2–4", "Wooded setting", "Steps from the cliffs"],
  },
  {
    id: "barn",
    name: "The Barn",
    kind: "Weddings & events",
    age: "Built c. 1850",
    image: "/img/full-view.jpg",
    blurb:
      "A 170-year-old barn and sweeping grounds that host weddings, reunions and celebrations against a backdrop of vineyards and Lake Erie sunsets.",
    features: ["Weddings & receptions", "Open lawns", "Vineyard backdrop", "Golden-hour ceremonies"],
  },
];

export const gallery = [
  { src: "/img/aerial-shot.jpg", alt: "Aerial view of the estate on the cliffs above Lake Erie", span: "wide" },
  { src: "/img/sunset.jpg", alt: "Golden sunset through the trees over the estate grounds" },
  { src: "/img/full-view.jpg", alt: "The farmhouse across open lawns at dusk" },
  { src: "/img/house.jpg", alt: "The historic white farmhouse and front lawn" },
  { src: "/img/front-porch.jpg", alt: "The columned front porch of the carriage house" },
  { src: "/img/vinecliff-sign.jpg", alt: "The Vine Cliff sign at the roadside at sunset", span: "wide" },
] as const;

export const nearby = [
  { name: "Chautauqua Institution", note: "Arts, music & lectures — a short drive south" },
  { name: "SUNY Fredonia", note: "Campus, performances & town life nearby" },
  { name: "Dunkirk", note: "Lakeside dining, marina and harbor" },
  { name: "Lake Erie Wine Country", note: "The largest grape-growing region east of the Rockies" },
] as const;
