#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adductomicsr — adductomics_workflow
// Correct retention time drift, identify peptide adducts, generate a target table, quantify peaks, and filter the final peak table from raw mzXML files.
// Input: mzXML files, runOrder.csv, allResults_ALVLIAFAQYLQQCPFEDHVK_example.csv, exampletargTable2.csv
// Container: quay.io/biocontainers/bioconductor-adductomicsr:1.26.0--r45hdfd78af_0
// R packages: adductdata, adductomicsR, devtools, ExperimentHub
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADDUCTOMICSR_ADDUCTOMICS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-adductomicsr:1.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("adductdata", "adductomicsR", "devtools", "ExperimentHub")
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
    library(adductomicsR)
    
    # --- Model retention time deviation across samples using ---
    rtDevModelling(
      MS2Dir = ".",
      nCores = 4,
      runOrder = "runOrder.csv"
    )
    
    # --- Identify peptide adducts and group spectra using ---
    specSimPepId(
      MS2Dir = ".",
      nCores = 4,
      rtDevModels = "./rtDevModels.RData"
    )
    
    # --- Generate a target table of adducts for quantification ---
    generateTargTable(
      allresultsFile = "allResults_ALVLIAFAQYLQQCPFEDHVK_example.csv",
      csvDir = "."
    )
    
    # --- Quantify adduct peaks across samples using adductQuant ---
    object <- adductQuant(
      nCores = 2,
      targTable = "exampletargTable2.csv",
      intStdRtDrift = 30,
      rtDevModels = "./rtDevModels.RData",
      filePaths = list.files(".", pattern = ".mzXML", all.files = FALSE, full.names = TRUE),
      quantObject = NULL,
      indivAdduct = NULL,
      maxPpm = 5,
      minSimScore = 0.8,
      spikeScans = 1,
      minPeakHeight = 100,
      maxRtDrift = 20,
      maxRtWindow = 240,
      isoWindow = 80,
      hkPeptide = 'LVNEVTEFAK',
      gaussAlpha = 16
    )
    
    # Ensure the quantification object is loaded if it was saved to disk instead of returned
    if (!exists("object") || is.null(object)) {
      if (file.exists("adductQuantResults.Rda")) {
        load("adductQuantResults.Rda")
      }
    }
    
    # --- Extract and save the peak table from the quantification ---
    outputPeakTable(
      object = object,
      outputDir = "."
    )
    
    # --- Filter the peak table to remove noisy adducts and ---
    filterAdductTable(
      paste0("./adductQuantif_peakList_", Sys.Date(), ".csv")
    )

    writeLines(c(
        '"BIOC_ADDUCTOMICSR_ADDUCTOMICS_WORKFLOW":',
        paste0('        adductomicsr: ', as.character(packageVersion("adductomicsr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adductomics_workflow.csv versions.yml
    """
}

workflow BIOC_ADDUCTOMICSR_ADDUCTOMICS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mzXML files, runOrder.csv, allResults_ALVLIAFAQYLQQCPFEDHVK_example.csv, exampletargTable2.csv ] ]

    main:
    BIOC_ADDUCTOMICSR_ADDUCTOMICS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ADDUCTOMICSR_ADDUCTOMICS_WORKFLOW.out.tables
    plots    = BIOC_ADDUCTOMICSR_ADDUCTOMICS_WORKFLOW.out.plots
    objects  = BIOC_ADDUCTOMICSR_ADDUCTOMICS_WORKFLOW.out.objects
    versions = BIOC_ADDUCTOMICSR_ADDUCTOMICS_WORKFLOW.out.versions
}
