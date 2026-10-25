# Committee review — a better LLM, a better loop, a better output (2026-10-25)

**Chair's synthesis.** Eight reviewers from eight labs read the same packet and each took one adversarial mandate. Their output is *evidence to
check, not truth*: every claim below that I relied on was verified against code or data in this session, and the ledger in §2 says which held.
Raw reviews: `research/guangzhou_all_atom/docs/committee_raw/20261025/` (including the two truncated first attempts and the two credit-limit
errors, kept as a record). Harness: `research/guangzhou_all_atom/committee/committee_review.py`. Exact packet sent: `…/PACKET_SENT.md`.

## 1. How it was run (and what went wrong)
| id | mandate | model actually used | outcome |
|---|---|---|---|
| A | claims audit | openai/gpt-6.1-sol-pro | complete |
| B | methodology / generalisation | google/gemini-4-argon | complete |
| C | physics + code | **anthropic/claude-sonnet-5.5** (Opus 5.5 first attempt hit a credit limit; the harness fell back) | complete |
| D | LLM architecture | moonshotai/kimi-k3.1-pro | attempt 1 truncated (11.5k of 12k output tokens spent on hidden reasoning); rerun with `effort=low` complete |
| E | loop / verifiable rewards | deepseek/deepseek-v4-pro-0813 | complete |
| F | innovation | x-ai/grok-4.7 | complete |
| G | medicinal chemistry / output | z-ai/glm-5.3-prime | attempt 1 truncated the same way; rerun complete |
| H | red team | qwen/qwen3.8-max-prime | attempt 1 hit a credit limit (HTTP 402); rerun complete |

Sent: the brief, three findings docs, and six code files (~26k tokens). **Excluded:** candidate sequences, CRO panels, credentials (scanned before
sending). Cost ≈ $1.7; OpenRouter balance afterwards $11.23 (the account had ~$2 left when the run started — it was topped up mid-run).
**Limits of this committee:** all eight read *my* brief, which emphasised failures, so broad agreement partly reflects anchoring, and three
reviewers are not independent of the model family that wrote the brief. They did **not** find two of the most concrete defects below
(`kb_admissible` no-op; v2 panel fails H5) — verification did.

## 2. Verification ledger (what I checked, and what held)
**Confirmed in code/data**
| claim (reviewer) | result |
|---|---|
| `reward.py` weights FEP 0.90 as "TRUSTWORTHY ARBITER" and keeps MM-GBSA as a 0.45 fallback (A,C,D,E,F,G) | **true** (`reward.py:39-40`). Nuance: `score()` only fills admissible physics, so αvβ6 MM-GBSA stays pending there, but `reward()` has no guard of its own |
| `reward._num` accepts `bool`, NaN, inf (A) | **true** (`_num(True)→True`, NaN→nan, inf→inf) |
| non-gate bonuses can sum past the gate base, so gate dominance is not guaranteed (A) | **true**: 0.30+0.30+0.20+0.90+0.60+0.20 = 2.50 vs gate_pass 1.0 |
| PD-L1 and GRPR can never pass the hard gate (A) | **true**: `rule_pass=None` → `hard_gate_pass=False` for any non-avb6 target (ran `score()`) |
| `rank_key` coerces pending physics to 0.0 (C,D,F) | **true** (`score.py:94-95`) |
| both DPO oracles share features and model class; split ignores order and uses a greedy leader (A,B) | **true** (`methodology_close.py:84-125`): HistGBM on the same `feat()`; unordered monomer-set Tanimoto |
| availability parser defects: 2Nal dropped, `[Met]`→Thr, NMe erased, NaN returned with `False` (A,B,C) | **true; fixed** (`932850d25`, 6 tests) |
| availability anti-aligns with potency on the A1 grid (F) | **true**: ρ(potency, availability) = −0.40 (n = 4); YY→FF −0.231 while 5× tighter |
| A1 is strongly non-additive (A,B); YY→YF +0.81, YY→FY +0.71, YY→FF −0.95 ⇒ coupling −2.47 kcal/mol | **true** (arithmetic from the 4 IC50s) — the control edge is a *double* mutation whose single-edge effects have the opposite sign |
| the FEP readiness guard sits on the superseded path; fan-out is not HREX (several) | **true** (code review earlier) |

**Found by verification, not by the committee**
- `methodology_close.to_helm()` produced a string the gate parser reads as **one token** → `kb_admissible` was a **no-op for the permeability signal and
  reject-all for the avb6 binding signal**; Asn-Gly/free-Cys/double-Trp passed; a valid RGD peptide failed. So the earlier "rule-constrained DPO ≡ unconstrained →
  gate never bound" reading was **uninformative, not a null**. Fixed + 5 tests. (B diagnosed the symptom; its stated mechanism — an exception failing open — was wrong.)
- **All 8 v2 αvβ6 candidates fail hard gate H5 (single Lys chelator handle; `_n_lys = 0`)** while passing H1–H4. The position-9 NMeLys that doubles as the conjugation
  site was replaced for FTO divergence. As designed, none can be conjugated to a chelator. (G's stated reason — "panelB has no RGD" — conflated two panels, but the
  direction was right.)
- Bulk-water behaviour of the CaDA-Mn cage (free from build1's misplaced ions): coordination number 6, mean first-shell Mn–O(water) **2.25 ± 0.05 Å**, cage M–D 0.903 Å
  (sd 0.011) over ~120 ps of bonded-cage NPT. Reference hexa-aqua Mn(II) ≈ 2.18–2.20 Å **[from memory — UNVERIFIED]**. A partial, free, positive data point — not a
  hydration free energy, not exchange kinetics, not site binding.
- **Assay buffer of the −0.95 anchor** (Kapp 2017, open access, the protocol Quigley 2023 cites): 20 mM Tris, 150 mM NaCl, **1 mM CaCl₂ + 1 mM MgCl₂ + 1 mM MnCl₂**, pH 7.5, 1 % BSA;
  immobilised ECM ligand + soluble integrin; IC50 referenced to an internal standard. So the anchor is **not** a Mg/Ca-only assay and a Mn-bound MIDAS is reasonable; ADMIDAS/SyMBS
  occupancy in a mixed buffer is still unresolved. (Quigley's wording says "immobilised integrins"; Kapp's protocol immobilises the ligand — a discrepancy I could not resolve.)

**Refuted**
| claim | why wrong |
|---|---|
| `seq_logp` is mis-shifted (A) | the model prepends a target-conditioning slot (output length t+1); `logits[:len(ids)]` against `x` is the correct alignment; causality test passes. A unit test is still worthwhile |
| "the grid closes to ~0.6 kcal/mol / closure sets the noise floor" (C; G attempt 1) | closure is an **identity** (all three paths = +0.947) when edges derive from the same four IC50s; the coupling is −2.47; noise comes from the CIs (~0.4–0.6 kcal/mol/edge) |
| gate "FF > YF ≈ FY > YY" (E) | measured order is FF > **YY** > FY > YF |
| `revise()` cycles (C) | not reproduced: a finite 3-rule chain *(reasoned, not executed)* |
| `patent_id` can be `None` (C) | not reproduced for avb6 (floats 1.0 / 0.11); unchecked for PD-L1/GRPR |

**Still unverified:** that the generator's pre-training included the oracle-B peptides (B; data lineage not checked); every novelty claim ("first", "no predictor existed");
the Landry CC BY-NC-ND licence question; ADMIDAS/SyMBS metal identity; the hexa-aqua reference distance.

## 3. Consensus (number of reviewers who independently said it)
1. **Unknown must not equal zero; mask pending/inadmissible/out-of-domain physics; delete the MM-GBSA fallback and the "trustworthy arbiter" wording.** (7/8: A,C,D,E,F,G,H)
2. **The cheap decisive next experiment is one unrestrained ≥1 ns metal run (~$10–15), and the live FEP path must refuse to submit without a passing post-mode certificate.** (7/8)
3. **The LLM must beat exhaustive enumeration at matched cost before anything is trained** — the design space is 80 triples; today the LLM/loop is overhead. Rename `neural_generator`
   (a permeability re-ranker) and `revise()` (a constraint-repair chain); stop calling anything "closed loop" except the permeability DPO. (A,B,C,D,E,F,H)
4. **Typed evidence instead of "validated":** every number carries method, status (measured / reproduced / screen-pass / unvalidated / abstained), scope and provenance. (A,D,E,F,G)
5. **Anchors are locks, not training data:** A1/A2 can calibrate or test, never both; evaluate with noise-aware, stratified concordance (not Pearson on n = 4); run **all four A1 edges**
   because the grid is non-additive. (A,B,C,E,F)
6. **Pose, metal identity and sampling are three separate uncertainties:** no co-structure for A1/A2, a clashed cofold pose, a mixed-cation assay, and independent 0.5 ns windows with
   analytic-BAR errors. Need ≥3 replicas, pose-ensemble robustness, honest error bars. (B,C,F,G,H)
7. **The output should be a falsifiable decision record, not a binder list:** typed provenance, abstention where the oracle is inadmissible, and predictions registered *before* any measurement. (A,D,E,F,G)
8. **Radioligand-specific failure modes are absent from every reward and gate** — renal retention, plasma stability, chelator effects, αvβ3 off-target (G only; high value). The reward optimises what is
   computable, not what kills radioligands.

## 4. Where reviewers disagreed, and how I resolve it
- **Stop vs. continue (F,H,D,G: stop building a binder/generator vs. B,C,E: build an FEP anchor ladder).** Resolution: these agree on sequencing. Spend the ~$10 and ~$100 experiments that decide whether
  physics is usable (metal run → YY→FF with replicas), and *pre-commit the pivot*: if either fails, binding stays masked and the system ships as a rule/evidence/availability filter plus benchmark.
- **How strict is the metal test?** C wants ≥10 ns × 3 replicas and the full 6-O coordination; our plan was 1 ns and ≥2 O. Resolution: stage it — 1 ns as a *screen* (cheap, can only reject), then 10 ns × 3 if it
  passes; tighten "≥2 O" to the intended counts seen in the pre-EM gate (Mn1/Mn2 ≥ 4 sustained, Mn3 keeps the ligand Asp). A pass is "structural-stability screen passed", never "metal model validated" (A).
- **Use A1/A2 to fit a local SAR model (E) or keep them as a lock (B,F)?** Resolution: they are *development data* now (they have already shaped decisions). A local model on them may be built for
  uncertainty/abstention (E's GP, reporting leave-one-out), but every claim needs a separate test set — so the **cheapest high-value action is to expand the anchors from the literature** (H: ≥50 scaffolds
  would be needed for any decision-grade oracle; we have ~10). The paywalled SAR papers the lock agent could not open are the first targets.
- **Eight "one innovation" bets** (A counterfactual evidence certificates; B thermodynamic-cycle edit-graph proposer; C metal-aware FEP anchor ladder; D falsification-contracted edit policies;
  E anchor-calibrated multi-fidelity reward + pre-registered active learning; F claim-survival ledger + frozen audit-challenge benchmark; G pre-registered per-position falsification dossiers;
  H FEP protocol as an open benchmark / negative result). **Convergent core (A,D,E,F,G): typed evidence → admissibility → abstention → pre-registered predictions.** That is cheap, needs no wet lab,
  is the one thing this program uniquely has (a documented audit trail of how it was wrong), and is community-usable. B's cycle-closure idea is the only physics-novel one and is a sound
  *error check* (closure through two measured anchors is a label-free sampling-error estimate) but is downstream of a working metal model. Novelty of every variant is **[UNVERIFIED]** — SynCraft already
  removes "LLM + rules + computation" as a claim.

## 5. What to build (ordered; gates are pass/fail and written before running)
**Done this session:** Mn frame fix + gate + validator; relaxation restraints + dispatch guard; unrestrained validation stage; `kb_admissible` fix; availability parser/abstain fixes; regression tests (11).

**P0 — cheap, no GPU, unambiguous (next):**
1. `reward.py`: delete the MM-GBSA fallback and "trustworthy arbiter" wording; `ddg_fep` weight 0 unless a certificate is attached; `_num` rejects bool/NaN/inf; gate dominance guaranteed (lexicographic). `score.py`: typed pending in `rank_key`;
   target-specific rule policy so PD-L1/GRPR are not auto-failed (explicit `no_rule` state).
2. `fep_production.py`: refuse to submit without a post-mode JSON bound to the topology/coordinate hashes of the run (the guard now lives only on the dead path).
3. **v2 αvβ6 panel:** decide the conjugation strategy (restore a Lys handle, or document the intended site) before the panel is treated as radioligand-ready — all 8 fail H5.
4. `target_kb/avb6_measured_sar.json`: the A1 grid + A2 scan + selectivity ratios with PMID, assay buffer (1 mM Ca/Mg/Mn, Kapp 2017), censoring flags; a noise-aware stratified-concordance benchmark with an exact permutation test (B's design) — and a 0-GPU baseline to beat.
5. Dossier + claim-ledger skeleton: typed status per number, `predictions.json` written and hashed before any run, explicit abstention for binding, a `radioligand()` informational block (G).
6. Unit tests for the things reviewers worried about and that are cheap: DPO teacher-forcing alignment, `rank_key` ordering with pending, `_num`.

**P1 — spot GPU, needs your go (~$10–15):** restrained equilibration (build2) → unrestrained 1 ns → `validate_mn_coordination.py --mode post`. Already built (`fep_batch.py --equil --mn-restrain`, `--mn-validate`).
**P2 — only if P1 passes:** 10 ns × 3 replicas; YY→FF with ≥3 replicas/HREX against −0.95 (pre-registered band); **all four A1 edges** (non-additivity −2.47 is the stress test); Asp→Ala; then a cycle-closure check.
**P3 — LLM:** a frozen strong LLM as a typed-edit proposer over a deterministic executor with evidence cards — **only after** it beats enumeration + deterministic repair at matched verifier calls by a pre-registered margin
(D: ≥10 % absolute repair success, bootstrap CI excluding 0). Its real room is where enumeration is infeasible (PD-L1 12-mers, ring/linker edits), not the 80-triple αvβ6 space.

## 6. Pre-registered decision rules (written before any of P1–P3 runs)
- Unrestrained 1 ns: every Mn keeps ≥ 2 protein/ligand O for the whole run and the cage holds → continue to 10 ns × 3. Any UNBOUND → stop FEP on this pose; re-pose from 8TCG/4UM9/9XMM (not a smarter LLM).
- YY→FF (after the above): sign negative **and** |computed − (−0.95)| ≤ 0.5 kcal/mol **and** replica SEM ≤ 0.3. Miss → `fep_magnitude = REJECT`, binding weight stays 0, no panel is ordered.
- A pass on one distal edge validates nothing about the metal (C): the Asp→Ala edge and all four A1 edges are required before FEP enters any reward.
- No binding-improvement claim without wet-lab data. A loop result is reported as a methodological claim only.
