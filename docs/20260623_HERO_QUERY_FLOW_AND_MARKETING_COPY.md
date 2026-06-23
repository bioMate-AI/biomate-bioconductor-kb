# 2026-06-23 — Hero Query Flow Fix + Marketing Site Copy Update

## What was changed

### 1. Hero query flow — auth handoff fix

**Problem:** A user who types a query in the biomate.ai hero input and clicks "Start free" is redirected to `dev-public.biomate.ai/register?q=<query>`. The query was being lost in two paths:

- **Existing users** clicking "Sign in" on the register page: `setLocation('/login')` had no `?q=`, so the query was gone before login.
- **Race condition (safety net)**: If App.tsx's unauthenticated guard fired (`!isLoading && !isAuthenticated → setLocation('/login')`), the `initialMessage` captured in state was discarded.

**Fix — 3 files, commit `5b67ea929`:**

| File | Change |
|---|---|
| `frontend/client/src/pages/auth/register.tsx:535` | "Sign in" link now appends `?q=<pendingQuery>` when navigating to `/login` |
| `frontend/client/src/App.tsx:133` | Unauthenticated redirect preserves `initialMessage`: redirects to `/login?q=<initialMessage>` instead of bare `/login` |
| `frontend/client/src/pages/auth/login.tsx:36,53` | Reads `?q=` param; after successful login overrides auth-context's `setLocation('/')` with `setLocation('/?q=...')` |

**Auth flow after fix:**
```
biomate.ai hero → register?q=X
  ├─ new user:    register → /?q=X → App.tsx captures initialMessage → auto-submit ✓
  └─ existing:   "Sign in" → /login?q=X → login → /?q=X → auto-submit ✓
```

---

### 2. Hero input UI — inline layout

**Problem:** The hero form was a stacked textarea (3 rows, pre-filled placeholder) + two buttons below ("Start free" + "See what we do"). Cognitively heavy; button too far from input.

**Fix — `index.html`:**
- Replaced `<textarea rows="3">` with `<input type="text">` (single line)
- Removed the label "Input your use case here:"
- Moved "Start free →" button inline with the input using `display: flex; gap: 10px`
- Removed the competing "See what we do" secondary button from the form row
- Added `@media (max-width: 520px)` stack for mobile

New placeholder: `"Describe your analysis — RNA-seq, ADMET, variant calling…"`

---

### 3. Marketing site branding copy

**Problem:** BioMate was described inconsistently as "computational biology assistant", "agentic AI platform for biomedicine", etc. The correct positioning is: **agentic AI assistant for biomedical research**.

**Changes — `shell.js` + `index.html` visible copy:**

| Location | Old | New |
|---|---|---|
| `index.html <title>` | "Agentic AI Platform for Biomedicine" | "Agentic AI Assistant for Biomedical Research" |
| `index.html <h1>` | "…agentic AI assistant for biomedicine." | "…agentic AI assistant for biomedical research." |
| `shell.js` CTA bar (every page) | "The computational biology assistant for pharma, biotech, and academic labs." | "The agentic AI assistant for biomedical research." |
| `shell.js` footer brand | "Computational biology assistant for pharma, biotech, academic labs, and core facilities." | "Agentic AI assistant for biomedical research." |

SEO meta tags (`<meta name="description">`, `og:*`, `twitter:*`, `ld+json`) were intentionally left unchanged.

---

## Deployments

| Commit | What | When |
|---|---|---|
| `5b67ea929` | Auth query-flow fix (frontend only) | 2026-06-23 13:36 |
| marketing deploy | Hero UI + branding copy | 2026-06-23 14:29 / 14:35 |

---

## Open issues

- **Empty reply for new users (partially resolved):** The auth flow fix addresses the case where the query was lost before reaching the platform. If users still report empty replies after this fix, the next investigation point is the SSE parsing in `chat-with-artifacts.tsx` — the Gemini backbone sends no delta events, only a single `final` event with `data.response`; verify the client is reading that field correctly.
