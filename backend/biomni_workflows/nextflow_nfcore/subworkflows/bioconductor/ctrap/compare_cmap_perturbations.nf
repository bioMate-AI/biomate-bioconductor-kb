#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cTRAP — compare_cmap_perturbations
// Compare user's differential expression signature against CMap perturbations to identify similar or opposing cellular perturbations.
// Input: diffExprStat
// Container: quay.io/biocontainers/bioconductor-ctrap:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cTRAP
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load CMap metadata
//  * 2. [Core Analysis] Filter CMap metadata for specific cell lines and perturbation types
//  * 3. [Input & Preparation] Load and prepare CMap perturbation data
//  * 4. [Core Analysis] Compare differential expression signature against CMap perturbations
//  * 5. [Visualization & Output] Visualize perturbation similarity rankings and individual relationships

nextflow.enable.dsl = 2

process BIOC_CTRAP_COMPARE_CMAP_PERTURBATIONS {
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
    .bm_deps <- c("cTRAP")
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
            
            # Load required library
            library(cTRAP)
            
            # 1. Load User Input
            # The pipeline expects 'diffExprStat' (named numeric vector of t-statistics, where names are gene symbols)
            if (file.exists("diffExprStat.rds")) {
              diffExprStat <- readRDS("diffExprStat.rds")
            } else if (file.exists("diffExprStat")) {
              diffExprStat <- readRDS("diffExprStat")
            } else if (file.exists("diffExprStat.csv")) {
              df <- read.csv("diffExprStat.csv", row.names = 1)
              diffExprStat <- setNames(df[[1]], rownames(df))
            } else {
              stop("Required input file 'diffExprStat' (RDS or CSV format) not found in the working directory.")
            }
            
            # 2. Load CMap Metadata
            cmapMetadata <- loadCMapData("cmapMetadata.txt", type="metadata")
            
            # Summarise conditions
            getCMapConditions(cmapMetadata)
            getCMapConditions(
                cmapMetadata,
                perturbationType="Consensus signature from shRNAs targeting the same gene")
            
            # 3. Filter and Prepare CMap Perturbations
            cmapMetadataKD <- filterCMapMetadata(
                cmapMetadata,
                cellLine="HepG2",
                perturbationType="Consensus signature from shRNAs targeting the same gene")
            
            cmapPerturbationsKD <- prepareCMapPerturbations(
                metadata=cmapMetadataKD, zscores="cmapZscores.gctx",
                geneInfo="cmapGeneInfo.txt", ask=FALSE)
            
            # 4. Compare Differential Expression Signature against CMap Perturbations
            compareKD <- rankSimilarPerturbations(diffExprStat, cmapPerturbationsKD)
            
            # Save the comparison object
            saveRDS(compareKD, "compareKD.rds")
            
            # Print rankings to standard output
            cat("--- Top 10 Spearman Rank ---\n")
            print(head(compareKD[order(spearman_rank)], n=10))
            
            cat("--- Top Pearson Rank ---\n")
            print(head(compareKD[order(pearson_rank)]))
            
            cat("--- Top GSEA Rank ---\n")
            print(head(compareKD[order(GSEA_rank)]))
            
            cat("--- Top Rank Product Rank ---\n")
            print(head(compareKD[order(rankProduct_rank)]))
            
            # 5. Visualize Perturbation Similarity Rankings and Individual Relationships
            pdf("cmap_perturbation_plots.pdf", width=10, height=8)
            
            # Plot list of compared perturbations
            plot(compareKD, "spearman", n=c(10, 3))
            plot(compareKD, "pearson")
            plot(compareKD, "gsea")
            plot(compareKD, "rankProduct")
            
            # Information on perturbations
            if (nrow(compareKD) > 0) {
                topPerturbation <- compareKD[order(rankProduct_rank)][1, 1]
                cat("--- Information on top perturbation ---\n")
                print(compareKD, topPerturbation)
            } else {
                cat("No perturbations found in results.\n")
            }
            
            cat("--- Information on top 10 most similar perturbations ---\n")
            print(compareKD[order(rankProduct_rank)], 1:10)
            
            # Convert to table and save
            table <- as.table(compareKD)
            write.csv(as.data.frame(table), "compareKD_table.csv", row.names=FALSE)
            
            cat("--- Table Head ---\n")
            print(head(table))
            
            # Inspect attributes
            names(attributes(compareKD))
            attr(compareKD, "metadata")
            attr(compareKD, "geneInfo")
            
            # Plot relationship with specific perturbations if available
            if (nrow(compareKD) > 0) {
                plot(compareKD, topPerturbation, "spearman")
                plot(compareKD, topPerturbation, "pearson")
                plot(compareKD, topPerturbation, "gsea")
            }
            
            dev.off()
            
            cat("Pipeline completed successfully. Outputs saved to 'compareKD.rds', 'compareKD_table.csv', and 'cmap_perturbation_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_CTRAP_COMPARE_CMAP_PERTURBATIONS":',
        paste0('    cTRAP: ', as.character(packageVersion('cTRAP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_cmap_perturbations.csv versions.yml
    """
}

workflow BIOC_CTRAP_COMPARE_CMAP_PERTURBATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ diffExprStat ] ]

    main:
    BIOC_CTRAP_COMPARE_CMAP_PERTURBATIONS(ch_input)

    emit:
    tables   = BIOC_CTRAP_COMPARE_CMAP_PERTURBATIONS.out.tables
    plots    = BIOC_CTRAP_COMPARE_CMAP_PERTURBATIONS.out.plots
    objects  = BIOC_CTRAP_COMPARE_CMAP_PERTURBATIONS.out.objects
    versions = BIOC_CTRAP_COMPARE_CMAP_PERTURBATIONS.out.versions
}
