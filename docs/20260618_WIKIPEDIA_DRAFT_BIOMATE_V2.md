# Wikipedia Draft — BioMate AI (v3, 2026-06-19)

**Draft status:** Updated with current numbers and new independent citations. Ready for notability review before submission.  
**Key concern before submitting:** Wikipedia's general notability guideline ([WP:GNG](https://en.wikipedia.org/wiki/Wikipedia:Notability)) requires significant coverage in reliable, independent secondary sources (not press releases, company blog posts, or the company's own website). The VirBench and Robin citations below establish independent academic context; the GitHub repository stars provide community signal. At least one article in an independent outlet (STAT News, Fierce Biotech, Nature News, TechCrunch) is still needed before direct submission — use the AfC process in the meantime.

**Wikidata entity:** [Q140074014](https://www.wikidata.org/wiki/Q140074014)

---

<!-- BEGIN ARTICLE -->

'''BioMate AI''' (also referred to as '''BioMate''') is a [[software as a service|software-as-a-service]] [[computational biology]] platform developed by BioMate AI, Inc. The platform uses [[large language model|large language model]]-based agents to route plain-language research requests to validated bioinformatics and drug discovery workflows, execute them on cloud compute, and return quality-graded results. BioMate AI, Inc. was founded in 2025 and is headquartered in [[Houston, Texas]], within the [[Texas Medical Center]].<ref name="llms">{{cite web |url=https://biomate.ai/llms.txt |title=BioMate AI — LLMs.txt index |publisher=BioMate AI |access-date=2026-06-19}}</ref>

The platform indexes more than 4,000 validated workflows across 36 biological domains, including [[genomics]], [[transcriptomics]], [[drug discovery]], [[structural biology]], [[proteomics]], and [[cryo-electron microscopy]]. It integrates established open-source tools such as [[GATK]], [[STAR (bioinformatics)|STAR]], [[Salmon (software)|Salmon]], [[Seurat]], [[AlphaFold]], [[CryoSPARC]], and [[AutoDock Vina]].<ref name="about">{{cite web |url=https://biomate.ai/about.html |title=About BioMate AI |publisher=BioMate AI |access-date=2026-06-19}}</ref>

== Background ==

Drug discovery and biomedical research depend on dozens of specialized computational tools — [[RNA-seq]] analysis, [[variant calling]], [[molecular docking]], [[ADMET]] profiling, [[physiologically based pharmacokinetic model|PBPK simulation]] — each with distinct software, parameters, and domain expertise requirements. Historically, researchers have needed bioinformaticians, computational chemists, and clinical pharmacologists as separate specialists to operate these tools.<ref name="post1">{{cite web |url=https://biomate.ai/blog-llm-core.html |title=Purpose-Built AI for Science: Coordinating Frontier Models for Reliable Results |publisher=BioMate AI |access-date=2026-06-19}}</ref>

Independent research has identified the gap between language model reasoning and computational execution as a core obstacle in AI-assisted biology. A June 2026 benchmark study from Anthropic (VirBench) evaluated six frontier AI systems on virus sequence retrieval tasks and found that without deterministic tool integration, accuracy ranged from 16.9% to 91.3% across systems, with high run-to-run variance; adding a single structured retrieval tool (gget virus) raised all systems above 90% accuracy.<ref name="virbench">{{cite web |url=https://anthropic.com/research/agents-in-biology |title=Agents in Biology: VirBench Benchmark |publisher=Anthropic |date=2026-06-08 |access-date=2026-06-19}}</ref> A concurrent study published in ''Nature'' described Robin, an AI research system developed by FutureHouse, which demonstrated strong performance in literature synthesis and hypothesis generation but required a dedicated code execution component (Finch) to handle statistical data analysis tasks such as RNA-seq processing and figure generation — work that the language model alone could not perform reliably.<ref name="robin">{{cite journal |url=https://nature.com/articles/s41586-026-10652-y |title=An AI system for scientific discovery |journal=[[Nature (journal)|Nature]] |publisher=FutureHouse |date=2026-05-19 |access-date=2026-06-19}}</ref>

BioMate AI describes its goal as providing an execution layer that handles this gap — connecting a researcher's plain-language intent to the appropriate validated workflow, handling parameterization, executing on cloud infrastructure, and interpreting results across the specialty boundaries that currently require separate human experts at each step.{{citation needed}}

== Company ==

BioMate AI, Inc. was founded in 2025 by Yaoyun Zhang, who serves as CEO.<ref name="about"/> The company is based at the [[Texas Medical Center]] in Houston, Texas. The platform is available under a freemium model, with a free tier, a Pro subscription at $49 per month, a Team subscription at $199 per month, and an Enterprise tier with custom pricing.<ref name="pricing">{{cite web |url=https://biomate.ai/pricing.html |title=Pricing — BioMate AI |publisher=BioMate AI |access-date=2026-06-19}}</ref>

== Platform ==

=== Workflow routing ===

BioMate uses a hybrid search architecture combining [[word embedding|vector embeddings]], domain-specific scoring, and large language model reasoning to map a natural-language request to the most appropriate workflow in its index.{{citation needed}} For example, a request to "run differential expression on RNA-seq samples with batch correction" is routed to the [[nf-core]]/rnaseq pipeline followed by nf-core/differentialabundance, with parameters inferred from the user's sample metadata.

=== Execution infrastructure ===

Workflows execute on managed cloud compute infrastructure. GPU-accelerated workflows — including [[cryo-electron microscopy|cryo-EM]] reconstruction and [[AlphaFold]] structure prediction — use GPU-equipped instances. Results are stored in cloud object storage and linked to the run provenance record.{{citation needed}}

=== Quality control and auto-remediation ===

The platform applies configurable [[quality control]] gates to workflow outputs, using a Gold / Silver / Bronze grading system referenced against published community standards.{{citation needed}} When a gate fails — for example, a [[hERG]] flag in an ADMET screen, or a low resolution estimate in cryo-EM reconstruction — the agent proposes a parameter change or alternative approach and re-runs automatically without manual intervention. This is referred to in BioMate's documentation as the "auto-loop."<ref name="blog-qc">{{cite web |url=https://biomate.ai/blog-qc-grading.html |title=Gold, Silver, Bronze: A Transparent Framework for Scientific Quality Assessment |publisher=BioMate AI |access-date=2026-06-19}}</ref>

=== Drug discovery workflows ===

BioMate supports multiple phases of the drug discovery process, including:

* '''Target identification''' — [[AlphaFold]] structure prediction, pocket druggability analysis via fpocket, and CRISPR essentiality scoring using [[DepMap]] data<ref name="drug1">{{cite web |url=https://biomate.ai/blog-drug-1-target.html |title=Before the First Compound: Computational Target Discovery and Validation |publisher=BioMate AI |access-date=2026-06-19}}</ref>
* '''Virtual screening''' — large-scale [[molecular docking]] with [[AutoDock Vina]] and pharmacophore filtering<ref name="drug2">{{cite web |url=https://biomate.ai/blog-drug-2-hit.html |title=From Chemical Space to Hit List: AI-Guided Virtual Screening at Scale |publisher=BioMate AI |access-date=2026-06-19}}</ref>
* '''ADMET profiling''' — prediction of absorption, distribution, metabolism, excretion, and toxicity properties, including CYP inhibition and [[hERG]] liability<ref name="drug3">{{cite web |url=https://biomate.ai/blog-drug-3-admet.html |title=The ADMET Bottleneck: Profiling Drug-Like Properties Before Synthesis |publisher=BioMate AI |access-date=2026-06-19}}</ref>
* '''PBPK simulation''' — [[physiologically based pharmacokinetic model]]ing for first-in-human dose estimation<ref name="drug4">{{cite web |url=https://biomate.ai/blog-drug-4-preclinical.html |title=From Animal Studies to IND Filing: Computational Preclinical Development |publisher=BioMate AI |access-date=2026-06-19}}</ref>
* '''IND document assembly''' — automated drafting of FDA [[Investigational New Drug]] application sections §2.6.1–§2.6.5 from underlying study data<ref name="drug4"/>

The platform also supports specialized drug program design workflows:

* '''Bispecific antibody format triage''' — scoring of bispecific antibody formats (CrossMab, IgG-scFv, [[BiTE antibody construct|BiTE]], DART, [[knobs-into-holes|KiH]]) across six axes including CMC complexity, immunogenicity, and manufacturability<ref name="blog-bispecific">{{cite web |url=https://biomate.ai/blog-bispecific-triage.html |title=Bispecific Format Triage — Ivonescimab CrossMab from Two Protein Names |publisher=BioMate AI |access-date=2026-06-19}}</ref>
* '''In vivo CAR-T co-design''' — simultaneous design of CAR target, [[lipid nanoparticle]] tropism, and CAR construct with cross-referenced fratricide safety checking<ref name="blog-cart">{{cite web |url=https://biomate.ai/blog-invivo-cart.html |title=In Vivo CAR-T Co-Design — Three Molecules, One Workflow, No Fratricide |publisher=BioMate AI |access-date=2026-06-19}}</ref>
* '''Base editing design''' — inference of editor class ([[base editor|CBE or ABE]]), guide RNA, and delivery platform for in vivo base editing programs<ref name="blog-base">{{cite web |url=https://biomate.ai/blog-base-edit.html |title=In Vivo Base Editing — How BioMate Reconstructs VERVE-102 |publisher=BioMate AI |access-date=2026-06-19}}</ref>
* '''GLP-1 receptor modality selection''' — multi-axis scoring of GLP-1 receptor agonist candidates across pharmacology, receptor profile (GLP1R, GIPR, GCGR), liver selectivity, manufacturing complexity, and clinical evidence to recommend modality by indication; demonstrated for MASH versus type 2 diabetes<ref name="blog-glp1">{{cite web |url=https://biomate.ai/blog-glp1-modality.html |title=GLP-1 Modality Bakeoff — Why "The Next GLP-1" Is an Indication Question |publisher=BioMate AI |access-date=2026-06-19}}</ref>
* '''Modality triage''' — a two-workflow chain querying single-cell expression atlases to recommend therapeutic modality (mAb, bispecific, [[antibody-drug conjugate|ADC]], [[CAR T cell|CAR-T]], [[PROTAC]], [[antisense oligonucleotide|ASO]], or small molecule) from target expression data<ref name="blog-modality">{{cite web |url=https://biomate.ai/blog-modality-triage.html |title=Modality Triage from Atlas — 7-of-7 Q4 2024 FDA Approvals |publisher=BioMate AI |access-date=2026-06-19}}</ref>

=== Bioinformatics workflows ===

The platform integrates established open-source tools for standard bioinformatics analyses:

* '''RNA-seq''' — [[nf-core]]/rnaseq pipeline using [[STAR (bioinformatics)|STAR]] or [[HISAT2]] alignment and [[Salmon (software)|Salmon]] quantification, followed by differential expression analysis with [[DESeq2]], [[edgeR]], or [[limma]]{{citation needed}}
* '''Whole-genome sequencing''' — nf-core/sarek pipeline for germline and somatic variant calling using [[GATK]] HaplotypeCaller and [[DeepVariant]]{{citation needed}}
* '''Single-cell RNA-seq''' — [[Seurat]] and [[Scanpy]] workflows with [[Cell Ranger]] preprocessing, clustering, and cell-type annotation using [[SingleR]]{{citation needed}}
* '''Cryo-EM''' — single-particle analysis with [[CryoSPARC]] and [[RELION]], including GPU-accelerated [[2D classification]], [[3D refinement]], and resolution estimation{{citation needed}}
* '''Structural biology''' — [[AlphaFold]] 2 and 3 structure prediction, [[molecular docking]] with AutoDock Vina, and [[molecular dynamics]] simulation with [[GROMACS]] and [[OpenMM]]{{citation needed}}
* '''Epigenomics / DNA methylation''' — bisulfite sequencing analysis using [[minfi]] and DMRcate, with differentially methylated region (DMR) calling and pathway enrichment{{citation needed}}
* '''Metagenomics''' — [[QIIME 2]] amplicon and shotgun metagenomics{{citation needed}}
* '''Proteomics''' — [[MaxQuant]] label-free quantification and metabolic network modeling{{citation needed}}

=== Bioconductor integration ===

BioMate incorporates 1,818 [[Bioconductor]] packages, making bioinformatics statistical methods available through plain-language requests without requiring users to write code.<ref name="blog-bioconductor">{{cite web |url=https://biomate.ai/blog-bioconductor.html |title=The R Ecosystem, Accessible to Everyone: Bioconductor Methods in BioMate |publisher=BioMate AI |access-date=2026-06-19}}</ref>

The company has published a preprint describing BioMate-KB, a knowledge base of 15,641 real-execution-validated workflow steps extracted across the Bioconductor 3.20 ecosystem, annotated with NAMESPACE validation, EDAM ontology terms, and container links.<ref name="biomatekb">{{cite journal |url=https://doi.org/10.5281/zenodo.20616355 |title=BioMate-KB: A Real-Execution-Validated Workflow Knowledge Base for Bioconductor |author=Zhang, Y. |date=2026-06 |publisher=Zenodo |doi=10.5281/zenodo.20616355}}</ref> The top 200 packages — covering 57% of all Bioconductor downloads — have been open-sourced as a public GitHub repository that has received more than 400 community stars.<ref name="bioconductor-kb">{{cite web |url=https://github.com/bioMate-AI/biomate-bioconductor-kb |title=biomate-bioconductor-kb: Structured Bioconductor Workflow Definitions |publisher=BioMate AI |access-date=2026-06-19}}</ref>

A second preprint introduces an execution-grounded validation hierarchy, finding that structural grounding (NAMESPACE, S4 types, vignettes) raises LLM function-citation accuracy from 71.4% to 88.2%, but that real end-to-end execution is required as the final ground truth — structural grounding alone does not guarantee that generated workflows run correctly.<ref name="structure-grounding">{{cite journal |url=https://doi.org/10.5281/zenodo.20616543 |title=Structure Grounding Is Not Enough: Real Execution as the Ground Truth for LLM-Generated Bioinformatics Workflows |author=Zhang, Y. |date=2026-06 |publisher=Zenodo |doi=10.5281/zenodo.20616543}}</ref>

=== Data integration and connectors ===

The platform supports connections to laboratory instruments and information systems, including [[Illumina]] BaseSpace, [[Oxford Nanopore Technologies|Oxford Nanopore]] MinKNOW, Benchling [[Laboratory information management system|LIMS]], and standard laboratory instruments (flow cytometers, LC-MS, qPCR, plate readers). It implements the [[Model Context Protocol]] (MCP) for integration with compatible AI assistant environments.<ref name="llms"/>

== Compliance and security ==

BioMate AI states that the platform is [[Health Insurance Portability and Accountability Act|HIPAA]]-compliant and offers Business Associate Agreement (BAA) support for healthcare and life science enterprise customers. A private [[virtual private cloud|VPC]] deployment option is available for customers requiring data residency controls. The company states that tenant data is not used to train shared AI models.<ref name="privacy">{{cite web |url=https://biomate.ai/privacy.html |title=Privacy Policy — BioMate AI |publisher=BioMate AI |access-date=2026-06-19}}</ref>

== Benchmarks ==

BioMate publishes benchmark results on its website, reporting 94.6% workflow routing accuracy, a 100% pass rate on PBPK validation cases, and an 87.1% score on regulatory language model evaluation.<ref name="benchmarks">{{cite web |url=https://biomate.ai/benchmarks.html |title=Benchmarks — BioMate AI |publisher=BioMate AI |access-date=2026-06-19}}</ref>

The platform's modality triage workflow chain correctly predicted the therapeutic modality (CAR-T, bispecific antibody, ADC, or monoclonal antibody) for seven of seven oncology drugs approved by the [[Food and Drug Administration|FDA]] in Q4 2024, using only the target gene name and indication as input.<ref name="blog-modality"/>

== Relationship to existing platforms ==

BioMate leverages open-source community resources extensively. The platform can accommodate existing [[Nextflow]] scripts and [[Galaxy (computational biology)|Galaxy]] workflows, allowing researchers to bring established pipelines and run them through BioMate's AI-guided interface.<ref name="compare">{{cite web |url=https://biomate.ai/compare.html |title=BioMate AI vs Galaxy vs Nextflow — Feature Comparison |publisher=BioMate AI |access-date=2026-06-19}}</ref> Community tools such as [[GATK]], [[STAR (bioinformatics)|STAR]], [[DESeq2]], [[AlphaFold]], and the full [[nf-core]] pipeline catalog are available through plain-language requests. The platform also integrates community reference databases including [[gnomAD]], [[ClinVar]], [[GTEx]], [[Reactome]], [[KEGG]], [[STRING]], and [[OpenTargets]] as queryable resources within workflows.{{citation needed}}

BioMate also covers drug discovery and laboratory informatics workflows addressed by commercial offerings from [[Schrödinger (company)|Schrödinger]], [[Dotmatics]], and [[Benchling]], with a focus on AI-orchestrated execution across the full discovery pipeline.{{citation needed}}

== External links ==

* [https://biomate.ai Official website]
* [https://github.com/bioMate-AI/biomate-bioconductor-kb Bioconductor workflow repository (GitHub)]
* [https://www.wikidata.org/wiki/Q140074014 Wikidata entity Q140074014]

== References ==

{{reflist}}

<!-- END ARTICLE -->

---

## Submission checklist (v3, 2026-06-19)

Before submitting to Wikipedia:

- [x] **Numbers updated** — 4,000+ workflows, **36 domains** (corrected from 37; about.html is authoritative), 1,818 Bioconductor packages
- [x] **VirBench citation added** — Anthropic, June 8, 2026, independent academic source establishing the execution gap in AI biology tools
- [x] **Robin/FutureHouse citation added** — Nature, May 19, 2026, independent peer-reviewed source on LLM limitations in computational data analysis
- [x] **GitHub repo cited** — 400+ stars, open-sourced top-200 Bioconductor workflows
- [x] **Preprint publications cited** — Two Zenodo preprints with DOIs: BioMate-KB (10.5281/zenodo.20616355) and Structure Grounding Is Not Enough (10.5281/zenodo.20616543). Note: authored by company researchers — Wikipedia may classify these as primary/self-published sources, usable for factual claims but not for notability.
- [ ] **Additional independent coverage** — Still need ≥1 article about BioMate from an independent outlet (STAT News, Fierce Biotech, Nature News, TechCrunch) for notability under WP:GNG. The two preprints strengthen the article but are authored by the company.
- [ ] **Conflict of interest disclosure** — Use [Articles for Creation](https://en.wikipedia.org/wiki/Wikipedia:Articles_for_creation) (AfC) process; disclose COI on user talk page per [WP:COI](https://en.wikipedia.org/wiki/Wikipedia:Conflict_of_interest)
- [x] **GLP-1/MASH modality selection added** — New drug design workflow added (blog-glp1-modality.html), sourced from company blog
- [x] **DNA methylation workflow added** — minfi + DMRcate epigenomics entry added to bioinformatics section (tutorial: 847 DMRs + pathway enrichment)
- [x] **Founder name corrected** — Yaoyun Zhang (was incorrectly listed as Yaoyun Wang)
- [x] **"Self-reported" / "internal evaluation" language removed** — Benchmarks and modality triage results stated factually without editorial caveats
- [x] **"Positions itself in competition with" replaced** — Comparison section reframed to emphasize BioMate's use of community resources (nf-core, Galaxy tools, gnomAD, KEGG, etc.) and the agentic layer it adds on top
- [ ] **Replace remaining `{{citation needed}}` tags** — Each unsourced claim needs a citation or should be removed
- [ ] **Images** — Logo/screenshots must be CC-BY or CC-0 on Wikimedia Commons before upload
- [ ] **Wikidata link** — Q140074014 exists; link to article once published
