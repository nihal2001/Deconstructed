// Deletes the calling user's account and everything they own.
//
// Runs as an Edge Function because it needs the service role to remove the auth user and
// to clear Storage (Supabase does not allow storage objects to be deleted through SQL).
// Database rows go with the auth user through ON DELETE CASCADE.
//
// Deploy:  supabase functions deploy delete-account
import { createClient } from "jsr:@supabase/supabase-js@2";
import { removeAllPhotos } from "../_shared/photos.ts";

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

  try {
    await removeAllPhotos(admin, user.id);
  } catch (error) {
    return json({ error: (error as Error).message }, 500);
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
