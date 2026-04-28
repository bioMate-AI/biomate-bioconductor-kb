# Onboarding Welcome Screen

Date: 2026-04-16

## What Was Built

The `OnboardingWelcome` component is a 2-step inline onboarding flow rendered inside
`/home/yzhang/biomate/frontend/client/src/components/chat-interface.tsx` (lines ~74–308).
It appears in place of the empty chat area for every new user (zero messages, no prior
onboarding completion flag).

The component imports `DOMAIN_TAXONOMY` and `DOMAIN_LABELS` from
`client/src/components/domain-profile-selector.tsx`, which defines all 14 research domains.

---

## Design: 2-Step Flow

### Step 1 — Domain Selection (`step === "domains"`)

- Header: "What would you like to analyze?"
- 14 domain buttons rendered in a 2-column grid. Each button has:
  - `data-testid="onboarding-domain-btn-{key}"` (e.g. `onboarding-domain-btn-genomics`)
  - A checkbox-style indicator showing selection state
  - The human-readable label from `DOMAIN_LABELS`
- Multi-select: clicking any button toggles it; any number of domains may be selected.
- "Other domain" free-text input: accepts comma-separated custom domains not in the taxonomy.
- Footer row:
  - Selection count badge (e.g. "2 selected")
  - "Skip" ghost button — immediately closes welcome without saving
  - "Continue" primary button — **disabled** until at least one domain is selected or the
    "Other domain" field is non-empty. Clicking advances to Step 2.

The 14 domain keys (in taxonomy order):

| Key | Label |
|-----|-------|
| `genomics` | Genomics |
| `transcriptomics` | Transcriptomics |
| `single_cell` | Single Cell |
| `epigenomics` | Epigenomics |
| `proteomics` | Proteomics |
| `metabolomics` | Metabolomics |
| `metagenomics` | Metagenomics |
| `structural_biology` | Structural Biology |
| `drug_discovery` | Drug Discovery |
| `cryo_em` | Cryo-EM |
| `pharmacology` | Pharmacology |
| `systems_biology` | Systems Biology |
| `synthetic_biology` | Synthetic Biology |
| `bioimaging` | Bioimaging |

### Step 2 — Topic Selection (`step === "topics"`)

- Header: "Which topics interest you?"
- For each selected domain, renders:
  - A section heading showing `DOMAIN_LABELS[domainKey]` (uppercase, muted)
  - Clickable pill buttons for each topic in `DOMAIN_TAXONOMY[domainKey]`
  - A per-domain "Other topics" free-text input (comma-separated)
- If the user typed a custom domain in Step 1, an extra "Other: {customDomain}" section is shown.
- Scrollable content area (max-height 50vh) to handle many domains.
- Footer row:
  - "Back" ghost button — returns to Step 1
  - "Next — Enter BioMate" primary button — saves profile and closes welcome

---

## State Management

Defined in `ChatInterface` component body (line ~364):

```tsx
const [onboardingDone, setOnboardingDone] = useState(() =>
  typeof window !== 'undefined' && localStorage.getItem(ONBOARDING_DONE_KEY) === '1'
)
```

- `ONBOARDING_DONE_KEY = 'biomate_onboarding_done'` (defined at module scope, line ~82)
- Initialized from `localStorage` so the state survives page reloads within the same browser.
- `OnboardingWelcome` renders when `!onboardingDone && displayMessages.length === 0`.
- `onComplete` callback (passed from `ChatInterface`): calls `setOnboardingDone(true)`.

Both exit paths write the flag:
- **Skip** (Step 1 footer): `localStorage.setItem(ONBOARDING_DONE_KEY, '1')` then `onComplete()`
- **Next** (Step 2 footer, `handleNext`): saves profile to API, then `localStorage.setItem(...)`
  then `onComplete()`

---

## API Integration

`handleNext` (async, inside `OnboardingWelcome`) makes a best-effort POST:

```ts
await fetch('/api/user/domain-profile', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  credentials: 'include',
  body: JSON.stringify({ domains: allDomains, topics: allTopics }),
})
```

- `allDomains` = selected taxonomy keys + any comma-split values from the "Other domain" field.
- `allTopics` = selected taxonomy topics + comma-split values from all per-domain "Other" fields.
- The `try/catch` swallows errors — a failed API call never blocks the user from entering the app.
- `setSaving(true)` / `setSaving(false)` prevents double-submit; a spinner is shown on the button
  while the request is in-flight.

---

## data-testid Reference

| Selector | Element |
|----------|---------|
| `onboarding-welcome` | Root `<div>` of the component (present on both steps) |
| `onboarding-domain-btn-{key}` | Individual domain toggle button in Step 1 |
| `onboarding-starter-prompt` | Deferred — see Verified Queries section below |

---

## Session 6 Test Compatibility

The existing S6-1 through S6-4 tests in
`frontend/e2e/session6-production.e2e.ts` still apply:

- **S6-1** — `onboarding-welcome` visible for new user with 0 messages ✓
- **S6-2** — checks 5 domain buttons by key (`genomics`, `drug_discovery`, `cryo_em`,
  `proteomics`, `single_cell`) ✓
- **S6-3** — expects `onboarding-starter-prompt` elements after clicking a domain (currently
  deferred; test may fail until verified queries are integrated — see below)
- **S6-4** — clicking a starter prompt hides the welcome screen (same deferral caveat)

---

## Verified Queries (Deferred)

Starter/suggested queries shown after domain selection are **not yet live** in the component.
They are planned to come from:

```
backend/experiments/verified_queries/
```

Run `verify_queries.py` in that directory to validate query quality before integration.
Until then, `data-testid="onboarding-starter-prompt"` elements will not appear in the DOM,
and S6-3 / S6-4 will fail when the prompts panel is not rendered.

---

## Known Limitation

`biomate_onboarding_done` is stored in **browser-local storage**, not server-side per user.

- The welcome shows **once per browser profile**, regardless of which account is logged in.
- If a user clears browser data or logs in from a new device, the welcome reappears.
- Fix (future): persist the flag via `POST /api/user/domain-profile` and read it back on
  `/api/users/me` so the flag is user-scoped and synced across devices.
