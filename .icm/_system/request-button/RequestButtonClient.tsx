"use client";
// RequestButtonClient.tsx — the button and the form of a client request (blueprint
// 1.0.0-rc27). RequestButton.tsx shows it only in a test environment.
import { useState } from "react";
import type { CSSProperties, FormEvent } from "react";
import { collect, watch } from "./capture";
import type { BrowserCapture } from "./capture";
import type { CaptureUser, Urgency } from "./core";

watch();

const TEXT = {
  en: {
    open: "Request", title: "Ask for a change", what: "What should the app do?",
    where: "Where? (the page or the element)", urgency: "How urgent?",
    low: "It can wait", normal: "Soon", high: "It blocks me", words: "Tell us in your own words",
    note: "We also save a picture of this page and technical details. No password, no form value.",
    send: "Send", cancel: "Cancel", wait: "One moment…", sent: "Thank you. Your request is recorded:",
    fail: "The request was not sent:", close: "Close",
  },
  fr: {
    open: "Demande", title: "Demander un changement", what: "Que doit faire l'application ?",
    where: "Où ? (la page ou l'élément)", urgency: "Quelle urgence ?",
    low: "Ça peut attendre", normal: "Bientôt", high: "Ça me bloque", words: "Dites-le avec vos mots",
    note: "Nous enregistrons aussi une image de cette page et des détails techniques. Aucun mot de passe, aucune valeur de formulaire.",
    send: "Envoyer", cancel: "Annuler", wait: "Un instant…", sent: "Merci. Votre demande est enregistrée :",
    fail: "La demande n'a pas été envoyée :", close: "Fermer",
  },
  pt: {
    open: "Pedido", title: "Pedir uma alteração", what: "O que deve fazer a aplicação?",
    where: "Onde? (a página ou o elemento)", urgency: "Qual a urgência?",
    low: "Pode esperar", normal: "Em breve", high: "Está a bloquear-me", words: "Diga-nos por palavras suas",
    note: "Também guardamos uma imagem desta página e detalhes técnicos. Sem palavras-passe nem valores de formulários.",
    send: "Enviar", cancel: "Cancelar", wait: "Um momento…", sent: "Obrigado. O seu pedido foi registado:",
    fail: "O pedido não foi enviado:", close: "Fechar",
  },
};
type Lang = keyof typeof TEXT;
function pick(lang: string): Lang {
  const code = lang.slice(0, 2).toLowerCase();
  return code === "fr" || code === "pt" ? code : "en";
}

const Z = 2147483000;
const box: CSSProperties = {
  position: "fixed", inset: 0, zIndex: Z, background: "rgba(0,0,0,.45)", display: "flex",
  alignItems: "center", justifyContent: "center", padding: 16, fontFamily: "system-ui, sans-serif",
};
const panel: CSSProperties = {
  background: "#fff", color: "#111", borderRadius: 12, padding: 20, width: "100%", maxWidth: 480,
  maxHeight: "90vh", overflow: "auto", boxShadow: "0 10px 40px rgba(0,0,0,.3)", fontSize: 15,
};
const field: CSSProperties = {
  display: "block", width: "100%", boxSizing: "border-box", marginTop: 4, marginBottom: 12, padding: 8,
  border: "1px solid #999", borderRadius: 6, font: "inherit", color: "#111", background: "#fff",
};
const button: CSSProperties = {
  padding: "8px 16px", borderRadius: 6, border: "1px solid #111", font: "inherit", cursor: "pointer",
};
const dark: CSSProperties = { ...button, background: "#111", color: "#fff" };
const light: CSSProperties = { ...button, background: "#fff", color: "#111" };
const floating: CSSProperties = {
  ...dark, position: "fixed", right: 16, bottom: 16, zIndex: Z, borderRadius: 999,
  boxShadow: "0 4px 16px rgba(0,0,0,.3)", fontFamily: "system-ui, sans-serif",
};
const heading: CSSProperties = { margin: "0 0 12px", fontSize: 18 };
const note: CSSProperties = { fontSize: 13, color: "#444", margin: "0 0 12px" };
const row: CSSProperties = { display: "flex", gap: 8, justifyContent: "flex-end" };

type Props = { env: string; user: CaptureUser; lang?: string; dom?: boolean; endpoint?: string };
type State =
  | { step: "closed" }
  | { step: "capturing" }
  | { step: "form"; taken: BrowserCapture }
  | { step: "sending" }
  | { step: "done"; id: string; url: string | null }
  | { step: "failed"; reason: string };

export default function RequestButtonClient({ env, user, lang = "", dom = true, endpoint = "/api/baxter-request" }: Props) {
  const [state, setState] = useState<State>({ step: "closed" });
  const [language, setLanguage] = useState<Lang>(pick(lang || "en"));
  const t = TEXT[language];

  async function start() {
    setLanguage(pick(lang || document.documentElement.lang || navigator.language));
    setState({ step: "capturing" });
    setState({ step: "form", taken: await collect(user, dom) });
  }

  async function send(event: FormEvent<HTMLFormElement>, taken: BrowserCapture) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    setState({ step: "sending" });
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          form: {
            what: String(data.get("what") ?? ""),
            where: String(data.get("where") ?? ""),
            urgency: String(data.get("urgency") ?? "normal") as Urgency,
            words: String(data.get("words") ?? ""),
          },
          capture: taken.capture,
          screenshot: taken.screenshot,
        }),
      });
      const answer = (await response.json()) as { ok?: boolean; id?: string; url?: string | null; error?: string };
      if (answer.ok && answer.id) setState({ step: "done", id: answer.id, url: answer.url ?? null });
      else setState({ step: "failed", reason: answer.error ?? `HTTP ${response.status}` });
    } catch (reason) {
      setState({ step: "failed", reason: String(reason) });
    }
  }

  const close = () => setState({ step: "closed" });
  return (
    <div data-baxter-request={env}>
      {state.step === "closed" && (
        <button
          type="button"
          onClick={start}
          aria-label={t.title}
          style={floating}
        >
          {t.open}
        </button>
      )}
      {state.step !== "closed" && (
        <div style={box} onKeyDown={(e) => e.key === "Escape" && close()}>
          <div role="dialog" aria-modal="true" aria-label={t.title} style={panel}>
            <h2 style={heading}>{t.title}</h2>
            {(state.step === "capturing" || state.step === "sending") && <p>{t.wait}</p>}
            {state.step === "form" && (
              <form onSubmit={(e) => send(e, state.taken)}>
                <label>{t.what}<input name="what" required maxLength={1000} style={field} autoFocus /></label>
                <label>{t.where}<input name="where" maxLength={300} defaultValue={document.title} style={field} /></label>
                <label>
                  {t.urgency}
                  <select name="urgency" defaultValue="normal" style={field}>
                    <option value="low">{t.low}</option>
                    <option value="normal">{t.normal}</option>
                    <option value="high">{t.high}</option>
                  </select>
                </label>
                <label>{t.words}<textarea name="words" required rows={5} maxLength={10000} style={field} /></label>
                <p style={note}>{t.note}</p>
                <div style={row}>
                  <button type="button" onClick={close} style={light}>{t.cancel}</button>
                  <button type="submit" style={dark}>{t.send}</button>
                </div>
              </form>
            )}
            {(state.step === "done" || state.step === "failed") && (
              <>
                <p>
                  {state.step === "done" ? `${t.sent} ${state.id}` : `${t.fail} ${state.reason}`}
                </p>
                <button type="button" onClick={close} style={dark}>{t.close}</button>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
