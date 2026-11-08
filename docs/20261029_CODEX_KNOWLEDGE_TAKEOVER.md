# Knowledge-method takeover audit — 2026-10-29

Read-only inspection of the K2 and K4 workers, their S3 diagnostic outputs, the knowledge-layer output audit, and the incomplete knowledge-augmentation change. No instance launched, stopped, or modified. No release or internal/patent-content export performed. Public release remains paused.

## Live pilot evidence

Status sampled around 20:14 UTC on 2026-10-29. S3 timestamps below are UTC, converted from the local CLI listing. These are intermediate snapshots, not completion results.

| Pilot | Worker | State | Output prefix |
| --- | --- | --- | --- |
| K2 literature extraction | `i-0dace5be00919a762`, g5.4xlarge | running | `s3://biomate-nextflow-work/cyclic_peptide/allatom/k2/k2pilot7_20261029/` |
| K4 patent extraction | `i-0609fef39c55c57f2`, g6.4xlarge | running | `s3://biomate-nextflow-work/cyclic_peptide/allatom/k4/ext3/` |

K2 `stage.log` records successful environment/tests and reuse of the corpus, then resume from `k2pilot5_20261029/extract`. The persisted statistics at 20:05:39 are inherited resume state: 1,280 passages, 4,933 raw rules, 2,624 verified rules, 1,894 entailment YES and 730 entailment NO, with 15 passage parse failures. They must not be described as new pilot7 output. The fresh `extract.log` at 20:14:02 shows an active generation batch at 166/256 prompts; this is batch progress, not corpus completion. No extraction return code or completion marker is present.

K4 `stage.log` records successful installation and tests only. Persisted statistics at 19:58:07 record 3,506 passages, 1,312 raw items, 769 verified items, 37 passage parse failures, and 434 split passages. Rejections: quote absent 202, quote length 306, structure absent from passage 16, value absent 7, statement length 10, invalid kind 2. The fresh extraction log at 20:13:50 shows 581/1,030 prompts in an active batch. No postprocessing results or completion marker were listed. Counts alone establish neither semantic precision nor structure validity. No example sequences or patent passage content were downloaded for this audit.

The diagnostic tails show continued processing, with no terminal failure visible. They are not a full error-log audit. Both launcher scripts schedule a 180-minute shutdown; this audit did not verify the installed worker timer or remaining budget.

## Prior quarantine and evidence constraints

The prior independent audit is [knowledge_outputs.md](committee_raw/20261031_output_audit/knowledge_outputs.md). This takeover read its findings and the local code; it did not independently reopen the underlying papers or structures.

- Gold knowledge: exact quotes do not imply supported direction. In the audit, 10/13 sampled weight-eligible entries were correct at entry level. LIT-OB-001 has a goal statement without a measured direction; LIT-IMHB-004 has a correlation without a sign; LIT-SD-002 overgeneralizes one compound and mixes source provenance. Resolve these explicitly before use as priors. Reassess selective N-methylation and single-pair evidence before treating them as monotone rules. Do not manufacture a completed eligibility audit from quote matching alone.
- K2: prior independent sample yielded statement fidelity 30/39 and complete entry correctness 17/39. Raw verified rows include entailment-NO cases. Keep raw and strict outputs distinct and quarantined from sampler weights. Existing `strict_ok` requires entailment YES, confidence, topic/property relevance, and restricted SAR directions; this is a filter, not a semantic validation result. No scale-up justified by these counts. The preregistered judged 100-rule precision, coverage and quote-match gates still need measured evidence and the scale-up approval.
- K3: the audit identifies systematic linker-ring errors, CCD/D-residue discrepancies, and N-methylidene ambiguity. The current ring-table builder filters antibody receptors and excluded targets but still consumes the uncorrected thioether records. Quarantine contaminated ring priors or apply an explicit reviewed row filter before L2 use. Recompute statistics and hashes consistently for both sampler and prompt. Report independent PDB entries as well as chain/complex counts.
- K4 remains a separate patent tier with no promotion to scientific priors or public output. Before any recommendation to scale, require the preregistered precision >=0.80 with Wilson interval, structure parse success >=0.60 among examples with a structure string, and >=20 patents contributing verified example compounds. The extracting workstream's audit is not independent; the coordinator must redraw and judge independently. Patent coverage relative to BindingDB remains unestablished until postprocessing and audit complete.

## Incomplete `knowledge_augment/levels.py` change

The working-tree change introduces `audited_eligible` and `check_pins` but does not finish their integration. At inspection time neither `knowledge/eligibility_audit.json` nor `knowledge_augment/pins.json` existed.

1. L1/L2 currently fail closed on the missing audit by default. Preserve this behavior until a valid reviewed artifact exists; do not silently substitute the older weight-eligible list.
2. `KA_ALLOW_UNAUDITED=1` bypasses the missing audit, but `build_level` never adds the promised UNAUDITED label. The audit flag/hash returned by `audited_eligible` are discarded. Propagate status into labels, configuration and result manifests; forbid use as final evidence.
3. `check_pins` is defined but never called. Wire pin checking into the production configuration path and provide reviewed pins. The configuration hash currently omits the eligibility audit and pin inputs, so changed decisions can lack an explicit provenance trace even if effective selected IDs happen to match.
4. `l1_selection(kb_path=...)` bypasses audit enforcement; `literature_agreed_source(ids=...)` bypasses selection altogether. Keep any fixture/development path explicit and unqualified; enforce audit decisions on production entry points.
5. When an audit exists, its eligible decision replaces rather than intersects the stored `weight_eligible` gate. Define whether reviewed decisions can promote entries, validate audit IDs/decisions/duplicates, and test the intended policy explicitly.
6. `prompt_rule_ids` and prompt helpers still include all quote-verified rules/cards without audit quarantine. `prompts.py` explicitly permits internal-tier entries. Keep internal use separate from any future public path; semantic quarantine must affect prompt selection as well as token weights.
7. Existing feature exclusions already keep size, rotatable-bond and D-residue channels at zero; stored `weight` values are not read for token potentials. Preserve this invariant and test it rather than merely editing stored values.

The prompt module's introductory T1/T2 descriptions also lag the adopted provenance rule: tier follows whether the quoted statement is the source's own result, not simply peer-review/preprint status.

## Execution integrity corrections before another launch

Both launchers log extraction return codes but continue downstream and can emit `done.flag` after a failed extraction or postprocessing command. K4's test check only searches for the word `failed`, so some collection/import errors can escape that gate. Use actual exit codes, fail closed, persist a structured terminal status, and require all prerequisite stages to succeed before a success marker. Preserve logs and partial outputs separately for resumability. These corrections apply to future launches; no active worker was changed here.

Next steps: finish audit/pin/status enforcement with targeted tests; quarantine unsupported knowledge consistently in prompts and priors; collect the existing pilots' terminal status without launching replacements; evaluate the frozen raw/strict arms and independent patent sample; reconcile measured runtime and spot cost against the USD3 pilot caps before any further spend. Release stays paused and full-scale extraction remains approval-gated.

## Guard implementation after the audit

The parent assigned the eligibility guard fixes after the read-only audit above. Changes now in `knowledge_augment/levels.py`, `prompts.py`, and new `test_eligibility_guards.py`:

- Final L1/L2 construction requires reviewed audit and pins; the pins bind KB, audit, direction checks, source groups, ring library and exported potentials. Missing/stale evidence fails closed. No real eligibility audit or pins were invented.
- Custom KB/direction inputs obey the same hash validation; explicit rule IDs must be a unique subset of the eligible selection. Eligibility intersects existing weight eligibility, quote checks, source direction checks and exclusions. Duplicate audit IDs, unknown IDs/decisions and duplicate JSON keys fail.
- The explicit development escape for missing evidence carries UNAUDITED through configuration, hash, labels and prompt metadata/header. Existing mismatched evidence is not bypassed. Audit/pin changes alter configuration identity.
- Reviewed prompt selection admits only eligible or explicitly prompt-only IDs. Baseline L0 still works without audit or pins. Internal-content release policy and underlying structure corrections remain separate pending work.

Validation caveat: the synthetic-fixture suite ran locally before the allatom implementation-plan prohibition on laptop tests was relayed: 14 passed in 11.45 seconds. Local Python syntax compilation also completed. No further local tests were run after that instruction. These results are diagnostic only; the parent is coordinating the required isolated existing-Spot CPU rerun. Remote command from `allatom_paper/`: `python3 -m pytest -q knowledge_augment/test_eligibility_guards.py`. Tests use explicitly synthetic rules and do not validate real scientific eligibility. The older suite's assertion of 14 real selected rules has not been weakened and is not claimed to pass with missing audit evidence.

Remote validation completed on 29 October at 20:21 UTC: SSM command `36c18166-6c30-4312-9e52-8680b88fe54e` on existing Spot worker `i-0dace5be00919a762` returned Success/0. The isolated CPU-only fixture suite passed **14 tests in 0.22 s**. Evidence is retained under `s3://biomate-nextflow-work/cyclic_peptide/allatom/codex_takeover_20261029/paper1_review/guard_tests.txt`. This validates guard behavior, not biological truth or eligibility of any mined rule.
