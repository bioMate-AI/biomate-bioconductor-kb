#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: michip — step_by_step_processing
// Manually parse, filter, flag-correct, summarize, plot, normalize, and export MiChip miRNA microarray data step-by-step.
// Input: B_676.gpr, B_677.gpr
// Container: quay.io/biocontainers/bioconductor-michip:1.64.0--r45hdfd78af_0
// R packages: MiChip
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICHIP_STEP_BY_STEP_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-michip:1.64.0--r45hdfd78af_0"

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
    .bm_deps <- c("MiChip")
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
    
    # Load the required library
    library(MiChip)
    
    # Define the directory containing the user-provided GPR files (B_676.gpr and B_677.gpr)
    datadir <- "."
    
    # --- Parse raw data from the current directory ---
    defaultRawData <- parseRawData(datadir)
    
    # --- Filter out empty and unwanted rows ---
    noEmptiesDataSet <- removeUnwantedRows(defaultRawData, c("Empty"))
    humanDataSet <- standardRemoveRows(defaultRawData)
    
    # --- Correct for bad flags and low-intensity background ---
    flagCorrectedDataSet <- correctForFlags(humanDataSet)
    flagCorrectedDataSet <- correctForFlags(humanDataSet, intensityCutoff = 50)
    
    # --- Summarize replicate spot intensities ---
    summedData <- summarizeIntensitiesAsMedian(flagCorrectedDataSet, minSumlength = 0, madAdjust=FALSE)
    
    # --- Generate diagnostic scatter and box plots ---
    # These functions automatically write files to the working directory with the specified prefixes
    plotIntensitiesScatter(exprs(summedData), NULL, "MiChipDemX", "SummarizedScatter")
    boxplotData(exprs(summedData), "MiChipDemX", "Summarized")
    
    # --- Perform per-chip median normalization ---
    mednormedData <- normalizePerChipMedian(summedData)
    
    # --- Export the annotated normalized data matrix ---
    outputAnnotatedDataMatrix(mednormedData, "MiChipDemo", "medNormedIntensity", "exprs")
    
    # Save R objects for downstream analysis
    saveRDS(defaultRawData, file = "defaultRawData.rds")
    saveRDS(noEmptiesDataSet, file = "noEmptiesDataSet.rds")
    saveRDS(humanDataSet, file = "humanDataSet.rds")
    saveRDS(flagCorrectedDataSet, file = "flagCorrectedDataSet.rds")
    saveRDS(summedData, file = "summedData.rds")
    saveRDS(mednormedData, file = "mednormedData.rds")

    writeLines(c(
        '"BIOC_MICHIP_STEP_BY_STEP_PROCESSING":',
        paste0('        michip: ', as.character(packageVersion("michip")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_processing.csv versions.yml
    """
}

workflow BIOC_MICHIP_STEP_BY_STEP_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ B_676.gpr, B_677.gpr ] ]

    main:
    BIOC_MICHIP_STEP_BY_STEP_PROCESSING(ch_input)

    emit:
    tables   = BIOC_MICHIP_STEP_BY_STEP_PROCESSING.out.tables
    plots    = BIOC_MICHIP_STEP_BY_STEP_PROCESSING.out.plots
    objects  = BIOC_MICHIP_STEP_BY_STEP_PROCESSING.out.objects
    versions = BIOC_MICHIP_STEP_BY_STEP_PROCESSING.out.versions
}
