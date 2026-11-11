# K4 structure repair plan — 29 October 2026

**The failure needs source-linked chemical reconstruction, not another extraction run or automatic cyclization.** The original K4 report remains unchanged: 124/385 parse successes (0.322), consisting of 122 linear-only sequences and two assumed cycles. Neither category establishes a faithful patent macrocycle. Scale-up and patent knowledge use remain blocked.

This audit read the persisted aggregate `/tmp/knowledge-terminal-audit/k4/pilot_measure.json` and local parser/verifier code. It did not download or export raw patent examples, execute numerical work/tests locally, launch compute, or inspect original patent drawings. Counts below are transcribed from that report, not recomputed. Its integrity and S3 origin are recorded in `20261029_K2_K4_TERMINAL_REVIEW.md`.

## What failed and what can be repaired

| Original category | Count | Required repair/evidence |
|---|---:|---|
| `ok_linear_only` | 122 | Resolve the compound ID to its exact example, sequence listing, drawing and cyclization procedure. Identify whether the extracted string is a precursor, a linear compound, or an incomplete description. Add a bond only when source-linked endpoints and bond type are explicit. Genuine linear compounds remain linear and ineligible for a cyclic-structure claim. |
| `ok_cyclo_assumed` | 2 | The parser maps the word `cyclo` to a head-to-tail amide automatically. Independently establish closure topology, attachment atoms, stereochemistry and any linker from the source; the lexical marker alone is insufficient. |
| `seq_convert_fail` | 138 | Inventory exact failure reasons and residue tokens remotely, retaining item IDs and original strings internally. Distinguish unsupported syntax from unspecified chemistry. Resolve noncanonical residues through the patent's definition table/sequence listing or explicit structure; never infer an unknown residue from approximate spelling. |
| `not_converted_name` | 100 | A compound name or example number is a lookup key, not a structure. Join it to the same patent's table/drawing and substitutions. Generic/Markush names remain unresolved unless one complete instantiated compound is identified. |
| `not_converted_none` | 21 | Review whether the format label is wrong or the quoted string is not a structure. Correct only in a versioned sidecar with exact source evidence. Do not relabel solely to increase conversion. |
| `not_converted_HELM` | 2 | Require the exact monomer dictionary and explicit connection block. Validate attachment labels, modified monomers, stereochemistry and closure against the source before conversion. |

The report also contains 987 example entries, only 385 with a structure string. Preserve this wider coverage denominator alongside the fixed 385 conversion denominator. Recovering previously absent strings is a separate versioned coverage analysis, not a way to replace the original denominator.

## Confirmed implementation defects and narrow prospective fixes

`seq2smiles.py` had several deterministic defects independent of the 138 unresolved examples. These fixes are prospective and have not been run against the patent corpus:

- Terminal `Ac`, `NH2` and `OH` annotations were removed before conversion, silently changing chemistry. The converter now rejects these unsupported terminal annotations instead of deleting them. Supporting a particular cap later requires an explicit atom-level implementation and source-appropriate tests.
- N-methyl Pro/Hyp passed into branches that ignored the N-methyl flag. Those unsupported structures now fail closed.
- An initial one-letter `D` in a compact sequence such as synthetic `DAG` was consumed as a D-stereochemistry prefix, deleting the Asp residue. Compact and fully one-letter-delimited sequences now retain that residue; `D-Phe` still denotes the explicit three-letter stereochemical prefix.
- Standalone `NMe-Phe` syntax now matches the already supported `N-Me-Phe` tokenization.

These corrections may lower the reported parse-success count by exposing previously silent errors. They do not establish a higher faithful cyclic-structure yield. Added `patent_mining/test_sequence_repairs.py` has nine synthetic cases. No existing output or reported count was changed. Remote QA is pending.

Additional limitations remain: Ile/Thr side-chain stereochemistry is not explicitly assigned by the fragment table; Hyp stereochemistry is hard-coded; broad `cyclo` detection assumes head-to-tail closure; terminal Pro/Hyp cyclization is unsupported. Do not label their outputs fully specified source-faithful structures without independent review. `verify_patent.py` currently calls linear/assumed-cycle products `ok_*`; `postprocess.py` counts every status beginning with `ok` as parse success. That is a syntactic/conversion measure, not cyclic identity validation. The existing macrocycle graph filter in `pm_filter.py` is useful only as a necessary topology screen after reconstruction; it cannot prove source correspondence or stereochemistry.

## Versioned repair interface

Create a new private repair prefix; never rewrite `k4/ext3/` or its `pilot/measure.json`. For every reviewed original item retain:

- Original item ID, patent publication and family ID, compound/example/table/SEQ-ID identifiers, original structure string/format/status and original KB hash.
- Source document hash plus page/figure/table-cell or text offsets; exact quoted structure/definition/closure evidence. Image-derived recovery additionally retains an internal crop reference and its hash.
- Explicit residue sequence or monomer IDs; each modification's definition source; terminal groups; absolute stereochemistry including side chains; attachment atom mapping; closure bond type/endpoints; linker identity and substitutions. Missing information stays explicitly unresolved.
- Candidate atom-mapped structure and canonical isomeric representation, converter version and dependency versions; topology-filter result; unresolved stereocentres and unsupported features.
- Independent redraw/reconstruction result, reviewer identity/date and disagreements. No automated or agent-only check is labelled an independent human review.
- Compound-to-activity join evidence: exact row/compound ID, assay, target, value/relation/unit. A number elsewhere in the passage is insufficient; the current `num_ok` function only checks occurrence and does not establish this association.

Statuses should distinguish `unresolved`, `reconstructed_unreviewed`, `reviewed_linear`, `reviewed_cyclic`, and `rejected_mapping`, while retaining the original status in a separate field. Do not overwrite `structure_status` in original records. Keep graph validation, source fidelity, stereochemical completeness and activity linkage as separate checks.

## Executable next steps without a new extraction job

1. Package the two prospective parser files with the existing patent module into an isolated EC2 CPU QA directory. On an already authorized allocation, from `allatom_paper/patent_mining`, run:

   ```bash
   CUDA_VISIBLE_DEVICES='' PYTHONPATH="$PWD" python3.11 -m pytest -q test_sequence_repairs.py test_k4.py
   ```

   The full legacy suite needs its existing extraction/import dependencies. Do not install into or modify an active mining environment. This note authorizes no provisioning or new spend.

2. Against immutable verified items on that authorized worker, produce an internal error inventory keyed by original item ID and full `seq_convert_fail` suffix. Review the 122 linear and two assumed-cycle cases first for precursor/closure ambiguity, then prioritize exact syntax fixes among the 138 failures. The aggregate alone cannot tell how many are repairable; no recovery-yield estimate is justified yet.
3. For a bounded pilot, select and freeze an audit sample before inspecting repair outcomes. Reconstruct from source evidence, independently redraw, and resolve discrepancies. Keep all selected failures in the denominator; do not substitute easy examples.
4. Reprocess only into a new version and report paired old/new outcomes over the same 385 original structured examples, plus coverage over all 987 examples. Separately report faithful reviewed cyclic counts and unresolved counts. Preserve the original 0.322 and its status composition in every comparison.
5. Re-evaluate the registered >=0.60 parsing gate on the unchanged denominator and the independent precision >=0.80/Wilson requirement. Do not replace the registered parsing measure with a more convenient denominator or quietly call linear conversions cyclic successes. The >=20 patents-with-examples criterion was already met, but it does not repair chemistry. Zero BindingDB overlap remains uninterpretable as novelty until structures and matching are validated.

The initial method knowledge catalogue should continue to prioritize reviewed literature statements. Patent structures remain quarantined until these source-fidelity gates are met; even a corrected parser does not confer numerical-prior or method-action permission.
