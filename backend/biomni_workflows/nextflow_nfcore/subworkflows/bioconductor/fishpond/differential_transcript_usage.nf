#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fishpond — differential_transcript_usage
// Test for differential transcript usage (DTU) by analyzing isoform proportions per gene across conditions.
// Input: coldata.csv, Salmon quantification directories
// Container: quay.io/biocontainers/bioconductor-fishpond:2.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, fishpond, tximeta
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read sample metadata
//  * 2. [Input & Preparation] Import quantification data using tximeta
//  * 3. [Input & Preparation] Scale inferential replicates
//  * 4. [Input & Preparation] Filter out low-expression features
//  * 5. [Input & Preparation] Compute isoform proportions per gene
//  * 6. [Input & Preparation] Run differential testing on isoform proportions using
//  * 7. [Input & Preparation] Write outputs

nextflow.enable.dsl = 2

process BIOC_FISHPOND_DIFFERENTIAL_TRANSCRIPT_USAGE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(tximeta)
        library(fishpond)
        
        # --- Read sample metadata ---
        coldata <- read.csv("coldata.csv")
        
        # --- Import quantification data using tximeta ---
        y <- tximeta(coldata)
        
        # --- Scale inferential replicates ---
        y <- scaleInfReps(y)
        
        # --- Filter out low-expression features ---
        y <- labelKeep(y)
        y <- y[mcols(y)\$keep,]
        
        # --- Compute isoform proportions per gene ---
        iso <- isoformProportions(y)
        
        # --- Run differential testing on isoform proportions using ---
        set.seed(1)
        iso <- swish(iso, x="condition")
        
        # --- Write outputs ---
        # Save the full SummarizedExperiment object with results
        saveRDS(iso, "dtu_isoform_proportions_results.rds")
        
        # Save the results table
        results_df <- as.data.frame(mcols(iso))
        write.csv(results_df, "dtu_swish_results.csv", row.names=TRUE)
        
        # Generate diagnostic plots
        pdf("dtu_plots.pdf", width=8, height=6)
        if ("pvalue" %in% colnames(results_df)) {
          hist(results_df\$pvalue, col="grey", 
               main="P-value Distribution (DTU Swish)", 
               xlab="p-value", ylab="Frequency")
        }
        tryCatch({
          plotMASwish(iso, alpha=0.05, main="MA Plot of Isoform Proportions")
        }, error=function(e) {
          warning("Could not generate MA plot: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_FISHPOND_DIFFERENTIAL_TRANSCRIPT_USAGE":',
        paste0('    fishpond: ', as.character(packageVersion('fishpond')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_transcript_usage.csv versions.yml
    """
}

workflow BIOC_FISHPOND_DIFFERENTIAL_TRANSCRIPT_USAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coldata.csv, Salmon quantification directories ] ]

    main:
    BIOC_FISHPOND_DIFFERENTIAL_TRANSCRIPT_USAGE(ch_input)

    emit:
    tables   = BIOC_FISHPOND_DIFFERENTIAL_TRANSCRIPT_USAGE.out.tables
    plots    = BIOC_FISHPOND_DIFFERENTIAL_TRANSCRIPT_USAGE.out.plots
    objects  = BIOC_FISHPOND_DIFFERENTIAL_TRANSCRIPT_USAGE.out.objects
    versions = BIOC_FISHPOND_DIFFERENTIAL_TRANSCRIPT_USAGE.out.versions
}
