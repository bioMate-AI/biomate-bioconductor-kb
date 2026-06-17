#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dmrseq — dmr_simulation
// Split samples from the same condition into artificial groups and spike in in silico DMRs to assess the sensitivity and specificity of DMR detection.
// Input: bs_object.rds
// Container: quay.io/biocontainers/bioconductor-dmrseq:1.30.0--r45hdfd78af_0
// R packages: GenomicRanges, bsseq, dmrseq
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, bsseq, dmrseq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Reorder or subset samples to create a null comparison
//  * 2. [Core Analysis] Run simDMRs to generate a simulated BSseq object with spiked-in DMRs
//  * 3. [Core Analysis] Retrieve coordinates and effect sizes of the simulated DMRs

nextflow.enable.dsl = 2

process BIOC_DMRSEQ_DMR_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "bsseq", "dmrseq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(dmrseq)
    library(bsseq)
    library(GenomicRanges)
    
    # Read user input
    if (!file.exists("bs_object.rds")) {
      stop("Error: Input file 'bs_object.rds' not found in the working directory.")
    }
    
    BS.chr21 <- readRDS("bs_object.rds")
    
    # Ensure it is a BSseq object
    if (!inherits(BS.chr21, "BSseq")) {
      stop("Error: The object loaded from 'bs_object.rds' is not of class 'BSseq'.")
    }
    
    # Reorder samples to create a null comparison.
    # We attempt to use the exact documented subsetting if dimensions allow,
    # otherwise we fall back to available dimensions.
    if (nrow(BS.chr21) >= 20000 && ncol(BS.chr21) >= 4) {
      BS.null <- BS.chr21[1:20000, c(1, 3, 2, 4)]
    } else {
      warning("Input BSseq object is smaller than 20000x4. Adapting subsetting to available dimensions.")
      loci_to_use <- seq_len(min(20000, nrow(BS.chr21)))
      if (ncol(BS.chr21) >= 4) {
        sample_idx <- c(1, 3, 2, 4)
      } else {
        sample_idx <- seq_len(ncol(BS.chr21))
      }
      BS.null <- BS.chr21[loci_to_use, sample_idx]
    }
    
    # Add 100 DMRs using the exact documented function call and arguments
    BS.chr21.sim <- simDMRs(bs=BS.null, num.dmrs=100)
    
    # Display simulated object details as in the documented code
    show(BS.chr21.sim\$bs)
    
    # Display coordinates of spiked-in DMRs
    show(BS.chr21.sim\$gr.dmrs)
    
    # Display effect sizes
    head(BS.chr21.sim\$delta)
    
    # Save meaningful results to output files
    # 1. Save the simulated BSseq object
    saveRDS(BS.chr21.sim\$bs, file = "simulated_bs_object.rds")
    
    # 2. Save the coordinates of spiked-in DMRs
    dmr_df <- as.data.frame(BS.chr21.sim\$gr.dmrs)
    write.csv(dmr_df, file = "simulated_dmr_coords.csv", row.names = FALSE)
    saveRDS(BS.chr21.sim\$gr.dmrs, file = "simulated_dmr_coords.rds")
    
    # 3. Save the effect sizes and other simulation metadata
    sim_metadata <- data.frame(
      dmr_index = seq_along(BS.chr21.sim\$delta),
      delta = BS.chr21.sim\$delta,
      mean_coverage = BS.chr21.sim\$dmr.mncov,
      num_cpgs = BS.chr21.sim\$dmr.L
    )
    write.csv(sim_metadata, file = "simulated_dmr_metadata.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_DMRSEQ_DMR_SIMULATION":',
        paste0('    dmrseq: ', as.character(packageVersion('dmrseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmr_simulation.csv versions.yml
    """
}

workflow BIOC_DMRSEQ_DMR_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bs_object.rds ] ]

    main:
    BIOC_DMRSEQ_DMR_SIMULATION(ch_input)

    emit:
    tables   = BIOC_DMRSEQ_DMR_SIMULATION.out.tables
    plots    = BIOC_DMRSEQ_DMR_SIMULATION.out.plots
    objects  = BIOC_DMRSEQ_DMR_SIMULATION.out.objects
    versions = BIOC_DMRSEQ_DMR_SIMULATION.out.versions
}
