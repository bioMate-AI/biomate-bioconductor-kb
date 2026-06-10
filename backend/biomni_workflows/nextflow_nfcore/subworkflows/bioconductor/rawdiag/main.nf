#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rawdiag — orbitrap_method_diagnostic_plots
// Read Thermo Orbitrap raw files and generate diagnostic plots to optimize LC-MS method parameters.
// Input: file1.raw, file2.raw
// Container: quay.io/biocontainers/bioconductor-rawdiag:1.6.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAWDIAG_ORBITRAP_METHOD_DIAGNOSTIC_PLOTS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rawdiag:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("experimenthub", "rawdiag")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # -----------------------------------------------------------------------------
    # Pipeline: orbitrap_method_diagnostic_plots
    # Description: Read Thermo Orbitrap raw files and generate diagnostic plots 
    #              to optimize LC-MS method parameters.
    # -----------------------------------------------------------------------------
    
    # Define user input files exactly as declared
    rawfile <- c("file1.raw", "file2.raw")
    
    # Verify that the input files exist before proceeding
    missing_files <- rawfile[!file.exists(rawfile)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # ==========================================
    # Stage 1: Check and install rawrr assembly dependencies
    # ==========================================
    rawDiag::checkRawrr()
    
    rawrr::installRawrrExe()
    
    rawrr::rawrrAssemblyPath()
    rawrr::rawrrAssemblyPath() |> list.files()
    
    # ==========================================
    # Stage 2: Read raw file headers
    # ==========================================
    (rawfile |>
      lapply(FUN = rawrr::readFileHeader) -> rawFileHeader)
    
    # Save the file headers to an RDS object
    saveRDS(rawFileHeader, file = "raw_file_headers.rds")
    
    # ==========================================
    # Stage 3: Read and merge scan-level metadata from raw files
    # ==========================================
    rawfile |>
      lapply(FUN = rawDiag::readRaw) |>
      Reduce(f = rbind) -> x
    
    # Save the merged scan-level metadata
    write.csv(x, file = "scan_metadata.csv", row.names = FALSE)
    saveRDS(x, file = "scan_metadata.rds")
    
    # ==========================================
    # Stage 4: Generate diagnostic plots
    # ==========================================
    library(rawDiag)
    ls("package:rawDiag") |>
      grep(pattern = '^plot', value = TRUE) -> pm
    
    # Open PDF device to save the diagnostic plots
    pdf("diagnostic_plots.pdf", width = 10, height = 5)
    
    pm |> 
      lapply(FUN = function(plotFUN) {
        lapply(c('trellis'), function(method) {
          message("plotting", plotFUN, "using method", method, "...")
          # Call the plotting function and print it to the PDF device
          p <- do.call(plotFUN, list(x, method))
          print(p)
        })
      })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs generated: 'raw_file_headers.rds', 'scan_metadata.csv', 'scan_metadata.rds', and 'diagnostic_plots.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RAWDIAG_ORBITRAP_METHOD_DIAGNOSTIC_PLOTS":
        rawdiag: \$(Rscript -e 'cat(as.character(packageVersion("rawdiag")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_orbitrap_method_diagnostic_plots.csv versions.yml
    """
}

workflow BIOC_RAWDIAG_ORBITRAP_METHOD_DIAGNOSTIC_PLOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file1.raw, file2.raw ] ]

    main:
    BIOC_RAWDIAG_ORBITRAP_METHOD_DIAGNOSTIC_PLOTS(ch_input)

    emit:
    tables   = BIOC_RAWDIAG_ORBITRAP_METHOD_DIAGNOSTIC_PLOTS.out.tables
    plots    = BIOC_RAWDIAG_ORBITRAP_METHOD_DIAGNOSTIC_PLOTS.out.plots
    objects  = BIOC_RAWDIAG_ORBITRAP_METHOD_DIAGNOSTIC_PLOTS.out.objects
    versions = BIOC_RAWDIAG_ORBITRAP_METHOD_DIAGNOSTIC_PLOTS.out.versions
}
