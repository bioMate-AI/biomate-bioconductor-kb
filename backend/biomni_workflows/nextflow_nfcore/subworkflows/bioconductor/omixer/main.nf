#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Omixer — multivariate_sample_randomization
// Randomize samples across multi-well plates to minimize correlation between biological factors and technical batches, with support for sample blocking, well mask
// Input: sampleList.Rdata
// Container: quay.io/biocontainers/bioconductor-omixer:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Omixer, dplyr, forcats, ggplot2, stringr, tibble
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define the biological variables to randomize across batches. 2. Create a well mask to reserve specific wells for control samples. 

nextflow.enable.dsl = 2

process BIOC_OMIXER_MULTIVARIATE_SAMPLE_RANDOMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    library(Omixer)
    library(tibble)
    library(forcats)
    library(stringr)
    library(dplyr)
    library(ggplot2)
    
    # 1. Load the input sample list
    # The file 'sampleList.Rdata' must exist in the working directory and contain the 'sampleList' object.
    if (!file.exists("sampleList.Rdata")) {
      stop("Error: 'sampleList.Rdata' not found in the working directory.")
    }
    load("sampleList.Rdata")
    
    # 2. Define the biological variables to randomize across batches
    randVars <- c("tissue", "sex", "age", "bmi", "date")
    
    # 3. Create a well mask to reserve specific wells for control samples
    mask <- rep(c(rep(0, 88), rep(1, 8)), 7)
    
    # 4. Run multivariate randomization using omixerRand to find the optimal layout
    omixerLayout <- omixerRand(sampleList, sampleId="sampleId", 
        block="block", iterNum=100, wells=96, div="col", plateNum=7, 
        randVars=randVars, mask=mask)
    
    # Save the initial randomized layout
    write.csv(omixerLayout, "omixer_layout_rand.csv", row.names = FALSE)
    saveRDS(omixerLayout, "omixer_layout_rand.rds")
    
    # 5. Recreate the exact randomized layout using the saved random seed with omixerSpecific
    if (file.exists("randomSeed.Rdata")) {
      load("randomSeed.Rdata")
      .GlobalEnv\$.Random.seed <- randomSeed
      
      omixerLayoutSpecific <- omixerSpecific(sampleList, sampleId="sampleId",
          block="block", wells=96, div="col", plateNum=7,
          randVars=randVars, mask=mask)
      
      # Save the specific recreated layout
      write.csv(omixerLayoutSpecific, "omixer_layout_specific.csv", row.names = FALSE)
      saveRDS(omixerLayoutSpecific, "omixer_layout_specific.rds")
    } else {
      warning("randomSeed.Rdata was not found; skipping omixerSpecific step.")
    }
    
    # 6. Generate lab-friendly PDF sample sheets using omixerSheet
    # This function automatically writes a PDF file (typically 'sampleSheet.pdf') to the working directory.
    omixerSheet(omixerLayout, group="tissue")

    writeLines(c(
        '"BIOC_OMIXER_MULTIVARIATE_SAMPLE_RANDOMIZATION":',
        paste0('    Omixer: ', as.character(packageVersion('Omixer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multivariate_sample_randomization.csv versions.yml
    """
}

workflow BIOC_OMIXER_MULTIVARIATE_SAMPLE_RANDOMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleList.Rdata ] ]

    main:
    BIOC_OMIXER_MULTIVARIATE_SAMPLE_RANDOMIZATION(ch_input)

    emit:
    tables   = BIOC_OMIXER_MULTIVARIATE_SAMPLE_RANDOMIZATION.out.tables
    plots    = BIOC_OMIXER_MULTIVARIATE_SAMPLE_RANDOMIZATION.out.plots
    objects  = BIOC_OMIXER_MULTIVARIATE_SAMPLE_RANDOMIZATION.out.objects
    versions = BIOC_OMIXER_MULTIVARIATE_SAMPLE_RANDOMIZATION.out.versions
}
