#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOTHiC — gothic_hicup_pipeline
// Identify significant genomic interactions from pre-processed and filtered HiCUP output.
// Input: fileName, restrictionFile
// Container: quay.io/biocontainers/bioconductor-gothic:1.46.0--r45hdfd78af_0
// R packages: GOTHiC
// Bioconductor: 3.20 | R: 4.4
// Requires: GOTHiC
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Save the full data frame as a CSV table
//  * 2. [Visualization & Output] Save the results as an RDS object for downstream R
//  * 3. [Visualization & Output] Generate and save the p-value density plot to assess

nextflow.enable.dsl = 2

process BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE {
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
    
    # Load required libraries
    library(GOTHiC)
    
    # Define input file paths in the working directory
    fileName <- "fileName"
    restrictionFile <- "restrictionFile"
    
    # Validate that the required input files exist
    if (!file.exists(fileName)) {
      stop(paste("Error: Input file 'fileName' (mapped and filtered reads from HiCUP) not found in the working directory:", getwd()))
    }
    
    if (!file.exists(restrictionFile)) {
      stop(paste("Error: Input file 'restrictionFile' (digest/restriction fragment file) not found in the working directory:", getwd()))
    }
    
    # Run the cumulative binomial test on HiCUP output using GOTHiChicup
    # Keeping the exact function call and arguments from the documented code
    binom=GOTHiChicup(fileName, sampleName='lymphoid_chr20', res=1000000, 
    restrictionFile, cistrans='all', parallel=FALSE, cores=NULL)
    
    # Save the meaningful results to output files
    # --- Save the full data frame as a CSV table ---
    write.csv(binom, file = "gothic_hicup_results.csv", row.names = FALSE)
    
    # --- Save the results as an RDS object for downstream R ---
    saveRDS(binom, file = "gothic_hicup_results.rds")
    
    # --- Generate and save the p-value density plot to assess ---
    pdf("gothic_pvalue_density.pdf", width = 6, height = 6)
    if (!is.null(binom) && nrow(binom) > 0) {
      # Determine the correct p-value column name (typically "pvalue" or "p-value")
      p_col <- grep("p.*val", colnames(binom), ignore.case = TRUE, value = TRUE)
      if (length(p_col) > 0) {
        plot(density(binom[[p_col[1]]], na.rm = TRUE), 
             main = "P-value distribution", 
             xlab = "pvalue", 
             col = "blue", 
             las = 1)
      } else {
        warning("Could not find a p-value column in the results to plot.")
      }
    } else {
      warning("Result data frame is empty; skipping density plot.")
    }
    dev.off()

    writeLines(c(
        '"BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE":',
        paste0('    GOTHiC: ', as.character(packageVersion('GOTHiC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gothic_hicup_pipeline.csv versions.yml
    """
}

workflow BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fileName, restrictionFile ] ]

    main:
    BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE.out.tables
    plots    = BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE.out.plots
    objects  = BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE.out.objects
    versions = BIOC_GOTHIC_GOTHIC_HICUP_PIPELINE.out.versions
}
