#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cghMCR — minimum_common_regions_mcr
// Identify Minimum Common Regions (MCRs) of copy number alteration across samples from segmented data.
// Input: segData
// Container: quay.io/biocontainers/bioconductor-cghmcr:1.68.0--r45hdfd78af_0
// Requires: DNAcopy, cghMCR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize a cghMCR object with segmentation data and threshold parameters
//  * 2. [Core Analysis] Identify MCRs using the MCR function
//  * 3. [Core Analysis] Append probe IDs to the identified MCRs using mergeMCRProbes

nextflow.enable.dsl = 2

process BIOC_CGHMCR_MINIMUM_COMMON_REGIONS_MCR {
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
        library(cghMCR)
        library(DNAcopy)
        
        # ==========================================
        # 1. Read User Input
        # ==========================================
        # The pipeline expects 'segData' (a segmented data object from DNAcopy)
        # in the working directory, saved as an RDS file.
        if (file.exists("segData")) {
          segData <- readRDS("segData")
        } else if (file.exists("segData.rds")) {
          segData <- readRDS("segData.rds")
        } else {
          stop("Required input file 'segData' (RDS format) not found in the working directory.")
        }
        
        # ==========================================
        # 2. Identify Minimum Common Regions (MCRs)
        # ==========================================
        # Initialize a cghMCR object with segmentation data and threshold parameters
        cghmcr <- cghMCR(segData, gapAllowed = 500, alteredLow = 0.9,
         alteredHigh = 0.9, recurrence = 100)
        
        # Identify MCRs using the MCR function
        mcrs <- MCR(cghmcr)
        
        # Display the first few identified MCRs
        cat("--- Identified MCRs (First few rows) ---\n")
        print(head(cbind(mcrs[, c("chromosome", "status", "mcr.start", "mcr.end", 
                             "samples")])))
        
        # Save all identified MCRs to a CSV file
        write.csv(mcrs, "all_identified_mcrs.csv", row.names = FALSE)
        saveRDS(cghmcr, "cghmcr_object.rds")
        saveRDS(mcrs, "mcrs_object.rds")
        
        # ==========================================
        # 3. Append Probe IDs to Identified MCRs
        # ==========================================
        # Append probe IDs to the identified MCRs
        # Wrapped in a tryCatch block to handle potential errors during merging
        tryCatch({
          mcrs <- mergeMCRProbes(mcrs, as.data.frame(segData[["data"]]))
          
          cat("\n--- MCRs with Merged Probes ---\n")
          print(head(cbind(mcrs[, c("chromosome", "status", "mcr.start", "mcr.end", 
                               "probes")])))
          
          # Save the MCRs with probe IDs to a CSV file
          write.csv(mcrs, "mcrs_with_probes.csv", row.names = FALSE)
        }, error = function(e) {
          warning("Could not merge MCR probes. Error message: ", e\$message)
        })
        
        cat("\nPipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_CGHMCR_MINIMUM_COMMON_REGIONS_MCR":',
        paste0('    cghMCR: ', as.character(packageVersion('cghMCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_minimum_common_regions_mcr.csv versions.yml
    """
}

workflow BIOC_CGHMCR_MINIMUM_COMMON_REGIONS_MCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ segData ] ]

    main:
    BIOC_CGHMCR_MINIMUM_COMMON_REGIONS_MCR(ch_input)

    emit:
    tables   = BIOC_CGHMCR_MINIMUM_COMMON_REGIONS_MCR.out.tables
    plots    = BIOC_CGHMCR_MINIMUM_COMMON_REGIONS_MCR.out.plots
    objects  = BIOC_CGHMCR_MINIMUM_COMMON_REGIONS_MCR.out.objects
    versions = BIOC_CGHMCR_MINIMUM_COMMON_REGIONS_MCR.out.versions
}
