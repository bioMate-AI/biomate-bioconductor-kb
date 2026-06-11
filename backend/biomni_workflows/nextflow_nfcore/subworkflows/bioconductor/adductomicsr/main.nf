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
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    
    # 1. Model retention time deviation across samples using rtDevModelling
    rtDevModelling(
      MS2Dir = ".",
      nCores = 4,
      runOrder = "runOrder.csv"
    )
    
    # 2. Identify peptide adducts and group spectra using specSimPepId
    specSimPepId(
      MS2Dir = ".",
      nCores = 4,
      rtDevModels = "./rtDevModels.RData"
    )
    
    # 3. Generate a target table of adducts for quantification using generateTargTable
    generateTargTable(
      allresultsFile = "allResults_ALVLIAFAQYLQQCPFEDHVK_example.csv",
      csvDir = "."
    )
    
    # 4. Quantify adduct peaks across samples using adductQuant
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
    
    # 5. Extract and save the peak table from the quantification object using outputPeakTable
    outputPeakTable(
      object = object,
      outputDir = "."
    )
    
    # 6. Filter the peak table to remove noisy adducts and low-quality samples using filterAdductTable
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
