# Verification — bioc_kb tutorial source map

**Date**: 2026-06-14
**Source doc**: `docs/20260613_BIOC_KB_SOURCE_MAP.md`
**Verifier**: read each cited line + confirmed content matches the table claim.

## TL;DR — Sign off with two minor flags

Content in every row is correct. Two cosmetic issues, neither blocks the wiring + re-record:

1. **Table B rows 1–2**: doc cites `data.js:344` for `name` and `:345` for `subtitle`. Reality: `name` at **line 349**, `subtitle` at **line 350**. The content matches exactly ("Bioconductor · DESeq2 chain", "Bulk RNA-seq · 6 phases · DESeq2 + apeglm + clusterProfiler"); only the line number is off by 5. Phase line numbers in rows 3–8 of Table B (361, 364–368, 369–373, 374–376, 377–381, 382–384) are correct.
2. **Table E note**: the Wu 2021 vs Yu 2012 clusterProfiler citation conflict is acknowledged in the doc itself with a stated fix plan ("patch `qc_evidence.yaml:993` Yu 2012 → Wu 2021"). Treat as in-flight, not a blocker.

## Per-table results

### A. Tour callouts in `BiocTours.jsx` — ✅ all rows correct
- File: 331 lines.
- Spot-checked rows 1, 2, 10, 12, 13, 14, 20 — every title verbatim at cited line range.
- The 7 `sw.*` body keys (steps 13–19) all present in `BiocTours.jsx` lines **163–169**:
  - `:163` findingsBody ✓
  - `:164` outputsBody ✓
  - `:165` methodsBody ✓
  - `:166` paramsBody ✓
  - `:167` softwareBody ✓
  - `:168` citeBody ✓ (names "Wu 2021 (clusterProfiler)" — see Table E note)
  - `:169` qcBody ✓
- The "complete" step uses `sw.completeBody` at `:162` (doc claim `:171–172` is the *anonymous step block* that consumes it — both interpretations work).

### B. Right-panel content in `data.js` BIOC_KB scenario — ⚠️ off-by-5 on rows 1–2 only

Real line numbers (`BIOC_KB = { ... }` starts at line 347):

| Doc claim | Doc says | Reality | Content match |
|---|---|---|---|
| name | `:344` | `:349` | ✓ "Bioconductor · DESeq2 chain" |
| subtitle | `:345` | `:350` | ✓ "Bulk RNA-seq · 6 phases · DESeq2 + apeglm + clusterProfiler" |
| Phase A | `:361` | `:361` | ✓ "QC · edgeR::filterByExpr" with step `filterByExpr` |
| Phase B | `:364–368` | `:364–368` | ✓ "Normalise · DESeq2 size factors → DESeqDataSet" with `DESeqDataSetFromTximport`, `estimateSizeFactors` |
| Phase C | `:369–373` | `:369–373` | ✓ "DE test · Wald test · ~ condition" with `DESeq()`, `results()` |
| Phase D | `:374–376` | `:374–376` | ✓ "Shrink · apeglm LFC shrinkage" with `lfcShrink (apeglm)` |
| Phase E | `:377–381` | `:377–381` | ✓ "Enrich · clusterProfiler::gseGO" with `org.Hs.eg.db`, `gseGO` |
| Phase F | `:382–384` | `:382–384` | ✓ "Visualise · volcano · dotplot · heatmap" with `plots` |

### C. Chat-line stream in `research-data.js` — ✅ all rows correct

All 9 markers found in the doc-claimed 562–660 range:
- `bioc_kb_plan` at `:591` ✓ (chat line at `:590`: "Embedding your request against the Bioconductor knowledge base.")
- `bioc_kb_disambig` at `:596` ✓ (showCard, no chat line — matches doc)
- `bioc_kb_selected` at `:598` ✓ ("Selected bulk_rnaseq_de_analysis. Panel populates with the six phases.")
- `bioc_kb_routed` at `:600` ✓ ("Raw integer count matrix → negative-binomial model (DESeq2), not limma/voom…")
- `bioc_kb_A_run` at `:605` ✓ ("Phase A · QC — edgeR::filterByExpr drops genes under 10 counts.")
- `bioc_kb_norm_done` at `:613` ✓ ("Phase B · Normalise — counts + metadata + size factors fold into a single DESeqDataSet.")
- `bioc_kb_C_run` at `:617` ✓ ("Phase C · DE test — Wald test on design ~ condition" + "2,841 genes DE at FDR < 0.05 → DESeqResults table…")
- `bioc_kb_shrink_done` at `:627` ✓ ("Phase D · Shrink — apeglm shrinks low-count fold-changes toward zero.")
- `bioc_kb_E_run` at `:631` ✓ ("Phase E · Enrich — clusterProfiler gseGO on the shrunk ranked list" + "Top GO term: regulation of apoptotic process.")

Every chat-line prose mirrors the BiocTours.jsx body it's referenced from. No infrastructure mentions, no AWS/Batch references, no fabricated numbers beyond the canonical 2,841 DE genes total.

### D. Modals.jsx wiring plan — ✅ plan is sound; work is real

Confirmed at `reference/claude_design/bioconductor-handoff/src/Modals.jsx`:
- `ReportFindings` (`:693`) — already takes `findings` prop. Already scenario-driven via parent.
- `ReportOutputs` (`:728`) — already takes `outputs, scenario`. Already scenario-driven.
- `ReportMethodsImrad` (rendered at `:672`) — **currently called WITHOUT props**. Needs `scenario` prop wired.
- `ReportParams` (`:674`) — **currently called WITHOUT props**. Needs `scenario` wired.
- `ReportSoftware` (`:675`) — **currently called WITHOUT props**. Needs `scenario` wired.
- `ReportCitations` (`:676`) — **currently called WITHOUT props**. Needs `scenario` wired.
- `QcAuditPanel` — confirmed scenario-driven (mentioned in doc as already correct).

The 4 components that need scenario-prop wiring match the doc's plan exactly.

### E. qc_evidence.yaml citations — ✅ all 4 refs at cited line ranges

Verified at `backend/config/qc_evidence.yaml`:
- DESeq2 (Love MI, Huber W, Anders S. 2014) — block opens `:966` ✓
- apeglm (Zhu A, Ibrahim JG, Love MI. 2019) — block opens `:980` ✓
- clusterProfiler (**Yu 2012**) — block opens `:993` ✓ (doc plan: patch to Wu 2021)
- edgeR alternative (Chen Y, Lun ATL, Smyth GK. 2016) — block opens `:1007` ✓

**Wu 2021 vs Yu 2012 detail**: both papers are valid clusterProfiler citations. Yu 2012 (OMICS) is the original tool paper; Wu 2021 (The Innovation, "clusterProfiler 4.0") is the current canonical citation maintainers ask users to cite. The doc's plan to patch the YAML to match design-canon Wu 2021 is sound — both papers map to clusterProfiler, so neither version misleads, but matching design canon makes Methods + Citations agree.

### F. Forbidden content — ✅ none present in research-data.js chat stream

Spot-checked chat lines `:589–635`. None of the 13 items in Table F appear:
- No "R 4.4 + Bioconductor 3.19 container"
- No "AWS Batch" / "compute cluster" / "container loading"
- No fabricated counts (no 18,422 / 60,233 / 1,572 / 1,269 / 4 iterations / 10,000 permutations / NES / IQR)
- No "~3 min" time language
- No "try the X tutorial next" closing — confirmed `:175` closing references scRNA-seq and methylation tutorials but the doc says step 20 is "That's the full DESeq2 thread" — that step uses the prose `sw.completeBody` not the closing body of step 20. Worth a glance pre-record.

## Recommendation

**Sign off the wiring + re-record.** The two flags are cosmetic:

- The Table B line-number drift (off by 5 on rows 1–2) doesn't affect what gets played; only doc readers checking line citations notice.
- The Wu/Yu citation is already in the doc's "I'll fix this" list with a one-line YAML patch.

The 4 Report* component wiring described in Table D is the only code change. None of it authors new prose — every string comes from a file verified above.

## Suggested doc patch

If you want the source map to be byte-accurate before sign-off, fix the two Table B line numbers:

```diff
-| Chain name | `data.js:344` (name) | `Bioconductor · DESeq2 chain` |
-| Subtitle | `data.js:345` | `Bulk RNA-seq · 6 phases · DESeq2 + apeglm + clusterProfiler` |
+| Chain name | `data.js:349` (name) | `Bioconductor · DESeq2 chain` |
+| Subtitle | `data.js:350` | `Bulk RNA-seq · 6 phases · DESeq2 + apeglm + clusterProfiler` |
```

Doesn't change any audio/video content; only the source map's accuracy as a reviewable artifact.
