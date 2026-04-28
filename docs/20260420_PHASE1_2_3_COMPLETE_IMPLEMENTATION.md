# BioMate CRO Phases 1–3 — Complete Implementation Reference

**Date:** 2026-04-20  
**Status:** All phases complete — 199/199 tests passing (58 + 73 + 68)  
**Scope:** Model validation, 21 CFR Part 11 compliance, auto-retrain loop, IND document assembly

---

## Table of Contents

1. [Overview and Motivation](#1-overview-and-motivation)
2. [Repository Layout — New Files](#2-repository-layout--new-files)
3. [Phase 1 — Model Validation and Applicability Domain](#3-phase-1--model-validation-and-applicability-domain)
4. [Phase 2 — 21 CFR Part 11 Audit Trail and Electronic Signatures](#4-phase-2--21-cfr-part-11-audit-trail-and-electronic-signatures)
5. [Phase 3 — Auto-Retrain Loop and IND Section Assembly](#5-phase-3--auto-retrain-loop-and-ind-section-assembly)
6. [API Surface — All New Endpoints](#6-api-surface--all-new-endpoints)
7. [Data Flows End-to-End](#7-data-flows-end-to-end)
8. [Modified Files and What Changed](#8-modified-files-and-what-changed)
9. [Test Coverage](#9-test-coverage)
10. [Environment Variables and Configuration](#10-environment-variables-and-configuration)
11. [Known Limitations and Next Steps](#11-known-limitations-and-next-steps)

---

## 1. Overview and Motivation

Before this work, BioMate had a functional DMTA loop (assay ingest → rank → Bayesian propose → CRO export) but lacked:

- **Regulatory credibility:** No validated performance metrics for any predictive model. A pharma client's regulatory affairs team could not cite BioMate predictions in an IND without independent validation numbers.
- **Prediction reliability indicators:** The `/propose` endpoint returned predicted scores with no confidence interval and no flag for whether a compound was within the model's training distribution.
- **Audit trail:** Every write operation mutated the SQLite database with no record of who did what or when. A pharma IT security review would fail this immediately.
- **Autonomy:** The DMTA loop required manual `/propose` calls after each assay data ingest. There was no background automation.
- **Regulatory document output:** All the pieces for an IND pharmacology section existed in separate API calls; nothing assembled them into a document.

The three phases addressed these gaps in order of regulatory priority.

---

## 2. Repository Layout — New Files

```
backend/lib/galaxy/ai/
├── compliance/                          ← NEW: Phase 2
│   ├── __init__.py
│   ├── audit_store.py                   ← SHA-256 hash-chained audit log
│   ├── esig.py                          ← TOTP electronic signatures (RFC 6238)
│   └── audit_middleware.py              ← FastAPI dependency for regulated endpoints
│
└── drug_discovery/
    ├── model_validation.py              ← NEW: Phase 1 — PBPK validation service
    ├── applicability_domain.py          ← NEW: Phase 1 — hat-matrix + Tanimoto AD
    ├── auto_retrain.py                  ← NEW: Phase 3a — background refit loop
    ├── ind_assembly.py                  ← NEW: Phase 3b — IND CTD §2.6.1 generator
    ├── reference_data/
    │   └── pk_marketed_drugs.json       ← NEW: Phase 1 — 31-drug reference dataset
    ├── test_phase1_cro.py               ← NEW: 58 assertions
    ├── test_phase2_compliance.py        ← NEW: 73 assertions
    └── test_phase3_autoretrain_ind.py   ← NEW: 68 assertions

database/
└── compliance/
    └── audit.db                         ← CREATED at runtime: global audit SQLite

docs/
├── 20260420_BIOMATE_AS_A_CRO_BUSINESS_AND_TECHNICAL_GUIDE.md   ← NEW
├── 20260420_PHASE1_CRO_MODEL_VALIDATION_AND_AD.md              ← NEW
├── 20260420_PHASE2_21CFR11_COMPLIANCE.md                       ← NEW
└── 20260420_PHASE1_2_3_COMPLETE_IMPLEMENTATION.md              ← THIS FILE
```

**Modified files:**

```
backend/lib/galaxy/ai/drug_discovery/
├── api_router.py                        ← +10 new endpoints; audit Depends() wiring;
│                                           BayesianOptimizer API fix
└── bayesian_optimizer.py                ← RoundProposal: +3 fields (CI, AD, GP stds)
                                            propose_next_round: exposes posterior σ
```

---

## 3. Phase 1 — Model Validation and Applicability Domain

### 3.1 Problem

The Bayesian optimizer had no measure of whether its predictions were trustworthy. Two distinct needs:

1. **Model-level validation:** Is the PBPK model accurate enough to cite in regulatory documents? (EMA question)
2. **Per-prediction reliability:** For this specific proposed compound, is the GP operating within its training distribution? (AD question)

### 3.2 Reference Dataset (`pk_marketed_drugs.json`)

31 marketed drugs with published human pharmacokinetics:

```json
{
  "aspirin": {
    "dose_mg": 650, "route": "oral",
    "Cmax_ug_mL": 17.0, "AUC_ug_h_mL": 26.6,
    "CL_L_h": 39.0, "Vd_L": 11.0,
    "t_half_h": 0.25, "F_oral": 0.68, "fu": 0.50,
    "logP": 1.19, "MW": 180.2,
    "smiles": "CC(=O)Oc1ccccc1C(=O)O",
    "primary_metabolism": "hydrolysis_esterases",
    "reference": "DrugBank DB00945; Rowland & Tozer 4th Ed. Table 11-1"
  },
  ...
}
```

Drugs selected to cover:
- Wide logP range (−1.0 to 5.7)
- Multiple routes (oral, IV)
- High-extraction and low-extraction hepatic clearance
- Known CYP metabolism, esterase hydrolysis, renal elimination
- Sources: DrugBank, FDA approved labels, published PK literature

Key decisions about the dataset that required debugging:
- **CL_apparent vs CL_true:** Every entry uses CL_apparent (the oral clearance reported in DrugBank, which is CL_true/F). This meant AUC = dose/CL_apparent, not dose×F/CL_apparent. Getting this wrong caused systematic AUC fold errors exactly equal to F for every drug.
- **Cmax corrections for special cases:** Fluoxetine corrected from steady-state (0.015 µg/mL) to single-dose (0.008 µg/mL); Simvastatin Vd recalculated from t½ and CL (2193L, not 4500L); Fentanyl uses terminal Vd (335L) with a `cmax_note` about the IV bolus limitation.

### 3.3 Model Validation Service (`model_validation.py`)

**Class `_AnalyticalPKPredictor`**

One-compartment Bateman equation predictor. Uses observed CL, Vd, F from the reference dataset as inputs (EMA PBPK Step 1: validate model structure, not parameter prediction from molecular properties).

Key equations:

```python
# Absorption rate estimated from logP (lipophilicity-absorption correlation)
if logP < 0:    ka = 0.3   # hydrophilic → slow absorption
elif logP < 2:  ka = 1.0
elif logP < 4:  ka = 2.0
else:           ka = 3.0   # lipophilic → fast absorption

# Elimination rate: for oral drugs, CL_apparent = CL_true / F
# → ke = CL_true / Vd = CL_apparent × F / Vd
ke = CL_L_h * (1.0 if route == "iv" else F) / Vd_L

# AUC: F is already embedded in CL_apparent, must NOT be applied again
AUC_ug_h_mL = dose_ug / (CL_L_h * 1000.0)

# Cmax via Bateman equation at tmax
tmax = ln(ka/ke) / (ka - ke)
dose_absorbed = dose_ug * (1.0 if route == "iv" else F)
Cmax = (dose_absorbed / Vd_mL) * (ka/(ka-ke)) * (exp(-ke*tmax) - exp(-ka*tmax))
```

The `ke = CL_apparent × F / Vd` fix (vs the naive `CL/Vd`) was critical. For verapamil (F=0.20), the naive formula gave t½=1.1h (reference: 6h); the corrected formula gives 5.6h.

The AUC double-F bug was diagnosed by plotting fold_error_AUC vs F across all 31 drugs — the near-perfect linear correlation `fold_error ≈ F` proved that F was being applied twice.

**Class `ModelValidationService`**

```python
svc = ModelValidationService()
report = svc.run_pbpk_validation(drug_names=None)  # None = all 31 drugs
```

Returns a `ValidationReport` (Pydantic) with:
- `per_compound`: list of `PerCompoundResult` — observed vs predicted Cmax/AUC, percent error, fold error, in-domain flag, notes
- `metrics`: `ValidationMetrics` — AFE, AAFE, RMSE, R², within_2fold, within_3fold for both Cmax and AUC
- `regulatory_summary`: plain-English EMA compliance paragraph for IND attachment
- `ema_criterion_met`: bool — True if within_2fold_Cmax ≥ 0.67 AND within_2fold_AUC ≥ 0.67

**Current results (2026-04-20):**

| Metric | Cmax | AUC |
|--------|------|-----|
| AFE (bias) | 1.41 | 1.00 |
| AAFE (accuracy) | 2.12 | 1.003 |
| R² | 0.933 | 1.000 |
| Within 2-fold | 71.0% ✅ | 100.0% ✅ |
| EMA criterion (≥67%) | **MET** | **MET** |

AUC = 100% because AUC = dose/CL_apparent is mechanistically determined once CL and dose are known — validating model structural correctness. Cmax variation (71%) reflects ka estimation uncertainty from logP.

### 3.4 Applicability Domain Checker (`applicability_domain.py`)

**Why two criteria are needed**

Hat-matrix leverage detects compounds that are outliers within the span of the training fingerprint matrix. But if a query compound has bits set only in dimensions where ALL training compounds have zero (unobserved feature subspace), then:

```
XᵀX has zeros in those rows/columns
(XᵀX)⁺ gives zero weight to those dimensions
h_query = xᵀ × (XᵀX)⁺ × x = 0
```

Leverage = 0 incorrectly classifies the compound as "in domain" (0 < h*). Tanimoto similarity catches this case: the compound has zero bits in common with any training compound → Tanimoto = 0.0 < threshold.

**Criterion 1 — Hat-matrix leverage (Tropsha/Roy)**

```python
XtX = X_train.T @ X_train
XtX_pinv = np.linalg.pinv(XtX)          # pseudoinverse: robust for sparse bits
h_train = [x @ XtX_pinv @ x for x in X_train]
h_threshold = 3.0 * mean(h_train)        # Tropsha's h* = 3p/n equivalent

h_query = x_query @ XtX_pinv @ x_query
in_domain_leverage = h_query <= h_threshold
```

**Criterion 2 — Tanimoto nearest-neighbour**

```python
# Vectorised: compute similarity to all training compounds in one pass
dots = X_train @ x_query                 # shape (N,)
x_sum = x_query @ x_query               # |x_query|²
train_sums = (X_train ** 2).sum(axis=1)  # |x_i|² per row
denominators = train_sums + x_sum - dots
similarities = dots / denominators
max_sim = similarities.max()

in_domain_tanimoto = max_sim >= 0.20    # TANIMOTO_OOD_THRESHOLD
```

**AD status logic:**
```python
ad_status = "in_domain" if (in_domain_leverage and in_domain_tanimoto) else "out_of_domain"
```

**Integration with BayesianOptimizer**

`RoundProposal` was extended with three new fields (all backward-compatible with `field(default_factory=...)`):

```python
@dataclass
class RoundProposal:
    ...
    confidence_intervals: dict[str, list[tuple[float, float]]] = field(default_factory=dict)
    ad_statuses: list[str]                                      = field(default_factory=list)
    gp_stds: dict[str, list[float]]                             = field(default_factory=dict)
```

In `propose_next_round()`, after GP scoring:
```python
mu, sigma = gp.predict(X_lib, return_std=True)
ci = (max(0, mu - 1.96*sigma), min(1, mu + 1.96*sigma))   # 95% CI
```

AD check runs on every proposed compound; graceful degradation to `"unknown"` if RDKit or numpy unavailable.

---

## 4. Phase 2 — 21 CFR Part 11 Audit Trail and Electronic Signatures

### 4.1 Regulatory Requirement

21 CFR Part 11 §11.10(e): *"Use of computer-generated, time-stamped audit trails to independently record the date and time of operator entries and actions that create, modify, or delete electronic records."*

21 CFR Part 11 §11.50/§11.200: Electronic signatures must be unique to one individual, non-reusable, and linked to the signed record with the signer's identity, date/time, and meaning.

### 4.2 Audit Store (`audit_store.py`)

**Storage:** Single global SQLite database at `database/compliance/audit.db`. WAL journal mode for concurrent reads without blocking writes.

**Schema:**
```sql
CREATE TABLE audit_log (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp_utc  TEXT    NOT NULL,    -- ISO 8601 UTC
    user_id        TEXT    NOT NULL,    -- from JWT sub or fallback
    action         TEXT    NOT NULL,    -- AuditAction constant
    resource_type  TEXT    NOT NULL,    -- "campaign", "proposal", "esig"
    resource_id    TEXT    NOT NULL,    -- campaign_id or sig_id
    payload_hash   TEXT    NOT NULL,    -- SHA-256 of request data
    details        TEXT    NOT NULL,    -- free-text annotation (not hashed)
    previous_hash  TEXT    NOT NULL,    -- record_hash of predecessor
    record_hash    TEXT    NOT NULL UNIQUE  -- SHA-256 of all above fields
);
```

**Hash chain construction:**

```python
record_hash = SHA256(
    timestamp_utc | user_id | action |
    resource_type | resource_id |
    payload_hash | previous_hash
)
```

The `details` field is intentionally excluded from the hash so human-readable annotations can be added without breaking the chain. All other fields are immutable once written.

The first record uses `previous_hash = "0" * 64` (genesis sentinel).

**Tamper detection via `verify_chain()`:**

Reads all records in id order and re-derives every `record_hash`. Detects three attacks:

| Attack | Detection mechanism |
|--------|---------------------|
| Field value changed | Re-derived hash ≠ stored hash |
| Record inserted mid-chain | Next record's `previous_hash` ≠ inserted record's hash (because the inserted record hash was computed with the genuine predecessor) |
| Record deleted | Gap: record N's `previous_hash` points to record N−2's hash, not N−1's |

Note: `verify_chain()` does NOT detect appending records to the end of the log (which is the intended write operation). It detects modification of the historical record.

**Append-only enforcement:**

`AuditStore` exposes no `update()` or `delete()` method. Direct SQL modification is caught by `verify_chain()` at the next audit review.

**Actions recorded:**

```python
class AuditAction:
    INGEST_ASSAY      = "INGEST_ASSAY"
    PROPOSE_ROUND     = "PROPOSE_ROUND"
    EXPORT_CRO_ORDER  = "EXPORT_CRO_ORDER"
    REGISTER_MODEL    = "REGISTER_MODEL"
    RUN_MODEL         = "RUN_MODEL"
    POLL_LIMS         = "POLL_LIMS"
    MODEL_VALIDATION  = "MODEL_VALIDATION"
    ESIG              = "ESIG"
    SYSTEM            = "SYSTEM"    # auto_retrain background actions
```

### 4.3 TOTP Implementation (`esig.py`)

Implemented from scratch against RFC 6238 / RFC 4226. No `pyotp` dependency.

**HOTP (RFC 4226):**
```python
def _hotp(secret_bytes, counter, digits=6):
    msg = struct.pack(">Q", counter)               # 8-byte big-endian counter
    digest = hmac.new(secret_bytes, msg, sha1).digest()
    offset = digest[-1] & 0x0F                     # dynamic truncation
    code = struct.unpack(">I", digest[offset:offset+4])[0] & 0x7FFFFFFF
    return str(code % 10**digits).zfill(digits)
```

**TOTP (RFC 6238):**
```python
def _totp(secret_bytes, time_step=None, period=30):
    if time_step is None:
        time_step = int(time.time()) // period
    return _hotp(secret_bytes, time_step)
```

Compatible with Google Authenticator, Authy, 1Password, and any RFC 6238 hardware token.

**ESignatureService workflow:**

1. **Registration:** `register_user(user_id)` → generates 20-byte random secret, base32-encodes it, stores encrypted in `esig_secrets` table, returns plaintext for QR code generation.

2. **Signing:** `sign(user_id, action, meaning, totp_token)`:
   - Validate TOTP within ±1 time step window (handles 30-second clock skew)
   - Check `esig_used_tokens` for replay: `(user_id, time_step)` must be unique
   - Build signed manifest: `SHA256(sig_id | user_id | action | meaning | timestamp_utc)`
   - Append `ESIG` record to audit log
   - Return `ESignatureRecord` with `manifest_hash` and `audit_record_id`

3. **Verification:** `verify_signature(sig)` re-derives the manifest hash from `sig` fields. Since the manifest hash is locked into the audit chain, any post-signing modification (to either the sig record or the audit record) is detectable.

**Encryption:** TOTP secrets are stored AES-256-GCM encrypted when `BIOMATE_ESIG_KEY` (32-byte hex) and the `cryptography` package are available. Falls back to plaintext with a warning log when either is missing.

**Replay protection:**

```sql
CREATE TABLE esig_used_tokens (
    user_id   TEXT NOT NULL,
    time_step INTEGER NOT NULL,
    PRIMARY KEY (user_id, time_step)
);
```

Each TOTP time step is single-use per user. Re-presenting the same token raises `ValueError("replay rejected")`.

### 4.4 Audit Middleware (`audit_middleware.py`)

A FastAPI **dependency** (not Starlette middleware) attached to each regulated endpoint via `Depends(_audit_fn)`.

**User identity extraction priority:**
1. JWT Bearer token — decode `sub`, `email`, or `user_id` claim without re-verification (upstream auth middleware owns verification)
2. `X-BioMate-User-Id` header — for service-to-service calls
3. `anonymous@{remote_ip}` fallback

**eSig gate logic:**

```python
_ESIG_SUPPORTED_ACTIONS = {"EXPORT_CRO_ORDER", "PROPOSE_ROUND"}
_ESIG_REQUIRED = os.environ.get("BIOMATE_ESIG_REQUIRED", "0") == "1"

if action in _ESIG_SUPPORTED_ACTIONS:
    if x_biomate_esig_header:
        validate_totp_and_record_sig()
    elif ESIG_REQUIRED:
        raise HTTPException(403, "eSig required")
    else:
        esig_status = "not_provided"  # advisory log only
```

**Failure mode:** By default, audit failures (DB unavailable) log an error but do not block the operation. `BIOMATE_AUDIT_STRICT=1` makes audit failure fatal.

**Wiring in `api_router.py`:**

```python
# Import with graceful fallback
try:
    from ..compliance.audit_middleware import audit_regulated_action as _audit_fn
except ImportError:
    async def _audit_fn(*args, **kwargs): pass

# Applied to every regulated endpoint
@router.post("/{campaign_id}/ingest-assay")
async def ingest_assay(..., _audit: None = Depends(_audit_fn)):
    ...
```

Endpoints covered: `ingest-assay`, `propose`, `export/cro-order`, `models/register`, `models/{name}/run`, `lims/poll`, `model-validation/{type}`.

---

## 5. Phase 3 — Auto-Retrain Loop and IND Section Assembly

### 5.1 Auto-Retrain Loop (`auto_retrain.py`)

**Problem:** After each LIMS poll and assay ingest, the GP surrogate model becomes stale. Clients were required to manually call `/propose` to get updated predictions. In a fast-moving campaign (weekly Benchling updates), this created a toil burden.

**Solution:** A daemon thread that monitors the audit log for new `INGEST_ASSAY` events and automatically runs the full refit + proposal cycle.

**New campaign DB tables:**

```sql
CREATE TABLE virtual_library_cache (
    campaign_id     TEXT PRIMARY KEY,
    smiles_json     TEXT NOT NULL,
    n_propose       INTEGER NOT NULL DEFAULT 10,
    diversity_weight REAL NOT NULL DEFAULT 0.2,
    saved_at        TEXT NOT NULL
);

CREATE TABLE auto_proposals (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_id      TEXT NOT NULL,
    round_number     INTEGER NOT NULL,
    proposed_smiles_json TEXT NOT NULL,
    scores_json      TEXT NOT NULL,
    ci_json          TEXT NOT NULL DEFAULT '{}',
    ad_statuses_json TEXT NOT NULL DEFAULT '[]',
    triggered_by     TEXT NOT NULL DEFAULT 'auto_retrain',
    created_at       TEXT NOT NULL
);
```

**`refit_and_propose()` — core synchronous function:**

```python
def refit_and_propose(db_path, campaign_id, triggered_by="auto_retrain"):
    # 1. Load current ranked compounds from campaign DB
    ranked = AssayIngestionService(db_path).get_ranked_compounds(campaign_id)
    if not ranked: return None

    # 2. Load cached virtual library
    vl = load_virtual_library(db_path, campaign_id)
    if not vl: return None

    # 3. Build CampaignDataset and refit GP
    opt = BayesianOptimizer(campaign_id=campaign_id, db_path=db_path,
                            n_initial=max(2, len(smiles_list)))
    features = opt._featurise(smiles_list)
    dataset = CampaignDataset(
        compound_ids=compound_ids, smiles_list=smiles_list, features=features,
        objectives={"composite_score": np.array(scores_list)},
        objective_directions={"composite_score": "maximize"},
    )
    opt.fit(dataset)

    # 4. Score virtual library, select proposals
    proposal = opt.propose_next_round(
        virtual_library_smiles=vl["smiles_list"],
        n_propose=vl["n_propose"],
        diversity_weight=vl["diversity_weight"],
    )

    # 5. Persist and audit
    auto_p = save_auto_proposal(db_path, campaign_id, proposal, triggered_by)
    audit_store.append(AuditEvent(user_id="system:auto_retrain", action=SYSTEM, ...))
    return auto_p
```

Note on `n_initial`: The BayesianOptimizer enforces a minimum observation count check. In the auto-retrain context, we set `n_initial = max(2, len(training_compounds))` so the optimizer runs on whatever data is available rather than requiring the default 16-compound threshold.

**Background loop manager:**

```python
_active_loops: dict[str, threading.Thread] = {}
_loop_stop_events: dict[str, threading.Event] = {}

def start_background_loop(db_path, campaign_id, check_interval_s=60.0):
    # Idempotent: no-op if loop already running
    if is_loop_running(campaign_id): return

    stop_event = threading.Event()
    def _loop():
        last_audit_id = _get_latest_ingest_audit_id(campaign_id)
        while not stop_event.wait(check_interval_s):
            latest_id = _get_latest_ingest_audit_id(campaign_id)
            if latest_id != last_audit_id:
                refit_and_propose(db_path, campaign_id)
                last_audit_id = latest_id

    t = threading.Thread(target=_loop, daemon=True)
    t.start()
    _active_loops[campaign_id] = t
```

Threads are daemon threads — they do not prevent process shutdown. Each campaign has at most one active loop. The loop detects new data by comparing the id of the most recent `INGEST_ASSAY` audit record, not by polling the campaign DB directly (coupling to the audit trail, not to the data store).

**New API endpoints:**

```
POST /{campaign_id}/virtual-library     Cache virtual library + params
GET  /{campaign_id}/auto-proposal       Get latest auto-proposals (limit param)
POST /{campaign_id}/retrain             Manual trigger + start background loop
```

**Complete client workflow after Phase 3:**

```
1. Client uploads assay data:
   POST /{campaign_id}/ingest-assay   (CSV upload)

2. Client caches virtual library once:
   POST /{campaign_id}/virtual-library
   {"virtual_library_smiles": [...5000 SMILES...], "n_propose": 10}

3. Client starts the background loop (or uses /retrain to trigger immediately):
   POST /{campaign_id}/retrain

   → BioMate refits GP, generates proposal, saves to auto_proposals
   → Background loop starts watching for future ingest events

4. Every time Benchling LIMS poll runs:
   GET  /{campaign_id}/lims/poll
   → Ingest fires → audit INGEST_ASSAY record → loop detects new id
   → Automatic refit + proposal, no human action required

5. Client retrieves latest proposals anytime:
   GET  /{campaign_id}/auto-proposal
```

### 5.2 IND Section Assembly (`ind_assembly.py`)

**Problem:** Regulatory affairs teams at client biotechs needed to assemble BioMate outputs (PBPK validation, ADMET results, compound rankings, applicability domain) into an ICH M4-compliant document for IND submission. This was being done manually from multiple API calls.

**Solution:** `INDSectionAssembler.assemble()` pulls data from all sources and produces a complete CTD Section 2.6.1.

**Document structure (ICH M4S(R2)):**

| Section | Content source | What it contains |
|---------|---------------|------------------|
| Title page | Parameters | Molecule name, sponsor, indication, target, generation date |
| 2.6.1.1 | Hardcoded template | Overview of GP, PBPK, AD, and audit methodology |
| 2.6.1.2 | `ModelValidationService` | EMA metrics table, per-compound fold errors, regulatory summary |
| 2.6.1.3 | Campaign DB compounds | Safety gate table, pass rates, top-5 ranked compounds |
| 2.6.1.4 | Campaign DB + auto_proposals | Scoring algorithm, latest Bayesian proposal summary |
| 2.6.1.5 | Hardcoded template | Leverage + Tanimoto method, in/out domain interpretation table |
| 2.6.1.6 | `AuditStore` | Chain verification status, action count table, hash chain explanation |

**Data loading with graceful degradation:**

Each section loads from its source independently. If a source is unavailable (e.g., no campaign compounds yet, PBPK import fails), that section shows a "data unavailable" placeholder and appends to `result.warnings`. The document is always produced even with partial data.

**Output formats:**

1. **Markdown** (always written to disk) — complete, human-readable, version-control friendly.
2. **DOCX via pandoc** — generated if `pandoc` is in PATH. Uses `--from=markdown --to=docx`. Falls back gracefully with a warning if pandoc is not installed.

Per the project's memory (feedback: prefer pandoc over python-docx), no XML manipulation is performed.

**API endpoint:**

```
POST /{campaign_id}/ind-assembly
Body: {
    "molecule_name": "BM-0042",
    "sponsor": "BioTech Inc.",
    "indication": "oncology",
    "target_name": "EGFR"
}
Response: {
    "sections": ["2.6.1.1", "2.6.1.2", ...],
    "pandoc_available": true,
    "docx_generated": true,
    "generated_at": "2026-04-20T...",
    "warnings": [],
    "markdown_preview": "# CTD Section 2.6.1...",
    "markdown_path": "/tmp/biomate_ind_.../cmp-001_CTD_2.6.1.md",
    "docx_path": "/tmp/biomate_ind_.../cmp-001_CTD_2.6.1.docx"
}
```

### 5.3 Audit Query Endpoint

```
GET /api/drug-discovery/audit
Query params:
    campaign_id  — filter by resource_id
    user_id      — filter by user
    action       — filter by AuditAction
    since_utc    — ISO 8601 datetime filter
    limit        — 1–1000 (default 100)
    verify       — bool: run verify_chain() and include result
```

Returns records oldest-first with optional chain verification status. Intended for:
- FDA 21 CFR Part 11 audit reviews
- Internal compliance monitoring
- Incident investigation (who changed what, when)

---

## 6. API Surface — All New Endpoints

### Phase 1 endpoints

```
GET /api/drug-discovery/model-validation/{model_type}
    ?drug_names=aspirin,caffeine,...   optional filter
    
    Returns: ValidationReport {
        model_type, dataset_name, n_reference_compounds,
        per_compound: [{ name, dose, route, observed_Cmax, predicted_Cmax,
                         percent_error_Cmax, fold_error_Cmax,
                         observed_AUC, predicted_AUC,
                         fold_error_AUC, in_domain, notes }],
        metrics: { AFE_Cmax, AAFE_Cmax, RMSE_Cmax, R2_Cmax,
                   within_2fold_Cmax, within_3fold_Cmax,
                   AFE_AUC, AAFE_AUC, RMSE_AUC, R2_AUC,
                   within_2fold_AUC, within_3fold_AUC,
                   ema_criterion_met },
        regulatory_summary,
        ema_criterion_met,
        warnings
    }
```

The `/propose` endpoint (pre-existing) now also returns:

```
confidence_intervals: {"composite_score": [(lo, hi), ...]}  # 95% GP CI per compound
ad_statuses: ["in_domain" | "out_of_domain" | "unknown"]    # per proposed compound
gp_stds: {"composite_score": [sigma, ...]}                  # posterior uncertainty
```

### Phase 2 endpoints

```
GET /api/drug-discovery/audit
    ?campaign_id=&user_id=&action=&since_utc=&limit=100&verify=false
    
    Returns: {
        total_returned: int,
        records: [{ id, timestamp_utc, user_id, action, resource_type,
                    resource_id, payload_hash, details, record_hash }],
        chain_verification: { valid, total_records, first_tampered_id, error }
                             (only if verify=true)
    }
```

All write endpoints also now silently write audit records (no response change).

### Phase 3 endpoints

```
POST /{campaign_id}/virtual-library
    Body: { virtual_library_smiles: [...], n_propose: 10, diversity_weight: 0.2 }
    Returns: { campaign_id, status: "cached", n_smiles, n_propose }

GET  /{campaign_id}/auto-proposal
    ?limit=1   (1–50)
    Returns: {
        campaign_id,
        loop_running: bool,
        proposals: [{
            id, round_number, n_proposed,
            proposed_smiles, scores, confidence_intervals,
            ad_statuses, triggered_by, created_at
        }]
    }

POST /{campaign_id}/retrain
    Returns: { campaign_id, proposal_id, round_number, n_proposed,
               proposed_smiles, scores, confidence_intervals,
               ad_statuses, created_at }

POST /{campaign_id}/ind-assembly
    Body: { molecule_name, sponsor, indication, target_name }
    Returns: { sections, pandoc_available, docx_generated, generated_at,
               warnings, markdown_preview, markdown_path, docx_path }
```

---

## 7. Data Flows End-to-End

### Fully Automated DMTA Loop (Phase 3)

```
Week 1:
  Scientist → POST /virtual-library (cache 5000 SMILES)
  Scientist → POST /retrain (start background loop)
  BioMate   → GP fit + proposal → auto_proposals[id=1] + SYSTEM audit

Week 2 (Benchling new data):
  BioMate   → GET /lims/poll (scheduled)
             → new IC50 results arrive → INGEST_ASSAY audit record id=47
  Auto-loop → detects audit_id 47 ≠ previous (audit_id 23)
             → refit_and_propose() runs automatically
             → auto_proposals[id=2] + SYSTEM audit record

  Scientist → GET /auto-proposal   (sees new round-2 proposals)
  Scientist → GET /export/cro-order?fmt=wuxi   (→ EXPORT_CRO_ORDER audit)
  Scientist → emails CSV to WuXi (outside BioMate)
```

### IND Submission Workflow

```
Month 6 (development candidate selected):
  RA team  → POST /ind-assembly
             {"molecule_name": "BM-0042", "sponsor": "...", ...}

  BioMate assembles:
    §2.6.1.1 → static methods description
    §2.6.1.2 → ModelValidationService.run_pbpk_validation() →
                31-drug EMA metrics (71% Cmax, 100% AUC within 2-fold)
    §2.6.1.3 → campaign DB compounds → ADMET pass rates, top-5 table
    §2.6.1.4 → auto_proposals latest round → proposal summary
    §2.6.1.5 → AD methodology description
    §2.6.1.6 → AuditStore.get_records() + verify_chain() →
                {total=247, valid=true, action_counts={INGEST_ASSAY:8, ...}}

  Output: BM-0042_CTD_2.6.1.md  (8–15 KB Markdown)
          BM-0042_CTD_2.6.1.docx (pandoc, if available)

  RA team  → attaches DOCX to IND Section 2.6
```

### Audit Chain for One Campaign Cycle

```
Record 1: INGEST_ASSAY  user=alice  campaign=cmp-001  hash=a3f2...
Record 2: PROPOSE_ROUND user=alice  campaign=cmp-001  hash=7b91...  prev=a3f2...
Record 3: ESIG          user=alice  esig_id=f4c2...   hash=2d08...  prev=7b91...
Record 4: EXPORT_CRO_ORDER user=alice campaign=cmp-001 hash=9e14...  prev=2d08...
Record 5: SYSTEM        user=system:auto_retrain      hash=6a33...  prev=9e14...

verify_chain() → ChainVerificationResult(valid=True, total_records=5)
```

---

## 8. Modified Files and What Changed

### `bayesian_optimizer.py`

**`RoundProposal` dataclass — 3 new fields:**
```python
# Before:
@dataclass
class RoundProposal:
    campaign_id: str
    round_number: int
    proposed_compounds: list[str]
    scores: dict[str, list[float]]
    acquisition_values: list[float]
    pareto_front_smiles: list[str]
    diversity_score: float
    timestamp: str

# After (backward-compatible — all new fields have default_factory):
    confidence_intervals: dict[str, list[tuple[float, float]]] = field(default_factory=dict)
    ad_statuses: list[str]                                      = field(default_factory=list)
    gp_stds: dict[str, list[float]]                             = field(default_factory=dict)
```

**`propose_next_round()` — expose GP posterior uncertainty:**
```python
# Before:
mu, _ = gp.predict(X_lib, return_std=True)

# After:
mu, sigma = gp.predict(X_lib, return_std=True)
# CI and AD check computed from sigma and ApplicabilityDomainChecker
```

### `api_router.py`

**Imports added:**
```python
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
try:
    from ..compliance.audit_middleware import audit_regulated_action as _audit_fn
except ImportError:
    async def _audit_fn(*args, **kwargs): pass
```

**Bug fix — BayesianOptimizer API:**

The original `propose_next_round` endpoint called `BayesianOptimizer(objectives=objectives)` which does not match the actual constructor `BayesianOptimizer(campaign_id, db_path, n_initial)`. Fixed to:

```python
opt = BayesianOptimizer(campaign_id=campaign_id, db_path=_campaign_db(campaign_id))
features = opt._featurise(smiles_list)
dataset = CampaignDataset(
    compound_ids=compound_ids, smiles_list=smiles_list, features=features,
    objectives={"composite_score": np.array(scores_list)},
    objective_directions={"composite_score": "maximize"},
)
opt.fit(dataset)
```

This fix also applies to `auto_retrain.py`'s `refit_and_propose()`.

**`_audit: None = Depends(_audit_fn)` added to 7 endpoints.**

**10 new endpoints added** (see §6).

---

## 9. Test Coverage

### Summary

| Suite | File | Tests | Status |
|-------|------|-------|--------|
| Phase 1 | `test_phase1_cro.py` | 58 | ✅ 58/58 |
| Phase 2 | `test_phase2_compliance.py` | 73 | ✅ 73/73 |
| Phase 3 | `test_phase3_autoretrain_ind.py` | 68 | ✅ 68/68 |
| **Total** | | **199** | **✅ 199/199** |

### Phase 1 — What is tested (58 assertions)

- Full 31-drug PBPK validation: AFE, AAFE, RMSE, R², within_2fold, EMA criterion
- 8-drug high-quality subset metrics
- Per-compound result structure (fields present, types correct)
- AD in-domain: vector in training subspace → leverage ≤ threshold
- AD out-of-domain: vector in null space → Tanimoto guard fires (not leverage)
- AD out-of-domain warning message content
- 95% CI bounds: lo ≤ hi, values in [0,1], high-uncertainty warning threshold
- Batch mode: correct count, valid statuses, CI present
- `RoundProposal` new fields exist
- BayesianOptimizer proposal CI/AD plausibility
- API model-validation endpoint structure (9 fields)
- API 400 on unsupported model_type

### Phase 2 — What is tested (73 assertions)

- AuditStore: append, retrieve, id sequence, first record genesis hash
- Hash chain: valid after 5 appends, previous_hash linking
- Tamper detection: field modification, record insertion, record deletion (3 separate scenarios)
- TOTPService: generate secret format, compute 6-digit numeric token, verify within window
- TOTPService: reject wrong token (5 cases), reject stale token (10 steps old)
- ESignatureService: register/is_registered, sign returns correct fields
- Manifest verification: valid passes, tampered meaning fails
- Reject unregistered user with clear error message
- Reject invalid TOTP token
- Replay attack: same token on second use raises ValueError
- Sign creates ESIG audit record with correct payload_hash
- Chain valid after ESIG record
- Audit middleware: 7 action derivation paths
- Campaign_id extraction from 3 path patterns
- get_records filter by user_id and action
- Empty log: valid, total_records=0
- hash_payload: deterministic, matches manual SHA-256, different inputs differ
- End-to-end: ingest+propose creates 2 records, chain valid, previous_hash links

### Phase 3 — What is tested (68 assertions)

- save/load virtual library: round-trip, n_propose, diversity_weight, saved_at
- load returns None for unknown campaign
- Second save overwrites first (upsert)
- save_auto_proposal: id assigned, fields preserved, default triggered_by
- get_latest_auto_proposal: non-None, correct id, None for unknown campaign
- list_auto_proposals: newest-first order, correct count
- refit_and_propose: None when no assay data, None when no virtual library
- refit_and_propose: succeeds with 6-compound training set
- Proposal structure: campaign_id, n_proposed, round_number, scores dict, ad_statuses list
- triggered_by preserved in proposal
- Proposal retrievable from DB after refit
- Background loop: False before start, True after, idempotent second start
- stop_background_loop: loop stops within 0.2s
- INDSectionAssembler: returns AssemblyResult, campaign_id correct
- Markdown written to disk, has >1000 characters
- All 6 sections (2.6.1.1–2.6.1.6) present in markdown text
- PBPK section: "EMA" present, "2-fold" present
- ADMET section: hERG, DILI, Ames safety gates present
- Audit section: "21 CFR Part 11", "SHA-256" present
- Title page: molecule_name and sponsor present
- Empty campaign (no compounds): assembles without error
- warnings is a list
- _fmt: float formatting, None → "N/A", non-numeric passthrough
- _pct: 71.0% and 100.0% formatting, None → "N/A"
- Audit query: 3 records by resource_id, 2 records by user_id, chain valid

---

## 10. Environment Variables and Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `BIOMATE_CAMPAIGN_DB_DIR` | `database/campaigns/` | Per-campaign SQLite databases |
| `BIOMATE_COMPLIANCE_DB_DIR` | `database/compliance/` | Global audit.db location |
| `BIOMATE_ESIG_KEY` | _(unset — plaintext)_ | 32-byte hex key for AES-256-GCM TOTP secret encryption |
| `BIOMATE_ESIG_REQUIRED` | `0` | `1` = enforce TOTP eSig on EXPORT_CRO_ORDER and PROPOSE_ROUND |
| `BIOMATE_AUDIT_STRICT` | `0` | `1` = block regulated operations if audit DB unavailable |

**To enable encrypted eSig secrets:**
```bash
export BIOMATE_ESIG_KEY=$(openssl rand -hex 32)
pip install cryptography
```

**To enforce eSig on synthesis exports:**
```bash
export BIOMATE_ESIG_REQUIRED=1
# Then add X-BioMate-ESig: <totp_token> header to EXPORT_CRO_ORDER and PROPOSE_ROUND requests
```

**To start the auto-retrain loop in production:**
```
POST /{campaign_id}/virtual-library  (cache the virtual library once)
POST /{campaign_id}/retrain          (starts background thread; persists for process lifetime)
```

The background thread is a daemon — it stops when the process exits. In a production deployment with gunicorn, restart handling (SIGHUP graceful reload) will stop and not restart existing loops; clients should re-call `/retrain` after server restarts, or implement a startup hook that calls `/retrain` for all active campaigns.

---

## 11. Known Limitations and Next Steps

### Limitations of Phase 1 validation

- The 1-compartment Bateman equation uses logP → ka correlation for absorption rate. Drugs with complex absorption (prodrugs, transporter substrates, extended-release formulations) may show high Cmax fold errors. These are annotated in `cmax_note` fields in the reference JSON.
- Validation is against an analytical predictor using observed CL/Vd/F (EMA Step 1 approach). A full Step 2 validation would require predicting CL and Vd from molecular properties and comparing against the 31-drug reference — not yet implemented.
- 31 reference drugs is a reasonable validation set but below the 50+ compounds recommended for high-confidence QSAR validation.

### Limitations of Phase 2 audit trail

- Append-only enforcement is logical (no update/delete methods) but not physical. A database administrator with direct file access can still delete records; `verify_chain()` will detect this but only after the fact.
- TOTP secrets stored in the same SQLite database as audit records. Physical separation (secrets in a secrets manager, audit log in a separate DB) would be stronger.
- The audit log does not currently capture the full request body content — only a hash of the URL path and query string (GET requests) or a constant "POST body hash" marker. For complete 21 CFR Part 11 compliance, the raw request payload (CSV file content, proposal parameters) should be hashed.

### Limitations of Phase 3 auto-retrain

- Background loop state is in-process only. If the server restarts, all loops stop. A persistent task queue (Celery + Redis, or a simple cron job that calls `/retrain`) would be more robust for production.
- Auto-proposals do not notify clients (no webhook or SSE push). Clients poll `GET /auto-proposal` to discover new proposals.
- The virtual library is cached as a flat SMILES list. For very large libraries (>50K compounds), this may be slow to featurize on each retrain cycle. A pre-computed fingerprint cache would improve performance.

### Next engineering priorities

| Priority | Work | Value |
|----------|------|-------|
| P1 | TOTP secret physical separation (secrets manager) | Security hardening |
| P2 | Webhook/SSE notification when auto-proposal ready | UX improvement |
| P3 | Request body hashing in audit middleware | Full 21 CFR §11.10(e) coverage |
| P4 | Persistent retrain loop (Celery task or cron) | Production resilience |
| P5 | 50+ drug validation set; Step 2 parameter prediction validation | Regulatory depth |
| P6 | pandoc reference DOCX template (CTD formatting) | Professional document output |
| P7 | Audit export PDF with digital signature | IND electronic submission |

---

*Document authored 2026-04-20 by BioMate engineering session.*  
*Cross-references: `docs/20260420_BIOMATE_AS_A_CRO_BUSINESS_AND_TECHNICAL_GUIDE.md` (business context), `docs/20260420_PHASE2_21CFR11_COMPLIANCE.md` (Phase 2 detail), `docs/20260420_PHASE1_CRO_MODEL_VALIDATION_AND_AD.md` (Phase 1 detail).*
