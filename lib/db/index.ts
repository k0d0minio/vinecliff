// Drizzle client backed by Neon's serverless HTTP driver.
//
// The HTTP driver runs happily in Vercel's serverless functions (server
// actions, route handlers) and in Node scripts such as the migrator. It is not
// used from the Edge middleware — that path stays database-free and validates
// the signed session cookie on its own.
import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";
import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error(
    "DATABASE_URL is not set. Add the Neon connection string to the environment."
  );
}

const sql = neon(connectionString);
export const db = drizzle(sql, { schema });
