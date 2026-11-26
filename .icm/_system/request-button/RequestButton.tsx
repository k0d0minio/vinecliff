// RequestButton.tsx — the request button of a client repo (blueprint 1.0.0-rc27).
// Add it to the root layout, in <body>: <RequestButton />. It renders nothing outside a
// test environment (buttonEnv of core.ts). The rules: .icm/_system/features/requests.md.
import { createHash } from "node:crypto";
import project from "../../project.json";
import RequestButtonClient from "./RequestButtonClient";
import { buttonEnv } from "./core";
import type { CaptureUser } from "./core";

export type RequestButtonUser = { signedIn: boolean; role?: string | null; id?: string | null };

type Props = {
  /** The signed-in person, when the layout knows it. The id leaves the server only as a hash. */
  user?: RequestButtonUser;
  /** The language of the form: en, fr or pt. Default: the lang of the page. */
  lang?: string;
  /** false: no DOM snapshot in the capture. */
  dom?: boolean;
};

export function RequestButton({ user, lang, dom = true }: Props) {
  const env = buttonEnv(process.env);
  if (!env) return null;
  const idHash = user?.id
    ? createHash("sha256").update(`${project.slug}:${user.id}`).digest("hex").slice(0, 16)
    : null;
  const captured: CaptureUser = { signed_in: user ? user.signedIn : null, role: user?.role ?? null, id_hash: idHash };
  return <RequestButtonClient env={env} lang={lang} dom={dom} user={captured} />;
}

export default RequestButton;
