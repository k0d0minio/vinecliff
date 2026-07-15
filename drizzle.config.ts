import { defineConfig } from "drizzle-kit";

// `drizzle-kit generate` uses this to diff the schema and emit SQL into
// ./drizzle. Applying migrations is done by scripts/migrate.ts (Neon HTTP
// driver) rather than `drizzle-kit migrate`, so DATABASE_URL is only needed
// for optional tooling like `drizzle-kit studio`.
export default defineConfig({
  schema: "./lib/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "",
  },
  strict: true,
  verbose: true,
});
