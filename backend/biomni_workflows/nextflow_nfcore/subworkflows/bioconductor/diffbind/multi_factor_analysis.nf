#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DiffBind — multi_factor_analysis
// Perform differential binding analysis incorporating multiple metadata factors (e.g., pairing or batch effects) in the design matrix.
// Input: tamoxifen.csv, BAM files, BED/Peak files
// Container: quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0
// R packages: DiffBind
// Bioconductor: 3.20 | R: 4.4
// Requires: DiffBind
// Visualizations: MA plot, PCA plot
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and count reads
//  * 2. [Input & Preparation] Set up multi-factor design formula using dba.contrast
//  * 3. [Core Analysis] Run differential analysis using dba.analyze
//  * 4. [Visualization & Output] Retrieve multi-factor report using dba.report

nextflow.enable.dsl = 2

process BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("DiffBind")
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
    library(DiffBind)
    
    # ==========================================
    # STAGE 1: Load and count reads
    # ==========================================
    # Read the user-provided sample sheet and construct the DBA object
    tamoxifen <- dba(sampleSheet = "tamoxifen.csv")
    
    # Count reads overlapping the consensus peakset
    tamoxifen <- dba.count(tamoxifen)
    
    # ==========================================
    # STAGE 2: Set up multi-factor design formula
    # ==========================================
    # Reproducing documented code exactly:
    tamoxifen <- dba.contrast(tamoxifen,design="~Tissue + Condition")
    
    # ==========================================
    # STAGE 3: Run differential analysis
    # ==========================================
    # Reproducing documented code exactly:
    tamoxifen <- dba.analyze(tamoxifen)
    
    # ==========================================
    # STAGE 4: Retrieve multi-factor report
    # ==========================================
    # Reproducing documented code exactly:
    multifactor.DB <- dba.report(tamoxifen)
    
    # ==========================================
    # STAGE 5: Write outputs
    # ==========================================
    # Save the differential binding report as a CSV file
    if (!is.null(multifactor.DB) && length(multifactor.DB) > 0) {
      write.csv(as.data.frame(multifactor.DB), file = "multifactor_report.csv", row.names = FALSE)
    } else {
      # Create an empty file or write a message if no DB sites are found
      write.csv(data.frame(Message = "No significantly differentially bound sites found."), 
                file = "multifactor_report.csv", row.names = FALSE)
    }
    
    # Save the complete analyzed DBA object as an RDS file
    saveRDS(tamoxifen, file = "tamoxifen_analyzed.rds")
    
    # Generate diagnostic and results plots
    pdf("diffbind_plots.pdf", width = 8, height = 8)
    
    # 1. Correlation Heatmap
    tryCatch({
      plot(tamoxifen)
    }, error = function(e) {
      warning("Could not generate correlation heatmap: ", e\$message)
    })
    
    # 2. PCA Plot
    tryCatch({
      dba.plotPCA(tamoxifen, contrast = 1)
    }, error = function(e) {
      warning("Could not generate PCA plot: ", e\$message)
    })
    
    # 3. MA Plot
    tryCatch({
      dba.plotMA(tamoxifen, contrast = 1)
    }, error = function(e) {
      warning("Could not generate MA plot: ", e\$message)
    })
    
    # 4. Volcano Plot
    tryCatch({
      dba.plotVolcano(tamoxifen, contrast = 1)
    }, error = function(e) {
      warning("Could not generate Volcano plot: ", e\$message)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS":',
        paste0('    DiffBind: ', as.character(packageVersion('DiffBind')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_factor_analysis.csv versions.yml
    """
}

workflow BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tamoxifen.csv, BAM files, BED/Peak files ] ]

    main:
    BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS.out.tables
    plots    = BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS.out.plots
    objects  = BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS.out.objects
    versions = BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS.out.versions
}
