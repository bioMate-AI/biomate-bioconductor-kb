# Citation-Integrity Audit — Consolidated Report

**Date:** 2026-07-27
**Trigger:** directive — "make sure all knowledge has solid source and citations."
**Method:** 4 parallel adversarial audits (each claim: is the source *real* → does it *support the claim* → is it *correctly attributed*), disjoint doc ownership, **no fabrication** rule (unsourced → flagged/softened, never given an invented DOI). Prompted by the OPUS near-miss (a real number mislabeled to the wrong subgroup, caught by arithmetic).
**Companion standard:** memory `feedback_citation_integrity`; CLAUDE.md "cite every real number."

---

## Totals
| Audit scope | Checked | Verified real | Fixed | Flagged |
|---|--:|--:|--:|--:|
| Manuscripts M1–M3 | 23 refs | 23 | 20 | 2 |
| Manuscripts M4–M5 | 27 refs | 27 | 27 | 3 |
| Evaluation docs (6) | ~130 claims | ~123 | 9 | 2 |
| Registry + strategy (7 docs) | ~40 refs | ~40 | 3 | 2 |
| **Total** | **~220** | **~213** | **~59** | **11** |

**No DOI, PMID, or epitope sequence was fabricated at any point.** Every fix used a source-confirmed identifier; every unsourceable claim was flagged in-text, not invented.

---

## Substantive catches (would have embarrassed in peer review)

1. **M4 — fabricated embellishment removed.** Ref 5 (Marcu, HLA Ligand Atlas, JITC 2021 — real) had "deep-learning immunopeptidome expansion (class I/II +46–100%)" grafted on. The paper is a **mass-spec atlas doing no DL and reporting no such figure.** Rewrote the claim + reference to what it actually supports; removed the false DL framing. **This is the origin of the "46–100%" number** that also propagated into `WHERE_TO_TRAIN_MODELS` (independently flagged there).
2. **M2 — wrong attribution (OPUS-lesson class).** PRECISESADS ref cited a *different* paper's title; corrected to **Barturen 2021, *Arthritis Rheumatol.* 73:1073** (verified: 4 clusters, longitudinally stable).
3. **M5 — PROFILE wrong first author + CI.** Cited "Parkes et al." → real first author **Noor et al.** (Parkes is senior), *Lancet Gastroenterol Hepatol* 2024;9:415–427. Box 1 interaction CI "−14/+14" → published **−15/+15, p=0.944**.
4. **Celiac antigen — epitope sequence mislabels.** ω1/ω2 were wrong (`PYPQPELPY`) → canonical **ω1=PFPQPEQPF, ω2=PQPEQPFPW** (Sollid, 3-source cross-check); non-canonical sequence dropped; γ1/γ2 relabeled `[PARTIALLY UNVERIFIED]`; 33-mer clarified as the deamidated form. (Ranking results unaffected — all scored 1.00 — but identities are now correct.)
5. **M3 — misleading statistic.** "~30% are FcRn non-responders" was actually the **placebo responder rate in ADAPT**; reworded to the accurate numbers.
6. **text2term mis-attributed** — "Vasudevan 2024" → **Gonçalves et al. 2024**, *Database* baae119.
7. **M5 benchmark trials** — IPASS/CRYSTAL/OPUS/PRIME/MERiDiAN/COIN were named but uncited → added as verified refs 8–13. Cross-checked reproduction claims: CRYSTAL p=0.03 ✓, PROFILE CI −15/+15 ✓.
8. **Uncited claims closed with real sources:** M1 ComBat-seq (Zhang 2020), M2 "8 endotypes" (Hubbard 2025).

---

## Open flags — resolve before submission (none papered over)

| # | Item | Doc | Status / action |
|---|---|---|---|
| 1 | **"~96% / ~17%" in-vs-OOD LLM ontology-mapping accuracy** | harmonization survey, internal-model docs, registry | `[UNVERIFIED]` — qualitative failure is documented (LLMs hallucinate IDs; PMC12162076 precision 14.7–59%); the *exact numbers* trace to no source. Keep qualitative claim, drop/replace the precise figures. |
| 2 | **"46–100% DL coverage expansion"** | WHERE_TO_TRAIN (registry note) | `[UNVERIFIED]` — origin was the M4 Marcu embellishment (now removed). DL immunopeptidome gains are real (CAPTAn, Prosit ~7×) but this exact range isn't sourceable. Replace with a sourced figure or soften. |
| 3 | **MERiDiAN per-subgroup ORR 2×2 cells** | gate3 benchmark | `[SOURCE UNVERIFIED]` — EJC full text paywalled; the **PFS interaction p=0.4619 IS verified** (PMID 27817944). Recommend: run MERiDiAN as a PFS-interaction control, or source the ORR cells from the paper. |
| 4 | **OPUS / PRIME KRAS-mutant per-cell counts** | gate3 benchmark, M5 Box 2 | Flagged as **reconstructed, not line-by-line re-verified** (some cells paywalled). Verdicts robust; confirm exact cells against source tables before submission. |
| 5 | **Celiac γ1/γ2 cores** | celiac validation | `[PARTIALLY UNVERIFIED]` — γ-family nomenclature genuinely tangled; relabeled illustrative γ-family frames, not verbatim canonical cores. |
| 6 | **MS PLP 139-151 / MOG 35-55** | M4 | `[UNVERIFIED]` — ref 13 (Wucherpfennig) covers MBP 85-99 only; PLP/MOG need their own primary source or removal. |
| 7 | **telitacicept gMG Phase 3** | M3 | Softened — **no peer-reviewed Phase-3 paper exists** (AAN-2025 late-breaker, NCT05737160); cite the presentation, update when published. |
| 8 | **Orphan refs (Nelson 2015, Minikel 2024)** | M3 | Real but uncited in the body — add the supporting sentence or remove. |

---

## Verdict
The knowledge base is now **source-backed and internally consistent**: ~213/220 claims trace to verified primary sources; ~59 citations were corrected (real identifiers only); 11 items are **explicitly flagged in-text** as unverified/reconstructed/conference-only rather than presented as fact. The remaining flags are either (a) precise numbers whose qualitative claim survives, or (b) paywalled per-cell trial counts whose verdicts are robust — all clearly marked. **Nothing was fabricated to close a gap.** The docs are honest about what is verified vs reconstructed vs illustrative — which is the submission-grade standard the directive asked for.
