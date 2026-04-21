# CRO Compliance Workspace — Production Integration

**Date:** 2026-04-21  
**Branch:** integration/next-phase  
**Final status:** 10/10 E2E tests passing

---

## Overview

Converted the CRO Compliance demo page from a hardcoded single-campaign prototype into a real multi-user, multi-campaign production workspace integrated with BioMate's authentication, sidebar navigation, chat assistant routing, and Nextflow ADMET pipeline.

---

## What Was Built

### 1. Multi-Campaign Registry (Backend)

**File:** `backend/lib/galaxy/ai/drug_discovery/api_router.py`

Added a global SQLite campaigns registry at `backend/database/campaigns_registry.db`.

```python
_CAMPAIGN_REGISTRY_DB = str(
    Path(__file__).parent.parent.parent.parent.parent / "database" / "campaigns_registry.db"
)

def _registry_conn():
    conn = sqlite3.connect(_CAMPAIGN_REGISTRY_DB)
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS campaigns (
            campaign_id TEXT PRIMARY KEY,
            user_id     TEXT NOT NULL DEFAULT '',
            molecule_name TEXT NOT NULL DEFAULT '',
            target      TEXT NOT NULL DEFAULT '',
            indication  TEXT NOT NULL DEFAULT '',
            sponsor     TEXT NOT NULL DEFAULT '',
            objective   TEXT NOT NULL DEFAULT 'balance',
            created_at  TEXT NOT NULL
        )
    """)
    conn.commit()
    return conn
```

Updated `create_campaign` (`POST /campaigns`) to `INSERT OR REPLACE` into the registry after provisioning the per-campaign DuckDB.

Added new `GET /campaigns?user_id=` endpoint:
```python
@router.get("/campaigns")
async def list_campaigns(user_id: str = Query("", ...)):
    conn = _registry_conn()
    rows = conn.execute(
        "SELECT * FROM campaigns WHERE user_id = ? ORDER BY created_at DESC",
        (user_id,)
    ).fetchall() if user_id else conn.execute(...).fetchall()
    return {"campaigns": [dict(r) for r in rows]}
```

### 2. Dynamic Campaign State (Frontend)

**File:** `frontend/client/src/pages/drug-discovery-cro-demo.tsx`

Replaced the module-level `CAMPAIGN_ID` / `CAMPAIGN_META` constants with React state:

```typescript
interface CampaignEntry {
  campaign_id: string; user_id: string; molecule_name: string;
  target: string; indication: string; sponsor: string;
  objective: string; created_at: string;
}

const [campaignId, setCampaignId] = useState<string | null>(null)
const [campaignMeta, setCampaignMeta] = useState<CampaignEntry | null>(null)
```

When `campaignId === null`, the page renders a **campaign list view** showing all campaigns for the logged-in user. Clicking a row opens the compliance dashboard for that campaign. A "New Campaign" button opens the `CampaignWizard` modal.

Key UX elements in list view:
- Campaign rows have `data-testid="campaign-row"` for E2E targeting
- Each row shows molecule name, campaign ID prefix, target, indication, created date
- Empty state is a dashed card with a `+` icon prompting the first campaign

### 3. Real User Identity

Changed `userId` to always use email (stable, matches what E2E tests send):

```typescript
// Before (broken):
const userId = user?.id ? String(user.id) : (user?.email ?? "demo-user")

// After (correct):
const userId = user?.email ?? "demo-user"
```

**Why this matters:** `user.id` is a numeric database row ID. E2E tests register/login with an email address and create campaigns tagged with that email. Using `user.id` caused a mismatch where the frontend fetched campaigns for `"1234"` but the backend had them stored under `"cro_e2e_test@biomate.test"`.

### 4. Sidebar Navigation

**File:** `frontend/client/src/components/app-sidebar.tsx`

Added CRO Compliance to the Quick Actions section:

```tsx
<Button variant="ghost" className="w-full justify-start"
  data-testid="button-cro-compliance"
  onClick={() => setLocation("/drug-discovery-cro")}
>
  <FlaskConical className="w-4 h-4 mr-2" />
  <span>CRO Compliance</span>
</Button>
```

### 5. Chat Assistant Routing

**File:** `frontend/server/galaxy-assistant.ts`

After `finalMessage` is assembled, CRO-related queries append a workspace link:

```typescript
const _isCroQuery = ['cro', 'compliance', 'ind assembly', '21 cfr', 'cfr part 11',
  'audit trail', 'esig', 'electronic signature', 'auto-retrain', 'dmta loop',
  'drug discovery campaign', 'ingest assay', 'cro order'].some(kw => _msgLower.includes(kw));
if (_isCroQuery && !finalMessage.includes('/drug-discovery-cro')) {
  finalMessage += '\n\n→ Open your [CRO Compliance workspace](/drug-discovery-cro) to manage campaigns, view the audit chain, and generate IND packages.';
}
```

### 6. DMTA Auto-Retrain Nextflow Wiring

**File:** `backend/lib/galaxy/ai/drug_discovery/api_router.py`

The `trigger_retrain_now` endpoint now fire-and-forgets a POST to the Nextflow executor for ADMET screening after GP refit. The `nf_run_id` is returned in the response if submission succeeds.

---

## E2E Test Updates

**File:** `frontend/e2e/cro-compliance.e2e.ts`

### New helpers

**`ensureTestCampaign(page)`** — creates a test campaign via `POST /api/drug-discovery/campaigns` (cached per test session in `_sharedCampaignId`):

```typescript
let _sharedCampaignId: string | null = null;

async function ensureTestCampaign(page: Page): Promise<string> {
  if (_sharedCampaignId) return _sharedCampaignId;
  const id = `cmp-e2e-egfr-${Date.now().toString(16)}`;
  await ctx.request.post(`${BASE_URL}/api/drug-discovery/campaigns`, {
    data: { campaign_id: id, user_id: EMAIL, molecule_name: "BMT-4451",
            target: "EGFR L858R", indication: "NSCLC", ... },
    headers: { "X-E2E-Test-Token": E2E_TOKEN },
  });
  _sharedCampaignId = id;
  return id;
}
```

**Updated `loadCroPage()`** — handles the list-first navigation:
```typescript
async function loadCroPage(page: Page) {
  await silentAuth(page);
  await ensureTestCampaign(page);
  await page.goto(`${BASE_URL}/drug-discovery-cro`);
  await page.waitForLoadState("load");

  const hasList = await page.locator('text=CRO Compliance Campaigns')
    .isVisible({ timeout: 10_000 }).catch(() => false);
  if (hasList) {
    await page.waitForSelector('[data-testid="campaign-row"]', { timeout: 20_000 });
    await page.locator('[data-testid="campaign-row"]').first().click({ timeout: 15_000 });
  }
  await page.waitForSelector('[data-testid="demo-campaign-id"]', { timeout: 30_000 });
}
```

**CRO-02 rewritten** — old test assumed localStorage persistence; now tests DB persistence (select → reload → re-select → same campaign ID).

---

## Bugs Found and Fixed

### Bug 1: `GET /campaigns` returned 404 after code was added

**Root cause:** The gunicorn backend was not reloaded after the new endpoint was added to `api_router.py`. gunicorn does not hot-reload by default.

**Fix:** `kill -HUP <master_pid>` triggers a graceful worker restart.

**Lesson:** When adding new FastAPI routes to the Galaxy backend, always `kill -HUP $(pgrep -f "gunicorn.*8081" | head -1)` after editing. The `POST /campaigns` route was already registered from an earlier deploy cycle, which is why it worked while `GET /campaigns` did not — they were added in separate sessions.

**Verification:**
```bash
curl http://localhost:8081/api/drug-discovery/campaigns?user_id=test
# Before HUP: 404 No route for /api/drug-discovery/campaigns
# After HUP:  {"campaigns": [...]}
```

### Bug 2: userId mismatch (user.id vs user.email)

**Root cause:** `useAuth()` returns a `User` object where `id` is the numeric SQLite row ID (e.g., `"42"`). E2E tests register users and tag campaigns with the email string. The frontend fetched campaigns for `"42"` but the registry had them under `"cro_e2e_test@biomate.test"`.

**Fix:** Changed `userId` to always use `user.email`.

**Lesson:** For user-scoped resources in multi-tenant systems, use a stable human-readable identifier (email) rather than an internal auto-increment ID. This makes debugging easier and avoids cross-system ID translation problems.

### Bug 3: CRO-02 stale test logic

**Root cause:** CRO-02 tested that the campaign ID survived a page reload, relying on the old `localStorage`-based persistence. The new architecture uses DB persistence with explicit list selection.

**Fix:** Rewrote CRO-02 to load a campaign via `loadCroPage`, reload, re-select from the list, and verify the same campaign ID appears.

**Lesson:** When replacing persistence mechanisms (localStorage → DB), test assertions for that mechanism must be updated to match the new model. The "what persists" is the same (campaign identity), but "how you observe it" changes.

### Bug 4: Campaign row locator brittleness

**Root cause:** Original E2E locator `button[class*="rounded-xl border"]` was brittle — CSS class order isn't guaranteed and it could match unintended elements.

**Fix:** Added `data-testid="campaign-row"` to the campaign button in the list, updated tests to use `[data-testid="campaign-row"]`.

**Lesson:** Always add `data-testid` attributes to key interactive elements at build time. CSS class selectors in E2E tests are fragile; semantic test IDs are not.

---

## Test Results

```
10 passed (1.2m)
```

| Test | Assertion | Screenshot |
|------|-----------|-----------|
| CRO-01 | Campaign header + 21 CFR Part 11 chip + Tutorial btn | CRO-01_dashboard_loaded.png |
| CRO-02 | Campaign ID same before/after reload (DB persistence) | CRO-02_campaign_persistent.png |
| CRO-03 | EMA 2-fold criterion banner + table ≥5 rows | CRO-03_validation_panel.png |
| CRO-04 | Audit chain verification badge visible | CRO-04_audit_chain.png |
| CRO-05 | Auto-Retrain loop: start → running → stop → stopped | CRO-05_retrain_stopped.png |
| CRO-06 | IND Generate button + post-generate state | CRO-06_ind_*.png |
| CRO-07 | Ingest Assay eSig modal: INGEST_ASSAY + 21 CFR cite | CRO-07_ingest_assay_modal.png |
| CRO-08 | Export CRO Order eSig + OTP input fill | CRO-08_export_modal_open.png |
| CRO-09 | Refresh button fetches compounds (table rows present) | CRO-09_refresh_compounds.png |
| CRO-10 | Tutorial tour all 10 steps complete | CRO-10_tour_complete.png |

---

## Architecture Notes

### Campaign ownership model
- Each campaign is tagged with `user_id = user.email` at creation time
- The list view fetches `GET /api/drug-discovery/campaigns?user_id=<email>` on mount
- No JWT enforcement at campaign level (MVP scope); access control deferred

### "All campaigns" breadcrumb
- Campaign header has an "← All campaigns" button that calls `setCampaignId(null)`
- This returns to the list view without a full page navigation
- The URL stays `/drug-discovery-cro` regardless of selected campaign (no URL-based campaign routing — deferred)

### E2E auth pattern
- `silentAuth` uses `page.context().request.post()` which shares the cookie jar with the browser
- E2E token `X-E2E-Test-Token: biomate-e2e-bypass-token-dev-only` bypasses rate limiting on register/login
- Campaign creation also uses the bypass token so tests don't hit per-user quotas

---

## Files Changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/ai/drug_discovery/api_router.py` | Added `_CAMPAIGN_REGISTRY_DB`, `_registry_conn()`, `GET /campaigns`, registry write in `create_campaign`, ADMET Nextflow wiring in `trigger_retrain_now` |
| `frontend/client/src/pages/drug-discovery-cro-demo.tsx` | Full multi-campaign refactor: `CampaignEntry` interface, list view, `fetchCampaigns()`, `openCampaign()`, `userId = user.email`, `data-testid="campaign-row"` |
| `frontend/client/src/components/app-sidebar.tsx` | Added CRO Compliance Quick Action button |
| `frontend/server/galaxy-assistant.ts` | CRO keyword routing block appends workspace link |
| `frontend/e2e/cro-compliance.e2e.ts` | `ensureTestCampaign`, updated `loadCroPage`, rewritten CRO-02, `data-testid` selectors |
