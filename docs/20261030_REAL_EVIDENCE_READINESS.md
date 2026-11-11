# Real evidence readiness from the curated knowledge layer — 30 October 2026

## Outcome

Two concrete source-to-molecule mappings are available without reconstructing a graph from prose: **AfCycDesign/9CDZ chain B** and **grazoprevir/CCD SUE**. The former already has a row in the existing structure library. They support scoped conditioning context, not numerical rewards or universal edit rules. Neither is approved here as a parent satisfying the current generation constraint C. A third apparent join, Cyclin A/1URC, has a closure ambiguity and is withheld.

This targeted audit read the 107-entry KB, selected primary papers, existing K3 records and deposited structure text. It did not run chemistry, model inference, tests or statistical aggregation. The old document's quote verification and “weight eligible” designations do not establish molecular applicability or held-out independence.

## 1. Direct existing-library join: CARD-AFCYC-001 → 9CDZ:B

**Curated source:** DOI `10.1038/s41467-025-59940-7`, PMCID `PMC12095755`, recorded text hash `fc9a33c8a8d3a7df014fd2a3cf7b3dcd7b4db777344f6325714bca29b5277f92` (not rehashed here).

The paper identifies RMG_14 as the peptide crystallized with MDM2. Its methods give **9CDZ**; the data-availability text contains a transposed **9DCZ** but links to 9CDZ. The authoritative wwPDB entry confirms 9CDZ and the same publication DOI. [Primary paper](https://www.nature.com/articles/s41467-025-59940-7), [wwPDB deposition](https://www.wwpdb.org/pdb?id=pdb_00009cdz).

The downloaded mmCIF explicitly supplies:

- Polymer entity 2: `GLIDGTEGTDFESMWR`, chains B and D, standard L-polypeptide representation.
- `_struct_conn`: chain B Gly1 N linked covalently to Arg16 C; the same closure is listed for chain D. This establishes terminal closure from the deposit rather than a guessed `cyclo` label.
- Existing mapping: `research/guangzhou_all_atom/cyclic_llm/allatom_paper/structure_knowledge/results/library_v1.jsonl:687` has `pdb_id=9CDZ`, `pep_chain=B`, `rec_chains=[A]`, the same sequence, target `Q00987`, and `primary_cyclisation=head_to_tail`. Its affinity list is empty. No numerical affinity is added.

**Candidate conditioning statement:** this exact head-to-tail peptide has an experimentally deposited MDM2-bound conformation. This is a positive structural-context example, not a generic claim that an arbitrary sequence or edit improves affinity/permeability. [Deposited mmCIF](https://files.rcsb.org/download/9CDZ.cif).

**Concrete input join:** `evidence_id=CARD-AFCYC-001; structure_id=9CDZ; peptide_chain=B; target=Q00987; parent_sequence=GLIDGTEGTDFESMWR; closure=(B,ARG,16,C)-(B,GLY,1,N); evidence_kind=experimental_bound_structure`. Match by the exact source DOI and structure/chain identity, not only peptide-name similarity. This is ready to populate a *review-candidate* context record linked to the existing K3 row.

**Generation limitation:** the existing row records `n_nme=0`, whereas `rules/spec.py` requires 2–6 N-methyl amides. Thus this cannot simply be inserted as a C-valid generation parent. No descriptor computation was run to assess its other bounds. Keep context eligibility separate from generation-parent eligibility, and do not change C merely to admit this example.

## 2. Exact deposited graph: LIT-CHAM-003 → grazoprevir/CCD SUE

**Curated source:** DOI `10.1002/chem.202502256`, PMCID `PMC12929930`, recorded text hash `17161ed2d67515d5ac9b422370283962b5f70521fa52579532837f1941061269` (not rehashed here).

The primary study compares grazoprevir across solid, polar/apolar solution and bound states. Its Figure 3 explicitly includes 3SUE. That deposit is an **R155K HCV NS3/4A variant** complex, not a wild-type target. Its ligand component SUE is explicitly aliased grazoprevir/MK-5172. [Primary study](https://pmc.ncbi.nlm.nih.gov/articles/PMC12929930/), [3SUE](https://www.rcsb.org/structure/3SUE).

The public CCD provides atoms, bonds and stereochemical descriptors. Source InChIKey: `OBMNJSNZOWALQB-NCQNOWPTSA-N`. The following is copied from the CCD's OpenEye canonical descriptor; it is **not** newly generated or chemically validated here:

```text
CC(C)(C)[C@H]1C(=O)N2C[C@@H](C[C@H]2C(=O)N[C@@]3(C[C@H]3C=C)C(=O)NS(=O)(=O)C4CC4)Oc5c(nc6ccc(cc6n5)OC)CCCCC[C@@H]7C[C@H]7OC(=O)N1
```

[CCD component and descriptor](https://www.rcsb.org/ligand/SUE), [CCD source file](https://files.rcsb.org/ligands/download/SUE.cif).

**Candidate conditioning statement:** grazoprevir exhibits environment-dependent conformations and intramolecular hydrogen bonding in this study. Attach it only to this molecular identity as conformational context. Do not translate the source's conformer populations into sampler weights, or infer that adding any hydrogen-bond donor improves permeability. This macrocyclic peptidomimetic is outside a strict canonical cyclic-peptide scope; use as an explicit out-of-domain context/control if the study permits it, otherwise exclude. Its C eligibility is untested.

## 3. Withheld join: CARD-CYCLINAB-001 → 1URC

The curated card's primary source (DOI `10.1021/acs.jmedchem.5c00253`, PMCID `PMC13138696`) refers to 1URC as a lariat precedent and separately describes compound 6. The inspected 1URC deposit names Ace-Arg-Lys-Leu-Phe-Gly, represents `(ACE)RKLFG` in chains E/F, and lists ACE–ARG connections, but its `_struct_conn` section does **not** supply the putative ring-closing bond. Do not equate this deposit with compound 6 or invent a Lys-side-chain closure. Its underlying primary citation is DOI `10.1039/B409157D`. [Campaign source](https://pmc.ncbi.nlm.nih.gov/articles/PMC13138696/), [deposition](https://www.rcsb.org/structure/1URC).

The campaign's deposited supplementary models for compounds 7 and 34 are computational binding models, not automatically crystal structures. This candidate remains unresolved until the underlying chemical topology and exact compound correspondence are established.

## Preserved structure provenance

| Public file | Local read-only download | SHA-256 |
|---|---|---|
| `9CDZ.cif` | `/tmp/evidence_9CDZ.cif` | `29774e0f0daebfbf04128052e687a87e4ac6fb1d410ed131a353086910f6ed47` |
| `3SUE.cif` | `/tmp/evidence_3SUE.cif` | `f32f967028e2792ddf2e370749f0e8437fb2f88ce50c809f269b474993b76dca` |
| `SUE.cif` | `/tmp/evidence_SUE.cif` | `a596aff28b4284f656fa4ebdde260c46647ee1c7dbf938b3a8542def7cc501c0` |
| `1URC.cif` | `/tmp/evidence_1URC.cif` | `8e01b2e9fa49b27a7538a4552ff29f0ec2a51741f92bba0c3a1c2da8d57d832e` |

Hashes identify the exact downloaded files inspected; future deposit revisions may differ. No new structure was synthesized or inferred.

## Qualification before learned conditioning

Start with the existing **9CDZ:B** library join for a real-source conditioning contract, then use CCD SUE only if out-of-domain contextual controls are prespecified. Both remain `AI_ASSISTED_CANDIDATE`, `method_prior_eligible=false`, with no numerical prior.

Required checks are concrete: freeze source and coordinate versions; verify source-chain correspondence and selected-model completeness; qualify the context-to-parent relationship; remove overlap with stop/held-out compounds, scaffolds, source papers and target families; prevent the same 9CDZ structural evidence from appearing in both training context and evaluation. Existing-library presence proves availability, not split clearance. For grazoprevir, also exclude related protease-bound deposits from held-out structural tests and preserve the R155K qualifier. Remote chemistry checks may then validate source graphs and C separately. A valid generation-parent example still requires a source-qualified molecule satisfying the frozen C and split rules.

## Implementation clarification: output constraints versus prefix parents

Subsequent inspection of `hybrid/model.py::sample` and `hybrid/run_stage1.py::FrozenParentProtocol` establishes that C constrains completed proposals. The frozen parent pool enforces source/task metadata and exclusions, but does not require the full parent molecule to pass C. Therefore an out-of-C source molecule is not automatically prohibited as a prefix parent by the code. Earlier references here to C-valid generation parents describe a possible narrower study design, not an implemented universal eligibility rule. Such a restriction must be explicitly prespecified if adopted. Any parent still needs an exact reviewed mapping, evidence applicability and split clearance; whether its retained prefix can yield valid completions remains an empirical question. None of these candidates is promoted by this clarification.
