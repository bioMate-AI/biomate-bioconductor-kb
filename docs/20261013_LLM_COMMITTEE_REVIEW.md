# Cross-model committee review of the v2 sequences (pre-wet-lab gate)

**Date:** 2026-10-13 · Independent review of the 18 v2 candidates by frontier models from three providers,
BEFORE any synthesis — the gate round-1 lacked. Rubric = `20261013_SEQUENCE_REVIEW_KEY_POINTS.md`.
Runner: `research/guangzhou_all_atom/llm_committee_review.py` → `results/llm_committee_review.json`.
This is a **review/sanity layer, not validation** — it does not replace docking/MM-GBSA/wet-lab.

## Committee
- **OpenAI `gpt-6.1-sol-pro`** — full structured review ✅
- **Google `gemini-3.1-pro-preview`** — full structured review ✅
- **Anthropic `claude-opus-5.5`** (via OpenRouter) — returned empty content (provider quirk); the Claude
  perspective is represented directly by this session. Honest gap, not hidden.

## Consensus findings (acted on)
1. **Binding ≠ function / selectivity (unanimous).** Every candidate needs *functional* and *off-target*
   assays, not just a binding score: αvβ6 → αvβ3/αvβ5/αvβ8 counterscreens (bare RGD binds all); PD-L1 →
   PD-1/PD-L1 blockade reporter. The `PASS`/`LEAD`/`extended-affinity` labels are **not experimental
   evidence**. Our computational pipeline (cofold iptm, MM-GBSA ΔG) covers **binding only**.
2. **Tryptophan oxidation — a liability our gate MISSED (GPT-6 + Gemini).** We flagged Met but not Trp.
   **Fixed:** added `cmc:Trp-ox` to `knowledge_liability_flags.py` and re-gated. NOTE Trp is often
   load-bearing (the PD-L1 aromatic cleft face) → flag, don't auto-remove; address by formulation.
   Re-gated tiers: **αvβ6 = 4 PASS / 6 WATCH** (PASS = the Trp-free K-03/05/06/07), **PD-L1 = all 8 WATCH**.
3. **Pharmacophore — sequence present, geometry unproven.** αvβ6 RGDL + lock confirmed at sequence level
   (GPT, Gemini) but "productive geometry remains unproven" (GPT); PD-L1 IgV-cleft chemotype **cannot be
   confirmed from sequence** (GPT challenge) — structure-gated, docking decides.
4. **The v2 liability-fix EDITS are activity-cliff risks (Gemini NO-GO; GPT echoes).** Fixing a CMC
   liability by editing can break structure-gated binding:
   - **AVB6-K-09** — 4 simultaneous flank mutations to dodge FTO → likely breaks the lock/selectivity.
   - **PDL1-K-03** (Asp-Ser→Ser-Asp), **PDL1-K-04** (K-D-G→K-G-D tail reorder), **PDL1-K-08** (core L→T) —
     sequence/backbone changes risk destroying the structure-gated PD-L1 interaction.
   i.e. our v2 traded a CMC liability for a cliff risk on these four — they must be **dock-validated or
   redesigned before synthesis**, not advanced on the liability-clean label alone.
5. **Identity discrepancy (GPT) — PDL1-K-02.** The `[NMeL]` in the HELM (the intended N-methyl-Leu
   conformational element) vs the "Nle" production note (for the *Met→Leu* oxidation fix at a different
   position) must not be conflated. **Resolution:** position-2 `M→L` is the oxidation fix (production = Nle);
   the `[NMeL]` lock residue is unchanged and separate. Documented so synthesis is unambiguous.

## Convergent recommendation
- **Lowest-risk for the first wet-lab round (committee top picks ∩ our PASS set): AVB6-K-05, K-06, K-07,
  K-03** — minimally edited, Trp-free, clean developability, pharmacophore intact; plus **PDL1-K-02** as the
  single conservatively-edited PD-L1 (Met→Leu only). These are *provisional lower-liability choices for
  functional/selectivity testing, not validated leads* (GPT).
- **Hold-for-redesign (NO-GO as-is): AVB6-K-09, PDL1-K-03, PDL1-K-04, PDL1-K-08** — heavy edits = cliff risk.
- **Overall committee verdict: HOLD.** Nothing advances to wet-lab as "validated." Advance the conservative
  top picks through the **binding** physics (cofold→MM-GBSA — now validated for *both* targets) **and** the
  **functional + selectivity** assays; redesign the four NO-GOs.

## Actions taken from this review
- Added **Trp-oxidation** to the liability gate; re-gated v2; regenerated the reviewer CSV.
- Resolved the **PDL1-K-02** NMeLeu-vs-Nle ambiguity (documented above).
- Flagged the **four activity-cliff NO-GOs** for dock-validation/redesign before any synthesis.
- Reaffirmed the **binding≠function** boundary: results labeled "binding prediction"; functional +
  selectivity assays are mandatory wet-lab legs, not optional.

## Honest limits
The committee is a cheap cross-model *sanity* gate — it reasons from sequences + rubric, not from structure
or data. It cannot confirm binding, function, or selectivity; it de-risks by catching mechanism/liability/
consistency errors (which it did) before money is spent. Docking/MM-GBSA (binding) + wet-lab (function +
selectivity) remain required.
