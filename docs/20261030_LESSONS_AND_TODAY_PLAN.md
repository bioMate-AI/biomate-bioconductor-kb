# Lessons learned (2026-10-27 → 10-30) and the plan to a verified manuscript draft

## A. Lessons — errors we made, what they cost, the rule that prevents them
| # | error | cost | rule from now on |
|---|---|---|---|
| 1 | Built new things before reading earlier work (atom LM from scratch; hybrid proposal without the SNG/neurosymbolic docs; Stage B cofold selector; a whole survey that missed the C2 run and replay_permeability) | days of compute and effort | **Excavate first**: before any build, search docs, S3, git history and other worktrees; write the inventory, then decide. |
| 2 | Misread "large LLM" as NLP LLMs and ran paid API arms | ≈USD 4.3, a detour, owner's trust | **Confirm the definition of the central claim in one sentence with the owner before launching anything**; echo it back in the plan. |
| 3 | Paid API spend started without telling the owner; key shared with other work; wrongly attributed a top-up to the owner | cost and confusion | **No paid calls without an estimate shown first; verify attributions before stating them; use a dedicated limited key.** |
| 4 | Reported results before auditing (parse_helm bug, zero-byte CIFs, pooled vs within-source labels, knowledge-scale mismatch, stereo-blind fingerprints, Haiku overrun) | retractions, rework | **Audit first; planted-signal positive control before any null is believed; suspect our own code first.** |
| 5 | Benchmark shortcuts: similarity (AUROC 0.914), typicality (no-target control 0.665), leave-one-out artifact (−1.0), analog lookup dominating | invalid comparisons | **Validity gates (no-target, typicality, shuffled-label) are required for every benchmark; report control-adjusted.** |
| 6 | Treated pooled public data as if labs were comparable | inflated apparent skill (0.67 grouped vs 0.22/0.21/0.25 leave-labs-out, post source-defect fix; ≈0.30 pre-fix) | **Within-source standardisation; leave-labs-out is a primary regime; model lab offsets.** |
| 7 | Over-claiming wording ("did not help", "chance by construction", "first") | credibility | **State power and limits next to every null; tag every number [VERIFIED:file] / [PENDING]; no "first" without a prior-art check.** |
| 8 | Citations from tool summaries | possible mis-citation | **Open the primary source; unverifiable items tagged [UNVERIFIED] and kept out of the text.** |
| 9 | Stalled agents / long jobs with hidden logs / idle instances | wasted time and cost | **Timeouts on every call; incremental log upload; terminate idle instances; check running resources at each status.** |

## B. What "manuscript ready today" means (honest scope)
Not submission-ready: pending experiments (GPU model runs, IH-LM ladder, P1 pretraining, technique tests, C2 reproduction) may not all finish, and several citations remain unverified. **Target for today: a complete, internally consistent, claim-evidence-checked draft (v1)** in which every number traces to a committed artifact, every pending item is either filled from a finished and audited result or moved to "planned/limitations", and the story stands on what is verified.

## C. Tracks (parallel) and the freeze rule
| track | owner | deliverable today | depends on |
|---|---|---|---|
| T-LOOP | WS2 (+WS1 as one team) | L5 final, L7 aggregate (GBM/physchem/kNN/GP baselines; atom LM, ChemBERTa; IH-LM rungs R0–R4 as far as built; controls) | GPU jobs, IHLM interface |
| T-MODEL | WS1 | IHLM tests passing and committed; P0 intrinsic numbers; P1 only if timing probe and cost rule allow (otherwise planned) | test suite |
| T-TECH | T1, T2, WS7 agents | pre-registered technique results with kill criteria (fusion, acquisition, anchors); C2 reproduction | CPU runs |
| T-EVAL | WS3 | H4b scoring of whatever score files exist; validity-gate reporting | score files from T-LOOP/T-MODEL |
| T-PAPER | WS6 | assemble results sections from committed artifacts as they land; related work with verified citations; limitations; RSI-companion patch note | all of the above |
| T-QA | new: claim-evidence auditor | ledger: every claim → artifact → verified?; red-team review; finds errors before any reader does | draft text |
| T-FIG | new: figures builder | reproducible figure scripts from committed JSON for the figure plan | aggregates |
**Freeze rule:** at the freeze time chosen by the owner today, any experiment without a finished, audited result is moved to Limitations/Planned; nothing unfinished is described as a result. After the freeze: QA pass, number-trace pass, citation pass, then the draft is tagged.

## D. Order of operations today
1. Collect finished results continuously (commit aggregates). 2. QA auditor builds the claim-evidence ledger on the current draft now and re-runs after each fill. 3. Figures are generated from committed JSON only. 4. Freeze → consistency pass → tag `draft-v1`. 5. Owner review gate before anything is submitted or released.

## E. Schedule to the owner's midnight review (set 2026-10-28 15:14 CDT)
Owner reviews at midnight CDT. New experiment launches allowed until 19:30 CDT only if they can finish by 21:00. **Experiment freeze 21:00 CDT**: anything without a finished, audited result moves to Planned/Limitations. 21:00–22:30: assemble results, rerun the claim-evidence ledger, regenerate figures from committed artifacts, citation pass (primary-source verified only). 22:30–23:30: final audit, tag the draft, write the REVIEW BRIEF for the owner (docs/20261030_REVIEW_BRIEF.md: verified claims, nulls, open issues, decisions needed, spend). GPU comparators: cumulative spot cost cap USD 40 for the L7 GPU runs, self-terminating, report spend rate. No paid LLM APIs. No release or submission without owner review.

## F. Simplification (owner, 2026-10-28 ~15:30 CDT)
No freeze time and no launch cutoffs. Work continuously until the owner's midnight review: add each result to the draft as it finishes AND passes its audit/controls; anything not finished by midnight stays "planned". Unchanged: verified-only claims, typed intervals, cost caps (USD 40 L7 GPU; no paid LLM APIs), review brief by ~23:30 (docs/20261030_REVIEW_BRIEF.md), final auditor pass before the brief.
