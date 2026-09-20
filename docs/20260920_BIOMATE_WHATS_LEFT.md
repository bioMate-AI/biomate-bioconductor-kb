# BioMate — What's Left for Improvement (+ Nuance-Testing Plan)

_2026-09-20. Source: the user-manual coverage ledger (`docs/user-manual/coverage-ledger.md`),
Appendix E (roadmap), the whole-system manual audit, and the backlog tasks. This is the durable
version of the "what's left" answer._

## Status baseline (what's DONE)
- **User manual** — 40 chapters written (Overview ×4, Part I modules ×13, Part II data ×5,
  domains ×13, appendices ×6), every "supported" claim gated by the coverage ledger. Committed on
  `integration/dev-test`.
- **Manual synced to Google Drive** — 56/56 files copied faithfully via rclone into the
  `user_manual` folder (chapters + subfolders + screenshots) plus a readable Index doc.
- Recent fixes shipped: cost/pricing UI removed (DesignGenerate + `/capabilities`), `user_notes`
  trust-boundary leak closed, interactive-tools availability gate, single-cell in-app panel,
  reproducibility-record fallbacks, FASTQ/FASTA data-perception labels.

The **only remaining manual work** is the claude-design phase: render the verified markdown as
branded in-app `/manual` doc-pages. Requirements captured separately (see
`docs/user-manual/CLAUDE_DESIGN_REQUIREMENTS.md` once written).

---

## A. Fixable gaps — "built but not wired" / "runs but incomplete" (highest ROI)
These are real components/paths that exist but aren't fully connected. Cheap, verifiable fixes.

| # | Gap | Fix shape | Status |
|---|-----|-----------|--------|
| A1 | **PaeHeatmap** viewer exists (`viewers/pae-heatmap.tsx`) but `*_pae.json` sidecars aren't routed to it in `step-output-preview.tsx` | one-wire route (like the CitationPanel fix) | **in progress (this session)** |
| A2 | **Metabolomics has zero code-enforced QC gate** (only domain without one) — no parser/verdict in `qc_trace_monitor.py`, no `qc_evidence.yaml` section | add metric parser + gate + citations, matching the other domains | **in progress (agent)** |
| A3 | **GWAS→scRNA→eQTL** chain runs but is incomplete (binary eQTL gate, no coloc/PP4, hardcoded demo scRNA) | finish coloc/PP4 + real scRNA input, or keep parked in Appendix E | pending decision |
| A4 | **Owner-transfer** has a backend but no UI | add the transfer control to project settings | pending |
| A5 | **FAERS** wired (workflow 11363) but demo-shaped (hardwired 2004-Q1 + insulin) | generalize the query params | pending |
| A6 | **Somatic variant calling** (Mutect2) — workflows exist + route, but no chain/gold-standard | build chain + gold | pending |
| A7 | **Stale catalog counts** — CLAUDE.md says "2,455/34"; the MCP server instructions say "4,017/36"; earlier live queries suggested ~4,200/42. **These disagree** and must be reconciled to the live DB | update the strings to the verified live count | **in progress (drift test agent verifying)** |

---

## B. Verification debt (the biggest "nuance" gap)
Things claimed/wired that were never verified end-to-end.

- **Missing gold-standard validators.** Only `transcriptomics.py` exists; the tutorial doc references
  epigenomics / proteomics / metabolomics / metagenomics validators that **do not exist**. This is
  the honest "does it actually reproduce the published metric" test, and it's absent for most domains.
- **E2E-unverified tools** (wired, never run to completion): Foldseek, MMseqs2, GROMACS-MD,
  AlphaFold-Multimer (T17–T20).
- **Single-cell in-app panel** is data-gated on a `*.summary.json` sidecar that was never confirmed
  emitted on a real run.
- **Interactive tools** (RStudio / Jupyter / CellxGene) are availability-gated but not provisioned on
  dev — either provision or keep the honest gate.

---

## C. Nuance-testing plan (the core need)
Nearly every real bug this arc was a **nuance the existing suite didn't catch** — caught only by
reading + screenshots (the `user_notes` leak, checksums-opt-in, FASTQ labels, Salmon 50-vs-70, cryo
CTF 0.2-vs-0.70, wrong DB IDs, `InteractiveToolsRow` ungated, PaeHeatmap unrouted). Build one test
per bug-class so they can't recur:

1. **Trust-boundary tests** — assert human-only data (e.g. `user_notes`) never reaches the model
   across *every* injection path. (Seeded: `memory-knowledge-filter.test.ts`.)
2. **Doc↔code drift tests** — assert every QC threshold / tool name / workflow-ID / catalog count in
   tutorials & specs matches the code. Would have caught the Salmon/CTF/DB-ID/count drift.
   **(in progress — agent building `doc-code-drift.test.ts`.)**
3. **Wiring / no-dead-affordance tests** — assert built components stay mounted with their props
   (CitationPanel, PaeHeatmap, `onOpenOutput`, the interactive gate) and no button 400s / no fake
   success. **(in progress — agent building `wiring-contracts.test.ts`.)**
4. **Gold-standard L-tier runs** — the missing per-domain validators run on Batch and asserted
   against the published metric. Largest debt; needs Batch time.
5. **Routing nuance tests** — bulk-vs-single-cell, germline-vs-somatic, `out_of_domain`,
   disambiguation.

---

## D. In-flight parallel work (this session)
- Agent: metabolomics QC gate (A2).
- Agent: doc↔code drift test suite (C2 / A7).
- Agent: wiring + trust-boundary test suite (C3 / C1).
- Me: PaeHeatmap wire (A1) + stale-count reconciliation (A7).

---

## E. Backlog cross-reference (existing task IDs)
- Object model: #17 (`@ref`/DataChip), #19 (EvidenceAnswer object), #20 (output→dataset back-link).
- Writing/skills: #23 (manuscript assembler), #27–#30 (survey / Methods / manuscript / CSL citation).
- Quality-eval: #32 (citation relevance floor, findings output-read, follow-ups).
- Cleanup: #36 (L1d legacy endpoint removal + MemStorage→cache), #37 (drop vestigial Galaxy exec).
- Facility upgrades: #38 (U1 DeepVariant DAG, U2 DIA-NN pin, U4–U12).

---

## Recommended sequencing
1. **Now (cheap, CI-able):** A1 PaeHeatmap wire, A2 metabolomics gate, A7 count reconcile, and the
   C1–C3 nuance-test classes (drift / wiring / trust). These catch the exact recurring bug family and
   run in CI.
2. **Next (verification):** stand up the missing per-domain gold-standard validators (B / C4) — the
   real "nuance" verification; needs Batch runs, so schedule deliberately (review diff first per the
   no-speculative-deploys rule).
3. **Then:** the object-model + writing-skills backlog (#17/#19/#20, #23/#27–#30).
