---
name: github-issues
description: Create, edit, relabel, comment on, close and reopen GitHub issues in nihal2001/Deconstructed, following this repo's issue format and its ai-solo / human-needed labels. Use this whenever the user wants to file, write up, log, track, split, update, reword, relabel, tick off or close an issue, or says something like "make an issue for this", "add that to the backlog", "update #12" or "this is done, close it", even if they don't say "GitHub". Also use it when work on the current branch turns up something that should be tracked in an issue.
---

# GitHub issues for Deconstructed

Issues live in `nihal2001/Deconstructed` and are managed with `gh`. They are the project's backlog, and the labels decide whether an AI session may ship the work alone, so an issue has to be accurate enough to act on without this conversation.

The repo is **public**. Anything in an issue is visible to everyone and stays in notification emails after an edit. Never include keys, tokens, the contents of `Config/Secrets.xcconfig` or `supabase/.env`, or personal details. Name a setting (`GOOGLE_MAPS_API_KEY`) rather than its value.

## Creating an issue

1. **Check for a duplicate.** Search open and closed issues. If one covers the same work, update it instead (see below), and tell the user.

   ```bash
   gh issue list --state all --search "<keywords>" --json number,title,state,labels
   ```

2. **Verify the facts.** Open every file, symbol, setting and branch you plan to cite, and confirm the problem still exists on `main`. A wrong path in an issue costs the next session more than a missing one.

3. **Note the branch, when it matters.** If the issue is about work on the current branch, or depends on it, name the branch and say whether it's pushed and how it relates to `main`. Later readers won't have this worktree, and local branches are invisible on GitHub.

   ```bash
   git branch --show-current
   git status -sb
   git log --oneline origin/main..HEAD
   ```

4. **Write the title and body** using the format below.

5. **Create it.** Pass the body on stdin so that backticks and `#` survive the shell, then report the URL.

   ```bash
   gh issue create --title "<title>" --label "<labels>" --body-file - <<'EOF'
   <body>
   EOF
   ```

If the user described several separate pieces of work, make one issue per piece and cross-reference them with `#N`.

## Title

A short, plain sentence starting with a verb, in sentence case: "Remove developer text from live builds", "Decide how moderation runs after launch". For decisions, start with "Decide". An area prefix is fine when it helps scanning: "Map: add filters for cuisine and price".

## Labels

Every issue gets exactly one of the first two. Add `pre-launch` when it applies.

| Label | Meaning |
| --- | --- |
| `ai-solo` | Simple and low-risk. AI can ship it without human confirmation. |
| `human-needed` | Needs a person to review, decide or act before shipping. |
| `pre-launch` | Must be done or decided before the first App Store release. |

Use `human-needed` for anything that changes navigation or the app's overall flow, needs the owner's accounts (Supabase, Resend, App Store Connect, Google Cloud), or makes a product, brand, legal, privacy or App Review commitment. Also use it for anything you can't verify yourself, such as a check on a real device.

`ai-solo` is a permission as much as a description, so when in doubt use `human-needed`.

The GitHub default labels (`bug`, `enhancement`, `accessibility` and so on) exist but the backlog doesn't rely on them. Add one only if the user asks. Don't invent new labels without asking.

## Body

Use `##` headings, in this order, and leave out any that don't apply.

| Section | When |
| --- | --- |
| `## Problem` | Always. What's wrong or missing today, and why it matters. Be concrete: cite the file, setting or behaviour. |
| `## Blocked on` | Checkboxes for what must happen first, with `#N` links. |
| `## Proposed change` | Code or product work. Point at what already exists and should be reused. |
| `## What to do` | Setup or operational work done by a person. Replaces Proposed change. |
| `## What to decide` | Decision issues. Replaces Proposed change. Include a recommendation if there is one. |
| `## Testing` | Manual checks, with the setup they need. |
| `## Acceptance criteria` | Code changes. Observable results someone can check, as a bullet list. |
| `## Done when` | Setup or decision issues. Replaces Acceptance criteria, usually one or two sentences. |
| `## Open questions` | Anything the user hasn't settled. Don't guess the answer in the body. |
| `## Why ai-solo` or `## Why human-needed` | Almost always, as the last section. One or two sentences justifying the label. |

Use `- [ ]` for steps that get ticked off one at a time, and plain bullets for criteria. Write `#N` so issues link to each other, and put file paths, settings and code in backticks. Keep the tone plain and direct, explain unfamiliar terms briefly, and address the owner as "you" where the work is theirs ("Needs your Supabase and Resend accounts").

### Example: `ai-solo`

```markdown
## Problem
When you tap a restaurant pin on the Map tab, the restaurant tile doesn't show how expensive the place is.

## Proposed change
Show the price level (`$` to `$$$$`) on the map's restaurant tile, next to the cuisine.

`priceLevel` already exists in `Domain/Models.swift` and is shown in `RestaurantProfileView.swift`. Reuse the same formatting.

## Acceptance criteria
- The tile shows the price level when it's available
- No placeholder gap is shown when the price is unknown
- Demo data shows prices on the tile too

## Why ai-solo
A small display-only change using data that already exists; low risk.
```

### Example: `human-needed`, `pre-launch`

```markdown
## Problem
The app promises that reports are reviewed within 24 hours, but a few decisions about running this are still open.

## What to decide
- [ ] Who checks the moderation queue each day
- [ ] How long closed reports are kept. The privacy policy has to state the answer (#11)

## Done when
Each decision is recorded in `docs/moderation.md`, and any resulting work has its own issue.

## Why human-needed
These are your commitments to users and to App Review.
```

## Changing an issue

Read the issue first, including its comments, so you work from what's there now and not from memory.

```bash
gh issue view <N> --json number,title,state,labels,body,comments
```

- **Body:** `--body-file` replaces the whole body, so start from the current text and change only what was asked. Keep ticked boxes ticked and leave other sections alone.

  ```bash
  gh issue edit <N> --body-file - <<'EOF'
  <full updated body>
  EOF
  ```

- **Title:** `gh issue edit <N> --title "<title>"`

- **Labels:** `gh issue edit <N> --add-label "<label>" --remove-label "<label>"`. When swapping `ai-solo` and `human-needed`, do both in one command so the issue always has exactly one, and update the `Why` section to match. Only move an issue to `ai-solo` when the user says to, because that removes the human check.

- **Comments:** `gh issue comment <N> --body-file -`. Prefer a comment for progress updates and findings, and edit the body when the plan itself has changed, so the body always reads as the current state.

- **Progress:** tick boxes only for work you've confirmed is done. Merged code isn't proof that a device test or a production setup step happened.

## Closing and reopening

- Close an issue only when the user asks, or says the work is done. Check the Acceptance criteria or Done when section first, and if anything is unmet, tell the user rather than closing.
- Say why it was closed:

  ```bash
  gh issue close <N> --reason "completed" --comment "<what finished it>"
  gh issue close <N> --reason "not planned" --comment "<why>"
  gh issue close <N> --reason "duplicate" --comment "Duplicate of #M"
  ```

- Reopen with `gh issue reopen <N>`.
- Don't use `gh issue delete`. Close the issue instead, so its history stays. Deleting can't be undone, so leave it to the user.
- For code, let the commit close the issue on merge: list `Closes #14, closes #15` near the end of the commit message or PR description, and mention `(#14)` next to the matching change.

## Reporting back

Finish with the issue's URL and what you did: its labels, and for an edit, what changed. If you made a call the user might want to overrule, such as `human-needed` versus `ai-solo` or `pre-launch`, say so in one line.
