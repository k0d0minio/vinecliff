// Refuses to call a migration run done while any journal entry is not in the
// database. Runs after `npm run db:migrate`: in the build's vercel-build
// (.icm/local/vercel-build.sh).
//
//   DATABASE_URL="postgres://..." npm run db:verify
//
// The Drizzle migrator applies only journal entries stamped later than the
// newest applied row, and reports success whether or not that left anything
// behind. This script compares the SHA-256 of every journal file (the hash
// Drizzle itself records) with the applied rows, and exits non-zero on a gap.
// Read-only: it never applies anything.
import "dotenv/config";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { neon } from "@neondatabase/serverless";

type JournalEntry = { idx: number; when: number; tag: string };

const drizzleDir = join(process.cwd(), "drizzle");

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error("DATABASE_URL is not set. Nothing to verify against.");
  }

  const { entries } = JSON.parse(
    readFileSync(join(drizzleDir, "meta", "_journal.json"), "utf8"),
  ) as { entries: JournalEntry[] };

  const sql = neon(url);
  // scripts/migrate.ts uses the migrator's defaults: schema "drizzle", table "__drizzle_migrations".
  const rows = (await sql`select hash from drizzle.__drizzle_migrations`) as Array<{ hash: string }>;
  const applied = new Set(rows.map((r) => r.hash));

  const missing = entries.filter((entry) => {
    const file = readFileSync(join(drizzleDir, `${entry.tag}.sql`), "utf8");
    // Drizzle hashes the whole file as read, comments included.
    const hash = createHash("sha256").update(file).digest("hex");
    return !applied.has(hash);
  });

  if (missing.length > 0) {
    throw new Error(
      `${missing.length} journal ${missing.length === 1 ? "entry is" : "entries are"} not applied to this database:\n` +
        missing.map((e) => `  - ${e.tag} (when ${e.when})`).join("\n"),
    );
  }

  console.log(
    `[verify] all ${entries.length} journal entries are applied (${applied.size} rows in __drizzle_migrations)`,
  );
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
