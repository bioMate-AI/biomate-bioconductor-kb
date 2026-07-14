export interface ProjectTemplate {
  id: string
  name: string
  description: string
  category: string
  primaryDomain: string
  tags: string[]
  researchGoal: string
  suggestedWorkflows: string[]
  icon: string
}

export const PROJECT_TEMPLATES: ProjectTemplate[] = [
  {
    id: "rnaseq-deseq2",
    name: "RNA-seq Differential Expression",
    description: "Identify differentially expressed genes between conditions using DESeq2, with pathway enrichment.",
    category: "Bioinformatics",
    primaryDomain: "genomics",
    tags: ["rna-seq", "deseq2", "differential-expression"],
    researchGoal: "Analyze RNA-seq data to identify differentially expressed genes between conditions using DESeq2. Compare control vs treatment groups, generate volcano plots, perform pathway enrichment analysis (GO, KEGG), and identify key regulatory genes.",
    suggestedWorkflows: ["nf-core/rnaseq", "DESeq2", "pathway-enrichment"],
    icon: "🧬",
  },
  {
    id: "gwas-finemapping",
    name: "GWAS Fine-Mapping",
    description: "GWAS analysis and statistical fine-mapping to identify causal variants and credible sets.",
    category: "Bioinformatics",
    primaryDomain: "genomics",
    tags: ["gwas", "fine-mapping", "causal-variants"],
    researchGoal: "Perform genome-wide association study analysis and statistical fine-mapping to identify causal variants. Run LD clumping, compute credible sets, annotate variants with functional consequences, and prioritize candidate causal SNPs.",
    suggestedWorkflows: ["MAGMA", "GWAS-fine-mapping", "variant-annotation"],
    icon: "🔬",
  },
  {
    id: "scrnaseq-clustering",
    name: "Single-Cell RNA-seq Analysis",
    description: "QC, clustering, cell-type annotation, and marker gene identification for scRNA-seq data.",
    category: "Bioinformatics",
    primaryDomain: "single-cell",
    tags: ["scrna-seq", "clustering", "cell-types"],
    researchGoal: "Process and analyze single-cell RNA-seq data to identify cell populations and their gene expression signatures. Perform quality control, normalization, dimensionality reduction (UMAP/PCA), clustering, marker gene identification, and cell type annotation.",
    suggestedWorkflows: ["nf-core/scrnaseq", "Seurat", "scanpy"],
    icon: "🫧",
  },
  {
    id: "drug-admet",
    name: "Drug Discovery — ADMET Profiling",
    description: "Evaluate drug candidates for hERG, DILI, Ames, CYP450, BBB, and Lipinski Ro5.",
    category: "Drug Discovery",
    primaryDomain: "drug-discovery",
    tags: ["admet", "drug-discovery", "toxicity"],
    researchGoal: "Evaluate drug candidates for ADMET properties (Absorption, Distribution, Metabolism, Excretion, Toxicity). Predict hERG cardiotoxicity, DILI, Ames mutagenicity, CYP450 inhibition profiles, BBB permeability, and Lipinski Ro5 compliance.",
    suggestedWorkflows: ["ADMET-panel", "molecular-docking", "PBPK"],
    icon: "💊",
  },
  {
    id: "cryoem-spa",
    name: "Cryo-EM Single Particle Analysis",
    description: "Full SPA pipeline: motion correction, CTF, particle picking, 2D/3D classification, refinement.",
    category: "Structural Biology",
    primaryDomain: "structural-biology",
    tags: ["cryo-em", "spa", "structure-determination"],
    researchGoal: "Process cryo-EM micrographs through a full single-particle analysis pipeline to determine a 3D protein structure. Run motion correction, CTF estimation, particle picking, 2D/3D classification, refinement, and post-processing to achieve near-atomic resolution.",
    suggestedWorkflows: ["cryoSPARC", "RELION", "cryoem-spa"],
    icon: "🔭",
  },
  {
    id: "pbpk-modeling",
    name: "PBPK / PK-PD Modeling",
    description: "Allometric scaling, multi-species PK simulation, pediatric dose selection, Cmax/AUC/t½.",
    category: "Pharmacology",
    primaryDomain: "pharmacology",
    tags: ["pbpk", "pkpd", "allometric-scaling"],
    researchGoal: "Build and validate a PBPK model to predict drug pharmacokinetics and pharmacodynamics. Perform allometric scaling from animal to human, simulate oral and IV dosing scenarios, optimize pediatric dose selection, and generate PK parameter estimates (Cmax, AUC, t1/2).",
    suggestedWorkflows: ["PBPK-allometric", "BOIN-trial-simulation", "dose-finding"],
    icon: "📊",
  },
  {
    id: "metagenomics-16s",
    name: "Metagenomics / 16S Microbiome",
    description: "OTU/ASV clustering, taxonomic classification, alpha/beta diversity, differential abundance.",
    category: "Bioinformatics",
    primaryDomain: "metagenomics",
    tags: ["16s", "microbiome", "diversity"],
    researchGoal: "Analyze 16S rRNA amplicon sequencing data to characterize microbial community composition and diversity. Perform OTU/ASV clustering, taxonomic classification, alpha/beta diversity analysis, and identify differentially abundant taxa between sample groups.",
    suggestedWorkflows: ["nf-core/ampliseq", "QIIME2", "diversity-analysis"],
    icon: "🦠",
  },
  {
    id: "immunology-bulk",
    name: "Immunology & Autoimmune Research",
    description: "Immune cell profiling, dysregulated pathway identification, disease-associated signatures.",
    category: "Immunology",
    primaryDomain: "immunology",
    tags: ["immunology", "autoimmune", "immune-profiling"],
    researchGoal: "Investigate immune cell composition, activation states, and gene expression changes in autoimmune or inflammatory disease contexts. Analyze bulk RNA-seq or immune cell subset data, identify dysregulated pathways, and characterize disease-associated immune signatures.",
    suggestedWorkflows: ["DESeq2", "immune-deconvolution", "pathway-enrichment"],
    icon: "🛡️",
  },
]

export function getTemplateByTag(tags: string[]): ProjectTemplate | undefined {
  return PROJECT_TEMPLATES.find(t => tags.includes(t.id))
}
