// Deletes the calling user's account and everything they own.
//
// Runs as an Edge Function because it needs the service role to remove the auth user and
// to clear Storage (Supabase does not allow storage objects to be deleted through SQL).
// Database rows go with the auth user through ON DELETE CASCADE.
//
// Deploy:  supabase functions deploy delete-account
import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "visit-photos";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  // Identify the caller with their own token; never trust a user ID from the request body.
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: userError } = await asUser.auth.getUser();
  if (userError || !user) {
    return json({ error: "Not signed in" }, 401);
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Photos are stored under "<user id>/<visit id>/<file>".
  const { data: visitFolders, error: listError } = await admin.storage.from(BUCKET).list(user.id, { limit: 1000 });
  if (listError) {
    return json({ error: `Could not list photos: ${listError.message}` }, 500);
  }
  for (const folder of visitFolders ?? []) {
    const prefix = `${user.id}/${folder.name}`;
    const { data: files } = await admin.storage.from(BUCKET).list(prefix, { limit: 1000 });
    const paths = (files ?? []).map((file) => `${prefix}/${file.name}`);
    if (paths.length > 0) {
      const { error: removeError } = await admin.storage.from(BUCKET).remove(paths);
      if (removeError) {
        return json({ error: `Could not delete photos: ${removeError.message}` }, 500);
      }
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    return json({ error: `Could not delete account: ${deleteError.message}` }, 500);
  }
  return json({ deleted: true }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
