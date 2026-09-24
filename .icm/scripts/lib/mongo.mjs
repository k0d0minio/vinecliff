// lib/mongo.mjs — the one MongoDB transport for the pipeline scripts (TEMPLATE-OWNED). Run with node, never imported by the app.
//
// What lib/neon.sh is to Neon, this is to a MongoDB cluster (decision D35): db-branch.sh's
// `database` isolation, db-env.sh on a `provider: "mongodb"` repo, and the reference
// mongodb-cleanup.yaml all reach the cluster through here. It uses the repo's own driver — the
// `mongodb` package, or the one `mongoose` carries as `mongoose.mongo` — resolved from the repo
// root, from each `migrations.path` and its parents (a pnpm workspace keeps the driver inside the
// package that uses it), or from $ICM_MONGO_DRIVER_DIR (the cleanup workflow installs one there).
// No new binary, no global install.
//
// The URI is read from the variable `database.url_env` names (default MONGODB_URI) — the cluster,
// never a database — and never printed, logged or passed in argv; every error is scrubbed of a
// connection string before it reaches stderr. The database names the writes accept are checked
// here as well as in the callers:
//   drop    only `run_*` and `preview_*`; never `database.mongodb.production_name` or
//           `preview_name`, whatever their shape; never the UAT database (`database.mongodb.uat_name`,
//           read when uat is declared — D39) unless the caller says `--uat` (db-env.sh reset-uat,
//           on the operator's --apply) — and `--uat` drops that one name only, whatever its shape.
//   forget  only `run_*` — it deletes the migration runner's records of named migrations, which
//           is exactly what a re-stamp does to them (the idempotency proof).
//
// Verbs (stdout is data; stderr is prose; exit 0 ok · 1 refused or failed · 2 usage):
//   check                        connect and ping → `ok <n> database(s)`
//   list                         JSON [{name, collections}] of every database but admin/local/config
//   snapshot <db>                canonical JSON of the database's shape: every collection (not
//                                system.*) with its type and its index specs (v and ns dropped,
//                                option keys sorted, `key` order kept) — two snapshots compare as
//                                strings
//   drop <db> [--uat]            dropDatabase; a user without that action drops every collection
//                                instead (an empty database ceases to exist)
//   forget <db> <collection> <name>...
//                                delete the runner's records whose `name` (ts-migrate-mongoose) or
//                                `fileName` (migrate-mongo) is one of <name>...
//
// Usage: node .icm/scripts/lib/mongo.mjs <verb> [args]
import { readFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../../..");
const scrub = (s) => String(s).replace(/mongodb(\+srv)?:\/\/[^\s"'<>]*/g, "mongodb://<redacted>");
const fail = (msg, code = 1) => {
  process.stderr.write(`error: ${scrub(msg)}\n`);
  process.exit(code);
};

let pj = {};
try {
  const f = path.join(root, ".icm/project.json");
  if (existsSync(f)) pj = JSON.parse(readFileSync(f, "utf8"));
} catch (e) {
  fail(`.icm/project.json is not valid JSON: ${e.message}`);
}
const dbc = pj.database ?? {};
const mdb = dbc.mongodb ?? {};
const urlEnv = dbc.url_env || "MONGODB_URI";
const protectedNames = [mdb.production_name, mdb.preview_name].filter(Boolean);
const uatDb = pj.uat?.target && pj.uat?.url ? (mdb.uat_name || "") : "";

function loadDriver() {
  const paths = [pj.migrations?.path ?? pj.migrations_path ?? []].flat().filter(Boolean);
  const dirs = new Set([process.env.ICM_MONGO_DRIVER_DIR, root].filter(Boolean));
  for (const p of paths) {
    for (let d = path.resolve(root, p); d.startsWith(root) && d !== root; d = path.dirname(d)) dirs.add(d);
  }
  for (const d of dirs) {
    const req = createRequire(path.join(d, "noop.js"));
    try { return req("mongodb"); } catch {}
    try { const m = req("mongoose"); if (m?.mongo?.MongoClient) return m.mongo; } catch {}
  }
  fail(`no MongoDB driver found (the mongodb or mongoose package) from ${[...dirs].map((d) => path.relative(root, d) || ".").join(", ")} — install the repo's dependencies, or set ICM_MONGO_DRIVER_DIR`);
}

function canon(v, keepOrder = false) {
  if (Array.isArray(v)) return v.map((x) => canon(x));
  if (v && typeof v === "object" && v.constructor === Object) {
    const keys = keepOrder ? Object.keys(v) : Object.keys(v).sort();
    return Object.fromEntries(keys.map((k) => [k, canon(v[k], k === "key")]));
  }
  return v;
}

function guardDrop(name, uat) {
  if (uat) {
    if (!uatDb || name !== uatDb) fail(`refusing '${name}' with --uat — it is not the declared UAT database (database.mongodb.uat_name)`);
    if (protectedNames.includes(name)) fail(`refusing '${name}' — it is database.mongodb.production_name or preview_name`);
    return;
  }
  if (!/^(run|preview)_[a-z0-9_]+$/.test(name)) fail(`refusing '${name}' — only run_* and preview_* databases are the pipeline's`);
  if (protectedNames.includes(name)) fail(`refusing '${name}' — it is database.mongodb.production_name or preview_name`);
  if (uatDb && name === uatDb) fail(`refusing '${name}' — it is the UAT database (db-env.sh reset-uat --apply is its one reset)`);
}

const [verb, ...args] = process.argv.slice(2);
const verbs = ["check", "list", "snapshot", "drop", "forget"];
if (!verbs.includes(verb)) fail(`usage: mongo.mjs ${verbs.join("|")} [args]`, 2);
if ((verb === "snapshot" || verb === "drop") && !args[0]) fail(`usage: mongo.mjs ${verb} <db>`, 2);
if (verb === "forget" && args.length < 3) fail("usage: mongo.mjs forget <db> <collection> <name>...", 2);
if (verb === "drop") guardDrop(args[0], args.includes("--uat"));
if (verb === "forget" && !/^run_[a-z0-9_]+$/.test(args[0])) fail(`refusing to forget migrations on '${args[0]}' — only a run_* database`);

const uri = process.env[urlEnv];
if (!uri) fail(`$${urlEnv} is unset in this environment (database.url_env) — export it; never in git`);
const { MongoClient } = loadDriver();
const client = new MongoClient(uri, { serverSelectionTimeoutMS: 10_000 });

try {
  await client.connect();
  const admin = client.db("admin");
  if (verb === "check") {
    await admin.command({ ping: 1 });
    const { databases } = await admin.command({ listDatabases: 1, nameOnly: true });
    process.stdout.write(`ok ${databases.length} database(s)\n`);
  } else if (verb === "list") {
    const { databases } = await admin.command({ listDatabases: 1, nameOnly: true });
    const out = [];
    for (const { name } of databases) {
      if (["admin", "local", "config"].includes(name)) continue;
      const cols = await client.db(name).listCollections({}, { nameOnly: true }).toArray();
      out.push({ name, collections: cols.filter((c) => !c.name.startsWith("system.")).length });
    }
    process.stdout.write(`${JSON.stringify(out.sort((a, b) => a.name.localeCompare(b.name)))}\n`);
  } else if (verb === "snapshot") {
    const db = client.db(args[0]);
    const cols = (await db.listCollections().toArray()).filter((c) => !c.name.startsWith("system.")).sort((a, b) => a.name.localeCompare(b.name));
    const shape = {};
    for (const c of cols) {
      const indexes = c.type === "view" ? [] : (await db.collection(c.name).indexes()).map(({ v, ns, ...spec }) => spec).sort((a, b) => a.name.localeCompare(b.name));
      shape[c.name] = { type: c.type ?? "collection", indexes };
    }
    process.stdout.write(`${JSON.stringify(canon(shape))}\n`);
  } else if (verb === "drop") {
    const db = client.db(args[0]);
    try {
      await db.dropDatabase();
    } catch (e) {
      if (e?.code !== 13) throw e; // Unauthorized: drop what the role may drop instead
      for (const c of await db.listCollections({}, { nameOnly: true }).toArray()) if (!c.name.startsWith("system.")) await db.dropCollection(c.name);
    }
    process.stdout.write(`dropped ${args[0]}\n`);
  } else if (verb === "forget") {
    const [name, collection, ...names] = args;
    const r = await client.db(name).collection(collection).deleteMany({ $or: [{ name: { $in: names } }, { fileName: { $in: names } }] });
    process.stdout.write(`forgot ${r.deletedCount} record(s) in ${name}.${collection}\n`);
  }
} catch (e) {
  fail(`${verb}: ${e?.message ?? e}`);
} finally {
  await client.close().catch(() => {});
}
