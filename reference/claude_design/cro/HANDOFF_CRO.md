# BioMate CRO Compliance — Claude Code Handoff

Companion to `BioMate CRO Compliance.html`. Covers all 7 surfaces from
`uploads/20260420_CRO_COMPLIANCE_UX_REQUIREMENTS.md`.

---

## File Map

| Prototype file | Ports to |
|---|---|
| `BioMate CRO Compliance.html` | `frontend/client/src/pages/drug-discovery/` entry — wire into chat-message branch `workflow_type = 'drug_discovery_cro'` |
| `cro/tokens-cro.css` | Merge tokens into existing BioMate CSS vars; delete the duplicated base and keep only CRO-specific additions (reg-chip, audit-row, dmta, otp, contents-preview, callout) |
| `cro/primitives.jsx` | Replace with shadcn equivalents: `RegChip → Badge variant="outline" className="font-mono text-xs"`, `Chip → Badge`, `Callout → Alert`, `Collapsible → <Collapsible>`, `Modal → <Dialog>`, `Toast → useToast()` |
| `cro/CroIcon.jsx` | Delete; use `lucide-react` throughout |
| `cro/data-cro.js` | Delete; replaced by live API responses |
| `cro/Surface1_CampaignDashboard.jsx` | `drug-discovery-action.tsx` `dashboard` mode (enhanced) |
| `cro/Surface2_ValidationPanel.jsx` | `drug-discovery-validation-panel.tsx` (new) |
| `cro/Surface3_AuditTrail.jsx` | `drug-discovery-audit-viewer.tsx` (new) |
| `cro/Surface4_AutoRetrain.jsx` | `drug-discovery-auto-retrain.tsx` (new) |
| `cro/Surface5_EsigModal.jsx` | `drug-discovery-esig-modal.tsx` (new) |
| `cro/Surface6_IndAssembly.jsx` | `drug-discovery-ind-assembly.tsx` (new) |
| `cro/Surface7_CampaignWizard.jsx` | `drug-discovery-campaign-wizard.tsx` (new) |
| `cro/DrugDiscoveryAction.jsx` | Extend existing `drug-discovery-action.tsx` with the new `DrugDiscoveryMode` union + tab bar |
| `cro/Tour.jsx` + `cro/tour.css` | **Optional** — ships a 12-step spotlight tutorial. Intended for recording demos and first-run onboarding, not production. If porting: use `@reactour/tour` or `shepherd.js` instead of the handwritten SVG mask; keep the `data-tour="..."` anchors already on each surface (see §Tour anchors below) |

## Tab bar contract (`drug-discovery-action.tsx`)

```ts
type DrugDiscoveryMode =
  | 'assay-upload' | 'cro-export' | 'dashboard'       // existing
  | 'validation' | 'audit' | 'auto-retrain'
  | 'ind-assembly' | 'new-campaign';                  // new

const TABS = [
  { key: 'dashboard',    label: 'Dashboard',    icon: 'Target' },
  { key: 'validation',   label: 'Validation',   icon: 'Beaker' },
  { key: 'audit',        label: 'Audit',        icon: 'Shield', count: auditCount },
  { key: 'auto-retrain', label: 'Auto-Retrain', icon: 'RefreshCw', pulseWhenRunning: loopRunning },
  { key: 'ind-assembly', label: 'IND',          icon: 'FileText' },
];
```

Render tabs only when `campaign_id` is set. For `new-campaign`, render the wizard full-width without tabs.

## AI trigger → initial mode

| AI intent | Initial mode |
|---|---|
| "show my campaign" | `dashboard` |
| "validate the model" / "check EMA" | `validation` |
| "show audit trail" | `audit` |
| "auto-retrain status" / "propose next round" | `auto-retrain` |
| "generate IND" | `ind-assembly` |
| "new campaign" / "start drug discovery" | `new-campaign` |

Backend already returns `campaign_id` in the drug-discovery response payload — read it to pre-populate forms.

---

## API Contract (17 endpoints)

All under `/api/drug-discovery/`. JWT bearer auth. Regulated endpoints (marked 🔒)
append to the audit log automatically via `Depends(_audit_fn)` and require eSig
when `BIOMATE_ESIG_REQUIRED=1`.

### Surface 1 — Campaign Dashboard

**GET** `/{campaign_id}/compounds`
```ts
Response = {
  compounds: {
    compound_id: string; rank: number; composite_score: number;
    ad_status: 'in_domain' | 'out_of_domain';
    round_proposed: number;
  }[];
  campaign_round: number;
  total_compounds: number;
  last_updated: string; // ISO 8601
  dmta_state: {
    design:  { status: 'pending'|'active'|'done'; ts: string|null };
    make:    { ... }; test: { ... }; analyse: { ... };
  };
}
```

### Surface 2 — Validation

**GET** `/model-validation?model=pbpk&format=json|md|pdf`
```ts
ValidationReport = {
  generated_at: string;
  model: string;
  criterion_met: { cmax: boolean; auc: boolean };
  metrics: {
    cmax: { afe: number; aafe: number; r2: number; within2: number; within3: number };
    auc:  { same shape };
  };
  drugs: {
    name: string; obs_cmax: number; pred_cmax: number;
    fold: number; ad: 'in_domain'|'out_of_domain';
    excluded?: boolean; exclusion_reason?: string;
  }[];
  n_excluded: number;
}
```

**POST** `/model-validation` — trigger re-run; returns `ValidationReport`.

### Surface 3 — Audit 🔒

**GET** `/audit?resource_id={id}&limit=10&offset=0&user=&action=&from=&to=`
```ts
{ records: AuditRecord[]; total: number; }

AuditRecord = {
  id: number; ts: string;
  who: string; kind: 'user'|'system'|'esig';
  action: 'INGEST_ASSAY'|'VALIDATE_MODEL'|'PROPOSE_ROUND'|'EXPORT_CRO_ORDER'|'ESIG'|...;
  resource: string;
  payload_sha256: string;  // hex, 64 chars
  record_hash: string;     // hex, 64 chars
  prev_hash: string;       // '0000...' for genesis
  detail?: string;
  // Only for kind='esig':
  meaning?: string; sig_id?: string;
};
```

**GET** `/audit/verify` → `{ valid: boolean; verified_at: string; broken_at?: number; total_records: number; }`

**GET** `/audit/export?campaign_id={id}&format=csv|json` — file download.

### Surface 4 — Auto-Retrain 🔒

**GET** `/{id}/retrain/status` → `{ running: boolean; check_interval_s: number; last_retrain_at: string|null; next_check_in_s: number; last_trigger: 'manual'|'auto_retrain'|null }`

**POST** `/{id}/retrain/start` → `{ running: true }`

**POST** `/{id}/retrain/stop` → `{ running: false }`

**POST** `/{id}/retrain/trigger` 🔒 — force manual retrain; returns new `Proposal`.

**GET** `/{id}/auto-proposal?format=json|csv`
```ts
Proposal = {
  round: number; generated_at: string; trigger: 'manual'|'auto_retrain';
  items: {
    rank: number; smiles: string; score: number;
    ci_lo: number; ci_hi: number;
    ad: 'in_domain'|'out_of_domain';
  }[];
}
```

**GET** `/{id}/proposals` → `{ history: { round, ts, n, trigger }[] }`

**GET** `/{id}/virtual-library` → `{ n: number; saved_at: string; hash: string; n_propose: number; diversity_weight: number }`

**POST** `/{id}/virtual-library` 🔒
```ts
{ smiles: string[]; n_propose: number; diversity_weight: number }
→ { n_valid: number; n_invalid: number; hash: string }
```

### Surface 5 — eSig 🔒

**POST** `/esig/register` → `{ secret_b32: string; qr_uri: string }` (call only if user not enrolled)

**POST** `/esig/sign`
```ts
{ user_id: string; action: string; meaning: string; totp_token: string; payload_sha256: string }
→ { sig_id: string; signed_at: string; record_hash: string } | 401 { error: 'invalid_totp'|'replay_detected'|'expired' }
```

### Surface 6 — IND 🔒

**POST** `/{id}/ind-assembly`
```ts
{ molecule_name, target_name, indication, sponsor }
→ AssemblyResult = {
  markdown_path: string; docx_path?: string;
  sections: { id: string; title: string; status: 'ok'|'warn'|'err'; meta: string }[];
  warnings: string[]; pandoc_available: boolean;
  generated_at: string;
}
```

**GET** `/{id}/ind-assembly/download?format=md|docx` — file download.

### Surface 7 — Campaigns 🔒

**POST** `/campaigns`
```ts
{ campaign_id?, molecule_name, target_name, indication, objective: 'potency'|'admet'|'balance', virtual_library_smiles: string[] }
→ { campaign_id: string; created_at: string }
```

After creation, frontend calls in order:
1. `POST /model-validation` (blocking, shown with progress bar in wizard step 3)
2. `POST /{id}/virtual-library`
3. `POST /{id}/retrain/start`

---

## State Machine (per surface)

### Audit
`loading → { valid | tampered | empty } → viewing-record`
- `tampered` triggered by `GET /audit/verify` returning `valid: false`
- Show `broken_at` record # in red chip; disable export; surface admin-contact CTA

### Auto-Retrain
`no-library → library-uploaded → { stopped | running } → { running+retraining | running+idle }`
- Loop enters `running+retraining` on countdown=0; back to `idle` after response lands
- Polling: `GET /{id}/retrain/status` every 5s while mounted; debounce on tab blur

### eSig
`idle → checking → { error | success }` with auto-clear + countdown reset at `now % 30 === 0`
- `error` state persists 1.5s then back to `idle`
- `success` state closes modal after 700ms; parent resumes the gated action

### IND
`fresh → { generating → generated } → { regenerating (confirm) → generating → generated }`

### Wizard
`step-1 (blocked until valid) → step-2 (blocked until file parsed) → step-3 (validation runs async) → launch`

---

## Security notes (don't forget)

- **TOTP secret** is returned once on `POST /esig/register` — never again. Show "save to authenticator" UI immediately and don't store on client.
- **Hash chain** verification runs on every audit mount — cache the result for 30s to avoid re-hashing on tab switch.
- **Regulated actions** (🔒) are blocked at the backend by the `Depends(_audit_fn)` + eSig check. Frontend should show the eSig modal *before* firing the request; the backend rejection is the fallback, not the UX.
- **Audit row expansion** should NOT re-fetch; full hashes are already in the initial response payload.

---

## Tour anchors (optional, for tutorial port)

The prototype ships a 12-step tutorial triggered from the **Tutorial** button in the top nav. Steps are defined in `cro/Tour.jsx` as `TOUR_STEPS`, each with a `target: '[data-tour="..."]'` selector and a `setup(knobs)` function that flips the UI into the right state (tab + validation/audit/loop state) before the step shows.

Anchors currently placed on surfaces:

| Anchor | Surface | Element |
|---|---|---|
| `tabs-bar` | DrugDiscoveryAction | Tab strip |
| `dmta-stepper` | Surface 1 | DMTA loop progress |
| `dashboard-actions` | Surface 1 | Ingest Assay + Export CRO Order buttons |
| `validation-callout` | Surface 2 | EMA pass/fail banner |
| `audit-list` | Surface 3 | Full audit records list |
| `loop-strip` | Surface 4 | Auto-retrain status strip |
| `ind-generate` | Surface 6 | Generate IND Package button |
| `esig-btn` | DrugDiscoveryAction | e-Sig top-right button |
| `new-campaign-btn` | DrugDiscoveryAction | New campaign button |

**When porting:** keep these `data-tour` attributes (they're harmless in production) and wire them to whatever tour library the BioMate app already uses. The `setup()` functions translate 1:1 to imperative tab/state transitions — just call the existing navigation + state setters instead of `setKnobs`.

If no tour is desired in production, delete `cro/Tour.jsx` + `cro/tour.css` and the `<button className="tut-btn">` in the top-nav shell; the `data-tour` attributes can stay.

---

## Porting order (matches spec priority)

1. **P0** — Surface 3 (Audit) + Surface 4 (Auto-Retrain): unblocks 21 CFR Part 11 demo and the core DMTA loop.
2. **P1** — Surface 2 (Validation) + Surface 6 (IND): revenue-generating.
3. **P2** — Surface 1 (enhanced Dashboard) + Surface 7 (Wizard): UX polish.
4. **P3** — Surface 5 (eSig): only when `BIOMATE_ESIG_REQUIRED=1`.

## E2E test IDs (match spec)

`DD-CRO-1` through `DD-CRO-7` — see spec §"E2E Test Plan". Add `data-testid` on:
- `ema-criterion-banner` (Surface 2)
- `chain-validity-badge`, `audit-export-button` (Surface 3)
- `loop-status-badge`, `trigger-retrain-button`, `copy-smiles-button`, `download-csv-button` (Surface 4)
- `ind-generate-button`, `ind-download-md`, `ind-download-docx` (Surface 6)
- `wizard-step-{1|2|3}`, `wizard-launch-button` (Surface 7)
- `esig-otp-input`, `esig-sign-button` (Surface 5)

---

## Known prototype simplifications (fix on port)

- Mock data in `cro/data-cro.js` — 10-compound TOP list, 31-drug validation set, 10 audit records. Real pages use paginated responses.
- `QrMock` draws a deterministic SVG pattern, not a real QR. Replace with `qrcode.react` fed from `qr_uri`.
- Dropzone in wizard is a click-trigger — wire to real `<input type="file">` with FileReader + client-side SMILES parse.
- Audit date-range filter is a static `<select>`; replace with date picker.
- Loop countdown is UI-only; real version should reconcile with `next_check_in_s` from status poll.
- "Trigger retrain now" simulates with `setTimeout`; real version awaits `POST /retrain/trigger`.
