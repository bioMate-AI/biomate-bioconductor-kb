# Competitor publication timelines → our submission/acceptance estimate

**Date:** 2026-10-05 · For the manuscript plan (`docs/marketing/manuscript-plan.md`). Dates are from
preprint servers (verbatim post dates) + publisher citations (volume/issue/DOI). **Exact journal
"Accepted" dates could not be verified** — Science/Cell/Nature/PubMed article pages return 403/cookie
walls to automated fetch — so submit→accept is derived as *publish minus typical production lag* and
labelled accordingly. No dates are fabricated; unverified ones are flagged.

## 1. Competitor / comparable papers — measured timelines

| Paper (venue) | Preprint posted | Journal received (submit) | Published (in-issue) | Preprint→publish | Submit→publish |
|---|---|---|---|---|---|
| **Biomni** — *Autonomous biomedical research with an AI agent* (**Science** 393(6813), DOI 10.1126/science.adz4351) | bioRxiv **2025-05-30** | **2025-06-02** | **2026-07-09** | **~13.4 mo** | **~13.1 mo** |
| **The Virtual Lab** — Swanson et al. (**Nature** 646(8085):716–723, DOI s41586-025-09442-9) | bioRxiv **2024-11-11** | not verified (≈ mid-2025) | Nature vol 646 (**≈ Oct 2025**; online reported ~Jul 2025) | **~8–11 mo** | ~8–10 mo (est.) |
| **LongevityBench / Longevity-LLM** (**Cell** 189(19):5980, DOI 10.1016/j.cell.2026.08.026) | bioRxiv **2026-01-12** | not verified | **2026-09-17** (cover) | **~8.2 mo** | ~7 mo (est.) |

**Read:** top-tier biology/multidisciplinary venues (Science/Nature/Cell) run **~8–13 months preprint→publication**.
Biomni — the closest analog to our flagship Paper A — took **~13 months** from Science submission to in-issue
publication (and preprinted ~13.5 months ahead). All three **preprinted first** and let the preprint carry
priority/visibility for the entire review period.

**Venue norms for our other targets (general, not a single paper):**
- **NeurIPS Datasets & Benchmarks** (RealBio / Paper B option): deadline-driven — full-paper deadline
  ~late May/early June, decisions ~Sept, camera-ready ~Oct, conference Dec → **submit→accept ≈ 3.5 mo**,
  but you can only enter at the annual deadline.
- **Bioinformatics / GigaScience** (RealBio rolling option): rolling; first decision ~1–3 mo,
  **submit→accept ≈ 3–5 mo**.
- **NAR Database Issue** (Paper C): rolling submission; annual **cover deadline ~mid-Sept** for the
  January issue; review **~1–3 mo** → **submit→accept ≈ 2–3 mo** (fastest credible win).
- **Nature Methods** (Paper A/C-Paper-2): **submit→accept ≈ 4–8 mo**, publish +1–2 mo.

## 2. Our submission → acceptance estimate (grounded in manuscript-plan readiness)

Readiness from `docs/marketing/manuscript-plan.md` §1–3, as of 2026-10-05. "Prep" = remaining gap work
before submission. All submit dates assume a **bioRxiv/arXiv preprint posted the same week** (the
competitor pattern — lock priority immediately; journal acceptance is many months out regardless).

| Paper | Target venue | Readiness | Prep needed | **Est. submit** | **Est. accept** | Est. publish |
|---|---|---|---|---|---|---|
| **C — Bioc-KB (Paper 1)** | NAR Database | submission-draft; strongest real data | mint DOI; executable smoke-test of a step sample | **Nov 2026** | **~Jan–Feb 2027** | ~Mar 2027 |
| **RealBio** | Bioinformatics/GigaScience (rolling) — *not* waiting for NeurIPS 2027 | manuscript-complete | independent (non-self) grading track | **Nov–Dec 2026** | **~Mar–Apr 2027** | ~May 2027 |
| **B — harness-vs-LLM** | NeurIPS D&B 2027 *or* bioinformatics methods jnl | draft (2026-10-04) | held-out decomposition benchmark; **fuller CPT decision row** (now measurable — grader fixed today); replay package | **D&B: Jun 2027** / rolling: **Jan 2027** | D&B **~Sep 2027** / rolling **~May 2027** | late 2027 |
| **A — flagship system (C1)** | Nature Methods form | "structurally submission-ready" + gaps | independent grading; **Biomni head-to-head baseline**; QC-loop & rule-vs-LLM ablations; live QC-gate case study (done) | **Jan–Feb 2027** | **~Aug–Oct 2027** (NMeth 4–8 mo; Biomni/Science took ~13 mo) | ~late 2027 / early 2028 |
| **D — on-prem LLM (cost/compliance)** | systems / ML-for-science | 3 overlapping drafts | consolidate to one; reconcile catalog count; **full-corpus CPT**; family-holdout retriever numbers only | **Q1–Q2 2027** | **~Q4 2027** (Cell-class ~8 mo if Cell/Nature-tier) | ~early 2028 |
| **C — Bioc-KB (Paper 2)** | Nature Methods / Bioinformatics | draft | finalize benchmark write-up | **Dec 2026–Jan 2027** | **~Apr–Jul 2027** | ~mid 2027 |

## 3. Takeaways for strategy
1. **Preprint everything at submission.** Every comparator preprinted 8–13 months before journal
   publication and used that window for priority + adoption (Biomni hit >10k labs while in review). Post
   bioRxiv/arXiv the week we submit each paper — the acceptance lag at top venues is unavoidable, so the
   preprint *is* the early public record.
2. **Lead with the fast, strong win (Bioc-KB → NAR).** Strongest committed data, shortest review
   (~2–3 mo). A Jan–Feb 2027 acceptance is the earliest credible external validation; it anchors the
   Phase-A credibility push while the slower flagship is in review.
3. **Don't gate RealBio on NeurIPS D&B.** The 2026 D&B deadline has passed; a rolling bioinformatics
   venue accepts ~6 months sooner than waiting for D&B 2027. Use D&B only for Paper B if its extra
   analyses (decomposition benchmark) land in time for the Jun 2027 deadline.
4. **Flagship (Paper A) is the long pole:** budget **~8–13 months** submit→publish (Biomni's Science
   cycle was ~13). To have it out in 2027, submit by Q1 2027 — which means the independent-grading +
   Biomni-baseline + ablation gap work is the critical path starting now.
5. **Honesty flag:** exact competitor *accepted* dates are unverified (paywalls); the submit→publish
   anchors (Science ~13 mo, Nature ~8–11 mo, Cell ~8 mo) are solid and sufficient for planning. Verify
   the precise received/accepted dates from the article PDFs' history footers before any external use.

## Sources
- Biomni bioRxiv (posted 2025-05-30): https://www.biorxiv.org/content/10.1101/2025.05.30.656746v1 ; Science DOI 10.1126/science.adz4351 (Vol 393 Iss 6813, publ. 2026-07-09; received 2025-06-02 per index) ; PubMed 42424436.
- The Virtual Lab bioRxiv (posted 2024-11-11): https://www.biorxiv.org/content/10.1101/2024.11.11.623004v1 ; Nature 646(8085):716–723, DOI 10.1038/s41586-025-09442-9 ; PubMed 41522341.
- LongevityBench bioRxiv (posted 2026-01-12): 10.64898/2026.01.12.698650 ; Cell 189(19):5980–5994.e8 (publ. 2026-09-17), DOI 10.1016/j.cell.2026.08.026.
