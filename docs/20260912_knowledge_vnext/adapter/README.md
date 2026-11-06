# Current knowledge objective adapter

`load_knowledge(current_prepared, mapkg=optional_path)` preserves all prepared pathway memberships, typed PrimeKG edges, disease-specific genetic priors, CollecTRI relations and evidence-qualified signs. Optional MAP-KG parses confidence separately and drops exact duplicated exports. No top-K cap or fabricated nonedge negatives.

`KnowledgeTasks(facts, shared_encoder.genes, gene_to_index=verified_symbol_to_global_index)` uses the actual caller-owned gene embedding. Unmatched or non-gene entities receive typed auxiliary embeddings; report mapping coverage rather than claim all nodes updated shared genes. A namespaced RNA/Ensembl vocabulary requires a verified symbol mapping. Optimizer construction must deduplicate shared parameters while including auxiliary embeddings and heads.

For each frame batch: `loss, parts, counters = adapter(batch, heldout_groups=...)`. After a successful optimizer step call `adapter.record_optimizer_step(counters)`. Forward exposure is not optimizer exposure. Counters exclude inferred signs and zero-confidence facts from supervised source counts. Persist counters with checkpoint/run state.

Objectives are positive-edge relation classification, positive membership alignment, disease-prior regression and signed regulation only when `sign_decision == PMID`. Default activation and regulon-inferred signs remain stored but unsupervised as experimental signs. Membership alignment alone admits collapse; use biological objectives and ablations, not a training-loss claim of useful biology. Observed edge labels are not causal proof.

Split groups hash typed endpoint pairs independent of source and direction, so exact reciprocal/cross-source facts share a group. Alias normalization, source-study holdouts and downstream target-level exclusions remain caller responsibilities; these hashes alone do not prevent all evaluation leakage. Unknown release/licensing information remains unresolved in the acquisition manifest.

Four tests check actual uncapped artifact counts/disease coverage, shared-embedding gradients and exposure, held-out group rejection, and inferred-sign mutation invariance. This is staged implementation, not a launched current-model training run. Text knowledge is not covered by this adapter.
