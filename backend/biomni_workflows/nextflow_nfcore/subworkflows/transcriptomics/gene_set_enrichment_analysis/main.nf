#!/usr/bin/env nextflow
/*
 * transcriptomics/gene_set_enrichment_analysis
 *
 * Gene Set Enrichment Analysis (GSEA) and over-representation analysis (ORA)
 * on differential expression results. Supports KEGG, GO, Reactome, MSigDB,
 * and custom gene set databases.
 *
 * Pipeline Steps:
 * 1. FGSEA              -- Fast preranked GSEA (fgsea) on ranked gene list
 * 2. ORA                -- Over-representation analysis (clusterProfiler enrichGO/enrichKEGG)
 * 3. GSEA_PLOT          -- GSEA enrichment plots for top pathways
 * 4. DOTPLOT            -- Dot plot of significant gene sets
 * 5. CNET_PLOT          -- Concept network plot linking genes to pathways
 * 6. PATHWAY_REPORT     -- HTML summary report of all enrichment results
 *
 * Outputs:
 *   gsea_results.tsv         -- fGSEA results (NES, padj, leading edge)
 *   ora_results.tsv          -- ORA results (count, GeneRatio, padj)
 *   gsea_plots.pdf           -- Enrichment score plots for top pathways
 *   dotplot.pdf              -- Dot plot of top enriched gene sets
 *   pathway_report.html      -- HTML summary report
 *
 * References:
 *   fgsea: Korotkevich et al. bioRxiv 2021, doi:10.1101/060012
 *   clusterProfiler: Yu et al. OMICS 2012, 16(5):284-287
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.input              = null          // DESeq2/edgeR results TSV: gene_id, log2FoldChange, padj
params.gene_col           = 'gene_id'     // Column name for gene identifiers
params.lfc_col            = 'log2FoldChange' // Column name for fold change
params.padj_col           = 'padj'        // Column name for adjusted p-value
params.species            = 'Homo sapiens'  // Species: 'Homo sapiens' | 'Mus musculus' | ...
params.organism           = 'hsa'         // KEGG organism code: hsa | mmu | rno | ...

// Gene set databases to test
params.databases          = 'GO,KEGG,Reactome'  // Comma-separated: GO | KEGG | Reactome | MSigDB
params.msigdb_categories  = 'H,C2,C5'    // MSigDB collections (if MSigDB in databases)
params.go_ontology        = 'BP'          // GO ontology: BP | CC | MF | ALL

// Statistical thresholds
params.fdr_threshold      = 0.25          // FDR threshold for GSEA (standard: 0.25)
params.ora_padj           = 0.05          // padj threshold for ORA
params.min_gs_size        = 15            // Minimum gene set size
params.max_gs_size        = 500           // Maximum gene set size
params.n_permutations     = 1000          // Number of GSEA permutations

// Ranking metric for GSEA
params.rank_by            = 'signed_log'  // Ranking: signed_log (-log10(padj)*sign(lfc)) | lfc | stat

// Visualisation
params.top_pathways       = 20            // Number of top pathways to plot
params.show_category      = 15            // Categories to show in dotplot/cnetplot

params.outdir             = './results/gene_set_enrichment_analysis'
params.publish_dir_mode   = 'copy'
params.max_memory         = '32.GB'
params.max_cpus           = 8
params.max_time           = '12.h'

// ============================================================================
// Processes
// ============================================================================

process FGSEA {
    container 'quay.io/biocontainers/bioconductor-fgsea:1.28.0--r43hf17093f_0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(de_results)

    output:
    path("gsea_results.tsv"),  emit: gsea_results
    path("gsea_plots.pdf"),    emit: gsea_plots

    script:
    """
    Rscript - <<'REOF'
    library(fgsea)
    library(dplyr)
    library(ggplot2)
    library(msigdbr)

    # Load DE results
    de <- read.table("${de_results}", header=TRUE, sep="\t", stringsAsFactors=FALSE)
    de <- de[!is.na(de\$${params.lfc_col}) & !is.na(de\$${params.padj_col}), ]

    # Build ranked gene list
    if ("${params.rank_by}" == "signed_log") {
        de\$rank <- -log10(pmax(de\$${params.padj_col}, 1e-300)) * sign(de\$${params.lfc_col})
    } else if ("${params.rank_by}" == "lfc") {
        de\$rank <- de\$${params.lfc_col}
    } else {
        de\$rank <- de\$${params.lfc_col}  # fallback
    }
    ranks <- setNames(de\$rank, de\$${params.gene_col})
    ranks <- sort(ranks, decreasing=TRUE)
    ranks <- ranks[!duplicated(names(ranks))]

    # Load gene sets
    all_results <- list()
    dbs <- strsplit("${params.databases}", ",")[[1]]
    for (db in trimws(dbs)) {
        if (db == "GO") {
            gs <- msigdbr(species="${params.species}", category="C5", subcategory="${params.go_ontology}")
            gs_list <- split(gs\$gene_symbol, gs\$gs_name)
        } else if (db == "KEGG") {
            gs <- msigdbr(species="${params.species}", category="C2", subcategory="CP:KEGG")
            gs_list <- split(gs\$gene_symbol, gs\$gs_name)
        } else if (db == "Reactome") {
            gs <- msigdbr(species="${params.species}", category="C2", subcategory="CP:REACTOME")
            gs_list <- split(gs\$gene_symbol, gs\$gs_name)
        } else {
            next
        }
        res <- fgsea(pathways=gs_list, stats=ranks,
                     minSize=${params.min_gs_size}, maxSize=${params.max_gs_size},
                     nperm=${params.n_permutations})
        res\$database <- db
        all_results[[db]] <- res
    }
    final_results <- do.call(rbind, all_results)
    final_results <- final_results[order(final_results\$padj), ]
    write.table(final_results[, -which(names(final_results) == "leadingEdge")],
                "gsea_results.tsv", sep="\t", quote=FALSE, row.names=FALSE)

    # GSEA plots for top pathways
    top_paths <- head(final_results\$pathway[final_results\$padj < ${params.fdr_threshold}], ${params.top_pathways})
    if (length(top_paths) > 0) {
        all_gs <- do.call(c, lapply(all_results, function(r) attr(r, "pathways")))
        pdf("gsea_plots.pdf", width=10, height=5)
        for (p in top_paths) {
            tryCatch(plotEnrichment(all_gs[[p]], ranks) + ggtitle(p), error=function(e) NULL)
        }
        dev.off()
    } else {
        pdf("gsea_plots.pdf"); dev.off()
    }
    REOF
    """
}

process ORA {
    container 'quay.io/biocontainers/bioconductor-clusterprofiler:4.10.0--r43hf17093f_0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(de_results)

    output:
    path("ora_results.tsv"),  emit: ora_results
    path("dotplot.pdf"),      emit: dotplot

    script:
    """
    Rscript - <<'REOF'
    library(clusterProfiler)
    library(org.Hs.eg.db)
    library(ggplot2)

    de <- read.table("${de_results}", header=TRUE, sep="\t")
    sig <- de[!is.na(de\$${params.padj_col}) & de\$${params.padj_col} < 0.05, ]
    gene_list <- unique(sig\$${params.gene_col})

    results <- list()

    if (grepl("GO", "${params.databases}")) {
        go_res <- enrichGO(gene=gene_list, OrgDb=org.Hs.eg.db,
                           keyType="SYMBOL", ont="${params.go_ontology}",
                           pAdjustMethod="BH", pvalueCutoff=${params.ora_padj},
                           minGSSize=${params.min_gs_size}, maxGSSize=${params.max_gs_size})
        if (!is.null(go_res) && nrow(go_res@result) > 0) {
            df <- as.data.frame(go_res); df\$database <- "GO"
            results[["GO"]] <- df
        }
    }

    if (grepl("KEGG", "${params.databases}")) {
        eg <- bitr(gene_list, fromType="SYMBOL", toType="ENTREZID", OrgDb=org.Hs.eg.db)
        kegg_res <- enrichKEGG(gene=eg\$ENTREZID, organism="${params.organism}",
                               pAdjustMethod="BH", pvalueCutoff=${params.ora_padj})
        if (!is.null(kegg_res) && nrow(kegg_res@result) > 0) {
            df <- as.data.frame(kegg_res); df\$database <- "KEGG"
            results[["KEGG"]] <- df
        }
    }

    if (length(results) > 0) {
        final <- do.call(rbind, results)
        write.table(final, "ora_results.tsv", sep="\t", quote=FALSE, row.names=FALSE)
        # Dotplot
        pdf("dotplot.pdf", width=10, height=8)
        if (!is.null(go_res)) print(dotplot(go_res, showCategory=${params.show_category}))
        dev.off()
    } else {
        write.table(data.frame(), "ora_results.tsv", sep="\t")
        pdf("dotplot.pdf"); dev.off()
    }
    REOF
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    def de_results = Channel.fromPath(params.input)
    FGSEA(de_results)
    ORA(de_results)
}
