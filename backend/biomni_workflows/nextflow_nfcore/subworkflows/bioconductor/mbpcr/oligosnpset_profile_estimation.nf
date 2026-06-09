#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mBPCR — oligosnpset_profile_estimation
// Estimate copy number profiles directly from an oligoSnpSet object.
// Input: oligoSet
// Container: quay.io/biocontainers/bioconductor-mbpcr:1.64.0--r45hdfd78af_0
// Requires: mBPCR, oligoClasses
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the oligoSnpSet object
//  * 2. [Core Analysis] Estimate the copy number profile using estProfileWithMBPCRforOligoSnpSet
//  * 3. [Visualization & Output] Extract and plot the estimated copy number profile

nextflow.enable.dsl = 2

process BIOC_MBPCR_OLIGOSNPSET_PROFILE_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    library(mBPCR)
    library(oligoClasses)
    
    # 1. Load the oligoSnpSet object from the working directory
    if (file.exists("oligoSet")) {
      oligoSet <- readRDS("oligoSet")
    } else if (file.exists("oligoSet.rds")) {
      oligoSet <- readRDS("oligoSet.rds")
    } else {
      stop("Required input file 'oligoSet' or 'oligoSet.rds' not found in the working directory.")
    }
    
    # Dynamically determine a chromosome present in the dataset
    chr_to_use <- as.character(unique(chromosome(oligoSet))[1])
    
    # 2. Estimate the copy number profile using estProfileWithMBPCRforOligoSnpSet
    # Removed hardcoded rhoSquare to allow the function to estimate it optimally for arbitrary data
    r <- estProfileWithMBPCRforOligoSnpSet(oligoSet, sampleToBeAnalyzed=1, chrToBeAnalyzed=chr_to_use, maxProbeNumber=1000, ifLogRatio=0)
    
    # 3. Extract the estimated copy number profile
    cc <- r\$estPC
    cc1 <- cc[chromosome(cc) == chr_to_use, 1]
    
    # Save the full results object
    saveRDS(r, "mbpcr_profile_results.rds")
    
    # Save the extracted profile data to a CSV file
    df_out <- data.frame(
      Position = position(cc1),
      CopyNumber = copyNumber(cc1)
    )
    write.csv(df_out, paste0("estimated_profile_chr", chr_to_use, ".csv"), row.names = FALSE)
    
    # Plot and save the estimated copy number profile to a PDF
    pdf(paste0("copy_number_profile_chr", chr_to_use, ".pdf"), width = 7, height = 5)
    par(las=1)
    # Removed hardcoded ylim to prevent clipping of arbitrary user data
    plot(position(cc1), copyNumber(cc1), ylab="copy number", xlab="base position")
    dev.off()

    writeLines(c(
        '"BIOC_MBPCR_OLIGOSNPSET_PROFILE_ESTIMATION":',
        paste0('    mBPCR: ', as.character(packageVersion('mBPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oligosnpset_profile_estimation.csv versions.yml
    """
}

workflow BIOC_MBPCR_OLIGOSNPSET_PROFILE_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ oligoSet ] ]

    main:
    BIOC_MBPCR_OLIGOSNPSET_PROFILE_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_MBPCR_OLIGOSNPSET_PROFILE_ESTIMATION.out.tables
    plots    = BIOC_MBPCR_OLIGOSNPSET_PROFILE_ESTIMATION.out.plots
    objects  = BIOC_MBPCR_OLIGOSNPSET_PROFILE_ESTIMATION.out.objects
    versions = BIOC_MBPCR_OLIGOSNPSET_PROFILE_ESTIMATION.out.versions
}
