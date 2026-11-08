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

 # ══════════ HARD TIER: obscure same-package VARIANT triples (name alone is uninformative; must read context) ══════════
 # edgeR sub-pipelines (single-factor exact vs multifactor GLM-LRT vs fold-change-threshold)
 ("h_edger_1","RNA-seq, control vs treated only (one factor, two groups), raw counts; I want the classic pairwise exact-test differential expression.",
   ["edger","edger_classic_pipeline","edger_glm_lrt_pipeline","edger_fold_change_threshold_testing"],"edger_classic_pipeline",[],"single-factor 2-group exact test"),
 ("h_edger_2","Factorial RNA-seq design (genotype × treatment with an interaction term), raw counts; I need DE for the interaction using negative-binomial GLMs.",
   ["edger","edger_classic_pipeline","edger_glm_lrt_pipeline","edger_fold_change_threshold_testing"],"edger_glm_lrt_pipeline",[],"multifactor GLM + LRT"),
 ("h_edger_3","I want to call genes that exceed a specific log-fold-change threshold with a rigorous statistical test, not just FDR on zero-change.",
   ["edger","edger_classic_pipeline","edger_glm_lrt_pipeline","edger_fold_change_threshold_testing"],"edger_fold_change_threshold_testing",[],"fold-change-threshold test (TREAT/glmTreat)"),
 # DESeq2 sub-pipelines (Wald 2-group vs LRT time-series vs multi-factor covariate)
 ("h_deseq_1","Simple two-condition comparison, raw count matrix, standard pairwise test.",
   ["deseq2","deseq2_likelihood_ratio_test","deseq2_multi_factor_analysis"],"deseq2",[],"standard Wald 2-group"),
 ("h_deseq_2","Time-course with four time points; I want genes that change significantly across ANY time point, not a single pairwise contrast.",
   ["deseq2","deseq2_likelihood_ratio_test","deseq2_multi_factor_analysis"],"deseq2_likelihood_ratio_test",[],"LRT across multiple levels/time"),
 ("h_deseq_3","Two conditions, but samples come from three sequencing batches; I want DE while controlling for the batch covariate.",
   ["deseq2","deseq2_likelihood_ratio_test","deseq2_multi_factor_analysis"],"deseq2_multi_factor_analysis",[],"multi-factor batch covariate"),
 # fgsea variants (preranked GSEA vs ORA vs coregulation-no-contrast)
 ("h_fgsea_1","I have a ranked .rnk statistic vector and a GMT; run fast preranked enrichment.",
   ["fgsea","fgsea_over_representation_analysis","fgsea_gene_set_coregulation_analysis"],"fgsea",["fgsea_over_representation_analysis"],"ranked preranked GSEA"),
 ("h_fgsea_2","I have a foreground gene list, a background universe, and a GMT; run a hypergeometric over-representation test.",
   ["fgsea","fgsea_over_representation_analysis","fgsea_gene_set_coregulation_analysis"],"fgsea_over_representation_analysis",["fgsea"],"hypergeometric ORA"),
 ("h_fgsea_3","Single-cell expression matrix with no explicit contrast/condition; I want to find gene sets whose members are highly co-regulated.",
   ["fgsea","fgsea_over_representation_analysis","fgsea_gene_set_coregulation_analysis"],"fgsea_gene_set_coregulation_analysis",[],"coregulation without a contrast"),
 # GSEA by ontology (GO/KEGG vs Reactome vs Disease Ontology)
 ("h_gsea_db_1","Ranked gene list; I specifically want Disease Ontology gene-set enrichment.",
   ["clusterprofiler_gene_set_enrichment_analysis","reactomepa_reactome_gsea","dose_gene_set_enrichment_analysis"],"dose_gene_set_enrichment_analysis",[],"ranked + Disease Ontology"),
 ("h_gsea_db_2","Ranked gene list; I want Reactome GSEA.",
   ["clusterprofiler_gene_set_enrichment_analysis","reactomepa_reactome_gsea","dose_gene_set_enrichment_analysis"],"reactomepa_reactome_gsea",[],"ranked + Reactome"),
 ("h_gsea_db_3","Ranked gene list; I want GO and KEGG GSEA.",
   ["clusterprofiler_gene_set_enrichment_analysis","reactomepa_reactome_gsea","dose_gene_set_enrichment_analysis"],"clusterprofiler_gene_set_enrichment_analysis",[],"ranked + GO/KEGG"),
 # MSnbase variants (import/quantify vs label-free LFQ vs targeted SRM/MRM)
 ("h_msnb_1","DDA proteomics; I want label-free MS2 quantitation by spectral counting / spectral index.",
   ["msnbase","msnbase_label_free_quantitation","msnbase_chromatographic_srm_import"],"msnbase_label_free_quantitation",[],"label-free spectral counting"),
 ("h_msnb_2","Targeted SRM/MRM experiment with chromatographic .mzML; I want to import and extract the chromatographic traces.",
   ["msnbase","msnbase_label_free_quantitation","msnbase_chromatographic_srm_import"],"msnbase_chromatographic_srm_import",[],"targeted SRM/MRM chromatographic"),
 # scran variants (clustering/norm vs PC selection vs gene correlation)
 ("h_scran_1","SingleCellExperiment with a PCA already computed; I want to choose the optimal number of principal components from the technical-variance estimates.",
   ["scran","scran_automated_pc_selection","scran_gene_correlation_analysis"],"scran_automated_pc_selection",[],"PC-number selection"),
 ("h_scran_2","SingleCellExperiment with highly variable genes; I want significant pairwise gene correlations while blocking on batch.",
   ["scran","scran_automated_pc_selection","scran_gene_correlation_analysis"],"scran_gene_correlation_analysis",[],"HVG correlation blocking batch"),

 # ── Group 5: single-cell object-format (partial) ──
 ("sc_01","I have a SingleCellExperiment object (pre-processed) and want graph-based quick clustering to drive cluster-based normalization within Bioconductor.",
   SC_FMT,"scran",["nf-core/scdownstream","ucell_seurat_workflow"],"SingleCellExperiment object, Bioc step"),
 ("sc_02","I have an h5ad AnnData count matrix and want a full downstream pipeline: clustering, cell-type annotation, UMAP.",
   SC_FMT,"nf-core/scdownstream",["scran","ucell_seurat_workflow"],"h5ad -> downstream pipeline"),
 ("sc_03","I have a Seurat object and want to score a set of positive/negative marker gene signatures per cell within Seurat.",
   SC_FMT,"ucell_seurat_workflow",["scran","nf-core/scdownstream"],"Seurat object, signature scoring"),
]

# accept_retrieval: scientifically-valid ALTERNATIVES for the FULL-CATALOG retrieval@1 metric only
# (NOT used in the in-context discrimination arms, which stay strict on the specific gold). Principle:
# a tool is credited iff it performs the correct analysis REGIME for the stated input — a DB-agnostic
# GSEA tool for an un-pinned GSEA query; any count-based NB DE for a generic count-DE query; a two-color
# microarray tool for two-color data; a label-free tool for LFQ. Tools that miss the stated design
# requirement (batch covariate, interaction, specific ontology, single-script-vs-pipeline) are NOT credited.
ACCEPT_RETRIEVAL = {
 "og_02": ["Gene Set Enrichment Analysis"],
 "og_05": ["Gene Set Enrichment Analysis", "clusterprofiler_gene_set_enrichment_analysis"],
 "og_08": ["Gene Set Enrichment Analysis"],
 "og_10": ["Gene Set Enrichment Analysis", "clusterprofiler_gene_set_enrichment_analysis"],
 "h_fgsea_1": ["Gene Set Enrichment Analysis", "clusterprofiler_gene_set_enrichment_analysis"],
 "h_gsea_db_3": ["Gene Set Enrichment Analysis"],
 "as_01": ["genarise", "limmaGUI"],
 "as_02": ["nf-core/differentialabundance", "edger", "absseq"],
 "as_03": ["deseq2", "nf-core/differentialabundance", "absseq"],
 "st_01": ["edger"],
 "h_deseq_1": ["edger", "edger_classic_pipeline", "absseq", "nf-core/differentialabundance"],
 "h_deseq_3": ["nf-core/differentialabundance"],
 "h_edger_1": ["deseq2", "absseq", "nf-core/differentialabundance"],
 "h_edger_2": ["nf-core/differentialabundance"],
 "pr_04": ["msnbase_label_free_quantitation"],
 "h_msnb_1": ["nf-core/proteomicslfq"],
}
def norm(s): return s.strip().lower()
rows=[]
for id_,q,cands,gold,inv,disc in ITEMS:
    assert gold in cands, f"{id_}: gold not in candidates"
    for p in inv: assert p in cands, f"{id_}: invalid pick {p} not in candidates"
    rows.append({"id":id_,"query":q,"candidates":cands,"correct_method":gold,
                 "acceptable_alts":[],"invalid_picks":inv,"discriminator":disc,
                 "accept_retrieval":ACCEPT_RETRIEVAL.get(id_,[])})
os.makedirs(HERE,exist_ok=True)
with open(os.path.join(HERE,"data.jsonl"),"w") as f:
    for r in rows: f.write(json.dumps(r)+"\n")
from collections import Counter
print(f"wrote {len(rows)} items; groups:",Counter(r['id'][:2] for r in rows))
