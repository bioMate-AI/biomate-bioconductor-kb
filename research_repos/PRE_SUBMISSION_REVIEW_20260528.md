# Pre-Submission Review — BioMate Publication Trilogy
**Reviewer:** Claude (Bäckman framework, Nature Methods adaptation)
**Date:** 2026-05-28
**Manuscripts reviewed:** 3
- Flagship — `research_repos/flagship_paper/manuscript/MANUSCRIPT_DRAFT.md` (206 lines)
- AutoLoop — `research_repos/autoloop_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md` (126 lines)
- BioMate-Cryo — `research_repos/cryo_em_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md` (410 lines)

---

## Summary verdict

| Paper | Verdict |
|---|---|
| **Flagship** | **MAJOR REVISIONS REQUIRED** — §3.4 and §3.5 are TBD placeholders, abstract is empty, internal count contradiction (29 vs 57) is acknowledged but unresolved, key claims rest on N=4 with one degree of freedom. Not submittable to *Nature Methods* in current form. |
| **AutoLoop** | **MAJOR REVISIONS REQUIRED** — §3 Results and §4 Discussion are empty placeholders, references list contains a parenthetical editorial note rendering it unfit for submission, scenario count contradiction (125 vs 139) flagged by author and unresolved, no abstract. |
| **BioMate-Cryo** | **MAJOR REVISIONS REQUIRED** — the "protocol-discrimination benchmark" headline is a *synthetic* gate-trigger exercise, not real TRPV1 data, and the abstract/conclusion language obscures this. §3.3 is mislabelled "Planned Benchmark" yet referenced in headline claims. Comparison row labelled "CryoSPARC Live" reports "not run" yet the paper frames CryoSPARC Live as the primary comparator. |

None of the three is currently submission-ready. The Flagship and AutoLoop drafts explicitly say so (placeholder banners); BioMate-Cryo does not, but its core comparative claim is unsubstantiated.

---

## Manuscript 1: Flagship

### D1 Language & Style — 6 issues
1. **No abstract.** Line 21: `*[To be drafted after §3 Results land.]*`. *Nature Methods* requires a structured abstract; cannot review without one.
2. **First-person plural throughout Results** ("we argue", "we present", "we caution") is acceptable but heavy by *Nature Methods* house style — tighten where the agent is BioMate, not the authors (e.g., line 33 "We argue that this gap is not domain-specific" → "This gap is architectural rather than domain-specific").
3. **Long subordinate-clause sentences** especially in §1.1 (line 29 is 90+ words, one sentence). Break into two.
4. **British/American spelling inconsistency**: "modelling" (line 29, 45), "labelled" (line 89, 100), "standardised" (line 47), but "characterized" (line 192-style elsewhere). Pick one; *Nature Methods* prefers US.
5. **Title is long** (15 words). Nature Methods recommends ≤12 — consider "Evidence-Graded QC Governance with Auto-Loop Convergence for Drug-Discovery Workflows."
6. **§1.4 line 65** contains an architectural sentence ("A single in-process hook (`qc_trace_monitor`) intercepts the structured output of every workflow step…") buried inside the contribution summary; this belongs in §2.

### D2 Internal Consistency — 5 issues
1. **Catalog count contradiction explicitly unresolved.** §1.4 (line 65) reports "29 gates across 16 domains, with 22 GOLD, 5 SILVER, and 2 BRONZE." §3.1 (line 135) reports "57 gates distributed across 25 drug-discovery domains … 26 GOLD … 26 SILVER … 5 BRONZE." Line 141 acknowledges this and promises reconciliation "in revision." A reviewer will read §1 first and conclude the paper contradicts itself. **Must fix §1 before submission.** (Table 1 CSV confirms 57 / 26 / 26 / 5 / 25 domains.)
2. **§3.1 BRONZE list (line 139) does not match Table 1 by location.** Text names five BRONZE gates: `pbpk.pbpk_cl_min`, `docking_binding_score`, `docking_valid_poses`, `nlmixr2_poppk.nlmixr2_ofv_stability`, `biomarker_enrichment.phase3_enrichment_factor`. Table 1 confirms 2 BRONZE in docking, 1 in pbpk, 1 in nlmixr2_poppk, 1 in biomarker_enrichment — totals 5. Consistent, but reviewer must compute this from the CSV; add the list to the table footnote.
3. **Five vs four auto-loop domains.** §1.4 (line 67) and §3.1 (line 135) say *five* wired auto-loop domains (ADMET, CYP-DDI, NCA-PK, Docking, PBPK). §3.3 (lines 157, 159) reports four domains and notes "PBPK reported separately in the next-wave benchmark." Reconcile: either drop PBPK from §1 enumeration or report its data here.
4. **§3.3 single-shot percentages contradict the E2 CSV.** Manuscript (line 161): "20% to 50%". CSV `e2_convergence_per_domain.csv` `baseline_single_shot_pct` column: ADMET 40, CYP_DDI 30, Docking 20, NCA_PK 50. Range is 20–50, consistent — but the `autoloop_gate_pass_at_1_pct` column shows 13.9/25.9/22.9/25.9, which a reader might confuse for "single-shot." Disambiguate in caption.
5. **§3.3 ADMET mean iterations (3.97)** is the highest of all domains and is mentioned in passing (line 166), but Table also reports CYP-DDI = NCA-PK = 1.74 and Docking = 1.73 — i.e., ADMET takes 2.3× more iterations than every other domain. This is the most interesting auto-loop result; it deserves explanation, not a half-sentence aside.

### D3 Unsupported Claims — 6 issues
1. **§1.4 line 71** "the central novelty" of cross-domain governance is asserted but no related-work survey demonstrates that no existing platform does this. The only platforms named earlier (Nextflow Tower, AWS HealthOmics, Terra) are not analysed for governance features. Add a comparison table.
2. **§3.2 line 153** "0% recovery without an explicit profile switch" — this is logically a tautology under the experimental setup (single fixed default profile by definition rejects every threshold-exceeding scenario). Frame as a definitional statement, not as a finding.
3. **§3.4 (E3) entire section is TBD** (line 173: "full E3 data by Wave 2 Agent E"). The reported correlation rests on N=4 domains and one degree of freedom (Docking vs everything-else). Line 183 acknowledges this. **The paper's headline claim that "provenance grade predicts convergence reliability" rests on this single contrast and cannot stand without E3 finalised.**
4. **§3.5 (E4) entire section is TBD** (line 187: "full E4 data by Wave 2 Agent F"). The "audit completeness against comparators" framing is hypothesis, not data.
5. **§1.4 line 67** "Auto-loop converges within at most three iterations in the majority of cases" — but the E2 CSV shows ADMET mean iterations 3.97, exceeding the stated 3-iteration budget. There is a soft contradiction with the "default: three iterations" budget in §2.3 line 111 — reconcile (probably the budget is per-gate not per-scenario, but this is unclear from the text).
6. **§2.4 line 117** "Random seed 20260527" anchors reproducibility but neither `run_e1.py` nor the CSV records the actual seed used. Verify and report seed-set provenance.

### D4 Statistics & Methodology — 4 issues
1. **No inferential statistics on E1** (acknowledged, line 125). For 100%/0% results this is defensible, but state explicitly that scenario counts (50 per domain) preclude binomial CI estimation if you don't report them.
2. **E2 escalation rate of 0% for three domains** is suspicious for a synthetic-scenario benchmark — the scenarios were "designed to fail one or more gates" (auto-loop paper §2.4) — if 0% escalation falls out of the design, this is a design artefact, not a property of auto-loop. Acknowledge or stratify by `persistent` vs `non-persistent` scenarios.
3. **E3 chi-squared p=0.010 on N=112** (e3_methods.md line 72) versus **Fisher's exact GOLD-vs-BRONZE p=0.106** (line 74) is a real disclosure issue. The methods note explains this honestly (line 119–123: the persistent adversarial scenarios depress GOLD convergence) but the headline manuscript text (§3.4 line 183: "consistent with the pre-registered hypothesis") does not currently disclose the p=0.106 contrast. **This must appear verbatim in the manuscript Results or it is selective reporting.**
4. **Cross-domain N=4** for the provenance correlation (Pearson r=0.977, p=0.023; e3_methods line 103) is genuinely fragile — one domain reclassification (any single Docking gate promoted to SILVER) would collapse the result. Report sensitivity analysis.

### D5 Tables & Figures — 3 issues
1. **Table 1 (in §3.1)** is referenced but only its summary CSV exists; no markdown table is inlined in the manuscript. Insert the per-domain table or cite Supplementary.
2. **Figure 1 / 2 / 3 / 4** are referenced (line 145, 157, 172, 185) but the figures directory contains only `e1_false_rejection.png`, `e4_audit_completeness.png`, `figure5_architecture.png`. **Figure 2 (E2 convergence) and Figure 3 (E3 provenance) PNGs do not exist in the flagship paper's `figures/` folder.** The autoloop paper has them; if the plan is cross-paper sharing, declare it; otherwise generate.
3. **Figure captions absent** from the manuscript. Each figure needs a self-contained caption with N, statistical test, and definition of axes.

### D6 Contribution — verdict
The cross-domain framing is genuinely novel and the GOLD/SILVER/BRONZE provenance grading — with the publicly-documented Aronov 2008 *J Med Chem* fabricated-citation discovery as its motivating story — is a real methodological contribution. **However**, as currently drafted the paper presents one fully-finished experiment (E1, false-rejection elimination on synthetic data) plus three TBDs. A *Nature Methods* editor would desk-reject with "resubmit when complete." The cross-paper structure (flagship + auto-loop + cryo) also creates a problem: the flagship's most quantitative claim (E2 convergence) is the auto-loop paper's central result, and the flagship's most visually striking finding (cryo membrane-protein false-rejection recovery) is the cryo paper's central result. The flagship risks being a "wrapper" with little independent contribution beyond the gate catalog and the provenance grading framework — both of which could fit as a *Nature Methods* Brief Communication or as supplementary material to one of the other two papers.

---

## Manuscript 2: AutoLoop

### D1 Language & Style — 3 issues
1. **No abstract** (line 23 placeholder). *J Med Chem* requires a structured abstract.
2. Title length OK (17 words) but "Provenance-Graded Auto-Loop for Drug-Discovery Pipelines" is the contribution — lead with it.
3. Long sentences in §1.1 (line 31, 33) — split.

### D2 Internal Consistency — 4 issues
1. **125 vs 139 scenario count contradiction.** Manuscript §1.4 line 53 says "125 benchmark scenarios"; §2.4 line 93 says "125 scenarios across the four wired domains: 36 in ADMET, 27 in CYP-DDI, 27 in NCA-PK, and 35 in docking" (sum = 125 ✓). But `e3_methods.md` line 18 says **"139-scenario Wave-1 results"**; `e3_provenance_correlation.csv` contains 139 rows (verify). The `methods/00_intake_notes.md` reference at line 105 confirms the author flagged this. **Must reconcile before submission.**
2. **Reference 3 (Avilov 2023)** is annotated "*(uncited evidence anchor; auto-loop without provenance)*" — that is an authoring note, not a reference. **Remove the parenthetical before submission.** Also: verify Avilov S et al. *Reaction Chemistry & Engineering* 2023 actually exists with that author/journal/year. The cryptic note suggests the author was uncertain. (I did not find a clear match for "Avilov" with that journal/year on a quick search — flag for PubMed/CrossRef verification per the Aronov-correction process lesson.)
3. **§2.3 Docking knowledge base "5 BRONZE"** (line 89): the CSV `e2_provenance_per_domain.csv` shows Docking with `bronze=5` (✓), matching. But §2.3 also describes only "Two handlers" with five rules — clarify how 2 handlers correspond to 5 BRONZE entries.
4. **§1.4 line 53** claims 14.3% escalation is "structural, not accidental" because "five scenarios … are constructed as persistent-fail by design" — but the CSV shows Docking has *zero* `escalated=True` rows for `weak_score` and `no_poses` gate_types. Where are the five persistent docking failures? The escalate-marked rows in the CSV are ADMET (3) and CYP-DDI (3) — not Docking. **The 14.3% Docking escalation in the e2 results CSV is not the by-design persistent stratum; it is genuine BRONZE-domain non-convergence.** This is honestly more interesting than the by-design framing, but the manuscript currently misattributes it.

### D3 Unsupported Claims — 5 issues
1. **§1.2 line 41** "Bayesian-only remediation cannot meet [regulatory traceability]" — strong claim, single cited example (Avilov 2023, itself unverified). Soften or add two more counter-examples discussed and dismissed.
2. **§2.1 line 65** "~2-fold IC50 increase per unit logP reduction" attributed to Waring & Johnstone 2007 — verify this is verbatim in the cited paper (the Aronov fix established this as a process gate, and Waring & Johnstone is a real paper, but the slope value should be quoted).
3. **§1.4 line 53** "100% gate-pass within ≤3 iterations in three domains" — true for ADMET/CYP-DDI/NCA-PK from the CSV (✓). But the abstract placeholder (line 23) claims "96.4% gate-pass within ≤3 iterations across 125 benchmark scenarios" — 96.4% of 125 = 120.5; the actual count is (36+27+27+30 of 35) = 120 of 125 = 96.0%. Recompute and reconcile.
4. **§2.4 line 93** "Published single-shot baselines are 40% (ADMET), 30% (CYP-DDI), 50% (NCA-PK), and 20% (Docking)" — these numbers match the CSV `baseline_single_shot_pct` exactly. But they are described as drawn from "published baseline distributions." **Provide citations for each baseline.** Currently they read like internal pre-registration values, not published rates.
5. **§2.3 Aronov 2008 *Curr Opin Drug Discov Devel*** citation now correctly points to the real paper (per citation-correction doc) — but the manuscript references (line 126) still need a DOI or accessible URL; PMID 18175275 is correct but readers will want a DOI. Many readers cannot easily access *Curr Opin Drug Discov Devel*.

### D4 Statistics & Methodology — 3 issues
1. **§2.4 scoring rubric** (line 95): 1.0/0.8/0.5/0.0 weights are ad hoc; no justification. Pass@≤3 is the headline metric anyway, so consider dropping the weighted score.
2. **No comparison to a "naive" or "single-shot" auto-loop** — only single-shot vs auto-loop pass rates are reported. To prove the *provenance* dimension adds value (the paper's distinguishing claim), need to compare against a deterministic remediation engine without provenance attribution. Otherwise this is a parameter-search paper with a citation footnote.
3. **Iteration budget of 3 is hard-coded** but ADMET CSV shows iterations=4, 5, 9 — the budget appears not enforced. Reconcile (likely the orchestrator allows step-internal retries beyond the gate budget); explain.

### D5 Tables & Figures — 2 issues
1. **§3 Results is empty** (line 105 placeholder). Cannot evaluate figures/tables.
2. **e2_convergence.png and e3_provenance_correlation.png** exist in `figures/` but are not embedded or captioned in the manuscript draft.

### D6 Contribution — verdict
The core contribution — evidence-anchored remediation rules attached to a deterministic auto-loop — is real and the GOLD/0 Docking story is the strongest single finding across the whole trilogy. *J Med Chem* readership is the right audience. **But the paper is incomplete (§3 + §4 empty), the abstract is empty, the reference list contains an editor's note in the bibliography, and the central numeric claim (96.4%) is rounded from 96.0% with the source scenario count contradicting the methods notes (125 vs 139).** Cannot be submitted today.

---

## Manuscript 3: BioMate-Cryo

### D1 Language & Style — 4 issues
1. **Abstract is 290+ words** (line 22 single block) — exceeds *Nature Methods* 200-word limit. Cut substantially.
2. **Title acceptable** at 11 words but "Interactive QC Governance" is the contribution — consider leading with it.
3. **Methods section uses Title Case headers** (§2.1 "Pipeline Architecture", §2.2 "QC Gate Modules"), but the other two papers use sentence case. Harmonise across the trilogy.
4. Section §2.7 line 165 has a marketing-style sentence ("BioMate-Cryo is a pure orchestration layer: the user runs CryoSPARC under their own license…") — rewrite as neutral technical description.

### D2 Internal Consistency — 6 issues
1. **§3.3 is labelled "Planned Benchmark"** (line 261) and §2.6 (line 157) says EMPIAR-10005 raw movies are "impractical" to download. But §3.4 (line 291), §4.1 (line 327), §5 Conclusions (line 359), and the **Abstract** (line 22) all present the protocol-discrimination benchmark as a completed result. **The abstract states "On benchmark data … BioMate-Cryo achieves … 100% of membrane-protein-like exposures … are silently discarded" — this is a SYNTHETIC trigger result, not real TRPV1 data.** The abstract must explicitly state "synthetic exposures parameterized from published TRPV1 motion statistics" or similar. *Nature Methods* reviewers will treat this as a misleading abstract otherwise.
2. **Table 1 (line 196)** column "CryoSPARC Live" is entirely "not run" — yet §2.8 (line 173) describes CryoSPARC Live as the "primary comparator for false-positive/negative gate behavior" and §4.1 (line 325) calls out the architectural distinction between BioMate-Cryo and CryoSPARC Live. **The headline comparative claim is unsubstantiated by direct measurement.** Either run a CryoSPARC Live head-to-head or remove the comparator framing.
3. **Gate count: §2.2 says 7 paper-level gates** (line 92), then §2.2 architectural note (line 122) reveals **11 metric-level evaluations** in code; **3 in the cross-domain catalog**. This is a real architecture explanation, but it complicates the "7 gates" headline. The abstract says "seven QC gate modules"; Table 1 of the flagship paper (cryo_em row) shows 3 gates for cryo_em. Cross-paper consistency requires explicit mapping.
4. **Abstract: "23-step CryoSPARC SPA"** but §3.2 (line 188) describes "complete 24-job CryoSPARC pipeline." 23 steps vs 24 jobs needs reconciliation (the 24th may be a validation or output job, but state this).
5. **Run A FSC 3.98 Å vs published 2.2 Å.** Manuscript correctly explains this is Nyquist-limited at the auto-downsampled 1.96 Å/px box (line 190, 213). This is **honest reporting** but a casual reader will compare 3.98 Å to the 2.2 Å published baseline and conclude BioMate is worse. Lead with Run B (1.78 Å Nyquist-limited at 0.885 Å/px) in the Results headline; demote Run A.
6. **Cross-paper:** Flagship §1.2 line 39 cites "Zhang & Zhang, manuscript in preparation" for the cryo result, stating "100% of exposures whose motion statistics fall in the membrane-protein-typical 58–74 Å range are silently discarded." Cryo paper §3.4 confirms this number but it is *synthetic*. The flagship's text reads as if this is a real-data finding. **Fix the flagship to also flag "synthetic exposures from published TRPV1 statistics."**

### D3 Unsupported Claims — 6 issues
1. **Abstract claim "the first cryo-EM processing platform with audit-trailed, evidence-graded QC governance"** (§5 line 359, also implied in abstract) — the word "first" requires explicit dismissal of: TranSPHIRE (cited, has feedback-based threshold adjustment), Warp (real-time monitoring), CryoSPARC Live, RELION Schemes. The abstract mentions these dismissively; the related-work analysis is in §1.2 but is not exhaustive. *Nature Methods* will demand this.
2. **§3.4 line 301** "Scaled to a full TRPV1 dataset … estimated 15–30% of the full set" — no source for 15–30% range. State as projection with stated assumption.
3. **§3.4 line 301** "estimated **6,630 recoverable particles**" — derivation is "~1,326 particles/micrograph × 5" but the 1,326 figure is from "published TRPV1 collection parameters" without citation. Provide source.
4. **§2.3 protocol profile thresholds** — all four profiles are listed as "Evidence: BRONZE" (Table 2, line 135). Yet text in §4.1 line 329 says "The membrane protein drift threshold of 80 Å is not a new discovery; Glaeser and others have published on this for years." If Glaeser supports it, why is it BRONZE not SILVER? Either upgrade the grade or explain why community-paper support doesn't reach SILVER.
5. **§3.2 line 192 "FSC 0.143 = 1.78 Å — Nyquist-limited, confirming full extraction of available signal."** Nyquist-limited reconstruction is a **feature of pixel size, not algorithm quality**. The claim that BioMate achieved this means it didn't *fail* — not that it improved on baseline. Soften.
6. **§2.5 audit schema "designed to satisfy 21 CFR Part 11"** (line 151) — repeated in §4.3 and Abstract. "Designed to satisfy" is honest; ensure no version of the prose says "satisfies" or "compliant with."

### D4 Statistics & Methodology — 4 issues
1. **Sample sizes are tiny.** Protocol-discrimination benchmark = 20 real soluble + 5 synthetic membrane exposures. 5 synthetic micrographs cannot support population claims ("100% false-positive rate"). The 100%/0% asymmetry is by-construction (5 synthetic exposures all parameterized to fall in the 50–80 Å zone).
2. **No CI on false-positive rate.** A 5-of-5 vs 0-of-5 result has wide binomial CIs (Wilson 95% CI: [56.6%, 100%] vs [0%, 43.4%]). State or use exact methods.
3. **No statistical test against the baseline** because the baseline (CryoSPARC Live head-to-head) was not run. Without a measured comparator, the "100% false-positive elimination" claim has no statistical backbone.
4. **No replication.** Each benchmark configuration is run once. State whether deterministic.

### D5 Tables & Figures — 4 issues
1. **figures/ directory is empty** (verified: `cryo_em_benchmark_paper/figures/` lists no PDFs or PNGs). Supplementary Figures S1–S4 are referenced (lines 404–410) but no files exist in the repo. **Cannot submit without figures.**
2. **tables/ directory is empty**, yet Table 1, Table 2, Table 3 are referenced. Tables 1 and 2 are inlined in the manuscript as markdown — acceptable for draft, but final-form Tables need export.
3. **Table 1 (line 196)** mixes Run A (20 movies, 1 GPU) and Run B (26K particles, 4 GPU) as if comparable — they processed *different inputs*. Footnote inadequate; consider splitting into two tables.
4. **Table 2 (line 275)** — column "Difference" of "−5" for accepted micrographs is misleadingly negative-signed when the membrane_protein profile *accepts more*. Convention should be +5. Re-sign.

### D6 Contribution — verdict
The orchestration + audit-trail + protocol-profile work is genuinely useful for the cryo-EM core-facility audience. *Nature Methods* historically publishes such workflow papers (cryoSPARC itself, CTFFIND4, Warp). However, the headline differentiating result is **synthetic**: 5 made-up exposures with motion statistics drawn from a published paper's distribution. Reviewers will ask: "Why couldn't you process even 100 raw TRPV1 micrographs?" The cited reason — 174 GB raw movies — is a one-night download in 2026. If the answer is "EC2 budget," say so; if it's "CryoSPARC license," say that. **The paper's empirical claim must rest on at least one real membrane-protein dataset, not just synthetic exposures.** Until then, the cross-domain context (the flagship paper) is doing most of the work; standalone, this paper would not survive *Nature Methods* triage.

---

## Cross-paper concerns

1. **The "first" / "no existing tool" claim** appears in all three papers without an exhaustive related-work table. *Nature Methods* will demand one. Provide a single shared Supplementary Table comparing BioMate against: Nextflow Tower, CryoSPARC Live, Warp, TranSPHIRE, RELION Schemes, Schrödinger SDS, Certara Simcyp, Phoenix WinNonlin, Galaxy, KNIME Server, Bayesian-optimisation platforms.
2. **GOLD/SILVER/BRONZE grading is defined three times** with slightly different wording. The flagship §2.2, autoloop §2.2, and cryo §2.4 should reference a single canonical definition (publish it in the supplementary, cite in all three).
3. **Synthetic data prevalence.** All three papers rely substantially on synthetic data: E1 scenarios are sampled from published bands (flagship), 125 auto-loop scenarios are synthetic by construction (autoloop §2.4), the cryo protocol-discrimination benchmark is synthetic. **The trilogy must not present synthetic-derived percentages as if they were measurements on real datasets.** Each percentage in the abstracts needs a real/synthetic flag.
4. **BioMate naming convention.** "BioMate" appears as "BioMate" (flagship), "BioMate-Cryo" (cryo), and inconsistently "BioMate AI" (author affiliation). Pick a convention.
5. **The companion-paper cross-citation chain** ("BioMate Team, manuscript in preparation") creates a circular dependency. *Nature Methods* discourages forward citations to unpublished works for headline claims. The cryo paper's §1.2 statement about the membrane-protein 100% false-rejection result cannot be cited in the flagship as a finding if the cryo paper is itself unpublished.
6. **Possible second fabricated citation.** Autoloop Reference 3 (**Avilov S et al. *Reaction Chemistry & Engineering* 2023**) is annotated with an authoring note rather than a finished citation, and I could not quickly verify the existence of this exact author/journal/year combination. Given the Aronov 2008 *J Med Chem* fabrication was caught in a similar context, **this citation must be PubMed/CrossRef verified before any submission.** This is the most important single follow-up.
7. **CLAUDE.md "Documentation rule" violation.** Citation correction doc is at `docs/20260528_CITATION_CORRECTION_ARONOV.md` (correct location) but `frontend/client/src/data/qc-evidence.ts` was reportedly not patched a third time — review noted in the correction doc that a manual step remains. The fabricated DOI may still appear in the frontend tooltip code. **Verify before submission** because reviewers will run the live demo URL.

---

## Top 10 must-fix items before any submission

1. **Verify Avilov 2023 reference** (autoloop, ref 3) on CrossRef/PubMed. If fabricated, replace per Aronov-correction process. **Highest priority — second possible citation fabrication.**
2. **Reconcile 125 vs 139 scenario count** in the autoloop benchmark (autoloop §2.4 vs e3_methods).
3. **Reconcile 29 vs 57 gate count** between flagship §1.4 and §3.1 — edit §1.4 to use the current count.
4. **Flagship: complete or remove E3 (§3.4) and E4 (§3.5).** A *Nature Methods* paper cannot have two TBDs in Results.
5. **Flagship §3.4: disclose the p=0.106 Fisher's exact result** verbatim in the manuscript, not just in `e3_methods.md`.
6. **Cryo abstract + §3.3 + §5: explicit "SYNTHETIC" labelling.** The protocol-discrimination result must not read as if it came from real TRPV1 raw movies.
7. **Cryo §3.3 mislabel.** "Planned Benchmark" → "Synthetic Protocol-Discrimination Benchmark" and remove the future-tense language ("will be run") since the synthetic version *was* run.
8. **AutoLoop §3 + §4 are empty.** Cannot submit; complete or remove the manuscript from the trilogy.
9. **Cryo Table 1: remove "CryoSPARC Live" column** or actually run the head-to-head. "Not run" against a comparator framed as primary is editorially unacceptable.
10. **All three: write the abstracts.** Two of three are placeholders.

---

## Reviewer's honest assessment

**What is genuinely good.** The provenance-grading framework (GOLD/SILVER/BRONZE), the audit-trail JSONL schema, and — most importantly — the **falsifying-its-own-citation event** documented in `docs/20260528_CITATION_CORRECTION_ARONOV.md` are a real methodological contribution. The fact that the project caught its own fabricated Aronov 2008 *J Med Chem* citation, rewrote three manuscripts and the production code to correct it, and produced a process-lesson document recommending mandatory PubMed verification, is exactly the kind of self-corrective scientific hygiene that *Nature Methods* methods papers should model. The flagship paper's §3.1 paragraph defending the retention of 5 BRONZE gates "rather than misrepresent them as SILVER" is the single best paragraph in the trilogy. The cross-domain breadth (25 domains, 57 gates) is unprecedented at this level of formality. The cryo Run B Nyquist-limited 1.78 Å reconstruction is a strong technical demonstration of the orchestration layer.

**What is genuinely weak.** The empirical foundation is mostly synthetic. E1's false-rejection results are *by construction* — scenarios are sampled to fall in the marginal zone, and the threshold rejects them. E2's auto-loop convergence rates are on *designed-to-fail* scenarios, against which "100% convergence in 3 of 4 domains" is impressive but boundary-dependent. E3's central correlation rests on N=4 domains and one degree of freedom (Docking vs everything-else), with a Fisher's exact p=0.106 that the manuscript does not currently disclose. The cryo paper's protocol-discrimination headline uses 5 made-up micrographs. The "BioMate is the first…" claim across all three papers is not defended against an exhaustive comparator list. The references chain is circular ("manuscript in preparation" in all three). And one citation in the autoloop reference list (Avilov 2023) has an authoring note that should have been replaced — a second possible fabrication that must be verified before submission given the Aronov precedent. **Net: the framework is real, the data backing it is preliminary, and the trilogy as a whole reads as a strong workshop pre-print, not three independent *Nature Methods*-class papers.**

---

*Path: `research_repos/PRE_SUBMISSION_REVIEW_20260528.md` (uncommitted, no manuscript edits made).*
