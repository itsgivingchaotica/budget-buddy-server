---
name: project-build-workflow
description: "Use when starting or running any software project with a planning chat and a coding agent - idea intake, ambition level, GitHub-tracked design, specs, handoffs, task IDs, PRs and progress logs."
---

# Project build workflow (Planner → Builder → Owner)

A reusable workflow drawn from the Budget Buddy project. Three roles:

- **Planner**: the planning chat or Claude Project. Owns the *what* and *why*: idea, level, brief, scope, decisions, backend shape, design, specs, handoffs.
- **Builder**: the coding agent in the repo. Owns the *how*: GitHub setup, plan, code, tests, PRs, progress log, as-built architecture.
- **Owner**: the human. Approves every stage, spec and deviation, and every commit/push. The owner's explicit OK is the only source of truth.

First, work out which role you're in this session (a repo with code = Builder; a planning conversation = Planner) and follow that role's section. For a brand-new idea, start at Phase 0.

## Standing rules (every project, both roles)

1. **Nothing is approved until the owner says so.** Mark status on every doc and issue: `Draft` · `Proposed (Claude)` · `Preliminary (owner direction)` · `Approved (owner, YYYY-MM-DD)` · `Deferred` · `Superseded`. Record owner decisions separately from Claude's suggestions.
2. **No commits, pushes, issues or PRs created without the owner's explicit OK.** Never print, commit or log secrets. No sensitive user content (financial, health, personal) in logs or issues.
3. **IDs with plain names.** Every idea, decision, task and question gets an ID. The first time an ID appears in any doc, issue or message, write its plain name beside it: "G2 (goal and debt maths)". Keep a `GLOSSARY.md` with one sentence per ID and per ID family.
4. **Deterministic first, AI assists.** Code decides and calculates; AI proposes, chooses among code-computed options, and words things; the user decides. No figure shown to a user is produced by a model.
5. **Small, reversible steps.** One task = one branch = one PR. Migrations are additive and reversible (working `down`). Data rewrites need a backup, a before/after check and owner approval.
6. **Specs win, but reality reports back.** When a spec and the built code disagree, the Builder stops and tells the owner before building. Real API values beat examples. Every deviation goes back into the decision log.
7. **Docs describe what is true.** `ARCHITECTURE.md` describes only what's built; the target design lives in its own doc with built/designed labels.
8. **Dated, plain language.** Date every approval and entry. Short sentences; tables for comparisons.
9. **Build for the current ambition level, design for the next one up** (Phase 0.2).
10. **Docs are the source of truth; GitHub is the trail.** Approved content lives in `docs/`. Issues track the conversation and status, PRs record the approval, and each one links to the other.

## ID families (adapt prefixes per project)

| Prefix | Meaning | Lives in | GitHub |
|---|---|---|---|
| I-nn | Raw idea from intake | `IDEA_CARD.md` | `idea` issue |
| D-0nn | Product/architecture decision (D-001 = ambition level) | `DESIGN_DECISIONS.md` | `decision` issue |
| C-n | Hard constraint | `CONSTRAINTS.md` | listed in a pinned issue |
| Q-nn | Open question (Planner) | `DESIGN_DECISIONS.md` | `question` issue |
| PO-nn | Question for the owner raised by the Builder | `PROGRESS.md` | `question` issue |
| P1–Pn | MVP features in priority order | `MVP_SCOPE.md` | `feature` issue (parent) |
| M0, M1, M2 | Milestones (M0 = discovery and design) | `MVP_SCOPE.md` | GitHub milestones |
| L0–L4 | Ambition level | D-001 | `level:Ln` label |
| Task IDs (e.g. AUTH1, DM-3, C8, EV1) | One reviewable piece of build work = one PR | `IMPLEMENTATION_PLAN.md` | `task` issue |
| K-n / TD-n | Known issues / accepted tech debt | `PROGRESS.md` / plan | `bug` / `tech-debt` issue |

## Doc set (one `docs/` folder, in one repo)

Keep all docs in one repo (usually the server/core repo); other repos' READMEs link to it.

```
.github/
  ISSUE_TEMPLATE/  idea.yml  decision.yml  question.yml  spec.yml  screen.yml  task.yml  bug.yml  config.yml
  PULL_REQUEST_TEMPLATE.md
  workflows/ci.yml
docs/
  GLOSSARY.md              Planner
  ARCHITECTURE.md          Builder (as-built only)
  IMPLEMENTATION_PLAN.md   Builder (task IDs, order, ground rules; owner-approved revisions)
  PROGRESS.md              Builder (running log, PO-nn questions, approvals)
  evals/<feature>-YYYY-MM-DD.md   Builder (eval reports)
  product/
    IDEA_CARD.md  CONSTRAINTS.md  PRODUCT_BRIEF.md  MVP_SCOPE.md
    DESIGN_DECISIONS.md    (D-000 lists this hierarchy, D-001 the level)
    TARGET_ARCHITECTURE.md (intended design, built/designed labels, L+1 column)
    DESIGN_INPUTS.md       (backend capabilities and constraints for design)
    SPEC_<FEATURE>.md / SCREENS_<AREA>.md
    HANDOFF_<NN>.md
    screens/               mockups and screenshots
```

---

## GitHub during discovery and design

Design work is tracked in GitHub **from the moment the repo exists**, not only once building starts. Then anyone looking at the repo (a reviewer, a recruiter, a future collaborator) can follow the idea → decision → spec → task → PR trail.

### When to create the repo

Create it **right after the Idea Card is approved (0.1)**. Don't wait for code. At first it holds only `README.md` (one-paragraph pitch + "Status: discovery"), `docs/product/IDEA_CARD.md` and `.github/`. If the project will have several repos (client/server), create the core repo first; it holds the docs. Create the others when the architecture decides them (0.5).

### Handoff #00: GitHub setup (the Builder does it, the owner approves)

The Planner writes Handoff #00. The Builder (Claude Code, using `gh`) creates:

1. **Issue templates** (`.github/ISSUE_TEMPLATE/*.yml`), as below.
2. **Labels** via `gh label create`:
   - type: `idea`, `decision`, `question`, `spec`, `screen`, `feature`, `task`, `bug`, `tech-debt`, `docs`
   - status: `status:inbox`, `status:shaping`, `status:proposed`, `status:approved`, `status:parked`, `status:dropped`, `status:superseded`
   - idea triage: `idea:core`, `idea:later`
   - area: `area:product`, `area:design`, `area:backend`, `area:client`, `area:infra`, `area:ai`
   - level: `level:L0` … `level:L4` (for items that only apply from a given level)
3. **Milestones:** `M0 Discovery & design`, then `M1`, `M2`… from the scope.
4. **A GitHub Project board** with a Status field: `Inbox → Shaping → Proposed → Approved → Ready for handoff → In build → Done`, plus `Parked`. Views: "Design" (idea/decision/spec/screen) and "Build" (task/bug).
5. **Pinned issues:** "Project status" (current stage, level, next decision) and "Constraints (C-n)".
6. **The PR template** (Phase 3) and minimal CI (it can run only a docs check until code exists).

If the Planner has a GitHub connector with write access, it may create issues directly (with the owner's OK). Otherwise it writes them into `docs/product/ISSUES_TO_CREATE.md` (title, labels, milestone and body for each), and the Builder creates them with `gh issue create` and replaces each entry with its issue number.

### What goes in GitHub at each design stage

| Stage | Issues | PR (approval record) |
|---|---|---|
| 0.1 Idea intake | One `idea` issue per raw idea (I-nn), triaged `idea:core` / `idea:later` / `status:parked` / `status:dropped` (with the reason in a comment) | `docs/idea-card` → adds `IDEA_CARD.md`, which links every I-nn issue |
| 0.2 Ambition level | `decision` issue D-001 with the level options and a recommendation | `docs/level` → D-001 in `DESIGN_DECISIONS.md` |
| 0.3 Constraints | Constraints are listed in the pinned issue | `docs/constraints` |
| 0.4 Brief + scope | One `feature` issue per P1–Pn (parent issue; ideas linked as sub-issues or by reference) | `docs/brief-and-scope` |
| 0.5 Backend shape | `decision` issues for each hard-to-reverse choice (tenancy, IDs, auth, DB, hosting) | `docs/target-architecture` |
| 0.6 Design inputs | — | `docs/design-inputs` |
| 0.7 Client design | One `screen` issue per screen area with the mockup image attached; feasibility flags as comments or `question` issues | `docs/screens-<area>` (spec + `screens/*.png`) |
| 0.8 Specs | One `spec` issue per spec (review checklist); on approval, the Builder creates its `task` issues | `docs/spec-<feature>` |

**Approval = merge.** The owner approves a design doc by merging its docs PR. Merging closes the linked `decision`/`spec` issue (`Closes #n`), and the doc's status line records `Approved (owner, date) · PR #n`. A superseded decision gets a new issue that references the old one, and the old one is relabelled `status:superseded`.

**Traceability rule:** every doc header carries its issue number; every issue links its doc path; every `task` issue links its spec, its parent `feature` and the ideas it came from.

### Design-phase issue templates

**idea.yml**
```
Title: I-nn (plain name)
Labels: idea, status:inbox   Milestone: M0
The idea (owner's words) · Problem it solves / who for · Inspiration or reference (links, sketches)
Triage (Planner): core / later / parked / dropped, with reason · Feeds: P-n / spec / screen issue
```

**decision.yml**
```
Title: D-0nn (plain name)
Labels: decision, status:proposed, area:*
Context · Options (A/B/C with pros, cons, cost, reversibility) · Recommendation (Claude)
Level impact: what changes at L+1 · Owner decision: ___ (date) · Recorded in: DESIGN_DECISIONS.md · PR #
```

**question.yml**
```
Title: Q-nn / PO-nn (plain name)
Labels: question, area:*
Question · Why it matters / what it blocks · Options + recommendation · Answer (owner, date)
```

**spec.yml**
```
Title: SPEC: <feature> (P-n)
Labels: spec, status:shaping, area:*
Doc: docs/product/SPEC_X.md · Ideas: I-nn · Decisions: D-0nn · Screens: #
Review checklist:
- [ ] Definitions precise   - [ ] Edge cases and states   - [ ] API contract
- [ ] Worked examples (acceptance tests)   - [ ] AI feature contract (if AI)
- [ ] Level notes (L+1)   - [ ] Feasibility checked against backend shape
- [ ] Open choices answered
```

**screen.yml**
```
Title: SCREEN: <area>
Labels: screen, area:design, area:client
Mockup (attach image / canvas link) · User job it answers · Data shown → endpoint/field
Actions → endpoint · States: loading / empty / partial / error / offline / stale / AI-uncertain
Feasibility flags (from DESIGN_INPUTS): … · Resolution: design change / backend task #
```

**task.yml**, **bug.yml**: see Phase 3.

---

## Phase 0 — Planner: from raw idea to approved direction

Work through the stages in order. Each stage ends with a short owner approval, a D-0nn entry and (once the repo exists) a merged docs PR. Don't move on while the owner's answer to a stage is still open. Ask at most 3–5 questions per turn, each with a recommendation.

### Claude Project setup (once)

- **Project instructions:** paste the Standing rules and "Follow project-build-workflow; you are the Planner."
- **Project knowledge:** add each doc as it's approved. Re-upload after merges, because knowledge doesn't update itself. Keep a dated snapshot when docs move into the repo.
- **One conversation per stage or spec** keeps context clean. Open each with the pinned "Project status" issue text.

### 0.1 Idea intake (brain dump → Idea Card)

The owner dumps everything: features, screens, inspirations, worries, half-thoughts. The Planner doesn't judge yet. It gives each raw idea an I-nn, then sorts the dump into an **Idea Card** (`product/IDEA_CARD.md`):

```
Problem (one paragraph) · Who has it (primary user first) · Core job as ONE question the app answers
Why current options fail · What would make this different · Success measure (observable)
Owner's goal for the project (learn / show / earn / serve)
Ideas: I-nn table with triage (core / later / parked / dropped + reason)
Biggest unknowns / risks
```

Nothing is silently lost. Once approved, create the repo and run Handoff #00 (GitHub setup); each I-nn becomes an `idea` issue.

### 0.2 Ambition level: decide this before any design

The level sets the defaults for architecture, infrastructure, security, process weight and cost. Record it as D-001. Rule: **build for the current level and design for the next one up.** Make the hard-to-reverse choices now so they don't block the climb.

| Level | Who uses it | Data | Infra defaults | Must-haves added at this level | Typical cost |
|---|---|---|---|---|---|
| **L0 Portfolio / learning** | Owner + reviewers | Synthetic/demo only | One managed PaaS, one region, managed DB on a free/hobby tier, hosted auth | Clean repo, README, tests, CI, demo data + demo script, architecture doc, eval if AI, visible GitHub design trail | $0–20/mo |
| **L1 Private beta** | Owner + <100 invited | Real but few | Same + error tracking, uptime check, automated backups with a restore test | Privacy basics, data export/delete, secrets management, staging DB or branch previews | $20–100/mo |
| **L2 Public launch** | Up to ~10k | Real, public | Separate staging + prod, managed DB with point-in-time recovery, CDN for assets, background job queue | Privacy policy + terms, store listings, rate limits and cost caps, privacy-respecting analytics, support channel, incident checklist, accessibility pass | $100–1k/mo |
| **L3 Growth / commercial** | 10k–1M | Sensitive at scale | Infrastructure as code, horizontal app scaling, caching, read replicas, observability (logs/metrics/traces), feature flags | SLOs + on-call, security review / pen test, compliance as the domain needs (PCI, HIPAA, SOC 2), payments, WCAG AA, i18n-ready strings | $1k+/mo |
| **L4 Worldwide** | Millions, many countries | Regulated, regional | Multi-region, data residency per region, global CDN/edge, DR with stated RPO/RTO | GDPR/CCPA and local law, full localization (currency, dates, RTL), 24/7 support, security program | Varies |

**Hard-to-reverse choices (decide at L0, sized for L+1):** ownership/tenancy model (user vs org), ID type (UUID vs integer), money (decimal, never float), time (stored in UTC, shown in the user's zone), auth provider, primary database, API style, where sensitive data lives, data residency if L3+ is plausible. Each gets its own `decision` issue.

**Process weight scales with the level.** At L0 the doc set stays light (brief + scope + decisions + specs), but issues, PR templates and CI still apply because they're part of the portfolio. From L2 up, add staging sign-off, release notes and a rollback plan for every release; public repos at L2+ should check nothing sensitive is in issues.

### 0.3 Constraints and possibilities inventory

One table (`product/CONSTRAINTS.md`) covering: time and deadline · budget per month · owner's skills and what they want to learn · platforms (iOS/Android/web) · data sensitivity · external data sources and APIs (what they allow and cost) · AI use (model, cost cap, what it may decide) · legal/regulatory needs at this level · existing code to reuse. Each constraint gets an ID (C-n).

### 0.4 Product brief and MVP scope

- **Brief:** problem, target user, core job, principles, non-goals, constraints (links to C-n), level (D-001).
- **Scope:** P1–Pn in priority order, milestones with measurable goals, non-goals, and a **cut order** (what goes first if time runs short).
- Start the **glossary**, and the **decision log** with D-000 (doc hierarchy: which doc, its role, who maintains it).

### 0.5 Backend shape before screens

The client design must respect what the backend can do, and should take advantage of it, so the backend shape comes first:

1. **Domain model:** entities, the ownership root (what belongs to whom), relationships, lifecycle (created → archived; no hard deletes unless decided), and which tables are reference data.
2. **Sources of truth:** every number or status a user sees is computed in one named place. AI never produces a displayed figure.
3. **Data flow:** import/sync, background jobs, real-time vs batch, idempotency and duplicates.
4. **Target architecture** (`product/TARGET_ARCHITECTURE.md`): components, repos, hosting, auth, storage, AI services, sized to the level table, with a **"what changes at L+1"** column.
5. **Scalability notes:** expected load at this level, the first bottleneck you expect, and the planned answer to it.

### 0.6 Capabilities and constraints sheet (backend → design)

A one-page handoff from the backend shape to design (`product/DESIGN_INPUTS.md`):

| Topic | What design must know |
|---|---|
| Cheap and instant | Data the API can return fast enough for any screen |
| Slow or async | Jobs that need progress, "working…" or notify-when-done states |
| First run | What data exists at sign-up, so every screen needs a real empty state |
| Freshness | How stale data can be; what is cached or offline |
| Computed vs AI | Which content is exact (show it as fact) vs AI-made (label it, let the user override it) |
| Errors and limits | Rate limits, cost caps and failure modes the UI must explain |
| Possibilities | What the backend makes newly possible (projections, undo, history), so design can use it |
| Level limits | e.g. L0: no push notifications, one currency; L2+: app store rules |

### 0.7 Client design: product + visuals, bounded by the backend

1. **Brand and visual direction** (tone, palette, type) on a design canvas; approved; a screenshot goes into `screens/`.
2. **Screen inventory from user jobs:** each core job maps to the fewest screens that answer it; one `screen` issue per area.
3. **Screen specs** (`SCREENS_<AREA>.md`), each listing: purpose; the data it shows → the endpoint/field that provides it; actions → the endpoint each one calls; all states (loading, empty, partial, error, offline, stale, AI-uncertain); copy and rounding.
4. **Feasibility pass:** the Builder (or the Planner acting as architect) checks the mockups against the backend shape and flags anything that can't be computed, is too slow, or needs a new table. Each flag either changes the design or becomes a backend task. Record the outcome as a D-0nn that names the constraint that shaped it.
5. Loop between 0.5 and 0.7 until screens and data model agree, then approve both by merging their docs PRs.

### 0.8 Specs, plan and first build handoff

- Feature specs (template below), each with a `spec` issue, and worked examples as acceptance tests.
- On each spec's approval, the Builder creates its `task` issues (one per task ID, in milestone M1/M2).
- If code already exists, the first build handoff is a **read-only audit**: stack, data model, auth, tests, known issues (K-n), plan-vs-code mismatches. It becomes the first `ARCHITECTURE.md`. Otherwise it's **Day 0 setup** (Phase 2).
- Then feature handoffs in deterministic-first order. Close milestone M0.

### Spec template

```
# <Feature> — Spec
Status: Draft | Approved (owner, YYYY-MM-DD) · PR #   Issue: #   Traceability: I-nn, D-0nn, Pn, C-n
1. Purpose — the user question this answers
2. Definitions — every term, precisely
3. Formula / behaviour — step by step
4. Rules and edge cases — states and precedence, empty/zero/missing data, exclusions
5. Display — labels, rounding, states
6. Assumptions returned with every result
7. API contract — endpoints, request, response, errors
8. Worked examples — numbered, hand-calculated; these ARE the acceptance tests
9. Level notes — what changes at L+1 (scale, localization, compliance)
10. Out of scope
11. Open choices for the owner (numbered, with a recommendation)
```

### AI feature contract (required in any spec that uses a model)

Inputs (and what is deliberately excluded) · what the AI decides · what code decides · output validation · fallback when it fails · how it's evaluated (labels independent of the system) · what's logged (no sensitive text) · cost/rate cap.

## Phase 1 — Planner: handoff to the Builder

One numbered handoff per batch of work (`HANDOFF_NN.md`; #00 = GitHub setup). Template:

```
# Handoff #NN — <goal>
From: Planner   Date:   Status: DRAFT | APPROVED (owner, date). Send after: <preconditions>

## Before you start (owner)
1. Specs approved (PRs merged): <list>
2. Copy into docs/product/: <files> (or already merged)
3. Paste the prompt below into the Builder.

## Goal — one or two sentences, measurable

## Prompt for the Builder
> Context. <what's done>. Ambition level: L<n> (D-001). Build in the order below, one PR per numbered step, each closing its task issue, with green CI and my explicit OK to commit. Specs: <paths>. Where a spec and the code disagree, tell me before building; real values win over examples.
> Order (deterministic first, AI on top):
> 1. TASK-ID (plain name) #issue: scope, key rules, acceptance tests = spec §n examples
> 2. …
> If time runs short, cut in this order: … Ask before cutting anything else.
> Ground rules: <standing rules above + project-specific ones>
> Report after each step with: test counts, type-check count, spec deviations, understanding check, exact manual test steps for me.

## What comes back to the Planner
After each step: deviations (for the decision log). After step X: <sample output for review>. After the last step: <end-to-end result>.
```

## Phase 2 — Builder: setup (Day 0)

Before any feature work (GitHub setup is Handoff #00 if not done yet):
1. **Git and secrets check:** repos, branches, remotes, uncommitted work (leave it untouched and report), confirm `.env`/keys are ignored with `git check-ignore`, scan history for leaked secrets without printing values.
2. **Backup and restore check** (if a database exists): dump the dev DB outside the repos, restore to a scratch DB, compare row counts and checksums, drop the scratch DB.
3. **Implementation plan:** task IDs (each with its issue number), order, dependencies, ground rules, acceptance tests per task. The owner approves each revision; archive superseded revisions.
4. **CI:** minimal GitHub Actions on push and PR (tests + type check) that needs no secrets: test signing keys, a fake AI client that refuses real calls in test.
5. **Level infra:** set up only what the current level's row requires (e.g. L1 adds error tracking and backups).
6. **Progress log:** start `PROGRESS.md`.

## Phase 3 — Builder: the per-task loop

For each task in the handoff's order:

1. **Branch from an up-to-date `main`:** `feature/<short-name>`, `fix/<short-name>`, `chore/<short-name>`, `docs/<short-name>`. One task per branch. An unrelated problem found mid-task gets its own `fix/` branch, issue and PR, merged first. Move the task issue to "In build".
2. **Read the spec.** If it conflicts with the code or is ambiguous, raise a PO-nn `question` issue with options and a recommendation before building.
3. **Build the deterministic parts first**, then AI on top. Migrations are additive with a tested rollback. Ownership: every query is scoped to the current user; another user's record → 404; add ownership-matrix test rows.
4. **Test:** the spec's worked examples as tests, hand-calculated cases, edge cases, ownership rows, then **mutation checks** (break the logic on purpose; every break must be caught).
5. **Log in `PROGRESS.md`** (template below) with the status "done, uncommitted".
6. **Report to the owner** (template below) and wait. Don't commit without an explicit OK.
7. **On OK:** commit, push, open the PR (template below, `Closes #task`), wait for green CI, and merge when the owner says so. Update the log entry to "merged", record the owner's approval line, and update `ARCHITECTURE.md` with what's now built.
8. **Hand deviations back** to the Planner for the decision log (a comment on the spec issue, plus the progress log).

### Commit message

```
TASK-ID (plain name): what it does, in plain words
```
e.g. `G2 (goal and debt maths): GoalCalculator and DebtCalculator`. The body covers why, notable choices and migration names, plus any attribution lines the environment requires. Docs PRs: `Docs: <doc> (<stage>)`.

### PROGRESS.md entry

```
### TASK-ID (plain name) #issue — done, uncommitted | merged (YYYY-MM-DD)
- Branch, base, migration(s) (additive; rollback tested). Details in ARCHITECTURE.md.
- Spec deviations / choices (for the decision log):
  1. <what> — <why> — <consequence>
- Tests: <file> (n: what they cover) … Suite **N pass**. Type check: N. Mutation checks (n) all caught.
- PO questions: PO-nn #issue …
- PO approval (YYYY-MM-DD): <what was approved, incl. which deviations>.
```

### Report to the owner (after every task)

1. What was built, in two or three sentences.
2. Spec deviations, numbered, each with its reason.
3. Test counts, type-check count, mutation checks.
4. **Understanding check:** the 2–3 files that hold the core logic, a plain-language walkthrough, and 3 questions the owner should be able to answer. The owner reads those files before approving.
5. Exact manual test steps (device/browser), including demo-data commands.
6. Open PO-nn questions and the decision needed to commit.

### Pull request description (`.github/PULL_REQUEST_TEMPLATE.md`)

```
## TASK-ID (plain name)
Implements <spec path §n> · Handoff #NN step n · Closes #<task issue>

### What
2–4 sentences, plain language.

### Why / decisions
- D-0nn …   - PO-nn answered: …

### Spec deviations
1. … (approved by owner, date)

### Core logic (read these)
- path/file — what it holds

### Tests
- Suite N pass · type check N · mutation checks n/n caught
- Spec worked examples covered: §n 1–9

### Migrations
- name — additive, rollback tested | none

### How to check manually
1. …

### Out of scope / follow-ups
- … (#issue)
```

Docs PRs use a short form: doc(s) changed · stage · issues closed · what the owner is approving.

### task.yml (one per task ID)

```
Title: TASK-ID (plain name)
Labels: task, milestone (M1/M2), area:*, type (feature/fix/chore)
Spec: docs/product/SPEC_X.md §n · Parent: P-n #   Ideas: I-nn · Handoff: #NN step n · Decisions: D-0nn
Goal: one sentence
Acceptance:
- [ ] Spec worked examples pass as tests
- [ ] Ownership-matrix rows added
- [ ] Mutation checks caught
- [ ] CI green
- [ ] Understanding check answered by owner
- [ ] ARCHITECTURE.md and PROGRESS.md updated
Depends on: #…
```

### bug.yml

```
Title: K-n (plain name)
Labels: bug, area:*
What happens · What should happen (spec §) · Steps (synthetic data only) · Severity · Fix in: task / own fix PR
```

## Phase 4 — Evals (for every AI feature)

- A golden set whose labels never come from the system's own output (generator-assigned, or hand-written before the first run). Easy set + hard set; mark ambiguous rows.
- Freeze rules and prompts while measuring (fingerprint them); use a fixed "today" date.
- Include an injection row (hostile text in user data).
- Report in `docs/evals/<feature>-YYYY-MM-DD.md`: run details, where the labels came from, a headline table (accuracy of auto-decided items, review rate, critical errors that must be 0, correct with no user action), a per-source breakdown, cost, failures with notes, and known issues for later (as issues).

## Phase 5 — Milestone close

- End-to-end check from a fresh database and demo reset, timed against the scope's target.
- An audit script that computes the same figures through every surface and fails if any differ.
- Fill the README with as-built facts, the level, and links to the design trail (Idea Card, decisions, specs, board); write a demo script.
- Close the GitHub milestone; move `later` ideas into the next milestone or leave them parked.
- Planner updates the decision log, glossary and scope, and writes the next handoff.

## Starting a new project with this workflow

1. Planner: set up the Claude Project → brain dump → Idea Card (approved).
2. Create the core repo; Handoff #00 (GitHub setup): templates, labels, milestones, board, pinned issues; idea issues created.
3. Planner, with a docs PR merged at each stage: ambition level (D-001) → constraints → brief + scope → backend shape → design inputs → screens (feasibility loop) → specs. The Builder creates task issues as each spec is approved.
4. Planner: write the first build handoff (audit or Day 0 setup). Builder: Day 0, implementation plan, CI.
5. Loop Phase 1 → Phase 3 per batch; run evals for AI features; close each milestone with Phase 5.
6. **Levelling up:** to move from L(n) to L(n+1), the Planner opens a `decision` issue and writes a level-up spec from the level table (new must-haves and infra changes). It's built as normal tasks, and the move is recorded as a new decision that supersedes D-001.
