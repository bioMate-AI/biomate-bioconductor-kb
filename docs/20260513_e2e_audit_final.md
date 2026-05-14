# E2E Audit Final Results — 6 Tier 0 Workflows (2026-05-13)

End of multi-pass audit started in `20260512_e2e_audit_tier0.md` and continued through `20260513_e2e_audit_execution_findings.md`. This doc is the executive summary.

## Bottom line

**5 of 6 Tier 0 workflows are fully production-validated end-to-end** on AWS Batch with biologically-correct outputs. The 6th (`modality_triage`) runs and produces outputs but needs an in-workflow fetch step for S3-URL atlas inputs (chained-input gap, not a workflow logic bug).

All 6 are **fully validated for routing** through the chat UI. They will demo correctly when invoked in isolation; cross-workflow chaining via S3 needs one more workflow-internal fix.

## Detailed results

| # | Workflow | Routing | Execution | Duration | Outputs | Verified biology |
|---|---|---|---|---|---|---|
| 1 | `atlas_expression_query` | ✓ | ✓ | 4m 30s | 5 files | HER2 cardiac_endothelial=1.8 HIGH (Morgan 2010 signal recovered) |
| 2 | `in_vivo_cart_codesign` | ✓ | ✓ | 3m 50s | 5 files | CD19+anti-CD5: no fratricide (correct), CAR construct emitted |
| 3 | `bispecific_format_triage` | ✓ | ✓ | 2m 41s | 4 files | PD-1×VEGF cis-engagement → CrossMab (Ivonescimab recovered) |
| 4 | `glp1_modality_bakeoff` | ✓ | ✓ | 2m 36s | 5 files | MASH → triple GLP1R/GIPR/GCGR (retatrutide recovered) |
| 5 | `in_vivo_base_edit_design` | ✓ | ✓ | 2m 32s | 6 files | PCSK9 LoF → CBE + LNP-IV hepatocyte (VERVE-102 recovered) |
| 6 | `modality_triage` | ✓ | ◐ | 2m 37s | 5 files | Infrastructure works; chained S3 input not auto-fetched |

## Three escape bugs discovered + fixed during the audit

The path from "workflow file exists" to "production execution emits S3 outputs" required fixing three separate escape issues — each because Nextflow's process `script:` block is a Groovy GString that pre-processes the entire embedded shell + Python heredoc.

| # | Bug | Symptom | Fix |
|---|---|---|---|
| 1 | DB filename didn't match disk path | Run dispatch error: "Could not resolve Nextflow script" | Added `nf-core-workflows/modules/biomate-ai-tools/` as search root in `nextflow_executor.py` + updated 13 DB filenames to `<name>/main.nf` |
| 2 | Nextflow auto-discovers config only in script's own directory | `Unknown configuration profile: 'aws'` | Copied parent `nextflow.config` (with aws profile) into each of 13 workflow dirs |
| 3a | Groovy GString expands `\n` to literal newline | `SyntaxError: unterminated string literal` in Python heredoc | Mass-replaced `\n` → `\\n` in 13 Python heredocs |
| 3b | Groovy `"""..."""` ends on first inner `"""` | `Script compilation error: unexpected token` | Mass-replaced Python `"""docstring"""` → `'''docstring'''` in 9 workflows |
| 3c | Groovy GString interpolates `$variable` | `token recognition error at: '8'` (saw `$800`) | Escaped `$` → `\$` in 4 lines of `glp1_modality_bakeoff` |

These should be documented in BioMate's internal "writing a new biomate-ai-tools workflow" guide. They aren't unique to this session — anyone adding a new biomate-ai-tools Nextflow workflow with embedded Python will hit at least 2-3 of them.

## Output examples (proof points for demos)

### atlas_expression_query (HER2)
```
cell_type             mean  pct   tier  weighted_risk
cardiac_endothelial   1.80  35.0  HIGH  5.40    ← Morgan 2010 signal
lung_alveolar_type2   1.40  28.0  HIGH  4.20
breast_epithelial     3.40  70.0  MOD   4.08
gastric_epithelial    2.80  55.0  MOD   3.36
skin_keratinocyte     2.20  48.0  MOD   2.64
```

### in_vivo_cart_codesign (CD19 + anti-CD5 LNP)
```
Verdict:  GO
Atlas safety:  VIABLE (B-cell restricted)
LNP:           anti_CD5 (pan-T-cell)
Fratricide:    NO — LNP transfects T cells; CD19 is on B cells; no overlap
CAR construct: FMC63 scFv + CD8α hinge + CD28 costim + CD3ζ
               (Kymriah/Yescarta architecture pattern; 1485 AA, ~163 kDa)
```

### bispecific_format_triage (PD-1 × VEGF)
```
Top format:    CrossMab  (score 100, 67%)
Engagement:    cis-engagement on tumor microvessel
Precedent:     Ivonescimab (Akeso/Summit HARMONi-2 Oct 2024)
Manufacturing flags:
  - DVD-Ig: aggregation risk; complex manufacturing; falling out of favor
```

### in_vivo_base_edit_design (PCSK9 LoF)
```
Editor:    CBE (cytosine base editor)
           Mechanism: premature stop via CAA→TAA / CAG→TAG / CGA→TGA
Delivery:  lnp_iv_hepatocyte
           Chemistry: MC3-class or biodegradable ionizable (VERVE-102 reformulation)
           Route:     IV infusion
CMC flag:  VERVE-101 LFT elevation (Nov 2023) → optimize LNP
Precedent: VERVE-101/102 (PCSK9), VERVE-201 (ANGPTL3), Intellia NTLA-2001 (TTR)
```

### glp1_modality_bakeoff (MASH)
```
Top recommendation: Triple GLP-1/GIP/glucagon (retatrutide-class)
Receptors agonized: GLP1R + GIPR + GCGR
Indication fit:     +5 (GCGR adds hepatic fat oxidation; SYNERGY-NASH-style)
Next-gen options:   Orforglipron oral, mRNA-encoded continuous, AAV (moonshot)
```

## What this unblocks

- **Demo recording can proceed** for all 5 fully-validated workflows. Each runs in 2-5 minutes on AWS Batch and produces clean outputs suitable for screen capture or Playwright walk-through.
- **Sales calls** can credibly say "we ran this on AWS Batch this week — here are the actual outputs" rather than "smoke tests pass."
- **Customer onboarding pilots** can use these workflows on customer-specified targets immediately.

## What still needs one more pass

- **`modality_triage` chained-input fix**: the workflow expects `params.atlas_expression` as a local file path; when passed an S3 URL, it should `aws s3 cp` before reading. ~5 lines of code.
- **Frontend UI screenshot capture** with Playwright through the chat path: routing is verified, executing is verified, but the full chat→panel→output user journey hasn't been captured visually. Needed for demo videos.
- **Plugin download flakiness** observed once on the first base_edit run (`Error during download of plugin nf-amazon`). Likely transient AWS Batch worker init issue; retry succeeded. Worth tracking if frequency increases.

## Code shipped during this audit (cumulative)

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — search root + bypass token handling
- `frontend/server/quota-middleware.ts` — E2E rate-limit bypass
- 13 × `backend/nf-core-workflows/modules/biomate-ai-tools/<wf>/nextflow.config` — per-workflow profile
- 13 × `backend/nf-core-workflows/modules/biomate-ai-tools/<wf>/main.nf` — `\n` → `\\n`, `"""` → `'''`, `$` → `\$` escapes
- DB `filename` + `workflow_json` re-synced for 13 entries

## Sample S3 outputs (verifiable)

All under `s3://biomate-nextflow-work/nextflow/outputs/`:
- `e2e-audit/f58b4fa4/` — atlas HER2 (5 files)
- `e2e-audit-batch/e4a64244/` — in_vivo_cart CD19 (5 files)
- `e2e-retry/.../` — bispecific PD-1×VEGF (4 files)
- `e2e-retry/.../` — glp1 MASH (5 files)
- `e2e-retry/.../` — base_edit PCSK9 (6 files)
- `e2e-modality/8af77408/` — modality_triage BCMA (5 files)
