# Ref Ex 2: closure, stereochemistry and assay qualification — 30 October 2026

Record: `db28a398d88433ee`; patent `US20100311648A1`; extraction passage `US-20100311648-A1:29`. This supplements `20261029_PATENT_SOURCE_RECOVERY_REVIEW.md`; original extraction records remain unchanged; dated follow-up fields are recorded separately in the review-candidate packet.

## New source findings

| Field | Supporting location | Qualification |
|---|---|---|
| Closure | Paragraph **[0211]** | Explicit Glu-side-chain/Orn-side-chain lactam chemistry supports the bracketed motif. Applying it specifically to Ref Ex 2 remains a source-context inference; no Ref Ex 2 atom drawing was inspected. |
| Stereochemistry | **[0046]**, definitions | D-prefix notation explicitly identifies D-Phe. Unprefixed residues follow the stated conventional notation; this is not independent atom-level stereochemical validation. |
| Dab identity | Definitions table, image **C00009** | Direct image inspection shows the two-carbon amino side chain, consistent with 2,4-diaminobutyric acid. It is a side-chain schematic with no alpha-carbon stereochemical marking; it does not settle Dab absolute stereochemistry. |
| Functional conditions | **[0291]–[0292]**, section **7.3**; Table 4 | Doxycycline 0.1 ng/mL induces low-density hMC4-R; 10 ng/mL induces high density. These are functional-system conditions. |
| Binding endpoint | Section **7.1** | Ki comes from a separate competitive radioligand-binding procedure. Do not attach the doxycycline condition to Ki by default. |
| Table 1 header | HTML **TABLE-US-00002** | Doxycycline appears in a separate two-column table above five-column endpoints. HTML therefore does not reliably establish its original visual span. Low-density assignment to EC50/activity is supported contextually, not visually verified. |

[Published patent and named sections](https://patents.google.com/patent/US20100311648A1/en).

## Access and disposition

The directly fetched source HTML is `/tmp/refex2_primary.html`. Paragraph numbers above were read from its explicit `para-num` markers, not inferred from extraction-window IDs. Published PDF retrieval and the Dab figure initially returned cache failures through the web reader. A subsequent ordinary HTTP retrieval of the actual public figure URL succeeded, and `/tmp/refex2_dab_C00009.png` was visually inspected. The image confirms side-chain connectivity but contains no stereochemical wedge/dash or complete amino-acid graph. [Original Dab definition figure](https://patentimages.storage.googleapis.com/68/b1/b1/d08462ccaabe90/US20100311648A1-20101209-C00009.png).

This review adds closure-class, Dab side-chain and assay-system evidence while preserving uncertainty about the exact molecular graph and original table layout. Required next qualification: inspect the published Ref Ex 2 structure/synthesis or an explicit source cross-reference; establish absolute stereochemistry; verify the Table 1 header visually. No standalone synthesis of Ref Ex 2 was established during this inspection. Examples using substituted phenylalanine or other residues cannot silently stand in for it.

Status remains `AI_ASSISTED_CANDIDATE`, `method_prior_eligible=false`, `graph_qualified=false`. No chemistry, descriptor calculations, local tests, paid jobs or original-record edits were performed.

Provenance hashes: downloaded HTML SHA-256 `09ef79f5181acd3ddc80197b1223dc4d0824f3901b30f6d8de8adc5c91c975dc`; Dab figure SHA-256 `5ca630864b2fa2e803636078c3b487ab1f75ee5840764d86f8a8a971cbbbb301`. These identify the inspection copies, separately from the retained corpus-text hash.
