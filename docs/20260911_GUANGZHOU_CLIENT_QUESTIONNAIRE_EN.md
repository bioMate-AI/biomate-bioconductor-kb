# AI Drug-Discovery Platform — Molecular Generation and Optimisation

## Technical Clarification Questions

**To:** Guangzhou Medical ** Company · project contact Luo **  
**Canonical Chinese source:** `/Users/kky/biomate/docs/20260909_AI_DRUG_MOLECULE_GEN_QUESTIONS_ZH.md`  
**Translation status:** faithful English reference; the Chinese original remains authoritative.

## Introduction

We understand the core request to be an AI-driven drug-discovery platform covering molecular generation, activity prediction, property optimisation, and an automated closed loop. The goal is a reusable platform rather than a one-off delivery for one target.

The following questions align the platform boundary, data and integration approach, iteration loop, and acceptance criteria. Target-specific activity cut-offs and property ranges are configurable runtime inputs, not part of this scoping questionnaire.

## Platform scope — please identify the required layers

| Layer | Scope |
|---|---|
| 1. Knowledge | Literature and patent/FTO search; known activity and SAR evidence for design |
| 2. Reasoning | Hypothesis generation; target and chemotype rationale |
| 3. Generation | AI molecule generation, including de novo design and scaffold hopping — explicit core requirement |
| 4. Optimisation | Activity prediction; docking, molecular dynamics and binding free energy; ADMET/safety; multi-objective optimisation and closed loop — explicit core requirement |

## 1. Platform capability scope

1. Which chemical modalities must the platform cover: small molecules, peptides/macrocycles, PROTACs, molecular glues, or a combination?
2. Which target classes are in scope? Must the platform support both structure-based design (experimental or predicted structures) and ligand/activity-data-based generation?
3. Must it support multi-target / polypharmacology design, balancing activity and selectivity across targets, or only single-target programs?
4. Is the platform for current named targets only, or must users be able to configure new targets independently in the future?

## 2. Data, integration, and intellectual property

5. Should activity/property prediction use general pretrained models directly, or be trained/fine-tuned on the company’s own experimental data? If the latter, what data scale, modalities, and formats are available?
6. Must the platform integrate bidirectionally with existing ELN, compound-library, internal database, or LIMS systems?
7. How should ownership and permitted use of generated compounds, models, workflows, and derived outputs be defined?

## 3. Optimisation and workflow capabilities

8. Should developability, affinity, and safety be presented as configurable multi-objective optimisation, with users setting runtime ranges and weights rather than fixed rules?
9. Which safety-evaluation categories must be standard platform capabilities—for example hERG/cardiotoxicity, hepatotoxicity, off-target profiles, or metabolic stability?
10. Must synthetic-feasibility scoring and structural novelty/freedom-to-operate screening be built-in dimensions, so candidates are synthesizable and have patentable space?

## 4. Wet-lab feedback and the DMTA loop

11. Does “automated closed loop” mean a purely computational loop (generate → predict → optimise → rank), or a wet-lab DMTA loop (design → make → test → analyse) where experimental results drive model iteration?
12. Who will perform synthesis and activity testing—the company’s laboratory or a nominated CRO? What approximate throughput and cycle time are expected per round?
13. In what format will each round’s experimental data be returned? Must the platform automatically ingest results and retrain/update activity and property models, or is offline manual retraining sufficient?
14. With limited wet-lab capacity, how should the next batch be selected: exploitation (best predicted candidates), exploration (high uncertainty/information gain), or a combination? Does each round require human review/approval, or proceed automatically?
15. Must the platform handle partial, failed, or censored experimental results and retain end-to-end provenance from model version to proposed compounds to returned results?

## 5. Delivery, deployment, and acceptance

16. Is the deliverable a sustainable, self-configurable, maintainable platform with a user interface, or candidate-compound delivery by project/milestone? Which model does the RMB 70 million budget represent?
17. Will acceptance use benchmark targets or retrospective known-activity data to assess generation quality, prediction accuracy, and optimisation performance? How should platform-level acceptance criteria be defined?
18. Are private/on-premises deployment, data-residency controls, or domestic/secure software and hardware-stack requirements mandatory?
19. Who are the expected users—computational chemists, medicinal chemists, or R&D management—and what operating scale is expected (molecules per generation round and run frequency)?
20. Does 31 December 2026 denote an initial usable MVP or final platform delivery? What phased milestones are expected?

## Closing

These questions establish platform scope, data foundations, wet-lab iteration, and acceptance. They enable a proposal and milestone plan that genuinely fit the company’s goal and produce lead candidates suitable for subsequent preclinical research.
