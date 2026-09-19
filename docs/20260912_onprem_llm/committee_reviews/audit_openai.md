## Executive assessment

Do **not** spend GPU yet. The samples show evidence of a more severe problem than the known fractional-integer bug: some SFT inputs appear physically truncated or malformed, and at least one visible routing label is likely wrong.

Examples:

- The first routing sample ends after `Alphagenome Track Predic` and contains **no `Request:` span at all**. The answer `nf-core/atacseq` is therefore unsupported.
- The second ends at `mass‑spectromet`, and `nf-core/proteomicslfq` is visibly a more plausible choice than `glmsparsenet` from the available request text.
- The third ends in the middle of the candidate list, before the request, and the gold `spillr` is not visible among the candidates.
- The RAG example ends at `3D geno`; among the candidates, `hic`, `hicar`, `cutandrun`, and `atacseq` are all potentially plausible. `atacseq` is not securely grounded by the shown text.

If this truncation is only in the audit display, verify that explicitly from raw JSONL hashes and lengths. If it exists in the training artifacts, it is a P0 dataset-corruption defect.

---

# 1. Data quality defects

## P0: malformed and truncated SFT records

Your current paraphrase code does not protect against pre-existing or post-generation truncation.

`split_request()` accepts any request of 8–1200 **characters**, including:

- `I have label-free mass‑spectromet`
- incomplete sentences,
- clipped structured blocks,
- partial candidate names,
- requests missing the key modality or objective,
- content ending because of a source-field character cap.

It also contradicts its own docstring:

```python
# a trailing structured block after the request is rare; treat rest as request
```

The docstring says suffixes remain verbatim, but the implementation always returns `suffix=""`. Any structured block after `Request:` is paraphrased, not preserved.

Required validation before training:

- Every routing record must contain exactly one parseable request and a complete candidate block.
- Gold must exactly match one and only one candidate after normalization.
- Candidate names must not be truncated.
- Reject suspicious terminal fragments: dangling hyphens, unclosed brackets/quotes, incomplete UTF-8, abrupt alphanumeric endings, or input at a known character cap.
- Validate task-specific required sections with a parser, not `rfind()`.
- Store and compare source length, serialized length, and final rendered length.
- Manually inspect all records at common maximum lengths; spikes at 512/1,000/2,048 characters are strong truncation evidence.

Do not silently “repair” these by generating missing text. Return to the source artifact.

## P0: “grounded in a real artifact” does not imply a correct label

The visible routing examples suggest labels may have been assigned by weak lexical association or source metadata rather than by the actual request.

Specific risks:

- A real workflow can still be the wrong workflow for a real study.
- Paper titles and abstracts often describe biological findings, not the computational analysis requested.
- A study can use several workflows. Treating one as the unique gold creates false negatives.
- Candidate sets can contain multiple defensible tools, especially ATAC-seq/CUT&RUN/Hi-C examples.
- Downstream tasks can be confused with upstream processing, as potentially shown by `glmsparsenet` versus `nf-core/proteomicslfq`.

Actions:

1. Require a short, hidden adjudication record for every routing gold:
   - input modality,
   - intended operation,
   - expected output,
   - why the gold fits,
   - why the strongest negative does not.
2. Mark examples as `single_gold`, `multi_valid`, `ambiguous`, or `insufficient_information`.
3. Exclude ambiguous examples from exact-match routing training, or train accepted-positive sets rather than one arbitrary label.
4. Double-review high-confusability families such as:
   - ATAC-seq / CUT&RUN / ChIP-seq,
   - Hi-C / HiChIP / HiCAR,
   - bulk / single-cell RNA-seq,
   - proteomics preprocessing / statistical classification.

## P0: the parameter bug is broader than fractional integers

Yes, the schema-validation gap is worse than the 170 known examples.

Validating only `integer` versus `number` will miss:

- enum values not in the schema;
- boolean strings such as `"yes"` instead of `true`;
- percentages represented inconsistently as `1`, `0.01`, or `"1%"`;
- integer counts below minimum, including zero;
- values above maximum;
- violation of `multipleOf`;
- numeric strings where the runtime expects a number;
- scientific notation unsupported by a wrapper;
- list versus scalar errors;
- wrong list item types;
- null supplied to required non-null fields;
- invalid file/datatype assignments;
- incompatible genome builds or reference assets;
- conditional parameters supplied under an inactive branch;
- missing parameters required only when another option is selected;
- parameters valid for a different tool version;
- mutually exclusive options selected together;
- output parameters hallucinated as inputs;
- units omitted or converted incorrectly;
- path, URI, regex, and identifier-format violations.

`cond_param` is especially dangerous: JSON Schema validation alone may not capture Galaxy-style nested conditionals, repeats, sections, and dynamic options.

Implement one canonical validator against the **exact versioned runtime schema**. It should validate both the gold output and any structured parameter block in the user message. Quarantine rather than coerce invalid golds. Coercion can hide a semantically wrong interpretation—for example, `nPerm=0.01` might need to become `1`, `100`, or be rejected depending on the original wording.

Also execute or dry-run a stratified subset against the real workflow/tool engine. Static schema validity is necessary but not sufficient.

## P1: paraphrase expansion greatly overweights a small number of golds

Expanding 3,969 parents to 17,265 examples does not provide 17,265 independent examples. It creates approximately four correlated views per parent while repeating:

- the same gold,
- the same candidates,
- the same schema,
- the same errors,
- the same label noise,
- much of the same fixed prompt.

Consequences:

- mislabeled parents are amplified;
- candidate-order shortcuts are amplified;
- fixed instruction text dominates token counts;
- evaluation can be badly inflated if siblings cross splits;
- persona artifacts can become stronger than biological variation.

Split by parent before augmentation. Weight paraphrase siblings so that each parent contributes roughly the same total loss as one original, or sample one view per parent per epoch.

## P1: routing shortcuts and distribution artifacts

Audit correlations between gold and:

- candidate position;
- candidate-list length;
- capitalization or namespace;
- presence of `nf-core`;
- workflow popularity;
- source dataset;
- persona;
- query length;
- exact workflow-name mentions;
- whether the gold description contributed words to the generated request.

Randomize candidate order during training. Evaluate separately with shuffled candidate order. Ensure negatives are plausible and do not have obvious formatting differences from positives.

“Never paraphrase the target’s own description” is not enough. Generated requests can still leak distinctive phrases, workflow names, repository names, paper titles, accession IDs, or unique output terms copied from target metadata. Run phrase-overlap and retrieval-attribution audits against every target artifact used during generation.

## P1: missing abstention and clarification behavior

Some displayed examples do not contain enough information to select one workflow. Forcing exact workflow selection teaches confident guessing and conflicts with the `clarify` task.

Create examples where:

- no candidate is suitable;
- multiple candidates are equally valid;
- required modality or objective is absent;
- the request is truncated or contradictory.

The expected behavior should be a clarification or no-match result where the product permits it. If routing must always emit a candidate, report that limitation honestly and do not call the labels uniquely correct.

## P1: corpus quality remains weak after JSON parsing

The tools samples still contain low-information schema dumps:

```text
Reference sequence:
Sequence query file:
Generate a multifasta...
```

Empty labels and UI text are not useful prose. The second sample retains:

```text
## Examples
[]
```

This demonstrates that empty containers and templated headings still leak.

Other likely defects:

- duplicated `full_text` plus extracted component fields;
- nested JSON rendered into awkward Python/JSON-like syntax by `_render`;
- JSON encoded inside a JSON string and therefore parsed only once;
- HTML entities, Markdown fragments, navigation text, and scripts;
- boilerplate such as “Repository Actions” repeated across thousands of tools;
- generated `scientific_context` claims that are fluent but unsupported;
- stale or contradictory documentation across tool versions;
- descriptions with missing parameter names or descriptions detached from names;
- repeated ontology labels, synonyms, definitions, and ancestry paths;
- obsolete ontology terms not marked obsolete;
- forum misinformation, prompt-injection text, PII, credentials, and unsupported answers;
- vendored, generated, minified, or duplicate code;
- code/comments containing secrets, internal hosts, or licenses incompatible with model use.

A length threshold is not a quality gate. Eighty characters of malformed JSON or boilerplate still pass.

---

# 2. Preprocessing and verbalization

## The fix is directionally correct but incomplete

Parsing each field according to its schema is better than concatenating raw JSON. However, generic dictionary traversal is not reliable semantic verbalization.

This code:

```python
for k,v in d.items():
    rv=_render(v)
    lines.append(f"{_humanize(k)}: {rv}.")
```

can:

- lose relationships between nested objects;
- flatten conditional structure;
- reorder information in semantically misleading ways;
- mix provenance with scientific claims;
- render empty or placeholder values;
- duplicate values repeated at different levels;
- produce grammatically fluent but structurally wrong text.

Use schema-specific renderers with explicit field allowlists and templates. Preserve machine-readable JSON separately for tasks that need exact schemas; prose should not replace the authoritative structure.

## The malformed-JSON fallback can reintroduce the original leak

```python
except Exception:
    p=clean_prose(raw)
    return p if len(p)>=80 else None
```

A truncated JSON object, double-encoded JSON, JSON5, or a Python dictionary string can fail parsing, pass through `clean_prose`, and enter the corpus as “legacy prose.” This recreates the defect under a different path.

Use three-way classification:

1. valid structured JSON → schema-specific verbalization;
2. clearly natural prose → cleaned prose;
3. JSON-like but invalid → quarantine and log.

Detect JSON-likeness using delimiters, key/value density, escaped quotes, and parse attempts after one controlled de-encoding. Do not repeatedly decode arbitrary strings.

Also detect nested `error` fields, not only `d.get("error")`.

## Dedup must be rerun after final rendering

If MinHash was computed before JSON repair, HTML stripping, or verbalization, it no longer represents the final documents. Previously distinct raw JSON records may become identical prose, while identical source content can render differently.

Deduplicate the final normalized text, while retaining provenance and version information.

Recommended layers:

- exact hash on normalized final text;
- paragraph/chunk-level exact dedup;
- MinHash or SimHash over final text;
- template-aware boilerplate removal;
- cross-source dedup among tools, forums, KG, and SFT source artifacts;
- contamination dedup against all evaluation queries and their paraphrase parents.

Do not blindly collapse tool versions. Near-identical versions can have materially different defaults, parameter ranges, and outputs. Cluster them, then either preserve version-specific deltas or select one version intentionally.

## Dedup can also delete legitimate distinctions

Aggressive MinHash may merge:

- related ontology concepts;
- adjacent tool versions;
- workflows differing in one critical parameter;
- similarly structured but biologically distinct protocols.

Report dedup thresholds and manually inspect both false merges and missed duplicates. Keep mappings from retained documents to all removed source IDs.

## Preserve source boundaries and provenance

Every training unit should retain:

- source type and source ID;
- tool/workflow version;
- ontology release;
- extraction timestamp;
- original field path;
- whether text is original, template-verbalized, or model-generated;
- license;
- quality flags;
- transformation version.

Without this, you cannot remove a bad source or regenerate only affected documents.

---

# 3. Retriever methodology and leakage

## Random query holdout is not a convincing generalization test

It is not necessarily literal duplicate leakage, but it is highly likely to be **group leakage**.

If the same workflow occurs in both train and test, the model can learn a workflow-specific lexical prototype. If queries are generated or paraphrased from the same parent, paper, description, or template, random splitting can put near-siblings on both sides.

The reported improvement therefore supports only:

> retrieval of new randomly selected queries drawn from the same workflow/template distribution.

It does not establish generalization to new studies, new workflow versions, or unseen workflow families.

## Required split design

At minimum, report several evaluations:

1. **Parent/source-group holdout**  
   Group all paraphrases and queries from the same original request, study, paper, or artifact.

2. **Seen-workflow, novel-source holdout**  
   The workflow may occur in training, but the held-out query comes from an independent study/source.

3. **Workflow holdout**  
   No query for the held-out workflow appears in training.

4. **Workflow-family holdout**  
   Hold out related tools together to prevent namespace or family transfer from making workflow holdout trivial.

5. **Temporal holdout**  
   Train on artifacts available before a cutoff and test on later queries/workflow versions. This is closest to deployment drift.

Workflow- or family-holdout may be harder than the deployed task if the catalog is fixed, so it should supplement rather than replace a realistic seen-catalog evaluation.

## Hard-negative mining can leak evaluation information

Document exactly when negatives were mined.

Potential leakage occurs if:

- held-out queries were used to mine negatives;
- the final model or evaluation outcomes influenced negative selection;
- negatives were mined after looking at test failures;
- multiple query siblings were split before mining;
- hyperparameters or checkpoints were repeatedly selected on the reported holdout.

Mine negatives using training queries only. Freeze a validation set for checkpoint selection and a separate untouched test set for final reporting.

## Candidate catalog leakage versus legitimate transduction

Encoding the full workflow catalog at evaluation is expected for retrieval. Training on held-out workflow documents is a different question:

- If deployment has a fixed catalog and only queries are new, document-side exposure is legitimate.
- If claiming zero-shot retrieval for new workflows, held-out workflow descriptions must not influence fine-tuning or tuning.

State which claim the metric supports.

## SFT/retriever contamination

The retriever holdout is contaminated if its queries or close paraphrases appear in:

- routing SFT;
- paraphrase augmentation;
- prompt-generation inputs;
- model selection sets;
- mid-training forums or study text;
- hard-negative-mining queries.

Fine-tuning the LLM on those examples does not directly update BGE, but it still invalidates end-to-end evaluation and can leak through synthetic-query generation or manual tuning.

Build a global lineage registry across mid-training, SFT, retriever train/validation/test, and all paraphrases. Split before augmentation and generation.

## Evaluation needs more than recall

Add:

- MRR and nDCG;
- recall by workflow frequency;
- recall by query source, length, modality, and family;
- performance on workflows unseen during retriever training;
- confidence/margin calibration;
- false-positive analysis among near-neighbor workflows;
- bootstrap confidence intervals;
- comparison against BM25, TF-IDF, untuned BGE, and hybrid retrieval on the same frozen split.

A jump from 0.233 to 0.767 can partly reflect memorization of repeatedly labeled workflows, especially without grouped evaluation.

---

# 4. Cheap detection of degenerate paraphrases

Use a cascade so expensive judging is needed only for borderline cases.

## Stage 1: deterministic structural checks

Reject if:

- required markers disappeared or multiplied;
- candidate/schema/gold blocks changed byte-for-byte;
- gold is no longer in the candidate list;
- any ID, number, unit, organism, assay, datatype, negation, or constraint was changed unexpectedly;
- output is truncated, empty, or outside a length-ratio range;
- the paraphrase adds a new assay, sample type, organism, objective, or workflow name;
- persona text dominates the actual request.

Parse structure before and after generation rather than relying on string slicing.

## Stage 2: intent-slot preservation

Extract inexpensive slots from original and paraphrase:

- modality/assay;
- organism;
- input datatype;
- desired operation;
- expected output;
- constraints;
- negation;
- key numeric values and units.

Require exact or ontology-compatible preservation. This catches a cold-room/cage-rotation story that no longer clearly asks for RNA-seq processing.

## Stage 3: embedding and length filters

Compute original/paraphrase embedding similarity and reject both tails:

- too low: likely intent drift;
- too high: negligible augmentation.

Also measure similarity between the paraphrase and the irrelevant persona context. Reject when the main semantic mass is closer to the distractor than to the original request.

Embedding similarity alone is insufficient because negation and entity swaps can remain highly similar.

## Stage 4: routing-consistency check

Run a frozen baseline retriever or classifier on both versions.

Reject or manually review when:

- the original retrieves the gold but the paraphrase does not;
- gold rank drops sharply;
- the predicted workflow family changes;
- retrieval confidence becomes very low.

Do not require the current model to be correct in all cases; use rank change as a drift signal.

## Stage 5: bidirectional entailment or small judge

Use an NLI model to require approximate bidirectional entailment. Send only borderline cases to a small LLM judge with a structured rubric:

- same task?
- same inputs?
- same desired output?
- any new constraints?
- any removed critical facts?
- is the actual request still explicit?

Audit a random sample of accepted and rejected cases to calibrate thresholds.

## Disable the problematic persona now

“Bury in irrelevant lab context” directly optimizes for low signal-to-noise and conflicts with reliable intent preservation. Remove it until the above gates exist. If robustness to distractors is needed, create a separate, capped stress-test slice rather than making it a large fraction of ordinary SFT.

---

# 5. Prioritized actions

## P0 — single highest-priority fix

**Block training and implement a deterministic, task-aware artifact validator that quarantines malformed or invalid SFT records before any further augmentation.**

It must catch:

- truncated or missing requests;
- incomplete candidate lists;
- gold absent from candidates;
- ambiguous or unsupported routing labels;
- invalid parameter types, ranges, enums, units, and conditionals;
- changed structured blocks;
- paraphrase-parent leakage across splits.

Then regenerate/relabel only from authoritative source artifacts.

This is higher priority than model training or retriever tuning because current defects corrupt the target itself. GPU training will amplify them, and the 4× paraphrase expansion amplifies each bad parent several times.

## P1

1. Split globally by parent/source/workflow family before paraphrasing or negative mining.
2. Replace the random retriever test with frozen grouped, temporal, and workflow/family evaluations.
3. Disable the distractor persona pending semantic-preservation gates.
4. Re-run corpus cleaning and dedup on final rendered text.
5. Add schema-specific verbalizers and quarantine malformed JSON-like fields.
6. Conduct independent adjudication of high-confusability routing labels.

## P2

1. Rebalance SFT by parent and task rather than raw augmented-row count.
2. Randomize candidate order and test order robustness.
3. Add abstention/clarification and multi-valid labels.
4. Add provenance, versioning, licenses, and transformation lineage.
5. Audit forums/code for PII, secrets, prompt injections, generated files, and unsupported claims.

The central issue is not insufficient diversity. It is that malformed inputs, ambiguous labels, and schema-invalid golds appear to be treated as authoritative and then multiplied.