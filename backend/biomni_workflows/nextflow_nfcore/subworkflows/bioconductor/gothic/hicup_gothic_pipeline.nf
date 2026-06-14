#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gothic — hicup_gothic_pipeline
// Identify significant genomic interactions from HiCUP preprocessed and filtered BAM/SAM files using GOTHiChicup.
// Input: fileName, restrictionFile
// Container: quay.io/biocontainers/bioconductor-gothic:1.46.0--r45hdfd78af_0
// R packages: GOTHiC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOTHIC_HICUP_GOTHIC_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gothic:1.46.0--r45hdfd78af_0"

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
    .bm_deps <- c("GOTHiC")
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
    library(GOTHiC)
    
    # Define input file paths from the working directory as specified
    fileName <- "fileName"
    restrictionFile <- "restrictionFile"
    
    # Check if input files exist before running
    if (!file.exists(fileName)) {
      stop(paste("Required input file 'fileName' (HiCUP output) not found in the working directory:", getwd()))
    }
    if (!file.exists(restrictionFile)) {
      stop(paste("Required input file 'restrictionFile' (restriction fragment file) not found in the working directory:", getwd()))
    }
    
    # Run the binomial test on HiCUP output using GOTHiChicup
    message("Running GOTHiChicup pipeline...")
    binom=GOTHiChicup(fileName, sampleName='lymphoid_chr20', res=1000000, 
    restrictionFile, cistrans='all', parallel=FALSE, cores=NULL)
    
    # Write meaningful output files
    message("Writing output files...")
    
    # --- Save the complete interactions table as a CSV ---
    write.csv(binom, file = "significant_interactions.csv", row.names = FALSE)
    
    # --- Save the result as an RDS object for downstream R analysis ---
    saveRDS(binom, file = "significant_interactions.rds")
    
    # --- Generate and save the p-value density plot if p-values ---
    if (!is.null(binom) && "pvalue" %in% colnames(binom)) {
      pdf("pvalue_distribution.pdf", width = 6, height = 6)
      plot(density(binom\$pvalue), 
           main = "P-value distribution of genomic interactions", 
           xlab = "pvalue", 
           col = "blue", 
           las = 1)
      dev.off()
      message("P-value distribution plot saved to 'pvalue_distribution.pdf'")
    }
    
    message("Pipeline completed successfully. Outputs saved to 'significant_interactions.csv' and 'significant_interactions.rds'.")

    writeLines(c(
        '"BIOC_GOTHIC_HICUP_GOTHIC_PIPELINE":',
        paste0('        gothic: ', as.character(packageVersion("gothic")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicup_gothic_pipeline.csv versions.yml
    """
}

workflow BIOC_GOTHIC_HICUP_GOTHIC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fileName, restrictionFile ] ]

    main:
    BIOC_GOTHIC_HICUP_GOTHIC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GOTHIC_HICUP_GOTHIC_PIPELINE.out.tables
    plots    = BIOC_GOTHIC_HICUP_GOTHIC_PIPELINE.out.plots
    objects  = BIOC_GOTHIC_HICUP_GOTHIC_PIPELINE.out.objects
    versions = BIOC_GOTHIC_HICUP_GOTHIC_PIPELINE.out.versions
}
