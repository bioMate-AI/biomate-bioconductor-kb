#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normr — enrichment_regimes
// Identify multiple enrichment regimes (e.g., broad domains and sharp peaks) in a ChIP-seq experiment over control.
// Input: ChIP.bam, Control.bam
// Container: quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0
// Requires: Rsamtools, normr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Call multiple enrichment regimes using regimeR() with a specified number of models
//  * 2. [Visualization & Output] Analyze results using summary()
//  * 3. [Visualization & Output] Export the called regimes to BED format using exportR()

nextflow.enable.dsl = 2

process BIOC_NORMR_ENRICHMENT_REGIMES {
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
    .bm_deps <- c("Rsamtools", "normr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
    # Load required libraries
    library(normr)
    library(Rsamtools)
    
    # Define input files
    chip_bam <- "ChIP.bam"
    control_bam <- "Control.bam"
    
    # Check if input files exist
    if (!file.exists(chip_bam) || !file.exists(control_bam)) {
      stop("Required input files 'ChIP.bam' and/or 'Control.bam' are missing in the working directory.")
    }
    
    # Extract genome information from the BAM header for robustness
    message("Extracting genome information from BAM header...")
    bam_header <- Rsamtools::scanBamHeader(chip_bam)
    targets <- bam_header[[1]]\$targets
    if (length(targets) == 0) {
      stop("No target sequences found in BAM header.")
    }
    genome <- data.frame(
      chrom = names(targets),
      size = as.numeric(targets),
      stringsAsFactors = FALSE
    )
    
    # ==================== DOCUMENTED CODE ====================
    message("Running regimeR for ChIP...")
    chipRegimes <- regimeR(treatment = chip_bam,
                           control   = control_bam,
                           genome    = genome,
                           models    = 3,
                           verbose   = FALSE)
    summary(chipRegimes)
    
    exportR(chipRegimes, filename = "chipRegimes.bed", type = "bed", fdr=0.05)
    # ================== END DOCUMENTED CODE ==================
    
    # Save RDS objects of the regimes for downstream analysis
    message("Saving results to RDS...")
    saveRDS(chipRegimes, "chipRegimes.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_NORMR_ENRICHMENT_REGIMES":',
        paste0('    normr: ', as.character(packageVersion('normr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichment_regimes.csv versions.yml
    """
}

workflow BIOC_NORMR_ENRICHMENT_REGIMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ChIP.bam, Control.bam ] ]

    main:
    BIOC_NORMR_ENRICHMENT_REGIMES(ch_input)

    emit:
    tables   = BIOC_NORMR_ENRICHMENT_REGIMES.out.tables
    plots    = BIOC_NORMR_ENRICHMENT_REGIMES.out.plots
    objects  = BIOC_NORMR_ENRICHMENT_REGIMES.out.objects
    versions = BIOC_NORMR_ENRICHMENT_REGIMES.out.versions
}
