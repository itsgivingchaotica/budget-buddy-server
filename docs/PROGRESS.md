# Budget Buddy — MVP Progress Log

Plan: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) (revision 2). Task IDs below refer to that plan.

---

## Day 0 — Setup (2026-11-22) ✅ complete

### P1 — Git and secrets

**Finding:** `bb-client/` and `bb-server/` are **existing, separate git repos** with history and GitHub remotes. The root is not a repo.

| Repo | Branch | Commits (all refs) | Remote | Working tree before Day 0 |
|---|---|---|---|---|
| `bb-client` | `main` | 90 | `origin` → GitHub (`budget-buddy-native`) | clean |
| `bb-server` | `main` | 40 | `origin` → GitHub (`budget-buddy-server`) | **15 modified files, uncommitted** (controllers, models, `db/seeds.rb`, tests, fixtures; +68/−75 lines). Untouched. |

**Decision:** I did **not** run `git init` at the root. A root repo would contain both existing repos inside it and complicate their history. To be decided before Day 1 (see *Open decisions*).

**Secrets check:**
- Nothing secret is currently tracked in either repo. `bb-server` tracks `config/credentials.yml.enc`, which is encrypted and normally committed.
- `bb-server/config/master.key` appears in git's object store **only inside a local stash** (`stash@{0}`, "WIP on (no branch): Initial commit", 2024-08-28, commit `b138149`). It's on no branch, no remote-tracking ref and no remote, so it was never pushed. It's the same key as the current one. The stash was left untouched.
- Confirmed ignored with `git check-ignore`:
  - `bb-server`: `.env`, `.env.local`, `config/master.key`, `log/development.log`, `tmp/local_secret.txt`
  - `bb-client`: `.env`, `.env.local`, `.env.production`
- `.env.example` is trackable in both repos.
- No secret values were displayed.

### P2 — Database backup and restore check
- Dev database: **`bb_server_development`** (from `config/database.yml`; no `DATABASE_URL` override). Server is **PostgreSQL 14.25**; `pg_dump` client is 17.12.
- Backup: `backups/bb_server_development_2026-11-22.dump` (custom format, 21,865 bytes, mode `600`, folder mode `700`). Stored at the project root, outside both repos, and covered by the root `.gitignore`.
- Restore check: confirmed scratch DB `bb_restore_check_20261122` did not exist → created it → `pg_restore --no-owner` → compared → dropped it. Only `bb_server_development` and `bb_server_test` remain.
  - The restore printed one warning: `unrecognized configuration parameter "transaction_timeout"`. This is a `SET` line written by the newer v17 `pg_dump`, which the v14 server doesn't recognise. It's harmless, and no data was affected.
  - Every table matched on **row count and on an MD5 checksum of its contents**:

| Table | Rows |
|---|---|
| users | 2 |
| budgets | 1 |
| categories | 5 |
| tags | 38 |
| entries | 44 |
| entries_tags | 76 |
| schema_migrations | 17 (latest `20250419232612`) |
| ar_internal_metadata | 1 |

### Data check, done early (read-only; part of D-1)
- Categories have IDs **6–10** (`Expense`, `Income`, `Savings & Goals`, `Miscellaneous`, `Budgeting Strategy`), all `category_type = default`.
- **All 38 default tags have `user_id = 1`**, while `db/seeds.rb` creates them with `user_id = nil`. This confirms D2. D-3 will need your approval to set them to `NULL`.
- Duplicate tags: 0 among global tags, 0 among user tags. Duplicate emails, ignoring case: 0. So D-3's unique indexes can be added without cleanup.
- Entries with no `category_id`: 0. Entries whose tag category doesn't match their own category: 0. Entries with no tags: 1, which is invisible in the current category endpoint (D5).
- `entries.frequency` values: `Every week` (18), `""` (15), `Every month` (9), `Every year` (2).
- The server is **Postgres 14**, so `NULLS NOT DISTINCT` (PG15+) isn't available. This confirms the plan's choice of partial unique indexes for D-3.

### P3 — Baseline test run (no code changed)
- Command: `bin/rails db:test:prepare && bin/rails test`, run in `bb-server` against the **working tree, including the 15 uncommitted changes**.
- Result: **20 runs, 36 assertions, 0 failures, 0 errors, 0 skips** (seed 14645, 0.51 s).
- Coverage: the five scaffold CRUD tests each for the Budgets, Entries, Tags and Users controllers. There are **no** model tests with assertions, and no tests for the custom endpoints (`entries_by_budget_with_default_categories`, `default_tags`, `show_by_email`, `categories#default`). There's no `CategoriesControllerTest`.
- Client: no tests exist, so none were run.

### P4 — Files

| File | Change |
|---|---|
| `docs/PROGRESS.md` | created (this file) |
| `.gitignore` (root) | created. Protects a future root repo: `backups/`, `*.dump`, `.env*` (except `.env.example`), `**/config/master.key`, `.DS_Store`, `.ruby-lsp/` |
| `backups/bb_server_development_2026-11-22.dump` | created (ignored) |
| `bb-server/.env.example` | created. Variable names only, plus the planned variables commented out |
| `bb-client/.env.example` | created. Variable names only, with a note that `EXPO_PUBLIC_*` values are public |
| `bb-server/.gitignore` | modified. Added `!/.env.example`, because the existing `/.env*` rule would have ignored the template |
| `bb-client/.gitignore` | modified. Added `.env*` and `!.env.example`. Previously only a file named exactly `.env` was ignored, so `.env.local` and similar files could have been committed |

Nothing was committed or pushed. No application code was changed.

### Open decisions / blockers before Day 1
1. ~~**Uncommitted work in `bb-server`.**~~ **Resolved 2026-11-22.** The Copilot refactor is saved in three commits on `chore/copilot-backend-checkpoint` (see *Copilot checkpoint* below).
2. **Repo layout.** Choose one: (a) keep two repos and make `docs/` a third small repo or copy it into `bb-server`; (b) a root repo that ignores `bb-client/` and `bb-server/` and tracks only `docs/`, `CLAUDE.md` and `README.md`; (c) merge both into one repo with `git subtree`, which keeps history but rewrites paths. Recommended: (b) for the sprint, which is reversible and leaves both histories untouched.
3. **Day 1 work branches.** Recommended: a `feature/auth` branch in `bb-server` (and in `bb-client` for C0).
4. **Kinde setup (needed for S1).** The issuer URL is probably the existing `KINDE_SITE`/`EXPO_PUBLIC_KINDE_APP_DOMAIN`. Whether Kinde puts an `aud` claim in access tokens depends on whether an API audience is registered in the Kinde dashboard. That needs checking in the dashboard, or by decoding a real token's claims, without printing the token.
5. Checked the old local `bb-server` branch `kinde-auth`: it has **no commits that aren't already on `main`** (it's 30 commits behind). There's no earlier auth work to reuse.

---

## Copilot checkpoint (2026-11-22) ✅ complete

The uncommitted, Copilot-assisted backend refactor was audited (read-only) and saved **without changes** on a new `bb-server` branch. Nothing was pushed or merged.

| Commit | Message | Files |
|---|---|---|
| `f884c35` | `fix(backend): repair Rails models, controllers, and seed logic` | 4 controllers, 4 models, `db/seeds.rb` |
| `e89066f` | `test(backend): update fixtures and API controller tests` | 4 controller tests, `entries.yml`, `users.yml` |
| `0e7f1df` | `chore(config): protect environment files and add example configuration` | `.gitignore`, `.env.example` (Day 0 files) |

- Branch: `chore/copilot-backend-checkpoint`, based on `main` @ `6b57c1a` (which matches `origin/main`). Not pushed.
- Tests: committed `main` gave **20 errors** (fixtures referenced columns that no longer exist). The checkpoint branch gives **20 runs, 36 assertions, 0 failures, 0 errors**.
- Working tree clean. `main..branch` = exactly the 17 audited files (+85/−75). No `.env`, `master.key` or dump files are tracked.

### Known issues register (fix during Day 1)

Each issue is tied to the plan task that fixes it. Status column: ⬜ open, ✅ fixed.

| # | Issue | Source | Severity | Fix in | Status |
|---|---|---|---|---|---|
| K1 | No authentication on any endpoint | pre-existing | Critical | S1 | ⬜ |
| K2 | No ownership checks: `find(params[:id])` everywhere, `index` returns whole tables, `GET /users` and `show_by_email` expose every user | pre-existing | Critical | S2, S3 | ⬜ |
| K3 | `tag_params` permits `user_id` and `default_tag`, so any caller can create tags for another user or global "default" tags | Copilot `f884c35` | High | S3 (allow only `name`, `category_id`; owner = `current_user`; `default_tag` server-only) | ⬜ |
| K4 | `category_params` permits `category_type`, so any caller can create `default` categories that every user sees | Copilot `f884c35` | High | S3 (category write actions → 403) | ⬜ |
| K5 | `budget_params` permits `user_id`, so the client decides who owns a budget | pre-existing | High | S3 | ⬜ |
| K6 | `sync_tags` accepts any tag ID: another user's private tags or a tag from a different category can be attached, and invalid IDs are silently dropped (previously 404) | Copilot `f884c35` (was already partly true with `Tag.find`) | Medium | S3 (tags limited to global defaults plus the caller's own) + D-4 (tag must be in the entry's category; unknown ID → 422) | ⬜ |
| K7 | `Entry belongs_to :category, optional: true` allows entries with no category (dev database currently has 0) | Copilot `f884c35` | Medium | D-4 (make it required again; give fixtures categories) | ⬜ |
| K8 | **Seed and dev database disagree:** seeds create global defaults with `user_id: nil`, but the dev database's 38 defaults have `user_id = 1`. **Do not run `db:seed` on the dev database until D-3**, or it creates 38 duplicate tags. | Copilot `f884c35` + existing data | Medium (data) | D-3 (move defaults to NULL after a backup, with approval; partial unique indexes) | ⬜ |
| K9 | `default_tags` filters by whatever `user_id` the client sends (the client sends 1), so a freshly seeded database returns nothing | pre-existing, changed by Copilot | Medium | D-3 (ignore the param; return `default_tag AND user_id IS NULL`) | ⬜ |
| K10 | The entries-by-category endpoint ignores `entries.category_id`, so untagged entries are invisible (1 in the dev database) | pre-existing | Low | D-4 | ⬜ |
| K11 | Entries `update` error format changed to `{errors: [...]}`, and `categories#default` now returns objects instead of names. Neither is called by the current client. | Copilot `f884c35` | Info | Note for C1 | ⬜ |
| K12 | CORS `origins '*'`; Authorization header not filtered from logs | pre-existing | Medium | S3 | ⬜ |
| K13 | Scaffold tests send `user_id` in budget params and cover no custom endpoints | pre-existing | Info | S3 tests, Day 1 test matrix | ⬜ |
| K14 | `master.key` exists in a **local stash** only (`stash@{0}`), never pushed | pre-existing | Low | Your decision: leave it, or drop that stash later. Don't push stashes. | ⬜ |

---

## Plan revision 3 (2026-11-22)

`IMPLEMENTATION_PLAN.md` updated with the architecture-audit findings:
- **X1 → TD1:** the 33 orphaned `entries_tags` rows are accepted technical debt and won't be touched. No foreign keys or deletions without approval.
- **X3 → CT0:** client Jest setup, on its own track, limited to about 1.5 hours, never blocking the backend.
- **X5 → C-B:** the new-budget flow works on Day 1 (create a named budget before importing).
- **X7 → KA:** the Kinde API audience is a **prerequisite for S1b**. S1a stays independent. S1b requires `aud`.
- **D13/TS0/TD4:** TypeScript baseline of **100 errors** (`npx tsc --noEmit`, 2026-11-22). They'll be grouped by root cause at TS0, just before the first client change. No broad refactor; touched files must not gain errors.

`ARCHITECTURE.md` stays a factual snapshot. Only §9 (planned) and the status note in §10 changed.

---

## S1a — Kinde token verifier (2026-11-22) ✅ implemented, waiting for review

Branch: `bb-server` **`feature/auth`**, created from `chore/copilot-backend-checkpoint` @ `0e7f1df`. ~~Not committed.~~ *Correction (2026-11-22, feasibility review): committed locally as `3b54035` after the security review below; not pushed, not merged.*

| File | Change |
|---|---|
| `Gemfile`, `Gemfile.lock` | `gem "jwt", "~> 3.1"` → resolves to **jwt 3.3.0** (only dependency `base64`, already present) |
| `app/services/kinde/token_verifier.rb` | **new.** `Kinde::TokenVerifier` |
| `app/services/kinde/jwks_fetcher.rb` | **new.** `Kinde::JwksFetcher` (OIDC discovery → `jwks_uri` → JWKS) |
| `test/services/kinde/token_verifier_test.rb` | **new.** 35 tests |
| `test/services/kinde/jwks_fetcher_test.rb` | **new.** 10 tests |
| `.env.example` | `KINDE_ISSUER_URL` and `KINDE_AUDIENCE` documented as read by the verifier |

**Behaviour**
- Only RS256 is accepted. `alg: none` and HS256 (including "algorithm confusion", where the public key is used as an HMAC secret) are rejected **before** any key fetch.
- Checks `iss` (a trailing slash is tolerated), `exp`/`nbf` with 30 s tolerance, and the required claims `sub`, `exp`, `iss`. Checks `aud` when an audience is configured. `from_env(require_audience: true)` raises a `ConfigurationError` if `KINDE_AUDIENCE` is blank; S1b will use this.
- Keys:
  - Found through OIDC discovery. The `jwks_uri` must be https on the issuer's host.
  - Only RSA keys with `use` = `sig` or unset, `alg` = RS256 or unset, and a `kid` are used. Malformed keys are skipped.
  - Cached for 1 hour. If an hourly refresh fails, the old keys keep working.
  - An unknown `kid` triggers at most one re-fetch per 60 s.
  - After a failed fetch, the verifier waits 10 s before trying again.
- Errors:
  - `InvalidToken#reason` is one of `:missing`, `:malformed`, `:expired`, `:not_yet_valid`, `:invalid_signature`, `:invalid_algorithm`, `:invalid_issuer`, `:invalid_audience`, `:missing_claim`, `:missing_key_id`, `:unknown_key`. The token is never included in error messages, and this is tested.
  - `KeysUnavailable` → S1b will map it to 503.
  - `ConfigurationError` for a bad issuer or a missing required audience.
- Tokens over 8 KB are rejected without being decoded. Fetch timeouts are 3 s, and response bodies are capped at 100 KB.

**Not changed:** controllers, routes, initializers and config. Nothing outside `app/services/kinde/` references `Kinde::` (checked with grep).

**Test results**
- Focused: `bin/rails test test/services/kinde` → **45 runs, 135 assertions, 0 failures, 0 errors**. Ran 5 times with random seeds, stable.
- Full suite: `bin/rails test` → **65 runs, 171 assertions, 0 failures, 0 errors** (the original 20 plus 45 new).
- `bin/rails zeitwerk:check` → all good (production eager loading).
- No test makes a network call. RSA keys are generated in-process, and the key fetcher and HTTP layer are injected fakes.

**Bug caught by the tests during development:** one malformed key in the key set (invalid base64) raised `JWT::Base64DecodeError`, which the per-key rescue didn't cover, so every token would have been rejected. The per-key rescue now covers `JWT::DecodeError`, and there's a regression test.

**Next (not started):** KA (Kinde dashboard audience + client `audience` param + env), then S1b.

### S1a security review (2026-11-22)

Focused review of key-fetch failures, stale keys, algorithm restrictions and error handling. **No blocking issues.** Six hardening changes were made before committing, each with a regression test:

| # | Finding | Severity | Resolution |
|---|---|---|---|
| R1 | Stale cached keys were trusted **indefinitely** while Kinde was unreachable, so a key Kinde had revoked could stay valid during a long outage | Medium (defence in depth) | Cached keys are trusted for at most **24 h** (`MAX_STALE_KEYS_SECONDS`). After that, requests fail closed with `KeysUnavailable` (S1b → 503) |
| R2 | A **validly signed** token with a JSON array or number payload raised an unhandled `TypeError` (would be a 500). Only reachable with a token signed by Kinde's own key | Low | The key finder rejects non-object payloads as `:malformed`, before the signature step |
| R3 | `InvalidToken` kept the underlying JWT error as its `cause` (which contains audience and issuer values), so a log of the exception chain could leak claim data | Low | Raised with `cause: nil`. Only the reason code is exposed |
| R4 | No minimum RSA key size for keys from the key set | Low (defence in depth) | Keys under 2048 bits are ignored. jwt 3.x also refuses to sign with them |
| R5 | `strip` ran on the token before the size check | Very low | Size check runs first |
| R6 | Audience wasn't trimmed | Very low | Whitespace is trimmed |

**Confirmed safe:**
- Only RS256 accepted. `none` and HS256 are rejected *before* any key fetch (tested).
- `iss` is always checked.
- The `jwks_uri` must be https on the issuer's host. Redirects aren't followed, TLS certificates are checked (Net::HTTP default `VERIFY_PEER`), there are timeouts, and bodies are capped.
- An unknown `kid` causes at most one re-fetch per 60 s. A failed refresh for an unknown `kid` doesn't become a 503.
- One malformed key doesn't break the others.
- Errors never contain the token.

**Remaining risks (accepted, or for S1b/S2):**
- A key Kinde **removes** stays trusted for up to 1 h (cache TTL), or up to 24 h if Kinde is unreachable.
- The mutex is held during a key fetch (two HTTP calls, up to about 12 s worst case), so requests that need keys wait during the *first* failed fetch. After that the 10 s backoff makes them fail fast.
- Each Puma process keeps its own cache. S1b must memoize one verifier per process.
- `jwks_uri` isn't checked for port.
- S1b must log only the reason code and keep 401 responses generic (added to the S1b row in the plan).

**Results after hardening:** focused **50 runs, 164 assertions, 0 failures**; full suite **70 runs, 200 assertions, 0 failures**; `zeitwerk:check` all good.

**New security requirement SR-1 (for S2), recorded in the plan:** existing accounts are never linked to a Kinde identity on an unverified email alone. Linking requires a server-verified email source, Kinde's email-verified flag, and no existing `kinde_id`. Otherwise no link: create a new user, or require a manual approved link.

---

## KA — Kinde API audience (2026-11-22) ✅ done (step 4 confirmed 2026-11-24)

- **Steps 1–2 (you, in the Kinde dashboard):** created the API "Budget Buddy API" with audience `https://api.budgetbuddy.app`, and authorized **only** the Front-end and mobile application `5dec…0b15`, which the Expo app uses. The earlier audience `https://budgetbuddyapp.kinde.com/api` turned out to be Kinde's Management API, and was never requested by the app.
- **Step 3 (configuration):**

| File | Change | Tracked? |
|---|---|---|
| `bb-client/utils/KindeConfig.ts` | Passes the SDK default scope plus `additionalParameters: { audience }`, but **only when `EXPO_PUBLIC_KINDE_AUDIENCE` is set** (SDK 1.3.1 throws at construction if `audience` is present and isn't a string). The SDK merges it into the `/oauth2/auth` query for login and register (checked in the SDK source). | yes (uncommitted) |
| `bb-client/.env` | `EXPO_PUBLIC_KINDE_AUDIENCE` added | ignored |
| `bb-client/.env.example` | `EXPO_PUBLIC_KINDE_AUDIENCE=` (no value) | yes (uncommitted) |
| `bb-server/.env` | `KINDE_ISSUER_URL` (copied from the existing `KINDE_SITE`, trailing slash removed) and `KINDE_AUDIENCE` added | ignored |

- **Checks:**
  - `Kinde::TokenVerifier.from_env(require_audience: true)` builds successfully.
  - The issuer exactly matches the `issuer` in Kinde's live OIDC discovery document, with no trailing slash.
  - Kinde publishes 1 key, and it's usable (RS256, at least 2048 bits). The only advertised signing algorithm is RS256.
  - `tsc` is still 100 errors (KindeConfig.ts keeps its 1 pre-existing TS2345).
  - Rails suite 70/70 passes.
- **Step 4 (2026-11-24, you, on a physical iPhone via the iOS development build below):** a fresh **Sign In** logged, claims only:
  - `iss`: `https://budgetbuddyapp.kinde.com`
  - `aud`: `["https://api.budgetbuddy.app"]`
  - Compared without printing values: `bb-server/.env` `KINDE_ISSUER_URL` matches `iss` and `KINDE_AUDIENCE` matches `aud`, the two values `Kinde::TokenVerifier` reads. **S1b is unblocked**, with no configuration change needed.
  - The temporary `__DEV__` `[KA check]` log in `bb-client/app/login/index.tsx` was removed on 2026-11-24 (PO-29). The file is back to its committed version.

---

## Feasibility review for plan revision 4 (2026-11-22) ✅ accepted (D-017); plan approved with amendments (D-018). See "Plan revision 4.1" below

Scope: check the approved product direction (`docs/product/PRODUCT_BRIEF.md`, `DESIGN_DECISIONS.md` Approved entries, `MVP_SCOPE.md` draft) against the code, and revise the plan. **Read-only investigation.** The only files changed are `docs/IMPLEMENTATION_PLAN.md` (now revision 4, Draft) and this file. No migrations, no code changes, no commits. `ARCHITECTURE.md` is untouched. Nothing is implemented until you approve.

### 1. Current state vs the 2026-11-22 snapshot

**Nothing has changed since the snapshot.**
- All 87 snapshot source files are byte-identical to the live repos, and so are `ARCHITECTURE.md`, `CLAUDE.md` and plan revision 3. No repo file is newer than the snapshot.

| Repo | Branch @ HEAD | Working tree | Pushed? |
|---|---|---|---|
| `bb-server` | `feature/auth` @ `3b54035` | clean | No. `feature/auth` and `chore/copilot-backend-checkpoint` have no upstream |
| `bb-client` | `main` @ `81fa7d7` | KA changes, uncommitted: `.gitignore`, `app/login/index.tsx`, `utils/KindeConfig.ts` modified; `.env.example` untracked | `main` matches `origin/main` |

- **S1a:** implemented, hardened and committed locally (`3b54035`). It's waiting for your review, and it isn't wired into any controller.
  - The S1a entry above said "Not committed". That was out of date and has been corrected.
  - The plan header said "approved through S1a" while this log said "waiting for review", so the review status needs confirming (PO-20).
  - The suite was re-run today: **70 runs, 200 assertions, 0 failures**.
- **KA:** steps 1–3 done. **Step 4 is still pending**: a fresh login to check the `iss`/`aud` claims. It needs you, and **S1b stays blocked until it's done**. The temporary `__DEV__` claims log in `app/login/index.tsx` is still there; remove it after step 4.
- **Dev database** (read-only session, aggregates only): no changes. users 2, budgets 1, categories 5, tags 38, entries 44, entries_tags 76 (33 orphaned), latest migration `20250419232612`.
  - New detail: **all 44 entries are in the Income category** (tags Salary 31, Freelance 7, Gifts Received 3, Bonuses 2; one untagged). There are no expense entries.
  - Every entry has an `end_date`, and start dates run from 2025-04-12 to 2025-05-01.
  - This makes "reuse entries as obligations" moot for existing data.
- **`ARCHITECTURE.md` still accurately describes the code.**

### 2. Data model assessment (details in plan revision 4, §2)

**Per-concept recommendation**

| Concept | Recommendation | Main tradeoff |
|---|---|---|
| Account | **New** `accounts` | No reuse candidate exists |
| Import, Transaction | **New**, owned by an account (`current_user.transactions` through accounts, no denormalized `user_id`) | One join on queries, but ownership can't drift |
| Transfer link | **New** `transfer_links` (suggested/confirmed/rejected) | Simpler alternative: a column on `transactions`. That can't remember rejections or carry suggestion state |
| Category + labels | **Reuse** `categories`, adding `slug`, `kind`, `active` and default label columns. New rows for the flat list; old 5 rows marked legacy | Labels are global defaults per category in the MVP (per-user labels in v1) |
| Category budget | **New** `category_budgets`, with `effective_from` semantics | — |
| Obligation | **New** `obligations` with structured recurrence | Not reusing entries means the legacy entry UI isn't reused (it's hidden anyway) |
| Goal (+ contributions) | **New** `goals` (one table, three types) + `goal_contributions` | Some nullable type-specific columns |
| Merchant rule | **New** `merchant_rules` → category | — |
| Financial profile | **New** `financial_profiles`: jsonb answers plus typed fields the calculations use | — |
| AI usage | **New** `ai_usage` (as revision 3 S4) | — |
| Plan proposal | **New** `plan_proposals` *(not in the approved list, PO-14)* | Enforces "nothing saved until approved" server-side |

**(a) Budgets: soft retire (recommended).**
- **What changes:**
  - No new table references `budgets`.
  - `budgets`, `entries`, `tags` and `entries_tags` stay in place, frozen.
  - New endpoints aren't nested under `/budgets/:id`.
- **What breaks:**
  - The legacy UI, which is hidden from navigation in LG1. Its code is kept.
  - The header's `currentBudget.name`.
  - C-B, which is dropped.
  - The 20 existing scaffold tests keep passing.
  - S3 still has to scope the legacy endpoints (S3-L), or make them read-only (PO-10).
- **Keeping one implicit budget per user** would avoid touching legacy screens, but:
  - it contradicts D-006/D-007;
  - it forces `budget_id` onto every new table and `currentBudget` into every new screen;
  - it leaves multi-budget CRUD endpoints to lock down;
  - removing it later would take a multi-table migration.

**(b) Obligations: a new table.**
- Entries are budget-owned plan lines with free-text recurrence (`"Every week"`, `""`, custom days) and a broken custom-frequency path (D9).
- They also carry HABTM tags with orphaned join rows, and the dev data is all Income plans.
- Converting them would mean reinterpreting rows, and that isn't additive.
- Obligations need a structured recurrence, a due date and (later) paid status.

**(c) Categories and tags: purely additive.**
- **Expense tags:** the 15 become the flat spending categories.
- **Income and Transfers:** one Income category (PO-8), plus a new Transfers category.
- **Labels:**
  - Essential/Needs → need
  - Non-Essential/Wants/Discretionary → want
  - Fixed/Variable → fixed/variable
  - One-time/Recurring → recurrence label
  - Planned/Unexpected → dropped
- **Savings & Goals tags:** these become onboarding goal suggestions, not categories.
- **Safest path:** no existing tag, entry or `entries_tags` row is modified or deleted.
  - The legacy category rows only get values in **new** columns, and that's reversible.
  - TD1's 33 orphans are irrelevant, because nothing new reads `entries_tags`.
  - Revision 3's D-3 rewrite (default tags `user_id` 1 → NULL) and D-4 are **no longer needed**. That removes the only data-rewrite step that needed approval.

**(d) Separate `category_budgets` and `goals` tables (recommended) over one shared "targets" table.**
- A shared table would mostly hold mutually exclusive nullable columns, and the two have different lifecycles: one resets monthly, the other completes.
- What they share is the approval flow, and that's shared in code (a `PlanItem` concern plus `plan_proposals`).

**(e) Security tasks.**
- **S1b:** unchanged.
- **S2:** unchanged, plus it creates the financial profile and adds the `lower(email)` unique index carried over from D-3.
- **S3: same principle, new root.**
  - Every new resource is scoped from `current_user` (directly, or through `accounts`).
  - Any `account_id`, `transaction_id` or `goal_id` in a request is resolved through the caller's scope (else 404).
  - A transfer link requires **both** transactions to be the caller's, in different accounts.
  - A goal contribution can link only the caller's confirmed transfer.
  - The coach tools are bound to `current_user` with no budget, and `goal_id` tool inputs are re-resolved through `current_user.goals`.
  - Legacy endpoints get S3-L.
  - The ownership test matrix grows with each new resource, so it should be table-driven.
- **S4:** unchanged in design, extended to onboarding follow-ups and plan drafting.

**Nothing destructive is planned.**

### 3. Feasibility against 3 days

The estimates are focused engineering hours including tests, against the current codebase. **Reuse is limited.**
- **Server:** auth (S1a), the scaffold and the seeds are reusable.
- **Client:** login, routing, NativeWind and the store pattern are reusable. Almost every MVP screen (about 10) is new, because the current screens are built around budgets and entries.

| P | Feature | Estimate | Notes |
|---|---|---|---|
| P1 | Security foundation (S1b, S2, S3/S3-L, S4, C0) | 6–9 h | S1a done; KA step 4 needs you |
| P2 | Accounts and CSV import (DM-2, T1, I1, I2, C2) | 7–10 h | One format helps |
| P3 | Transfer matching (TR1, C2b part) | 3–4 h | |
| P4 | Categorization (DM-1, AI1–AI3, AI-0, review UI) | 6–9 h | |
| P5 | Coach onboarding (ON1, ON2, C5) | 4–6.5 h | Follow-ups are about 1.5–2 h of this |
| P6 | Coach-drafted plan (DM-3, OB1, PL1, PL2, C6) | 7–10 h | |
| P7 | Goals, all three types (G1, G2, C7) | 6–9 h | Milestones about 1 h, transfer linking about 1 h |
| P8 | Today / This week (W1, C3 part) | 4–6 h | **Blocked on the Phase 5 formula** |
| P9 | Monthly dashboard (AN1/AN2, C3 part) | 2–3 h | |
| P10 | Coach Q&A (AS1, AS2, C4) | 5–6.5 h | |
| — | Cross-cutting: TS0, CT0, demo generator, end-to-end QA, README | 6–9 h | |
| | **Total** | **56–82 h** | |

**The scope doesn't fit.**
- Three days is roughly 24–30 focused hours.
- P1–P3 (never cut) alone are 16–23 h. The full §5 fallback order (follow-ups → milestones → transfer-to-goal linking → monthly dashboard) saves only **5–7 h**.
- Success criterion 1 (sign-up to approved plan in < 5 min) needs P2, P4, P5 and P6 working, so it can't be met in 3 days either.

**Expected cuts within 3 days: all four §5 items, and more besides.** Plan revision 4 proposes two milestones (PO-2):
- **M1 (Days 1–3):** P1, P2 and P3, plus P4 without the Claude step, a minimal client and demo data.
- **M2 (Days 4–7):** everything else, with manual obligations, goals and Today built before the coach. The coach then only drafts rows for tables that already work.
- **The alternative is to keep 3 days and cut deeper**, e.g. no Q&A, a deterministic (non-AI) plan draft, and rules-only categorization. That removes most of what makes the product AI-forward.

### 4. To define (not decide)

#### 4.1 Inputs for a deterministic "safe to spend this week"

Phase 5 owns the formula. These are the inputs it has to pin down:

1. **Window:**
   - Week start day (per user?) and the user's **time zone**. `users` has none today, so it's planned on `financial_profiles`.
   - "This week" means today → end of week, or a rolling 7 days.
2. **Data freshness:**
   - Each account's data-through date, and how the overall date is chosen (proposal: the earliest among active accounts).
   - How the gap between data-through and today is treated: transactions in the gap are unknown.
3. **Starting position (PO-6)**, one of:
   - account balances, which need an opening balance per account or the optional CSV `balance` column;
   - or a **budget-based** formula (remaining flexible category budget for the month, prorated to the week). This needs no balances.
4. **Account inclusion:** which account purposes count as spendable. Checking yes, savings no; side-income Venmo?
5. **Expected income in the window:** pay frequency, typical amount and next pay date from onboarding. Is income counted before it arrives? Expected income isn't in the approved concept list (PO-5).
6. **Obligations due:**
   - Is the horizon this week only, or up to the next paycheck? The core job is "can I cover what's coming, on time".
   - **Paid vs unpaid:** without auto-matching, an obligation that was already paid could be counted twice (PO-5).
7. **Goal contributions due this week:** the per-week amount from GoalCalculator, for active goals only. Debt goals are covered by their obligation.
8. **Category budgets:** which categories count as flexible (labels `variable`/`want`?), and how a monthly budget is prorated to a week (days-in-month or weeks-in-month).
9. **Spending so far this week:** confirmed transfers excluded, and transactions matching an obligation excluded from flexible spend.
10. **Buffer:** none, a fixed amount, or a percentage (user preference?).
11. **Presentation:**
    - Rounding (whole dollars?).
    - A negative result is shown as "$0, over by $X".
    - Every result carries `data_through` and the assumptions.

#### 4.2 Generic CSV format

Full proposal in plan §2.4:
- **One file per account**, chosen at upload. UTF-8 (BOM allowed), comma-delimited, header required.
- **Required columns:** `date` (`YYYY-MM-DD` or `MM/DD/YYYY`), `description`, `amount` (signed: **negative = money out, positive = money in**; `$`, thousands separators and `(x)` accepted; max 2 decimals; zero skipped).
- **Optional columns:** `transaction_id` (becomes the duplicate key when present) and `balance` (used only if Phase 5 uses balances).
- **Limits:** 2 MB / 10,000 rows. Posted transactions only.

#### 4.3 Synthetic demo data

- **Generator:** a deterministic Ruby generator (fixed random seed) in `bb-server/lib/demo/`. It writes generic-format CSVs for 24 months for one fictional persona. Under the same seed it produces the same bytes, so tests can use it too.
- **Accounts:**
  - **Checking:** biweekly paycheck, rent on the 1st, utilities, weekly groceries, dining, subscriptions, a semi-annual insurance bill, a monthly loan payment (for the debt goal), and card-style description noise (`SQ *`, store numbers).
  - **Savings:** a monthly transfer in from Checking, occasional transfers back, small interest credits.
  - **"Venmo":** side-job income from several fictional payers, dining splits, and "cash out" transfers to Checking.
- **Transfers:** generated as pairs (same amount, opposite sign, 0–2 day lag), plus **decoys**: same amount within 3 days but not a transfer, to exercise confirm/reject.
- **Extra files:** an overlapping second export (to demonstrate zero duplicates) and one malformed file (to demonstrate row errors).
- **Names:** fictional merchant and person names only, so nothing looks like real data.
- **Loading:** `rake demo:seed` loads the files **through the real import pipeline** (import → duplicate detection → transfer suggestions → categorization), so the demo exercises production code.

### 5. Questions and conflicts for the product owner

| # | Question / conflict | Why it matters | Recommendation |
|---|---|---|---|
| PO-1 | `MVP_SCOPE.md` is still marked **Draft, not approved**, but this review (and the request) treats P1–P10 as the MVP | Revision 4 is sequenced on it | Approve or amend MVP_SCOPE before approving revision 4 |
| PO-2 | **Scope vs 3 days**: P1–P10 ≈ 56–82 h; the 3-day sprint ≈ 24–30 h. "Never cut P1–P3" + D-013 (all goal types) + success criterion 1 can't all hold in 3 days | Determines what "MVP done" means | Two milestones (M1 Days 1–3, M2 Days 4–7, taken from the v1 fortnight), or cut deeper and keep 3 days |
| PO-3 | Is the 3-day timeline (D-009) fixed, or can the MVP borrow from the ~2-week v1 window? | Same | — |
| PO-4 | **Obligation vs "upcoming payment" goal** both have amount + due date. Also: Emergency Fund / Retirement don't fit the three goal types | Users (and the coach) need a clear rule | Obligation = paid from regular cash flow and shown as "due"; upcoming-payment goal = saved toward ahead of time. Emergency fund → purchase-style goal without a date, or v1 |
| PO-5 | **Expected income** and **obligation paid-status** aren't in the approved concepts, but safe to spend needs both | Prevents wrong or double-counted figures | Income pattern as typed fields on the financial profile; MVP "mark paid" toggle (or an amount/date match) on obligations |
| PO-6 | **No current balance** in CSV-only data | Decides the safe-to-spend family of formulas | Phase 5 picks one: opening balance per account, optional `balance` column, or a budget-based formula |
| PO-7 | Labels: global per category, per user, or per transaction? Custom user categories in the MVP? | Schema and UI | Global defaults, read-only in the MVP; per-user overrides and custom categories in v1 |
| PO-8 | Category list details: one Income category or keep Salary/Freelance/…? Add Insurance, Fees & Interest, Other? Rename Debt Repayment? | Seeds and AI allowlist | One Income category; add Insurance and Other |
| PO-9 | Credit-card payments from checking when the card isn't imported: spending (debt payment) or transfer? | Spending totals | Debt Payments category unless both sides are imported and confirmed as a transfer |
| PO-10 | **Legacy UI and endpoints:** hide the Budget/Categories tabs in the MVP? Legacy endpoints scoped (S3-L) or read-only (410)? When are the legacy tables dropped? | S3 effort; data retention | Hide the tabs; scope the endpoints; drop tables only in v1, after a backup, with approval |
| PO-11 | **Are the existing 44 dev entries / 2 users real personal data?** D-008 says synthetic data only during development | Privacy | If real or unsure: create a **fresh** dev database for the MVP (the old one is kept and backed up, not dropped) |
| PO-12 | Week start day and time zone: fixed (e.g. Monday, device time zone) or per user? | Today / This week boundaries | Per user on `financial_profiles`, defaulting to Monday + the device time zone |
| PO-13 | Category budget period: monthly only in the MVP (weekly view prorated)? | Schema | Monthly only |
| PO-14 | Approve the `plan_proposals` table (not in the approved concept list) | "Nothing saved until approved" | Approve |
| PO-15 | CSV row limit for "several years" of history | Import design | 10,000 rows / 2 MB per file |
| PO-16 | Transfer matching window: exactly 3 days, and are transfers within the **same** account possible (e.g. sub-accounts)? | TR1 rules | 3 days, different accounts only |
| PO-17 | Credit cards as accounts at all in the MVP (sign convention, payments look like transfers)? | Import + transfers | Allowed (`kind = credit_card`), documented sign convention |
| PO-18 | Approve the generic CSV format (§4.2) | I1 | — |
| PO-19 | Documentation paths: the product docs refer to `claude/…`, but the files live in `docs/product/` | Traceability | Update the product docs' paths (not changed here) |
| PO-20 | S1a review status: approved (plan revision 3 header) or still waiting (this log)? Merge strategy for `feature/auth`? | Before S1b | Confirm S1a approved; keep working on `feature/auth` until M1 review |

**Stopped here.** Nothing is implemented. Next steps once you've reviewed: answer PO-1, PO-2, PO-11 and PO-20 at minimum, do KA step 4, and approve (or amend) plan revision 4.

---

## Plan revision 4.1 (2026-11-22) ✅ approved. M1 not started

Source: handoff #02 and `docs/product/DESIGN_DECISIONS.md` D-016 to D-019. `MVP_SCOPE.md` is now **Approved** (re-copied to `docs/product/`). `HANDOFF_CLAUDE_CODE_02.md` wasn't copied to `docs/product/`; its prompt was pasted directly, so nothing is missing.

**Docs only.** `IMPLEMENTATION_PLAN.md` is now revision 4.1 and this file was updated. No code, migrations, commits or pushes. `ARCHITECTURE.md` untouched.

### PO answers (D-018)

| # | Answer | Effect in revision 4.1 |
|---|---|---|
| PO-1 | MVP_SCOPE approved | Plan follows MVP_SCOPE P1–P10 and §6 fallback |
| PO-2, PO-3 | M1 = Days 1–3, M2 = Days 4–7, borrowed from the v1 fortnight | §3 |
| PO-4 | Obligation = paid from regular cash flow, shown as "due"; upcoming-payment goal = saved toward ahead of time; emergency fund = purchase goal without a date | `goals.target_date` optional for purchase; GoalCalculator handles no date |
| PO-5 | Income pattern as typed fields on `financial_profiles`; manual "mark paid" on obligations | ON1 typed fields; `obligation_payments` in OB1 |
| PO-6 | Budget-based "Left to spend" (amendment 2); opening balance / balance column optional, v1 | W1 / `LeftToSpend`; no balances in the MVP |
| PO-7 | Labels: global defaults, read-only in MVP; per-user overrides and custom categories in v1 | DM-1 |
| PO-8 | One Income category; add Insurance and Other | §2.5: 17 spending categories + Income + Transfers |
| PO-9 | Card payments from checking = Debt Repayment category unless both sides are imported and confirmed as a transfer | §2.5, keyword rules |
| PO-10 | Hide legacy tabs; scope legacy endpoints (S3-L); drop legacy tables only in v1, after backup, with approval | LG1, S3-L, §10 |
| PO-11 | Fresh synthetic-only dev database; old database kept and backed up | **DB0** (new) |
| PO-12 | Week start and time zone per user on `financial_profiles`; default Monday + device time zone | ON1, W1 |
| PO-13 | Category budgets monthly only | DM-3 |
| PO-14 | `plan_proposals` approved | AD10, PL1/PL2 |
| PO-15 | 10,000 rows / 2 MB per file | §2.4, I2 |
| PO-16 | 3-day window, different accounts only | TR1 |
| PO-17 | Credit cards allowed as accounts, documented sign convention | DM-2, §2.4 |
| PO-18 | Generic CSV format approved | I1 |
| PO-19 | Repo copies live in `docs/product/` (`claude/…` = `docs/product/…`) | Noted |
| PO-20 | S1a approved; keep working on `feature/auth` until the M1 review; commits/pushes need explicit approval each time | S1a row, §10 |

### Amendments folded in

1. **AI in M1:**
   - AI-0, **S4-min** (rack-attack on `categorize` + `ai_usage` daily cap checked before any Claude call) and **AI2** now come after AI1/AI3 in M1.
   - **TR1 is last in the M1 backend order**, so it moves to the start of M2 cleanly if M1 runs over.
2. **"Left to spend this week" (W1, `LeftToSpend`, `GET /home/week`):**
   - It's this week's share of the flexible category budgets minus flexible spending this week, and needs no balances.
   - Obligations and goal contributions due are listed separately and never subtracted.
   - **Smallest mark-paid schema:** `obligation_payments(obligation_id, due_on, paid_on, marked_by, transaction_id NULL)`, unique `(obligation_id, due_on)`. A row means that occurrence is paid; unmarking deletes the row.
   - W1 stays **blocked on the Phase 5 spec**.
3. **Tabs (LG1):** Home, Plan, Activity, Coach. C2/C2b live under Activity, with a needs-review badge. A new **C8** covers the Plan tab (budgets, bills, goals: the manual path into the coach's tables).
4. **First run (C5):** sign in → accounts + import → onboarding (prefilled from Rails-computed `onboarding/context`) → top 3–5 uncertain merchants (`onboarding/review_queue`) → plan draft → Home.
5. **CI and eval-lite (D-016):**
   - **CI1:** one GitHub Actions workflow per repo. Server: Postgres 14 service + `bin/rails test`. Client: tsc baseline check + `test:ci` once CT0 works. No secrets needed.
   - **EV1:** categorization eval over a labelled golden synthetic set, in M1.
   - **EV2:** Q&A eval (expected tool called, figures equal to analytics output), in M2.
   - Both evals run manually or via `workflow_dispatch`, never on push.
6. **Fresh dev database (DB0):** recorded below.
7. **Categories:** one Income category; Insurance and Other added.

Also applied: **Q-27**, uploaded CSVs parsed and discarded. `imports.row_errors` stores line number + error code only, with no raw row text (AD13).

### Fresh development database (DB0, planned; not yet created)

| | Old (kept) | New (MVP, synthetic only) |
|---|---|---|
| Name | `bb_server_development` | `bb_server_mvp_development` |
| Schema | Frozen at `20250419232612` | Current, with all M1/M2 migrations |
| Data | Existing 2 users / 44 entries; backup `backups/bb_server_development_2026-11-22.dump` | Seeds + DEMO-G synthetic data only |
| Select it | `BB_DEV_DATABASE=bb_server_development bin/rails …` (pre-MVP code), or `psql` in a read-only session | Default (no env var needed) |

- **Mechanism:** `config/database.yml` development `database: <%= ENV.fetch("BB_DEV_DATABASE", "bb_server_mvp_development") %>`, a one-line config change made in DB0 at the start of M1.
- **Old database:** no migrations are applied to it. With the new code it would report pending migrations, so it's for reference and rollback only.

### Updated M1 estimate

| Block | Hours |
|---|---|
| Security (S1b, S2, S3/S3-L, TS0, C0) | 5–7.5 |
| DB0 | 0.5 |
| LG1 (4 tabs) | 1–1.5 |
| DM-1, DM-2, T1, I1, I2, C2 | 7–10 |
| TR1 + transfers screen | 3–4 |
| AI1, AI3, review screen + badge | 3.5–5 |
| **AI-0, S4-min, AI2 (added)** | **4–6** |
| DEMO-G (+ golden labels) | 2–3 |
| **CI1 (added)** | **1–2** |
| **EV1 (added)** | **1.5–2.5** |
| CT0 | 1–1.5 |
| M1 QA / buffer | 1.5–2 |
| **Total** | **31–46 h** (was 26–35 h) |

**M1 doesn't fit Days 1–3 as specified.**
- Three days is roughly 24–30 focused hours.
- With the agreed slips (TR1 + transfers screen → M2, then CT0), M1 is 27–40 h. That fits only at the optimistic end.
- M2 is now **31–48 h** (+3–4 h if TR1 moves in), against roughly 32–40 h in Days 4–7, so it's also tight.

### New questions and conflicts

| # | Question | Recommendation |
|---|---|---|
| PO-21 | M1 is 31–46 h vs ~24–30 h. Accept that M1 may run into Day 4 (pushing M2 to Days 5–8, still inside the ~2-week window), or approve a further M1 slip order? | Accept a possible Day 4 overrun. If you prefer cutting, slip EV1 report polish (keep the raw accuracy number), then the M1 QA buffer. Keep AI2 and the server CI job |
| PO-22 | `eval.yml` on GitHub needs an `ANTHROPIC_API_KEY` repository secret, a credential stored at GitHub | You add it yourself (Claude Code never handles the value). Until then, evals run locally |
| PO-23 | CI only runs after a push, and every push needs your approval | Approve pushes of `feature/auth` at checkpoints (e.g. after S3, after AI2), or keep CI local-only until the M1 review |
| PO-24 | "Flexible" categories for Left to spend come from the global labels, which are read-only in the MVP (PO-7). A user who considers a "fixed" category flexible can't change it | Acceptable for the MVP. The Phase 5 spec should name the labels that count as flexible |
| PO-25 | `HANDOFF_CLAUDE_CODE_02.md` isn't in `docs/product/` | Copy it for traceability (not blocking) |
| PO-26 | PO-9's answer says "Debt Payments category", but no rename of the existing "Debt Repayment" tag was approved (PO-8 only added Insurance and Other) | Keep "Debt Repayment" (matches today's tag), unless you confirm the rename. It's a seed-only change either way |

~~**Still on you:** KA step 4.~~ Done 2026-11-24 (see KA above). S1b is unblocked.

**Waiting:** M1 starts only when you say so.

---

## iOS development build on a physical iPhone (2026-11-23 → 2026-11-24) ✅ working

### Diagnosis

The app couldn't launch on your iPhone through Expo Go:
- The App Store build of Expo Go only runs **one** SDK, the current one (54–58 at the time). SDK 51 isn't it, and iOS can't install an older Expo Go.
- "Couldn't load" was this mismatch.
- The repo itself had no startup bug.

### Decision (PO-27, you, 2026-11-23): option (a)

Keep SDK 51 and use a **local custom development build** to unblock KA step 4. Then add an **Expo SDK upgrade as its own task before C0** (UP1 in the plan), so new client work starts on a current SDK. The rejected alternatives:
- (b) upgrade first, which would have delayed S1b by 1–2 days;
- (c) stay on SDK 51 for the whole MVP.

### Changes (bb-client, `main`, all uncommitted)

| File | Change |
|---|---|
| `package.json` / `package-lock.json` | `react-native-svg@15.2.0` added: a missing peer of `react-native-pie-chart`, which only gets linked into a native build if it's a direct dependency. Aligned to SDK 51's expected versions: `expo` ~51.0.39, `expo-router` ~3.5.24, `expo-splash-screen` ~0.27.7, `@react-native-picker/picker` 2.7.5, `@react-native-community/datetimepicker` 8.0.1, `@react-native-community/slider` 4.5.2. `expo-dev-client` was added, then **removed**: its `expo-dev-menu` 5.0.23, the latest for SDK 51, doesn't compile on Xcode 16.4 (`Cannot find 'TARGET_IPHONE_SIMULATOR' in scope`). Scripts `ios`/`android` are now `expo run:ios`/`expo run:android` (set by prebuild). Previous manifests backed up in the session scratchpad. |
| `app.config.ts` | `ios.bundleIdentifier: "app.budgetbuddy.mvp.dev"` (required by prebuild; generic, no personal data). |
| `.gitignore` | `/ios` (generated by `expo prebuild`; not edited by hand. The signing team is set in Xcode and has to be re-selected if `ios/` is regenerated.) |
| `.env` (ignored) | Kinde callback and logout URLs now `budget-buddy-scheme://kinde_callback` and `budget-buddy-scheme://kinde_logout`. The old `exp://` lines are kept as comments. `EXPO_PUBLIC_API_BASE_URL` host is now `the Mac's LAN IP` (the Mac's IP changed). You also replaced a placeholder client ID. |
| Kinde dashboard (you) | The two `budget-buddy-scheme://` URLs were added to the mobile app's allowed callback and logout URLs. The old `exp://` entries are kept. |

`npx expo install --check` reports "Dependencies are up to date". Two `expo-doctor` warnings remain, both accepted:
- SDK 51 officially supports Xcode up to 16.2, and 16.4 is installed; this is what broke `expo-dev-menu`.
- A nested `@expo/config-plugins` 7.3.1 bundled inside the Kinde SDK (with its own older `expo-constants`). Login works.

### Environment (your Mac)

- **Xcode 16.4**, the newest available for macOS 15.3. It has the iOS 18.5 SDK. All simulator runtimes were removed to save disk space; none are needed for device builds.
- **CocoaPods 1.17.0**, installed into rbenv Ruby **3.4.13**. Homebrew Ruby 3.3.0 stays **pinned**: it is `bb-server`'s Ruby (rbenv `3.3.0` symlinks to it), and unpinning would upgrade it to Ruby 4.0. Run pod and prebuild commands with `RBENV_VERSION=3.4.13`.
- iPhone 16, iOS 26.5, Developer Mode on, free Apple ID (Personal Team) signing. The app expires after **7 days**; rebuilding from Xcode renews it.
- The Expo CLI on SDK 51 can't detect iOS 26 devices (`expo run:ios --device` fails), so builds run from Xcode (▶).

### How to run on the phone

1. `cd bb-client && npx expo start -c`. Don't scan the QR code; it opens Expo Go.
2. Open the **bb-client** app on the phone, or press ▶ in Xcode with the phone as destination.
3. Phone and Mac must be on the same non-guest Wi-Fi. Local Network permission for bb-client must be on.
4. **If the Mac's IP changes:** update `EXPO_PUBLIC_API_BASE_URL` in `.env`, restart Metro, and **rebuild in Xcode**, because the Metro address is baked into the debug build (`ip.txt`). A DHCP reservation for the Mac in the router avoids this.

### New questions

| # | Question | Recommendation |
|---|---|---|
| PO-28 | UP1 (Expo SDK 51 → current, est. **8–16 h**) goes before C0 per PO-27. That raises M1 from 31–46 h to **39–62 h**, against ~24–30 h. Accept, or move UP1 to the start of M2 (C0/LG1/C2 would then be built on SDK 51 and migrated)? | Keep UP1 before C0, as decided, but time-box it at 12 h. If it runs over, finish M1's client work on SDK 51 and continue the upgrade at the start of M2. Backend tasks (S1b onward) aren't affected and can run in parallel |
| PO-29 | Remove the temporary `[KA check]` log now (KA acceptance criterion), and commit the bb-client changes (KA + dev build) to a branch? | ✅ **Approved and done (2026-11-24):** log removed; pushing both branches approved (to be run by you; my shell can't unlock your SSH key); `bb-client` branch `feature/ios-dev-build` (from `main` @ `81fa7d7`), commit **`6a61d74`**, local only, not pushed. It has the KA config (`KindeConfig.ts`, `.env.example`, `.env*` ignore) and the dev-build changes (`app.config.ts`, `/ios` ignore, `package.json`/lockfile). `tsc` is still at the 100 baseline. |

---

## M1 started (2026-11-24)

**Decisions:**
- **PO-28:** you kept UP1 before C0. You didn't set a cap, so I'll flag UP1 to you at 12 h rather than stopping on my own.
- **S1b:** approved.
- **M1:** started.

### DB0 — fresh development database ✅ done (uncommitted, `bb-server` `feature/auth`)

- **Config:** `config/database.yml` development `database:` is now `ENV.fetch("BB_DEV_DATABASE", "bb_server_mvp_development")`.
- **New database:** `bb_server_mvp_development`, created with `db:create db:schema:load db:seed`. It has 5 categories (**ids 1–5**), 38 default tags, and no users, budgets or entries.
- **Switching:** `BB_DEV_DATABASE=bb_server_development bin/rails …` selects the old database. Verified with `bin/rails runner`.
- **Old database untouched:** before and after, users 2, budgets 1, tags 38, entries 44, entries_tags 76, categories 5, schema `20250419232612`.
- **Note:** the legacy client hard-codes category ids **6–10** (`utils/types.ts`). On the new database, the legacy Categories screens won't find their categories. This is expected: DM-1 reworks categories and LG1 hides the legacy screens.
- **Restart needed:** a running Rails server picks up the new database only after a restart.

### S1b — authentication on every API endpoint ✅ done (uncommitted, `bb-server` `feature/auth`)

| File | Change |
|---|---|
| `app/controllers/concerns/authenticatable.rb` (new) | `before_action :authenticate!`. It reads `Authorization: Bearer` (scheme case-insensitive) and verifies the token with **one memoized `Kinde::TokenVerifier` per process**, built with `require_audience: true`. Success sets `current_auth_claims` / `current_kinde_sub`. `InvalidToken` → **401** `{"error":"unauthorized"}` plus `WWW-Authenticate: Bearer`. `KeysUnavailable` → **503** `{"error":"authentication_unavailable"}`. Logs record only `[auth] rejected request: <reason>`, never the token or header. |
| `app/controllers/application_controller.rb` | `include Authenticatable`, so all 5 `api/v1` controllers are covered. `/up` (Rails' health controller) stays public. |
| `config/initializers/kinde_auth.rb` (new) | Builds the verifier at boot outside tests, so dev and prod **refuse to start** without `KINDE_ISSUER_URL` / `KINDE_AUDIENCE`. Building it makes no network calls. |
| `test/support/auth_test_helper.rb` (new), `test/test_helper.rb` | A local test RSA key, a fake JWKS fetcher and an `auth_headers` helper. No network in tests. |
| `test/controllers/{budgets,entries,tags,users}_controller_test.rb` | Requests now send `headers: auth_headers`. Assertions are unchanged. |
| `test/controllers/authentication_test.rb` (new, 24 tests) | Every controller and custom route without a token → 401. Writes without a token change nothing. Expired, wrong-audience, missing-audience, wrong-issuer, missing-`sub`, wrong-key, unknown-`kid`, garbage, empty and `Basic` tokens → 401. A valid token → 200. Key-fetch failure → 503. `/up` is public. The log contains the reason and not the token. The controllers' verifier refuses to build without an audience. |

**Checks:**
- **Test suite:** **94 runs, 289 assertions, 0 failures** (was 70/200).
- **Mutation check:** with `include Authenticatable` removed, 20 of the 24 authentication tests fail, as intended.
- **Boot:** the dev server boots with `.env`; with `KINDE_AUDIENCE` empty it fails with `ConfigurationError`.
- **Live server:** `/api/v1/budgets` and `/users/show_by_email` → 401, `/up` → 200.

**Effects to know about:**
- **The current mobile app now gets 401s** on every data call. It doesn't send the token until **C0**. Login itself (Kinde) still works.
- **No `current_user` yet:** mapping `sub` to a user needs `users.kinde_id`, which is S2.
- **Not scoped per user yet:** any valid token can still reach any user's legacy data. S3/S3-L adds per-user scoping.
- `ARCHITECTURE.md` isn't updated yet. That waits until the M1 review, once more is built.

**Next:** S2 (`users.kinde_id`, `GET /me`, SR-1 linking). On the client side, TS0 and then UP1. **Waiting on you:** approval to commit DB0 and S1b on `feature/auth`.

---

## Handoff #04 (2026-11-24): auth status, plan update, database inputs

**The handoff file isn't in `docs/product/` yet.** The other four product docs were copied on 2026-11-24 (`PRODUCT_BRIEF`, `MVP_SCOPE`, `DESIGN_DECISIONS` D-000–D-021, `SPEC_LEFT_TO_SPEND`). `HANDOFF_CLAUDE_CODE_04.md` wasn't (the same gap as PO-25 for #02). This doesn't block anything.

### Step 1: auth status, measured on 2026-11-24 (answers Q-35)

| Task | Status | Tests | Branch / commit |
|---|---|---|---|
| **S1a** token verifier | ✅ Done, approved (PO-20) | 50 focused tests in `test/services/kinde/` | `bb-server` `feature/auth` @ **`3b54035`** (committed, **not pushed**: no upstream set) |
| **KA** API audience, steps 1–4 | ✅ Done. Step 4 on 2026-11-24 on a physical iPhone, **claims only**: `iss` `https://budgetbuddyapp.kinde.com`, `aud` `["https://api.budgetbuddy.app"]`. Both match `bb-server/.env` (compared without printing). **The temporary `[KA check]` log is removed** (0 occurrences in `bb-client/app` and `utils`). | Manual check (no automated test for a live Kinde login) | `bb-client` `feature/ios-dev-build` @ **`6a61d74`** (committed, **not pushed**: no upstream set) |
| **S1b** authentication on every `api/v1` endpoint | ✅ Done and tested, **uncommitted** | 24 new tests (`authentication_test.rb`); full suite **94 runs / 289 assertions / 0 failures** | `bb-server` `feature/auth`, working tree (11 changed or new files, together with DB0) |
| **S2** `users.kinde_id`, `GET /me`, SR-1 linking | ❌ **Not started** | — | — |
| **S3 / S3-L** ownership scoping, CORS allowlist | ❌ **Not started.** CORS is still `origins '*'`. Legacy endpoints are authenticated, but **not scoped per user**. | — | — |
| **C0** client token + 401 handling | ❌ **Not started** (after UP1, per PO-27/PO-28) | — | — |

**Where this differs from the plan, or from what the handoff assumes:**
1. **"Kinde API authentication is working" is only half true.** Tokens are issued with the right audience and the API verifies them (S1b). But **no request is tied to a user yet** (S2), **no data is scoped per user** (S3), and **the app doesn't send the token** (C0). So the current app gets **401** on every data call: an expected gap until C0.
2. **Pushes:** you approved pushing on 2026-11-24, but it can only be done from your Terminal (SSH passphrase). Neither branch has an upstream yet. I couldn't query GitHub from my shell, so I can't confirm whether a push happened.
3. **No other deviations:** S1b follows rev. 3/4.1 exactly. It has a memoized verifier, the audience is required, 401/503 bodies give no reason, logs hold the reason only, and boot fails without config.

### Step 2: plan updated ("Revision 4.1 — Approved (2026-11-24)")

Handoff items 1–4 (AI in M1, the four tabs, first-run order, CI + eval-lite) and the `obligation_payments` idea were **already in rev. 4.1** from handoff #02, so they're unchanged. **New in this update:**
- **W1 unblocked:** it points at the spec, the endpoint is `GET /api/v1/outlook/week` (renamed from `/home/week`), and its acceptance tests are spec §10 examples 1–9 + the §9 response shape + an ownership test.
- **`obligation_payments` schema confirmed** as the spec proposes: `obligation_id`, `due_on`, `paid_on` + timestamps, unique `(obligation_id, due_on)`, FK `restrict`. I **dropped** rev. 4.1's `marked_by` and `transaction_id`: both only serve v1's automatic matching, and adding them later is additive.
- **C3:** the spec labels, a shared conservative-rounding helper with its own unit tests, and the four states in precedence order.
- **Brand (D-020):** palette tokens and fonts for new screens. `@expo-google-fonts/*` is a new dependency, installed with approval.
- **Categories:** spec §7 `fixed_variable` labels. The new debt category is named **"Debt Payments"**: a new row, so the legacy tag "Debt Repayment" is untouched (**resolves PO-26** with no rewrite).
- **Legacy category rows:** they get `kind = legacy` / `active = false` through **column defaults at the time the columns are added**, with no `UPDATE`. On the MVP database they're ids **1–5**, not 6–10.
- **`financial_profiles`:** `week_starts_on` (0–6, default 1 = Monday) and `time_zone` (validated IANA name). The device zone is sent with `/me` and onboarding; until it's set, W1 uses `UTC` and says so in its assumptions.
- **M1 estimate:** UP1 (8–16 h) is now in the table. Total **39–62 h**, about **37–60 h remaining**. A risk row was added for the time zone.

### Step 3: database inputs, checked against the plan

| Input | Status |
|---|---|
| Fresh synthetic-only dev database, old one kept, switching documented | ✅ Done (DB0, above) |
| Categories: 17 spending (15 + Insurance + Other), one Income, Transfers (`kind = transfer`), spec §7 labels, legacy rows `legacy`/inactive | In the plan (§2.2, §2.5, DM-1). "Debt Payments" naming per the spec |
| `financial_profiles.week_starts_on` / `time_zone` + income pattern | In the plan (§2.2); defaults specified above |
| `obligation_payments` | Confirmed (§2.2) |
| `plan_proposals`, credit cards, CSV limits (10,000 rows / 2 MB), transfer window (3 days, different accounts) | Already in the plan (PO-14/15/16/17) |
| Additive, reversible migrations; no row rewrites | Yes. Migrations run only on the MVP database (DB0); the old database stays at `20250419232612` |

### Conflicts for the product owner

| # | Conflict | Recommendation |
|---|---|---|
| PO-30 | **Order.** The handoff says to continue M1 "in plan order, starting with the database tasks (DM-1 → DM-2 → T1 …)". But the plan order is **S2 → S3 → DM-1**, and S2/S3 aren't done (the handoff seems to assume they are). | **Do S2 then S3 first** (about 3–4 h): they're security priority 1 and "never cut", and DM-2 onwards needs S3's scoping pattern for every new controller. DM-1 itself only touches global categories, so it *could* go first if you prefer the handoff's order |
| PO-31 | **Uncommitted work is piling up.** DB0 + S1b are uncommitted on `feature/auth`; S2 onwards would add more on top. | Approve committing DB0 and S1b now, as two commits |
| PO-32 | **M1 timeline.** With UP1, M1 is 39–62 h against ~24–30 h. The handoff asks for an estimate "including AI and CI", which is in there too. | Accept M1 running to about Day 5, or move UP1 to M2 (PO-28 alternative) |

---

## Decisions (2026-11-24, after handoff #04)

- **PO-30:** S2 → S3 first, then DM-1.
- **PO-31:** commit DB0 and S1b. **Done:** `bb-server` `feature/auth`, **`919d8b7`** (DB0) and **`654dfc9`** (S1b). Local only.
- **PO-32:** accept M1 running to about Day 5.
- **Brand:** the PO shared the logo sheet (Acorn Keeper: lockup, app icon on Pine, small sizes, coach avatar on Fern) and the Forest Floor type sheet. Saved as `docs/product/brand/logo-acorn-keeper.png` and `docs/product/brand/forest-floor-type.png` for the screen work. Nothing in them conflicts with D-020.

## S2 — `users.kinde_id`, `GET /me`, SR-1 linking ✅ done (uncommitted, `bb-server` `feature/auth`)

| File | Change |
|---|---|
| `db/migrate/20261124150000_add_kinde_id_to_users.rb` | `users.kinde_id` (string, unique index) and a unique `lower(email)` index. Additive. |
| `db/migrate/20261124150100_create_financial_profiles.rb` | `financial_profiles` per plan §2.2: `user_id` unique FK, `answers`/`coach_notes` jsonb, `answers_version`, `pay_frequency`, `next_pay_on`, `typical_pay_amount` decimal(12,2), `change_appetite`, **`week_starts_on` int not null default 1 (Monday)**, **`time_zone`** (IANA, nullable), `onboarding_completed_at`. |
| `app/models/user.rb`, `app/models/financial_profile.rb` | `has_one :financial_profile`. Names and email are only required for legacy users (Kinde may not provide them). Email uniqueness is case-insensitive. Profile validations: week 0–6, pay frequency, change appetite, amount ≥ 0, `time_zone` a valid IANA zone (TZInfo). |
| `app/services/kinde/user_profile_fetcher.rb` (new) | `GET <issuer>/oauth2/v2/user_profile` with the caller's verified token, called server-side: https on the issuer host only, 3 s timeouts, 20 KB cap. Every failure → `Unavailable`; messages never contain the token. |
| `app/services/users/kinde_provisioner.rb` (new) | **SR-1.** Find by `kinde_id`, without calling Kinde. Otherwise fetch the Kinde profile; its `id` must equal the token's `sub`. If an existing user's email matches (ignoring case), link only if `email_verified` is **exactly `true`** and the row has no `kinde_id` (a conditional `UPDATE … WHERE kinde_id IS NULL`, so a race can't overwrite). Otherwise raise `Conflict`. No email match → create the user from Kinde's email and names. Then make sure exactly one `financial_profile` exists. Races on the unique indexes are handled. Logs record user id + sub only. |
| `app/controllers/concerns/authenticatable.rb` | Adds `current_user` (by `kinde_id`, memoized), `require_current_user!` (→ **403** `{"error":"user_not_provisioned"}`), and keeps the verified token privately for the Kinde call (never logged or rendered). |
| `app/controllers/api/v1/me_controller.rb` (new), `config/routes.rb` | **`GET /api/v1/me`** → `{id, email, first_name, last_name, picture, onboarding_completed, profile: {week_starts_on, time_zone}}` (no `kinde_id`). An optional `time_zone` param is stored only if the profile has none and it's valid (PO-12, spec §2). Unlinkable email → **409** `account_link_required`; Kinde unavailable → **503** `profile_unavailable`. |
| `app/controllers/api/v1/users_controller.rb` | **The caller's own record only** (rev. 3 S2 compatibility): `index` → `[current_user]`; `show`/`update`/`destroy` of anyone else → 404; `show_by_email` → only the caller's email (case-insensitive), else 404; **`create` provisions the caller like `/me`** and ignores the body (so the legacy "look up, else create" flow keeps working after C0); `update` permits names only (the email comes from Kinde). |
| Tests | New: `test/services/users/kinde_provisioner_test.rb` (13, SR-1), `test/services/kinde/user_profile_fetcher_test.rb` (8), `test/controllers/me_controller_test.rb` (9). Rewritten: `users_controller_test.rb` (12, own-record rules). `AuthTestHelper` gains a fake Kinde profile endpoint (tests can't reach Kinde), and fixture users get `kinde_id`s. |

**SR-1 detail checked during S2:**
- **The `email_verified` field.** A mirror of Kinde's OpenAPI spec defines `email_verified` (boolean) on `/oauth2/v2/user_profile`. Kinde's own API page lists the email but doesn't mention the flag, so it's **unconfirmed against a real response**. The code links only on `email_verified === true`, so a missing field means **no automatic linking**, as the plan requires.
- **Confirm with a real response at C0.** Check the profile response has `email_verified` (field names only, no values printed).
- **Linking only matters for the old database's 2 users**, which aren't in the MVP database. Any manual link for them stays out of plan (§10).

**Checks:**
- **Test suite:** **131 runs, 426 assertions, 0 failures** (was 94/289).
- **Mutation checks:** treating a missing or non-`true` `email_verified` as verified → 2 SR-1 tests fail. `GET /users` returning every user → the scoping test fails.
- **Migrations:** applied to `bb_server_mvp_development`, rolled back (`STEP=2`) and re-applied cleanly. The old database is still at `20250419232612`.

**Notes:**
- **Restart Rails** to use the MVP database with the new tables.
- **Pending-migrations error is expected on the old database.** Running the server with `BB_DEV_DATABASE=bb_server_development` now raises it (DB0: the old database is kept unmigrated).
- **Other legacy endpoints aren't scoped per user yet.** Budgets, entries, tags and categories get that in **S3**.

**Next:** S3/S3-L (ownership scoping for the legacy endpoints, CORS allowlist, `authorization` filtered from logs), then DM-1. **Waiting on you:** approval to commit S2.

## S2 committed

`bb-server` `feature/auth` **`c9a5ffa`** (approved 2026-11-24). Local only.

## S3 / S3-L — ownership scoping, CORS allowlist, log filtering ✅ done (uncommitted, `bb-server` `feature/auth`)

| File | Change |
|---|---|
| `app/controllers/application_controller.rb` | `rescue_from ActiveRecord::RecordNotFound` → **404** `{"error":"not_found"}`, so another user's record looks the same as a missing one (AD2). Helpers `render_forbidden` (403) and `render_invalid_reference` (**422** for unknown or invisible reference data). |
| `budgets_controller.rb` | `require_current_user!`; every lookup goes through `current_user.budgets`; create builds on `current_user.budgets`; **`user_id` is no longer permitted** (injected values are ignored). |
| `entries_controller.rb` | Scoped through the caller's budgets. Writes check references first: a `budget_id` the caller doesn't own → **404** (including moving an own entry into another user's budget); an unknown `category_id` or an invisible `tag_ids` entry → **422**. Tags are synced only from visible tags. `entries_by_budget_with_default_categories` requires the caller's budget (else 404). |
| `tags_controller.rb`, `app/models/tag.rb` | `Tag.visible_to(user)` = global default tags + the caller's own. Show/index use it. **Writes only on the caller's own non-default tags**: default tags → **403**, other users' → 404. Create forces `user_id = caller`, `default_tag = false`. `default_tags` **ignores `user_id`** and returns all defaults. This also fixes the legacy client's `user_id: 1` filter, which returned nothing on the MVP database (its default tags have no owner). |
| `categories_controller.rb` | Reads unchanged (global reference data). **create/update/destroy → 403** (categories come from seeds, DM-1). |
| `config/initializers/cors.rb` | **No more `origins '*'`.** Exact origins from `CORS_ORIGINS` (comma-separated), only on `/api/*`, headers `Authorization, Content-Type, Accept`. Development defaults to the local Expo web ports (`http://localhost:8081`, `http://localhost:19006`); with nothing configured, no cross-origin browser access. A `*` in `CORS_ORIGINS` **fails boot**. (The native app doesn't use CORS; this protects the web build.) |
| `config/initializers/filter_parameter_logging.rb` | `:authorization` added (`:token` already covers `access_token`). |
| Tests | New: **`test/controllers/ownership_matrix_test.rb`**, the shared matrix. 21 rows targeting another user's users/budgets/entries/tags or category writes, each asserting the status **and that nothing in the database changed**. Plus index-lists-only-own, injected `user_id` ignored, own data still usable, unprovisioned token → 403, categories readable. New: `test/integration/cors_and_logging_test.rb` (an unlisted origin gets no CORS header; authorization filtered; the request log never contains the token). Rewritten: `tags_controller_test.rb`. Fixtures: tags owned per user plus a global default tag; a category fixture. |

**Checks:**
- **Test suite:** **163 runs, 505 assertions, 0 failures** (was 131/426).
- **Mutation checks:** an unscoped `Budget.find` → 3 matrix rows fail; removing the entry budget-ownership check → 2 fail.
- **Boot:** the dev server boots with the new CORS initializer.

**Notes:**
- **The matrix is meant to grow.** Each new resource (DM-2 accounts, T1/I2 transactions, OB1, G1, …) adds rows to `ROWS` in `ownership_matrix_test.rb`.
- **Restart Rails** to load the new CORS configuration. If you use the Expo web build from another origin, set `CORS_ORIGINS` in `bb-server/.env`.
- **Legacy client behaviour once C0 sends the token:**
  - budgets, entries and tags are the user's own;
  - `default_tags` now returns the 38 global defaults on the MVP database;
  - the hard-coded category ids 6–10 still won't match the MVP database (ids 1–5) until LG1 hides those screens.
- **Security block status:** S1b, S2 and S3 are done. C0 remains, after UP1.

**Next:** DM-1 (categories flat list + labels). **Waiting on you:** approval to commit S3.

## S3 committed

`bb-server` `feature/auth` **`2c92400`** (approved 2026-11-24). Local only.

## DM-1 — the flat category list ✅ done (uncommitted, `bb-server` `feature/auth`)

The design was approved on 2026-11-24, including the proposed `need_want` / `recurrence_label` defaults. The full design note was given in chat; its summary is in `docs/product/TARGET_MVP_ARCHITECTURE.md` §3.

| File | Change |
|---|---|
| `db/migrate/20261124160000_add_flat_list_columns_to_categories.rb` | **As reviewed, line for line.** Adds `slug`, `kind` (not null, default `legacy` then the default is dropped), `active` (not null, default false), `position`, `need_want`, `fixed_variable`, `recurrence_label`; a unique `slug` index; six CHECKs (kind values; each label's values; spending ⇒ `fixed_variable`; non-legacy ⇒ `slug`). |
| `app/models/category.rb` | Constants, validations matching the CHECKs, predicates, and the scopes `active_list` (active, non-legacy, by position), `spending`, and `flexible` (spec §7). Documents that new rows leave `category_type` NULL. |
| `db/seeds.rb` | Legacy section: creates rows with `kind: legacy, active: false`, fills **only the new `slug` column** where empty (`legacy-expense` …), and **limits the legacy tag loop to `category_type = 'default'`**, so the new Income category gets no tags (K8). MVP section: 19 rows upserted by slug, `active: true`, `position` 1–19, spec §7 `fixed_variable`, and the agreed `need_want` / `recurrence_label` defaults. **`category_type` isn't set.** Saved only if something changed. |
| `app/controllers/api/v1/categories_controller.rb` | `GET /categories` → `active_list` with `id, slug, name, kind, position` and the labels. It previously returned all rows. **The current client never calls this endpoint** (checked: no `/categories` call in `bb-client/store` or `app`). `categories#default` is unchanged. |
| `app/models/financial_profile.rb` | Documents `week_starts_on` as Ruby `wday` (**1 = Monday**, the default; 0 = Sunday), with constants `MONDAY`/`SUNDAY`, and `time_zone` as an IANA name. |
| Tests | New `test/models/category_test.rb`. Each database constraint is checked in its own savepoint, asserting the specific `PG::CheckViolation` / `NotNullViolation` / `UniqueViolation`. New `test/integration/category_seed_test.rb`: seed twice → no change; the 17 + Income + Transfers slugs; flexible and fixed sets exactly as spec §7; the agreed label defaults; new rows' `category_type` NULL; `categories#default` returns only legacy rows; legacy rows inactive with no new tags; `GET /categories` order and labels. New `test/models/financial_profile_test.rb` (Monday default, wday range, IANA zone). The fixture category is now explicitly legacy. |

**Checks:**
- **Migration:** migrated `bb_server_mvp_development`. Right after migrating (before seeding), the 5 existing rows read `kind = legacy`, `active = false`, with no `UPDATE`. **Rollback** gives a `schema.rb` identical to before (apart from the version line), and **re-migrating** gives an identical schema.
- **Seed:** run twice; the second run changes nothing (24 categories: 19 active + 5 legacy; 38 tags; the same latest `updated_at`). Only the 5 legacy rows have `category_type = 'default'`. Flexible = groceries, dining-out, entertainment, transportation, healthcare, clothing, personal-care, gifts, travel, home-improvement, other.
- **Test suite:** **180 runs, 554 assertions, 0 failures** (was 163/505).
- **Old database:** still at schema `20250419232612`.

### Differences from `TARGET_MVP_ARCHITECTURE.md` (draft, 2026-11-24)

What's built matches the target: security §2, `users` / `financial_profiles` / `categories` in §3. Points to note for the Claude Project, which owns that file:
1. **Statuses are now behind.** S3 is committed (`2c92400`), not 🟡, and DM-1 is built (🟡, uncommitted), not 📐.
2. **The ER diagram leaves out three links that the schema design has:** `categories → obligations`, `accounts → obligations` (paid from), and `categories → merchant_rules`. They're present in the design and will be built (OB1, AI3).
3. **Everything else, including §4 services and §5 AI, is unbuilt (📐) and consistent with the plan.** The "under $15/month" AWS ceiling in §7 is new information. It isn't in `DESIGN_DECISIONS.md` (Q-25 is "partly answered"), so it should be recorded there.

`docs/ARCHITECTURE.md` now has an "As-built changes since the audit" section covering S1a–S3, DB0, DM-1 and the iOS development build. The section-by-section rewrite of the 2026-11-22 audit is still planned for the M1 review.

**Waiting on you:** approval to commit DM-1; and the C0 ordering question (PO-33, below).

| # | Question | Recommendation |
|---|---|---|
| PO-33 | The current app is unusable for data (every API call → 401) until C0. C0 only depends on S2 + KA (done) and TS0 (~0.5 h), **not** on UP1. Move **TS0 → C0 before DM-2**? | **Yes.** C0 is plumbing (an axios instance with the token, 401 → login, `GET /me`), not new screens, so PO-27's reason for UP1-first (don't build screens on SDK 51) doesn't apply. Rework after UP1 is about 0.5 h at most (the `getToken` call, if the Kinde SDK is replaced). Keep **UP1 before LG1**, the first new screens. |

## Decisions (2026-11-24, later)

- **DM-1 (new category list) committed:** `bb-server` `feature/auth` **`389458b`**. Local only.
- **PO-33 (build order: C0 before DM-2) approved.** The order is now TS0 (TypeScript baseline) → C0 (app sends the login token) → DM-2 (accounts).
- **UP1 (Expo upgrade) stays before LG1 (new tab layout), capped at one working day.** If it isn't done by then: stop, report what's blocking, continue on SDK 51 with the development build, and finish the upgrade in v1.
- **House rule:** IDs are written with their plain name the first time (`docs/GLOSSARY.md`), now in `CLAUDE.md`. The glossary is at `docs/GLOSSARY.md`, not `docs/product/`. IDs missing from it so far: DB0 (fresh dev database), CI1 (GitHub Actions CI), EV1 (categorization eval), EV2 (coach Q&A eval), S4-min (minimal rate limit and AI cost cap), C8 (Plan tab screens), PO-n questions.

## TS0 (TypeScript baseline) ✅ done (uncommitted, `bb-client` branch `feature/client-auth`, from `feature/ios-dev-build`)

- **`scripts/tsc-baseline-check.js`** + `npm run tsc:check`. It runs `tsc --noEmit` and **fails if the total, or any single file's count, rises** above `tsc-baseline.json`. `--update` records the current state (only to lower it). Tested: adding one error to `utils/services.ts` → `FAILED … utils/services.ts: 1 -> 2`.
- **Baseline:** 100 errors in 21 files at the start; **99 after C0** (the rewritten user lookup removed one), now recorded.
- **Grouped by cause:**

| Cause | Errors |
|---|---|
| NativeWind `className` isn't declared to TypeScript (no `nativewind/types` reference) | 48 (TS2769 ×37, TS2322 ×11) |
| Implicit `any` parameters | 15 (TS7006, TS7031) |
| Store data typed loosely (tags as `string`, `null` as an index) | ~14 (TS2339, TS2538) |
| Missing modules (`@/components/HelloWave`, `@/types`, `@storybook/react`) | 5 (TS2307) |
| `unknown` values used directly | 5 (TS18046) |
| Assorted one-offs | ~13 |

Nearly half have one cause: NativeWind's types. UP1 (Expo upgrade, which moves to NativeWind 4) or a one-line type reference would remove them. **No error was fixed in TS0**, by design.

## C0 (app sends the login token) ✅ code done, ⏳ needs a phone test (uncommitted, `bb-client` `feature/client-auth`)

| File | Change |
|---|---|
| `utils/api.ts` (new) | The one axios client. `baseURL` = `EXPO_PUBLIC_API_BASE_URL`; 15 s timeout. **The request interceptor attaches `Authorization: Bearer <access token>`** from `client.getToken()` (errors → no header). **The response interceptor handles a 401:** one `client.forceTokenRefresh()` + retry; if that fails, it removes the `login` flag and calls `router.replace("/login")`, de-duplicated. The token is never logged. `deviceTimeZone()` returns the device's IANA zone. |
| `store/budget.ts` | All 10 calls go through `api` (no direct `axios`, no `apiUrl`). **The user lookup is now `GET /me?time_zone=<device zone>`**, replacing `getUserDetails` → `show_by_email` → `POST /users`, which was also broken: it tested `.length` on an object and axios throws on a 404. **The entries prefetch at the start of `fetchUserData` only runs when there's a budget, inside a `try`.** Since S3 (ownership rules), a missing budget is a 404, which would have aborted the whole user load. `user_id` params removed (the server ignores them since S3). |
| `package.json` | `tsc:check` script only. No dependency changes. |

**Not done yet:**
- **The hard-coded category ids 6–10 aren't fixed**, so the legacy Categories screens won't show the MVP database's categories until LG1 (new tab layout) hides them.
- **No automated client test,** because CT0 (client test setup) hasn't been done.

**Phone test steps (acceptance):**
1. Restart Rails (`bin/rails server -b 0.0.0.0`; it now uses the MVP database).
2. Restart Metro with `npx expo start -c`.
3. Open the app and **sign in**. Home should load with no 401s in the Metro log.
4. Create a budget.
5. Look in the Rails log for `[auth] created user_id=… for sub=…` and `[auth] kinde profile fields: …`.
6. Send me the field names only. They confirm whether `email_verified` exists, which SR-1 (safe account linking) relies on.

**Server, temporary:** `Users::KindeProvisioner` logs the Kinde profile's **field names** (never values), in development only, for that check. It's to be removed once confirmed.

## DM-2 (accounts) ✅ done (uncommitted, `bb-server` `feature/auth`)

| File | Change |
|---|---|
| `db/migrate/20261124170000_create_accounts.rb` | `accounts`: `user_id` FK (not null), `name` (not null), `kind`, `purpose` (not null), `purpose_note`, `opening_balance` decimal(12,2) + `opening_balance_on` (optional, v1 / PO-6 balance-based safe to spend), `archived_at`, timestamps. **Unique `(user_id, lower(name))`.** CHECKs: `kind` ∈ checking/savings/credit_card/p2p/cash/other; `purpose` ∈ spending/bills/savings/side_income/other; trimmed name 1–60 characters; opening balance and date both set or both empty. |
| `app/models/account.rb`, `user.rb` | Validations matching the CHECKs (name trimmed and unique ignoring case, note ≤ 200), `active` scope, `archive!` (idempotent). The sign convention is documented (out −, in +; credit card purchases −). `User has_many :accounts`. |
| `accounts_controller.rb`, `routes.rb` | `GET/POST /accounts`, `GET/PATCH/DELETE /accounts/:id`, all through `current_user.accounts`. **DELETE archives** (204; the row is kept). Archived accounts are hidden from the list unless `?include_archived=true`, still readable, and **read-only** (PATCH → 422 `archived`). Permitted: name, kind, purpose, purpose_note; injected `user_id` ignored. The response has no `user_id`. `data_through` comes with I2 (import endpoint). |
| Tests | `test/models/account_test.rb` (7; database constraints asserted per savepoint), `test/controllers/accounts_controller_test.rb` (7), **3 new ownership-matrix rows** (show/update/destroy another user's account → 404, no change), and accounts in the list and unprovisioned checks. |

**Checks:**
- **Test suite:** **197 runs, 607 assertions, 0 failures** (was 180/554).
- **Migration:** migrate → rollback → `schema.rb` identical; re-migrate → identical.
- **Mutation check:** an unscoped `Account.find` → 3 matrix rows fail.

**Committed:** DM-2 (accounts) as `bb-server` `feature/auth` **`6adcb49`** (approved 2026-11-24; local only). The temporary Kinde-field log in `kinde_provisioner.rb` stays uncommitted. **Next:** T1 (transactions tables). **Waiting on you:** the C0 phone test, then approval to commit TS0 + C0 (client).

## Phone test finding 2: logout (2026-11-24) ✅ fixed (uncommitted, `bb-client` `feature/client-auth`)

**Symptom:** tapping Logout showed "Logout failed" and nothing was cleared.

**Cause:** `handleLogout` only cleared storage and navigated when `client.logout()` returned true. In Kinde SDK 1.3.1, `logout()`:
1. **first clears the SDK's stored tokens** (`cleanUp()` → `Storage.clearAll()`);
2. then opens Kinde's `/logout?redirect=<EXPO_PUBLIC_KINDE_LOGOUT_REDIRECT_URL>`;
3. returns `true` **only if Kinde redirects back into the app**.

So the phone was already signed out of Kinde locally, while the app kept its user and store data.

**Fix:**
- **`utils/session.ts` (new):** `logout()` always resets the store, clears persisted storage and AsyncStorage, and goes to `/login` (`router.replace`, so Back doesn't return), whether Kinde returns true, false or throws. Failures are logged as a fixed message plus the error's class name only, never error text, which could contain a token.
- **`app/(tabs)/index.tsx`:** `handleLogout` uses it: `clearUser`, then `useBudgetStore.persist.clearStorage()`, then `services.clearAllData()`, then `/login`.

**Is the logout URL allowed in Kinde?** `.env` has `EXPO_PUBLIC_KINDE_LOGOUT_REDIRECT_URL = budget-buddy-scheme://kinde_logout`. I couldn't verify the dashboard from here:
- An unauthenticated request to `<kinde-domain>/logout?redirect=…` returns the same `302 → /logged-out` for that URL and for a made-up one, so Kinde doesn't reveal its allowlist without a session.
- The symptom (no redirect back to the app) is **consistent with the URL not being on the allowlist**.
- **Owner action:** in Kinde, open the mobile application, find **Allowed logout redirect URLs**, and make sure `budget-buddy-scheme://kinde_logout` is listed exactly. Logout now completes locally either way; the allowlist only decides whether Kinde's page closes by itself.

## Stale persisted data cleared once (2026-11-24) ✅ (uncommitted)

**`store/budget.ts`:**
- Persist **`version: 1`** with **`migrate: migrateBudgetStore`**. Any older version, including the unversioned 0 that earlier builds wrote, is **discarded** and replaced with `initialBudgetData()`. It isn't migrated, because it refers to the old database's users, budgets and category ids.
- `initialBudgetData()` is now the single definition of the empty store, used by the initial state, `clearUser` and the migration.

**Tests:** the first client tests, and the start of CT0 (client test setup).
- **Setup:** `jest.config.js` (`jest-expo` preset, `@/` alias), `jest.setup.js` (official AsyncStorage mock), `npm run test:ci` (`jest --ci`).
- **`utils/__tests__/session.test.ts` (4):** Kinde true / false / throws (with a fake token in the error message, asserted **absent** from the log) / storage failure. In every case it clears and goes to login.
- **`store/__tests__/budget.persist.test.ts` (5):** the version is 1; migrate discards version 0 and keeps version 1; **a real rehydrate from stale version-0 AsyncStorage leaves an empty store and rewrites it as version 1**; `clearUser` resets.
- **Results:** **9/9 pass.** Mutation checks: restoring "clear only on success" → 2 fail; keeping stale state → 2 fail. `tsc:check` still at the 99 baseline.
- **Pre-existing failure, not caused by this change:** the Expo template's `components/__tests__/ThemedText-test.tsx` snapshot is out of date (`ThemedText` styles changed after the snapshot was recorded). It needs an owner decision (update the snapshot, or delete the template test) before `test:ci` is fully green.

## Reinstalling the development app: blocked (2026-11-24)

`xcodebuild` (phone connected, Mac IP still the Mac's LAN IP) stops with **"iOS 18.5 is not installed"**. The iOS 18.5 component was deleted along with the simulators to free disk space, and in Xcode 16 the device build support comes in that same download. Re-installing it means **about 8 GB** (30 GB free): `xcodebuild -downloadPlatform iOS`, or Xcode → Settings → Components → iOS 18.5 → Get.

**A reinstall isn't needed for today's changes.** They're JavaScript only, delivered by Metro to the installed app (reload it). A rebuild will be needed when the free-account signing expires (7 days after the first install, about 2026-11-30) or when native packages change (UP1, Expo upgrade).

### `/me` on every launch and after login (2026-11-24)

- `fetchUserData` (called when `Header` mounts on the Budget tab, so on launch and after every login) used to return early when a saved user and tags existed, skipping `GET /me`. That shortcut is removed: the app always asks the server who the caller is, and the server's answer replaces the saved user.
- Test: `store/__tests__/budget.fetchUser.test.ts` (2 tests). Putting the shortcut back fails the "saved user" test.
- Deleted the Expo template snapshot test `components/__tests__/ThemedText-test.tsx` and its snapshot (owner's decision). Client suite: 11 tests, all pass. `tsc:check`: 99 (baseline 99).
- iOS platform download started with `xcodebuild -downloadPlatform iOS`; Xcode chose the iOS 18.6 runtime (8.86 GB).
- Download finished; a Debug build for a physical iPhone now succeeds (`xcodebuild … -destination generic/platform=iOS`). The reinstall is unblocked. Disk: 21 GB free.

### T1 (transactions tables) — done, uncommitted (2026-11-24)

- **Migrations** (additive, reversible; rollback and re-migrate tested): `20261124180000_create_imports.rb`, `20261124180100_create_transactions.rb`.
- **`imports`:** per account; `status` processing/completed/failed; four counts ≥ 0; `row_errors` jsonb array of `{line, code}` only (AD13: no raw row text, file never stored); `data_from ≤ data_through`.
- **`transactions`:** per account; `amount` decimal(12,2), CHECK ≠ 0 (negative = money out); `description` ≤ 255; `normalized_description` (upper case, whitespace collapsed, trailing `#123`, `XXXX1234`/`****1234`, `CARD 1234` and bare 3+ digit numbers stripped); `base_key` = SHA-256(`posted_on|cents|normalized`), CHECK hex-64; `occurrence ≥ 1`; `external_id` optional.
  - Unique `(account_id, base_key, occurrence)`; partial unique `(account_id, external_id) WHERE external_id IS NOT NULL`; index `(account_id, posted_on)`; `category_id` indexed.
  - `categorization_source` in user/memory/rule/ai/transfer/none, and CHECK that `none` ⇔ no category. `confidence` 0–1.
  - Composite FK `(import_id, account_id)` → `imports(id, account_id)`: a transaction's import must be in the same account. Manual rows have no import.
  - FKs don't cascade. `Account` has `restrict_with_exception` on imports/transactions (archive, never delete).
- **Models:** `Import`, `Transaction` (`normalize_description`, `base_key_for`, `outflow?`/`inflow?`; assigned category must be on `Category.active_list`). `User has_many :imports/:transactions, through: :accounts` (AD2, no `user_id` column).
- **Tests:** `test/models/transaction_test.rb` (20), `test/models/import_test.rb` (4). Full suite **221 pass**. Mutation check: removing the same-account import validation fails a test.
- **Choices beyond the plan:** the composite FK and the source ⇔ category CHECK (both stop drift at the database); the normalization rule list is a first version that I1 (CSV parser) can extend.
- **Known gap (pre-existing):** `User has_many :accounts, dependent: :destroy` will now raise if an account has transactions. Deleting a user with data needs a decision (archive the user?) before any delete-account flow.

### C0 (app sends the login token) phone retest — passed (2026-11-24)

- Rails log, 22:28–22:29: `/me` 401 before sign-in, then 200 on sign-in (user created), then 200 again after logout and a second sign-in; `/budgets` and `/tags/default_tags` 200 both times.
- Kinde profile fields (names only): email, email_verified, family_name, given_name, id, name, picture, preferred_username, sub, updated_at. `email_verified` is present, as SR-1 (safe account linking) requires.
- Temporary `[auth] kinde profile fields` log line removed (it was never committed). Server: 221 tests pass.
- Client committed on `feature/client-auth` as `2413a2c` (TS0, C0, logout, stale data, `/me`, CT0 start). Not pushed.
- Decision: `DELETE /api/v1/users/:id` stays as is until there's a delete-account screen (it would fail for a user with transactions).

### T1 committed; I1 (CSV parser) — done, uncommitted (2026-11-24)

- T1 (transactions tables) committed on `bb-server` `feature/auth` as `eae5d14`. No ownership-matrix rows yet: T1 has no endpoints; they come with I2 (import endpoint).
- **I1:** `app/services/csv_import/parser.rb` (`CsvImport::Parser`), pure parsing for the §2.4 format; normalization and occurrence numbering are left to I2.
  - Row error codes: `missing_date`, `bad_date`, `missing_description`, `description_too_long`, `missing_amount`, `bad_amount`, `amount_too_large`, `transaction_id_too_long`. Warning: `zero_amount` (row skipped). One code per row, first problem found.
  - Amounts: optional sign, `$`, valid thousands groups, `(12.34)` = −12.34, ≤ 2 decimals, magnitude ≤ 9,999,999,999.99 (fits decimal(12,2)). Unreadable optional `balance` is dropped, not an error.
  - Dates are strict to the spec: `YYYY-MM-DD` or `MM/DD/YYYY` with two-digit month and day; real calendar dates only.
  - Fully blank lines are skipped. Line numbers are CSV record numbers (header = 1).
  - Template `public/csv-templates/generic.csv` (synthetic rows), tested to parse cleanly.
- **Tests:** `test/services/csv_import/parser_test.rb` (25), covering the plan's I1 list plus leap days, limits, encoding, unclosed quotes and "errors never contain row text". Full suite **246 pass**. Mutation checks caught: BOM handling, line numbering, sign + parentheses rule.
- **Note:** Ruby 3.3 ships `csv`; moving to Ruby 3.4 will need `gem "csv"` in the Gemfile.

### I1 (CSV parser): month-first dates without leading zeros (2026-11-24)

- Product owner's change to PO-18 (generic CSV format): dates may be `M/D/YYYY` as well as `YYYY-MM-DD` and `MM/DD/YYYY`. Two-digit years and day-first dates are still row errors.
- Tests: valid 2/3/2026, 12/31/2026, 2/29/2028 (plus 02/03/2026, 2/03/2026); invalid 2/30/2026, 2/3/26, 13/1/2026 (plus 31/12/2026, 2/3/026, 002/3/2026, 2026-2-3). Parser tests: 27. Mutation check (two-digit only) caught.
- Recorded in `docs/IMPLEMENTATION_PLAN.md` §2.4 and in the new user-facing `bb-server/public/csv-templates/generic-notes.txt` (format notes + change log).

### I1 committed; I2 (import endpoint) — done, uncommitted (2026-11-24)

- I1 (CSV parser) committed as `f9ac479` (with the M/D/YYYY change).
- **T1 fix found while building I2:** rows with a bank `transaction_id` used a content-based `base_key`, so a *different* bank id with the same date, amount and description in a later file would have been dropped as a duplicate. Now `Transaction.duplicate_key_for` keys those rows on the id (SHA-256 of `external_id|<id>`, occurrence 1), as §2.3 says. Normalized descriptions are also capped at 255 characters (upper-casing can lengthen text). No migration; T1 model tests +2.
- **Endpoints:** `POST /accounts/:account_id/imports`, `GET /transactions`, `PATCH /transactions/:id` (category only), `DELETE /transactions/:id`; `data_through` on accounts. See `ARCHITECTURE.md`.
- **Choices to review:**
  - Rejected files (wrong type, too large, missing headers…) return 422 and store **no** `imports` row; `status: failed` is unused for now.
  - `row_errors` stores errors only; zero-amount warnings are returned in the response (`warnings`, `skipped_count`) but not stored.
  - `data_from`/`data_through` on an import cover all valid rows in the file, duplicates included.
  - `DELETE /transactions/:id` is a hard delete; importing the same file again brings the row back.
  - PATCH and DELETE on transactions in an archived account → 422 (archived accounts are read-only, DM-2).
  - Clearing a category (`category: null`) sets source `none` and `needs_review: false`.
  - Known limit: a file with `transaction_id` and a later file of the same rows without it are not matched to each other.
- **Ownership-matrix rows (5):** import into other's account → 404; list other's account → 404; update / delete other's transaction → 404; unknown category on own transaction → 422. The snapshot now includes `imports` and `transactions`; the index test checks `/transactions` lists only the caller's; the not-provisioned 403 check covers `/transactions`.
- **Tests:** `imports_controller_test.rb` (15, including same file again, rearranged, overlapping, two accounts, bank ids, 10,000 rows in **1.8 s**), `transactions_controller_test.rb` (10), 5 matrix rows, fixtures `transactions.yml`. Full suite **280 pass**. Mutation checks caught: occurrence numbering, account scoping on import, transaction scoping.
- `users_controller_test` "destroy" now deletes the fixture transaction first: deleting a user with transactions still fails (500), per the decision to wait for a delete-account screen.

### I2 approved with two additions (2026-11-24)

- Product owner accepted I2 (import endpoint) decisions 1–4 as described: no import row for rejected files; zero-amount warnings not stored; DELETE is a hard delete; archived accounts' transactions are read-only.
- **(a) `DELETE /users/:id`** now returns **409** `{error: "user_has_data", message}` and deletes nothing when the user's accounts hold imports or transactions (it was a 500). Test: `users_controller_test` "destroy is 409 and deletes nothing…" (counts of users, budgets, accounts, profiles, imports, transactions unchanged).
  - **Known debt:** a user with imported data can't delete their account until a delete-account flow is designed.
- **(b) Delete rule recorded** in the plan's TR1 (transfer matching) and G1 (goals) rows and beside `TransactionsController#destroy`: deleting a transaction that's in a transfer link or linked from a goal contribution → 422, nothing deleted; tests land with TR1 / G1.

### I2 committed; AI1 (rules-based categorization) — done, uncommitted (2026-11-24)

- I2 (import endpoint) committed as `1be4c0b`, with the users#destroy 409 and the recorded delete rule.
- **AI1:**
  - Migration `20261124190000_create_merchant_rules.rb` (additive; rollback tested). `MerchantRule` model; `User has_many :merchant_rules`. The table is read by AI1 and will be written by AI3 (learning from corrections).
  - `Categorization::MerchantKey`, `Categorization::KeywordRules`, `Categorization::DisabledAi`, `Categorization::Pipeline` (see `ARCHITECTURE.md`). The importer runs the pipeline after the import is saved; the response adds `categorized` counts.
  - The AI interface AI2 must implement: `categorize(items:, allowed_slugs:)` with items `{index, merchant, amount}` only (no account or user data), returning `{index, category_slug, confidence}`. The pipeline already validates answers (active slug, never Transfers, confidence 0.6–1, index in range).
- **Choices to review:**
  - Rules set `confidence` to null (it's only meaningful for AI answers).
  - Income rules match only money in; debt-payment rules only money out (a payment received on a card isn't spending); other rules match both, so refunds land in the same category and net.
  - Transfers, Zelle/Venmo-style person payments and Amazon are deliberately not in the rules: they go to review.
  - Clearing a category with PATCH leaves the row at `none` and doesn't re-run the pipeline.
- **Tests:** `pipeline_test.rb` (11), `keyword_rules_test.rb` (6, including "every rule points at a seeded MVP category, never Transfers"), plus an import → categorization request test. Full suite **299 pass**. Mutation checks caught: AI receiving already-placed rows, memory skipped, sign rules removed. 10,000-row import including categorization: 1.9 s locally.

### AI1 approved (2026-11-24)

- Decisions accepted: (1) no confidence on rule/memory matches; (2) transfers, P2P (Zelle/Venmo) and Amazon skip the rules, and with AI2 (Claude categorization) go to Claude first, reaching review only below 0.6 confidence; recorded in the plan's AI2 row together with sending each account's `purpose`; (3) clearing a category doesn't re-run categorization.
- **Fix for (3):** clearing a category set `needs_review: false`; it now sets **`true`**, so the row returns to the review queue. Test updated (`transactions_controller_test`).
- The AI step's items now include `account_purpose` (no account names or ids). Test: transfer-like, Zelle, Amazon and a side-income Venmo inflow all reach the AI step with their purposes.
- Full suite **300 pass**.

### AI1 committed; AI3 (learning from corrections) — done, uncommitted (2026-11-24)

- AI1 (rules-based categorization) committed as `a784301` (including the needs-review-on-clear fix and `account_purpose`).
- **AI3:** `TransactionsController#update` → `remember_merchant!`: upserts `(user, merchant_key) → category` atomically, in the same database transaction as the category change. Same category again keeps the hit count; a different category replaces the rule and restarts `hits` at 0.
- **Choices to review:**
  - Clearing a category leaves memory as it is, so the merchant's next import still uses the old rule.
  - Learning doesn't re-categorize other existing rows of the same merchant (e.g. others waiting in review); only future imports use it.
- **Tests:** `merchant_memory_test.rb` (6): the rule is saved; **the next import of that merchant uses memory and the AI step is called only for the other row**; replace vs keep; clearing doesn't teach; Transfers / unknown slug / another user's transaction teach nothing; memory is per user. The ownership-matrix snapshot now includes `merchant_rules`. Full suite **306 pass**. Mutation check (no memory write) caught.

### AI3: two changes from the product owner (2026-11-24)

- **(1) Forgetting wrong memory:** clearing a category on a row whose `categorization_source` is `memory` deletes the caller's merchant rule for that merchant, in the same database transaction. Clearing rows from rules, AI or the user leaves memory alone. Another user's rule for the same merchant is never touched.
- **(2) Applying a correction to waiting rows:** a correction also updates the caller's other rows from the same merchant that have `needs_review = true`, weren't chosen by the user, and are in active (not archived) accounts. They get the category with source `memory` in the same database transaction. PATCH returns `also_updated: N`.
- **Transaction date is not sent to Claude** (data minimization, D-008): the AI2 (Claude categorization) row now says merchant key, amount and account purpose only. AI1 already sends no date.
- **Tests:** `merchant_memory_test.rb` now 12, covering the forget rule, the other sources, other users, waiting rows vs user choices / not-waiting / other merchant / other user / archived account, `also_updated: 0`, and all-or-nothing on failure. Mutation checks caught: user-choice guard, memory-only forget, archived-account guard. Full suite **312 pass** (three repeat runs, 4 s each). One earlier full run hung and was stopped; it didn't recur, most likely a leftover test process from the run before.

### AI3 committed; DEMO-G (demo data generator) — done, uncommitted (2026-11-24)

- AI3 (learning from corrections) committed as `6c96f1c`.
- **DEMO-G:** `lib/demo/generator.rb`, `lib/demo/seeder.rb`, `lib/tasks/demo.rake` (see `ARCHITECTURE.md`, commands in `CLAUDE.md`).
  - Persona: invented employer (Northwind Labs), invented landlord and local businesses, people as initials + invented surnames. Chain names (Whole Foods, Shell, Netflix…) appear only as merchants so AI1's rules have realistic input.
  - Accounts: Everyday Checking (spending), Rainy Day Savings (savings), Venmo (p2p, side_income).
  - 54 transfer pairs (checking ↔ savings, Venmo cash-outs; 0–2 day gap) and 8 decoys (same amount within 3 days, not transfers), exposed as `transfer_pairs` / `decoy_pairs`.
  - Golden set: 300 rows, every one of the 19 active categories, 44 noisy variants (lower case, `POS PURCHASE`, extra spaces + numbers, card digits). Transfers are labelled `transfers`; EV1 decides how to score them, since categorization never assigns Transfers.
- **Not yet testable:** "demo import produces the expected transfer suggestions" needs TR1 (transfer matching). The pairs and decoys are in place for that test.
- **Tests:** `test/lib/demo/generator_test.rb` (9: byte-identical, seed changes output, write to disk, parsing, date range, pair and decoy shapes, golden coverage, no real personal data) and `seeder_test.rb` (3: imports via the pipeline, re-run inserts nothing, expected rule categories). Full suite **324 pass**.
- **Development database:** ran `bin/rails db:seed` (idempotent, categories by slug) and `bin/rails demo:seed` for the demo user (#2): 1,082 rows inserted; overlap 76 duplicates; malformed 2 inserted, 3 row errors; 826 categorized by rules, 256 waiting for review (mostly Venmo and transfers, for AI2/TR1). To see it on the phone: `bin/rails demo:seed USER_EMAIL=<your Kinde email>`.

### DEMO-G committed; AI-0 (Claude connection) and S4-min (rate limit and AI cost cap) — done, uncommitted (2026-11-24)

- DEMO-G (demo data generator) committed as `91bc30e`.
- **AI-0:**
  - Gem `anthropic ~> 2.14` (2.14.0 is current; the plan said 2.12). SDK usage checked against the installed gem's source (`OutputConfig#format_`, `JSONOutputFormat`, `Usage`, `Anthropic::Errors::*`); the SDK itself doesn't log.
  - `app/services/anthropic_client.rb`, `script/anthropic_smoke.rb`. `.env`: added `ANTHROPIC_CATEGORIZATION_MODEL` / `ANTHROPIC_ASSISTANT_MODEL=claude-haiku-5-5`; `.env.example`: those two uncommented, key left empty.
  - **Smoke call (2026-11-24, one request):** model `claude-haiku-5-5`, **458 input + 59 output tokens**, 2.7 s, answer matched the schema. ≈ $0.00008 at $0.10 / $0.50 per MTok.
  - `dotenv` loads `.env` in tests too, so the real key is visible there; `AnthropicClient` refuses to build a real client in the test environment. WebMock isn't installed yet (CI1 can add it).
  - Tests: `anthropic_client_test.rb` (7): parsed result and token counts, request shape (model from env, structured output, low effort), defaults, the log line contains no key/prompt/answer, API errors log only class + status, refusal/truncation/non-JSON → typed errors, no real client in tests.
- **S4-min:**
  - Migration `20261124200000_create_ai_usage.rb` (additive; rollback tested). `AiUsage`, `AiBudget`, `AiRateLimit`, `config/initializers/rack_attack.rb`, `POST /api/v1/transactions/categorize`. Gem `rack-attack ~> 6.8`.
  - **Design change from the plan:** the per-user categorize limit is in the controller, after authentication, not in Rack::Attack, which runs before the token is verified and would trust an unverified user id. Rack::Attack keeps the per-IP limit.
  - The cap is enforced inside `AnthropicClient`: a metered call must name the user, `AiBudget.check!` runs before the request and `record!` after it (refusals count too).
  - Known limits: soft cap (concurrent requests can overshoot by one request); in-process memory stores (one server); UTC days.
  - Tests: `ai_budget_test.rb` (7) and `ai_limits_test.rb` (6): usage rows add up; over the cap → `Exceeded` and **the fake client gets no call**; per-user cap; yesterday doesn't count; refusals count; 21st categorize in an hour → 429 JSON with `Retry-After`, other users unaffected; cap reached → 429 `ai_daily_cap_reached` and no AI call; under the cap → one call, usage recorded; cap hit during an import → import succeeds, rules still apply, rest to review; per-IP throttle → 429 JSON, `/up` not throttled.
  - Mutation checks caught: cap check removed, per-user limit removed, AI-failure fallback removed.
- Full suite **344 pass**, 3 runs in a row (5–7 s), no hang. One run looked like a hang but was a syntax error in a new test hidden by my output filter.

### AI-0 and S4-min committed; new build order (2026-11-24)

- AI-0 (Claude connection) committed as `0f2ec38`; S4-min (rate limit and AI cost cap) as `78f73e0`. Split into two commits as asked: the AI-0 commit has the wrapper without the cap (tests pass at that commit), S4-min adds it.
- **New order (product owner, so the phone can be tested soon):** AI2 (Claude categorization) → UP1 (Expo upgrade, capped at one working day, including rebuilding and installing the dev app on the iPhone) → LG1 (new tab layout) → C2 (accounts and import screens; designs come from the Claude Project before C2 starts) → **phone test with demo data** → TR1 (transfer matching) → C2b (review and transfer screens).
- iOS platform check: iOS 18.5 SDK and the iOS 18.6 runtime are installed (Ready); no download needed. 18 GB free.

### AI2 (Claude categorization) — done, uncommitted (2026-11-24)

- `app/services/categorization/claude_categorizer.rb`; pipeline AI step rewritten (batches, per-run limit, resume); migration `20261124210000_add_ai_attempted_at_to_transactions.rb` (nullable column + partial index, no backfill; rollback tested). Details in `ARCHITECTURE.md`.
- **Why the new column:** the plan needs "a 429 loses no data and the next call resumes" and `{processed, remaining}`. Without a marker, a row Claude was unsure about and a row Claude never saw look the same, so unsure rows would be re-sent on every call. `ai_attempted_at` is set when Claude answered (refusal / cut-off included) or the user cleared the row; it stays nil when the call failed (429, network, daily cap).
- Structured outputs don't support `minimum`/`maximum`/array limits, and the Ruby SDK doesn't strip them, so the schema uses only `enum` and types; the pipeline checks index range and confidence.
- **Tests:** `claude_categorizer_test.rb` (11, real `ClaudeCategorizer` + `AnthropicClient` with a fake SDK): request carries only the four fields and no date, allowlist without Transfers, data-not-instructions in the prompt; confident → `ai` + usage recorded; invented slug discarded → review, not re-sent; low confidence → review, not re-sent; refusal and cut-off → review; **429 on batch 2 of 2: batch 1 kept, the next call sends only the 10 unanswered rows**; ≤ 100 rows per run in batches of 50; **injection descriptions only reach an allowed category or review**; P2P / Amazon / transfer-like rows reach Claude with account purpose (side-income inflow → Income); over the cap → no request, rows wait; cleared rows never sent. Mutation checks caught: failed batch marked as answered, per-run limit removed, allowlist check removed. Full suite **355 pass**.
- **Manual run against the real API (demo user, development database):** 3 pipeline runs, 6 Claude calls (`claude-haiku-5-5`), **21,203 input + 6,949 output tokens (≈ $0.006)**, 1.5–6.5 s per call. Of 256 rows waiting: 152 categorized by Claude (confidence min 0.60, avg 0.84), 104 to review.
  - Checked against the generator's labels: **107 of 107 non-transfer rows correct**; all 45 mismatches were own-account transfers filed as "other". Claude can't choose Transfers, and "other" counts as spending, so this would have inflated Left to spend.
  - **Prompt fix:** money moved between the person's own accounts → confidence 0.2 → review (for TR1). Re-asking Claude about those 45 rows (no database writes, 1 call, 3,610 + 1,099 tokens): **0 of 45** would now be saved; max confidence 0.2.
  - The 45 rows already saved as "other" in the development demo data are unchanged. Re-seeding the demo user would clear them (needs approval: it deletes that user's demo rows).
- Total real-API spend today: smoke 517 tokens + demo run 28,152 + re-ask 4,709 ≈ **$0.007**.

### AI2: deterministic transfer pre-check (2026-11-25)

- **PO decision:** transfer-like rows never reach Claude. `Categorization::TransferCheck` (after merchant memory, before keyword rules and Claude): `TRANSFER TO/FROM`, `CASH OUT`/`CASHOUT`, or the whole-word name (4+ characters) of another of the user's own accounts → `needs_review = true`, source `none`, `ai_attempted_at` set (so they don't count as `remaining` and are never queued). The low-confidence prompt instruction stays as a backup. Supersedes the 2026-11-24 "transfer-like rows go to Claude first" note in the plan's AI2 row; Zelle/Venmo payments and Amazon still go to Claude.
- Merchant memory still wins (a user's own teaching). Another user's account names are never used.
- **EV1 (categorization eval):** the plan now asks for a separate critical-error count, "transfer filed as spending/income".
- **Tests:** `transfer_check_test.rb` (3), pipeline (+3, and the superseded test rewritten), `claude_categorizer_test.rb` (+1: transfer-like rows are never sent to the fake Claude client, now or on later runs). Full suite **362 pass**. Mutation checks caught: pre-check removed; the row's own account name treated as "another account".
- **Undo on Review (question):** small server change (~1–2 h with tests): PATCH also returns `also_updated_ids`, and `POST /transactions/:id/undo_correction` restores, in one database transaction, the picked row, only those `also_updated` rows that still carry what the correction set, and the merchant rule's previous state. Recommended over dropping Undo, since the spec's acceptance check requires it. Planned with C2b unless the PO wants it earlier.

### Demo reset done; UP1 (Expo upgrade) started — target SDK 54 (2026-11-25)

- **Demo reset/re-seed (PO-approved):** `Demo::Reset` + `bin/rails demo:reset` (refuses outside development; only `demo.user@example.com`; deletes that user's transactions, imports and merchant rules; keeps user, accounts, profile and AI usage). Tests: `test/lib/demo/reset_test.rb` (3). Ran it: deleted 1,082 transactions / 5 imports, re-seeded through the real pipeline (Claude on), one extra categorize run.
  - **Needs review: 144** = 108 transfers (waiting for TR1), 28 "other" (Amazon/Target, Claude unsure), 8 income (the decoy "concert tickets" repayments).
  - **Critical errors (transfer filed as spending/income): 0.** Categorized rows matching the generator label: 936/936 (the 2 extra rows are from `malformed.csv`, which has no labels).
  - AI usage for the demo user today (UTC 2026-11-25, includes yesterday evening's runs): 11 requests, 38,668 input + 12,985 output tokens (≈ $0.01). Not committed yet.
- **UP1 target: SDK 54 (PO decision).** Expo SDK 58 is current, but SDK 55+ needs Xcode 26.2+ (56–58: 26.4+, iOS 16.4+); SDK 54 needs Xcode 16.1+ and works with the installed Xcode 16.4. SDK 55–58 and the Xcode upgrade move to v1.
- **Branch `chore/expo-sdk-54`** (from `feature/client-auth` @ `2413a2c`).
- **Step 1, SDK 51 → 52:** `expo@~52.0.0`, React Native 0.76.9, React 18.3.1, Expo Router 4, React Navigation 7, Reanimated 3.16, Screens 4.4, `jest-expo` 52.
  - **Kinde SDK 1.3.1 bundles its own old Expo native modules** (`expo-web-browser@12.8.2`, `expo-constants@14`, `expo-modules-core@1.12`, `expo-secure-store@12`), which would put two copies of Expo's native core in the app. Fixed with npm `overrides` so Kinde uses the app's SDK-matched copies (one copy of each, checked with `npm ls`); a stale nested lockfile entry was removed.
  - Kinde 2.x (`2.3.1`, Aug 2026) drops those dependencies (uses `react-native-app-auth`) and keeps the same methods, but `audience` moves from the constructor to login. Switching is an auth change needing a KA (Kinde audience check) re-run on the phone: **evaluated, not switched**; decision deferred to the end of UP1.
  - `expo-doctor` (with `RBENV_VERSION=3.4.13` for CocoaPods): 17/18; the remaining item is React Native Directory metadata (unmaintained `react-native-modal-datetime-picker`, no listing for Kinde, `@heroicons/react`, `dotenv`).
  - `tsc:check`: 52 errors (baseline 99). Jest: 11/11.
  - Native: `expo prebuild --clean` + `pod install` OK (old architecture: `newArchEnabled: false`). Device compile running.
- Step 1 native compile (unsigned, generic iOS device): **BUILD SUCCEEDED** on SDK 52. (`prebuild --clean` regenerates the Xcode project and drops the signing team; it's re-selected in Xcode before installing.)
- **Step 2, SDK 52 → 53:** React 19.0.0, React Native 0.79.6, Expo Router 5.1, `jest-expo` 53, `react-native-web` 0.20.
  - npm couldn't upgrade React 18 → 19 in place: the old `jest-expo` 52 carried an RC `react-server-dom-webpack`, and Expo Router 5's optional peer of that package resolved to a release needing React 19.2. Fix: removed the old `jest-expo` from the tree, set the SDK 53 dev versions, and ran `npm install --legacy-peer-deps` **once**; a plain `npm install` works afterwards (no flag kept in the project).
  - Kinde workaround holds: overrides updated to SDK 53's `expo-modules-core 2.5.0` / `expo-secure-store ~14.2.4`; one copy each of `expo-constants 17.1.8`, `expo-web-browser 14.2.0`, `expo-modules-core 2.5.0`, `expo-secure-store 14.2.4`.
  - Remaining peer mismatches: only Storybook 7 (supports React ≤ 18). The Budget tab imports `.storybook`, so it's in the app bundle; judged at runtime.
  - `expo-doctor` 17/18 (same directory-metadata item). **TypeScript: 52** (no increase). Jest 11/11.
  - Native: New Architecture now on by default (SDK 53). Prebuild + `pod install` OK (92 pods). Device compile running.
- Step 2 native compile (unsigned, New Architecture on): **BUILD SUCCEEDED** on SDK 53. Kinde 1.3.1's native modules compile on the New Architecture, so the "New Architecture off" fallback wasn't needed and auth is unchanged. (Xcode had the old workspace open during `prebuild --clean` and showed "workspace has disappeared"; closed without saving, nothing affected.)
- **Step 3, SDK 53 → 54:** React 19.1.0, React Native 0.81.5, Expo Router 6, Reanimated 4.1 (+ `react-native-worklets` 0.5.1; Reanimated 4 runs only on the New Architecture), `jest-expo` 54, `react-native-web` 0.21.
  - Same React-jump conflict as step 2, same fix (`--legacy-peer-deps` once; plain `npm install` works afterwards).
  - Kinde overrides updated to `expo-modules-core 3.0.30` / `expo-secure-store ~15.0.8`; one copy each of `expo-constants 18.0.14`, `expo-web-browser 15.0.11`, `expo-modules-core 3.0.30`, `expo-secure-store 15.0.8`.
  - `babel-preset-expo` is no longer hoisted, so it's now a direct dependency (Jest couldn't load the Babel config without it).
  - **Storybook removed (PO rule: remove if it causes trouble):** Storybook 7 brought a second `react-dom` (18.3.1), flagged by `expo-doctor` as a duplicate. Removed `.storybook/`, the two `*.stories.tsx`, five `@storybook/*` packages, `babel-loader` (Storybook web only), the `storybook*` scripts, the Metro `sbmodern` tweak, the `extra.storybookEnabled` app-config flag, and the import/switch in the Budget tab (`app/(tabs)/index.tsx` now always exports `HomeScreen`).
  - **NativeWind 2 → 4.2.7** with Tailwind 3.4.19: Babel preset `jsxImportSource: "nativewind"` + `nativewind/babel`, `withNativeWind` in Metro, `global.css` imported by `app/_layout.tsx`, `nativewind/preset` in `tailwind.config.js`, `nativewind-env.d.ts`. `styled()` no longer exists: `components/ThemedText.tsx` uses `Text` directly (same behaviour; callers' `className` still overrides the type classes). 12 files use `className`; they're re-checked on the phone.
  - **Zustand on Hermes:** since SDK 53 Metro resolves package `exports`, picking Zustand's ESM build, which uses `import.meta` (unsupported by Hermes). Fixed with `babel-preset-expo`'s `unstable_transformImportMeta: true`. Found by building the iOS JS bundle (`expo export`), before the native build.
  - `expo-doctor` **18/18** (first fully clean run). **TypeScript: 48** (52 → 48: the removed story files). Jest 11/11. iOS JS bundle: 1,803 modules. Prebuild + `pod install` OK (94 pods). Device compile running.
- Step 3 native compile (unsigned, New Architecture on): **BUILD SUCCEEDED** on SDK 54. **UP1 finished within the one-day cap.** TypeScript baseline locked at **48 errors in 12 files** (`tsc-baseline.json --update`). Lockfile checkpoints were kept for SDK 52, 53 and 54.
- Remaining for UP1: re-select the signing team in Xcode (`prebuild --clean` clears it), install on the iPhone, and the PO's phone test (login; KA check that `iss`/`aud` are unchanged; legacy screens and `className` styling render). Not committed yet: branch `chore/expo-sdk-54`.
- **Phone test (2026-11-25), SDK 54 development build on the iPhone:** installs and launches (New Architecture on); sign in → `/me` 200, logout → sign in → `/me` 200 each time (Kinde `iss`/`aud` unchanged; shared-module workaround works at runtime); NativeWind 4 styling renders.
  - **Budget tab fix:** content was clipped at the bottom of the fixed 150-pt gradient (the old architecture drew `overflow: "visible"` content outside it; the New Architecture clips). Gradient now uses `minHeight: 150`. Confirmed on the phone: full card and both buttons visible.
  - **`components/ExternalLink.tsx`:** Expo Router 6 regenerated typed routes on `expo start`, which broke the starter component's `href: string`; typed as `Href & string` (the current Expo template's fix). TypeScript back to 48.
  - **Categories tab** (`app/(tabs)/explore.tsx`) still shows Expo's starter "Explore" page, unchanged on this branch and unstyled (no scroll view or safe area); not a regression. Left for LG1 (new tab layout), which replaces it.
- **UP1 done** within the one-day cap: SDK 51 → 54 committed on `bb-client` `chore/expo-sdk-54` (see below).

### UP1 committed; LG1 (new tab layout) — done, uncommitted (2026-11-25)

- UP1 (Expo upgrade) committed on `bb-client` `chore/expo-sdk-54` as `7cc9083` (PO approved after the phone test).
- **LG1:** four tabs Home / Plan / Activity / Coach with Forest Floor placeholders; Activity is a stack ready for C2. Brand tokens in `constants/Theme.ts`; new font packages `@expo-google-fonts/bricolage-grotesque` and `@expo-google-fonts/inter` (named in the plan's brand rule, D-020). Details in `ARCHITECTURE.md`.
  - **Legacy UI frozen, not deleted:** Expo Router turns every file under `app/` into a route, so the old Budget/Categories tabs, `category/` stack and `new-budget` screen were moved unchanged (`git mv`) to `legacy/app/` (with `legacy/README.md`). The TypeScript baseline entries were renamed to the new paths with the same counts.
  - The login check and `GET /me` moved from the legacy Budget tab/Header into the tab layout (`useSessionBootstrap`), so `/me` still runs at startup and after login whichever tab shows. Log out is on Home for now.
  - Regenerated typed routes flagged 4 legacy links to removed routes (`/category…`, `/new-budget`); cast to `Href` with a note, so TypeScript stays at **48** (no new errors).
  - Navigation now uses a light Forest Floor theme (Birch background); the spec defines no dark theme.
  - **Tests:** `app/__tests__/routes.test.ts` (2: routes are exactly the four tabs + Activity stack + login + system files; legacy files kept outside `app/`), `hooks/__tests__/useSession.test.tsx` (2: signed-out → `/login` without `/me`; signed-in → `/me`). Client suite 15/15. Mutation checks caught: `/me` call removed; a legacy route file back under `app/`.
  - iOS JS bundle builds (1,564 modules). No native changes: Metro reload is enough on the phone.

### LG1 committed; C2 (accounts and import screens) — built, uncommitted (2026-11-25)

- LG1 (new tab layout) committed as `6868ae8`.
- **Server additions for C2** (`bb-server` `feature/auth`, uncommitted): accounts JSON adds `transaction_count` (one grouped query with `data_through`); `GET /transactions?import_id=` scoped through `current_user.imports` (another user's import → 404; new ownership-matrix row; `test/fixtures/imports.yml`). The user-delete test also removes the new fixture import (the known 409 rule). Server suite **367 pass**; mutation (unscoped import filter) caught.
- **Client** (`bb-client` `chore/expo-sdk-54`): screens and helpers listed in `ARCHITECTURE.md`. New native dependency `expo-document-picker ~14.0.8` (named in the plan): linked with `pod install` only, so the signing team is kept; **the phone needs one rebuild from Xcode**.
  - Links use Expo Router typed routes (no casts), so TypeScript checks every Activity link.
  - Tests: `utils/__tests__/format.test.ts` (money with true minus and no float maths, dates, freshness, earliest data-through, plurals, file/row error messages that never show row text, `categorizeUntilDone` incl. stopping quietly on 429 and a bounded loop, template URL, import result figures, grouping by day); routes test updated. Client suite **34/34**. TypeScript **48** (no increase). iOS JS bundle builds (1,576 modules).
- **Gap for C2b, needs a decision:** the spec shows a *suggested* category with "?" on rows waiting for review (Activity list and Review chips). The server doesn't keep Claude's low-confidence guess (answers below 0.6 are discarded, AI2), so C2 shows a "Needs review" chip. C2b's Review screen needs the suggestion: proposal = an additive nullable `transactions.suggested_category_id`, set from Claude's below-threshold answer (never Transfers), cleared when a category is chosen.
- **Not built (spec is silent, plan mentions "add/edit"):** editing an account. Proposed for C2b or later.

### PO decisions on C2 gaps; design comparison (2026-11-25)

- **(1) `suggested_category_id` comes with C2b (review and transfer screens):** shown as the first "?" chip on Review (and as "Category?" in the Activity list); the row stays in review until the user confirms.
- **(2) Account editing comes after C2b**, limited to name and purpose.
- New product docs: `docs/product/SCREENS_WELCOME.md` (C9 welcome and account screens, DRAFT, **don't build yet**), reference screenshots in `docs/product/screens/`, brand assets in `bb-client/assets/brand/` (`mascot.svg`, `welcome-hero.svg`) and `assets/images/app-icon-1024.png`.
- C2 compared with `docs/product/screens/Activity*.png`; differences being fixed: Import icon, weekday dates, number tiles for "to review" (and transfers after TR1), day headers, chip borders; Accounts back link + large title + intro, top-right freshness chip, inline outlined Import CSV, dashed Add account, centred footer; Add account Cancel + centred title, helper texts, "Save without importing" as a link; Import as one card, upload on file choice, 2×2 result tiles with thousands separators and full dates; tab bar icons.
- **C2 restyled to the screenshots:** new tokens `line`, `tile`, `dayHeader` in `constants/Theme.ts`; `components/brand/ui.tsx` adds outlined small buttons, Chestnut underlined links, `ScreenHeader` ("‹ Activity" + large title + intro), `FormHeader` (Cancel + centred title), `NumberTile`, large selectable chips. Import uploads as soon as a file is chosen (the design has no Import button). Dates: "Sat, Nov 21" (summary, day headers), "Dec 1, 2024" (import range); counts with thousands separators. Tab icons match the design. Client tests 35/35, TypeScript 48, bundle builds.
- Not in C2 by design: the "transfers to confirm" tile (TR1) and "Category?" suggestion chips (C2b, `suggested_category_id`).
- **PO change (2026-11-25), Import:** choosing a file no longer uploads it (imports can't be undone in the MVP, so a wrong-account pick couldn't be fixed). After a file is chosen, the account + file card shows "Change" on both rows and a full-width Pine **Import** button below it; the upload starts only on that tap. Changing the account or file after a result returns to the choose step. Client tests 35/35, TypeScript 48.
- **Phone test finding (2026-11-25): Activity empty state was a dead end.** The "Add your first account" button rendered with no Pine background (white text on a white card, invisible). Most likely cause: `Pressable` with a `style` *function* under NativeWind 4's JSX wrapper on device (Jest keeps the style, so it couldn't be proven locally). Fix: `PressableBox` in `components/brand/ui.tsx` (static style, its own pressed state); used by `Button`, the dashed Add account and Home's Log out; no style functions remain.
  - Empty state now keeps the header (title, **Import**, "0 accounts" + **Accounts** link); the card has a full-width Pine **Add your first account** and a Chestnut **Download the CSV template** link. **Import with no accounts opens Add account first** (header button, and the Import screen redirects if reached with no accounts); "Save and import CSV" continues to Import.
  - Test `__tests__/activityEmptyState.test.tsx` (2): the button renders with a Pine background, Import/Accounts/template present, both buttons open Add account.
  - **Found while adding it: test files under `app/` become Expo Router routes** (the LG1 routes test had produced a `/__tests__/routes.test` route). Both tests moved to top-level `__tests__/`; the routes test now asserts no test files under `app/`.
  - `expo-asset` added as a direct dependency (`expo-font` needs it resolvable in Jest; already linked natively via `expo`, no rebuild). Client tests **37/37**, TypeScript **48**, bundle builds.

### C2 committed; CI1 (GitHub Actions CI) — built, uncommitted (2026-11-25)

- C2 (accounts and import screens) committed: server `f096f8a` (`feature/auth`), client `1cb736a` (`chore/expo-sdk-54`). PO pushed both branches.
- **TR1 (transfer matching) paused for CI1 (PO):** work in progress (migration `20261125100000_create_transfer_links.rb`, `TransferLink`, `TransferMatcher`, import hook, `Demo::Reset` deleting links; 367 tests passing) rolled back in the dev database and stashed on `feature/auth` (`stash@{0}`: "TR1 (transfer matching) work in progress, paused for CI1"). It moves to a new branch from `main` after the PO merges.
- **CI1:** `bb-server/.github/workflows/ci.yml`, `bb-client/.github/workflows/ci.yml` (see `ARCHITECTURE.md`).
- **Clean-machine checks** (fresh `git worktree` of each committed branch: no `.env`, `node_modules`, `.expo/` or `expo-env.d.ts`):
  - Server: `bundle install`, `db:test:prepare`, full suite. **One problem found:** the I2 test "10,000 rows import in under 5 seconds" failed once in the full parallel run (alone it takes ~3.0 s; earlier 1.9 s before AI2's pre-check). Parallel test workers share the CPU, and CI runners are slower, so it would make CI flaky. The test now always checks that all 10,000 rows import; the 5-second limit is enforced with `PERF=1` (plan wording: "< 5 s locally"). With `PERF=1`: 3.0 s.
  - Client: `npm ci` (no `--legacy-peer-deps` needed), `tsc:check` **48** (same without the git-ignored `.expo/types` and `expo-env.d.ts`), `test:ci` **37/37**.
  - Server suite in the repo: **367 pass**.
- Notes for the PRs: the server PR to `main` also carries the earlier Copilot backend checkpoint commits (`f884c35`, `e89066f`, `0e7f1df`), which were never on `main`. `chore/expo-sdk-54` had no upstream set locally.
- **CI1 committed:** server `e0d6058` (workflow + opt-in timing), `d6ea619` (GitGuardian flagged the throwaway CI Postgres password: now no credential at all, `POSTGRES_HOST_AUTH_METHOD: trust`), `c026592` (runner pinned to `ubuntu-24.04`: Ubuntu 26.04 only has Ruby 3.3.14, Gemfile requires 3.3.0; Ruby upgrade added to the plan's v1 list); client `5fbc6d0`.
- **GitGuardian incident 41125160:** false positive (throwaway CI database value in `e0d6058`); PO to mark it ignored/false positive in GitGuardian. History not rewritten.
- **EAS "Publish Preview Update" check on the client PR:** not CI1. The project has no EAS Update setup; its log showed Kinde's nested `expo-constants` 14 (`uuidv4 is not a function`), i.e. EAS installed without npm `overrides`. A clean `npm ci` of the branch has no nested copy. PO is switching "Updates" off in the Expo project's GitHub settings. Rule recorded: install the client with npm only.

### CI1 merged; TR1 (transfer matching) — done, uncommitted (2026-11-25)

- PO merged both PRs to `main` (server `d79872e`, client `4acbc67`), with CI green; pulled locally. EAS "Updates" switched off in the Expo project (it isn't part of CI1); GitGuardian alert marked by the PO.
- **TR1** on new branch `bb-server` `feature/transfer-matching` from `main` (stashed work restored). Migration `20261125100000_create_transfer_links.rb` (additive; rollback tested). Details in `ARCHITECTURE.md`.
- **Differences from handoff #05 §A, and why:**
  - Confirm stores `category_id`, `categorization_source`, `confidence`, `needs_review`; `suggested_category_id` joins the stored state with C2b (the column doesn't exist yet).
  - `DELETE /transfer_links/:id` on a rejected link returns **409 `row_in_another_transfer`** if one of its rows has since joined another pair (the "one active link per row" rule would otherwise be broken).
  - Undo of a confirm restores a row only if it's still a Transfer from that confirm (same "leave rows the user changed since" rule as B.2).
  - Added the recorded PO rule now that links exist: a transaction in any transfer link can't be deleted (422). AI3's "also update other rows" skips rows in a suggested or confirmed pair.
- **Tests:** `transfer_matcher_test.rb` (16: exactly 3 days, 4 days, inflow first, same account, same sign, different amounts, smallest gap, earliest date then lowest id, one active link per row, idempotent, rejected pair never again but rows can pair elsewhere, confirmed rows skipped, categorized rows are candidates, ±3-day window, other users' rows, DB uniqueness), `transfer_links_controller_test.rb` (12), 3 ownership-matrix rows + index and 403 checks; snapshot includes `transfer_links`. Server suite **398 pass**. Mutation checks caught: different-account rule, rejected-pair rule, smallest-gap ordering, ownership scoping.
- **Acceptance on demo data** (`demo:reset` + `demo:seed`, Claude on): **62 suggested pairs = 54 of 54 real transfers + 8 of 8 decoys, 0 wrong pairs, 0 real pairs missed.** `needs_review` rows: 138, of which 113 are in a suggested pair (108 transfer rows + 5 decoy Venmo repayments). **Left to review outside a pair: 25**, all Amazon/Target ("other", Claude unsure).
  - **Why 25, not ~36:** the earlier 36 counted the 8 decoy "concert tickets" repayments separately; they now sit inside suggested pairs (shown in Transfers, for Reject), and this run Claude placed 3 more Amazon/Target rows confidently (28 → 25). No data was tuned. Once the decoys are rejected, their Venmo rows (where still in review) rejoin Review, so after rejecting all decoys "to review" is about 30.
- **PO approval (2026-11-25):** TR1 approved, including all five differences from handoff #05 §A: (1) Undo stores categorization source and confidence too (exact restore); (2) undoing a reject → 409 if a row has since joined another pair (one pair per row); (3) Undo of a confirm skips rows changed since (consistent with the category Undo); (4) transactions in a pair can't be deleted (integrity); (5) merchant corrections skip rows in a pair (closes a bug where teaching a merchant could undo a pending transfer). TR1 gets its own PR to `main`; C2b starts afterwards on new branches from `main` in both repos.

### TR1 merged; C2b (review and transfer screens) — server done, uncommitted (2026-11-25)

- TR1 (transfer matching) merged to `main` by the PO; C2b branches `feature/review-and-transfers` created from `main` in both repos.
- **Server (handoff #05 §B):**
  - **B.1** migration `20261125120000_add_suggested_category_to_transactions.rb`: nullable FK + CHECK "a row never has both a category and a suggestion". The pipeline keeps Claude's valid but < 0.6 pick as `suggested_category_id` (never Transfers or legacy; invented slugs and out-of-range confidence ignored); every categorization clears it (model callback + every `update_all`). Transfer confirm stores it and Undo restores it.
  - **B.2** migration `20261125120100_create_category_corrections.rb` + `Categorization::Correction` (apply/undo). `PATCH /transactions/:id` with a category now returns `correction_id`; `POST /category_corrections/:id/undo` restores rows still at the corrected category, restores or deletes the merchant rule, sets `undone_at`; second undo 409; another user's 404. Response: `restored_transaction_ids`, `remaining`.
  - **B.3** `GET /transactions/review_groups` via `Categorization::Review`: waiting rows in active accounts, not in a suggested transfer pair, grouped by AI3's merchant key; `display_name` and `representative_transaction_id` from the latest row; most common suggestion; up to 2 alternatives from the user's most used categories in the same direction, empty slots filled with Other; order count ↓, |total| ↓, key. `remaining` is the shared "to review" count.
  - `GET /transactions` rows add `suggested_category` (slug) and `transfer_suggested`.
  - **Choices beyond the handoff:** corrections also store `categorization_source` and `confidence` (exact restore, as TR1) and the `merchant_key` (needed to restore/delete the rule); the column is `transaction_id` as specified but the association is `picked_transaction` (`transaction` is a Rails method); deleting a corrected transaction deletes its correction records (an Undo for a deleted row means nothing).
  - Tests: `suggestions_test.rb` (6), `category_corrections_test.rb` (7), `review_groups_test.rb` (6), ownership-matrix row + review-groups check; snapshot includes `category_corrections`. Server suite **418 pass**. Mutation checks caught: undo restoring rows changed since, rule not forgotten, pairs not excluded from Review, suggestions dropped, unscoped correction lookup.
- **Client (handoff #05 §C)** on `bb-client` `feature/review-and-transfers`: Review and Transfers screens, Activity transfers tile and row chips, mascot "All caught up" (details in `ARCHITECTURE.md`). Activity's "to review" now uses `review_groups.remaining`, so it matches Review (rows in a suggested transfer pair count on Transfers instead). No new dependencies (mascot via `react-native-svg`, already installed); no native rebuild needed.
  - Tests: `__tests__/reviewAndTransfers.test.tsx` (10: row chip states; card chips with and without a suggestion, purpose text, picked state + Undo; Review screen pick → collapse and count, Undo restores card and count, "All caught up" with Undo still reachable, More… without Transfers; transfer card actions and outcomes), `__tests__/mascot.test.ts` (asset sync). Client suite **48/48**, TypeScript **48**, iOS bundle builds (1,694 modules). Mutation checks caught: "?" missing on the suggestion, Undo not restoring the card, "Transfer?" chip missing.
- **Phone acceptance note:** the spec's check runs "after `demo:reset`", but the phone signs in as the PO's own account, whose rows were imported before B.1, so they have no suggestions (no backfill, per §B.1): Review shows alternatives only. Seeing "?" chips needs fresh rows in that account (decision requested).
- **`demo:reset USER_EMAIL=…` (C2b phone acceptance):** `Demo::Reset` can reset another account when it's named by email (development only; unknown email refused; demo account still the default). It now also deletes **category corrections** (they reference transactions, so a reset after any correction would otherwise fail; same fix for the demo account). Tests: `reset_test.rb` +3 (named account reset incl. corrections, demo account untouched; unknown email refused; demo reset after corrections and confirmed pairs). Server suite **421 pass**. The PO runs it on their own account.
- **C2b phone acceptance passed (PO, 2026-11-25)**: all five steps. Committed: server `2dfcfe0`, client `583c50e`, both on `feature/review-and-transfers`. Next: PRs to `main`, then EV1 (categorization eval).

### C2b merged; EV1 (categorization eval) — done, uncommitted (2026-11-25/26)

- C2b merged to `main` in both repos (server `5f14b03`). EV1 on `bb-server` `feature/categorization-eval`.
- **Labels (PO request):** taken from `Demo::Generator#golden`, i.e. the category the generator assigned when it created each row, never from the pipeline's output. Stated in the report. A test runs the eval with a deliberately wrong fake AI and checks the labels still equal the generator's; a mutation that reads labels from the pipeline is caught.
- **Report (`docs/evals/categorization-2026-11-26.md`), model `claude-haiku-5-5`:**
  - **Auto-categorized accuracy 100.0% (257 of 257)**; review rate **14.3%** (43 of 300); **transfer critical errors 0** (all 18 transfers sent to review); correct with no user action 85.7%.
  - By stage: merchant memory 0 rows (empty by design); keyword rules 250/250; Claude 7/7. Of the 43 sent to review, 25 had a suggestion (all 25 right) and 18 had none (the transfers).
  - Claude: 1 request, 3,093 input + 763 output tokens, about $0.0007.
  - **Limitations, stated in the report:** the keyword rules and the golden merchants were written together, so 250 of 300 rows hit a rule (this shows rule coverage of the demo, not generalization); Claude saw too few rows (7 categorized, 25 suggested) to estimate its accuracy; some labels are judgement calls; synthetic data, one run.
- Tests: `test/lib/evals/categorization_test.rb` (7: labels independent of the pipeline, transfers never auto-categorized even by an AI answering Income, eval user isolated with memory wiped per run, refuses production, metrics by hand, critical-error counting, report content). Server suite **428 pass**. Mutations caught: labels from the pipeline; critical count hidden.
- **Not built:** the plan's `eval.yml` (`workflow_dispatch`) for running EV1 on GitHub needs an `ANTHROPIC_API_KEY` repository secret (PO-22); the eval runs locally for now.
- **Proposed follow-up (decision needed):** a harder golden set (merchants the rules don't know, ambiguous and noisy descriptions, person-to-person payments) so the report measures Claude, not just rule coverage.

### EV1 committed (`9deac5c`); hard golden set — done, uncommitted (2026-11-26)

- PO: EV1 committed on `feature/categorization-eval`; build a harder set before calling EV1 done; skip the `workflow_dispatch` job for the MVP.
- **Hard set** `bb-server/lib/evals/golden_hard.yml`: **80 rows**, each labelled when written, before any hard-set run (unknown merchants 26, messy 14, person-to-person 8, refunds 7, ambiguous 19, transfers 6 incl. "WEB XFER" and "SAVINGS SWEEP", which the transfer check doesn't catch). Labels are the author's judgement (stated in the report). Keyword rules frozen at fingerprint `9efd9329adcaf092`; the report recomputes it and says so if the rules changed.
- `Categorization::Pipeline.call(keyword_rules: false)` for the Claude-only run (the app always uses the rules; the transfer check stays on). `Evals::GoldenSets` (easy/hard rows, fingerprint), report covers three runs.
- **Results (`docs/evals/categorization-2026-11-26.md`, `claude-haiku-5-5`, 5 requests, 15,829 + 5,077 tokens, ≈ $0.004):**

  | | Easy (300) | Hard (80) | Hard, Claude only (80) |
  |---|---|---|---|
  | Auto-categorized accuracy | 100% (257/257) | **96.8% (60/62)** | **96.7% (58/60)** |
  | Review rate | 14.3% | 22.5% | 25.0% |
  | Suggestion right | 100% (25/25) | 64% (9/14) | 69% (11/16) |
  | Transfer critical errors | 0/18 | 0/6 | 0/6 |
  | Keyword rules (accuracy) | 250 (100%) | 20 (95%) | off |
  | Claude (accuracy) | 7 (100%) | 42 (97.6%) | 60 (96.7%) |

  - Hard-set mistakes: full pipeline: NORTHSIDE COIN LAUNDRY → utilities (Claude; labelled other), WILLOW CREEK VET CLINIC → healthcare (keyword rule "CLINIC"; labelled other); Claude only: SUMMIT CLIMBING GYM → entertainment (labelled personal-care), JUNIPER DENTAL STUDIO INS REIMB → insurance (labelled healthcare). All four are ambiguous or judgement calls; none is a transfer.
  - The two unguarded transfers reached Claude and went to review (low confidence: the prompt's backup instruction held).
- Tests: `test/lib/evals/categorization_test.rb` now 13 (adds hard-set labels from the file, rules frozen, no personal data in the file, unguarded transfers reach the AI and would be counted as critical, Claude-only switch, three-run report, "rules changed" warning). Server suite **434 pass**. Mutation (report always says "frozen") caught.
- **`docs/product/` can't be committed:** the top-level `docs/` folder isn't inside any git repository (only `bb-server/` and `bb-client/` are repos). Decision requested on where the product docs should live.
- **PO (2026-11-26):** hard set approved for commit. **Known issue for v1:** the keyword rule "CLINIC" → healthcare misfiled WILLOW CREEK VET CLINIC (true: other); rules stay frozen for now; recorded in the plan's v1 list (§11). **Docs:** option 1, move the top-level `docs/` into `docs/` as its own small PR after EV1 merges (fix old-path references; one line in the client README pointing to the server repo's docs). Then C9. New `docs/product/README_DRAFT.md` and `DEMO_SCRIPT.md`: don't replace the README yet; fill its TODOs with as-built facts at the end of M2.

### Docs moved into the server repo (2026-11-26)

- PO decision (option 1): the top-level `docs/` (ARCHITECTURE, PROGRESS, IMPLEMENTATION_PLAN, GLOSSARY, `product/` with specs, handoffs, screens, brand, `README_DRAFT.md` and `DEMO_SCRIPT.md`) moved to `bb-server/docs/`, next to `docs/evals/`. It was not in any git repository before.
- Paths fixed: inside the docs, `bb-server/docs/…` → `docs/…`; 11 client source comments now point to `bb-server/docs/product/…`; the top-level `CLAUDE.md` (still outside both repos) points to `bb-server/docs/…`. One line added to each README pointing to the docs (both READMEs otherwise unchanged until the end of M2).
- Before committing, the docs were scanned for private data: no emails, names, keys or tokens; the Mac's LAN IP (2 mentions in PROGRESS) was replaced with "the Mac's LAN IP".
- Branches: server `chore/move-docs-into-server`, client `chore/docs-pointer` (both from `main`), one small PR each. Left untouched: `project-knowledge/2026-11-22/` (a dated snapshot).

### C9 (welcome and account screens) — built, uncommitted (2026-11-26)

- Client branch `feature/welcome-and-account` from `main`. Spec `docs/product/SCREENS_WELCOME.md` (D-023, D-020). Details in `ARCHITECTURE.md`. No server change.
- **SVG:** `react-native-svg` (already installed and linked natively) with `SvgXml`; no Metro SVG transformer, no PNG export.
- **Sign in vs cancel:** Kinde SDK 1.3.1's `login()`/`register()` return `null` both on cancel and on failure (the error is swallowed and logged). The Welcome screen therefore checks Kinde is reachable first (`GET <domain>/.well-known/openid-configuration`, 5 s timeout); unreachable → inline "Couldn't open sign-in…", no browser. A `null` result is treated as a cancel (no message). `register()` exists, so Create an account uses it.
- **Account sheet rows:** the spec text lists "Week starts on" and "Time zone"; the design screenshot also shows "Data: Demo data", which isn't built (spec text followed). Profile values come from `GET /me` (it already returns `profile`), loaded when the sheet opens.
- **Assets:** app icon `assets/images/app-icon-1024.png`; splash per §6 (PO added `assets/images/splash-mascot.png`): `expo-splash-screen` plugin, Birch `#F6F1E7`, image 200 pt wide, light only, config-only. **Deleted** (old login images, unused): `assets/images/budget-buddy.png` (bear on a banknote), `assets/images/home-screen-design.png` (people illustration). `squirrelbuddy.png` kept (used by frozen legacy code). The old `splash.png` (Expo's default placeholder) and `icon.png` are now unused but kept.
- iOS project updated with `expo prebuild` (no `--clean`, signing team kept) + `pod install`; one rebuild from Xcode needed for the icon and splash.
- **Owner task (demo checklist): brand Kinde's hosted pages** in the Kinde dashboard → Design: logo `mascot-512.png`, primary button colour Pine `#2F5D46`, background Birch `#F6F1E7`, business name "Budget Buddy".
- Tests: `__tests__/welcomeAndAccount.test.tsx` (14: routing rule; sign-in flow incl. unreachable, cancel, failing `/me`; reachability; Welcome renders name, both buttons, both legal links; offline message and buttons usable again; sign-up → Activity with 0 accounts; Terms note; account helpers and defaults; account sheet rows and Log out; Home's account button, no separate Log out), `__tests__/brandAssets.test.ts` (hero + mascot synced with assets). Client suite **63/63**, TypeScript **48**. Mutation checks caught: routing rule, reachability check, cancel handling.
- `CLAUDE.md` iPhone note updated (SDK 54).
- **App display name "Budget Buddy" (PO, 2026-11-26):** after logout, iOS showed "'bbclient' Wants to Use 'kinde.com' to Sign In". The prompt is iOS's standard consent for any web sign-in/sign-out session (Kinde opens one for both); the odd part was the starter name. `name` in `app.config.ts` is now "Budget Buddy" (home-screen label and the prompt). Slug (`bb-client`), Xcode project (`bbclient`), bundle ID (`app.budgetbuddy.mvp.dev`) and signing team unchanged. Not done (option B, offered): an ephemeral browser session, which would remove the prompt but make users re-enter credentials every sign-in.
- **C9 phone acceptance passed (PO, 2026-11-26);** committed on client `feature/welcome-and-account` as `face8a7`.

## Milestone 2 (handoff #06)

### Step 1 decisions (PO, 2026-11-26)

- Handoff #06 read; step 1 = DM-3 (category budgets), OB1 (bills), G1 (goals), as **three server PRs** (approved).
- **Budgets only for flexible categories** (active spending, labelled variable): fixed categories are bills; Income and Transfers have no budget. Others → 422.
- **Goal saved amount / debt balance computed, not stored:** saved = starting amount + set-asides; debt balance = latest balance update (else the starting balance). No `current_balance` column (differs from plan §2.2), so undo-by-delete can't drift.
- **Linking a goal contribution to a transfer: not in step 1** (on the cut list; added later only if time allows).
- **`POST /goals` built** (owner-scoped, tested) for PL2 and demo data; the app shows no "+ Add goal" in the MVP.

### DM-3 (category budgets) — done, uncommitted (2026-11-26)

- Branch `feature/category-budgets` (server). Migration `20261126100000_create_category_budgets.rb` (additive; rollback tested). Details in `ARCHITECTURE.md`.
- `plan_proposal_id` (plan §2.2) is left for PL1, when `plan_proposals` exists (additive then).
- "This month" uses the user's time zone (`UserClock`), so the Plan screen's "change from this month" matches the user's calendar, not UTC's.
- Tests: `category_budget_test.rb` (6: effective-from rule incl. replacement and before-first-row, per-category latest row, other users, flexible only, 1st / non-negative / unique in model and database, UserClock month boundary) and `category_budgets_test.rb` (7: listing with amounts in effect, bad month, bulk all-or-nothing, same-month update, single change in the user's zone, refusals, other users); ownership matrix: unknown category row, snapshot includes `category_budgets`, not-provisioned 403. Server suite **448 pass**. Mutation checks caught: oldest row picked instead of latest; flexible-only check removed.
- **PO approval (2026-11-26):** DM-3 approved. `UserClock` recorded in `ARCHITECTURE.md` as the single source of today / this week / this month for every feature. **Pending, not lost:** `GET /category_budgets/:slug/context` (SCREENS_PLAN §3.1: weekly equivalent, 3-month average, spent this month) depends on AN1, so it's built in step 3 (analytics) or step 5 (Plan tab).

### OB1 (bills) — done, uncommitted (2026-11-26)

- DM-3 merged to `main`. Branch `feature/bills` (server). Migration `20261126110000_create_obligations.rb` (additive; rollback tested). Details in `ARCHITECTURE.md`.
- **Spec deviations / choices (for the decision log):**
  1. **Added `obligations.day_of_month`** (not in plan §2.2). Without it, "monthly on the 31st" added in November would store Nov 30 and stay on the 30th forever. With it, Nov 30 → Dec 31 → Jan 31 → Feb 28. It defaults to `first_due_on`'s day, so callers can ignore it.
  2. **"Bills each month"** (SCREENS_PLAN §4) is a monthly equivalent: weekly × 52/12, every 2 weeks × 26/12, yearly ÷ 12; one-off and ended bills not counted. It's stated in the response's `assumptions`.
  3. **"Current occurrence"** for the status chip and Mark paid: the earliest due date in the next 7 days, else the latest before today, else the next. So a forgotten "Was due" bill gives way to the next due date once that is within 7 days (Home still lists unpaid ones from earlier this week, spec §8.1).
  4. **Mark paid twice:** the first `paid_on` stays (to change the date: unmark, then mark again). Archived bills refuse edits and new payments; unmarking still works.
  5. Extra endpoints beyond the plan row, all from SCREENS_PLAN §4: `GET /obligations` (summary), `GET /obligations/:id`, `PATCH`, `POST …/archive`. No delete (archive instead).
  6. `plan_proposal_id` left for PL1 (as with DM-3).
- Tests: `recurrence_schedule_test.rb` (10, hand-calculated: the 31st through Feb/Apr, leap year Feb 29, `day_of_month` 31 starting Nov 30, every 3 months, weekly/biweekly/every 4 weeks, yearly Feb 29, one-off and `ends_on`, before the first date, next/last lookups a year out, bad input), `obligation_test.rb` (8: day default, fixed only, amounts and schedules, consistency with `day_of_month`, own account only, database CHECKs incl. NULL day, payment rules incl. paying early, FK restrict + archive, monthly total), `obligations_test.rb` (7: create with injected owner/source ignored, refusals, list summary and all four chips, mark twice = one row / unmark restores due / non-occurrence 422 / future 422, `paid_on` in the user's zone, `/due` with ranges and archived excluded, edit + archive). Ownership matrix: 7 rows (show/update/archive/pay/unpay another user's bill → 404, other user's account → 404, unknown category → 422), snapshot includes both tables, not-provisioned 403, lists empty for the caller. Server suite **480 pass**. Mutation checks (10) all caught, after adding the archived-in-`/due` check.

- **PO approval (2026-11-26):** OB1 approved, including all six points above. **For PL1 (plan drafting):** the plan's committed-bills total must use `Bills.monthly_total` (the same monthly equivalents), so the drafted plan and the Plan tab always agree.
