# L7 model-comparison replay — status and first results (workstream 2, 2026-10-29)
Pre-registrations (research/guangzhou_all_atom/cyclic_llm/loop_retro/PREREG_LOOP.md): L5 (corrected GBM loop), L6 (product chain, partly deferred), L7a–L7f (model comparison, controls, 13-dimension logging, regime L, physchem, K_phys, Tier A/B LLM cost plan). Task scope everywhere: PAMPA permeability of cyclic peptides (CycPeptMPDB).

## 1. L5 (corrected GBM loop, 810/810) — `results/l5_aggregate.json`
In-distribution (A): loop 236.1 hits vs random 49.8 (+186.3, 95% CI 158.5–209.0). Near-duplicate-aware (C): +163.4 (128.1–196.3). **Scaffold-shifted (B): +22.2 (−1.6 to 44.1): claim C1 not met** (within-group hit definition: +41.7, 23.4–61.6; the two definitions disagree). Physchem rule K_z matches the loop in B (52.8 vs 52.3) and reaches 77% of it in A. No knowledge arm helps (15/15 99% intervals include 0). The loop's in-distribution picks are 69% from the largest source. Manuscript updated (`manuscript_loop.md`).

## 2. Controls (planted-signal) — outcomes
GBM/arms core tests (15) pass, incl. stereo-blind = 0 exactly, stereo-aware +0.87, regime-L disjointness, K_phys fusion identity, global-shuffle null. Adapters: atom LM planted ρ +0.84, ChemBERTa +0.90, +phys variants +0.85; v4 prior-relative control reformulated (v4 is contaminated; pre-reg L7a notes). Large LLMs (planted-vs-flipped): **pass** claude-haiku-5.5 (+1.46 SD), gemini-3.1-flash-lite (+0.77); **fail, not run:** llama-3.3-70b (+0.06), llama-4-maverick (shuffled mimics planted), deepseek-v4-flash (reasoning exhausts 16k tokens), qwen3.8-27b (cost). Memorisation probes (30 peptides vs stereo-scrambled decoys): haiku real 0.008 vs decoy 0.019, gemini 0.454 vs 0.446 — not flagged.
**Defects found and fixed during this work (all mine):** shuffled-label null (within-batch permutation retained batch-level signal → global draw); stereo metric (LOO artefact → fixed revealed/target split, ties = 0); shuffled-label adapter bar (3 shuffles → 8 shuffles, then t-test on the empirical null: atom-LM per-shuffle SD ≈ 0.22); frozen-arm SAR label/index mismatch (crashed torch jobs; silent in GBM: `stereo_rho_sar` of frozen arms from runs before commit d602e39d9 is invalid and excluded by the aggregator); reasoning-model token limits; zsh word-splitting in job submission (twice).

## 3. Tier A large-LLM results (first aggregate; `results/l7_aggregate.json`; 4 seeds per regime = **inconclusive (power)** by the pre-registered ≥ 8-pair rule)
Cumulative hits in 5 rounds × 50 picks from the shared 150-candidate subsets (random subset baseline ≈ 19.8 (A), 11.5 (B)):
| model | regime | loop | kb (physchem text) | frozen | zero-shot | shuffled | subset_random | **GBM on same subsets** |
|---|---|---|---|---|---|---|---|---|
| haiku-5.5 | A | 28.3 | 29.8 | 28.5 | 26.8 | 27.3 | 19.8 | **44.8** |
| haiku-5.5 | B | 13.3 | 12.3 | 11.5 | 10.3 | 9.8 | 11.5 | **16.5** |
| gemini-3.1-flash-lite | A | 26.3 | 21.0 | 18.5 | 23.8 | 22.0 | 19.8 | **44.8** |
| gemini-3.1-flash-lite | B | 10.3 | 10.3 | 8.0 | 8.3 | 10.5 | 11.5 | **16.5** |
| gemini-3.1-flash-lite | L | 31.8 | 33.8 | 34.0 | 30.5 | 32.3 | 34.5 | **62.5** |
Reading (exploratory): in-context feedback gives small, inconsistent gains over frozen/zero-shot/shuffled (largest: gemini A loop − frozen +7.8, CI 5.5–10.0); the physchem KB text does not reliably help the LLMs (gemini A: kb − loop −5.3, CI −9.3 to −2.0); LLMs beat random only in regime A; a gradient-boosted model using the SAME revealed labels on the SAME candidate subsets is far ahead in every regime. Stereo-resolved within-group ρ for the LLMs ≈ 0 (−0.07 to +0.08). Haiku regime L was not run (cap).
**Cost (API-reported):** Haiku's real cost was ≈ USD 0.175/sequence vs my 0.088 estimate (hidden reasoning); it stopped at its USD 1.6 cap after 8 of 12 sequences. Gemini 12/12 at ≈ 0.18/seq. Tier A total ≈ USD 4.2 incl. controls and probes — **above the USD 3.4 estimate** (Haiku underestimated 2×); OpenRouter balance now USD 10.60 after the owner's top-up.

## 4. Running / queued (state at 16:55Z)
- L7f GBM spot instance `i-073013accf9c1a4d7` (m6i.8xlarge, launched 12:35Z, active; logs updated within a minute): results so far aware 22, blind 22, physchem 30 task files in `res7f_gbm_*`.
- GPU Batch jobs resubmitted after the fixes (all RUNNABLE, waiting for spot GPU): r2atomA/B, r2cbA/B (regimes A,B, all arms incl. K_phys), r2atomLa/Lb, r2cbLa/Lb (regime L), r2atomP, r2cbP (physchem-channel adapters). Earlier GPU jobs failed for the defects in §2 (no outputs lost; no GPU result exists yet). L5 instance terminated after completion. v4 subset run not started (adapter control being re-run locally).
- Collect/aggregate: `collect_l7.sh` (syncs `res7a_*`/`res7f_*` and `res7a_llm/`, writes `results/l7_aggregate.json`).

## 5. Not done
GPU-model results (atom LM, ChemBERTa, +phys) and v4; large-LLM Tier B (needs funding; estimate USD ≈ 93–116 for sonnet-5.5 + gemini-3.8-flash + deepseek-v4-pro at the full protocol; ≈ 198 with opus); one-shot/contradicted-KB/curve arms for large LLMs; held-out family recovery (needs the binding replay); LLM-in-the-loop with fine-tuning on target families (L7); product-chain arms (L6: `chain_exec`, KB-equivalence test, product permeability signal blocked by the workflow not honouring `smiles_list`); a patch note for the peer RSI manuscript.
