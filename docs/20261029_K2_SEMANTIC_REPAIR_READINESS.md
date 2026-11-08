# K2 semantic repair readiness

The literature pilot remains immutable. These prospective changes do not regenerate it, amend its measured counts, or admit its strict subset to the method. No extraction, paid API call, local scientific computation or tests were run for this change.

## Repairs implemented

`knowledge_scale/verify.py` now rejects malformed object/text/effect fields rather than crashing, nonfinite or nonnumeric effect values, positive-number substrings inside negative values, and NaN/out-of-range confidence in the strict predicate. Numeric occurrence remains a weak check: it cannot establish compound identity, causal direction, effect units or the correct comparator. Existing A5.1 endpoint keywords are retained for reproducibility; tightening them retrospectively would change the old strict population.

`knowledge_scale/eligibility.py` adds a separate prospective review-sidecar contract. It binds an unchanged extraction record by canonical JSON hash, the inspected primary-source text by byte hash, and a quotation by exact text offsets. Reviewed endpoint, entity, direction, comparator, scope, claim origin and overlap checks must be explicit. Unresolved flags deny permission. Conditional parent selection additionally needs approved parent IDs, a parent-map hash and reviewed applicability. Numeric priors and unimplemented chemical actions are rejected. Passing this contract establishes review completeness, not the scientific correctness or independence of that review; reviewer type remains explicit.

The new synthetic contracts are in `knowledge_scale/test_semantic_eligibility.py`. Run them with the existing K2 tests on authorised AWS compute before relying on the changed verifier. No test result is claimed here.

## Recoverable from stored evidence versus additional source work

- **K2-76649530902f:** stored text supports auditing the reversed direction; preserve original record as failed and create a reviewed corrected sidecar. Confirm the named scaffold, intervention and comparator before permission.
- **K2-d2e32c9e1521:** correct cellular inhibition versus binding affinity using stored context; numerical affinity use remains prohibited. Exact compound and assay mapping is still needed.
- **K2-4c761c0659ae:** recover scoped cyclization chemistry, not proteolytic stability; precursor structures and reaction conditions are necessary for an executable action. Current implemented action is parent selection only.
- **K2-fc5211ae1ecd:** distinguish introductory historical background from the article's own result; no current-state or causal prior follows from the background statement. Inspect the primary results and any cited original source separately.
- **K2-3776fc3b71b8:** receptor/complex SASA cannot become peptide solubility by relabelling. A peptide-solubility claim needs independent supporting measurement/source evidence.
- **K2-6dde35922ebc:** successful binding of a symmetric design does not identify symmetry's effect. A directional intervention requires a relevant comparator, possibly absent from the current source.
- **K2-d590a3f68dcd and K2-124d856a78cc:** useful conditional candidates, but source tables/supplements and exact chemical identities must be inspected if not present in stored full text. Do not infer missing structure, closure, stereochemistry or matched-pair correspondence from prose alone.

## Exact remaining inputs for a model catalogue

1. Accepted review sidecars and the unchanged raw records, with review identity and all unresolved issues settled explicitly.
2. Frozen primary-source snapshots and exact offsets; corrected claims must retain original record hashes and correction provenance.
3. Source DOI/PMCID aliases mapped to full evidence families; separate compound, scaffold, target and study split exclusions. Author/year flags do not supply this mapping.
4. Named experimental entities mapped to complete isomeric structures, closure chemistry and stable parent/compound/scaffold IDs; task/assay/solvent/endpoint applicability values must match the model's scope vocabulary.
5. Frozen parent map plus approved parent IDs per claim. If an intervention requires an unsupported edit, retain it as contextual evidence until that action exists and is validated.
6. Explicit reviewed permissions and a frozen catalogue manifest. No automatic export from the raw/strict loader is added by this patch.

The next useful operation is source-backed completion of these fields for a small candidate subset, followed by remote contract QA and a separately registered knowledge-on integration test. Additional broad extraction does not resolve the existing endpoint, comparator and provenance errors.
