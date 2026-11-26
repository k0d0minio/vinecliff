// core.ts — the pure functions of the request button (blueprint 1.0.0-rc27).
// The rules: .icm/_system/features/requests.md. The capture shape: CAPTURE.md.
// This file has no import: the blueprint tests load it with Node.

export const CAPTURE_SCHEMA = "baxter.capture/1";
export const MAX_ENTRIES = 50;
export const MAX_MESSAGE = 500;
export const MAX_DOM = 300_000;

export type CaptureEntry = { at: string; level: string; message: string };
export type FailedRequest = { at: string; method: string; url: string; status: number; error: string | null };
export type CaptureUser = { signed_in: boolean | null; role: string | null; id_hash: string | null };
export type Capture = {
  schema: typeof CAPTURE_SCHEMA;
  captured_at: string;
  app: { repo: string; env: string; version: string };
  page: { url: string; route: string; title: string; lang: string };
  viewport: { width: number; height: number; device_pixel_ratio: number };
  user: CaptureUser;
  console_errors: CaptureEntry[];
  failed_requests: FailedRequest[];
  screenshot: { file: string; type: string; method: string } | null;
  screenshot_error: string | null;
  dom: string | null;
};
export type Urgency = "low" | "normal" | "high";
export type RequestForm = { what: string; where: string; urgency: Urgency; words: string };
export type Env = Record<string, string | undefined>;

// The environment where the button shows, or null. Local: `next dev`, or
// BAXTER_REQUEST_ENV=local. UAT: BAXTER_REQUEST_ENV=uat. Production only with
// BAXTER_REQUEST_ENV=production and BAXTER_REQUEST_PRODUCTION=on (the operator's choice).
export function buttonEnv(env: Env): string | null {
  const name = env.BAXTER_REQUEST_ENV || (env.NODE_ENV === "development" ? "local" : "");
  if (name === "local" || name === "uat") return name;
  if (name === "production" && env.BAXTER_REQUEST_PRODUCTION === "on") return name;
  return null;
}

const EMAIL = /[A-Z0-9._%+-]+@[A-Z0-9-]+(\.[A-Z0-9-]+)*\.[A-Z]{2,}/gi;
const JWT = /\beyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}/g;
const SCHEME = /\b(Bearer|Basic|Token)\s+[A-Za-z0-9._~+/=-]{8,}/gi;
const PAIR = /\b(password|passwd|pwd|token|secret|api[_-]?key|apikey|cookie|authorization)(["']?\s*[:=]\s*["']?)[^\s"'&,;]+/gi;
const OPAQUE = /\b[A-Za-z0-9_-]{32,}\b/g;
const SECRET_KEY = /pass|pwd|token|secret|key|auth|session|sig|code|otp|nonce|state|ticket|mail|cookie|jwt/i;

// A text with no e-mail address, no token, no password and no long opaque value.
export function redactText(text: string): string {
  return text
    .replace(JWT, "[hidden]")
    .replace(SCHEME, "$1 [hidden]")
    .replace(PAIR, "$1$2[hidden]")
    .replace(EMAIL, "[email]")
    .replace(OPAQUE, "[hidden]");
}

// An absolute URL with no user, no password, no secret query value, no token in the path
// and no fragment that holds values.
export function redactUrl(raw: string, base = "http://localhost/"): string {
  if (raw.startsWith("data:")) return "data:[hidden]";
  let url: URL;
  try {
    url = new URL(raw, base);
  } catch {
    return redactText(raw.split(/[?#]/)[0]);
  }
  url.username = "";
  url.password = "";
  for (const key of Array.from(new Set(url.searchParams.keys()))) {
    const value = url.searchParams.get(key) ?? "";
    if (SECRET_KEY.test(key) || redactText(value) !== value) url.searchParams.set(key, "hidden");
  }
  url.pathname = url.pathname
    .split("/")
    .map((part) => (redactText(decodeSafe(part)) === decodeSafe(part) ? part : "hidden"))
    .join("/");
  if (url.hash.includes("=") || url.hash.length > 40) url.hash = "";
  return url.toString();
}

function decodeSafe(part: string): string {
  try {
    return decodeURIComponent(part);
  } catch {
    return part;
  }
}

// The DOM snapshot with no script, no form value and nothing that redactText hides.
export function redactDom(html: string): string {
  return redactText(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/\s(value|checked|selected)="[^"]*"/gi, "")
      .replace(/<textarea([^>]*)>[\s\S]*?<\/textarea>/gi, "<textarea$1></textarea>"),
  ).slice(0, MAX_DOM);
}

function str(value: unknown, max = MAX_MESSAGE): string {
  return typeof value === "string" ? value.slice(0, max) : "";
}
function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
function obj(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}
function list(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.slice(-MAX_ENTRIES).map(obj) : [];
}

// The capture that the server keeps: only the fields of baxter.capture/1, each one
// redacted again. The server gives `app`; the browser cannot set it.
export function sanitizeCapture(input: unknown, app: Capture["app"], now = new Date()): Capture {
  const c = obj(input);
  const page = obj(c.page);
  const viewport = obj(c.viewport);
  const user = obj(c.user);
  const base = str(page.url, 2000);
  return {
    schema: CAPTURE_SCHEMA,
    captured_at: now.toISOString(),
    app,
    page: {
      url: base ? redactUrl(base) : "",
      route: redactUrl(str(page.route, 2000) || "/").replace(/^https?:\/\/[^/]+/, ""),
      title: redactText(str(page.title, 300)),
      lang: str(page.lang, 20),
    },
    viewport: {
      width: num(viewport.width),
      height: num(viewport.height),
      device_pixel_ratio: num(viewport.device_pixel_ratio),
    },
    user: {
      signed_in: typeof user.signed_in === "boolean" ? user.signed_in : null,
      role: str(user.role, 60) || null,
      id_hash: /^[0-9a-f]{8,64}$/.test(str(user.id_hash, 64)) ? str(user.id_hash, 64) : null,
    },
    console_errors: list(c.console_errors).map((e) => ({
      at: str(e.at, 40),
      level: str(e.level, 20) || "error",
      message: redactText(str(e.message)),
    })),
    failed_requests: list(c.failed_requests).map((e) => ({
      at: str(e.at, 40),
      method: str(e.method, 10).toUpperCase() || "GET",
      url: redactUrl(str(e.url, 2000)),
      status: num(e.status),
      error: e.error ? redactText(str(e.error)) : null,
    })),
    screenshot: null,
    screenshot_error: c.screenshot_error ? redactText(str(c.screenshot_error)) : null,
    dom: typeof c.dom === "string" && c.dom ? redactDom(c.dom) : null,
  };
}

const URGENCY: Urgency[] = ["low", "normal", "high"];

// The four fields of the form, or the list of faults. The client's words stay as typed.
export function parseForm(input: unknown): { form: RequestForm } | { faults: string[] } {
  const f = obj(input);
  const form: RequestForm = {
    what: str(f.what, 1000).trim(),
    where: str(f.where, 300).trim(),
    urgency: URGENCY.includes(f.urgency as Urgency) ? (f.urgency as Urgency) : "normal",
    words: str(f.words, 10_000),
  };
  const faults: string[] = [];
  if (!form.what) faults.push("what is empty");
  if (!form.words.trim()) faults.push("words is empty");
  return faults.length ? { faults } : { form };
}

export function oneLine(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

// The first AC line of a button request. The repo session makes it exact at `specified`.
export function acLine(route: string, where: string, what: string): string {
  return `AC-1: WHEN a person opens ${oneLine(route) || "/"} THE ${oneLine(where) || "page"} SHALL ${oneLine(what)}`;
}

// The next number of REQ-<slug>-<n> after each name of the list.
export function nextNumber(names: string[], slug: string): number {
  const pattern = new RegExp(`REQ-${slug.replace(/[^a-z0-9-]/g, "")}-(\\d+)\\b`);
  return names.reduce((max, name) => Math.max(max, Number(pattern.exec(name)?.[1] ?? 0)), 0) + 1;
}

function quote(words: string): string {
  return words
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .map((line) => (line ? `> ${line}` : ">"))
    .join("\n");
}

export type RecordInput = {
  id: string | null;
  date: string;
  form: RequestForm;
  capture: Capture;
  screenshot: string;
  captureFile: string;
};

// The request record of features/requests.md. With an id: a file of .icm/requests/ (front
// matter). With no id: the description of a Linear ticket (field lines; the key is the id).
export function buildRecord(r: RecordInput): string {
  const fields: [string, string][] = [
    ["source", "button"],
    ["date", r.date],
    ["page_url", r.capture.page.url],
    ["status", "received"],
    ["conflicts", ""],
  ];
  const head = r.id
    ? ["---", `id: ${r.id}`, ...fields.map(([k, v]) => `${k}: ${v}`.trimEnd()), "linear:", "---", `# ${oneLine(r.form.what).slice(0, 80)}`]
    : fields.map(([k, v]) => `- ${k}: ${v}`.trimEnd());
  return [
    ...head,
    "",
    "## Client words",
    "",
    quote(r.form.words),
    "",
    "## Acceptance criteria",
    "",
    acLine(r.capture.page.route, r.form.where, r.form.what),
    "",
    "## Details",
    "",
    `- where: ${oneLine(r.form.where) || "-"}`,
    `- urgency: ${r.form.urgency}`,
    `- capture: ${r.captureFile}`,
    `- screenshot: ${r.screenshot}`,
    `- console errors: ${r.capture.console_errors.length}, failed requests: ${r.capture.failed_requests.length}`,
    "",
  ].join("\n");
}
