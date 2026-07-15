-- Seed the booking platform: the three historic spaces (ported from the
-- original hardcoded lib/site.ts content), the whole-estate package, and the
-- default estate settings.
--
-- Rates are sensible placeholders in cents — the owner adjusts them from
-- /admin/spaces. Idempotent: ON CONFLICT keeps re-runs safe and never
-- clobbers values that have since been edited through the app.

INSERT INTO "spaces" (
  "slug", "name", "kind", "age", "blurb", "description", "image", "features",
  "is_event", "blocks_estate",
  "nightly_rate_cents", "weekly_rate_cents", "cleaning_fee_cents",
  "min_nights", "max_guests", "buffer_days", "min_lead_days", "max_horizon_months",
  "sort_order"
) VALUES
(
  'farmhouse',
  'The Farmhouse',
  'Weekly & weekend stays',
  'Built c. 1850',
  'A stately Greek Revival farmhouse with wraparound porch, wide lawns and views out toward the lake. Sleeps a gathering of family or friends in classic country comfort.',
  E'The heart of the estate, The Farmhouse is a stately Greek Revival home that has watched over these vineyards since the 1850s. Behind its columned wraparound porch you''ll find a full country kitchen, generous gathering rooms and beds for eight or more — comfortable, characterful and made for slow weeks by the lake.\n\nMornings start with coffee on the porch above the vines; evenings end around the fire pit under a Lake Erie sunset. Weekly stays are the Vine Cliff classic, and long weekends are lovely in every season.',
  '/img/house.jpg',
  ARRAY['Wraparound porch', 'Sleeps 8+', 'Full country kitchen', 'Fire pit & lawn games'],
  false, false,
  45000, 275000, 15000,
  2, 10, 1, 2, 18,
  1
),
(
  'carriage-house',
  'The Carriage House',
  'Intimate retreats',
  'Built c. 1850',
  'A charming, light-filled retreat tucked among the pines — perfect for couples and small parties who want quiet, character and a porch made for slow mornings.',
  E'Tucked among the pines a short stroll from the cliff edge, The Carriage House is the quiet corner of the estate. Light-filled rooms, a private porch and space for two to four make it a natural fit for couples'' escapes, writing retreats and small family stays.\n\nYou''re steps from the water and a short drive from Chautauqua, Fredonia and the wineries of the Lake Erie grape belt — close to everything, disturbed by nothing.',
  '/img/front-porch.jpg',
  ARRAY['Private porch', 'Cozy for 2–4', 'Wooded setting', 'Steps from the cliffs'],
  false, false,
  25000, 150000, 10000,
  2, 4, 1, 2, 18,
  2
),
(
  'barn',
  'The Barn',
  'Weddings & events',
  'Built c. 1850',
  'A 170-year-old barn and sweeping grounds that host weddings, reunions and celebrations against a backdrop of vineyards and Lake Erie sunsets.',
  E'Our 170-year-old barn and the open lawns around it host weddings, reunions and celebrations for up to 150 guests, with the vineyards and Lake Erie sunsets as your backdrop. Exchange vows at golden hour, dine under the rafters and dance until the fireflies come out.\n\nEvent bookings cover the barn and surrounding grounds across your setup, celebration and teardown days. As a rule we reserve the whole estate around confirmed events, so your party has the place entirely to itself.',
  '/img/full-view.jpg',
  ARRAY['Weddings & receptions', 'Open lawns', 'Vineyard backdrop', 'Golden-hour ceremonies'],
  true, true,
  250000, NULL, 50000,
  1, 150, 1, 14, 18,
  3
),
(
  'estate',
  'The Whole Estate',
  'Exclusive hire',
  'Est. 1850',
  'Take every key on the property — farmhouse, carriage house, barn and grounds — for weddings, reunions and retreats that deserve the entire cliff top to themselves.',
  E'For gatherings that want all of Vine Cliff, the estate package puts the farmhouse, carriage house, barn and grounds in your hands at once. House the wedding party in the farmhouse, tuck the newlyweds into the carriage house, celebrate in the barn — with no other guests anywhere on the property.\n\nTell us about your plans in the booking request and we''ll shape the days around them, from setup to farewell brunch.',
  '/img/aerial-shot.jpg',
  ARRAY['All three buildings', 'Sleeps 12+ overnight', 'Events up to 150', 'Total privacy'],
  true, true,
  350000, 2000000, 100000,
  2, 150, 1, 14, 18,
  4
)
ON CONFLICT ("slug") DO NOTHING;
--> statement-breakpoint
INSERT INTO "settings" ("key", "value") VALUES
(
  'notify_email',
  'hello@vinecliff.com'
),
(
  'cancellation_policy',
  'Deposits are fully refundable up to 30 days before arrival. Within 30 days of arrival, deposits are non-refundable, but we''re always happy to move your dates where the calendar allows. Event cancellations are handled case by case — please call us and we''ll work something out.'
)
ON CONFLICT ("key") DO NOTHING;
