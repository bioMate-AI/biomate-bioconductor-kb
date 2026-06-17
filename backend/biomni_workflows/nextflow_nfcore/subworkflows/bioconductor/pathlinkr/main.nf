#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathlinkR — rna_seq_downstream_analysis
// Visualize differentially expressed genes and perform pathway enrichment analysis on RNA-Seq results.
// Input: rnaseq_results.rds
// Container: quay.io/biocontainers/bioconductor-pathlinkr:1.6.0--r45hdfd78af_0
// R packages: dplyr, pathlinkR
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, pathlinkR
// Visualizations: volcano plot, heatmap, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate a volcano plot using eruption()
//  * 2. [Visualization & Output] Plot fold changes across comparisons using plotFoldChange()
//  * 3. [Core Analysis] Perform pathway enrichment using pathwayEnrichment()
//  * 4. [Visualization & Output] Plot pathway enrichment results using pathwayPlots()

nextflow.enable.dsl = 2

process BIOC_PATHLINKR_RNA_SEQ_DOWNSTREAM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("dplyr", "pathlinkR")
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
    library(dplyr)
    library(pathlinkR)
    
    # -----------------------------------------------------------------------------
    # 0. Load User Input
    # -----------------------------------------------------------------------------
    # Read the user-provided RDS file containing the list of DESeq2 results data frames.
    # We name the object 'exampleDESeqResults' to seamlessly match the documented code.
    exampleDESeqResults <- readRDS("rnaseq_results.rds")
    
    # -----------------------------------------------------------------------------
    # 1. Generate a volcano plot using eruption()
    # -----------------------------------------------------------------------------
    pdf("volcano_plot.pdf", width = 8, height = 6)
    eruption(
        rnaseqResult=exampleDESeqResults[[1]],
        title=names(exampleDESeqResults[1])
    )
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 2. Plot fold changes across comparisons using plotFoldChange()
    # -----------------------------------------------------------------------------
    pdf("fold_change_heatmap.pdf", width = 10, height = 8)
    plotFoldChange(
        inputList=exampleDESeqResults,
        pathName="Interferon alpha/beta signaling"
    )
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 3. Perform pathway enrichment using pathwayEnrichment()
    # -----------------------------------------------------------------------------
    # Run Sigora pathway enrichment
    enrichedResultsSigora <- pathwayEnrichment(
        inputList=exampleDESeqResults,
        analysis="sigora",
        filterInput=TRUE,
        gpsRepo="default"
    )
    
    # Run Hallmark pathway enrichment
    enrichedResultsHm <- pathwayEnrichment(
        inputList=exampleDESeqResults,
        analysis="hallmark",
        filterInput=TRUE,
        split=TRUE
    )
    
    # Save enrichment results to RDS and CSV files
    saveRDS(enrichedResultsSigora, "enriched_results_sigora.rds")
    saveRDS(enrichedResultsHm, "enriched_results_hallmark.rds")
    
    # Convert to data frame and drop the 'genes' list column for clean CSV writing
    if (inherits(enrichedResultsSigora, "data.frame")) {
        sigora_df <- enrichedResultsSigora
        if ("genes" %in% colnames(sigora_df)) {
            sigora_df\$genes <- sapply(sigora_df\$genes, function(x) paste(x, collapse = ";"))
        }
        write.csv(sigora_df, "enriched_results_sigora.csv", row.names = FALSE)
    }
    
    if (inherits(enrichedResultsHm, "data.frame")) {
        hm_df <- enrichedResultsHm
        if ("genes" %in% colnames(hm_df)) {
            hm_df\$genes <- sapply(hm_df\$genes, function(x) paste(x, collapse = ";"))
        }
        write.csv(hm_df, "enriched_results_hallmark.csv", row.names = FALSE)
    }
    
    # -----------------------------------------------------------------------------
    # 4. Plot pathway enrichment results using pathwayPlots()
    # -----------------------------------------------------------------------------
    pdf("pathway_enrichment_plots.pdf", width = 12, height = 10)
    pathwayPlots(
        pathwayEnrichmentResults=enrichedResultsSigora,
        columns=2
    )
    dev.off()

    writeLines(c(
        '"BIOC_PATHLINKR_RNA_SEQ_DOWNSTREAM_ANALYSIS":',
        paste0('    pathlinkR: ', as.character(packageVersion('pathlinkR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_downstream_analysis.csv versions.yml
    """
}

workflow BIOC_PATHLINKR_RNA_SEQ_DOWNSTREAM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rnaseq_results.rds ] ]

    main:
    BIOC_PATHLINKR_RNA_SEQ_DOWNSTREAM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PATHLINKR_RNA_SEQ_DOWNSTREAM_ANALYSIS.out.tables
    plots    = BIOC_PATHLINKR_RNA_SEQ_DOWNSTREAM_ANALYSIS.out.plots
    objects  = BIOC_PATHLINKR_RNA_SEQ_DOWNSTREAM_ANALYSIS.out.objects
    versions = BIOC_PATHLINKR_RNA_SEQ_DOWNSTREAM_ANALYSIS.out.versions
}
