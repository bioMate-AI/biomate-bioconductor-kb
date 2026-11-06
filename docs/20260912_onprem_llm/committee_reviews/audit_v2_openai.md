## Overall verdict

The task family is directionally appropriate, but the supplied full records expose **hard label-contract violations**, especially in conditional parameter extraction and cross-workflow decomposition. “Grounded in a real run” is not sufficient if the generated request no longer entails the label. I would **not start GPU training until these records are automatically validated and the affected subsets are regenerated or quarantined**.

## P0 — Definite label and schema errors

### 1. `cond_param` gold is objectively incomplete

The schema marks all seven parameters required:

- `gem`
- `seed.size`
- `iterations`
- `cuts`
- `splits`
- `sort.length`
- `samp.sig`

None is clearly supplied by the request. The gold only asks for `splits`:

```json
{"clarify_needed":["splits"]}
```

Under the stated contract, the gold must identify every missing required field:

```json
{
  "clarify_needed": [
    "gem",
    "seed.size",
    "iterations",
    "cuts",
    "splits",
    "sort.length",
    "samp.sig"
  ]
}
```

If some fields are conditionally required or supplied by workflow defaults, the displayed schema is wrong and must encode those conditions/defaults explicitly. As written, this is mislabeled training data.

### 2. The `clarify` gold has the same, more severe defect

The request supplies FASTQs and a high-level ChIP-seq objective, while the schema requires processed regions, BAMs, plotting/grouping fields, and other execution parameters. The gold asks only for:

```json
{"clarify_needed":["extend_reads"]}
```

At minimum, the following required fields are not unambiguously provided:

```json
{
  "clarify_needed": [
    "regions",
    "bam_files",
    "design",
    "normalization",
    "bin_count",
    "sample_count",
    "resampling_strategy",
    "split_by",
    "facet_by",
    "group_by",
    "extend_reads",
    "invert_strand",
    "strand_specific"
  ]
}
```

`sample_count` is not safely inferable because “three biological replicates and matching input controls” could imply six experimental libraries plus six controls, depending on the workflow’s counting semantics. A design description is also not necessarily a schema-valid `design` string or file.

More importantly, this request is probably being configured against the **wrong workflow stage**: it asks for FASTQ-to-results processing, while the schema expects BAMs and regions. An input-type compatibility task should reject or reroute this before parameter extraction.

### 3. The `interwf_decomp` example is semantically corrupted

The second request branch is explicitly raw single-cell RNA-seq. The gold says:

```json
{"sub_task":"metabolomics analysis","workflow":"phenomis"}
```

That is not supported by the request. `phenomis` is not a credible best match for raw UMI QC, doublet removal, normalization, and single-cell differential expression.

The first branch is also under-decomposed. Batch correction alone does not satisfy clustering, subtype discovery, marker identification, and visualization unless the selected workflow demonstrably implements all of those operations.

A realistic structure would be approximately:

1. Correct bulk RNA-seq batch effects.
2. Perform bulk subtype discovery and marker characterization, dependent on 1.
3. Process raw scRNA-seq data—QC, doublet detection, normalization and scaling—independent of 1.
4. Run covariate-adjusted scRNA-seq differential expression, dependent on 3.

The two main branches can run in parallel, but the steps within each branch cannot.

This record looks like semantic drift from a different source request, not mere ambiguity.

---

## P1 — Decomposition labels are not teaching valid dependencies

### 4. The epiNEM DAG has incorrect or misleading edges

The gold is:

```json
[
  {"sub_task":"Prepare binary effect matrix","order":1,"depends_on":[]},
  {"sub_task":"Run epiNEM network inference","order":2,"depends_on":[]},
  {"sub_task":"Plot the inferred network structure and save outputs","order":3,"depends_on":[1]}
]
```

The actual data dependencies are:

- Network inference consumes the prepared matrix: step 2 depends on step 1.
- Network plotting consumes the inferred network: step 3 depends on step 2.

A clearer gold is:

```json
[
  {
    "sub_task": "Prepare binary effect matrix",
    "phase": "Input & Preparation",
    "order": 1,
    "depends_on": []
  },
  {
    "sub_task": "Run epiNEM network inference",
    "phase": "Core Analysis",
    "order": 2,
    "depends_on": [1]
  },
  {
    "sub_task": "Plot the inferred network structure and save outputs",
    "phase": "Visualization & Output",
    "order": 3,
    "depends_on": [2]
  }
]
```

The phase-barrier rule partially masks the error, but it does not make `[1]` the correct prerequisite for plotting. Training should not rely on implicit phase ordering while also emitting contradictory explicit dependencies.

### 5. Cross-workflow DAGs need I/O-contract supervision

A workflow chain should be valid not only semantically but operationally:

- Upstream output type matches downstream input type.
- Genome build and annotation versions agree.
- Identifier namespaces agree or an explicit conversion step exists.
- Matrix orientation and assay layer are compatible.
- Required metadata columns survive the transition.
- No downstream step starts before its actual artifacts exist.

The current cross-workflow task appears to train workflow names and ordering without proving these contracts.

---

## P1 — Routing quality is plausible in places, but semantic uniqueness is not guaranteed

### 6. Correct or plausible routing records

- Small RNA-seq → `nf-core/smrnaseq`: reasonable and likely best among the options.
- Genotype–environment association with latent-factor correction → `lea_gea_least_squares_lfmm2`: strong match.
- Regulator-constrained network inference → `genie3_targeted_network_inference`: strong candidate match.

### 7. CUT&Tag example is ambiguous rather than clearly wrong

`nf-core/cutandrun` may support CUT&Tag and is a plausible comprehensive choice. However, the retrieved list also contains:

```text
Cutandtag Alignment Spikein
```

Because the request provides mostly an assay title and biological abstract rather than desired processing details, the gold is not textually unique. The exact CUT&Tag candidate may be preferable if spike-in alignment is known to be required; `nf-core/cutandrun` may be preferable for a full end-to-end analysis if no spike-in requirement is present.

Real-run provenance can establish what was historically run, but it does not establish that the request uniquely identifies it. Ambiguous candidate sets should be:

- regenerated with discriminative task details,
- allowed to have multiple acceptable labels, or
- excluded from exact-match training.

### 8. Forced single-workflow selection lacks abstention

The retriever guaranteeing that the gold is present tests only candidate reranking. Production also needs cases where:

- the correct workflow is absent,
- no candidate supports the input type,
- multiple candidates are equally suitable,
- the requested operation requires a chain rather than one workflow,
- the request is outside BioMate’s supported capabilities.

Add `none_of_the_above`, `clarify_needed`, or retriever-failure tasks. Otherwise, the model will confidently select an invalid candidate.

---

## P1 — Parameter extraction policy is good, but its implementation is incomplete

### 9. “Extract only explicitly specified values” is the correct policy

For configuration, restraint is preferable to silently inventing values. Defaults should be resolved in a separate stage that records:

- workflow and schema version,
- default source,
- whether the value was user-specified, derived, or defaulted,
- units and allowed range,
- cross-parameter constraints.

The second `param` example is good:

```json
{
  "filter.freq": 0.1,
  "genes.cluster": true,
  "samples.cluster": true
}
```

The conversion from 10% to `0.1` is deterministic and schema-appropriate.

### 10. The first `param` record is ambiguous and malformed

The text ends with:

```text
Candidate parameter: exclude=sgc.
```

That does not clearly present two parameter names. It resembles a generation or serialization artifact. In addition, “exclude the sex chromosome” is ambiguous between X alone and both X/Y, although the later X-specific statement supports `sgc: "X"`.

The intended gold may be:

```json
{"exclude":"X","sgc":"X"}
```

but the request should explicitly say “exclude chromosome X” and the candidate-parameter list should be serialized as something like:

```text
Candidate parameters: ["exclude", "sgc"]
```

### 11. Schema validity cannot be audited when the schema is hidden

The plain `param` examples provide names but not types, enums, multiplicity, or workflow version. To train reliable execution configuration, include a compact versioned schema containing:

- type,
- enum or pattern,
- required/optional/conditional status,
- cardinality,
- units,
- default,
- dependencies and exclusions,
- input-file role.

A value can be semantically sensible yet invalid for the actual CLI/schema.

---

## P2 — “Do not name the workflow” should be a split, not a universal principle

Omitting the target name is useful for preventing trivial lexical leakage and testing genuine task-to-workflow mapping. It should not define the entire routing distribution.

Real users commonly:

- explicitly request a workflow,
- use an alias or outdated name,
- specify a workflow version,
- ask to migrate from one workflow to another,
- name an unsuitable workflow,
- say not to use a particular workflow.

Training should contain a controlled mixture:

1. No workflow name: infer from task.
2. Correct explicit workflow name: honor and validate it.
3. Alias or typo: canonicalize.
4. Explicit but incompatible workflow: warn and suggest alternatives.
5. Conflicting tool name and requested outputs: clarify.
6. Version-constrained request: resolve compatibility.

Otherwise, the model may learn to ignore valuable explicit user constraints.

---

## P2 — Task design does not yet cover the full route → configure → run → diagnose lifecycle

The current tasks strongly cover routing and literal parameter extraction, but the following workflow-critical capabilities are missing or not demonstrated:

### Before routing/run

- Input artifact and MIME/type validation.
- FASTQ/BAM/VCF/matrix-object distinction.
- Paired-end vs single-end checks.
- Sample-sheet and metadata-column validation.
- Organism, genome build, annotation, and identifier compatibility.
- Workflow applicability and unsupported-request detection.

### During configuration

- Versioned schema validation.
- Conditional parameter logic.
- Cross-parameter constraints.
- Default resolution with provenance.
- Reference/container/database compatibility.
- Resource and cost estimation.
- Scheduler profile selection and quota checks.

### Workflow chaining

- Output-to-input compatibility.
- Required conversion/adaptor steps.
- Branching, scatter/gather, checkpoint and retry semantics.
- Preservation of sample identity and metadata.
- Correct dependency graph generation.

### Execution and diagnosis

- Render a reproducible run manifest or command.
- Preflight validation.
- Parse Nextflow/Galaxy/Bioconductor failures.
- Distinguish data errors, parameter errors, resource exhaustion, transient infrastructure errors, and tool bugs.
- Recommend safe retries without changing scientific meaning.

### Post-run

- QC acceptance criteria.
- Output interpretation.
- Missing/empty artifact detection.
- Comparison against expected output contracts.
- Provenance and reproducibility reporting.

No diagnostic task is demonstrated in the supplied workflow-relevant examples, despite diagnosis being central to the stated usage loop.

---

## Coverage and imbalance risks

The listed workflow-relevant tasks total 13,131 examples. Routing dominates:

- `rag_routing` + `routing`: 6,782 examples, about **44.5% of the entire 15,254-example SFT set**.
- `interwf_decomp`: only 354 examples, about **2.3%**.
- `wfgen`: 1,531 examples for 4,200 workflows.
- `param` + `cond_param`: 2,928 examples against 12,312 tools and potentially many more versioned schemas.

Aggregate counts do not establish coverage. With 4,200 workflows:

- 2,538 direct-routing records cannot cover every workflow even once.
- 4,244 RAG records could average roughly one per workflow, but only if nearly uniform.
- 1,531 workflow-generation records cannot provide broad per-workflow coverage.
- Parameter examples are necessarily sparse relative to 12,312 tools.

Likely risks include:

- Long-tail workflows with zero or one example.
- Overrepresentation of popular nf-core workflows.
- Ecosystem imbalance among nf-core, Galaxy, and Bioconductor.
- Domain imbalance across the 36 domains.
- Repeated request templates causing superficial memorization.
- Candidate lists with easy negatives rather than confusable same-assay workflows.
- Leakage between train/test through the same study, accession, source description, workflow, or paraphrase template.
- Poor coverage of rare parameter types, conditional fields, arrays, file collections, and cross-field constraints.

Required reporting before training should include:

- examples per workflow/tool/schema version/domain/ecosystem,
- zero-shot and one-shot workflow counts,
- Gini or similar concentration statistics,
- candidate hardness and same-domain negative rates,
- required-field and type-validation failure rates,
- near-duplicate clusters,
- split overlap by workflow, study/accession, source text, and generation template.

Evaluation should include both:

- **Known-workflow generalization:** held-out requests for workflows seen in training.
- **Long-tail/template generalization:** held-out studies and paraphrase templates.
- If desired, unseen-workflow retrieval/reranking, with metadata/schema supplied at inference time.

## Single highest-priority change before GPU training

**Implement a deterministic workflow-contract validator and quarantine/regenerate every failing record before training.**

At minimum, it should reject records when:

1. `clarify_needed` is not exactly consistent with the displayed required/conditional schema.
2. Extracted values fail type, enum, cardinality, or range checks.
3. A request’s input artifacts are incompatible with the selected workflow.
4. A DAG omits direct data dependencies or references the wrong prerequisite.
5. A downstream workflow cannot consume the upstream artifacts.
6. A workflow’s domain or assay contradicts the request.
7. The request does not uniquely support the forced exact-match gold.

Run this over the entire dataset and require zero hard schema/DAG violations before GPU training. The two clarification examples and the `phenomis` cross-workflow label demonstrate that the current data can otherwise teach the model to ignore explicit schemas and produce operationally invalid workflow plans.