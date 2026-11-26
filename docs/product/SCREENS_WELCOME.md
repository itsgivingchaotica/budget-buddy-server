# Budget Buddy — C9 (welcome and account screens): build spec

**Status:** APPROVED by the product owner (2026-11-25). Decision: D-023 (welcome screen and log out). Brand: D-020 (Forest Floor palette, mascot update 2026-11-25).
**Build order:** after C2 (accounts and import screens) passes the owner's phone test; before or alongside C2b (review and transfer screens). Small task: a few hours.
**Design source:** canvas page "Welcome & account" (Option A and the account sheet). Reference screenshots: `docs/product/screens/Welcome-A.png`, `Account-Sheet.png`.

---

## 1. Purpose

Replace the old login screen (people illustration, bear-on-banknote, blue buttons) with a signed-out Welcome screen in the Forest Floor brand, and move Log out from the Home placeholder into an account sheet. Also ship the new mascot as the app icon, and brand Kinde's hosted sign-in pages to match.

## 2. Scope

| # | Item | In this task |
|---|---|---|
| 2.1 | Welcome screen (signed-out root) | Yes |
| 2.2 | Account sheet with Log out, opened from Home | Yes |
| 2.3 | New app icon from the mascot | Yes |
| 2.4 | Kinde hosted pages branding | Owner does it in the Kinde dashboard (§7); no code |
| — | Splash screen redesign, Terms/Privacy legal text, profile editing, account deletion | No (v1) |

## 3. Assets (files delivered with this spec)

| File | Put it in | Use |
|---|---|---|
| `assets/welcome-hero.svg` (390×420) | `bb-client/assets/brand/` | Top illustration on Welcome |
| `assets/mascot.svg` (200×200) | `bb-client/assets/brand/` | Reusable mascot (coach avatar, empty states later) |
| `assets/app-icon-1024.png` | `bb-client/assets/images/` | App icon (no transparency, iOS rounds the corners) |
| `assets/mascot-512.png` | Not in the repo | Logo for the Kinde dashboard (§7) |

**Rendering SVG:** use `react-native-svg` (install with `npx expo install` so the version matches SDK 54; it's a native module, so this needs one rebuild). Prefer `SvgXml` or a hand-converted `.tsx` component over adding an SVG transformer to Metro. If you'd rather avoid the native module now, export the hero to PNG at @2x/@3x instead and say so. Either is fine; report which.

**Old login images:** the people illustration and bear-on-banknote images become unused. Remove them from `assets/` (they are not legacy code); list the deleted files in your report.

## 4. Welcome screen

**Route:** the signed-out root (whatever the current login screen route is). Always light theme, like the rest of the app (LG1).

**Layout, top to bottom** (390-wide reference; scale with screen width):
1. **Hero illustration** `welcome-hero.svg`, full width, edge to edge, top of the screen under the status bar. Height ≈ 50% of the screen on a 844-pt phone; keep its aspect ratio. Its bottom edge is a curve into Birch, already in the artwork.
2. **Name**, left-aligned, 28 pt side padding: "Budget" on line 1 in Bark `#3A2A1E`, "Buddy" on line 2 in Acorn `#B5652E`. Bricolage Grotesque **ExtraBold (800)** if the installed font package includes it, otherwise Bold (700); 46/44 pt, letter spacing −1.
3. **Tagline**, Inter Regular 17/24, colour `#5B4A3C`: "Turn the bank exports you already have into a plan you can keep, one week at a time."
4. **Buttons**, pinned to the bottom with 40 pt bottom padding plus the safe area, 28 pt side padding, 12 pt gap:
   - **Sign in:** filled Pine `#2F5D46`, white Inter SemiBold 17, height 54, radius 14.
   - **Create an account:** Birch background, 2 pt Pine border, Pine text, same size.
5. **Legal line** under the buttons, 13/19 centred, `#5B4A3C`: "By continuing you agree to our **Terms** and **Privacy Policy**." The two words are Pine, SemiBold, underlined links (see §4.3).

On short screens (e.g. iPhone SE), the hero shrinks first; the name, tagline and buttons must never overlap or be cut off. Content scrolls if Dynamic Type makes it too tall.

### 4.1 Behaviour

| Action | Result |
|---|---|
| Sign in | Opens Kinde's hosted sign-in (existing `login()` flow). |
| Create an account | Opens Kinde's hosted sign-up (`register()`); if the SDK version only has `login()`, use that and say so. |
| Kinde returns successfully | Call `/me` (as today). Then: **zero accounts** → Activity tab (first run starts with adding an account, D-019); **one or more** → Home tab. |
| User cancels in Kinde | Back on Welcome, no error shown. |
| Kinde can't open / network error | Inline message above the buttons in Ember-dark `#A8432B`, 15 pt: "Couldn't open sign-in. Check your connection and try again." Buttons re-enabled. |
| While Kinde is opening | Both buttons disabled; the tapped one shows a small spinner in place of its label. No double-taps. |

### 4.2 Accessibility
- Hero image: `accessibilityLabel` "Illustration: the Budget Buddy squirrel standing on a tree stump next to a jar of saved acorns." Name is a header (`accessibilityRole="header"`), read as "Budget Buddy".
- Buttons have `accessibilityRole="button"`, minimum 44 pt touch target (they're 54).
- Contrast: Pine on Birch and white on Pine both pass AA for this text size; don't lighten them.

### 4.3 Terms and Privacy (MVP)
No legal documents yet. Each link opens a simple in-app text screen (modal, Birch, back button) with a short plain-language note. Privacy note content: the app uses fictional demo data in development; uploaded CSV files are read and not kept; your data is only visible to your account; sign-in is handled by Kinde. Terms note: "Budget Buddy is a portfolio project, not financial advice." Real legal text is v1.

## 5. Account sheet and Log out

**Entry point:** a 44×44 circle at the top right of the Home header, Pine background, white Inter SemiBold 16 initial of the user's first name (from `/me`; fall back to the email's first letter). `accessibilityLabel` "Account".

**Sheet** (bottom sheet over a 45% Bark scrim, Birch background, top radius 28, grab handle):
1. Avatar circle (56, Pine, initial), the user's name (Bricolage Bold 22) and email (Inter 15, `#5B4A3C`).
2. White grouped card (radius 18), rows 16 pt Inter with value on the right in `#5B4A3C`, read-only for MVP:
   - "Week starts on" → from the financial profile `week_starts_on` (1 → Monday, …).
   - "Time zone" → from the financial profile `time_zone`, shown as a city ("America/New_York" → "New York").
   - If the profile doesn't exist yet, show the defaults (Monday, device time zone) without creating it.
3. **Log out** button: Birch background, 2 pt Ember `#C0563A` border, text `#A8432B` SemiBold 17, height 54, radius 14.
4. Footer: "Budget Buddy {version} · sign-in by Kinde", 13 pt, centred. Version from the app config.

**Behaviour:**
- Log out: same logic as today (always clears the store, even if Kinde doesn't redirect back) → Welcome. No confirm dialog.
- Dismiss by swipe down, tapping the scrim, or the system back gesture.
- Use a lightweight sheet (React Native `Modal` with a slide-up animation is fine). Don't add a bottom-sheet library just for this; if you think one is needed, ask first.
- Remove the temporary **Log out** button from the Home placeholder.

## 6. App icon

- Set `icon` in the app config to `assets/images/app-icon-1024.png` (Pine background, mascot centred). Rebuild to see it on the phone.
- Leave the splash screen as is for now; if it's still the old artwork, set its background to Birch `#F6F1E7` and use `mascot.svg`/PNG centred, only if that's a config-only change.

## 7. Kinde hosted pages (owner task, no code)

In the Kinde dashboard → **Design** (or Branding): upload `mascot-512.png` as the logo, set the primary button colour to Pine `#2F5D46`, the background to Birch `#F6F1E7`, and the business name to "Budget Buddy". Claude Code: add a one-line note about this to `docs/PROGRESS.md` so it's in the demo checklist.

## 8. Acceptance checks (owner's phone)

1. Signed out, the app opens on Welcome: illustration, two-tone name, tagline, Pine Sign in, outlined Create an account, legal line. Light look even in Dark Mode.
2. Sign in → Kinde → back in the app → `/me` 200 in the Rails log → Home (demo user has accounts).
3. Create an account with a new email → Kinde sign-up → lands on the Activity tab with "Add your first account".
4. Cancel in Kinde → back on Welcome, no error.
5. Airplane mode → Sign in → the inline "Couldn't open sign-in" message appears; buttons usable again after.
6. Home shows the initial at the top right; tapping it opens the sheet with name, email, week start, time zone.
7. Log out → Welcome. Sign in again works.
8. Terms and Privacy open the in-app notes and close back to Welcome.
9. The home-screen icon is the new squirrel on Pine.
10. iPhone SE size (Simulator) and largest Dynamic Type: nothing overlaps or is cut off.

**Automated:** a test that the signed-out root renders both buttons and the legal links; a test of the post-login routing rule (0 accounts → Activity, ≥1 → Home); TypeScript error count must not rise.

## 9. Out of scope / later
Splash redesign, real Terms and Privacy text, editing week start or time zone (v1, D-010), account deletion, Sign in with Apple, Option B (dark "Buddy note") welcome variant.
