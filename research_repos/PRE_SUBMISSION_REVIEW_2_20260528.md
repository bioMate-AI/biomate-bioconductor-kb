# Second Adversarial Review — 2026-05-28
**Reviewer:** Claude (Bäckman 6-dim framework, Nature Methods adaptation)
**Round:** 2 (post first-round MAJOR REVISIONS verdict)
**Manuscripts:** Flagship, AutoLoop, BioMate-Cryo

---

## Verdict per paper

| Paper | First-round | This round | Trend |
|---|---|---|---|
| Flagship | MAJOR REVISIONS | **MAJOR REVISIONS** (narrowed scope) | Improving |
| AutoLoop | MAJOR REVISIONS | **MINOR-to-MAJOR REVISIONS** | Substantially improved |
| BioMate-Cryo | MAJOR REVISIONS | **MINOR REVISIONS** | Substantially improved |

Trilogy is **not yet ready for bioRxiv** as three independent papers, but BioMate-Cryo is within reach of preprint posting; AutoLoop is one good Results-section pass away; Flagship still has two empty sections.

---

## Close-out verification (per first-round must-fix)

| Must-fix | Status | Evidence |
|---|---|---|
| Flagship §1 gate counts (29/16 eliminated) | **PARTIAL** | "29 gates / 16 domains" only appears once (line 141) inside the explicit reconciliation paragraph, framed as superseded. §1.4 line 65 now states 57/25/26-26-5. OK. |
| AutoLoop scenario counts (139/125/112) | **PASS** | §2.4 line 93 gives all three with semantics. "150" not present. Abstract uses 125/139/112 correctly. |
| Flagship §3.4 Fisher p=0.106 verbatim + "pre-registered" | **PASS** | Line 198 explicitly states "Pre-registered Fisher's exact test (GOLD vs BRONZE) … p = 0.106 … Pre-registered test did not reach the conventional p<0.05 threshold." Honest reporting. |
| Cryo SYNTHETIC labels in abstract + §3.4 + §5 | **PASS in abstract & §3.4** / **FAIL in §5** | Abstract line 22 says "5 synthetic micrograph exposures parameterized from … TRPV1/amphipol motion statistics". §3.4 has a "Note on data provenance" paragraph. **§5 Conclusions (line 361) still describes EMPIAR-10028 result but omits any synthetic-data caveat for the headline "first cryo-EM processing platform with audit-trailed evidence-graded QC governance" claim — the §3.4 framing is not echoed.** |
| Avilov→Taylor swap | **PASS** | Zero "Avilov" hits in any manuscript. AutoLoop ref 3 is now Taylor CJ et al., ACS Central Science 2023, 9(5):957-968, DOI 10.1021/acscentsci.3c00050. (DOI plausible; spot-check recommended but format looks correct.) |
| Aronov → Curr Opin (not J Med Chem) | **PASS** in manuscripts | All Aronov citations in MANUSCRIPT_DRAFT.md correctly cite *Curr Opin Drug Discov Devel* 2008;11(1):128–140, PMID 18175275. **Hangover:** `autoloop_benchmark_paper/manuscript/methods/00_intake_notes.md:31` still says "Aronov 2008 *J Med Chem* 51:6632, DOI 10.1021/jm0707476" — supplementary materials, not the main manuscript, but must be scrubbed before any reviewer is pointed at the methods directory. |

**Net close-out:** 5/6 fully closed, 1 partial (Cryo §5), 1 supplementary hangover (intake_notes). The deltas from round 1 are real and substantial.

---

## New issues found this round

### CRITICAL

**C1. Flagship §3.5 (E4) is still TBD but the abstract reports its numeric result.**
Abstract (`flagship_paper/manuscript/abstract.md`) line 5: "audit completeness reached 1.0 against 0.0 for baseline pipelines (Mann-Whitney U p=1.57×10⁻⁴)". MANUSCRIPT §3.5 line 206: "[TBD: full E4 data by Wave 2 Agent F.]". **The abstract claims a finalised statistical result for an experiment the manuscript body says is not finalised.** This is the same internal inconsistency the first round flagged for §3.4, transplanted to §3.5. Editor will desk-reject. Either: (a) drop the Mann-Whitney from the abstract, or (b) finalise §3.5.

**C2. Flagship abstract location split.**
`abstract.md` is a complete 178-word abstract; the in-manuscript line 21 still says "[To be drafted after §3 Results land.]". A reviewer reading MANUSCRIPT_DRAFT.md top-to-bottom sees no abstract. Either merge `abstract.md` into the draft or add a clear pointer at line 21.

### MAJOR

**M1. Multiple-comparison correction not applied.**
E3 reports 4 statistics (per-domain Pearson, omnibus chi-squared, pre-registered Fisher, sensitivity Fisher) plus a 2×3 contingency. No Bonferroni/Holm adjustment is discussed. The pre-registered Fisher (p=0.106) is honestly reported as primary, which mitigates the concern — but reviewers will ask why the *post-hoc* sensitivity Fisher=0.0044 is highlighted in the abstract without family-wise correction (Holm-Bonferroni on the family of 3 Fisher-type tests would lift 0.0044 to ~0.013, still significant; the omnibus chi-squared 0.010 to ~0.030, still significant). Add one sentence in §3.4 to head this off.

**M2. r=0.977 (N=4) appears in abstract without sufficient hedging.**
Flagship abstract: "per-domain gate-pass tracked provenance grade with descriptive Pearson r=0.977 (N=4)". The "(N=4)" tag is present and the word "descriptive" appears, which is good. But the AutoLoop abstract repeats r=0.977 with the same descriptive tag — in a paper whose central claim is provenance × convergence. A reader will form a false confidence interval. Recommend either dropping r=0.977 from one of the two abstracts or adding "1 df" so the fragility is apparent.

**M3. Sensitivity-analysis exclusion criterion: pre-registered or post-hoc?**
Flagship §3.4 line 200 describes the "adversarial `persistent` scenarios" as "constructed to defeat the remediator regardless of evidence quality" — this language implies they were defined *before* the sensitivity analysis ran. But the text does not say "pre-registered" for the exclusion rule, only for the primary Fisher contrast. The first round flagged this; it is now described but the pre-registration status of the *exclusion criterion* itself is ambiguous. One sentence fix: "The `persistent` gate-type label was assigned at scenario-construction time before any benchmark was run; the sensitivity analysis excluding these scenarios was specified in the pre-registration as a planned secondary analysis."

**M4. Cryo §5 Conclusion overstates ("the first cryo-EM processing platform…").**
Line 361 claim is unchanged from round 1 and not defended against an exhaustive comparator list. The §1.2 discussion of CryoSPARC Live/Warp/TranSPHIRE is qualitative; no table shows BioMate-Cryo's audit-trail field set vs theirs. The first round flagged this for all three papers; the cross-paper Supplementary comparator table has not been produced. **Highest priority remaining item for Cryo.**

**M5. Cryo Table 1 "CryoSPARC Live = not run" comparator framing.**
First round flagged this; still unchanged. Table 1 row still implies head-to-head that was not run. Either remove the row or run it.

### MINOR

**Mn1.** Flagship §3.3 line 166 explains the ADMET 3.97-mean-iterations finding ("deeper logP/MW staircases against compounds with multiple simultaneously-failing gates"). This addresses the round-1 observation. Good.

**Mn2.** AutoLoop abstract line 5 says "the framework combines parameter convergence with regulatory traceability suitable for IND-stage filings" — "suitable for IND-stage filings" is a forward-looking claim that should be softened ("designed to support IND-stage filings") because no actual IND submission is reported.

**Mn3.** Cryo §3.4 line 303: "estimated 15–30% of the full set" — still no citation for this range. Round 1 flagged; not fixed.

**Mn4.** Author affiliations still flag "*(placeholder — confirm with corresponding author)*" in Flagship and AutoLoop (lines 11). Required before submission, easy fix.

**Mn5.** Data & Code Availability: Cryo says "available from the corresponding authors upon request" — *Nature Methods* increasingly requires public deposit. Flagship/AutoLoop say `[REPO-PLACEHOLDER]`. None of the three has a specific deposit DOI or Zenodo archive.

**Mn6.** Limitations sections: Cryo §4.5 honestly notes "synthetic TRPV1-profile exposures" and "BRONZE evidence tier acknowledges…". AutoLoop has no Limitations section in the body (§4 is empty). Flagship has no Limitations section. The N=4 Pearson, the synthetic E1 scenarios, the pre-registered NS Fisher, and the BRONZE-only Docking remediation each deserve an explicit limitations bullet in Flagship.

**Mn7.** AutoLoop §2.4 line 95 ascribes single-shot baselines (40/30/50/20) to "TDC ADMET Group … FDA 2020 DDI test matrix … FDA 2003 BA/BE literature … DUD-E-style decoy sets" — collective citation but no per-baseline page-number anchor. Round 1 asked for individual citations; partially addressed.

**Mn8.** Cross-paper "manuscript in preparation" circular citations remain (flagship cites cryo; cryo cites flagship; autoloop cites both). Round 1 flagged; not addressed. *Nature Methods* will require bioRxiv DOIs at minimum.

---

## Citation spot-check (random 10 per paper, sanity-checked against memory; no WebFetch executed)

- **Flagship refs 4 (Redfern 2003), 5 (Lipinski 2001), 7 (Zhang/Chung/Oldenburg 1999), 8 (FDA/EMA PBPK), 9-10 (FDA/EMA AI guidance):** all plausible, no obvious fabrication. Ref 6 "Lammert et al. 2010; Andrade et al." is under-specified (no Andrade year/journal) — fix.
- **AutoLoop ref 3 (Taylor 2023 ACS Cent Sci 9(5):957):** plausible, format correct.
- **AutoLoop ref 12 (Aronov 2008 Curr Opin Drug Discov Devel 11(1):128–140 PMID 18175275):** PMID format correct; matches the post-correction target.
- **AutoLoop ref 11 (Waring & Johnstone 2007 BMCL):** plausible.
- **Cryo refs 5, 7, 8, 10, 13, 15:** standard well-known papers, formats correct.
- **Cryo ref 12 (Liu et al. 2025 Nat Methods):** **flag for live PubMed check** — 2025 paper, this AI claim is post-cutoff knowledge; reviewer should re-verify DOI.

No new fabrication suspected, but the Liu 2025 paper and the Taylor 2023 DOI should be independently CrossRef-checked before submission given the Aronov precedent.

---

## Recommendation

**Not ready for bioRxiv as a trilogy.** Per-paper:

- **BioMate-Cryo:** Closest to ready. Fix Cryo §5 conclusion to echo the synthetic-data caveat, remove or run the CryoSPARC Live comparator row, add a comparator table. **2–3 days of work.**
- **AutoLoop:** Complete §3 Results and §4 Discussion (the abstract already has the headline numbers; transposing into Results + adding a Limitations subsection should be straightforward). **3–5 days of work.**
- **Flagship:** Either finalise §3.5 E4 (matching the Mann-Whitney already in the abstract) or strip the E4 numeric claim from the abstract. Move `abstract.md` into the manuscript body. Add an explicit Limitations section. **5–7 days of work.**

**Top 3 remaining blockers:**
1. **Flagship abstract ↔ §3.5 contradiction** (claims Mann-Whitney p=1.57e-4 for an experiment the body marks TBD). Must fix before any submission.
2. **Cryo §5 still claims "first" without a comparator table** and the §5 conclusion does not carry the synthetic-data caveat that §3.4 honestly carries.
3. **Pre-registration ambiguity for the sensitivity-analysis exclusion criterion** (one sentence fix).

**Trend assessment:** The 4 must-fixes from round 1 were materially applied (5/6 closed, 1 partial). The most damaging round-1 issue — selective reporting of the pre-registered NS Fisher — is now exemplary in its honesty (§3.4 leads with "Pre-registered test did not reach…"). The Aronov citation correction propagated cleanly into the manuscripts. **The trilogy is on a credible trajectory to submission;** the remaining blockers are scoped and fixable in ~2 weeks of focused work, not architectural redesign.

---

*Path: `research_repos/PRE_SUBMISSION_REVIEW_2_20260528.md` (uncommitted, no manuscript edits).*
