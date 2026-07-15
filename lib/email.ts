// Transactional email via Resend's HTTP API — no SDK dependency, just fetch.
//
// Configuration (all optional; the module degrades gracefully):
//   RESEND_API_KEY   — from https://resend.com. When unset, sends become
//                      logged no-ops so the booking flow never breaks.
//   RESEND_FROM      — verified sender, e.g. 'Vine Cliff <stay@vinecliff.com>'.
//                      Defaults to Resend's shared onboarding sender, which
//                      only delivers to the Resend account owner — fine for
//                      testing, replace for production.
//   NEXT_PUBLIC_SITE_URL — absolute origin used in email links; falls back to
//                      the canonical site URL.
//
// Email delivery is best-effort by design: a failed send is logged and
// swallowed so a guest's booking request is never lost to a mail outage.
import { site } from "@/lib/site";
import { formatDate, type ISODate } from "@/lib/booking/dates";
import { formatMoney, type Quote } from "@/lib/booking/pricing";

export function siteBaseUrl(): string {
  return (process.env.NEXT_PUBLIC_SITE_URL ?? site.url).replace(/\/+$/, "");
}

export type EmailMessage = {
  to: string;
  subject: string;
  html: string;
  replyTo?: string;
};

export async function sendEmail(message: EmailMessage): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    console.log(
      `[email] RESEND_API_KEY not set — skipping "${message.subject}" to ${message.to}`
    );
    return;
  }
  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: process.env.RESEND_FROM ?? "Vine Cliff <onboarding@resend.dev>",
        to: [message.to],
        subject: message.subject,
        html: message.html,
        ...(message.replyTo ? { reply_to: message.replyTo } : {}),
      }),
    });
    if (!response.ok) {
      console.error(
        `[email] Resend rejected "${message.subject}" to ${message.to}: ${response.status} ${await response.text()}`
      );
    }
  } catch (error) {
    console.error(`[email] Failed to send "${message.subject}":`, error);
  }
}

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// ---------------------------------------------------------------------------
// Layout + building blocks (inline styles only — this is email HTML).
// ---------------------------------------------------------------------------

const palette = {
  pine: "#294032",
  pineDark: "#1a2a20",
  cream: "#f7f2e7",
  creamLight: "#fbf8f0",
  ink: "#23271d",
  inkSoft: "#3c4235",
  stone: "#8a8472",
  amber: "#c8812f",
  border: "#e4dcc9",
};

function layout(heading: string, bodyHtml: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<body style="margin:0;padding:0;background-color:${palette.cream};">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:${palette.cream};padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background-color:${palette.creamLight};border-radius:16px;overflow:hidden;border:1px solid ${palette.border};">
        <tr>
          <td style="background-color:${palette.pineDark};padding:28px 32px;text-align:center;">
            <p style="margin:0;font-family:Georgia,'Times New Roman',serif;font-size:26px;color:${palette.cream};letter-spacing:0.02em;">Vine&nbsp;Cliff</p>
            <p style="margin:6px 0 0;font-family:Helvetica,Arial,sans-serif;font-size:10px;letter-spacing:0.28em;text-transform:uppercase;color:#dda657;">Vineyards · Est. 1850</p>
          </td>
        </tr>
        <tr>
          <td style="padding:32px;">
            <h1 style="margin:0 0 16px;font-family:Georgia,'Times New Roman',serif;font-weight:normal;font-size:22px;line-height:1.3;color:${palette.ink};">${heading}</h1>
            ${bodyHtml}
          </td>
        </tr>
        <tr>
          <td style="padding:20px 32px 28px;border-top:1px solid ${palette.border};">
            <p style="margin:0;font-family:Helvetica,Arial,sans-serif;font-size:12px;line-height:1.7;color:${palette.stone};">
              ${site.fullName} · ${site.address.full}<br>
              <a href="tel:${site.phone.replace(/[^+\d]/g, "")}" style="color:${palette.stone};">${site.phone}</a> ·
              <a href="mailto:${site.email}" style="color:${palette.stone};">${site.email}</a>
            </p>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function paragraph(html: string): string {
  return `<p style="margin:0 0 16px;font-family:Helvetica,Arial,sans-serif;font-size:15px;line-height:1.7;color:${palette.inkSoft};">${html}</p>`;
}

function button(href: string, label: string): string {
  return `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 20px;"><tr><td style="border-radius:999px;background-color:${palette.pine};">
    <a href="${href}" style="display:inline-block;padding:12px 28px;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:bold;color:${palette.cream};text-decoration:none;">${label}</a>
  </td></tr></table>`;
}

function detailRows(rows: Array<[string, string]>): string {
  const body = rows
    .map(
      ([label, value]) => `<tr>
        <td style="padding:8px 0;font-family:Helvetica,Arial,sans-serif;font-size:13px;color:${palette.stone};vertical-align:top;white-space:nowrap;padding-right:24px;">${label}</td>
        <td style="padding:8px 0;font-family:Helvetica,Arial,sans-serif;font-size:14px;color:${palette.ink};text-align:right;">${value}</td>
      </tr>`
    )
    .join(`<tr><td colspan="2" style="border-top:1px solid ${palette.border};font-size:0;line-height:0;">&nbsp;</td></tr>`);
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:4px 0 20px;background-color:${palette.cream};border-radius:12px;padding:8px 20px;"><tbody>${body}</tbody></table>`;
}

function quoteRows(quote: Quote, label = "Estimated total"): Array<[string, string]> {
  return [
    ...quote.lines.map(
      (line) => [escapeHtml(line.label), formatMoney(line.amountCents)] as [string, string]
    ),
    [`<strong>${label}</strong>`, `<strong>${formatMoney(quote.totalCents)}</strong>`],
  ];
}

function finePrint(text: string): string {
  return `<p style="margin:16px 0 0;font-family:Helvetica,Arial,sans-serif;font-size:12px;line-height:1.7;color:${palette.stone};">${text}</p>`;
}

// ---------------------------------------------------------------------------
// Templates. Each returns { subject, html }; actions decide the recipient.
// ---------------------------------------------------------------------------

export type BookingEmailData = {
  reference: string;
  spaceName: string;
  isEvent: boolean;
  startDate: ISODate;
  endDate: ISODate;
  partySize: number;
  guestFirstName: string;
  manageToken: string;
  quote?: Quote;
  totalCents?: number;
  policy?: string | null;
  note?: string | null;
};

function stayRows(data: BookingEmailData): Array<[string, string]> {
  return [
    ["Reference", `<strong>${escapeHtml(data.reference)}</strong>`],
    ["Space", escapeHtml(data.spaceName)],
    [data.isEvent ? "First day" : "Check-in", formatDate(data.startDate)],
    [data.isEvent ? "Last day (departure)" : "Checkout", formatDate(data.endDate)],
    ["Guests", String(data.partySize)],
  ];
}

function statusUrl(token: string): string {
  return `${siteBaseUrl()}/bookings/${token}`;
}

export function requestReceivedEmail(data: BookingEmailData) {
  const rows = stayRows(data);
  if (data.quote) rows.push(...quoteRows(data.quote));
  return {
    subject: `We've received your request — ${data.reference}`,
    html: layout(
      `Thank you, ${escapeHtml(data.guestFirstName)} — your request is in`,
      [
        paragraph(
          `We've received your request for <strong>${escapeHtml(data.spaceName)}</strong>. Every request is reviewed personally, and we'll come back to you within a day or two.`
        ),
        detailRows(rows),
        paragraph(`You can check the status of your request any time:`),
        button(statusUrl(data.manageToken), "View your request"),
        data.policy ? finePrint(escapeHtml(data.policy)) : "",
      ].join("")
    ),
  };
}

export function bookingApprovedEmail(data: BookingEmailData) {
  const rows = stayRows(data);
  if (data.totalCents != null) {
    rows.push([
      "<strong>Total</strong>",
      `<strong>${formatMoney(data.totalCents)}</strong>`,
    ]);
  }
  return {
    subject: `You're booked at Vine Cliff — ${data.reference}`,
    html: layout(
      `Wonderful news, ${escapeHtml(data.guestFirstName)} — you're booked`,
      [
        paragraph(
          `Your ${data.isEvent ? "event at" : "stay in"} <strong>${escapeHtml(data.spaceName)}</strong> is confirmed. We can't wait to welcome you to the cliff top.`
        ),
        data.note ? paragraph(`<em>“${escapeHtml(data.note)}”</em>`) : "",
        detailRows(rows),
        paragraph(
          `We'll be in touch shortly about the deposit and arrival details. Your booking page always has the latest:`
        ),
        button(statusUrl(data.manageToken), "View your booking"),
        data.policy ? finePrint(escapeHtml(data.policy)) : "",
      ].join("")
    ),
  };
}

export function bookingDeclinedEmail(data: BookingEmailData) {
  return {
    subject: `About your Vine Cliff request — ${data.reference}`,
    html: layout(
      `About your request, ${escapeHtml(data.guestFirstName)}`,
      [
        paragraph(
          `We're sorry — we aren't able to host your requested dates for <strong>${escapeHtml(data.spaceName)}</strong> this time.`
        ),
        data.note ? paragraph(`<em>“${escapeHtml(data.note)}”</em>`) : "",
        detailRows(stayRows(data)),
        paragraph(
          `Different dates often work beautifully — reply to this email or call us on <a href="tel:${site.phone.replace(/[^+\d]/g, "")}" style="color:${palette.pine};">${site.phone}</a> and we'll find them together.`
        ),
      ].join("")
    ),
  };
}

export function bookingCancelledEmail(data: BookingEmailData) {
  return {
    subject: `Your Vine Cliff booking is cancelled — ${data.reference}`,
    html: layout(
      `Your booking has been cancelled`,
      [
        paragraph(
          `Your ${data.isEvent ? "event" : "stay"} booking for <strong>${escapeHtml(data.spaceName)}</strong> (${data.reference}) has been cancelled.`
        ),
        data.note ? paragraph(`<em>“${escapeHtml(data.note)}”</em>`) : "",
        detailRows(stayRows(data)),
        paragraph(
          `If this is a surprise, or you'd like to rebook, just reply to this email — we'd love to see you another time.`
        ),
        data.policy ? finePrint(escapeHtml(data.policy)) : "",
      ].join("")
    ),
  };
}

// --- Owner-facing notifications --------------------------------------------

export type OwnerBookingEmailData = BookingEmailData & {
  guestFullName: string;
  guestEmail: string;
  guestPhone?: string | null;
  message?: string | null;
  eventType?: string | null;
};

function adminBookingUrl(reference: string): string {
  return `${siteBaseUrl()}/admin/bookings?q=${encodeURIComponent(reference)}`;
}

export function ownerNewRequestEmail(data: OwnerBookingEmailData) {
  const rows = stayRows(data);
  if (data.eventType) rows.splice(2, 0, ["Occasion", escapeHtml(data.eventType)]);
  rows.push(
    ["Guest", escapeHtml(data.guestFullName)],
    ["Email", `<a href="mailto:${escapeHtml(data.guestEmail)}" style="color:${palette.pine};">${escapeHtml(data.guestEmail)}</a>`]
  );
  if (data.guestPhone) rows.push(["Phone", escapeHtml(data.guestPhone)]);
  if (data.quote) rows.push(...quoteRows(data.quote));
  return {
    subject: `New booking request · ${data.spaceName} · ${data.reference}`,
    html: layout(
      "New booking request",
      [
        paragraph(
          `<strong>${escapeHtml(data.guestFullName)}</strong> has requested ${data.isEvent ? "an event at" : "a stay in"} <strong>${escapeHtml(data.spaceName)}</strong>.`
        ),
        detailRows(rows),
        data.message
          ? paragraph(`Their message:<br><em>“${escapeHtml(data.message)}”</em>`)
          : "",
        button(adminBookingUrl(data.reference), "Review in admin"),
      ].join("")
    ),
  };
}

export function ownerRequestWithdrawnEmail(data: OwnerBookingEmailData) {
  return {
    subject: `Request withdrawn · ${data.reference}`,
    html: layout(
      "A booking request was withdrawn",
      [
        paragraph(
          `<strong>${escapeHtml(data.guestFullName)}</strong> has withdrawn their pending request <strong>${data.reference}</strong> (${escapeHtml(data.spaceName)}, ${formatDate(data.startDate)}). No action needed — the dates were never blocked.`
        ),
        button(adminBookingUrl(data.reference), "View in admin"),
      ].join("")
    ),
  };
}

export function ownerCancelRequestedEmail(data: OwnerBookingEmailData) {
  return {
    subject: `Cancellation requested · ${data.reference}`,
    html: layout(
      "A guest has asked to cancel",
      [
        paragraph(
          `<strong>${escapeHtml(data.guestFullName)}</strong> has requested to cancel booking <strong>${data.reference}</strong> (${escapeHtml(data.spaceName)}, ${formatDate(data.startDate)}).`
        ),
        button(adminBookingUrl(data.reference), "Review in admin"),
      ].join("")
    ),
  };
}

export type EnquiryEmailData = {
  name: string;
  email: string;
  phone?: string | null;
  spaceName?: string | null;
  message: string;
};

export function ownerNewEnquiryEmail(data: EnquiryEmailData) {
  const rows: Array<[string, string]> = [
    ["From", escapeHtml(data.name)],
    ["Email", `<a href="mailto:${escapeHtml(data.email)}" style="color:${palette.pine};">${escapeHtml(data.email)}</a>`],
  ];
  if (data.phone) rows.push(["Phone", escapeHtml(data.phone)]);
  if (data.spaceName) rows.push(["About", escapeHtml(data.spaceName)]);
  return {
    subject: `New enquiry from ${data.name}`,
    html: layout(
      "New enquiry from the website",
      [
        detailRows(rows),
        paragraph(`<em>“${escapeHtml(data.message)}”</em>`),
        button(`${siteBaseUrl()}/admin/enquiries`, "Open enquiries"),
      ].join("")
    ),
  };
}
