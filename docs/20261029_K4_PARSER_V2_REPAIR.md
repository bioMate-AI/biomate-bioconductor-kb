# Patent structure repair v2 — implementation, not a new extraction result

The immutable K4 report records 124/385 conversions: 122 linear-only sequences and two cycles whose closure was assumed. The remaining categories are 138 sequence conversion failures, 100 names, 21 unspecified formats and two HELM strings. There were 987 example records overall. These figures are copied from the stored report, not recomputed; no original record or reported denominator was changed.

Static inspection found further silent identity changes in the parser. The revised parser preserves one-letter histidine instead of deleting `H-`, distinguishes an explicit L-prefix from an additional leucine, and handles D/N-methyl prefix order without inserting aspartate. Compact cyclic wrappers now preserve their internal sequence tokens. Digits, unsupported punctuation and residue annotations are rejected rather than stripped. A single named residue such as `Ala` is no longer converted into three one-letter residues.

The parser no longer infers head-to-tail closure from `cyclo(...)`. The low-level converter supports explicitly requested `closure='head_to_tail'` for callers possessing closure evidence, but the extraction verifier and repair sidecar never supply that argument automatically. Ile, Thr and Hyp conversion fails closed until their side-chain stereochemistry is implemented and verified; generic N-methyl Pro/Hyp remains unsupported. This may reduce syntactic conversion counts, while eliminating false certainty about chemical identity.

The verifier now records graph parsing, unassigned tetrahedral centres, source-structure fidelity and activity linkage separately. A number occurring somewhere in a passage remains an occurrence check only. The numeric matcher no longer accepts 5 as a match for 5.3, -5, 5e-3 or an identifier 15. Every newly verified item remains `method_prior_eligible=false`; no programmatic quotation or graph check establishes a reviewed compound–activity association. Tetrahedral-centre reporting alone does not certify all stereochemistry, including double-bond geometry.

`patent_mining/repair_sidecar.py` prepares prospective, versioned re-conversion from an explicitly hashed original JSONL. It retains each original row unchanged, records its original line hash and line number, and writes only to a new exclusive output path. It does not fetch patents, infer closures, resolve names/HELM, join activity values or promote candidates. A partial interrupted output must be retained or explicitly replaced at a different path; it is not a complete repair result.

On an approved EC2 worker, run the synthetic suites first:

```bash
cd /w/code/cyclic_llm/allatom_paper/patent_mining
python3.11 -m pytest -q test_sequence_repairs.py test_k4.py
```

Only after those tests pass should the sidecar be run on the immutable private K4 archive, with its verified actual input hash and a new private destination. Compare paired outcomes using the original 385 structured-example denominator and retain coverage over all 987 examples. Do not interpret the graph ring indicator as cyclic-peptide identity or interpret non-overlap with a public database as novelty.

Automatically recoverable cases are limited to supported unambiguous sequence syntax. Names, compound numbers, missing structure strings, unknown monomers, linker/closure assignments, incomplete stereochemistry and compound-to-assay joins require source tables, definitions, sequence listings or drawings. This implementation cannot estimate recovery yield from aggregate failure counts.

Singleton named residues are rejected case-insensitively: `Ala`, `ala` and `ALA` cannot silently become three one-letter residues. Genuine one-letter sequences with this ambiguity must use explicit separators, such as `A-L-A`.

No tests, corpus processing, model inference, new mining, paid API calls or AWS launches were executed for this revision. Remote QA remains pending. No freedom-to-operate conclusion is made.
