# VCC 2026 Community Monitor Log

## 2026-10-20 (Run 1 — initial)

### Sources scanned
- virtualcellchallenge.org (DNS unreachable from container; used search snapshot)
- arcinstitute.org/news (DNS unreachable; used search results)
- Twitter/X @arcinstitute
- GitHub solution repos
- bioRxiv/arXiv
- pebblous.ai blog

### Previously reported: N/A (first run)

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
