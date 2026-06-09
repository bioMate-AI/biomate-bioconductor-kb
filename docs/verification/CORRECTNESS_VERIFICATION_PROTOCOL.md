# Output-Correctness Verification Protocol (for an independent third party)

This protocol lets an independent reviewer test whether a workflow we mark **executable** also
produces **correct** output — by comparing against **real data with a real, author-validated
reference output**. It deliberately does NOT rely on our synthetic fixtures.

## The claim hierarchy — only the top tier is "correct"
Our standing validation establishes the lower tiers; **T5 is what earns "correct," and we hand
it to you to run independently:**

| Tier | What it shows | Who establishes it |
|---|---|---|
| T1 | the workflow runs without error | us (CSV: `status`) |
| T2 | it produces its declared, non-empty outputs | us (CSV: `outputs_produced`) |
| T3 | outputs change when the input changes (not a hardcoded demo) | us |
| T4 | outputs are type/invariant-valid (p∈[0,1], dims consistent, no all-NA) | us (recommended) |
| **T5** | **outputs match a real, author-validated reference within tolerance** | **YOU (this protocol)** |

We do **not** claim T5 from synthetic inputs. Treat our "executable" as T1–T3, not "correct."

## The reference: each package's own vignette (real data + documented output)
Every Bioconductor package ships a vignette that runs the package's **own real example dataset**
(e.g. `airway`/`pasilla` for DESeq2, real flow-cytometry data for flowCore) and the rendered
vignette **shows the computed result**. That is the author's peer-reviewed canonical output — the
ground truth. Per-workflow pointer: `reference_vignette_url` column in
`supplements/S1_validated_workflows_by_domain.csv` (→ `https://bioconductor.org/packages/<pkg>/`,
"Documentation / vignettes").

## Procedure (per sampled workflow)
1. **Pick a sample** from `S1` (stratify by `domain`; include some `rising_star=yes`). The CSV has
   the package, workflow, and the reference vignette.
2. **Obtain the real input** the vignette uses (the documented example dataset — named in the
   vignette, loaded from the package's own data, not our synthetic fixture).
3. **Run the workflow's analysis** on that real input (the workflow steps are package-native R;
   run them in the package's public biocontainer `quay.io/biocontainers/bioconductor-<pkg>:<ver>`).
4. **Compare to the vignette's documented result** — concordance, not bit-identity:
   - same output **dimensions / row counts**;
   - same **top-N features** (e.g. top DE genes, top enriched terms) — high overlap (Jaccard ≥ a
     pre-set threshold);
   - **numeric agreement** on shared quantities (fold-changes, p-values, scores) — correlation
     ≥ threshold, or within a stated tolerance;
   - no sign flips / no degenerate (all-equal, all-NA) output.
5. **Record** pass/fail + the concordance metrics. A workflow passes T5 only if it reproduces the
   vignette's key results within tolerance.

## Stronger, where available: external ground truth
For packages with an independent gold standard, prefer it over the vignette:
- spike-in / simulated data with **known** differential features → ROC/AUC vs. truth;
- labelled datasets for clustering/classification → ARI/accuracy vs. known labels.
These give quantitative accuracy, not just author-concordance.

## Honest framing for your report
- A T5 pass = "reproduces the package's canonical result on real data." A T5 fail on an
  "executable" workflow = it runs but its numbers don't match the reference — exactly the kind of
  finding we want surfaced.
- Report the **concordance rate** over your sample (and per domain). That rate — not our
  "executable" count — is the defensible "correct-output" evidence.

## What we provide you
- `supplements/S1_validated_workflows_by_domain.csv` — workflows + domain + rank + rising-star +
  **reference vignette URL**.
- `supplements/S2–S5` — tools/packages, viz/API tools, annotation collections, rising-star
  rationale (with the numerical selection criteria).
- `bioc_validated_executable.csv` + `BIOC_EXECUTABLE_VERIFICATION_GUIDE.md` — the T1–T3 evidence
  and how it was produced.
- Public biocontainer references per package (no internal infrastructure needed).
