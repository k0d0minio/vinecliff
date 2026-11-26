# The capture shape `baxter.capture/1`

Language: en
Owner: the blueprint (1.0.0-rc27, JAM-577). The checktest engine of BAXTER reads and writes
the same field names. A change of a field is a new schema name, `baxter.capture/2`.

A capture is one JSON object: what the browser showed when the client made a request.
The request button writes it as `REQ-<slug>-<n>.capture.json` beside the request, or as an
upload of the Linear ticket.

| Field | Type | Value |
|---|---|---|
| `schema` | string | `baxter.capture/1` |
| `captured_at` | string | ISO 8601 time of the server |
| `app.repo` | string | `slug` of `.icm/project.json` |
| `app.env` | string | `local`, `uat` or `production` |
| `app.version` | string | `BAXTER_REQUEST_VERSION`, the first 12 characters of `VERCEL_GIT_COMMIT_SHA`, or `unknown` |
| `page.url` | string | The address, redacted |
| `page.route` | string | The path, redacted |
| `page.title` | string | The title of the document |
| `page.lang` | string | `lang` of the page |
| `viewport.width`, `viewport.height` | number | CSS pixels |
| `viewport.device_pixel_ratio` | number | |
| `user.signed_in` | boolean or null | null: the layout gave no user |
| `user.role` | string or null | |
| `user.id_hash` | string or null | The first 16 hex digits of SHA-256 of `<slug>:<user id>` |
| `console_errors[]` | `{at, level, message}` | The last 50: `console.error`, uncaught errors, unhandled rejections |
| `failed_requests[]` | `{at, method, url, status, error}` | The last 50 fetch and XHR calls with status 0 or 400 and more. Status 0: no answer |
| `screenshot` | `{file, type, method}` or null | `file`: the file name, or the upload URL. `method`: `dom-render` |
| `screenshot_error` | string or null | Why there is no screenshot |
| `dom` | string or null | The DOM snapshot: XHTML, 300,000 characters at most |

## What a capture never has
No cookie, no storage, no token, no password, no form value and no e-mail address.
- The browser does not read cookies or storage.
- The screenshot and the DOM snapshot come from a copy of the page with no script, no
  frame, no `meta` but charset and viewport, no `value`, `checked` or `selected`, no
  textarea text, and no request button.
- Text and attributes: e-mail addresses become `[email]`; JWTs, `Bearer` values,
  `password=` pairs and opaque values of 32 characters or more become `[hidden]`.
- Addresses: no user or password; a query value with a secret name or a secret value
  becomes `hidden`; a path part with a secret becomes `hidden`; a fragment with `=` is
  removed.
- The server redacts each field again (`sanitizeCapture` of `core.ts`). The server sets `app`.

## The limits of the screenshot
`dom-render` draws a copy of the page in an SVG image. It is not a copy of the pixels.
Images and style sheets of another origin, web fonts and canvas content do not show. A
fixed element shows at the top of the page.
