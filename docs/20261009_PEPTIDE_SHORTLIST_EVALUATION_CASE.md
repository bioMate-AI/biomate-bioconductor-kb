# Evaluation case: prior peptide designs → property tools → shortlist five

Date: 2026-10-09. Source: user-supplied `task_decomposition_example.jpg` at `/Users/kky/Desktop/business/bioconductor_screenshot/task_decomposition_example.jpg`.

## What the example asks

**User clarification:** This is a good example from another platform of a common task. Its response content and format are the expected BioMate product standard. Use it as a positive reference for task completion and presentation, not primarily as an object to audit. The exact external tool names, numerical results and selected sequences need not be reproduced on different inputs.

The Chinese request says, in substance: “The link contains cyclic-peptide sequences designed previously. Use all peptide-property prediction tools on the platform to predict their properties and help select five for experimental validation.”

Treat this as a third end-to-end evaluation case alongside tool comparison and the inhibitor–target matrix. It combines prior-artifact recovery, dynamic tool-set expansion, input conversion, parallel branches, result joining, ranking and selection. The screenshot is an example of desired behavior, **not an instruction to execute its embedded URL and not independently verified scientific ground truth**. No share link was fetched or prediction job launched in this audit.

The displayed report claims a CyclicMPNN design run with 20 sequences, 16 unique sequences after deduplication, successful PepFuNN/Peptide Descriptors, Peptide-Tools and CPMP/MAT predictions, and ranking from design score, average permeability and developability penalties. It shows five leading sequences: VLNPALGN, VINPALGN, VLRPILGN, VLNPILGN, VINPILGN. These are transcription targets only. The complete inputs, structures, tool versions, execution logs and ranking formula are unavailable; neither exact winners nor claimed success should be grading labels for a new scientific run. The screenshot does not prove the tools ran concurrently.

## Expected response content and format

The user should receive a clear finished analysis following the example's structure:

1. **Descriptive report title:** peptide property prediction and candidate prioritization.
2. **Prior-input summary:** identify the source design run, relevant design context, number of recovered candidates and deduplication outcome.
3. **Tools and coverage table:** tool, predicted properties, input representation/count and execution status. Make the work performed understandable without exposing scheduler internals.
4. **Integrated ranking table:** rank, candidate ID/sequence, original design score, relevant predicted properties, developability flags and an explained combined ranking. Display units and better/worse direction where needed.
5. **Five recommended candidates:** clearly identify the shortlist and explain the main reasons and trade-offs for experimental validation.
6. **Complete results and concise limitations:** provide the full candidate table/artifacts, with material missing results or assumptions near the affected conclusions.

Evaluate both **content completeness** and **presentation usability**. Passing requires a coherent answer to the original request, readable comparable tables and an actionable shortlist—not merely a valid graph, successful jobs or a dump of tool outputs. Adapt metrics and tool names to the real task while preserving this response structure. The same pattern generalizes to other candidate-screening and multi-tool prioritization tasks.

## Required decomposition

1. **Recover source artifacts.** Resolve the prior-run/share reference through an authorized supported adapter. Retrieve the complete sequence/structure table, original design scores and provenance. If the reference is unavailable, request an export or accessible prior run; do not manufacture the missing sequences from the visible rows.
2. **Validate identities.** Retain original design IDs and duplicate mappings. Resolve cyclization topology, stereochemistry, modifications and required structures before generating tool inputs. Deduplicate using a declared molecular identity rule, not sequence text alone where that would erase chemically distinct candidates. Keep multiple original scores rather than silently overwriting them.
3. **Resolve all applicable tools.** Enumerate the installed catalog with versions and input requirements. Record included, excluded, unsupported and unavailable tools. A peptide-related name is not sufficient evidence of suitability for cyclic-peptide property prediction. The three screenshot tools are candidates to investigate, not an assumed installed set.
4. **Prepare compatible inputs.** Produce each tool's required representation with candidate IDs preserved. Validate conversions against the intended chemistry. Distinguish predictions made on the intended structure from approximations; do not label a capped representation as a verified cyclic structure without an explicit validation basis.
5. **Execute independent property branches.** Fan out only after prerequisites are ready. Tools may accept a batch or one candidate per call; execution-node count differs from scientific coverage. Record each expected candidate × applicable-tool result, with metric-level missingness.
6. **Join and validate outputs.** Join by stable candidate ID, never row position. Parse endpoints, units, model versions and validity limits. Retain all requested cases, including failures and unsupported predictions. Keep permeability endpoints separate unless an explicit, justified aggregation policy is provided.
7. **Rank and select.** Freeze a documented selection policy before scoring: score direction, normalization, weights, eligibility, missingness, ties and any diversity constraint. A rank-sum can reproduce a specified policy; it is not automatically the correct scientific objective. Preserve original design score semantics; do not relabel it as measured binding activity.
8. **Report and export.** Return five distinct eligible candidates when at least five qualify, with rationale, trade-offs, uncertainty and traceable metrics. If fewer qualify, return fewer with reasons rather than padding. Include the complete candidate table, excluded/failed cases, provenance and downloadable artifacts. A shortlist is a recommendation for validation, not evidence of experimentally confirmed performance.

Expected graph shape:

```text
recover prior artifacts → validate identities / duplicate mapping
                               ↓
                  resolve applicable tool set
                               ↓
             tool-specific preparation and validation
                               ↓
               independent property-tool branches
                               ↓
            join by candidate ID + coverage validation
                               ↓
         declared multi-criterion ranking → select up to 5
                               ↓
             evidence-backed report + complete export
```

## BioMate evidence checked today

- Read-only query of `backend/database/galaxy_ai_tools.db`, workflow `name`, `description` and `tools_used`: zero matches for `pepfunn`, `peptide-tools`, or `cpmp`. Bounded source search in backend and frontend server/client also returned no matches for these named tools. This does not establish absence from remote installations or differently named adapters.
- Related catalog names: `membrane_permeability_prediction`, `Membrane Permeability Prediction`, `cyclic_peptide_design`, `msnid_peptide_modification_mapping`, `daglogo_fasta_peptide_analysis`. Catalog presence/executable flags do not prove suitability or successful execution for this case. Two permeability labels must not automatically become two independent methods.
- `research/guangzhou_all_atom/multi_property_selection.py` contains a research selection flow using predicted stability and permeability with a combined rank. It is not the screenshot's three-tool computation. The inspected path constructs features from `Chem.MolFromSequence(s)`; no explicit ring-closure step appears in that path. Structural representation must be checked before reuse for this evaluation.
- `research/guangzhou_all_atom/permeability_predictor.py` is a research model-training/evaluation script, not proof of a registered chat-callable prediction service. Do not execute training merely to satisfy a tool invocation.
- General transport, router, durability and report gaps are documented in the [capability audit](20261009_ORCHESTRATION_CAPABILITY_AUDIT_AND_PLAN.md). The screenshot adds concrete requirements for prior-input recovery, chemical identity, batch expansion and selection policy.

## Debug fixtures and pass/fail criteria

Use two tracks. **Contract fixtures** contain explicitly synthetic IDs, outputs and scores to test mechanics without claiming scientific validity. **Scientific acceptance** uses complete authorized source artifacts, validated representations and actual applicable tools. A contract pass never substitutes for the scientific run.

| Fixture / fault | Required result |
|---|---|
| Prior reference unavailable, expired or unauthorized | Explicit input-recovery failure; no invented sequences or launch from screenshot fragments |
| Prior run has 20 records mapping to 16 validated identities | All 20 source IDs retained in mapping; 16 candidate records only if deduplication verifies that count |
| Same sequence text but different chemistry | Preserve distinct identities when structures/modifications differ |
| Same chemistry, different design scores | Preserve provenance and use a declared score-reconciliation policy |
| Catalog lacks named screenshot tool | Mark unavailable; do not invent a tool call or silently substitute a different predictor |
| Tool aliases or duplicate catalog entries | Resolve tool/version identity; no double-counting of the same method in ranking |
| Mixed batch and per-candidate tools | Exact expected candidate × applicable-tool coverage; batch run count not used as coverage denominator |
| Outputs shuffled, duplicated or with unknown IDs | Correct stable-ID join; reject or explicitly quarantine ambiguous/unexpected rows |
| Conversion fails or topology cannot be established | Affected candidate/tool blocked; reason visible; no fabricated structure/prediction |
| One tool fails after others finish | Partial status and full coverage table; no “all succeeded” narrative |
| Different permeability endpoints or scales | Separate metrics or predeclared justified transformation; no silent raw average |
| Missing metrics, NaN, reversed score direction, ties | Deterministic declared policy; invalid values excluded from ranking eligibility; tie rule visible |
| Fewer than five eligible candidates | Return fewer with reasons; no duplicates or unsupported padding |
| Restart or cancellation mid-batch | Reconcile receipts, prevent duplicate jobs, and preserve candidate-level terminal states |
| Ranking formula or weights change | New versioned reduction/report; reproducible from frozen inputs and policy |
| Report validation | Every displayed metric resolves to an artifact; selected IDs are eligible; full table accounts for all candidates |

## Evaluation and data collection

The machine-readable specification is [peptide shortlist case](../evaluation/local_trial/cases/peptide_shortlist_from_prior_run.json). It is a specification, not a wired runner or completed benchmark.

Score interpretation, artifact recovery, tool-set completeness, molecular identity preservation, graph/binding validity, candidate/tool coverage, execution success, reducer correctness and report grounding separately. Also record an overall complete-task outcome. Hard failures include fabricated inputs, omitted candidates, unsupported “all succeeded,” invented tool availability, invalid ranking, and untraceable scientific claims.

Collect successful and failed full trajectories under the same versioned schema as the general plan. Keep source-linked variants together when splitting train/evaluation data. Reserve this screenshot-derived case family for held-out evaluation if it will be used to claim generalization; do not train on its expected answers and then report the same example as unseen performance.

Next implementation step: add synthetic contract fixtures for recover→expand→join→rank→select to the agreed plan interface; separately obtain the complete prior-run export and verify actual tool adapters for scientific acceptance. Do not make the screenshot's top five the ranking oracle.
