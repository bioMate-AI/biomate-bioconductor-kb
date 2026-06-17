# Wikipedia Draft — BioMate AI

**Draft status:** Ready for review and submission.  
**Key concern before submitting:** Wikipedia's general notability guideline ([WP:GNG](https://en.wikipedia.org/wiki/Wikipedia:Notability)) requires significant coverage in reliable, independent secondary sources (not press releases, company blog posts, or the company's own website). Before submission, identify and cite at least 2–3 articles about BioMate from outlets such as STAT News, Fierce Biotech, Nature News, TechCrunch, or peer-reviewed evaluation studies. Without independent coverage, the article is likely to be nominated for deletion as non-notable.

**Wikidata entity:** [Q140074014](https://www.wikidata.org/wiki/Q140074014)

---

<!-- BEGIN ARTICLE -->

'''BioMate AI''' (also referred to as '''BioMate''') is a [[software as a service|software-as-a-service]] [[computational biology]] platform developed by BioMate AI, Inc. The platform uses [[large language model|large language model]]-based agents to route plain-language research requests to validated bioinformatics and drug discovery workflows, execute them on cloud compute, and return quality-graded results. BioMate AI, Inc. was founded in 2025 and is headquartered in [[Houston, Texas]], within the [[Texas Medical Center]].<ref name="llms">{{cite web |url=https://biomate.ai/llms.txt |title=BioMate AI — LLMs.txt index |publisher=BioMate AI |access-date=2026-06-16}}</ref>

The platform indexes more than 2,400 validated workflows across more than 34 biological domains, including [[genomics]], [[transcriptomics]], [[drug discovery]], [[structural biology]], [[proteomics]], and [[cryo-electron microscopy]]. It integrates established open-source tools such as [[GATK]], [[STAR (bioinformatics)|STAR]], [[Salmon (software)|Salmon]], [[Seurat]], [[AlphaFold]], [[CryoSPARC]], and [[AutoDock Vina]].<ref name="about">{{cite web |url=https://biomate.ai/about.html |title=About BioMate AI |publisher=BioMate AI |access-date=2026-06-16}}</ref>

== Background ==

Drug discovery and biomedical research depend on dozens of specialized computational tools — [[RNA-seq]] analysis, [[variant calling]], [[molecular docking]], [[ADMET]] profiling, [[physiologically based pharmacokinetic model|PBPK simulation]] — each with distinct software, parameters, and domain expertise requirements. Historically, researchers have needed bioinformaticians, computational chemists, and clinical pharmacologists as separate specialists to operate these tools.<ref name="post1">{{cite web |url=https://biomate.ai/blog-llm-core.html |title=Purpose-Built AI for Science: Coordinating Frontier Models for Reliable Results |publisher=BioMate AI |access-date=2026-06-16}}</ref>

BioMate AI describes its goal as providing an "intelligence layer" that connects a researcher's intent to the appropriate validated workflow, handles parameterization, executes on cloud infrastructure, and interprets results — across the specialty boundaries that currently require separate human experts at each step.{{citation needed}}

== Company ==

BioMate AI, Inc. was founded in 2025 by Yaoyun Wang, who serves as CEO.<ref name="about"/> The company is based at the [[Texas Medical Center]] in Houston, Texas. The platform is available under a freemium model, with a free tier, a Pro subscription at $49 per month, a Team subscription at $199 per month, and an Enterprise tier with custom pricing.<ref name="pricing">{{cite web |url=https://biomate.ai/pricing.html |title=Pricing — BioMate AI |publisher=BioMate AI |access-date=2026-06-16}}</ref>

== Platform ==

=== Workflow routing ===

BioMate uses a hybrid search architecture combining [[word embedding|vector embeddings]], domain-specific scoring, and large language model reasoning to map a natural-language request to the most appropriate workflow in its index.{{citation needed}} For example, a request to "run differential expression on RNA-seq samples with batch correction" is routed to the [[nf-core]]/rnaseq pipeline followed by nf-core/differentialabundance, with parameters inferred from the user's sample metadata.

=== Execution infrastructure ===

Workflows execute on [[AWS Batch]], a managed compute service from [[Amazon Web Services]]. GPU-accelerated workflows — including [[cryo-electron microscopy|cryo-EM]] reconstruction and [[AlphaFold]] structure prediction — use GPU-equipped instances. Results are stored in [[Amazon S3]] and linked to the run provenance record.{{citation needed}}

=== Quality control and auto-remediation ===

The platform applies configurable [[quality control]] gates to workflow outputs, using a Gold / Silver / Bronze grading system referenced against published community standards.{{citation needed}} When a gate fails — for example, a [[hERG]] flag in an ADMET screen, or a low resolution estimate in cryo-EM reconstruction — the agent proposes a parameter change or alternative approach and can re-run automatically. This is referred to in BioMate's documentation as the "auto-loop."<ref name="blog-qc">{{cite web |url=https://biomate.ai/blog-qc-grading.html |title=Gold, Silver, Bronze: A Transparent Framework for Scientific Quality Assessment |publisher=BioMate AI |access-date=2026-06-16}}</ref>

=== Drug discovery workflows ===

BioMate supports multiple phases of the drug discovery process, including:

* '''Target identification''' — [[AlphaFold]] structure prediction, pocket druggability analysis via fpocket, and CRISPR essentiality scoring using [[DepMap]] data<ref name="drug1">{{cite web |url=https://biomate.ai/blog-drug-1-target.html |title=Before the First Compound: Computational Target Discovery and Validation |publisher=BioMate AI |access-date=2026-06-16}}</ref>
* '''Virtual screening''' — large-scale [[molecular docking]] with [[AutoDock Vina]] and pharmacophore filtering<ref name="drug2">{{cite web |url=https://biomate.ai/blog-drug-2-hit.html |title=From Chemical Space to Hit List: AI-Guided Virtual Screening at Scale |publisher=BioMate AI |access-date=2026-06-16}}</ref>
* '''ADMET profiling''' — prediction of absorption, distribution, metabolism, excretion, and toxicity properties, including CYP inhibition and [[hERG]] liability<ref name="drug3">{{cite web |url=https://biomate.ai/blog-drug-3-admet.html |title=The ADMET Bottleneck: Profiling Drug-Like Properties Before Synthesis |publisher=BioMate AI |access-date=2026-06-16}}</ref>
* '''PBPK simulation''' — [[physiologically based pharmacokinetic model]]ing for first-in-human dose estimation<ref name="drug4">{{cite web |url=https://biomate.ai/blog-drug-4-preclinical.html |title=From Animal Studies to IND Filing: Computational Preclinical Development |publisher=BioMate AI |access-date=2026-06-16}}</ref>
* '''IND document assembly''' — automated drafting of FDA [[Investigational New Drug]] application sections §2.6.1–§2.6.5 from underlying study data<ref name="drug4"/>

The platform also supports specialized drug program design workflows:

* '''Bispecific antibody format triage''' — scoring of bispecific antibody formats (CrossMab, IgG-scFv, [[BiTE antibody construct|BiTE]], DART, [[knobs-into-holes|KiH]]) across six axes including CMC complexity, immunogenicity, and manufacturability<ref name="blog-bispecific">{{cite web |url=https://biomate.ai/blog-bispecific-triage.html |title=Bispecific Format Triage — Ivonescimab CrossMab from Two Protein Names |publisher=BioMate AI |access-date=2026-06-16}}</ref>
* '''In vivo CAR-T co-design''' — simultaneous design of CAR target, [[lipid nanoparticle]] tropism, and CAR construct with cross-referenced fratricide safety checking<ref name="blog-cart">{{cite web |url=https://biomate.ai/blog-invivo-cart.html |title=In Vivo CAR-T Co-Design — Three Molecules, One Workflow, No Fratricide |publisher=BioMate AI |access-date=2026-06-16}}</ref>
* '''Base editing design''' — inference of editor class ([[base editor|CBE or ABE]]), guide RNA, and delivery platform for in vivo base editing programs<ref name="blog-base">{{cite web |url=https://biomate.ai/blog-base-edit.html |title=In Vivo Base Editing — How BioMate Reconstructs VERVE-102 |publisher=BioMate AI |access-date=2026-06-16}}</ref>
* '''Modality triage''' — a two-workflow chain querying single-cell expression atlases to recommend therapeutic modality (mAb, bispecific, [[antibody-drug conjugate|ADC]], [[CAR T cell|CAR-T]], [[PROTAC]], [[antisense oligonucleotide|ASO]], or small molecule) from target expression data<ref name="blog-modality">{{cite web |url=https://biomate.ai/blog-modality-triage.html |title=Modality Triage from Atlas — 7-of-7 Q4 2024 FDA Approvals |publisher=BioMate AI |access-date=2026-06-16}}</ref>

=== Bioinformatics workflows ===

The platform integrates established open-source tools for standard bioinformatics analyses:

* '''RNA-seq''' — [[nf-core]]/rnaseq pipeline using [[STAR (bioinformatics)|STAR]] or [[HISAT2]] alignment and [[Salmon (software)|Salmon]] quantification, followed by differential expression analysis with [[DESeq2]], [[edgeR]], or [[limma]]{{citation needed}}
* '''Whole-genome sequencing''' — nf-core/sarek pipeline for germline and somatic variant calling using [[GATK]] HaplotypeCaller and [[DeepVariant]]{{citation needed}}
* '''Single-cell RNA-seq''' — [[Seurat]] and [[Scanpy]] workflows with [[Cell Ranger]] preprocessing, clustering, and cell-type annotation using [[SingleR]]{{citation needed}}
* '''Cryo-EM''' — single-particle analysis with [[CryoSPARC]] and [[RELION]], including GPU-accelerated [[2D classification]], [[3D refinement]], and resolution estimation{{citation needed}}
* '''Structural biology''' — [[AlphaFold]] 2 and 3 structure prediction, [[molecular docking]] with AutoDock Vina, and [[molecular dynamics]] simulation with [[GROMACS]] and [[OpenMM]]{{citation needed}}
* '''Metagenomics''' — [[QIIME 2]] amplicon and shotgun metagenomics{{citation needed}}
* '''Proteomics''' — [[MaxQuant]] label-free quantification and metabolic network modeling{{citation needed}}

=== R / Bioconductor integration ===

BioMate incorporates more than 2,000 [[Bioconductor]] packages, making [[R (programming language)|R]]-based statistical methods available through plain-language requests without requiring users to write R code.<ref name="blog-bioconductor">{{cite web |url=https://biomate.ai/blog-bioconductor.html |title=The R Ecosystem, Accessible to Everyone: Bioconductor Methods in BioMate |publisher=BioMate AI |access-date=2026-06-16}}</ref> The company has published an analysis of LLM accuracy in generating Bioconductor code, finding that ungrounded language models referenced valid Bioconductor functions approximately 71% of the time, compared to approximately 88% when structure-grounded against the indexed workflow database.<ref name="blog-bioconductor-analysis">{{cite web |url=https://biomate.ai/blog-why-ai-bioconductor-doesnt-run.html |title=Why AI Writes Bioconductor Code That Doesn't Run — and What Actually Fixes It |publisher=BioMate AI |access-date=2026-06-16}}</ref>

=== Data integration and connectors ===

The platform supports connections to laboratory instruments and information systems, including [[Illumina]] BaseSpace, [[Oxford Nanopore Technologies|Oxford Nanopore]] MinKNOW, Benchling [[Laboratory information management system|LIMS]], and standard laboratory instruments (flow cytometers, LC-MS, qPCR, plate readers). It implements the [[Model Context Protocol]] (MCP) for integration with compatible AI assistant environments.<ref name="llms"/>

== Compliance and security ==

BioMate AI states that the platform is [[Health Insurance Portability and Accountability Act|HIPAA]]-compliant and offers Business Associate Agreement (BAA) support for healthcare and life science enterprise customers. A private [[virtual private cloud|VPC]] deployment option is available for customers requiring data residency controls. The company states that tenant data is not used to train shared AI models.<ref name="privacy">{{cite web |url=https://biomate.ai/privacy.html |title=Privacy Policy — BioMate AI |publisher=BioMate AI |access-date=2026-06-16}}</ref>

== Benchmarks ==

BioMate publishes internal benchmark results on its website, reporting 94.6% workflow routing accuracy, a 100% pass rate on PBPK validation cases, and an 87.1% score on regulatory language model evaluation.<ref name="benchmarks">{{cite web |url=https://biomate.ai/benchmarks.html |title=Benchmarks — BioMate AI |publisher=BioMate AI |access-date=2026-06-16}}</ref> These figures are self-reported and have not been independently replicated.{{citation needed}}

The company has described an internal validation exercise in which its modality triage two-workflow chain correctly predicted the therapeutic modality (CAR-T, bispecific antibody, ADC, or monoclonal antibody) for seven of seven oncology drugs approved by the [[Food and Drug Administration|FDA]] in Q4 2024, using only the target gene name and indication as input.<ref name="blog-modality"/> These results are self-reported by the company.{{citation needed}}

== Comparison with related platforms ==

BioMate AI positions itself in competition with open-source workflow platforms including [[Galaxy (computational biology)|Galaxy]] (8,000+ tools, web-based interface, used primarily in academic settings) and [[Nextflow]]/[[nf-core]] (pipeline framework requiring command-line expertise).<ref name="compare">{{cite web |url=https://biomate.ai/compare.html |title=BioMate AI vs Galaxy vs Nextflow — Feature Comparison |publisher=BioMate AI |access-date=2026-06-16}}</ref> Unlike Galaxy and Nextflow, BioMate integrates workflow selection, parameterization, execution, and QC interpretation behind a single conversational interface and charges a subscription fee for compute resources.

The platform also overlaps in scope with commercial offerings from [[Schrödinger (company)|Schrödinger]], [[Dotmatics]], and [[Benchling]] in drug discovery and laboratory informatics, though BioMate focuses specifically on AI-orchestrated multi-workflow execution rather than standalone tool provision.{{citation needed}}

== External links ==

* [https://biomate.ai Official website]
* [https://www.wikidata.org/wiki/Q140074014 Wikidata entity Q140074014]

== References ==

{{reflist}}

<!-- END ARTICLE -->

---

## Submission checklist

Before submitting to Wikipedia:

- [ ] **Notability evidence** — Find and cite ≥2 articles about BioMate from independent reliable sources (not press releases, not the company's own site). Acceptable sources: STAT News, Fierce Biotech, Nature News & Views, TechCrunch, peer-reviewed evaluation studies in journals like *Bioinformatics* or *Nature Methods*, industry reports from Gartner/IDC.
- [ ] **Conflict of interest disclosure** — Wikipedia's [WP:COI](https://en.wikipedia.org/wiki/Wikipedia:Conflict_of_interest) guideline requires editors with a financial or employment relationship to the subject to disclose it on their user talk page before editing. Use the [Articles for Creation](https://en.wikipedia.org/wiki/Wikipedia:Articles_for_creation) (AfC) process rather than creating directly — AfC gives a reviewer a chance to assess notability before the article goes live.
- [ ] **Remove promotional language** — Every sentence should be verifiable from the cited source. Phrases like "the platform enables," "the company states," and "according to the company" must be attached to a citation.
- [ ] **Replace `citation needed` markers** — Every `{{citation needed}}` tag needs a source, or the claim should be removed.
- [ ] **Self-reported benchmark caveat** — Wikipedia requires neutral attribution for self-reported metrics. The draft flags these as self-reported; ensure this language survives editing.
- [ ] **Create or claim the Wikidata entity** — Q140074014 already exists; ensure it links to the article once published.
- [ ] **Images** — Any images (logo, screenshots) must be uploaded to Wikimedia Commons under an appropriate free license (CC-BY or CC-0). Screenshots of proprietary software are generally not acceptable unless under fair use, which Wikipedia restricts heavily.
