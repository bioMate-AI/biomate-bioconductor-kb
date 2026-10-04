#!/usr/bin/env python3
"""Build the Bioconductor context-based method-selection benchmark (data.jsonl).

Each item: a rich scientific-context request -> the one correct method among confusable siblings.
Gold is PREDICTABLE from an observable data-shape/assay discriminator (design-validity gate:
docs/20261004_BIOC_METHOD_SELECTION_DESIGN_GATE.md). `invalid_picks` are candidates that are a
CORRECTNESS failure for that context (e.g. ORA on ranked data) -> used for the invalid-regime rate.
Candidate names are real workflow entries in the `workflows` table. Context uses real organisms/assays/
pathways; it tests context interpretation, not keyword matching, so method names are NOT in the query.
"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))

# Candidate menus per group (confusable siblings = the method choices offered)
ORA_GSEA = ["clusterprofiler", "clusterprofiler_gene_set_enrichment_analysis",
            "reactomepa", "reactomepa_reactome_gsea", "fgsea", "fgsea_over_representation_analysis"]
DE_ASSAY = ["limma", "deseq2", "edger", "nf-core/differentialabundance"]
DE_STAGE = ["deseq2", "deseq2_de_from_transcript_abundance", "nf-core/differentialabundance"]
PROT     = ["msstatstmt", "msstatslip", "MSstatsPTM", "nf-core/proteomicslfq", "msnbase"]
SC_FMT   = ["scran", "nf-core/scdownstream", "ucell_seurat_workflow"]

ITEMS = [
 # ── Group 1: ORA vs GSEA (discrete list -> ORA; ranked statistic -> GSEA; DB: GO/KEGG=clusterprofiler, Reactome=reactomepa, generic GMT=fgsea) ──
 ("og_01","I ran DESeq2 on human RNA-seq and extracted 284 genes significant at FDR<0.05 (up-regulated). I want GO and KEGG pathway over-representation for that gene set.",
   ORA_GSEA,"clusterprofiler",["clusterprofiler_gene_set_enrichment_analysis","reactomepa_reactome_gsea","fgsea"],"discrete DE gene list + GO/KEGG"),
 ("og_02","I have all ~18,000 detected mouse genes ranked by the signed -log10(p-value) from my DE test and want to detect coordinated pathway shifts without applying a significance cutoff (GO/KEGG).",
   ORA_GSEA,"clusterprofiler_gene_set_enrichment_analysis",["clusterprofiler","reactomepa","fgsea_over_representation_analysis"],"genome-wide ranked statistic + GO/KEGG"),
 ("og_03","I have a discrete list of 150 differentially expressed Entrez IDs and specifically want Reactome pathway over-representation.",
   ORA_GSEA,"reactomepa",["reactomepa_reactome_gsea","clusterprofiler_gene_set_enrichment_analysis","fgsea"],"discrete list + Reactome"),
 ("og_04","I have a ranked fold-change vector over all genes and want a Reactome GSEA.",
   ORA_GSEA,"reactomepa_reactome_gsea",["reactomepa","clusterprofiler","fgsea_over_representation_analysis"],"ranked vector + Reactome"),
 ("og_05","I have a .rnk file (gene -> ranking statistic) and a custom .gmt of MSigDB hallmark gene sets, and want fast preranked enrichment.",
   ORA_GSEA,"fgsea",["fgsea_over_representation_analysis","clusterprofiler","reactomepa"],"ranked .rnk + custom GMT"),
 ("og_06","I have a foreground list of top DE genes, a background universe of all detected genes, and a GMT of pathways, and want a hypergeometric over-representation test.",
   ORA_GSEA,"fgsea_over_representation_analysis",["fgsea","clusterprofiler_gene_set_enrichment_analysis","reactomepa_reactome_gsea"],"foreground+background+GMT hypergeometric"),
 ("og_07","After thresholding at |log2FC|>1 and FDR<0.1 I have 97 down-regulated genes; I want GO enrichment on just those.",
   ORA_GSEA,"clusterprofiler",["clusterprofiler_gene_set_enrichment_analysis","reactomepa_reactome_gsea"],"thresholded discrete list + GO"),
 ("og_08","My DE output is the full gene table with log2FC for every gene (no cutoff applied). I want KEGG GSEA to find subtle concordant pathway changes.",
   ORA_GSEA,"clusterprofiler_gene_set_enrichment_analysis",["clusterprofiler","reactomepa","fgsea_over_representation_analysis"],"full ranked table + KEGG GSEA"),
 ("og_09","I only have a set of ~40 candidate gene symbols from a literature screen (no scores) and want Reactome pathway over-representation.",
   ORA_GSEA,"reactomepa",["reactomepa_reactome_gsea","fgsea"],"unranked candidate set + Reactome"),
 ("og_10","I have a pre-ranked list of genes by t-statistic and want running-sum enrichment against a GMT I downloaded.",
   ORA_GSEA,"fgsea",["fgsea_over_representation_analysis","clusterprofiler"],"ranked by t-stat + GMT"),

 # ── Group 2: Microarray vs RNA-seq DE (two-color intensity -> limma; integer counts -> deseq2/edger; count matrix + report -> nf-core/differentialabundance) ──
 ("as_01","I have two-color Agilent microarray .gpr intensity files with a targets table (Cy3/Cy5), two conditions, and want differentially expressed genes.",
   DE_ASSAY,"limma",["deseq2","edger"],"two-color microarray intensity"),
 ("as_02","I have a raw integer count matrix (featureCounts) for human RNA-seq, 3 vs 3, and want a single reproducible negative-binomial DE analysis.",
   DE_ASSAY,"deseq2",["limma"],"raw integer counts, single NB method"),
 ("as_03","I have a tab-delimited table of raw RNA-seq counts with gene symbols and want DE via the robust quasi-likelihood F-test.",
   DE_ASSAY,"edger",["limma"],"raw counts, QL-F framework"),
 ("as_04","I have a pre-computed gene count matrix + samplesheet and want a full differential-abundance REPORT (multiple methods, volcano, heatmap, GSEA) rather than a single hand-written script.",
   DE_ASSAY,"nf-core/differentialabundance",["limma"],"count matrix + multi-method report"),

 # ── Group 3: input-stage DE ──
 ("st_01","I already hold a gene-level raw count matrix and coldata and want a single programmatic DESeq2 analysis in R/Markdown.",
   DE_STAGE,"deseq2",["deseq2_de_from_transcript_abundance"],"count matrix in hand, single method"),
 ("st_02","My upstream output is Salmon transcript quantifications (quant.sf) plus a tx2gene mapping; I need gene-level differential expression.",
   DE_STAGE,"deseq2_de_from_transcript_abundance",["deseq2","nf-core/differentialabundance"],"Salmon quant.sf -> gene-level"),
 ("st_03","I have a count matrix and want a reviewer-ready multi-method differential-abundance report with QC and plots, not a bespoke script.",
   DE_STAGE,"nf-core/differentialabundance",["deseq2","deseq2_de_from_transcript_abundance"],"count matrix + pipeline report"),

 # ── Group 4: proteomics labeling ──
 ("pr_01","I have TMT 10-plex proteomics quantified in Proteome Discoverer (PSM sheet + annotation) and want differential abundance testing.",
   PROT,"msstatstmt",["msstatslip","MSstatsPTM","nf-core/proteomicslfq"],"TMT-labeled DDA"),
 ("pr_02","I ran a limited-proteolysis (LiP-MS) experiment with matched trypsin-control (TrP) Spectronaut exports and want altered-peptide detection.",
   PROT,"msstatslip",["msstatstmt","MSstatsPTM","nf-core/proteomicslfq"],"LiP-MS + TrP control"),
 ("pr_03","I have phosphopeptide (PTM) quantification and want site-level differential modification analysis accounting for protein-level changes.",
   PROT,"MSstatsPTM",["msstatstmt","msstatslip","nf-core/proteomicslfq"],"PTM site quantification"),
 ("pr_04","I have label-free DDA mass spectra and want an end-to-end OpenMS label-free quantification pipeline from raw files.",
   PROT,"nf-core/proteomicslfq",["msstatstmt","msstatslip","MSstatsPTM"],"label-free DDA raw -> LFQ pipeline"),

 # ── Group 5: single-cell object-format (partial) ──
 ("sc_01","I have a SingleCellExperiment object (pre-processed) and want graph-based quick clustering to drive cluster-based normalization within Bioconductor.",
   SC_FMT,"scran",["nf-core/scdownstream","ucell_seurat_workflow"],"SingleCellExperiment object, Bioc step"),
 ("sc_02","I have an h5ad AnnData count matrix and want a full downstream pipeline: clustering, cell-type annotation, UMAP.",
   SC_FMT,"nf-core/scdownstream",["scran","ucell_seurat_workflow"],"h5ad -> downstream pipeline"),
 ("sc_03","I have a Seurat object and want to score a set of positive/negative marker gene signatures per cell within Seurat.",
   SC_FMT,"ucell_seurat_workflow",["scran","nf-core/scdownstream"],"Seurat object, signature scoring"),
]

def norm(s): return s.strip().lower()
rows=[]
for id_,q,cands,gold,inv,disc in ITEMS:
    assert gold in cands, f"{id_}: gold not in candidates"
    for p in inv: assert p in cands, f"{id_}: invalid pick {p} not in candidates"
    rows.append({"id":id_,"query":q,"candidates":cands,"correct_method":gold,
                 "acceptable_alts":[],"invalid_picks":inv,"discriminator":disc})
os.makedirs(HERE,exist_ok=True)
with open(os.path.join(HERE,"data.jsonl"),"w") as f:
    for r in rows: f.write(json.dumps(r)+"\n")
from collections import Counter
print(f"wrote {len(rows)} items; groups:",Counter(r['id'][:2] for r in rows))
