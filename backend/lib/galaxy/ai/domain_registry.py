"""
BioMate Canonical Domain Registry
==================================
Single source of truth for all research domain definitions.

Every domain list, label, topic, keyword set, specialist prompt, and
Galaxy category mapping is defined here. All other modules must import
from this file rather than maintaining their own lists.

Canonical domain set (14 user-facing domains):
    genomics, transcriptomics, single_cell, epigenomics, proteomics,
    metabolomics, metagenomics, structural_biology, drug_discovery,
    cryo_em, systems_biology, synthetic_biology, bioimaging, lab_automation

Naming conventions enforced here:
  - Use underscore, never hyphen  (single_cell NOT single-cell)
  - Use drug_discovery, NOT pharmacology
  - All lowercase

Routing-only domains (appear in DB / workflows but are not user profile domains):
    immunology, cancer_biology, molecular_biology, biochemistry,
    genetics, microbiology, cell_biology, biophysics, bioengineering,
    glycoengineering, pathology, physiology, database, literature,
    variant_calling, multi_omics
"""

from typing import Dict, List, Set

# ---------------------------------------------------------------------------
# 1. Canonical domain list — user-facing profile domains
#    This is the authoritative ordered list.  All other files must use it.
# ---------------------------------------------------------------------------

CANONICAL_DOMAINS: List[str] = [
    "genomics",
    "transcriptomics",
    "single_cell",
    "epigenomics",
    "proteomics",
    "metabolomics",
    "metagenomics",
    "structural_biology",
    "drug_discovery",
    "cryo_em",
    "systems_biology",
    "synthetic_biology",
    "bioimaging",
    "lab_automation",
]

# Domains that exist in the DB / workflow directories but are NOT user profile domains.
# The domain router may match these; they do not appear in user domain preference UI.
ROUTING_ONLY_DOMAINS: List[str] = [
    "immunology",
    "cancer_biology",
    "molecular_biology",
    "biochemistry",
    "genetics",
    "microbiology",
    "cell_biology",
    "biophysics",
    "bioengineering",
    "glycoengineering",
    "pathology",
    "physiology",
    "database",
    "literature",
    "variant_calling",
    "multi_omics",
]

ALL_DOMAINS: List[str] = CANONICAL_DOMAINS + ROUTING_ONLY_DOMAINS

# ---------------------------------------------------------------------------
# 2. Display labels  (used by the user domain profile UI)
# ---------------------------------------------------------------------------

DOMAIN_LABELS: Dict[str, str] = {
    "genomics":          "Genomics",
    "transcriptomics":   "Transcriptomics",
    "single_cell":       "Single Cell",
    "epigenomics":       "Epigenomics",
    "proteomics":        "Proteomics",
    "metabolomics":      "Metabolomics",
    "metagenomics":      "Metagenomics",
    "structural_biology": "Structural Biology",
    "drug_discovery":    "Drug Discovery & Pharmacology",
    "cryo_em":           "Cryo-EM",
    "systems_biology":   "Systems Biology",
    "synthetic_biology": "Synthetic Biology",
    "bioimaging":        "Bioimaging",
    "lab_automation":    "Lab Automation",
}

# ---------------------------------------------------------------------------
# 3. Domain topics  (used for user profile expansion and topic matching)
# ---------------------------------------------------------------------------

DOMAIN_TOPICS: Dict[str, List[str]] = {
    "genomics": [
        "variant calling", "WGS", "WES", "copy number", "structural variants",
        "population genetics", "genome assembly", "de novo assembly",
    ],
    "transcriptomics": [
        "bulk RNA-seq", "spatial transcriptomics", "long-read RNA-seq",
        "ATAC-seq", "microarray", "differential expression",
    ],
    "single_cell": [
        "scRNA-seq", "scATAC-seq", "multiome", "cell typing", "trajectory analysis",
        "cell clustering", "Seurat", "Scanpy",
    ],
    "epigenomics": [
        "ChIP-seq", "ATAC-seq", "bisulfite-seq", "CUT&RUN", "Hi-C",
        "DNA methylation", "WGBS", "RRBS",
    ],
    "proteomics": [
        "DDA", "DIA", "phosphoproteomics", "protein-protein interaction",
        "structural proteomics", "mass spectrometry", "TMT",
    ],
    "metabolomics": [
        "LC-MS", "GC-MS", "NMR", "lipidomics", "metabolic flux",
        "untargeted metabolomics", "targeted metabolomics",
    ],
    "metagenomics": [
        "16S amplicon", "shotgun metagenomics", "metatranscriptomics",
        "binning/MAGs", "microbiome", "taxonomic profiling",
    ],
    "structural_biology": [
        "AlphaFold", "molecular docking", "MD simulation",
        "X-ray crystallography", "protein structure prediction",
    ],
    "drug_discovery": [
        "ADMET prediction", "lead optimization", "target identification",
        "virtual screening", "docking", "pharmacophore", "QSAR",
        "scaffold hopping", "retrosynthesis", "generative chemistry",
        "PK/PD modeling", "IVIVE", "dose-response", "NCA", "population PK",
        "clinical pharmacology", "drug combination", "FDA label",
        "drug repurposing", "radiotherapy dosimetry",
    ],
    "cryo_em": [
        "SPA", "cryo-ET", "subtomogram averaging", "helical reconstruction",
        "CryoSPARC", "RELION",
    ],
    "systems_biology": [
        "ODE modeling", "network analysis", "flux balance analysis",
        "gene regulatory networks", "pathway modeling",
    ],
    "synthetic_biology": [
        "genetic circuit design", "metabolic engineering", "CRISPR design",
        "gene synthesis", "plasmid design",
    ],
    "bioimaging": [
        "cell segmentation", "fluorescence microscopy", "spatial omics imaging",
        "flow cytometry", "confocal", "image analysis",
    ],
    "lab_automation": [
        "liquid handling", "plate reader", "OT-2", "PyLabRobot", "LIMS",
        "sample tracking", "robotic dispensing", "high-throughput screening",
    ],
}

# ---------------------------------------------------------------------------
# 4. Domain specialist prompts  (used by DomainSpecialistPool)
#    All 14 canonical domains covered.  "default" is the fallback.
# ---------------------------------------------------------------------------

DOMAIN_SPECIALIST_PROMPTS: Dict[str, str] = {
    "genomics": (
        "You are a genomics expert. Given the user's request and available tools, "
        "recommend the best tools for DNA/genome analysis including alignment, variant calling, "
        "and annotation. Consider: sequencing type (WGS/WES/targeted), organism, reference genome "
        "version, and data quality requirements."
    ),
    "transcriptomics": (
        "You are a transcriptomics expert. Given the user's request and available tools, "
        "recommend the best tools for RNA-seq analysis including alignment, quantification, "
        "and differential expression. Consider: library type (poly-A/total RNA), strandedness, "
        "organism, and statistical analysis needs (DESeq2 vs edgeR vs limma)."
    ),
    "single_cell": (
        "You are a single-cell genomics expert. Given the user's request and available tools, "
        "recommend the best tools for scRNA-seq analysis including QC, normalization, clustering, "
        "and cell type annotation. Consider: technology (10X Chromium/Smart-seq/Parse), "
        "integration with other samples, and whether trajectory or velocity analysis is needed."
    ),
    "epigenomics": (
        "You are an epigenomics expert. Given the user's request and available tools, "
        "recommend the best tools for chromatin and methylation analysis. "
        "Consider: assay type (ChIP-seq/ATAC-seq/bisulfite-seq/CUT&RUN/Hi-C), "
        "peak calling strategy, and downstream enrichment analysis."
    ),
    "proteomics": (
        "You are a proteomics expert. Given the user's request and available tools, "
        "recommend the best tools for mass spectrometry data analysis including peptide "
        "identification and quantification. Consider: acquisition type (DIA/DDA), "
        "quantification method (label-free/TMT/SILAC), and PTM analysis needs."
    ),
    "metabolomics": (
        "You are a metabolomics expert. Given the user's request and available tools, "
        "recommend the best tools for metabolite profiling including peak detection, annotation, "
        "and pathway analysis. Consider: platform (LC-MS/GC-MS/NMR), targeted vs untargeted, "
        "and annotation database needs."
    ),
    "metagenomics": (
        "You are a metagenomics expert. Given the user's request and available tools, "
        "recommend the best tools for microbiome analysis including taxonomic profiling "
        "and functional annotation. Consider: sequencing type (16S amplicon vs shotgun WGS), "
        "database choice (SILVA/GTDB/RefSeq), and alpha/beta diversity analysis needs."
    ),
    "structural_biology": (
        "You are a structural biology expert. Given the user's request and available tools, "
        "recommend the best tools for protein structure analysis including prediction, docking, "
        "and molecular dynamics. Consider: whether experimental structure exists (docking) "
        "or prediction is needed (AlphaFold3/Boltz2/ESMFold), binding site analysis, "
        "and MD simulation force field requirements."
    ),
    "drug_discovery": (
        "You are a drug discovery and pharmacology expert. Given the user's request and available tools, "
        "recommend the best tools for the drug discovery pipeline including structure prediction, "
        "virtual screening, ADMET prediction, lead optimization, and PK/PD modeling. "
        "Consider: whether a SMILES or structure file has been provided before recommending docking, "
        "docking type (blind/DiffDock vs site-directed/AutoDock Vina), specific safety endpoints "
        "(hERG/DILI/Ames), and regulatory requirements."
    ),
    "cryo_em": (
        "You are a cryo-EM expert. Given the user's request and available tools, "
        "recommend the best tools for cryo-EM data processing including motion correction, "
        "CTF estimation, particle picking, 2D/3D classification, and refinement. "
        "Consider: SPA vs cryo-ET workflow, software preference (CryoSPARC vs RELION), "
        "and subtomogram averaging needs."
    ),
    "systems_biology": (
        "You are a systems biology expert. Given the user's request and available tools, "
        "recommend the best tools for network analysis, pathway modeling, and multi-omics "
        "integration. Consider: ODE vs constraint-based modeling, network type (PPI/regulatory/metabolic), "
        "and integration strategy."
    ),
    "synthetic_biology": (
        "You are a synthetic biology expert. Given the user's request and available tools, "
        "recommend the best tools for genetic circuit design, metabolic engineering, and "
        "CRISPR-based genome editing. Consider: organism host, design constraints, and "
        "verification/characterization needs."
    ),
    "bioimaging": (
        "You are a bioimaging expert. Given the user's request and available tools, "
        "recommend the best tools for cell and tissue image analysis including segmentation, "
        "quantification, and spatial analysis. Consider: imaging modality (fluorescence/brightfield/spatial), "
        "segmentation approach (CellPose/StarDist/nnU-Net), and throughput requirements."
    ),
    "lab_automation": (
        "You are a lab automation expert. Given the user's request and available tools, "
        "recommend the best tools for liquid handling, plate management, and robotic workflows. "
        "Consider: hardware platform (Opentrons OT-2/Hamilton/Tecan), protocol complexity, "
        "LIMS integration needs, and sample tracking requirements."
    ),
    "default": (
        "You are a bioinformatics expert. Given the user's request and available tools, "
        "recommend the most appropriate tools for the analysis. Prioritize well-validated tools "
        "with good documentation and active community support."
    ),
}

# ---------------------------------------------------------------------------
# 5. Keyword sets for domain routing  (used by DomainRouter)
#    Covers all canonical domains + routing-only domains.
# ---------------------------------------------------------------------------

DOMAIN_KEYWORDS: Dict[str, Set[str]] = {
    # ── Canonical domains ──────────────────────────────────────────────────
    "genomics": {
        "genome", "genomic", "dna", "sequencing", "alignment", "mapping",
        "bwa", "hisat", "variant", "snp", "indel", "vcf", "bam", "sam",
        "fastq", "fasta", "chromosome", "exome", "wgs", "wes", "chip-seq",
        "atac-seq", "dnase", "methylation", "epigenetic", "chromatin",
        "nucleotide", "basepair", "genome assembly", "de novo",
    },
    "transcriptomics": {
        "rna-seq", "rnaseq", "rna", "transcript", "gene expression", "mrna",
        "differential expression", "deseq", "edger", "kallisto", "salmon",
        "star", "featurecounts", "htseq", "cufflinks", "stringtie",
        "tpm", "fpkm", "transcriptome", "transcriptomic",
    },
    "single_cell": {
        "single-cell", "single cell", "scrnaseq", "scrna", "10x", "cellranger",
        "seurat", "scanpy", "harmony", "scvi", "cell type", "clustering",
        "umap", "trajectory", "pseudotime", "velocity", "anndata", "cell atlas",
    },
    "epigenomics": {
        "chip-seq", "chipseq", "atac-seq", "atacseq", "bisulfite",
        "wgbs", "rrbs", "cut&run", "hi-c", "hic", "histone modification",
        "transcription factor binding", "macs2", "dna methylation",
        "chromatin accessibility", "open chromatin",
    },
    "proteomics": {
        "protein", "proteome", "proteomics", "proteomic", "mass spec",
        "mass spectrometry", "ms/ms", "peptide", "dia", "dda", "maxquant",
        "skyline", "fragpipe", "openms", "mascot", "phospho", "ptm",
        "itraq", "tmt", "silac", "orbitrap", "maldi",
    },
    "metabolomics": {
        "metabolite", "metabolome", "metabolomics", "metabolomic", "xcms",
        "msdial", "metaboanalyst", "small molecule", "lipid", "lipidomics",
        "mzml", "mzxml", "peak detection", "compound identification",
        "lc-ms", "gc-ms", "nmr spectroscopy", "pathway",
    },
    "metagenomics": {
        "metagenome", "microbiome", "16s", "shotgun metagenomics", "kraken",
        "metaphlan", "humann", "qiime", "dada2", "amplicon", "otu", "asv",
        "taxonomy", "microbiota", "16s rrna",
    },
    "structural_biology": {
        "pdb", "alphafold", "protein structure", "molecular dynamics",
        "docking", "binding affinity", "conformation", "fold", "secondary structure",
        "boltz", "esm", "chai", "rosettafold", "ligand", "receptor",
    },
    "drug_discovery": {
        "drug", "admet", "pharmacokinetics", "pharmacology", "toxicity",
        "binding affinity", "compound", "therapeutic", "dose", "clinical",
        "adverse", "fda", "smiles", "herg", "dili", "ames", "adme",
        "lead optimization", "virtual screening", "scaffold", "qsar",
        "nca", "pk", "pd", "ivive", "half-life", "cmax", "tmax", "auc",
        "retrosynthesis", "generative chemistry", "diffdock", "autodock",
        "vina", "glide", "reinvent",
    },
    "cryo_em": {
        "cryo-em", "cryoem", "cryosparc", "relion", "spa", "micrograph",
        "ctf", "tomography", "tilt series", "subtomogram", "cryo-et",
        "particle picking", "2d class", "3d refinement",
    },
    "systems_biology": {
        "ode", "network analysis", "flux balance", "gene regulatory",
        "pathway modeling", "sbml", "fba", "cobra", "cytoscape",
        "network inference", "boolean model",
    },
    "synthetic_biology": {
        "genetic circuit", "metabolic engineering", "crispr", "guide rna",
        "grna", "knockout", "knockin", "plasmid", "gibson assembly",
        "golden gate", "gene synthesis", "promoter design",
    },
    "bioimaging": {
        "image", "microscopy", "segmentation", "cell counting", "fluorescence",
        "confocal", "nifti", "registration", "nnunet", "cellpose", "stardist",
        "imagej", "fiji", "spatial imaging", "flow cytometry",
    },
    "lab_automation": {
        "liquid handling", "pipetting", "plate reader", "ot-2", "opentrons",
        "pylabrobot", "hamilton", "tecan", "lims", "sample tracking",
        "robotic", "high-throughput screening", "hts", "echo",
    },
    # ── Routing-only domains ───────────────────────────────────────────────
    "immunology": {
        "immune", "antibody", "antigen", "t-cell", "b-cell", "cytokine",
        "flow cytometry", "facs", "immunophenotyping", "tcr", "bcr",
        "immunoglobulin", "hla", "mhc",
    },
    "cancer_biology": {
        "cancer", "tumor", "tumour", "oncology", "somatic", "driver",
        "cnv", "tcga", "maf", "oncogene", "tumour suppressor", "metastasis",
    },
    "molecular_biology": {
        "primer", "pcr", "cloning", "restriction", "golden gate",
        "crispr design", "guide rna design", "oligo", "vector map",
    },
    "biochemistry": {
        "enzyme", "kinetics", "michaelis", "thermodynamics", "assay",
        "spectroscopy", "circular dichroism", "itc", "spr",
    },
    "genetics": {
        "linkage", "gwas", "heritability", "population genetics",
        "pedigree", "mendelian", "qtl",
    },
    "microbiology": {
        "bacteria", "bacterium", "microbial", "pathogen", "antimicrobial",
        "resistance", "amr", "phage", "biofilm",
    },
    "cell_biology": {
        "cell line", "cell culture", "apoptosis", "proliferation",
        "signaling", "receptor", "organelle",
    },
    "database": {
        "database", "query", "uniprot", "ncbi", "ensembl", "pubmed",
        "kegg", "reactome", "go terms", "interpro", "blast", "fetch",
    },
    "literature": {
        "literature", "paper", "pubmed", "arxiv", "scholar", "citation",
        "review", "abstract", "doi",
    },
}

# ---------------------------------------------------------------------------
# 6. Galaxy tool category mapping  (used by DomainRouter and DomainSpecialistPool)
# ---------------------------------------------------------------------------

DOMAIN_TO_GALAXY_CATEGORY: Dict[str, List[str]] = {
    "genomics":          ["Sequence Analysis", "Variant Analysis", "Next Gen Mappers", "SAM"],
    "transcriptomics":   ["RNA", "Transcriptomics", "Sequence Analysis"],
    "single_cell":       ["Single-cell", "RNA", "Transcriptomics"],
    "epigenomics":       ["Epigenomics", "Sequence Analysis", "Variant Analysis"],
    "proteomics":        ["Proteomics", "Mass Spectrometry"],
    "metabolomics":      ["Metabolomics", "Mass Spectrometry"],
    "metagenomics":      ["Metagenomics", "Ecology"],
    "structural_biology": ["Structural Biology", "Computational chemistry"],
    "drug_discovery":    ["Pharmacology", "Computational chemistry", "Cheminformatics"],
    "cryo_em":           ["Cryo-EM", "Structural Biology"],
    "systems_biology":   ["Systems Biology", "Networks"],
    "synthetic_biology": ["Synthetic Biology", "Molecular Biology"],
    "bioimaging":        ["Imaging", "Graphics"],
    "lab_automation":    ["Lab Automation", "LIMS"],
    # Routing-only
    "immunology":        ["Immunology"],
    "cancer_biology":    ["Cancer Biology", "Variant Analysis"],
    "molecular_biology": ["Molecular Biology", "Sequence Analysis"],
    "biochemistry":      ["Biochemistry"],
    "database":          ["Data Source", "Web Services"],
    "literature":        ["Literature"],
}

# ---------------------------------------------------------------------------
# 7. Sub-domain → canonical domain mapping
#    Used by _inferDomainWithLLM() in galaxy-assistant.ts (fine-grained
#    technical sub-domains map back to canonical domains for search scoring).
# ---------------------------------------------------------------------------

def get_topics_for_domains(domains: List[str]) -> List[str]:
    """Return all topics for the selected domains, deduplicated (order-preserving)."""
    seen: set = set()
    topics: List[str] = []
    for domain in domains:
        for topic in DOMAIN_TOPICS.get(domain, []):
            if topic not in seen:
                seen.add(topic)
                topics.append(topic)
    return topics


# ---------------------------------------------------------------------------
# 8. Sub-domain → canonical domain mapping
#    Used by _inferDomainWithLLM() in galaxy-assistant.ts (fine-grained
#    technical sub-domains map back to canonical domains for search scoring).
# ---------------------------------------------------------------------------

SUBDOMAIN_TO_CANONICAL: Dict[str, str] = {
    # Genomics sub-domains
    "rna_seq":                  "transcriptomics",
    "variant_calling_germline": "genomics",
    "variant_calling_somatic":  "genomics",   # also cancer_biology at routing level
    "genome_assembly":          "genomics",
    "methylation":              "epigenomics",
    # Single-cell
    "single_cell":              "single_cell",
    # Epigenomics
    "epigenomics_chip":         "epigenomics",
    "epigenomics_atac":         "epigenomics",
    # Proteomics (identity)
    "proteomics":               "proteomics",
    # Drug discovery
    "drug_discovery":           "drug_discovery",
    # Metagenomics
    "metagenomics_16s":         "metagenomics",
    "metagenomics_shotgun":     "metagenomics",
    # Structural / cryo-EM
    "cryo_em":                  "cryo_em",
    "structural_biology":       "structural_biology",
}
