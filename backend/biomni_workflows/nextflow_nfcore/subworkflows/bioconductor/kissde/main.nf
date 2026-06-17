#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kissde — alternative_splicing_analysis
// Identify differentially used alternative splicing events from KisSplice2refgenome annotated output.
// Input: output_k2rg_alt_splicing.txt
// Container: quay.io/biocontainers/bioconductor-kissde:1.30.0--r45hdfd78af_0
// R packages: kissDE
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KISSDE_ALTERNATIVE_SPLICING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-kissde:1.30.0--r45hdfd78af_0"

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
    .bm_deps <- c("kissDE")
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
    
    # Load the required Bioconductor package
    library(kissDE)
    
    # Define the input file path (expected in the working directory)
    fileInAS <- "output_k2rg_alt_splicing.txt"
    
    # Verify file existence
    if (!file.exists(fileInAS)) {
      stop(paste("Required input file '", fileInAS, "' not found in the working directory.", sep = ""))
    }
    
    # --- Convert KisSplice2refgenome output to counts ---
    myCounts_AS <- kissplice2counts(fileInAS, pairedEnd = TRUE, k2rg = TRUE, counts = 2, exonicReads = FALSE)
    
    # --- Define condition vector ---
    myConditions_AS <- c(rep("SKNSH", 2), rep("SKNSH-RA", 2))
    
    # --- Perform quality control (saving plots to a PDF file) ---
    pdf("quality_control_plots.pdf", width = 12, height = 6)
    qualityControl(myCounts_AS, myConditions_AS)
    dev.off()
    
    # --- Run differential analysis ---
    myResult_AS <- diffExpressedVariants(myCounts_AS, myConditions_AS)
    
    # --- Export results ---
    writeOutputKissDE(myResult_AS, output = "results_table.tab")
    writeOutputKissDE(myResult_AS, output = "psi_table.tab", writePSI = TRUE)
    
    # --- Explore results (wrapped in tryCatch for non-interactive ---
    tryCatch({
      if (interactive()) {
        exploreResults(rdsFile = "results_table.tab.rds")
      } else {
        cat("Session is non-interactive. Skipping interactive exploreResults().\n")
        cat("The results RDS file is saved and can be explored later using: exploreResults(rdsFile = 'results_table.tab.rds')\n")
      }
    }, error = function(e) {
      warning("Could not run exploreResults: ", e\$message)
    })

    writeLines(c(
        '"BIOC_KISSDE_ALTERNATIVE_SPLICING_ANALYSIS":',
        paste0('        kissde: ', as.character(packageVersion("kissde")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alternative_splicing_analysis.csv versions.yml
    """
}

workflow BIOC_KISSDE_ALTERNATIVE_SPLICING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ output_k2rg_alt_splicing.txt ] ]

    main:
    BIOC_KISSDE_ALTERNATIVE_SPLICING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_KISSDE_ALTERNATIVE_SPLICING_ANALYSIS.out.tables
    plots    = BIOC_KISSDE_ALTERNATIVE_SPLICING_ANALYSIS.out.plots
    objects  = BIOC_KISSDE_ALTERNATIVE_SPLICING_ANALYSIS.out.objects
    versions = BIOC_KISSDE_ALTERNATIVE_SPLICING_ANALYSIS.out.versions
}
