// Emails the moderator when a report is filed.
//
// Called by a Supabase Database Webhook on inserts into public.reports, not by the app, so a
// modified client can't file a report without the alert going out. See docs/moderation.md.
//
// Deploy:  supabase functions deploy report-notify --no-verify-jwt
// Secrets: REPORT_WEBHOOK_SECRET, RESEND_API_KEY, MODERATOR_EMAIL, REPORT_EMAIL_FROM
Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  // JWT checks are off for this function because webhooks don't carry one. This replaces them.
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("REPORT_WEBHOOK_SECRET")) {
    return new Response("Forbidden", { status: 403 });
  }

  const { record } = await req.json();
  const snapshot = record.snapshot ?? {};
  const lines = [
    `Reason: ${record.reason}`,
    `Reported: ${record.target_type} by @${snapshot.username} (${snapshot.display_name})`,
    record.details ? `Reporter's note: ${record.details}` : null,
    snapshot.notes ? `Notes: ${snapshot.notes}` : null,
    snapshot.dishes?.length ? `Dishes: ${snapshot.dishes.join(", ")}` : null,
    snapshot.system_name ? `Ranking system: ${snapshot.system_name}` : null,
    snapshot.photo_paths?.length ? `Photos: ${snapshot.photo_paths.length}` : null,
    "",
    "Open Profile → Moderation queue in the app to act on this within 24 hours.",
    `Report ID: ${record.id}`,
  ];

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: Deno.env.get("REPORT_EMAIL_FROM"),
      to: Deno.env.get("MODERATOR_EMAIL"),
      subject: `New report: ${record.reason} (${record.target_type})`,
      text: lines.filter((line) => line !== null).join("\n"),
    }),
  });
  if (!response.ok) {
    return new Response(`Could not send the email: ${await response.text()}`, { status: 502 });
  }
  return new Response("sent", { status: 200 });
});
