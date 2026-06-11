#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fgsea — preranked_gsea
// Run fast preranked gene set enrichment analysis on a ranked list of genes.
// Input: naive.vs.th1.rnk, mouse.reactome.gmt
// Container: quay.io/biocontainers/bioconductor-fgsea:1.36.2--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, fgsea, ggplot2, org.Mm.eg.db
// Visualizations: enrichment plot, GSEA table plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load gene ranks from file
//  * 2. [Input & Preparation] Load pathways from GMT file
//  * 3. [Core Analysis] Run fgsea with specified size limits and p-value resolution
//  * 4. [Core Analysis] Collapse redundant pathways to identify independent main pathways
//  * 5. [Visualization & Output] Plot enrichment curves and GSEA tables
//  * 6. [Core Analysis] Map gene IDs to symbols for readability
//  * 7. [Visualization & Output] Save results to a text file

nextflow.enable.dsl = 2

process BIOC_FGSEA_PRERANKED_GSEA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("fgsea", "data.table", "ggplot2", "org.Mm.eg.db")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(fgsea)
    library(data.table)
    library(ggplot2)
    library(org.Mm.eg.db)
    
    # 1. Load gene ranks from file
    rnk.file <- "naive.vs.th1.rnk"
    ranks <- read.table(rnk.file, header=TRUE, colClasses = c("character", "numeric"))
    ranks <- setNames(ranks\$t, ranks\$ID)
    
    # 2. Load pathways from GMT file
    gmt.file <- "mouse.reactome.gmt"
    pathways <- gmtPathways(gmt.file)
    
    # 3. Run fgsea with specified size limits and p-value resolution
    # Run with eps = 0.0 for exact/more accurate p-value estimation
    fgseaRes <- fgsea(pathways = pathways, stats = ranks, eps = 0.0, minSize = 15, maxSize = 500)
    
    # 4. Plot enrichment curves
    # Identify a valid pathway to plot (preferring Programmed Cell Death if present)
    target_pathway <- "5991130_Programmed_Cell_Death"
    if (!(target_pathway %in% names(pathways))) {
      matches <- grep("5991130|Programmed_Cell_Death", names(pathways), value = TRUE)
      if (length(matches) > 0) {
        target_pathway <- matches[1]
      } else {
        target_pathway <- names(pathways)[1]
      }
    }
    
    p_enrich <- plotEnrichment(pathways[[target_pathway]], ranks) + labs(title=target_pathway)
    ggsave("enrichment_plot.pdf", plot = p_enrich, width = 7, height = 5)
    
    # 5. Collapse redundant pathways to identify independent main pathways
    # Use tryCatch to handle cases where no pathways pass the strict padj < 0.01 threshold
    collapsedPathways <- tryCatch({
      collapsePathways(fgseaRes[order(pval)][padj < 0.01], pathways, ranks)
    }, error = function(e) {
      message("No pathways significant at padj < 0.01, trying padj < 0.05")
      collapsePathways(fgseaRes[order(pval)][padj < 0.05], pathways, ranks)
    })
    
    mainPathways <- fgseaRes[pathway %in% collapsedPathways\$mainPathways][order(-NES), pathway]
    
    # 6. Plot GSEA table for the main independent pathways
    pdf("gsea_table_plot.pdf", width = 12, height = 8)
    # Limit to top 30 pathways to ensure the plot remains readable
    plot_pathways <- head(mainPathways, 30)
    plotGseaTable(pathways[plot_pathways], ranks, fgseaRes, gseaParam = 0.5)
    dev.off()
    
    # 7. Save full results to a text file
    fwrite(fgseaRes, file="fgseaRes.txt", sep="\t", sep2=c("", " ", ""))
    
    # 8. Map gene IDs to symbols for readability and save main pathways
    fgseaResMain <- fgseaRes[match(mainPathways, pathway)]
    fgseaResMain[, leadingEdge := mapIdsList(x=org.Mm.eg.db, keys=leadingEdge, keytype="ENTREZID", column="SYMBOL")]
    
    fwrite(fgseaResMain, file="fgseaResMain.txt", sep="\t", sep2=c("", " ", ""))
    
    # Save RDS objects for downstream analysis
    saveRDS(fgseaRes, "fgseaRes.rds")
    saveRDS(fgseaResMain, "fgseaResMain.rds")

    writeLines(c(
        '"BIOC_FGSEA_PRERANKED_GSEA":',
        paste0('    fgsea: ', as.character(packageVersion('fgsea')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_preranked_gsea.csv versions.yml
    """
}

workflow BIOC_FGSEA_PRERANKED_GSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ naive.vs.th1.rnk, mouse.reactome.gmt ] ]

    main:
    BIOC_FGSEA_PRERANKED_GSEA(ch_input)

    emit:
    tables   = BIOC_FGSEA_PRERANKED_GSEA.out.tables
    plots    = BIOC_FGSEA_PRERANKED_GSEA.out.plots
    objects  = BIOC_FGSEA_PRERANKED_GSEA.out.objects
    versions = BIOC_FGSEA_PRERANKED_GSEA.out.versions
}
