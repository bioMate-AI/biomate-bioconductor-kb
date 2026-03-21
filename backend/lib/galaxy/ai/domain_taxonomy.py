"""
User Domain Taxonomy

Static taxonomy of bioinformatics research domains and their associated topics.
Used by the User Domain Profile feature to personalize workflow search context.
"""

from typing import List

DOMAIN_TAXONOMY: dict[str, list[str]] = {
    "genomics": ["variant calling", "WGS", "WES", "copy number", "structural variants", "population genetics"],
    "transcriptomics": ["bulk RNA-seq", "spatial transcriptomics", "long-read RNA-seq", "ATAC-seq"],
    "single_cell": ["scRNA-seq", "scATAC-seq", "multiome", "cell typing", "trajectory analysis"],
    "epigenomics": ["ChIP-seq", "ATAC-seq", "bisulfite-seq", "CUT&RUN", "Hi-C"],
    "proteomics": ["DDA", "DIA", "phosphoproteomics", "protein-protein interaction", "structural proteomics"],
    "metabolomics": ["LC-MS", "GC-MS", "NMR", "lipidomics", "metabolic flux"],
    "metagenomics": ["16S amplicon", "shotgun metagenomics", "metatranscriptomics", "binning/MAGs"],
    "structural_biology": ["AlphaFold", "molecular docking", "MD simulation", "cryo-EM", "X-ray crystallography"],
    "drug_discovery": ["ADMET prediction", "lead optimization", "target identification", "virtual screening"],
    "cryo_em": ["SPA", "cryo-ET", "subtomogram averaging", "helical reconstruction"],
    "pharmacology": ["PK/PD modeling", "IVIVE", "dose-response", "clinical pharmacology"],
    "systems_biology": ["ODE modeling", "network analysis", "flux balance analysis", "gene regulatory networks"],
    "synthetic_biology": ["genetic circuit design", "metabolic engineering", "CRISPR design"],
    "bioimaging": ["cell segmentation", "fluorescence microscopy", "spatial omics imaging", "flow cytometry"],
}

DOMAIN_LABELS: dict[str, str] = {
    "genomics": "Genomics",
    "transcriptomics": "Transcriptomics",
    "single_cell": "Single Cell",
    "epigenomics": "Epigenomics",
    "proteomics": "Proteomics",
    "metabolomics": "Metabolomics",
    "metagenomics": "Metagenomics",
    "structural_biology": "Structural Biology",
    "drug_discovery": "Drug Discovery",
    "cryo_em": "Cryo-EM",
    "pharmacology": "Pharmacology",
    "systems_biology": "Systems Biology",
    "synthetic_biology": "Synthetic Biology",
    "bioimaging": "Bioimaging",
}


def get_topics_for_domains(domains: List[str]) -> List[str]:
    """Return all topics for the selected domains, deduplicated (order-preserving)."""
    seen: set[str] = set()
    topics: list[str] = []
    for domain in domains:
        for topic in DOMAIN_TAXONOMY.get(domain, []):
            if topic not in seen:
                seen.add(topic)
                topics.append(topic)
    return topics
