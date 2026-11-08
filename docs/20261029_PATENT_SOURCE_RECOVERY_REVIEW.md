# K4 patent source recovery review — 29 October 2026

## Scope and provenance

This is a targeted, assistant-assisted reading of actual preserved records and their stored primary-patent text. It is not a random sample, population precision estimate, structural validation or new mining run. No chemical parsing, tests, model execution or statistical aggregation was performed. Original records remain unchanged and none is promoted to method priors.

Records were read from `s3://biomate-nextflow-work/cyclic_peptide/allatom/k4/ext3/pilot/patent_kb_pilot.jsonl`, downloaded read-only to `/tmp/k4_patent_kb_pilot.jsonl`. Primary context was read from the existing `/tmp/k4_corpus.jsonl.gz` (the sel3 corpus). The extraction records retain passage IDs, but not exact character offsets or patent paragraph numbers. Passage suffixes are extraction-window identifiers, **not** paragraph numbers. Context below is located by named examples, table numbers and literal search anchors; no offsets are invented.

Stored source text identifiers (subsequently verified against the retained UTF-8 text strings; see follow-up below):

| Patent | `text_sha256` |
|---|---|
| WO-2014151634-A1 | `5377bfcff5879026a07bbb2b0079955b5f6d898138c010e78cae967a67083905` |
| WO-2024108198-A2 | `ffddf6cc555352de7dfde6fe95579cf284ea30e5f777842a8f57a3efe567a719` |
| EP-4170347-A1 | `55a80db3859d9cb5492798f4044332c483d0d6d4d26093ad4aec83dfdfd20354` |
| US-20100311648-A1 | `b3720703224c2e4ee37e9005b354898fb5fd14c37eb1b4988046d9a6bc22270e` |

## Concrete recoveries and exclusions

### Interleaved assay columns corrupted a sequence

Record `db28a398d88433ee`, passage `US-20100311648-A1:29`, compound `Ref Ex 2`, failed on residue `8`. Its structure string is `Ac-Arg-cyclo(Glu- 8 3.0 92 Dab-D-Phe-Arg- Trp-Orn)-OH`. In the stored [primary patent](https://patents.google.com/patent/US20100311648A1/en), **Table 1** places three assay columns in the middle of a wrapped sequence. Its neighboring Ref Ex 1 row has the same wrapping pattern.

The supported textual repair is `Ac-Arg-cyclo(Glu-Dab-D-Phe-Arg-Trp-Orn)-OH`, with separate observations Ki 8 nM, EC50 3.0 nM and intrinsic activity 92%. The table includes a 0.1 ng/mL doxycycline header, but its scope across individual assay columns has not been visually verified and must not be assigned indiscriminately to all endpoints. The existing activity object calls the endpoint `intrinsic K i`; the header distinguishes Ki from intrinsic activity, so that label also needs correction. These are source-reported values, not newly calculated results.

Next correction: preserve the original string and add a reviewed table-row reconstruction with explicit column labels, compound ID and context. Do not globally delete numbers from sequences. The recovered text still requires an explicit closure-site definition, Dab stereochemistry and terminal-group representation before graph reconstruction. The current v2 parser intentionally does not reconstruct this modified peptide. The table supplies a real compound-to-assay join; exact structure qualification remains separate.

### A cyclization reagent is present in the source, outside the short extraction quote

Records `ba134a47b2b054df` (GIP-057) and `fa4169d82a10b247` (GIP-126), both passage `EP-4170347-A1:140`, fail on modified residues (`3MeBn` and DOTA). In the stored [primary patent](https://patents.google.com/patent/EP4170347A1/en), **Examples 2 and 3** identify the final compounds and state that the linear precursor underwent **Solution Cyclization method A with dibromoxylene**. The general method explicitly identifies alpha,alpha-prime-dibromo-m-xylene or 2,6-bis(bromomethyl)pyridine, and the example selects the dibromoxylene branch. This supports a linker-mediated closure assignment, not an assumed head-to-tail amide or generic disulfide.

For GIP-126, the short quote gives the linear precursor without the bracketed `Cys(3MeBn)` notation, whereas its example heading names the cyclic product. That difference is explainable by the synthesis context, not by silently replacing the quote. Retain separate precursor and product fields and join them through Example 3. GIP-057 also carries Ttds and biotin; GIP-126 carries DOTA and Ttds. Their exact monomer/linker definitions and stereochemical graphs still need source qualification. Neither audited record supplies an activity value. Synthesis yield or exact mass must not be substituted for biological activity.

Next correction: use example-level context and the named general procedure to populate closure evidence, then resolve each modified component against source definitions/drawings. A graph builder must represent both linker attachment sites and retained terminal/conjugate groups. Current parser failure is appropriate until that representation exists.

### Sequence and identity can be recovered, but a missing drawing cannot be guessed

Record `35fcd616b1098727`, passage `WO-2024108198-A2:76`, is SEQ ID NO:148, `Hydantoin(C(O)-(Arg-Gly))-c(Cys-Glu-His-D-Phe-Arg-Trp-Cys)-NH 2`. It failed on Hydantoin. The stored [primary patent](https://patents.google.com/patent/WO2024108198A2/en) explicitly aliases this sequence to **RM-511**, under Formula II, and says its structure is shown below. It cites WO2008/147556 for that formula. The plain text does not preserve the indicated structural drawing.

Next correction: attach the supported RM-511/SEQ-ID identity and Formula-II provenance. Retrieve and inspect the cited drawing/source before assigning hydantoin connectivity and closure bonds. Nearby generic formulas discuss disulfide and lactam alternatives; those alternatives are not sufficient to choose every atom-level bond for this particular structure. Activity is null in this record and no numerical assay join is established by this review. This is a source-image recovery task, not a permissive unknown-residue parser fix.

### A reliable assay row is available without its structure

Record `1dbd58d6798c1f37`, passage `WO-2014151634-A1:544`, identifies **Compound No. 22** with HTRF IC50 3 nM, but has no structure string. The stored [primary patent](https://patents.google.com/patent/WO2014151634A1/en), **Table 8 — Compound No. 1 Variant Macrocyclic Peptides**, explicitly pairs compound 22 with 3 and labels the assay human PD-L1/PD-1 binding IC50 in nM. Surrounding text describes inhibition of PD-1 binding to PD-L1.

Next correction: retain this as a compound-specific binding-inhibition measurement with table provenance. Do not relabel it Kd, direct affinity, or a universal modification rule. Join compound 22 to its exact synthesis/structure entry and verify closure/stereochemistry before using it in a chemical prior. The stored row alone supports the measurement mapping; it does not supply the graph or isolate a causal sequence modification.

### Some conversion failures are appropriate scope exclusions

Record `9688e01dfb0dcf72` (Val-Ala) and related `7d3ea777c0cfb05f` (Val-Cit), passage `US-20240376154-A1:32`, are examples of **cathepsin-B-cleavable linker sequences** in the stored primary text. The preceding sentence explicitly assigns these sequences to linker L. The list is not a set of assayed standalone cyclic peptides. Related record `188c887faedc55d2` (Asp-Val-Ala) was `ok_linear_only`; that parser success does not fix the entity mismatch.

Next correction: classify these as linker-component context, with no cyclic-peptide structure/measurement eligibility. Do not expand the converter merely to turn these rows into passing cyclic-peptide examples. No compound-specific activity value or closure is supported by this passage.

## Priority and implementation consequence

The first actionable source repair is Table 1's sequence/assay-column separation, followed by explicit precursor/product and closure-procedure joins for GIP-057/GIP-126. The RM-511 drawing and compound-22 structure require additional primary-source inspection. Linker-only records should remain out of the cyclic-peptide measurement population.

These examples show why improving residue tokenization alone cannot establish the registered structure-quality threshold. Recovery needs separate evidence for entity identity, complete modified structure, closure chemistry and assay linkage. A versioned review sidecar can record these supported textual corrections now, while graph eligibility remains false until qualified. No aggregate recovery yield or FTO conclusion follows from this targeted review.

## Published-source follow-up and retained-text integrity

On 29 October 2026, separate online reads corroborated the selected textual fields against the published patents hosted by Google Patents. SHA-256 was also recomputed over each of the five retained patent `text` strings encoded as UTF-8, following the original acquisition algorithm; all matched their recorded hashes. This verifies retained-text integrity, not equivalence between entire current web pages and the archive. The linker-source hash is `4e6f2e6923613d8392ac4c7410496bba9069b1e6ffa87d2a2756da554dce3888`.

- **Ref Ex 2:** the online Table 1 independently confirms column separation and the three values. Its short header excerpt is “Intrinsic” / “activity”; these words belong to the percentage endpoint. The published PDF could not be fetched, so the merged doxycycline header remains unresolved. [Published source, Table 1](https://patents.google.com/patent/US20100311648A1/en).
- **GIP-057 and GIP-126:** the published EPO PDF text places Examples 2 and 3 at printed page 326, paragraphs **[0506] and [0507]**. Both specify “with dibromoxylene as cyclization reagent.” This confirms the source-level closure route. PDF text renders the micromole symbol ambiguously, whereas HTML retains it; no synthesis-scale correction is authorized from that extraction. Screenshot retrieval failed, so this is text corroboration rather than visual drawing validation. [Published PDF, page 326](https://patentimages.storage.googleapis.com/2c/73/76/9cabcd3913f82a/EP4170347A1.pdf#page=326).
- **RM-511:** the online Formula II discussion corroborates the alias with “also known as RM-511.” The specific structure drawing remains unreviewed. [Published source, Formula II discussion](https://patents.google.com/patent/WO2024108198A2/en).
- **Compound 22:** online Table 8 confirms its 3 nM HTRF binding-inhibition row. This does not resolve the missing chemical graph. [Published source, Table 8](https://patents.google.com/patent/WO2014151634A1/en).
- **Val-Ala:** online linker-L context corroborates that this is a cleavable-linker example, not evidence for a standalone cyclic-peptide measurement. [Published source, linker-L discussion](https://patents.google.com/patent/US20240376154A1/en).

The candidate packet records these observed locations and verified archive hashes while retaining `AI_ASSISTED_CANDIDATE` and `method_prior_eligible=false`. No scientific computation, graph reconstruction or test execution was performed.

## 30 October: component and drawing qualification follow-up

The dated review candidates now include three source-backed follow-ups while preserving the original extraction and 29 October fields:

- `20261030_PATENT_RM511_DRAWING_QUALIFICATION.md`: exact compound-linked image inspected, with explicit cysteine disulfide closure and hydantoin-containing unit. The complete graph and stereochemistry are not yet validated.
- `20261030_PATENT_REFEX2_QUALIFICATION.md`: Dab side-chain figure inspected; closure-class context and separate functional/binding assay conditions recovered. Exact Ref Ex 2 correspondence and Table 1 visual header scope remain incomplete.
- `20261030_PATENT_GIP_COMPONENT_QUALIFICATION.md`: Ttds/3MeBn definitions and explicit linker/branch attachment conventions recovered; exact GIP-057/126 product drawings subsequently retrieved and visually inspected. These definitions must be interpreted as installed components rather than blindly copying installation-reagent drawings.

No record was promoted to learned conditioning or a numerical prior. These source repairs narrow graph-recovery tasks without changing the original K4 conversion denominator or claiming a higher validated structure yield. The current generation constraint also requires 2–6 N-methyl amides; source-recovered structures need separate parent-eligibility checks. A chemically verified contextual example need not be a valid parent for this fixed experiment, and the constraint must not be relaxed simply to admit an example.

## Implementation clarification: output constraints versus prefix parents

Subsequent inspection of `hybrid/model.py::sample` and `hybrid/run_stage1.py::FrozenParentProtocol` establishes that C constrains completed proposals. The frozen parent pool enforces source/task metadata and exclusions, but does not require the full parent molecule to pass C. Therefore an out-of-C source molecule is not automatically prohibited as a prefix parent by the code. Earlier references here to C-valid generation parents describe a possible narrower study design, not an implemented universal eligibility rule. Such a restriction must be explicitly prespecified if adopted. Any parent still needs an exact reviewed mapping, evidence applicability and split clearance; whether its retained prefix can yield valid completions remains an empirical question. None of these candidates is promoted by this clarification.
