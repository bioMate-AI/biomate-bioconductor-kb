# BioMate CRO Compliance Suite — Use Cases & E2E Test Specification
**Date:** 2026-04-21  
**Page:** `/drug-discovery-cro`

---

## Use Cases

### UC-CRO-01: Campaign Persistence Across Page Reloads
**Actor:** CRO user  
**Goal:** Return to the same campaign after refreshing the browser.  
**Flow:**
1. Load `/drug-discovery-cro` — campaign is created and stored in `localStorage`.
2. Reload page — same `CAMPAIGN_ID` is used, no new campaign created.  
**Assertions:**
- Campaign ID in header does NOT change on reload.
- Setup API is NOT called again if ID already stored.

---

### UC-CRO-02: DMTA Stepper Reflects Live Retrain State
**Actor:** Auto-retrain loop  
**Goal:** The DMTA stepper updates when the loop starts/stops.  
**Flow:**
1. Load page — loop is stopped → Make = active (static baseline).
2. Start the auto-retrain loop via the Auto-Retrain tab.
3. Return to Dashboard — Make node shows "running" pulse.
4. Stop the loop.
5. Dashboard — Make node returns to baseline.  
**Assertions:**
- When retrain is running → Make shows `animate-pulse` blue indicator.
- When retrain stopped → Make shows static active state.

---

### UC-CRO-03: Compound Rankings Fetched from Real API
**Actor:** CRO user  
**Goal:** Top Compounds table loads real backend data (falling back to demo data if empty).  
**Flow:**
1. Load page — fetch `GET /api/drug-discovery/:id/compounds`.
2. If API returns compounds, render them; otherwise render `DEMO_COMPOUNDS`.
3. "Refresh" button re-fetches.  
**Assertions:**
- Table has ≥1 rows.
- Refresh button triggers a new fetch (spinner visible briefly).

---

### UC-CRO-04: Ingest Assay — E-sig Protected File Upload
**Actor:** Lab scientist  
**Goal:** Upload CSV/TSV assay data behind a 21 CFR Part 11 signature.  
**Flow:**
1. Click "Ingest New Assay Results" — eSig modal opens (action=INGEST_ASSAY).
2. Enter valid TOTP code → modal shows Success → closes.
3. Audit trail receives a new INGEST_ASSAY record.
4. Top Compounds table refreshes.  
**Assertions:**
- `data-testid="esig-modal"` is visible after click.
- Action label shows "INGEST_ASSAY".
- After sign, toast "Signed · INGEST_ASSAY recorded to audit trail" appears.
- Audit tab count increments by 1.

---

### UC-CRO-05: Export CRO Order — E-sig + Download
**Actor:** CRO liaison  
**Goal:** Generate and download a CRO order package after signing.  
**Flow:**
1. Click "Export CRO Order" — eSig modal opens (action=EXPORT_CRO_ORDER).
2. Sign with TOTP → file download is triggered via `GET /api/drug-discovery/:id/export/cro-order`.
3. Toast confirms.  
**Assertions:**
- eSig modal shows action = "EXPORT_CRO_ORDER".
- After sign, `<a download>` is clicked programmatically or a new tab opens.
- Toast with "Export downloaded" appears.

---

### UC-CRO-06: Model Validation Panel — EMA Criterion Display
**Actor:** Regulatory scientist  
**Goal:** View PBPK validation report with EMA 2-fold pass/fail.  
**Flow:**
1. Click "Validation" tab — panel loads.
2. Banner shows "EMA 2-FOLD CRITERION MET" (green) or "FAILED" (red).
3. Per-compound table shows ≥ 20 rows.
4. "Re-run" button works.
5. "JSON" download returns HTTP 200.  
**Assertions:**
- `data-tour="validation-callout"` exists.
- Banner contains "EMA 2-FOLD CRITERION".
- Table has ≥ 10 compound rows.

---

### UC-CRO-07: Audit Trail — 21 CFR Part 11 Hash Chain
**Actor:** QA/Regulatory  
**Goal:** View tamper-evident audit records with SHA-256 chain verification.  
**Flow:**
1. Click "Audit" tab.
2. Header shows "Chain: VALID" badge.
3. Records show timestamp, user, action, hash, prev-hash.
4. Export CSV returns a file.  
**Assertions:**
- `data-tour="audit-list"` has ≥ 1 record rows.
- "Chain: VALID" text visible.
- Export CSV button triggers download.

---

### UC-CRO-08: Auto-Retrain Loop — Start / Stop / Trigger
**Actor:** ML engineer  
**Goal:** Control the auto-retrain loop and see its state.  
**Flow:**
1. Click "Auto-Retrain" tab.
2. Status shows "STOPPED".
3. Click "Start" → status becomes "RUNNING".
4. Click "Trigger now" → new proposal appears in history.
5. Click "Stop" → status returns "STOPPED".  
**Assertions:**
- `data-tour="loop-strip"` exists.
- After Start: status text = "RUNNING".
- After Stop: status text = "STOPPED".

---

### UC-CRO-09: IND Section Assembly — One-Click §2.6.1
**Actor:** Regulatory affairs  
**Goal:** Generate IND Nonclinical Overview from campaign data.  
**Flow:**
1. Click "IND" tab — form shows campaign details pre-filled.
2. Click "Generate IND Package".
3. Spinner appears; 6 CTD sections appear on success.
4. Download Markdown → HTTP 200.
5. Download DOCX → HTTP 200 (if pandoc available).  
**Assertions:**
- `data-tour="ind-generate"` exists.
- After generate: "§2.6.1.1 Primary Pharmacodynamics" heading visible.
- Download button returns non-empty response.

---

### UC-CRO-10: Electronic Signature — Real TOTP Enrollment + Verification
**Actor:** Any user  
**Goal:** Real TOTP enrollment (not hardcoded 123456 bypass).  
**Flow:**
1. On page load, user is auto-enrolled if not yet registered.
2. Open eSig modal for any action.
3. Enter wrong code → error state, "Invalid code. Try again."
4. Enter correct TOTP code → success.  
**Assertions:**
- Wrong code → `data-testid="esig-error"` visible.
- Correct code → `data-testid="esig-success"` visible within 2s.
- Backend `POST /esig/sign` returns `{ sig_id: <uuid> }`.

---

## E2E Test Plan (Playwright)

Tests live in `e2e/cro-compliance.e2e.ts`.

| Test ID | Description | Critical |
|---------|-------------|----------|
| CRO-01 | Page loads directly, shows campaign header | YES |
| CRO-02 | Campaign ID persists on reload | YES |
| CRO-03 | Validation tab shows EMA criterion banner | YES |
| CRO-04 | Audit tab shows hash chain records | YES |
| CRO-05 | Auto-Retrain tab — start/stop loop | YES |
| CRO-06 | IND tab — generate IND sections | YES |
| CRO-07 | Ingest Assay opens eSig modal | YES |
| CRO-08 | Export CRO Order opens eSig modal | YES |
| CRO-09 | Dashboard refresh re-fetches compounds | NO |
| CRO-10 | Tutorial tour — 10 steps, all spotlights found | NO |
