# Compound 22 structure–assay join — 30 October 2026

The primary patent now supports a direct compound-number join between a product drawing, synthesis entry and the previously recovered assay row. It does not yet supply a validated machine-readable graph.

## Source qualification

In [WO2014151634A1](https://patents.google.com/patent/WO2014151634A1/en), the Compound 22 synthesis heading is followed by drawing `imgf000161_0001`. The associated text calls the synthesis Example 23 and reports molecular weight **1767.06**, using Cyclization Method C. The [exact drawing](https://patentimages.storage.googleapis.com/e0/cb/78/e705c0c8798fb2/imgf000161_0001.png) was retrieved and visually inspected. It depicts a sulfur-containing ring closure, multiple N-methyl amides and explicit stereochemical bonds; no SMILES was inferred or computed.

Table 8, discussed in Example 122, associates compound 22 with **3 nM HTRF inhibition of human PD-1/PD-L1 binding**. This is an inhibition IC50, not a Kd. The stable compound number supplies the join; it does not establish a causal effect for any isolated modification. [Primary synthesis and assay source](https://patents.google.com/patent/WO2014151634A1/en).

The reported molecular weight exceeds the current completed-output upper bound of 1400. That does not itself prohibit using a retained prefix: `hybrid/model.py` applies the chemical constraint to completed proposals, while `FrozenParentProtocol` selects parents by source/task metadata. Prefix feasibility and scientific applicability remain untested. This distinction corrects an overly broad parent-exclusion interpretation; it does not authorize a new parent or relax the frozen output constraint.

## Provenance

- Original record: `1dbd58d6798c1f37`, passage `WO-2014151634-A1:544`.
- Downloaded HTML: `/tmp/WO2014151634A1-primary.html`, SHA-256 `fcf66c0280014947a3334d10a4caa20d06da825345075b4a5baee5c00a4fd955`.
- Exact drawing: `/tmp/compound22-primary.png`, SHA-256 `3dae5f59e26cd94bd439bede9eec9b528adb9671ad3688c6d27c1e3de4e29460`.
- HTML element markers `p1122`–`p1128` locate the synthesis block; these are HTML identifiers, not asserted printed patent paragraph numbers.

The downloaded HTML and original corpus text are distinct byte representations with separate hashes. Original extraction fields are preserved; a dated candidate follow-up records this join.

## Remaining qualification

Complete atom-level transcription and independent stereochemical comparison, chemical validation on AWS, endpoint/protocol review, parent applicability and split clearance remain required. Status is `AI_ASSISTED_CANDIDATE`; graph, learned-conditioning and numeric-prior eligibility remain false. No tests, chemical parsing, model execution or scientific calculations were performed. Source-reported mass and IC50 are not new experimental results.
