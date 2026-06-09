#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOTHiC — gothic_hicup_pipeline
// Identify significant genomic interactions from pre-processed and filtered HiCUP output.
// Input: fileName, restrictionFile
// Container: quay.io/biocontainers/bioconductor-gothic:1.46.0--r45hdfd78af_0
// Requires: GOTHiC
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run the cumulative binomial test on HiCUP output using GOTHiChicup

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
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
    # 1. Save the full data frame as a CSV table
    write.csv(binom, file = "gothic_hicup_results.csv", row.names = FALSE)
    
    # 2. Save the results as an RDS object for downstream R analysis
    saveRDS(binom, file = "gothic_hicup_results.rds")
    
    # 3. Generate and save the p-value density plot to assess experiment quality
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
