# CLAUDE.md — Budget Buddy (server)

A budgeting coach for lapsed budgeters: import bank CSV exports, get a plan built from your own numbers, and see what's left to spend this week. Rails 7.1 API (this repo) + Expo app (`bb-client`).

## Your role

You are the **Builder**. Follow the workflow in `.claude/skills/project-build-workflow/SKILL.md` (Phases 2–5, and its GitHub sections). The Planner works in a Claude Project and sends numbered handoffs, kept in `docs/product/` as **`HANDOFF_CLAUDE_CODE_NN.md`** (this project's existing naming; don't rename).

**Every task follows the skill's Phase 3 loop:** a `task` issue → a branch from an up-to-date `main` → build and test → the report with the understanding check → the owner's OK → commit, push, and a PR that **closes the issue**. Move the issue's card on the board ("Budget Buddy") to **In progress** when you start and **In review** at handoff.

## Where things are

- All docs: `docs/` (product docs, specs, screens and handoffs in `docs/product/`). Docs are the source of truth; GitHub issues and PRs are the trail.
- **Ground rules:** `docs/IMPLEMENTATION_PLAN.md` (plus the ones below). **ID conventions and plain names:** `docs/GLOSSARY.md`.
- Ambition level: **D-029** in `docs/product/DESIGN_DECISIONS.md` (L0, designed for L1).
- Progress log: `docs/PROGRESS.md`. As-built architecture: `docs/ARCHITECTURE.md`. Eval reports: `docs/evals/`.
- Client repo: **`bb-client`** (`itsgivingchaotica/budget-buddy-native`); its `CLAUDE.md` points here.
- Pinned issue "Project status" in this repo: current stage, level and next decision.

## Ground rules

- **No commits, pushes, issues, labels or PRs without the owner's explicit OK, each time.** Show the plan or the list first.
- Never print, commit or log secrets. **No financial or personal text in logs or issues** (filter_parameters, no SQL log, `SafeError` for exceptions). Demo data only in issues and screenshots.
- One task = one branch = one PR that closes its `task` issue. Branches: `feature/`, `fix/`, `chore/`, `docs/`.
- Commit messages: `TASK-ID (plain name): what it does`. Write each ID's plain name the first time it appears (house rule; names in `docs/GLOSSARY.md`).
- Where a spec and the code disagree, stop and tell the owner before building. Real values win over examples.
- Migrations are additive and reversible. No data rewrites without a backup, a before/after check and the owner's approval (re-seed with `demo:reset`).
- Deterministic code decides and calculates; AI assists (D-027). No figure shown to a user comes from a model.
- `docs/ARCHITECTURE.md` describes only what's built.
- **The Builder keeps the issue checklists current.** Tick each box on the task issue as soon as it's verified, with a one-line proof comment (test, CI run, commit). Never tick the owner-only items (understanding check, phone test, screenshots) until the owner has done them. Before asking the owner to merge, every box is ticked or explained.
- **End every report that needs the owner with an "Owner action needed" block:** what to do, where, what to reply, and which boxes it unlocks. The owner shouldn't have to go looking.

## Project-specific rules

- **Dates:** `UserClock` is the only source of today / this week / this month (the user's time zone and week start).
- **AI:** every Claude call goes through `AnthropicClient`, which checks the daily cap (`AiBudget`); tests pass a fake `sdk:` (real clients are refused in test).
- **Ownership:** every lookup goes through `current_user`; another user's record → 404; new resources add rows to `test/controllers/ownership_matrix_test.rb`.
- **Money:** `decimal(12,2)`, BigDecimal, JSON as strings (`MoneyJson`; never "-0.00").
- **Tests:** hand-calculated worked examples, then mutation checks (break the logic on purpose; every break caught).
- **Report after each task:** what was built, deviations, test counts (server, client, TypeScript baseline), mutation checks, the understanding check (2–3 core files, a walkthrough, 3 questions), phone test steps with the `demo:*` command per state, open questions, the issue boxes now ticked, and the **Owner action needed** block. When the owner answers the questions: say for each whether it's right, point out gaps, and walk through the key lines with a small real-numbers example, defining finance terms in one sentence.
- **Handoff message order** (after the OK to commit): push commands → server PR → phone test steps → client PR (with the screenshots section). Create PRs with `gh pr create` after the owner pushes, with the issue's labels and milestone.
- **Docs check:** `bin/check-docs` (every doc has a status line; relative links resolve).

## Commands

```bash
bundle install
bin/rails db:create db:schema:load db:seed
bin/rails server
bin/rails test                                  # Minitest; single file or file:line works too
bin/rails eval:categorization                   # EV1, real Claude calls (~$0.001)
bin/rails demo:generate[dir] / demo:seed [USER_EMAIL=…] / demo:reset [USER_EMAIL=…]
bin/rails "demo:home_state[normal]" [USER_EMAIL=…]        # no_plan | normal | over | plan (development only)
bin/rails "demo:onboarding_state[interview]" [USER_EMAIL=…] # accounts | interview | merchants | plan
bin/check-docs                                  # docs status lines and links
bin/setup-labels [owner/repo] · bin/setup-milestones [owner/repo] "M2 …" "M3 …"
```
