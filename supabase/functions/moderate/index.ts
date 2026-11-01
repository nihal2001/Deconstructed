// Carries out a moderator's decision on a report.
//
// The database functions check the caller is a moderator and make the database changes. This
// function finishes the parts SQL can't reach: Storage files and the auth user. It runs them
// before closing the report, so a failure leaves the report in the queue to be tried again.
//
// Deploy:  supabase functions deploy moderate
import { createClient } from "jsr:@supabase/supabase-js@2";
import { BUCKET, removeAllPhotos } from "../_shared/photos.ts";

// About 100 years. Supabase has no permanent ban; this is the documented way to get one.
const PERMANENT_BAN = "876000h";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Missing Authorization header" }, 401);
  }
  const { report_id: reportID, action } = await req.json();

  const url = Deno.env.get("SUPABASE_URL")!;
  // Calls run as the moderator, so the moderator check in the database applies to them.
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: steps, error: moderateError } = await asUser.rpc("moderate_report", {
    p_report_id: reportID,
    p_action: action,
  });
  if (moderateError) {
    return json({ error: moderateError.message }, moderateError.code === "42501" ? 403 : 400);
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const paths: string[] = steps.storage_paths ?? [];
  if (paths.length > 0) {
    const { error } = await admin.storage.from(BUCKET).remove(paths);
    if (error) {
      return json({ error: `Could not delete photos: ${error.message}` }, 500);
    }
  }
  if (steps.ban_user_id) {
    const { error } = await admin.auth.admin.updateUserById(steps.ban_user_id, { ban_duration: PERMANENT_BAN });
    if (error) {
      return json({ error: `Could not ban the account: ${error.message}` }, 500);
    }
  }
  if (steps.delete_user_id) {
    try {
      await removeAllPhotos(admin, steps.delete_user_id);
    } catch (error) {
      return json({ error: (error as Error).message }, 500);
    }
    const { error } = await admin.auth.admin.deleteUser(steps.delete_user_id);
    if (error) {
      return json({ error: `Could not delete the account: ${error.message}` }, 500);
    }
  }

  const { error: finishError } = await asUser.rpc("finish_report", { p_report_id: reportID, p_action: action });
  if (finishError) {
    return json({ error: finishError.message }, 500);
  }
  return json({ done: true }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
