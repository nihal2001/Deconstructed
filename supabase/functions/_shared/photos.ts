import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const BUCKET = "visit-photos";

// Storage returns at most this many entries per request.
const PAGE_SIZE = 1000;

async function listAll(admin: SupabaseClient, prefix: string) {
  const entries: { name: string }[] = [];
  while (true) {
    const { data, error } = await admin.storage.from(BUCKET).list(prefix, { limit: PAGE_SIZE, offset: entries.length });
    if (error) {
      throw new Error(`Could not list photos: ${error.message}`);
    }
    entries.push(...(data ?? []));
    if ((data ?? []).length < PAGE_SIZE) {
      return entries;
    }
  }
}

// Removes every photo a person has stored, under "<user id>/<visit id>/<file>".
export async function removeAllPhotos(admin: SupabaseClient, userID: string): Promise<void> {
  for (const folder of await listAll(admin, userID)) {
    const prefix = `${userID}/${folder.name}`;
    const paths = (await listAll(admin, prefix)).map((file) => `${prefix}/${file.name}`);
    if (paths.length > 0) {
      const { error: removeError } = await admin.storage.from(BUCKET).remove(paths);
      if (removeError) {
        throw new Error(`Could not delete photos: ${removeError.message}`);
      }
    }
  }
}
