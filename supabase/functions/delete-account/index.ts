// Deletes the calling user's account and everything they own.
//
// Runs as an Edge Function because it needs the service role to remove the auth user and
// to clear Storage (Supabase does not allow storage objects to be deleted through SQL).
// Database rows go with the auth user through ON DELETE CASCADE.
//
// Apple requires its token to be revoked when an account is deleted. That happens first, so
// if Apple refuses, nothing has been deleted and the person can try again.
//
// Deploy:  supabase functions deploy delete-account
// Secrets: APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, APPLE_CLIENT_ID (see README)
import { createClient } from "jsr:@supabase/supabase-js@2";
import { revokeAppleToken } from "../_shared/apple.ts";
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

  if (user.identities?.some((identity) => identity.provider === "apple")) {
    const body = await req.json().catch(() => ({}));
    if (typeof body.appleAuthorizationCode !== "string" || body.appleAuthorizationCode === "") {
      return json({ error: "Confirm with Apple to delete your account." }, 400);
    }
    try {
      await revokeAppleToken(body.appleAuthorizationCode);
    } catch (error) {
      console.error(`Apple revocation failed: ${(error as Error).message}`);
      return json({ error: "Apple couldn't confirm this. Nothing was deleted. Try again." }, 502);
    }
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  try {
    await removeAllPhotos(admin, user.id);
  } catch (error) {
    console.error((error as Error).message);
    return json({ error: "Could not delete your photos. Try again." }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error(`Could not delete account: ${deleteError.message}`);
    return json({ error: "Could not delete your account. Try again." }, 500);
  }
  return json({ deleted: true }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
