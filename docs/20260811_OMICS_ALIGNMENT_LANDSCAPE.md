# What platforms do on multi-omics / cross-study ALIGNMENT — landscape + white space

Date: 2026-08-11. Verified competitive scan (two cross-validated passes; DOIs checked, no
fabrication). Companion to the multi-omics novelty/battery docs. Alignment = 4 layers:
identity, feature, distribution/batch, manifold/geometry.

## Who does what (verified)

| Layer | Leaders | Maturity |
|---|---|---|
| Identity (anchor cells/samples; diagonal) | Seurat CCA/RPCA anchors (Stuart 2019), fastMNN (Haghverdi 2018), OT: SCOT/Pamona/uniPort (2022) | academic; baked into ecosystems |
| Feature (ID map, liftover, cross-omics bridge) | biomaRt, UCSC liftOver; GLUE reg-graph (2022), StabMap disjoint-feature (2024), SATURN macrogenes (2024) | plumbing solved; cross-omics bridging = live frontier |
| Distribution/batch (the confounded core) | Harmony (2019), scVI/scANVI (2018–21), ComBat/SVA, limma, Scanorama, LIGER | **fully commoditized** — every commercial platform wraps these |
| Manifold/geometry (latent align, ref-map, universal embed) | Seurat WNN, totalVI/MultiVI, scArches/Symphony/Azimuth (2021); foundation models scGPT/Geneformer/UCE/SATURN/scFoundation (2023–24) | academic + atlas apps; FM wave contested |
| Bulk cross-study harmonization | recount3, ARCHS4, refine.bio, GDC, UCSC Xena, cBioPortal | uniform reprocessing; **deliberately leave batch correction to the user** |
| Alignment-quality QC (over-correction) | scIB/scib-metrics (Luecken 2022), kBET (2019), LISI/iLISI/cLISI (2019), RBET (2025) | **academic code only — never productized** |

## The two blunt takeaways

1. **Commercial/cloud platforms ship NO proprietary alignment algorithm.** Seqera/Tower,
   DNAnexus, Latch, Terra, 10x Loupe, Partek, BioTuring/BBrowserX, Qlucore, and the
   LLM-agent tools (OmicVerse, PromptBio) all wrap the same open-source math
   (Harmony/scVI/Seurat/Scanorama/fastMNN/ComBat). Their proprietary value is
   convenience, curation, or annotation — not alignment. ⇒ building/wrapping an aligner =
   commodity against a saturated field of top labs.

2. **The one unclaimed layer is alignment TRUSTWORTHINESS.** No platform we could verify
   productizes *"did my integration remove batch, or erase real biology?"* as a
   user-facing verdict. The over-correction signal is well-established academically
   (iLISI↑ good vs cLISI↑ = distinct cell states merged = biology destroyed; scIB's
   batch-vs-bio-conservation split) and there's a biology-erasure literature
   (bioRxiv 2021.11.15.468733; RBET 2025 exists *because* "tools lack over-correction
   estimation"). But it lives only as scripts a user must run themselves. This is a
   PRODUCTIZATION gap, not an unsolved-science gap — the metrics exist and are validated.

## Why this fits BioMate specifically

BioMate's actual strength is closed-loop QC (auto-loop gates, remediation). An
"alignment-trustworthiness" pass — run the integration, compute the batch-vs-bio
tradeoff, return an interpreted **trusted / over-corrected / under-corrected** verdict +
which populations got smeared + a remediation — is a QC gate, not a new integrator. It
plays to the moat instead of competing head-to-head with Satija/Theis on the aligner.

## Honesty caveat (do NOT over-claim)

The "no platform productizes it" is absence-of-evidence for tools with unverifiable
backends (PromptBio, BioTuring/Latch specifics were flagged UNVERIFIED). Before any public
"first/only" claim, verify those directly. Frame as "not offered as a named feature
anywhere we could confirm," not "nobody does it." [[feedback_overclaiming_conclusions]]
