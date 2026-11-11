# VCC 2026 Community Monitor Log

Daily monitoring log for the Arc Institute Virtual Cell Challenge 2026.
Competition closes: **November 5, 2026 23:59 UTC**
Final test set release: **October 22, 2026** (contexts D/E/F)
Our current baseline: Overall ~0.104, pds ~0.43

---

## 2026-09-14

### Items reported

1. **cell-eval2 BREAKING CHANGE — default profile "standard" (Sept 12, 2026)**
   - `strand` was the default; `standard` (fast battery) is now the default as of ~Sept 12.
   - `pds_l1 / pds_l2 / pds_cosine` values also move under `exclude_target_gene=True` for every profile except v1 and cell-eval-0.7.6 — requires baseline artifact regeneration.
   - Source: https://github.com/ArcInstitute/cell-eval2/blob/main/CHANGELOG.md

2. **cell-eval de_systema_test default changed to "z" (Sept 1, 2026)**
   - Previously "wilcoxon" (~5400s / 1000 perts); now "z" (~6.8s). Choice is banner-printed and recorded in resolved eval config.
   - Source: https://github.com/ArcInstitute/cell-eval/activity

3. **Kytos Observatory public experiments (Sept 5–11, 2026)**
   - k003 sparse mean-shift baseline: Overall −0.948
   - k004-resample: Overall −0.304 (rank 656)
   - k005: combined with Replogle K562 genome-wide Perturb-seq bulk data → 272/300 2026 targets covered → Overall −0.021, rank 534
   - Source: https://github.com/udirobert/kytos

4. **arXiv 2608.00152 — "Locked Evaluation Surfaces" (submitted July 31, revised Aug 28)**
   - Shoeibi & Yousefi; frozen Geneformer representation; key finding: within-screen informative representations can fail cross-screen transfer; locked pre-registered protocol.
   - Source: https://arxiv.org/abs/2608.00152

5. **Official VCC 2026 Cell paper published (DOI: 10.1016/j.cell.2026.08.004)**
   - "Virtual Cell Challenge 2026: Benchmarking zero-shot generalization across cellular contexts"
   - Source: https://www.cell.com/cell/fulltext/S0092-8674(26)00931-1

6. **pds_cosine scale-sensitivity insight (community discussion)**
   - L1-based PDS is scale-sensitive; as prediction magnitude increases pds_cosine approaches sign-based cosine similarity. Zero-norm predictions tie at distance 1.0.

### No new items found
- No Arc Institute news/announcements from Sept 13–14 specifically
- No deadline or rule changes
- No new starter code or baseline from Arc
- No top-team methods disclosed
- Leaderboard live but scores not directly scraped (site blocked)

---

## 2026-10-02 (Run 1 — initial)

### Leaderboard (live, validation contexts A/B/C)
Active top scores found; board was updated as recently as 4–13 hours before scan:
- **#1 Illumina AI** ("PerturbationAI"): Overall **0.4185** — 55 submissions, ~4h ago
- **#2 cqawesome** ("m0949r"): Overall **0.3282** — 78 submissions, ~13h ago
- #82 kaipengm2: Overall **0.1545** — "Simple Atlas Transfer Method" (open source, MIT)
- yashnil (rank 370): Overall **0.139** — 3-source ensemble
- MMatinGerami (rank 433): Overall **0.137** — 8-source norm-restored transfer
- ferry-ai: Overall **0.1448** — reported at t28
- Our team: ~**0.104** (estimated rank ~500–700)

Direct leaderboard URL blocked by proxy; scores sourced from GitHub repos and search snippets.

### New/notable GitHub repos
- `kaipengm2/Virtual-Cell-Challenge-2026` — **ACTIONABLE** (MIT, open source)
  - 5-source weighted ensemble: K562_GWPS + HCT116 + HEK293T + H1_2025 + CD4_DE
  - Adds "promoter-neighbor correction" (mechanism TBD — code in repo)
  - Integer counts generated to match mean CPM + pseudobulk profiles
  - Adding H1_2025 and the correction could lift us from 0.104 → 0.15+
- `MMatinGerami/zero-shot-perturbation` — uses 8 sources incl. Nadig HepG2+Jurkat, CD4+ T
- `yashnil/virtual-cell-generalization` — key finding: priors for never-perturbed genes fail externally (0.51 → 0.06), direct measurements maintain 0.30–0.32 across 19 lines

### New datasets (Awesome-Virtual-Cell PR #16 by MMatinGerami)
- **Primary CD4+ T cell Perturb-seq** (Zhu et al., Cell 2026) — genome-scale, primary human
- **TRADE HepG2/Jurkat** (Nadig et al., Nat Genetics 2025) — GEO: GSE264667
- ACTIONABLE: Adding these two atlases could improve Jurkat (our A context) and expand immune/liver coverage

### New papers
- **D²R²** (arxiv 2608.15288): Discrete diffusion + gene regulatory network for perturbation prediction. Best on Norman19 + VCC-H1. DL approach, not directly applicable to our mean-transfer, but shows frontier.
- **"Locked Evaluation"** (arxiv 2608.00152): Geneformer FAILS zero-shot transfer (negative Spearman rho = −0.139 to −0.267). VALIDATES that direct perturbation evidence >> foundation model embeddings. Supports our multi-source-mean approach.
- **VCC 2026 benchmark paper** published in Cell: "Virtual Cell Challenge 2026: Benchmarking zero-shot generalization across cellular contexts" (Cell S0092-8674(26)00931-1). New this cycle.

### Deadline / rule changes
- Final test set (D/E/F) releases **October 22** — ~20 days away
- Final submissions due **November 5** — ~34 days away
- No rule changes detected

### Blocked sources
- virtualcellchallenge.org (leaderboard) — blocked by proxy
- arcinstitute.org/news — blocked by proxy
- arxiv.org — blocked by proxy
- ingenix.substack.com — blocked by proxy
- blog.pebblous.ai — blocked by proxy

---

## 2026-10-20 (Run 2)

### Sources scanned
- virtualcellchallenge.org (DNS unreachable from container; used search snapshot)
- arcinstitute.org/news (DNS unreachable; used search results)
- Twitter/X @arcinstitute
- GitHub solution repos
- bioRxiv/arXiv
- pebblous.ai blog

### Items surfaced today

**[CRITICAL TIMELINE] Final test set releases Oct 22, 2026 (2 days away)**
- Source: https://virtualcellchallenge.org/leaderboard (search snapshot)
- Validation phase closes; 3 held-out cell lines revealed. Final submissions due Nov 5.

**[LEADERBOARD SNAPSHOT — validation phase, undated]**
- ~1,494 teams on leaderboard
- Top team: Illumina AI "iCell" — Overall 0.4665 (77 submissions)
- Our baseline: Overall ~0.104 (well below top; pds ~0.43 is competitive on that metric)

**[NEW PREPRINT — ACTIONABLE] PIE: Generalizing perturbation effects across unseen perturbations, contexts and datasets**
- URL: https://www.biorxiv.org/content/10.64898/2026.10.02.756297v1
- GitHub: https://github.com/ArcInstitute/pie
- Arc Institute news: https://arcinstitute.org/news/pie
- Posted Oct 5, 2026. **From Arc Institute itself** (Verma, Adduri, Bevilacqua, Eraslan, Burke, Goodarzi, Roohani).
- Uses Perceiver IO + curated biological knowledge sources + mean control expression to predict DE for unseen (context, perturbation) pairs. Models population-level (differential) effects, not absolute post-perturbation expression.
- Reports 1.2–3.2× AUPRC over strongest baselines on Replogle-Nadig, including unseen-context unseen-perturbation setting.
- **ACTIONABLE**: Could use PIE's DE-centric framing + knowledge-source augmentation on top of our multi-source-mean transfer. Also worth checking if PIE is available as a scorer to calibrate our predictions.

**[NEW PREPRINT — RELEVANT] Perturbation response decomposition (bioRxiv 2026.07.24.740459)**
- URL: https://www.biorxiv.org/content/10.64898/2026.07.24.740459v1.full
- Finds: global component is low-dimensional and inferable from controls; cell-line×perturbation interactions dominate predictable residual. Explains why uniform cross-line transfer is hard for epithelial lines.
- **ACTIONABLE**: Suggests reweighting transfer by matching control expression similarity (our weak spot for HeLa/CAL-33).

**[NEW PREPRINT — RELEVANT] CFM-GP: Unified Conditional Flow Matching for Gene Perturbation Across Cell Types**
- URL: https://arxiv.org/pdf/2508.08312
- Uses conditional flow matching to generalize across cell types. Evaluated with Cell-Eval metrics.

**[GITHUB REPOS — new solution repos found]**
- https://github.com/MMatinGerami/zero-shot-perturbation — with uncertainty quantification
- https://github.com/ferry-ai/virtual-cell-challenge-2026 — detailed task framing, packaging notes
- https://github.com/yashnil/virtual-cell-generalization — cross-context generalization, cites July 2026 bioRxiv (Molina/Zhang)
- https://github.com/anand-09/virtual-cell-challenge-2026 — control-mean + MLP baseline

**No new Arc baseline/starter code, no rule/deadline changes (Oct 22 test set, Nov 5 close unchanged).**

---
