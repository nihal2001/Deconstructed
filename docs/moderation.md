# Moderation

How reports reach a moderator, how to act on them, and what has to be set up first. App Review guideline 1.2 asks for timely responses to reports, and our target is 24 hours.

## How it works

1. Someone reports a review or photo from the visit screen, or a person from their profile.
2. `report_content()` saves the report with a snapshot of the content, so deleting the content afterwards hides nothing.
3. A Database Webhook calls the `report-notify` Edge Function, which emails `MODERATOR_EMAIL`.
4. The moderator opens **Profile → Moderation queue** in the app and picks an action. The `moderate` Edge Function carries it out and the report closes.

If the email fails, the report is still in the queue. Check the queue daily rather than relying on the email alone.

## Actions

| Action | What happens | Undo |
|---|---|---|
| Remove review or photo | Deleted for everyone, including its Storage files. The report keeps a copy of the text | No |
| Reset names (reports on a person) | Username and display name go back to placeholders | They can pick new ones |
| Ban account | Sign-in stops, the profile and reviews are hidden from everyone, follows are removed, and the person leaves community scores. Closes every open report against them | See below |
| Delete account | Removes the account and all its data. Closes every open report against them. Apple's token isn't revoked, because that needs the person to confirm with Apple | No |
| Dismiss | Nothing changes and the report closes | No |

A ban keeps the person's data and stops them signing in with the same identity. A deleted account can sign up again, so ban first if that matters.

To undo a ban, remove it under Authentication → Users in the Supabase dashboard and run:

```sql
delete from app_private.banned_users where user_id = '<user id>';
```

Their reviews come back. Their old follows don't.

## What blocking does

- Each person disappears from the other's search, feed, profile views and reviews, enforced in row-level security.
- Any follow between them ends and doesn't come back on unblocking.
- The blocked person isn't told, and can't read the block.
- Community scores don't change, because they are anonymous averages.
- Either person can still be reported.

## Text filter

Triggers refuse new or changed notes, dishes, display names, usernames, and system, criterion and score-level text that contains a term in `app_private.blocked_terms`. It also applies to private reviews, because they can be made public later.

The list covers slurs, sexual terms and threats. Mild swearing is allowed. Matching is on whole words after undoing common letter swaps and stretched letters, so words joined together such as a username with no separators get past it. Reports are the backstop.

Add a term (lower-case letters and single spaces only):

```sql
insert into app_private.blocked_terms (term) values ('example phrase');
```

Text already saved isn't rechecked. The demo uses a short copy of the filter in `ContentFilter`, not this list.

## Photos

There is no automatic image scanning. Every photo can be reported, moderators can open reported photos whatever the review's visibility, and removal deletes the file. A scanning service would add cost and a further processor to the privacy policy, so it is worth adding only if reports show a need.

## Setup

1. Apply the migrations.
2. Deploy the functions:
   ```bash
   supabase functions deploy moderate
   ```
   ```bash
   supabase functions deploy report-notify --no-verify-jwt
   ```
   Then enable `pg_cron` if it isn't on, and schedule the report purge, unless the migration did it (it says so in a notice):
   ```sql
   select cron.schedule('purge-closed-reports', '37 3 * * *', 'select app_private.purge_closed_reports()');
   ```
3. Set the secrets. `REPORT_EMAIL_FROM` must be an address on a domain verified with Resend, and `REPORT_WEBHOOK_SECRET` is any long random string:
   ```bash
   supabase secrets set RESEND_API_KEY=... MODERATOR_EMAIL=... REPORT_EMAIL_FROM=... REPORT_WEBHOOK_SECRET=...
   ```
4. Database → Webhooks: create a webhook on `public.reports` for `INSERT` that calls the `report-notify` function, with an `x-webhook-secret` header set to the same secret.
5. Make yourself a moderator. Find your user ID under Authentication → Users, then:
   ```sql
   insert into app_private.moderators (user_id) values ('<user id>');
   ```
6. Set `CONTACT_EMAIL` in `Config/App.xcconfig`. It appears on the About screen.

Then file a test report from a second account and confirm the email arrives and the queue shows it.

## How it runs after launch

Decided before launch (#30):

- **Who checks the queue.** The owner, once a day, and the report email covers anything urgent in between. The 24-hour target only holds if the queue is checked daily, so when you'll be away for more than a day, add a stand-in with step 5 of Setup before you go.
- **How long closed reports are kept.** 12 months after they close, then `app_private.purge_closed_reports()` deletes them, including their snapshots. Open reports are never purged. The privacy policy states this.
- **Photo scanning.** Reports and removal are enough for 1.0. Revisit it if reported photos become a regular problem.
- **Mild swearing.** Allowed for 1.0 (#29). "The pasta was shit" is a fair review.

## Blocked terms: what was reviewed

The list was reviewed before launch (#29). Everyday text and real names beat strict coverage, so `spic`, `dyke`, `dykes`, `coon`, `coons` and `go die` were removed, because they blocked "spic and span", the surnames Van Dyke and Coon, and sentences like "to go. Die-hard fans". `spics` stays because it has no innocent use. Reports cover the terms that were removed.

Some terms stay even though they have an innocent meaning, because a false match costs little: the person sees a clear message and rewords it. The main ones are `faggot` (also a British meatball dish) and `kike` (also a Spanish nickname). Remove them if real reviews or names run into them:

```sql
delete from app_private.blocked_terms where term = 'example';
```
