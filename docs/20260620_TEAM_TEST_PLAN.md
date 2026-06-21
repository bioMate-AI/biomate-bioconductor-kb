# BioMate Team Test Plan — 6-Person Real Scenario Testing
**Date:** 2026-06-20  
**Sprint:** Integration / Next Phase  
**Scope:** Full connector suite, autoloop arc, MCP wiring, cross-user isolation

---

## Team Roster & Assignments

| Person | Role | Area |
|--------|------|------|
| Alex | Bioinformatics lead | Drug discovery / ADMET / autoloop arc |
| Sarah | Wet-lab scientist | RNA-seq / WGS / instrument connectors |
| Marcus | Platform engineer | CryoEM / instrument watcher / API |
| Lisa | CRO/compliance | CRO library / compliance package / report export |
| David | Security / backend | Cross-user isolation / billing quota |
| Katy | PM / full flow | End-to-end connector smoke (MCP + Slack + ChatGPT GPT) |

---

## Priority Tier 1 — Critical Business Flows (Week 1)

These cover the paths customers pay for. A failure here = revenue risk.

### P1.1 — Drug Discovery / ADMET + Autoloop Arc (Alex, 2 days)
**Scenario:** Screen a known hERG inhibitor (terfenadine) through ADMET, watch QC gate fire, accept remediation, verify second run completes with different params.

**Steps:**
1. Login to `https://dev-public.biomate.ai` as fixture account
2. Send goal: `Screen terfenadine (OC(CCCN1CCC(CC1)(C(O)(c1ccccc1)c1ccccc1)CC)c1ccc(cc1)C(C)(C)C) for ADMET — hERG IC50, CYP3A4, Ro5, admet_standard profile`
3. Click Run → watch phase cards update via SSE
4. Wait for QC gate panel: `data-testid="autoloop-gate-table"` must appear, hERG row must show "halt"
5. Remediation card must show `was → now` param diff with `→` token
6. Click "Accept & Re-run" → capture run_ids via `/api/workflows/runs`
7. Wait for second run → assert `status=completed` via API
8. Download PDF report → verify contains ADMET table

**Pass criteria:**
- [ ] Gate fires within 12 min (hERG IC50 < threshold)
- [ ] Remediation card proposes changed parameter
- [ ] Second `run_id` is different from first
- [ ] Second run reaches `completed` (not stuck)

**Covered by:** `frontend/e2e/autoloop-full-arc.e2e.ts` (22-min timeout, real AWS Batch)

---

### P1.2 — RNA-seq Differential Expression (Sarah, 1.5 days)
**Scenario:** Submit a real GEO accession → BioMate fetches data → runs nf-core/rnaseq → DESeq2 → downloads methods report.

**Steps:**
1. Send goal: `Fetch GSE183947 from GEO and run RNA-seq differential expression. Human GRCh38, dUTP strand-specific, treated n=3 vs control n=3, FDR 0.05`
2. Workflow card appears with `rnaseq_differential`
3. Click Run → observe phase cards (STAR alignment, FeatureCounts, DESeq2)
4. After `completed`: click "View AI Findings" → findings panel shows top DEGs
5. Download DOCX report → check methods section includes pipeline version

**Pass criteria:**
- [ ] GEO fetch via `resolve_accession` → S3 path populated
- [ ] All 3 phases complete within 30 min
- [ ] Findings: ≥ 50 DEGs at FDR < 0.05
- [ ] DOCX export contains methods paragraph

---

### P1.3 — WGS Germline Variant Calling (Sarah, 1.5 days)
**Scenario:** Upload FASTQ pair → BioMate routes to sarek → GATK HaplotypeCaller → VCF preview.

**Steps:**
1. `upload_file` → get presigned URL → upload `NA12878_R1.fastq.gz` + `R2`
2. Send goal: `Whole-genome variant calling on the uploaded FASTQ pair, GRCh38, GATK HaplotypeCaller, germline mode`
3. Workflow card: `wgs_germline_gatk`
4. After completed: `preview_file` on `.vcf.gz` → first 20 lines render as code block
5. `/api/billing/usage` → vCPU-hours credited for this run

**Pass criteria:**
- [ ] Upload completes and `s3://` path inserted into run params
- [ ] VCF file preview renders (not binary blob)
- [ ] Billing event recorded

---

## Priority Tier 2 — Platform Infrastructure (Week 2)

### P2.1 — CryoEM SPA (Marcus, 2 days)
**Scenario:** EPU session ends → `cryoem_instrument_connector` fires → BioMate routes to `cryosparc_standard_spa` → 3D reconstruction output.

**Steps:**
1. Run `python3 lab_instruments/cryoem_instrument_connector.py` against mock EPU server
2. Verify `POST /api/instruments/new-data` payload contains `workflow_id=cryosparc_standard_spa`
3. In UI: workflow card appears auto-populated with session data
4. After run: 3D map `.mrc` preview → renders as download link (images too large to inline)
5. Export PDF → contains resolution estimate

**Pass criteria:**
- [ ] Instrument connector sends correct workflow_id
- [ ] CryoSPARC phases complete (import, motion-correct, CTF-estimate, 2D-class, 3D-refine)
- [ ] Output `.mrc` file accessible via `preview_file`

**Covered by:** `TestInstrumentToBioMateIntegration` in `tests/test_lab_instruments_e2e.py`

---

### P2.2 — Illumina BaseSpace → BioMate (Marcus, 2 days)
**Scenario:** Illumina NovaSeq run completes → `illumina_basespace_connector` detects it → BioMate auto-suggests RNA-seq workflow.

**Steps:**
1. `TestInstrumentToBioMateIntegration.test_illumina_rnaseq_notifies_biomate`
2. Mock BioMate server captures `POST /api/instruments/new-data`
3. Assert payload: `suggested_workflow=rnaseq_differential`, `basespace_run_id`, `sample_ids`
4. Run the InstrumentWatcher against mock BaseSpace + mock BioMate
5. Assert `_notify_biomate()` called exactly once per new run

---

### P2.3 — MCP Connector Smoke (Katy, 1 day)
**Scenario:** Claude Code calls `biomate_session` → real run executes → result returned.

**Steps:**
1. Set `BIOMATE_API_URL=https://dev-public.biomate.ai` + `BIOMATE_API_KEY=<dev-key>`
2. Run: `python3 -m pytest tests/test_mcp_e2e.py -v`
3. `test_biomate_session` — sends aspirin SMILES ADMET goal → gets `run_id` back within 90s
4. `test_search_workflow` — searches "rnaseq" → returns ≥1 result
5. Claude Desktop MCP: manually test `biomate_session` from Claude Desktop

**Pass criteria:**
- [ ] Both tests PASS (not skip) when `BIOMATE_API_URL` is dev
- [ ] `run_id` in response is a valid UUID
- [ ] Lite tool set (3 tools) visible in Claude.ai GPT/custom connector

**Covered by:** `test_mcp_e2e.py` wired into `run_postsync_tests.sh`

---

## Priority Tier 3 — Security & Compliance (Week 2–3)

### P3.1 — Cross-User Data Isolation (David, 1 day)
**Scenario:** User A runs a workflow. User B cannot see User A's run or billing data.

**Steps:**
1. Login as fixture account (User A) → submit ADMET run → capture `run_id_a`
2. Create ephemeral User B via `x-e2e-test-token` bypass
3. Login as User B
4. `GET /api/workflows/runs/<run_id_a>` → assert **404** (not 403, not 200)
5. `GET /api/billing/usage` → assert User B's usage = 0 (not User A's data)
6. `GET /api/projects` → assert empty list (User B has no projects)

**Pass criteria:**
- [ ] Run ID from User A returns 404 for User B
- [ ] Billing usage endpoint scoped per user
- [ ] No user data leakage in any API response

**Covered by:** `frontend/e2e/security-cross-user-isolation.e2e.ts`

---

### P3.2 — CRO Compliance Package (Lisa, 2 days)
**Scenario:** Drug discovery campaign → ADMET results → attach to CRO Library → export ISO-compliant compliance package.

**Steps:**
1. Navigate to `/drug-discovery-cro`
2. Create campaign: "Compound Series A — ADMET screen"
3. Attach ADMET run results (from P1.1 above)
4. Export compliance package → PDF/ZIP with chain-of-custody, method references, QC gates passed
5. Open package → verify §2.6.1 narrative present, all QC metrics listed

---

### P3.3 — Billing Quota Enforcement (Alex, 1 day)
**Scenario:** Set a user's quota to 1 vCPU-hour, run a workflow, verify enforcement kicks in.

**Steps:**
1. Lago API: `PATCH /api/v1/subscriptions/<sub_id>` → set `max_vcpu_hours=1`
2. Run a GPU workflow (>1 hour)
3. `/api/billing/quota` → assert `exceeded=true`
4. Submit second workflow → assert 402 Payment Required from API
5. Reset quota

---

## Automated Test Coverage Map

| Scenario | Automated? | Suite |
|----------|-----------|-------|
| Autoloop full arc (P1.1) | Yes | `autoloop-full-arc.e2e.ts` |
| RNA-seq GEO fetch (P1.2) | Partial | `bioconductor-workflows.e2e.ts` |
| WGS upload + VCF preview (P1.3) | No | Manual |
| CryoEM instrument trigger (P2.1) | Yes | `TestInstrumentToBioMateIntegration` |
| Illumina BaseSpace → BioMate (P2.2) | Yes | `TestInstrumentToBioMateIntegration` |
| MCP e2e smoke (P2.3) | Yes | `test_mcp_e2e.py` (wired post-sync) |
| Cross-user isolation (P3.1) | Yes | `security-cross-user-isolation.e2e.ts` |
| CRO compliance package (P3.2) | No | Manual |
| Billing quota enforcement (P3.3) | Partial | `billing-smoke.e2e.ts` |

---

## Running the Suite

```bash
# Full postsync suite (after sync_to_dev.sh)
bash scripts/run_postsync_tests.sh

# Individual suites
BIOMATE_URL=https://dev-public.biomate.ai \
  npx playwright test frontend/e2e/autoloop-full-arc.e2e.ts --timeout 1320000

BIOMATE_API_URL=https://dev-public.biomate.ai \
BIOMATE_API_KEY=$BIOMATE_CONNECTOR_API_KEY \
  python3 -m pytest /tmp/biomate-connector/tests/test_mcp_e2e.py -v

python3 -m pytest /tmp/biomate-connector/tests/test_lab_instruments_e2e.py -v

BIOMATE_URL=https://dev-public.biomate.ai \
E2E_FIXTURE_PASSWORD=$E2E_FIXTURE_PASSWORD \
  npx playwright test frontend/e2e/security-cross-user-isolation.e2e.ts
```

---

## Open Issues

- [ ] P1.2: GEO fetch (`resolve_accession`) — SRA accession via NCBI Entrez, needs valid `NCBI_API_KEY` on dev
- [ ] P2.3: MCP lite set — Slack and WeChat connectors not yet tested against live Slack workspace
- [ ] P3.3: Lago quota reset endpoint not yet documented (check `billing_router.py`)
