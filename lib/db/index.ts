// Drizzle client backed by Neon's serverless HTTP driver.
//
// The HTTP driver runs happily in Vercel's serverless functions (server
// actions, route handlers) and in Node scripts such as the migrator. It is not
// used from the Edge middleware — that path stays database-free and validates
// the signed session cookie on its own.
//
// The client is created lazily on first query rather than at import time, so
// modules that import `db` can be built (e.g. `next build` in CI) in
// environments where DATABASE_URL isn't configured. The missing-variable error
// only surfaces when a query actually runs.
import { neon } from "@neondatabase/serverless";
import { drizzle, type NeonHttpDatabase } from "drizzle-orm/neon-http";
import * as schema from "./schema";

type Db = NeonHttpDatabase<typeof schema>;

let client: Db | null = null;

function getDb(): Db {
  if (!client) {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error(
        "DATABASE_URL is not set. Add the Neon connection string to the environment."
      );
    }
    client = drizzle(neon(connectionString), { schema });
  }
  return client;
}

export const db: Db = new Proxy({} as Db, {
  get(_target, prop) {
    const instance = getDb();
    const value = Reflect.get(instance, prop);
    return typeof value === "function" ? value.bind(instance) : value;
  },
});
