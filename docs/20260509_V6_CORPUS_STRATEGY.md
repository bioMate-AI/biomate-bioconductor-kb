# v6 Corpus Strategy — Scoping

**Date:** 2026-05-09
**Decision:** Start with Option A (synthetic skeleton expansion) immediately; pursue Option B (real §2.6.x acquisition) in parallel as long-tail enrichment.
**Rationale below.**

---

## Goal

Fix the corpus gaps identified by the v2 checklist baseline:

- 0/227 examples ground for MRSD computation (C1)
- 0/183 §2.6.6 examples contain ICH M4S(R2) required subsection structure (A)

The model can't learn skills that aren't in the corpus. v6 must add them.

---

## Option A — Synthetic skeleton expansion

**Approach:** programmatically convert existing 1,727 prose examples into ICH M4S(R2)-structured skeletons with computable numeric chains.

### Sub-tasks

1. **Skeleton-completion task generator**
   - Input: existing FDA-label / EPAR prose paragraph
   - Output: ICH M4S(R2) §2.6.x skeleton with required subsection headings, the input prose distributed into the appropriate subsection, blanks for missing subsections marked `[NO DATA AVAILABLE]`
   - Trains: structural compliance (A), preserves existing prose

2. **MRSD computation task generator** (synthetic but verifiable)
   - Input: NOAEL value, species, body weight, proposed indication
   - Output: HED via FDA BSA factor, safety factor justification, MRSD with arithmetic shown
   - Ground-truth computed by `mrsd_verifier.py` — every example is checker-passing by construction
   - Volume target: 500 examples covering all 11 BSA species with NOAEL range 0.1–2000 mg/kg

3. **Phase-gating task generator**
   - Input: proposed Phase + trial duration
   - Output: required ICH M3(R2) Table 1 studies enumerated
   - Ground-truth from encoded ICH M3(R2) Table 1 (15 cells, deterministic)

4. **§2.6.7 tabulated-summary task generator**
   - Input: §2.6.6 narrative
   - Output: tabulated summary in one of 34 ICH templates
   - Templates encoded as Python dataclasses; generator fills from narrative

5. **Adversity-language task generator**
   - Input: study conclusion text
   - Output: same conclusion restated with ICH-compliant adversity phrasing
   - Source: existing FDA-label tox conclusions; ground-truth via curated rewrite rules

### Pros
- Available now, no external data dependency
- Every example is checker-grounded by construction (high signal)
- Volume scales freely — can hit 5,000+ task examples per category

### Cons
- Synthetic data has its own distribution; model may overfit to template patterns
- Adversity-language and skeleton tasks still rely on existing prose quality
- No cure for the deeper "real submissions look different" gap

### Effort
- Generators: 1–2 days each, ~5 days total
- Generation + validation: 1 day
- Re-train v6 (SFT): 1 day GPU

---

## Option B — Real §2.6.x acquisition

**Approach:** scrape and clean publicly available regulator-published nonclinical content into §2.6.x-shaped examples.

### Sources surveyed

| Source | Contains §2.6.x? | Bulk access | Quality |
|---|---|---|---|
| FDA Drugs@FDA reviews | reviewer prose, *not* sponsor §2.6.x | scrape from drugs@FDA | medium |
| EMA EPAR assessment reports | reviewer prose summarizing §2.6.x | data.europa.eu dataset | medium |
| Australian TGA AusPAR | nonclinical evaluation summaries | TGA website | medium |
| Health Canada SBDs (Summary Basis of Decision) | regulator summaries | canada.ca | medium-low |
| Pharma open-IND (Open Insulin, OSDD) | actual §2.6.x | small handful | high but rare |
| FDA FOIA | actual §2.6.x | months wait, heavy redactions | high if obtained |
| EMA clinical data publication (Policy 0070) | mostly *clinical* CSRs, some nonclinical | bulk via website | high but clinical-skewed |

### Pros
- Real distribution, not synthetic
- Closes the "real submissions look different" gap
- Long-term defensibility — investors/reviewers respect provenance

### Cons
- Most public sources are *reviewer-authored*, not sponsor §2.6.x
- Reviewer prose often re-orders and re-summarizes the original; structural patterns differ from ICH M4S(R2)
- Volume per source is small (TGA/SBD: ~hundreds; FOIA: tens); cleaning + format-normalization is heavy manual work
- Real sponsor §2.6.x is the gold but the smallest pool

### Effort
- Scraper per source: 0.5–1 day each
- Cleaning + ICH-section labeling: significant manual + LLM-assisted; 3–5 days for ~200 high-quality examples
- Risk: ends up looking like the existing EPAR corpus (we already have 2,281 EPAR records that don't pass A)

---

## Recommendation

**Start Option A now. Pursue Option B in parallel for TGA AusPAR + Health Canada SBD (the two best-structured public sources).**

Reasoning:
- Option A is the only path that *guarantees* checker-grounded MRSD and structural-compliance examples in volume.
- Option B's best realistic yield is ~200–500 examples and most of them won't pass the v2 structural checker (same problem as the existing EPAR corpus). Useful as distribution-shift regularization but not as the foundation.
- The hybrid is what production-grade regulatory LLMs actually use (per published Recursion / Owkin / Genesis Therapeutics work).

---

## Order of execution

**Today / next session:**
1. Build MRSD computation task generator (highest checker-impact, smallest scope)
2. Generate 500 examples; validate every one passes `mrsd_verifier.py`; commit
3. Build skeleton-completion task generator (uses existing prose)
4. Generate §2.6.6 skeletons from the 155 §2.6.6 training examples; validate every passes `structural_validator.py`

**Within ~1 week:**
5. Phase-gating + §2.6.7 table + adversity-language generators
6. Combine into v6 SFT mix; re-train v6
7. Run v2 checklist evaluator on v6; expect MRSD pass rate >70%, structural pass rate >80%

**In parallel (background):**
- TGA AusPAR scraper + Health Canada SBD scraper
- Manual labeling pass to extract §2.6.x-shaped fragments
- Add as 5–10% distribution-shift mix to v6 training
