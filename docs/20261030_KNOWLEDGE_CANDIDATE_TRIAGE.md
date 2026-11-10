# Knowledge-candidate triage against frozen C — 30 October 2026

## Decision boundary

Source qualification and generation compatibility are separate. The current recovered set supplies useful real evidence, but no entry is established here as an approved C-compatible learned-conditioning parent. This review reads source reports and code only; no descriptors, graph parsing, tests or data aggregation were run. Do not relax C to accommodate the recovered examples.

`research/guangzhou_all_atom/cyclic_llm/allatom_paper/rules/spec.py` requires all of:

- A sanitizable molecule with exactly one fragment.
- Largest RDKit-perceived atom ring at least 12 atoms; this is not a residue-count requirement or proof of a particular closure route.
- Between 2 and 6 matches of `[CX3](=O)[NX3;!H1]([CH3])` inclusive. N-methyl groups on other nitrogens and O-methyl groups do not automatically count.
- RDKit molecular weight between 600 and 1400 inclusive, TPSA at most 300, and no PAINS match.

Full C cannot be certified from a chemical name, a drawing, a literature mass or a successful parser alone. Nevertheless, a plainly incompatible source value can stop further admission work without recomputing descriptors.

## Established source-level incompatibility

| Candidate | Exact evidence available | Consequence under frozen C |
|---|---|---|
| AfCycDesign 9CDZ:B / CARD-AFCYC-001 | Existing K3 row at `structure_knowledge/results/library_v1.jsonl:687` records `n_nme=0`; the independently inspected deposit has the unmodified standard-residue sequence `GLIDGTEGTDFESMWR`. | Fails the N-methyl minimum on existing evidence. Keep as structural context outside the admitted generation-parent pool. This review does not rerun K3 descriptors. |
| GIP-057 / `ba134a47b2b054df` | EP4170347A1 Example 2 reports molecular weight 2400.949. | Clearly outside the upper mass bound. Graph recovery may serve the KB, but is not a priority for this C-constrained generation experiment. |
| GIP-126 / `fa4169d82a10b247` | EP4170347A1 Example 3 reports molecular weight 2301.683. | Same mass exclusion. Do not strip DOTA/spacer groups to manufacture a different admissible parent under the same evidence ID. |
| Val-Ala linker / `9688e01dfb0dcf72` and related short linker examples | Source identifies linker components, not standalone cyclic peptides; no macrocyclic closure is specified. | The named linear components are not suitable cyclic parents. Linking them into an unspecified larger molecule would create a new identity and require new evidence. |

These masses are source-reported values already inspected in the primary examples, not local RDKit results. Compound 22 is being qualified separately by the parent task; its independently reported mass exclusion should be joined only after that review is recorded. This document does not fabricate a completed compound-22 audit.

## Source-reading concerns, not computed failures

| Candidate | Concern | What remains uncomputed or unresolved |
|---|---|---|
| RM-511 / `35fcd616b1098727` | Inspected drawing establishes disulfide closure but shows no obvious qualifying N-methyl amides. | Full hydantoin/stereochemical graph and exact SMARTS count; MW/TPSA/PAINS. A nitrogen in the hydantoin or a methyl on carbon is not evidence of an N-methyl amide. |
| Ref Ex 2 / `db28a398d88433ee` | Named sequence and source closure context show no declared N-methylation. | Complete Ref Ex 2 graph, absolute stereochemistry and precise count remain unqualified. Do not infer N-methylation from its acetyl cap or free Dab/Orn nitrogen. |
| Grazoprevir / LIT-CHAM-003 | Source CCD graph is available, but its methyl substituents are not evidence that it satisfies this specific N-methyl-amide motif. Strict cyclic-peptide domain compatibility is also unresolved. | C has not been evaluated; preserve its role as out-of-domain conformational context unless explicitly prespecified otherwise. |
| SuFEx 4FSB-GXGY / K2-d590a3f68dcd | The tested named series does not declare N-methylated amides. | Installed linker and complete product graphs; all C descriptors; exact-parent qualification. O/S chemistry does not supply the required N-methyl count. |
| Macrocycle/linear series 1/5 / K2-124d856a78cc | Linear series 5 is the comparator; its phenolic O-methylation is not N-methylation. | Source graph qualification for each cyclic series-1 parent and C evaluation. Never substitute the linear comparator for a cyclic parent or transfer its effect unconditionally. |
| Thiazoline precursors 2b/3b / K2-4c761c0659ae | Nitrile precursors are linear; products are different molecules. No qualifying N-methylation established. | Exact cyclic product mapping and chemistry checks; precursor reaction evidence alone does not establish a valid product parent. |
| Cyclin precedent 1URC | Inspected deposit did not establish the claimed closure or exact identity with campaign compound 6. | Chemical identity/closure before any C evaluation. Do not fill in the missing bond from a convenient assumed lariat topology. |

No row in this table is represented as a fresh descriptor result. Missing evidence is not proof that a molecule fails; it is a reason to avoid declaring a pass.

## Learned memory requires the exact selected parent

`hybrid/learned_knowledge_inputs.py::__call__` looks up the selected **SMILES string** in the frozen parent map; an unknown string raises `selected parent lacks approved mapping`. It passes only that parent's ID into memory packing. It does not use nearest scaffold, sequence similarity, a campaign-wide association or an arbitrary evidence molecule to establish applicability. Equivalent alternative SMILES need an explicit frozen identity mapping; no implicit canonicalization should be assumed.

`hybrid/knowledge_memory.py` separately requires learned-conditioning permission, `approved_for_learned_conditioning`, empty unresolved flags, matching parent IDs and scope, verified source text/hash/quotation span and source exclusions. Required scope includes property, endpoint, assay, closure, scaffold and solvent. Optional embeddings must name an approved mapped parent. **Position-specific records are currently denied** (`local_position_not_supported`). Consequently the location-specific Cyclin methylation observation cannot be smuggled in by removing its position-specific flag. A genuinely molecule-level supported observation could be reviewed separately with its narrower meaning.

In study learned-on mode, the selected parent needs an eligible evidence slot. A general context card about 9CDZ cannot satisfy this requirement for a different generated parent, and synthetic approval labels cannot turn an unqualified real record into evidence. Present packets remain AI-assisted review candidates, not approved executable records.

## Source priorities for compatible candidates

1. **Prioritize the existing Cyclin A/B primary campaign's explicitly di-N-methylated compound 5** (LIT-NMEPOS-001/CARD-CYCLINAB-001, PMCID PMC13138696, DOI 10.1021/acs.jmedchem.5c00253). Recover its source graph, exact molecule-level assay statement and source ID first. Check whether both reported methylated nitrogens actually satisfy C's carbonyl-adjacent SMARTS, then all other bounds on authorized remote compute. “Di-N-methyl” alone is insufficient. Retain site-specific SAR separately because the current memory rejects local-position interventions.
2. **Inspect other explicitly N-methylated, fully deposited parent molecules in the same campaign and its oral-optimization follow-up** (CARD-CYCLINAB-002, PMC12990038). Prefer complete compound graph/assay rows already supplied by authors over large conjugates requiring extensive reconstruction. Do not assume the optimization paper's broad guidelines qualify individual compounds or treat computational binding models as experimental structures.
3. **Cross-reference allowed training-source parent identities with existing public KB primary records**, preserving the exact compound, scaffold and source-family lineage. If those primary molecules already meet C, source qualification can attach scoped qualitative context without a numeric reward. Exclude stop/held-out sources, compounds, scaffolds and target families before collecting their outcomes. Do not preferentially choose examples based on held-out performance.

The immediate bottleneck is a source-qualified **C-compatible exact parent**, not a shortage of quotations. Remote C checks and split verification follow source identity qualification; they must not be replaced by changing the frozen bounds or declaring broadly related evidence applicable.

## Evidence trail

- `20261030_REAL_EVIDENCE_READINESS.md`: deposited 9CDZ and CCD SUE identities, hashes and 1URC ambiguity.
- `20261030_PATENT_GIP_COMPONENT_QUALIFICATION.md`: primary linker/conjugate definitions and inspected drawings.
- `20261030_PATENT_RM511_DRAWING_QUALIFICATION.md`: direct disulfide and hydantoin observations.
- `20261030_PATENT_REFEX2_QUALIFICATION.md`: closure-class, Dab definition and assay scope.
- `20261029_literature_recovery_candidates.json` and `20261029_patent_recovery_candidates.json`: unresolved candidate records; not admission certificates.

Only this triage document was created. No candidate permissions, source records, graphs or frozen constraints were changed.
