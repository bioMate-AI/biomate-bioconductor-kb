# Zhao-Lab Tutorial Demos — Detailed Requirement for Claude Design

**Date:** 2026-06-17
**For:** Claude design / engineering handoff
**Researcher:** Dr. Zhongming Zhao (UTHealth Houston, Center for Precision Health)
**Builds on:** `design_handoff_zhi_lab/Zhi-Lab Demo Requirement.md` (same demo grammar) and `Tier-0 Demo Requirement.md` (8-beat template). The two researcher requirement docs are siblings — read both before recording.

## Goal

Two **3-minute tutorial demos** for Zhao-lab pipelines already wired into BioMate (chains `tumor_reactive_t_cell_chain` id=71, `scgwas_immunology_chain` id=72). Use cases are drawn from the lab's own published tools (turep, Scupa, ImmuneApp, scGWAS).

Output: 2 voice-over scripts (≤3:00), 2 `.demo.ts` recorder scripts, 2 MP4+WebM at 1920×1080.

Visual grammar = identical to Zhi-lab demos (same 8 beats, same 480×120 tip card, methodology-blue #2563eb outcome band).

---

## Demo ZZ01 — Tumor-reactive T-cell multi-tool chain

**Showcase demo: BioMate's multi-tool chain composer.** First Zhao-lab demo runs 3 tools in sequence on one chat prompt.

### Scientific anchor
- **turep** (bioRxiv 2026) — tumor-reactive CD8+ T-cell detection from scRNA-seq + spatial
- **Scupa** (R package 2026) — immune cell polarization scoring (Tex/Tem/Trm subtypes)
- **ImmuneApp** (github.com/bsml320/ImmuneApp MIT, 2025) — HLA-I epitope binding for neoantigen ranking
- **BioMate wiring:** chain id=71, 3 steps × 3 phases each = 9 rationale rows, 5 citations across 3 qc_evidence domains
- **(why?) anchor:** all 9 phases verified live at `/api/rationale/tumor_reactive_t_cell_chain:{1,2,3}.{A,B,C}`

### Cold-open promise (Beat 1)
> "Three Zhao-lab tools, one chat prompt: find tumor-reactive T cells, annotate their state, rank candidate neoantigens. 3 minutes, end to end."

### Input contract (Beat 2)
```
Find tumor-reactive T cells in this melanoma scRNA-seq, score their polarization, then rank the top HLA-I neoantigens — HLA-A*02:01 patient.
```

### Per-beat tip script

| Beat | Tip | Duration | Anchor |
|---|---|---|---|
| 3 | "BioMate sees scRNA + tumor-reactive + neoantigen + HLA-A*02:01 → routes to Zhao-lab chain (id=71) — 3 tools, 9 phases total." | 5500 | intent kicker |
| 4 | "Step 1: turep params land — h5ad path, TCR table optional. Step 2 (Scupa) + Step 3 (ImmuneApp) auto-wire from upstream outputs." | 6000 | param strip |
| 5 | "Confirm & run — chain composer dispatches Step 1 first, polls, then Step 2 with auto-wired inputs." | 4000 | run button |
| 6a | "Step 1 / Phase B — turep inference. 48k cells scanned, 612 flagged tumor-reactive at calibrated ECE 0.038." | 5500 | phase-group 1.B |
| 6b | "Step 2 / Phase B — Scupa polarization. 598 cells scored across Tex / Tem / Trm; majority Tex consistent with exhausted melanoma TILs." | 6000 | phase-group 2.B |
| 6c | "Step 3 / Phase B — ImmuneApp MHC-I prediction. 1,840 candidate peptides → 147 binders at rank-pct ≤2%." | 5500 | phase-group 3.B |
| 6d | "Step 3 / Phase C — neoantigen ranking. Top hit: KLVVVGAVGV at rank 0.12% — a known RAS-derived neoantigen." | 5500 | phase-group 3.C |
| 7 | "Findings: 612 tumor-reactive cells + 147 binders + 1 top neoantigen. Citations cite turep, Scupa, and ImmuneApp directly. (why?) anchors explain each tool choice." | 6000 | findings + citations |
| 8 | "Outcome: 3 Zhao-lab tools, 9 phases, one prompt. Multi-tool integration is BioMate's specialty." | 3000 | completed badge |

### Recorder assertions
```ts
await expect(page.locator('[data-testid^="phase-group-"]')).toHaveCount(9);
// citations across all 3 workflows
for (const wf of ['turep','scupa_polarization','immuneapp_hla_screen']) {
  const r = await page.request.get(`/api/workflows/${wf}/citations`);
  expect((await r.json()).citations.length).toBeGreaterThanOrEqual(1);
}
const why = await page.request.get('/api/rationale/tumor_reactive_t_cell_chain:3.C');
expect((await why.json()).rationale_text).toContain('neoantigen');
```

---

## Demo ZZ02 — Single-cell GWAS for immune cell types

### Scientific anchor
- **scGWAS** (github.com/bsml320/scGWAS GPL-3.0, 28★, May 2026)
- **BioMate wiring:** chain id=72, single-step 3-phase ABC
- Pairs with Zhi's **Z01 TorchGWAS** for a complete "bulk + single-cell GWAS" UTHealth demo

### Cold-open promise (Beat 1)
> "GWAS tells you which variants matter. scGWAS tells you which cell types they matter in. Crohn's variants light up Tregs in 3 minutes."

### Input contract (Beat 2)
```
Run scGWAS on Crohn's disease GWAS summary stats against the gut single-cell atlas.
```

### Per-beat tip script

| Beat | Tip | Duration | Anchor |
|---|---|---|---|
| 3 | "BioMate sees `scGWAS` + `Crohn` + `gut atlas` → routes to Zhao-lab single-cell GWAS chain (id=72)." | 4500 | intent kicker |
| 4 | "Params prefilled: 12 GWAS traits, 27 cell types from the gut atlas, permutation N=10k." | 5000 | param strip |
| 5 | "Confirm & run — scGWAS launches on the GPU queue." | 3500 | run button |
| 6a | "Phase A — sumstats + scRNA input join. GWAS Catalog-harmonized format auto-detected." | 5000 | phase A |
| 6b | "Phase B — cell-type enrichment scoring. 5 cell types pass FDR 5%." | 5500 | phase B |
| 6c | "Phase C — report. Top hit: Crohn's disease × Treg — the published headline." | 5500 | phase C |
| 7 | "Findings: trait × cell-type heatmap. Citations: scGWAS paper + GWAS Catalog harmonization." | 5000 | findings |
| 8 | "Outcome: cell-type GWAS resolution from one prompt." | 3500 | completed |

### Recorder assertions
```ts
await expect(page.locator('[data-testid^="phase-group-"]')).toHaveCount(3);
const r = await page.request.get('/api/workflows/scgwas_immune_cell/citations');
expect((await r.json()).citations.length).toBeGreaterThanOrEqual(2);
const why = await page.request.get('/api/rationale/scgwas_immunology_chain:B');
expect((await why.json()).rationale_text).toContain('enrichment');
```

---

## Outcome card spec
Same methodology-blue (#2563eb) band as Zhi-lab demos. ZZ01 lists three repos (turep / Scupa / ImmuneApp); ZZ02 lists one (scGWAS). License badge: ZZ01 mixed (MIT × 2 + NOASSERTION × 1, with footnote "Scupa license clarification pending"); ZZ02 GPL-3.0.

---

## Joint UTHealth playlist (cross-researcher)

Once both labs' demos record, group as a 4-demo "UTHealth Houston method-integration pilots" playlist:

1. Z01 — TorchGWAS on UDIP brain phenotypes (Zhi, ★★★ flagship)
2. ZZ02 — scGWAS for immune cell types (Zhao, cross-references Z01)
3. Z02 — Folding-Docking-Affinity (Zhi, drug discovery)
4. ZZ01 — Tumor-reactive T-cell chain (Zhao, ★★★ multi-tool showcase)

Cross-references in tip text: ZZ02 Beat-7 mentions "pairs with TorchGWAS for bulk + single-cell"; Z02 Beat-7 mentions "complements ZZ01 for parallel small-molecule + immunotherapy rails."

---

## Acceptance criteria

For each demo:

1. **Pre-recording (engineering, complete):**
   - [x] Workflow rows + chain rows in DB
   - [x] qc_evidence.yaml with real DOI citations (≥1 per workflow)
   - [x] rationale_mapping confirmed:true rows for all phases
   - [x] rationale_registry populated, verified live via `/api/rationale/<chain>:<phase>`
   - [x] Node proxy for `/api/rationale/*` (shipped with Zhi commits)
   - [x] chain_meta narrator hook (shipped with Zhi commits — closes 2026-06-16 handoff)

2. **Real-data validation (engineering, open):**
   - [ ] Replace .nf stubs with real wraps of upstream code (see `docs/20260617_RESEARCHER_INTEGRATION_OPEN_ITEMS.md`)
   - [ ] Stage test datasets (PBMC h5ad for turep; UKB sumstats for scGWAS; etc.)
   - [ ] e2e test under `frontend/e2e/researcher-chains-audit.e2e.ts` runs against real dispatches

3. **During recording (design, open):**
   - [ ] Voice-over reads each tip verbatim, total ≤3:00
   - [ ] All N phase cards render via `data-testid^="phase-group-"`
   - [ ] Citations tab visible in Beat 7
   - [ ] (why?) anchor visible on at least one phase in Beat 6

---

## Out-of-scope

- Recording the lab's 11 Tier-B tools (no LICENSE yet) — list as post-demo follow-up
- VISDB 2.0 (web-hosted database, not a workflow); CancerGen-RAG (deferred to RAG-corpus follow-up)
- MethConvTransformer + PRISM-xQTL — preprint stage, code not on GitHub yet
