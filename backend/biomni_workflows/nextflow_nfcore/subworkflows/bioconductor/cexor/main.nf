#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cexor — chip_exo_peak_calling
// Call reproducible peak-pairs and identify protein-DNA binding events and centers from ChIP-exo replicate BAM files, followed by visualization.
// Input: rep1.bam, rep2.bam, rep3.bam
// Container: quay.io/biocontainers/bioconductor-cexor:1.48.0--r45hdfd78af_0
// R packages: CexoR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CEXOR_CHIP_EXO_PEAK_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cexor:1.48.0--r45hdfd78af_0"

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
    .bm_deps <- c("CexoR")
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
    
    # Load required library
    library(CexoR)
    
    # Define input files as specified by the user
    r1 <- "rep1.bam"
    r2 <- "rep2.bam"
    r3 <- "rep3.bam"
    
    # Verify that the input files exist in the working directory
    if (!file.exists(r1) || !file.exists(r2) || !file.exists(r3)) {
      stop("Error: One or more of the required input files (rep1.bam, rep2.bam, rep3.bam) are missing from the working directory.")
    }
    
    # Call reproducible peak-pairs using the cexor function
    # Keeping arguments exactly as documented
    peak_pairs <- cexor(bam=c(r1, r2, r3), chrN="chr2", chrL=1e6, idr=0.01, N=3e4, p=1e-12)
    
    # Extract reproducible binding events and centers
    binding_events <- peak_pairs\$bindingEvents
    binding_centres <- peak_pairs\$bindingCentres
    
    # Save the complete peak_pairs object to an RDS file
    saveRDS(peak_pairs, file = "peak_pairs.rds")
    
    # Export the GRanges objects to CSV files for downstream analysis
    write.csv(as.data.frame(binding_events), file = "binding_events.csv", row.names = FALSE)
    write.csv(as.data.frame(binding_centres), file = "binding_centres.csv", row.names = FALSE)
    
    # Plot the mean profile of lambda exonuclease stop sites and reads, and save to PDF
    pdf("cexor_profile_plot.pdf", width = 8, height = 6)
    plotcexor(bam=c(r1, r2, r3), peaks=peak_pairs, EXT=500)
    dev.off()

    writeLines(c(
        '"BIOC_CEXOR_CHIP_EXO_PEAK_CALLING":',
        paste0('        cexor: ', as.character(packageVersion("cexor")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chip_exo_peak_calling.csv versions.yml
    """
}

workflow BIOC_CEXOR_CHIP_EXO_PEAK_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rep1.bam, rep2.bam, rep3.bam ] ]

    main:
    BIOC_CEXOR_CHIP_EXO_PEAK_CALLING(ch_input)

    emit:
    tables   = BIOC_CEXOR_CHIP_EXO_PEAK_CALLING.out.tables
    plots    = BIOC_CEXOR_CHIP_EXO_PEAK_CALLING.out.plots
    objects  = BIOC_CEXOR_CHIP_EXO_PEAK_CALLING.out.objects
    versions = BIOC_CEXOR_CHIP_EXO_PEAK_CALLING.out.versions
}
