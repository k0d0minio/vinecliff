// Applies pending Drizzle migrations against DATABASE_URL using Neon's HTTP
// driver. Runs in CI (GitHub Actions on merge to main) and can be run locally:
//
//   DATABASE_URL="postgres://..." npm run db:migrate
//
// It is safe to run repeatedly — Drizzle records applied migrations in the
// __drizzle_migrations table and skips anything already applied.
import "dotenv/config";
import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";
import { migrate } from "drizzle-orm/neon-http/migrator";

async function main() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error("DATABASE_URL is not set. Cannot run migrations.");
  }

  const sql = neon(connectionString);
  const db = drizzle(sql);

  console.log("Running database migrations…");
  await migrate(db, { migrationsFolder: "./drizzle" });
  console.log("Migrations complete.");
}

main().catch((error) => {
  console.error("Migration failed:", error);
  process.exit(1);
});
