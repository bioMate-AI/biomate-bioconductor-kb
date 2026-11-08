# Current-version joint streaming component

Executable: `train_joint_stream.py`; supporting shared_multimodal_trainer.py, train_streaming_rna.py (encoder base only), resumable_checkpoint.py, knowledge_tasks.py, central_dogma_heads.py and central_dogma_losses.py on import path.

Model: shared configurable transformer over stable namespaced feature IDs, observed values and modality tags. RNA/protein/ATAC/ribosome/proteome tags 0/1/2/3/4; separate assay readouts. Observed ATAC binary reconstruction uses BCE; other assay reconstruction uses MSE on adapter-declared transformed scale. Every feature window and row from ready sources is enumerated; no default source/cell/feature count cap. Window size bounds quadratic attention, limiting cross-window context; window enumeration is not equivalent to whole-cell simultaneous attention.

Manifest JSON:
- vocab: unique namespaced feature IDs;
- batches: optional pretokenized {path,source_id,study_id,split}, NPZ ids/values/valid/modality;
- dense_sources: {path,schema_path,source_id,modality,split_by_study}; NPZ values+Boolean observed; schema features+study_ids and declared scale. All samples×feature windows enumerated lazily after loading one bounded assay matrix;
- source_ledger: every collected source with source_id/status; pending entries and integrated-with-zero-exposure entries prevent completion;
- knowledge: optional prepared_dir/mapkg/gene_to_index/heldout_groups. Gene map must be independently verified symbol→global RNA token ID. All train facts are traversed in an exhaustive knowledge pass each epoch; knowledge also interleaves per reconstruction step. Auxiliary heads and shared embeddings are optimized together, without duplicate optimizer parameters.

CLI: --manifest ... --out ... --epochs ... --window 512 --batch-rows 16 --dim 128 --layers 4 --heads 4 --device cpu|cuda. --debug-steps is explicit integration-only and preserves next-batch checkpoint without marking epoch complete. Normal mode has no step cap. --resume checks exact source/schema/config hashes; optimizer/RNG, next batch, exhaustive-knowledge offset and exposure state resume. Changing source queue/vocab requires a versioned extension/reinitialization protocol, not same-run resume.

Study split conflicts fail before training. All validation windows are evaluated at end on a stable RNG seed without changing training RNG; test untouched. No evaluation by row random split. Finite loss and gradients checked; all container parameters clipped. Every successful assay optimizer step adds observed feature exposure. Knowledge counters update after successful optimizer step. Status says pending integration/evaluation, never a model scientific pass.

Validation: 7 tests pass across streaming-RNA, shared multi-omic and joint CLI tests. Joint CLI test runs all 2 train samples×3 windows, all 3 held-out validation windows, pauses after one batch, resumes and matches uninterrupted weights exactly. Synthetic tensors test implementation only; they are not scientific training evidence. Existing canonical adapter test proves measured H1 gradient reaches shared transformer. Full GPU and real large-source runs have not been performed by this agent.

Important remaining work:
- This CLI schedules measured assay reconstruction and structural knowledge, not yet task-specific H1–H4 supervised datasets. CanonicalAdapter is available but must be scheduled only with real intervention labels and masks. No reconstruction task is called measured H2 or H3.
- Text alignment adapter exists separately and requires frozen text encoder/tokenizer runtime; CLI does not yet consume literature shards. Keep text sources pending until actual optimization is wired.
- Full raw source acquisition, verification/deduplication, adapters and ledger are ingestion responsibilities. Current-version curriculum can begin with ready sources but cannot claim all-data completion while any collected source remains pending.
- Dense source NPZ is loaded source by source; production large assays should be native sparse/windowed shards from ingestion.
- Knowledge source/task imbalance is currently explicit exhaustive traversal plus interleaving, not balanced source sampling. Verify exposure and weight contributions; positive-only membership is not predictive link evaluation.
- Exact resume applies unchanged manifest/runtime and deterministic indexed windows; source extension requires a separate recorded checkpoint migration.

## Measured-source schedule (added)

`measured_sources` now executes canonical supervised updates in the same optimizer and checkpoint, after ready reconstruction records each epoch. Manifest must include explicit `head_config`. Each measured entry has path/source_id/study_id/split/objectives (canonical names→positive weights), labels (objective→{value:NPZkey,observed:NPZkey,...}), optional context (head input name→NPZkey), and perturbation_key (default perturbation). NPZ also supplies ids/values/valid/modality. Required mask and censoring fields are validated by existing central_dogma_losses; no labels are inferred. H1 can run without protein/peptide context. H4 requires complete baseline-protein/peptide/HLA/source mapping.

Successful updates record actual observed/censored label counts per canonical objective, independently of shared upstream gradients. H4 gradients updating H2 are not reported as measured H2 supervision. Head parameters join the shared encoder/knowledge optimizer and checkpoint; batch-position resume covers the measured phase. Synthetic CLI contract test schedules H1+H4, verifies H1/H2/H3/H4/encoder parameters update, and resumes to bitwise-identical uninterrupted weights.

`modality_schema` controls contiguous modality IDs and model head count (dict keyed integer strings or list entries with id). Presentation abundance can be its own assay (e.g. id5); its observed reconstruction must not be relabeled H4 delta. Missing source schema uses five modalities only for compatibility with older test fixtures.

## Prepared literature phase (added)

`text_sources` entries provide manifest_path/source_id/heldout_article_ids and optional batch_rows. Prepared manifests must be complete, name the existing sentence-transformers/all-MiniLM-L6-v2 encoder with immutable 40-character revision and tokenizer/mapping SHA256 identities, and contain 384-dimensional frozen vectors. Every chunk and manifest is content-bound into the run identity; iterator independently verifies chunk hashes. This trains a projection from shared RNA gene embeddings to frozen literature embeddings. It is weak mention alignment, not biological target supervision or a randomly initialized language model.

The text phase iterates all prepared windows each epoch. Known held-out articles are skipped without loss, decay or optimizer exposure; no-gene windows were already reported in preparation ledger and are not fabricated training rows. RNA gene indices are range/namespace checked. Projection and shared embeddings are in the common optimizer/checkpoint. Phase progress records text source, chunk, next row and accumulated source exposure. Interrupted text-phase resume produces bitwise-identical weights to uninterrupted execution in a schema-faithful synthetic-vector regression test. Mapping identity is pinned, but authoritative gene-name mapping preparation and actual encoder download/execution remain external prerequisites.

Current CLI regression suite covers reconstruction, measured H1/H4 and prepared-text interrupted/resumed trajectories. No large real-source training was performed by this agent; synthetic vector tests do not demonstrate that literature improved biological predictions.
