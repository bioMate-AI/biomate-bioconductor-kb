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

### 4. sessionStorage race fix — empty chat after login

**Problem:** After the first fix, existing users going through register → "Sign in" → login still got an empty chat. Root cause: `auth-context.login()` calls `setLocation('/')` synchronously inside the `await login()` call, which mounts App.tsx at `/` (no `?q=`) before `login.tsx` can call its override `setLocation('/?q=...')`. The `useState` lazy initializer in App.tsx only runs once on mount, so `initialMessage` was always `undefined`.

**Fix — commit `a44b194c4`:**

| File | Change |
|---|---|
| `frontend/client/src/pages/auth/login.tsx` | Before calling `login()`, write `qParam` to `sessionStorage.setItem('pendingHeroQuery', qParam)`. On error, remove it. |
| `frontend/client/src/App.tsx` | `useState` initializer now checks `sessionStorage.getItem('pendingHeroQuery')` as fallback when no `?q=` in URL; removes key after consuming. |

The `?q=` override in `login.tsx` is still there as a belt-and-suspenders path (URL wins if present); sessionStorage is the fallback that survives the auth-context navigation race.

---

### 5. Workflow DB — replaced stale local with prod 304MB DB

**Problem:** The sync script pushes the local `backend/database/galaxy_ai_tools.db` to dev. The local file was a stale 279MB copy (2,617 workflows). The correct prod DB was at `/private/tmp/gat_prod_local.db` (304MB, 4,014 workflows, downloaded from prod June 22).

**Root cause of the mistake:** The sync script triggers DB push whenever `local_db_mtime > LAST_DB_SYNC`, which was true for the stale local file. The correct file was sitting in `/tmp` but not at the expected repo path.

**Fix:**
1. Extracted old local DB from `git show 440322e56:backend/database/galaxy_ai_tools.db` to compare
2. Copied `/private/tmp/gat_prod_local.db` → `backend/database/galaxy_ai_tools.db`
3. Re-ran 3 local addition scripts against the new base:
   - `backend/scripts/add_zhi_lab_chains.py` — skipped (already in prod)
   - `backend/scripts/add_zhao_lab_chains.py` — skipped (already in prod)
   - `backend/scripts/add_gwas_methods_chain.py` — added 3 workflows (`magma_gene_analysis`, `metal_meta_analysis`, `ldsc_heritability`) + `z01_gwas_methods_chain`
4. Pushed merged DB directly to dev via `scp` + `docker cp`

**Final state:** local + dev both at 304MB, 4,017 workflows, 67 chains.

**Prevention:** The canonical prod DB should be kept at `backend/database/galaxy_ai_tools.db`, not in `/tmp`. After pulling a fresh prod snapshot, immediately copy it to the repo path before running any sync.

---

### 6. MCP config — pointed at dev-public.biomate.ai

**Problem:** `.mcp.json` had `BIOMATE_API_URL: http://localhost:5000` — MCP tools were hitting the local server (not running) instead of dev.

**Fix:** Updated `.mcp.json` `BIOMATE_API_URL` to `https://dev-public.biomate.ai`. Requires Claude Code restart to take effect.

---

## Deployments

| Commit | What | When |
|---|---|---|
| `5b67ea929` | Auth query-flow fix (frontend only) | 2026-06-23 13:36 |
| marketing deploy | Hero UI + branding copy | 2026-06-23 14:29 / 14:35 |
| `a44b194c4` | sessionStorage race fix | 2026-06-23 15:43 |
| DB push (direct scp) | 304MB prod DB + GWAS additions | 2026-06-23 16:43 |

---

## Open issues

- **Hero query flow — needs live test:** The sessionStorage fix is deployed but not yet verified end-to-end by the user (MCP was pointing to localhost when test was attempted). Re-test after Claude Code restart with MCP pointing at dev-public.biomate.ai.
- **`lavaan` and `glmmTMB`** have no workflow or tool DB entries. Not needed now (BioMate's `run_code` handles ad-hoc R), but worth adding if SAS-migration use cases become common.
- **DB sync guard:** The sync script has no check to ensure the local DB is ≥ the dev DB size before pushing. Consider adding a size/count guard to prevent accidentally downgrading dev.
