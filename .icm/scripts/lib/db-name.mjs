// lib/db-name.mjs — the one MongoDB database-name derivation, shared by the app and the pipeline (TEMPLATE-OWNED).
//
// Decision D35: a MongoDB repo gets a database per run (`run_<slug>`) and, where it declares
// `database.mongodb.previews: "branch"`, a database per preview (`preview_<git branch>`), all on
// the one cluster it already uses. The names are derived, never stored: the app derives its
// preview database from the branch Vercel deploys, the scripts derive the same name from the
// branch or the run slug, and this file is the only place the rule lives — so the two cannot
// disagree. Dependency-free on purpose: the app imports it (server-side), the scripts run it with
// `node`, and neither needs anything installed.
//
// The rule (MongoDB: no `/\. "$*<>:|?`, case-insensitive uniqueness; a length cap per cluster):
//   lower-case; every run of characters outside [a-z0-9_] becomes one `_`; leading and trailing
//   `_` dropped; `<prefix>_` in front. A name longer than the cap keeps its first (cap - 9)
//   characters and gains `_` + an 8-hex FNV-1a hash of the whole normalised body, so two long
//   branches that share a prefix still get two databases.
//   The cap is `database.mongodb.limits.name_bytes` in .icm/project.json — default 38, what Atlas's
//   shared and free tiers (M0/M2/M5) allow; MongoDB's own 63 holds only on a dedicated cluster
//   (M10+), which declares `name_bytes: 63`. 20 to 63; anything else is an error, never a guess.
//     runDbName("csv-export")                → run_csv_export
//     previewDbName("claude/csv-export")     → preview_claude_csv_export
//     previewDbName("Feature/ÜBER.fix")      → preview_feature_ber_fix
//     previewDbName("claude/sentry-web-instrumentation")      → preview_claude_sentry_web_ins_65692577
//     previewDbName("claude/sentry-web-instrumentation", 63)  → preview_claude_sentry_web_instrumentation
//
// The app side — the one line a repo changes (its connection code), gated by one variable:
//   import { databaseName } from "<path to>/.icm/scripts/lib/db-name.mjs";
//   mongoose.connect(uri, { dbName: databaseName(process.env, "MONGODB_DATABASE_NAME") });
// databaseName() returns preview_<VERCEL_GIT_COMMIT_REF> when VERCEL_ENV is "preview" AND
// MONGODB_PREVIEW_PER_BRANCH is "1" (set once, on the Preview target — Vercel's system
// environment variables must be exposed); otherwise the value of the name variable, exactly as
// before. Unsetting the flag is the whole revert. The app cannot read .icm/project.json, so a repo
// that declares `limits.name_bytes` other than 38 passes the same number as the third argument —
// `databaseName(process.env, "MONGODB_DATABASE_NAME", 63)` — or the app and the pipeline name two
// different databases for every long branch (`db-env.sh init` says so). A repo that cannot import
// across its package boundary copies this file verbatim and keeps it byte-identical — the
// examples above are its test.
//
// CLI (what the scripts and workflows call):
//   node .icm/scripts/lib/db-name.mjs run <slug>        → run_<slug>
//   node .icm/scripts/lib/db-name.mjs preview <branch>  → preview_<branch>
//   node .icm/scripts/lib/db-name.mjs preview --stdin   → one name per input line (a branch list)
// The CLI reads the cap from .icm/project.json itself (two levels up from this file), so no caller
// threads it through and none can disagree. It needs Node ≥ 20.16 (process.getBuiltinModule — no
// import statement, so the app's bundler never sees node:fs).

export const DEFAULT_NAME_BYTES = 38;
export const PREVIEW_FLAG = "MONGODB_PREVIEW_PER_BRANCH";

export function normalise(raw) {
  return String(raw ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function fnv1a(s) {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, "0");
}

export function nameBytes(raw) {
  if (raw === undefined || raw === null || raw === "") return DEFAULT_NAME_BYTES;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 20 || n > 63) {
    throw new Error(`db-name: name_bytes '${raw}' must be a whole number from 20 to 63 (38 on Atlas's shared tiers, 63 on a dedicated cluster)`);
  }
  return n;
}

export function pipelineDbName(prefix, raw, cap = DEFAULT_NAME_BYTES) {
  const max = nameBytes(cap);
  const body = normalise(raw);
  if (!body) throw new Error(`db-name: '${raw}' leaves nothing after normalising`);
  const name = `${prefix}_${body}`;
  return name.length <= max ? name : `${name.slice(0, max - 9)}_${fnv1a(body)}`;
}

export const runDbName = (slug, cap) => pipelineDbName("run", slug, cap);
export const previewDbName = (branch, cap) => pipelineDbName("preview", branch, cap);

export function databaseName(env = process.env, nameEnv = "MONGODB_DATABASE_NAME", cap = DEFAULT_NAME_BYTES) {
  if (env.VERCEL_ENV === "preview" && env[PREVIEW_FLAG] === "1" && env.VERCEL_GIT_COMMIT_REF) {
    return previewDbName(env.VERCEL_GIT_COMMIT_REF, cap);
  }
  return env[nameEnv];
}

// --- CLI — only when run directly, never on import --------------------------------------------------
if (typeof process !== "undefined" && /db-name\.mjs$/.test(process.argv?.[1] ?? "")) {
  const [kind, arg] = process.argv.slice(2);
  const fn = { run: runDbName, preview: previewDbName }[kind];
  if (!fn || !arg) {
    process.stderr.write("usage: db-name.mjs run <slug> | preview <branch> | preview --stdin\n");
    process.exit(2);
  }
  let cap;
  try {
    const fs = process.getBuiltinModule?.("node:fs");
    if (!fs) throw new Error("db-name: needs Node >= 20.16 (process.getBuiltinModule) to read .icm/project.json");
    const file = new URL("../../project.json", import.meta.url);
    const pj = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
    cap = nameBytes(pj?.database?.mongodb?.limits?.name_bytes);
  } catch (e) {
    process.stderr.write(`${e.message.startsWith("db-name:") ? e.message : `db-name: .icm/project.json: ${e.message}`}\n`);
    process.exit(1);
  }
  const name = (s) => fn(s, cap);
  if (arg === "--stdin") {
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c) => (input += c));
    process.stdin.on("end", () => {
      for (const line of input.split("\n")) if (line.trim()) process.stdout.write(`${name(line.trim())}\t${line.trim()}\n`);
    });
  } else {
    process.stdout.write(`${name(arg)}\n`);
  }
}
