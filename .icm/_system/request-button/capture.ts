// capture.ts — what the browser adds to a request: the baxter.capture/1 fields, a picture
// of the page and an optional DOM snapshot (blueprint 1.0.0-rc27; CAPTURE.md).
// It never reads a cookie, storage or a form value. The server redacts each field again.
import { MAX_ENTRIES, MAX_MESSAGE, redactText, redactUrl } from "./core";
import type { CaptureEntry, CaptureUser, FailedRequest } from "./core";

const consoleErrors: CaptureEntry[] = [];
const failedRequests: FailedRequest[] = [];
let watching = false;

function keep<T>(items: T[], item: T): void {
  items.push(item);
  if (items.length > MAX_ENTRIES) items.shift();
}
function show(value: unknown): string {
  if (value instanceof Error) return `${value.name}: ${value.message}`;
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
}
function error(level: string, parts: unknown[]): void {
  keep(consoleErrors, {
    at: new Date().toISOString(),
    level,
    message: redactText(parts.map(show).join(" ")).slice(0, MAX_MESSAGE),
  });
}
function failed(method: string, url: string, status: number, reason: string | null): void {
  if (url.includes("/api/baxter-request")) return;
  keep(failedRequests, {
    at: new Date().toISOString(),
    method: method.toUpperCase(),
    url: redactUrl(url, location.href),
    status,
    error: reason ? redactText(reason).slice(0, MAX_MESSAGE) : null,
  });
}

// Record console errors, page errors and failed requests from now on. One time only.
export function watch(): void {
  if (watching || typeof window === "undefined") return;
  watching = true;
  const consoleError = console.error.bind(console);
  console.error = (...parts: unknown[]) => {
    error("error", parts);
    consoleError(...parts);
  };
  window.addEventListener("error", (event) => error("uncaught", [event.message]));
  window.addEventListener("unhandledrejection", (event) => error("unhandled-rejection", [event.reason]));
  const fetchOriginal = window.fetch.bind(window);
  window.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const method = init?.method ?? (input instanceof Request ? input.method : "GET");
    try {
      const response = await fetchOriginal(input, init);
      if (!response.ok) failed(method, url, response.status, null);
      return response;
    } catch (reason) {
      failed(method, url, 0, show(reason));
      throw reason;
    }
  };
  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (this: XMLHttpRequest, method: string, url: string | URL, ...rest: unknown[]) {
    this.addEventListener("loadend", () => {
      if (this.status === 0 || this.status >= 400) failed(method, String(url), this.status, null);
    });
    return (open as (...args: unknown[]) => void).call(this, method, url, ...rest);
  } as typeof XMLHttpRequest.prototype.open;
}

// A copy of the page with no script, no frame, no form value, no button of this request,
// and no e-mail address or token in a text or an attribute.
function cleanCopy(): HTMLElement {
  const root = document.documentElement.cloneNode(true) as HTMLElement;
  root
    .querySelectorAll("script, noscript, iframe, object, embed, template, [data-baxter-request], meta:not([charset]):not([name=viewport])")
    .forEach((node) => node.remove());
  root.querySelectorAll("input, textarea, select, option").forEach((node) => {
    for (const name of ["value", "checked", "selected", "placeholder"]) node.removeAttribute(name);
    if (node.tagName === "TEXTAREA") node.textContent = "";
  });
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const text = node.nodeValue ?? "";
    const clean = redactText(text);
    if (clean !== text) node.nodeValue = clean;
  }
  root.querySelectorAll("*").forEach((node) => {
    for (const attr of Array.from(node.attributes)) {
      if ((attr.name === "src" || attr.name === "srcset") && node.tagName === "IMG") continue;
      const clean = attr.name === "href" || attr.name === "src" || attr.name === "action"
        ? redactUrl(attr.value, location.href)
        : redactText(attr.value);
      if (clean !== attr.value) node.setAttribute(attr.name, clean);
    }
  });
  return root;
}

function dom(): string {
  const root = cleanCopy();
  root.querySelectorAll("img").forEach((img) => {
    img.removeAttribute("srcset");
    img.setAttribute("src", redactUrl(img.getAttribute("src") ?? "", location.href));
  });
  return new XMLSerializer().serializeToString(root);
}

function styles(): string {
  let css = "";
  for (const sheet of Array.from(document.styleSheets)) {
    try {
      for (const rule of Array.from(sheet.cssRules)) css += `${rule.cssText}\n`;
    } catch {
      // A style sheet of another origin cannot be read. The picture has no such rules.
    }
  }
  // In the picture, the html element is not the root: give it the rules of :root.
  return css.replace(/:root\b/g, "html");
}

function imageData(img: HTMLImageElement): string | null {
  if (!img.complete || !img.naturalWidth) return null;
  const scale = Math.min(1, 800 / img.naturalWidth);
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(img.naturalWidth * scale));
  canvas.height = Math.max(1, Math.round(img.naturalHeight * scale));
  try {
    canvas.getContext("2d")?.drawImage(img, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL("image/png");
  } catch {
    return null; // an image of another origin
  }
}

function withTimeout<T>(work: Promise<T>, ms: number): Promise<T> {
  return Promise.race([work, new Promise<T>((_, reject) => setTimeout(() => reject(new Error("timeout")), ms))]);
}

// A picture of the visible part of the page, made from the clean copy (method
// "dom-render"): a PNG or JPEG data URL. Images of another origin are blank.
async function picture(): Promise<string> {
  const width = window.innerWidth;
  const height = window.innerHeight;
  const data = new Map<string, string>();
  for (const img of Array.from(document.images).slice(0, 60)) {
    const url = imageData(img);
    if (url) data.set(img.src, url);
  }
  const root = cleanCopy();
  root.querySelectorAll("img").forEach((img) => {
    img.removeAttribute("srcset");
    img.setAttribute("src", data.get((img as HTMLImageElement).src) ?? "");
  });
  root.querySelectorAll('link[rel="stylesheet"], style').forEach((node) => node.remove());
  const style = document.createElement("style");
  style.textContent = styles();
  root.querySelector("head")?.appendChild(style);
  const full = Math.max(document.documentElement.scrollHeight, height);
  const xml = new XMLSerializer().serializeToString(root);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="${window.scrollX} ${window.scrollY} ${width} ${height}"><foreignObject x="0" y="0" width="${width}" height="${full}">${xml}</foreignObject></svg>`;
  const image = new Image();
  image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
  await withTimeout(image.decode(), 8000);
  const scale = Math.min(1, 1600 / width);
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  const context = canvas.getContext("2d");
  if (!context) throw new Error("no canvas");
  context.fillStyle = getComputedStyle(document.body).backgroundColor || "#fff";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  const png = canvas.toDataURL("image/png");
  return png.length < 3_000_000 ? png : canvas.toDataURL("image/jpeg", 0.75);
}

export type BrowserCapture = {
  capture: Record<string, unknown>;
  screenshot: string | null;
};

// The capture of this moment. The server adds `app` and redacts each field again.
export async function collect(user: CaptureUser, withDom: boolean): Promise<BrowserCapture> {
  let screenshot: string | null = null;
  let screenshotError: string | null = null;
  try {
    screenshot = await picture();
  } catch (reason) {
    screenshotError = show(reason);
  }
  return {
    screenshot,
    capture: {
      page: {
        url: redactUrl(location.href),
        route: location.pathname,
        title: document.title,
        lang: document.documentElement.lang || navigator.language,
      },
      viewport: { width: window.innerWidth, height: window.innerHeight, device_pixel_ratio: window.devicePixelRatio },
      user,
      console_errors: [...consoleErrors],
      failed_requests: [...failedRequests],
      screenshot_error: screenshotError,
      dom: withDom ? dom() : null,
    },
  };
}
