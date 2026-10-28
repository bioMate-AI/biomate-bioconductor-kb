# External committee, round 2 — synthesis (2026-10-30)

Task: external LLM review of the whole package (manuscript draft, claims table, code excerpts, data-audit headlines), then independent verification of every specific code or data defect the reviewers claim. **Committee output is opinion, not evidence; status below is what I checked in the repo.**
Packet: `docs/20261030_COMMITTEE2_PACKET.md` (about 30k tokens, own material only; no candidate sequences, credentials or keys; scanned). Raw outputs and runner: `docs/committee_raw/20261030b/ext_*`.

## 1. Who reviewed, and cost
| reviewer | model | outcome | reported USD | counted USD |
|---|---|---|---|---|
| GPT | openai/gpt-5.5 | complete (4,919 tokens out) | 0.2987 | 0.2987 |
| Gemini | google/gemini-3.1-pro-preview | complete (3,756 out, 1,790 reasoning) | 0.1128 | 0.1128 |
| Anthropic | anthropic/claude-sonnet-4.6 | **no review**: `finish=length`, all 9,000 completion tokens were reasoning, content empty; not a refusal. One attempt, no retry (directive). Raw record kept | 0.2404 | 0.3606 (x1.5) |
Counted total **USD 0.772** of the 2.00 cap. Balance read before the first call 3.961; after the last call the credits endpoint reads 3.549 (it appeared to lag: it showed no change after GPT and Gemini). Expected true balance about 3.31 after Sonnet's reported 0.24 posts; the key is shared with other consumers, so the account balance cannot be attributed to this task alone. Reserve of 0.75 was never at risk. Reviewers covered: two of three requested labs. A retry of Sonnet with reasoning disabled would cost about 0.15 to 0.35 and was not run.

## 2. What the two reviewers agree on
- **Most damaging flaw, two answers:** GPT: the central comparison (in-house model vs larger pretrained models in the loop) has not been run, so the manuscript is not evidence for its main model hypothesis. Gemini: analysis I fails the no-target fingerprint control (0.584), so the binding benchmark measures dataset bias. Both are already stated in the draft; neither is new information, but both say the draft frames them too softly.
- **Publishable only as an evaluation / audit / null-results paper**, with Aim A removed from the title and abstract as a delivered aim and kept only as pre-registered future work.
- **The K_phys loop contrasts (54, dependent, uncorrected, 10 seeds) are over-narrated**; move to an appendix or label exploratory only; apply Holm or similar if kept.
- **Use cluster-based intervals for any generalisation language**; seed-based intervals only for variability over initial sets.
- **Regime L is not a clean leave-laboratories-out design** (6 to 18 held-out labs per seed, Townsend and Kelly never held out, all eligible labs held out in 3 of 10 seeds); run L9 or remove interpretation that depends on it.
- **Too many arms and regimes** for a reader; one primary-claims table with estimand, unit, interval type, pre-registration status and verdict.

## 3. Disagreements and my reading
- Gemini calls the dataset "fundamentally flawed" for target-specific binding; GPT calls the gate failure a result about this collection and these constructions only. The checks in Section 4 support GPT's narrower wording: the gate numbers are not a pipeline artefact, and they are not caused by compound overlap across folds, but they only show that compound-only information separates positives from decoys here.
- Gemini says the shifting from spread to post hoc bootstrap intervals "weakens rigor"; GPT says the typed labelling is better than most papers but the sentence "no threshold, feature set, model or contrast is chosen after seeing a result" is too broad. I agree with GPT (VERIFIED the sentence exists, Section 4.9 line 110).

## 4. Verification of every specific code or data claim
Status: VERIFIED (true as stated), PARTLY (true but changes no reported number or only interpretation), REFUTED, UNVERIFIED.

| # | claim (reviewer) | check | status | changes a reported number? |
|---|---|---|---|---|
| 1 | `cluster_contrast` seed-only bootstrap: `vals` can be empty, `np.mean([])` gives NaN (GPT, Gemini) | code has no guard (aggregate_l7.py lines 68-72). `np.mean([])` returns NaN with a warning; it does **not** crash `float()` as Gemini states (REFUTED part). Committed `l7_aggregate.json`: 0 NaN fields | VERIFIED (latent), crash claim REFUTED | No |
| 2 | `_family_ci` weights families equally and silently drops targets with NaN AUC (GPT, Gemini) | code: `fm = d.groupby("family").auc.mean()`, `d[d.auc.notna()]` | VERIFIED | Interpretation only (family-level estimand); manuscript does not call it "family mean" explicitly in the gate sections I searched (not found by grep); add |
| 3 | `control_auc` `items_used_frac` is global, coverage bias possible (GPT) | code: single global fraction | VERIFIED | Not shown to change numbers; per-family coverage not reported |
| 4 | `multi_proxy_scores` / C3: the same compound appears in several targets and families, so a compound can sit in both training and held-out folds (GPT) | measured in `items_I.csv.gz`: 9,432 rows, 6,619 compounds, 1,731 compounds in >1 target, 364 in >1 family; 1,093 rows (11.6%) have a compound present in another fold. **Rerun with compound-disjoint training** (`ext_check_gate.py`): C2 0.5658 [0.5056, 0.6252] (registered 0.5591 [0.4994, 0.6189]); C3 0.5796 [0.5304, 0.6302] (registered 0.5837 [0.5328, 0.6362]) | VERIFIED as a design property; **REFUTED as the cause of the gate failure** | No for C3 and C1; C2's lower bound moves from 0.4994 (interval contains 0.5) to 0.5056 (excludes 0.5): C2 becomes a marginal failure under the compound-disjoint variant |
| 5 | `prox` index may not be compound_id (GPT, flagged UNVERIFIED) | `proxies.csv.gz` first column compound_id, unique | REFUTED | No |
| 6 | Fold packer: weights are distinct compounds; families without labels absent (GPT, Gemini) | code confirms compounds as weight; all 317 families have pair labels and all targets map to a fold | VERIFIED (weights) / REFUTED (absent families) | No; folds are size- not label-balanced, as documented (fold 0 holds the GPCR family) |
| 7 | `load_groups` standardises labels with source mean and SD from all rows including evaluation rows (GPT) | code: `mu`, `sd` computed over all rows per source | VERIFIED | Labels are the same within-source z used elsewhere (a known mild transductive step); affects absolute label values, not training of any scored model in the reported stereo numbers |
| 8 | `__other__` pooling of sources under 20 peptides distorts labels (GPT) | code confirms pooling; this is the registered L3 convention | VERIFIED | Interpretation |
| 9 | `group_metrics` pair concordance excludes score ties instead of assigning 0.5, contradicting a documented convention (GPT) | code: `if y[a] != y[b] and s[a] != s[b]` | code claim VERIFIED; documented-convention claim **UNVERIFIED** (I found no document stating ties count 0.5) | Concordance 0.669 (chirality-aware GBM) is over pairs with distinct scores; continuous-score GBM has few ties, so effect small; blind scorers contribute no pairs |
| 10 | Constant scores assigned Spearman 0.0 rather than dropped (Gemini) | code confirms; matches the registered protocol (one seeded split, ties give 0) | VERIFIED, as registered | No |
| 11 | `perm_p` has no guard for `den == 0` (GPT) | code confirms. Call site filters labs with `np.std(K) > 0` (lolo_permutation_null.py line 24); y cannot be constant with at least 20 peptides | VERIFIED (function), not triggered | No |
| 12 | `fuse` / `fuse2` need `z()` to handle zero variance (GPT, UNVERIFIED) | `z()` returns zeros when SD < 1e-12 | REFUTED | No |
| 13 | Reliability `clip(...,0,1)` discards anti-correlation, may flatter fusion (GPT) | code confirms; part of registered amendment A1 | VERIFIED | Interpretation; T1 and T1b were null regardless |
| 14 | `analog_perm` uses raw revealed labels, lab offsets could matter (GPT) | analog ranking is within one held-out lab (revealed and remaining peptides share the lab), and mean-centring removes the offset | REFUTED as material | No |
| 15 | Regime L: Townsend and Kelly never held out; held-out set sizes vary (GPT, Gemini) | `regime_L_heldout_sets.json` lists `never_held_out: [2020_Townsend, 2021_Kelly]`, 18 eligible labs | VERIFIED | Already stated in the draft; the phrase "leave-laboratories-out" still overstates it |
| 16 | Numbering inconsistencies: Results (viii) before (vii); Limitations 8a, 8b, 8c, 8e, 8d, 8 (GPT) | abstract line 18 order (vi), (viii), (vii); Section 7 list 8a, 8b, 8c, 8e, 8d, 8 | VERIFIED | No |
| 17 | Sentence "No threshold... is chosen after seeing a result" conflicts with disclosed amendments (GPT) | sentence at draft line 110; draft discloses retrospective gates and post hoc intervals | VERIFIED | No |
| 18 | Proposed test: permute labels and rerun the fingerprint control to learn whether 0.584 is pipeline bias (Gemini) | I ran it: 5 within-target label permutations on analysis I, full gate. Means: C1 0.5075, C2 0.4887, C3 0.5052 (single runs 0.48 to 0.52) | Done | Result: the gate pipeline is unbiased on these compounds; the registered 0.584 is a property of the real labels. Limits: 5 permutations, point estimates only |

No reviewer cited specific literature; the venue suggestions (a datasets and benchmarks track, cheminformatics venues) are opinions. No prior-art claim needed web verification. `[UNVERIFIED]` flags by reviewers were all about code details, resolved above.

## 5. Findings that are new relative to our own audits
1. **Compound overlap across folds in the no-target controls (row 4).** Our gate had not been checked for compounds that occur in several targets. The rerun shows it does not drive the failure, but C2 flips from marginally passing to marginally failing under a compound-disjoint split, which is worth stating as a sensitivity in the gate section.
2. **Label-permutation null of the gate on real compounds (row 18)** is a positive confirmation we did not have: the 0.584 is signal in the labels, not a pipeline artefact.
3. **Latent NaN failure mode and zero-denominator guard** (rows 1, 11): not triggered; add guards.
4. **A statement defect:** the sentence in Section 4.9 is too broad (row 17).

## 6. Action table
| workstream | action | source |
|---|---|---|
| WS6 manuscript | Remove Aim A from title and abstract as a delivered aim; present it as pre-registered future work with falsification criteria; rewrite around three claims (permeability loop baselines, binding-benchmark validity audit, lookup and physicochemical nulls) | both |
| WS6 | One primary-claims table: estimand, unit, interval type, pre-registration status, verdict; denominator table (compounds, flat structures, sources, families, targets, positives and inactives per regime and fold) | GPT |
| WS6 | Quarantine K_phys loop contrasts, T1/T1b, anchor test and cheap-tier API arms to an appendix; show the nine-configuration K_phys result as exploratory with the Holm-adjusted count | both |
| WS6 | Fix numbering (abstract list, Limitations 8a-8e); replace the sentence in 4.9 with "deviations are dated amendments and are labelled exploratory or post hoc"; state that `_family_ci` is a family-level (unweighted) estimand; state regime L as "held-out subset of eligible smaller laboratories, with the two dominant laboratories always retained" | GPT, verified |
| WS6 / WS3 | Add the compound-disjoint sensitivity (row 4) and the label-permutation null (row 18) to the gate section from `ext_check_gate.json` | this synthesis |
| WS2 loop | Run L9 (cap of 9 held-out labs) or remove interpretation tied to the irregular regime-L sets; add NaN guard in `cluster_contrast` seed-only bootstrap | both; row 1 |
| WS2 | Confirmatory K_phys seeds 10-29 with Holm correction remain the test; no K_phys language beyond "exploratory lead" before then | both |
| WS3 benchmark | Report per-family and per-target coverage in `control_auc`; add compound-disjoint training as a registered gate variant; report control-adjusted scores for all arms in one table | GPT; rows 3, 4 |
| WS1 model / WS2 | Minimal end-to-end smoke test of the central comparison (one in-house or proof-of-pipeline checkpoint plus one pretrained comparator, one regime, two seeds, existing controls) to confirm the interface executes; this is the cheapest evidence that Aim A is operationally ready | GPT |
| WS5 KB | Add `den == 0` guard to `perm_p`; keep the permutation-null result as stated | row 11 |
| auditor | Final ledger rerun should check: numbering, the 4.9 sentence, `_family_ci` wording, regime-L wording, new gate sensitivity rows | this table |

## 7. Limits of this round
Two of three labs reviewed; Sonnet's reasoning consumed the output budget, a retry was not run. The reviewers saw only the packet (30k tokens), including excerpts of seven code files; several of their code remarks depend on helper functions they could not see, and I resolved those against the repo. My checks cover each specific claim; I did not re-audit the whole code base. The gate checks used 5 permutations and point estimates only.

Files: `docs/20261030_COMMITTEE2_PACKET.md`; `docs/committee_raw/20261030b/ext_run.py`, `ext_run.log`, `ext_cost_log.csv`, `ext_review_GPT.md`, `ext_review_GEMINI.md`, `ext_review_SONNET.REFUSED_or_empty.json`, `ext_check_gate.py`, `ext_check_gate.json`, `ext_check_gate.log`.

## 8. Addendum: single owner-requested attempt with claude-opus-5.5 (2026-10-30)
Why Opus 5.5 was not in the main round: in round 1 it returned an empty `content_filter` / `refusal` twice, so the round-2 runner used Sonnet 4.6 (which then ran out of output budget on reasoning). On the owner's request I ran **one** Opus 5.5 attempt on the round-2 packet with the same three-role brief, `reasoning.max_tokens = 2000` (so reasoning cannot consume the output), `max_tokens = 12000`, estimate first (worst case USD 0.554 with the 1.5x factor), balance 3.309 before the call (reserve 0.75).
**Result: the refusal recurred at the packet level.** `finish_reason = content_filter`, `native_finish_reason = refusal`, provider "Claude Platform on AWS", `usage = {}` (no tokens reported), message keys `role, content, refusal, reasoning` with an empty `content` and `refusal = null`. No cost was reported or charged (counted USD 0.00; balance 3.309 before and after). Per the instruction: no retry, no rewording, no substitution. Metadata: `docs/committee_raw/20261030b/ext_review_OPUS.meta.json`; script `ext_run_opus.py`; logged in `ext_cost_log.csv`. Because there is no review text, there are no Opus claims to verify. The same packet content passed GPT-5.5 and Gemini 3.1 pro without incident, so the filter is specific to this provider route and not obviously tied to anything in our material (the packet contains no sequences, credentials or keys, and was scanned). I did not try to find which passage triggers it, since that would require rewording experiments.
Spend update: the credits endpoint now reads 3.309, matching the reported charges (3.961 minus GPT 0.2987, Gemini 0.1128 and Sonnet 0.2404); the earlier 3.549 reading had lagged. Total counted spend for this task including the Anthropic factor remains **USD 0.772** (Opus added 0.00). The account balance after this task is **USD 3.309**.
