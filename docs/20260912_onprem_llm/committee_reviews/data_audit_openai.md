# Joint committee verdict

**Do not train on `data_pool_v2` as a uniformly gold pool yet.** The main issue is not simply “weak teachers”; it is a **supervision-contract mismatch**:

- Catalog routing requires catalog identifiers, but teachers produced unconstrained concepts.
- Param extraction requires workflow-specific schema keys and typed values, but teachers produced semantic descriptions.
- Routing is being evaluated against a single DB slug even when the query is under-specified or several workflows are acceptable.
- “Deterministic from DB” establishes reproducibility, not semantic correctness.

The graph anchors are probably the strongest portion, but they still need structural and semantic validation. Self-mined data is promising if tied to immutable evidence. Current committee labels should be quarantined from hard-label training.

## Priority summary

| Priority | Finding | Decision |
|---|---|---|
| **P0** | Task targets and gold definitions are misaligned | Redefine routing/param/wfgen/autofix label contracts before training |
| **P0** | Committee teachers were not given the information required to emit valid outputs | Regenerate retrieval- and schema-grounded outputs |
| **P0** | Prefix-family splitting will permit substantial semantic and structural leakage | Rebuild splits using workflow lineage, graph similarity, source provenance, and text deduplication |
| **P1** | DB-derived anchors are treated as semantic gold without validation | Run structural, schema, and sampled expert audits |
| **P1** | Self-mined claims may be stale or unsupported | Require source snapshots, citations, executable verification, and temporal metadata |
| **P1** | Coverage is unclear despite high counts | Measure coverage across workflows, tools, schemas, organisms, modalities, and error classes |

---

# 1. Committee distillation

## Diagnosis: primarily a labeling-context bug, but not only that

The reported agreement numbers do **not** validly measure teacher quality.

A teacher returning `Gene Set Enrichment Analysis` cannot exactly match `clusterprofiler_gene_set_enrichment_analysis` without being shown:

1. The closed-world catalog candidates.
2. Their slugs and descriptions.
3. Input/output constraints.
4. Relevant parameter schemas.
5. The required output format.

The first routing example is likely a **representation-level disagreement**, not a semantic failure:

- Query: ranked gene list and gene-set enrichment.
- Teacher: GSEA.
- DB: clusterProfiler GSEA workflow.

However, it is unsafe to automatically treat these as equivalent. “GSEA,” clusterProfiler, fgsea, over-representation analysis, and Wilcoxon-based enrichment can differ in input assumptions, statistics, organism support, outputs, and reproducibility.

The other examples show genuine ambiguity or possible quality problems:

- `signaturesearch` versus “Connectivity Map” may be semantically related, but the exact workflow fit depends on the workflow card and input requirements.
- `omicade4` versus “PCA” may reflect a broad workflow whose functionality includes PCA, or it may be an overly generic teacher answer.
- Teacher consensus of 0.30–0.49 is too low to support unattended hard labeling even after accounting for output-format mismatch.

Thus:

> The low DB agreement is confounded and cannot establish poor teacher quality, but the low teacher-teacher consensus still signals ambiguous prompts, missing catalog context, inadequate output constraints, or unstable ontology.

## Correct use of teachers

Teachers should be used as **grounded rankers, structured annotators, and adjudicators**, not as open-world answer generators.

### Routing protocol

For each query, provide the teachers with:

- Top-\(k\) retrieved workflow candidates from the actual BioMate retrieval stage.
- Candidate slug, title, concise capability description, required inputs, outputs, organism/modality support, and important exclusions.
- The routing policy: select one, return an acceptable set, request clarification, or return `none_of_the_above`.
- A strict JSON schema.

Example target:

```json
{
  "acceptable": [
    {
      "workflow_slug": "clusterprofiler_gene_set_enrichment_analysis",
      "relevance": "preferred",
      "evidence": ["accepts ranked genes", "supports GO enrichment"]
    }
  ],
  "rejected": [
    {
      "workflow_slug": "some_ora_workflow",
      "reason": "requires an unranked selected-gene list"
    }
  ],
  "clarification_needed": false
}
```

Two measurements must then be separated:

1. **Candidate recall:** Did retrieval include at least one acceptable workflow?
2. **Teacher selection quality:** Given adequate candidates, did the teacher rank/classify them correctly?

Including only the DB slug in the candidate set would produce artificially favorable results. Candidate sets should contain realistic hard negatives.

### Parameter protocol

Route to a workflow first, then provide:

- Exact workflow/version.
- Parameter schema with keys, types, enums, aliases, defaults, and constraints.
- User query.
- Explicit rules for omitted versus defaulted versus inferred parameters.
- Strict typed JSON output.

For example, a teacher must not invent `analysis_method` if that key does not exist. The output should distinguish:

```json
{
  "extracted": {
    "organismDb": "Homo.sapiens"
  },
  "unsupported_user_constraints": {
    "method": "Wilcoxon"
  },
  "not_mentioned": ["ontology"]
}
```

Also verify that `"Homo.sapiens"` is truly the permitted runtime value; many bioinformatics tools instead require identifiers such as `org.Hs.eg.db`, taxonomy IDs, or workflow-specific enums.

### Autofix protocol

Teachers need the actual:

- Error message/log.
- Workflow graph and relevant node.
- Tool/schema version.
- Inputs and parameters.
- Allowed edit operations.
- If available, known successful patch or post-fix test.

They should produce separate fields for:

- Symptom.
- Root-cause category.
- Evidence.
- Proposed patch.
- Confidence/abstention.
- Validation test.

“Missing input data” is a symptom category, not a complete autofix. “Compilation error” versus “dependency” may be different levels of the same causal chain, but without evidence neither is reliable.

### Workflow-generation protocol

Teachers should emit a typed DAG over permitted tools/modules, not a prose plan. Validate:

- Node existence.
- Port compatibility.
- Required inputs.
- Parameter validity.
- Acyclicity.
- Output satisfaction.
- Modality and organism constraints.

Multiple graphs can be valid, so exact graph matching should not be the sole evaluation.

## Usability of current committee output

| Current output | As hard training labels? | Potential salvage |
|---|---:|---|
| Routing concept answers | **No** | Build an alias/intent lexicon or weak semantic tags after mapping and verification |
| Routing queries/paraphrases | Conditional | Retain only if the query is entailed by the workflow card and does not introduce unsupported capabilities |
| Param free-form answers | **No** | Possibly mine ontology terms/aliases; regenerate all schema-key labels |
| Autofix categories | Not as fixes | Normalize into a coarse symptom taxonomy only when supported by logs or incidents |
| Workflow generation | **No**, absent executable validation | Keep as candidate plans only; regenerate as constrained DAGs |
| Teacher consensus flag | **No** as correctness | Use for triage, not truth; correlated teachers can agree on the same abstraction error |

**Recommendation:** quarantine all current distillation labels. Do not discard the raw records; use them as candidates for remapping, alias extraction, and targeted adjudication.

---

# 2. Gold validity

## Routing: one DB slug is not generally the only correct answer

A single slug is valid gold only when the task is explicitly:

> “Recover the exact workflow associated with this known record or workflow-specific description.”

It is not sufficient for user-intent routing. Many queries are broad enough to admit several workflows.

However, do not create unconditional equivalence classes such as:

> `GSEA = clusterProfiler = fgsea`

These are related but not universally interchangeable. Acceptability depends on:

- Ranked versus selected gene list.
- Statistical method.
- Gene-set collection.
- Organism and identifier type.
- Single-sample versus cohort-level analysis.
- Desired plots/tables.
- Runtime/environment constraints.

## Recommended routing gold

Use a **query-conditional, tiered accept set**:

```text
preferred:
  workflows satisfying all explicit constraints and product policy

acceptable:
  workflows that correctly perform the requested task but differ in
  non-requested implementation details

clarification_required:
  workflows whose suitability depends on an unspecified constraint

incompatible:
  plausible hard negatives violating an explicit requirement
```

Maintain two label levels:

1. **Intent/capability label:** e.g. ranked-list gene-set enrichment.
2. **Executable catalog routing label:** acceptable workflow slugs under current catalog/version.

If product policy requires a single route, store that separately as the **preferred operational choice**, not as the sole semantically correct answer.

### Routing metrics

Use:

- Accept-set Recall@\(k\).
- nDCG or graded MRR for preferred versus acceptable items.
- Constraint-violation rate.
- `none_of_the_above` and clarification accuracy.
- Candidate-retrieval recall.
- Exact preferred-slug accuracy only as a secondary policy metric.

Recompute the reported 0.27/0.30 agreement after semantic normalization and accept-set adjudication. The current exact-ish metric is not interpretable.

## Parameter extraction: schema keys and concepts are different layers

The training target for executable parameter extraction must be:

- Workflow/version-specific schema key.
- Typed, schema-valid value.
- Provenance from an explicit user phrase.
- Inference status.
- Handling of omitted/default values.

A concept such as “organism,” “Wilcoxon,” or “Gene Ontology” is not sufficient unless it maps to a valid key for the selected workflow.

Recommended representation:

```json
{
  "workflow_slug": "…",
  "schema_version": "…",
  "parameters": {
    "organismDb": {
      "value": "Homo.sapiens",
      "source_span": "human genes",
      "status": "normalized"
    }
  },
  "unmapped_constraints": [
    {
      "concept": "Wilcoxon",
      "source_span": "Wilcoxon",
      "reason": "no corresponding parameter in this workflow schema"
    }
  ]
}
```

Important distinctions:

- **Explicit:** stated by the user.
- **Normalized:** “human” mapped to a schema enum.
- **Inferred:** inferred but not directly stated; usually require confirmation.
- **Defaulted:** executor supplies a default.
- **Unspecified:** omit rather than hallucinate.

Defaults should generally not be trained as if extracted from the query.

---

# 3. Self-mining quality

## Overall assessment

Self-mining appears more promising than the current committee labels because the examples are concrete and provenance-bearing. It is still not automatically trustworthy.

## Documentation QA

The sample question, “how many workflows implement `params.mock_mode`?”, is highly snapshot-dependent.

Required controls:

1. **Immutable source snapshot**
   - Repository/document commit hash.
   - Catalog/database snapshot.
   - Extraction date.
   - Applicable BioMate version.

2. **Answer citation**
   - File and line range for textual claims.
   - Executed query and result artifact for quantitative claims.

3. **Recomputation**
   - Counts such as “Only 1” and “23” should be generated from the referenced snapshot, not copied from prose.
   - Reject if prose and computed state disagree.

4. **Document authority classification**
   - Runtime/schema source of truth.
   - Current user documentation.
   - Design proposal.
   - Incident note.
   - Deprecated documentation.

5. **Temporal labeling**
   - Some incident documents describe past failures rather than current behavior.
   - Store `valid_from`, `valid_to`, or at least the source version.

6. **Question naturalness**
   - Avoid overproducing internal implementation trivia unless the deployed model is expected to answer it.
   - Balance internal jargon with realistic user phrasing.

7. **Leakage control**
   - All QA pairs from the same document, generated variants, and derived database query should remain in one split.

Use documentation QA preferentially for **retrieval-grounded QA**, not as timeless param or workflow truth.

## Commit-fix pairs

The example is plausible and actionable, but commit messages and issue summaries often underdescribe the real cause.

Required controls:

- Link problem, commit, and exact diff.
- Verify the diff actually implements the stated fix.
- Prefer commits with a test or reproducible before/after behavior.
- Exclude broad refactors, merges, formatting-only changes, and commits with several unrelated fixes.
- Identify whether the endpoint already existed in the parent revision.
- Preserve the affected component/version.
- Redact credentials, patient information, internal hostnames, and secrets.
- Distinguish:
  - observed symptom,
  - root cause,
  - code change,
  - validation result.

The 377 accepted fixes from 600 commits also need a selection-bias audit: what classes were excluded, and does the retained set overrepresent easy UI wiring bugs?

## Hallucination control

No mined pair should be accepted solely because an LLM generated a fluent question or summary. Require at least one of:

- Direct textual entailment with citation.
- Executed database query.
- Test or reproducible behavior.
- Diff-based verification.
- Human review for high-impact cases.

---

# 4. Graph anchors

## Deterministic does not mean clean

DB-derived anchors are likely useful, but they are “gold” only for the database’s recorded state. They can inherit stale metadata, incomplete module boundaries, UI defaults, malformed graphs, and historical workarounds.

## DAG validation requirements

For every workflow:

- All referenced nodes/tools exist in the catalog version.
- Edges refer to valid ports.
- Source and destination types are compatible.
- Required inputs are connected or externally exposed.
- Required outputs are produced.
- Graph is acyclic, unless iteration is explicitly supported.
- Parameter values validate against the node’s schema.
- Disabled/deprecated nodes are represented correctly.
- Subworkflow references resolve to a fixed version.
- Module input/output bindings are preserved during expansion.
- No orphan nodes or unreachable outputs.
- Topological order is computed from edges, not trusted from stored display order.

### Decomposition-specific concern

The example:

```text
["Add gene annotation",
 "Unsupervised exploration",
 "Filter genes by variance",
 "Detect differential expression"]
```

is a linear list, while the true workflow may contain branches or parallelizable steps. Training a decomposition model only on ordered labels can incorrectly teach a linear plan.

Store decomposition gold as:

- Nodes or modules.
- Dependency edges.
- Optional versus required steps.
- Inputs/outputs.
- Human-readable labels.
- Subworkflow boundaries.

For inter-workflow decomposition, ensure modules are genuine reusable units rather than artifacts of naming or UI grouping.

## Parameter gold validation

Enums and defaults require checks against the actual runtime schema:

- UI schema versus executor schema.
- Current tool version versus workflow-pinned version.
- Enum aliases and case sensitivity.
- Conditional parameters.
- Dynamic defaults based on inputs.
- Deprecated values.
- Null versus omitted semantics.

A default is not automatically an extraction label. Train the model to leave an absent value unspecified unless BioMate’s contract explicitly requires materializing defaults.

## Sampled semantic audit

Automated structural validation is necessary but insufficient. Run a stratified expert audit across:

- Workflow families.
- Modalities.
- Organisms.
- Tool versions.
- Simple versus nested DAGs.
- Workflows with subworkflows.
- Rare parameter schemas.
- Deprecated and recently edited workflows.

Also measure coverage: 902 param anchors across 4,198 workflows and 12,000 tools may leave large schema families unseen.

---

# 5. Leakage and split design

## Prefix-family hashing is insufficient

Workflow-name prefixes are weak proxies for lineage or semantics. Leakage can occur through:

- Renamed or copied workflows.
- Nearly identical DAGs under different prefixes.
- Shared subworkflows.
- Different wrappers around the same tool sequence.
- Template-generated queries.
- Paraphrases of the same query.
- Documentation and commit pairs describing an eval workflow.
- The same error/fix pattern appearing with minor wording changes.
- Shared labels and metadata copied between workflows.

This could produce deceptively high eval performance based on memorized graph fragments or query templates.

## Defensible grouping

Construct similarity/provenance groups using multiple signals:

1. **Workflow lineage**
   - Parent/template IDs.
   - Fork/copy provenance.
   - Repository history.
   - Version ancestry.

2. **Graph similarity**
   - Canonicalized node/tool multiset.
   - Edge structure.
   - Subworkflow membership.
   - Weighted graph fingerprints.
   - Downweight ubiquitous utility nodes.

3. **Text similarity**
   - Workflow descriptions.
   - Queries and paraphrases.
   - Documentation passages.
   - Commit/issue summaries.
   - Exact hashes plus near-duplicate detection using MinHash or embeddings.

4. **Schema similarity**
   - Same tool/version and near-identical parameter schema.

5. **Generation provenance**
   - Same teacher prompt/template.
   - Same source record.
   - Same document or commit.
   - Same paraphrase seed.

Assign near-duplicate clusters atomically to a split. Avoid naïvely connecting every workflow sharing a common tool, which could collapse most of the catalog into one component; use weighted similarity and thresholds.

## Recommended evaluation tracks

A single split cannot answer all product questions. Maintain at least:

### 1. Warm-catalog test

Known workflows may appear in training, but evaluation queries are independently authored and deduplicated. Measures production routing to a familiar catalog.

### 2. Cold-family test

No workflow or close graph/lineage family from the eval group appears in training. Measures generalization to new workflow families.

### 3. Cold-tool/module test

Selected tools or reusable modules are held out where feasible. Measures compositional workflow generation.

### 4. Temporal test

Train on snapshots before date \(T\); evaluate on later workflows, commits, schemas, and incidents. This is especially important for docs and commit-fix data.

### 5. Adversarial constraint test

Near-neighbor workflows differ in ranked versus unranked input, organism, method, modality, or output. Measures whether the router uses constraints rather than names.

Keep a small, human-adjudicated test set completely isolated from all teacher generation, prompt development, and threshold tuning.

---

# 6. Biggest risk and top three pre-training fixes

## Single biggest risk

> **The largest risk is training on semantically mismatched targets as if they were exact gold—especially concept-level teacher answers and single-slug routing labels.**

This would teach the model inconsistent behavior: sometimes emit concepts, sometimes slugs, sometimes free-form parameter descriptions, and sometimes schema keys. More data will not repair an inconsistent target contract.

## Top three fixes before training

### 1. Redefine and validate the task contracts

- Routing: query-conditional preferred/acceptable/incompatible sets.
- Param extraction: workflow-specific typed schema keys with explicit/default/inferred status.
- Autofix: symptom, cause, patch, and validation as separate fields.
- Workflow generation/decomposition: canonical typed DAGs, not prose or linear lists.
- Establish structural validators and scoring metrics before producing more labels.

### 2. Quarantine and regenerate committee distillation

- Supply actual retrieval candidates, schemas, graph context, and allowed actions.
- Require strict JSON and permit abstention/clarification.
- Measure candidate recall separately from selection quality.
- Use teachers as rankers/adjudicators, not open-world label generators.
- Manually audit a stratified sample, especially disagreements and high-confidence consensus cases.
- Salvage existing outputs only as weak aliases, intent tags, or candidate paraphrases after entailment checks.

### 3. Rebuild validation and splitting around provenance and similarity

- Validate all graph anchors structurally and sample them semantically.
- Verify docs against immutable snapshots and commits against diffs/tests.
- Cluster exact and near duplicates across workflows, DAGs, schemas, queries, documents, and generation templates.
- Produce warm, cold-family, and temporal test tracks rather than relying on prefix hashes.

## Minimum release gates

Before training, the committee recommends requiring:

- **100% schema-valid** param and graph targets.
- **Near-100% structural validity** for DAG anchors, with all failures quarantined.
- A human-audited estimate of semantic precision for each source/task, reported separately.
- High retrieval candidate recall against adjudicated routing accept sets.
- Zero known exact/near-duplicate leakage into the protected evaluation set.
- Source/version/provenance fields for every self-mined example.
- Per-task and per-source training weights; do not flatten all records into a single confidence tier.

The pool is recoverable and potentially strong, but only after the label ontology, grounding context, and evaluation split are corrected.