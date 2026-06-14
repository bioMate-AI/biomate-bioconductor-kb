#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ACE — batch_post_analysis
// Automate segment adjustment and variant linking across a large dataset using a pre-defined models file.
// Input: Segmented QDNAseq object, models.tsv
// Container: quay.io/biocontainers/bioconductor-ace:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ACE, Biobase, QDNAseq, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the user-provided segmented QDNAseq object
//  * 2. [Input & Preparation] Run postanalysisloop to batch-process all samples

nextflow.enable.dsl = 2

process BIOC_ACE_BATCH_POST_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("ACE", "QDNAseq", "Biobase", "ggplot2")
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
    library(ACE)
    library(QDNAseq)
    library(Biobase)
    library(ggplot2)
    
    # Define input directory (current working directory where user files are located)
    inputdir <- "."
    
    # --- Read the user-provided segmented QDNAseq object ---
    # The pipeline expects the segmented QDNAseq object to be saved as "segmented_object.rds"
    object <- readRDS("segmented_object.rds")
    
    # Read and verify the models.tsv file from the working directory
    models <- read.table("models.tsv", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Define the output directory for the loop results
    outputdir <- "./output_loop"
    if (!dir.exists(outputdir)) {
      dir.create(outputdir, recursive = TRUE)
    }
    
    # --- Run postanalysisloop to batch-process all samples ---
    # This function automatically reads models.tsv and the sample-specific mutation files
    # (e.g., sample1_mutations.tsv, sample2_mutations.tsv) from the inputdir.
    results <- postanalysisloop(
      object, 
      inputdir = inputdir, 
      postfix = "_mutations",
      chrindex = 2, 
      posindex = 3, 
      freqindex = 4,
      outputdir = outputdir, 
      imagetype = 'png'
    )
    
    # Save the returned list of plots and models to an RDS file
    saveRDS(results, "post_analysis_results.rds")

    writeLines(c(
        '"BIOC_ACE_BATCH_POST_ANALYSIS":',
        paste0('    ACE: ', as.character(packageVersion('ACE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_post_analysis.csv versions.yml
    """
}

workflow BIOC_ACE_BATCH_POST_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Segmented QDNAseq object, models.tsv ] ]

    main:
    BIOC_ACE_BATCH_POST_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ACE_BATCH_POST_ANALYSIS.out.tables
    plots    = BIOC_ACE_BATCH_POST_ANALYSIS.out.plots
    objects  = BIOC_ACE_BATCH_POST_ANALYSIS.out.objects
    versions = BIOC_ACE_BATCH_POST_ANALYSIS.out.versions
}
