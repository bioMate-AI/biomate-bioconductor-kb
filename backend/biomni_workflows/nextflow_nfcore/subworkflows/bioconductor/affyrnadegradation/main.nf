#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AffyRNADegradation — degradation_analysis_and_correction
// Assess RNA degradation, plot diagnostics, and correct probe positional bias in Affymetrix 3' expression microarrays.
// Input: AmpData, probeDists
// Container: quay.io/biocontainers/bioconductor-affyrnadegradation:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AffyRNADegradation, affy
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Visualize probe positional bias using a tongs plot
//  * 2. [Core Analysis] Perform RNA degradation analysis and correction
//  * 3. [Visualization & Output] Plot probe degradation curves
//  * 4. [Core Analysis] Access the RNA integrity parameter d
//  * 5. [Visualization & Output] (Optional) Save custom probe locations to an .Rd file
//  * 6. [Core Analysis] Extract the corrected AffyBatch object

nextflow.enable.dsl = 2

process BIOC_AFFYRNADEGRADATION_DEGRADATION_ANALYSIS_AND_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("affy", "AffyRNADegradation")
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
        library(affy)
        library(AffyRNADegradation)
        
        # ==========================================
        # USER INPUT LOADING
        # ==========================================
        
        # Read the raw AffyBatch object from the working directory
        if (file.exists("AmpData.rds")) {
          AmpData <- readRDS("AmpData.rds")
        } else {
          stop("Error: Required input file 'AmpData.rds' not found in the working directory.")
        }
        
        # Read the optional custom probe locations if available
        if (file.exists("probeDists.Rd")) {
          load("probeDists.Rd")
        } else if (file.exists("probeDists.RData")) {
          load("probeDists.RData")
        }
        
        # ==========================================
        # WORKFLOW: degradation_analysis_and_correction
        # ==========================================
        
        # Stage 1: Visualize probe positional bias using a tongs plot
        pdf("tongs_plot.pdf")
        tongs <- GetTongs(AmpData, chip.idx = 1) 
        PlotTongs(tongs)
        dev.off()
        
        # Stage 2: Perform RNA degradation analysis and correction
        rna.deg <- RNADegradation(AmpData, location.type = "index")
        
        # Stage 3: Plot probe degradation curves
        pdf("degradation_curves.pdf")
        plotDx(rna.deg)
        dev.off()
        
        # Stage 4: Access the RNA integrity parameter d
        d_values <- d(rna.deg)
        write.csv(as.data.frame(d_values), "rna_integrity_d.csv", row.names = TRUE)
        
        # Stage 5: (Optional) Save custom probe locations to an .Rd file
        if (exists("probeDists")) {
          filename = paste(cdfName(AmpData), ".Rd", sep="")
          save(probeDists, file = filename)
        }
        
        # Stage 6: Extract the corrected AffyBatch object
        corrected_batch <- afbatch(rna.deg)
        saveRDS(corrected_batch, "corrected_AmpData.rds")

    writeLines(c(
        '"BIOC_AFFYRNADEGRADATION_DEGRADATION_ANALYSIS_AND_CORRECTION":',
        paste0('    AffyRNADegradation: ', as.character(packageVersion('AffyRNADegradation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_degradation_analysis_and_correction.csv versions.yml
    """
}

workflow BIOC_AFFYRNADEGRADATION_DEGRADATION_ANALYSIS_AND_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ AmpData, probeDists ] ]

    main:
    BIOC_AFFYRNADEGRADATION_DEGRADATION_ANALYSIS_AND_CORRECTION(ch_input)

    emit:
    tables   = BIOC_AFFYRNADEGRADATION_DEGRADATION_ANALYSIS_AND_CORRECTION.out.tables
    plots    = BIOC_AFFYRNADEGRADATION_DEGRADATION_ANALYSIS_AND_CORRECTION.out.plots
    objects  = BIOC_AFFYRNADEGRADATION_DEGRADATION_ANALYSIS_AND_CORRECTION.out.objects
    versions = BIOC_AFFYRNADEGRADATION_DEGRADATION_ANALYSIS_AND_CORRECTION.out.versions
}
