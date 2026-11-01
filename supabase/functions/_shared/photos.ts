import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const BUCKET = "visit-photos";

// Removes every photo a person has stored, under "<user id>/<visit id>/<file>".
export async function removeAllPhotos(admin: SupabaseClient, userID: string): Promise<void> {
  const { data: visitFolders, error: listError } = await admin.storage.from(BUCKET).list(userID, { limit: 1000 });
  if (listError) {
    throw new Error(`Could not list photos: ${listError.message}`);
  }
  for (const folder of visitFolders ?? []) {
    const prefix = `${userID}/${folder.name}`;
    const { data: files } = await admin.storage.from(BUCKET).list(prefix, { limit: 1000 });
    const paths = (files ?? []).map((file) => `${prefix}/${file.name}`);
    if (paths.length > 0) {
      const { error: removeError } = await admin.storage.from(BUCKET).remove(paths);
      if (removeError) {
        throw new Error(`Could not delete photos: ${removeError.message}`);
      }
    }
  }
}
