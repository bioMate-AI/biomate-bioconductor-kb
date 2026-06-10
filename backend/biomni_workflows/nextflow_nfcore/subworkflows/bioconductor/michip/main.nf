#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: michip — step_by_step_processing
// Manually parse, filter, flag-correct, summarize, plot, normalize, and export MiChip miRNA microarray data step-by-step.
// Input: B_676.gpr, B_677.gpr
// Container: quay.io/biocontainers/bioconductor-michip:1.64.0--r45hdfd78af_0
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
    .bm_deps <- c("michip")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(MiChip)
    
    # Define the directory containing the user-provided GPR files (B_676.gpr and B_677.gpr)
    datadir <- "."
    
    # 1. Parse raw data from the current directory
    defaultRawData <- parseRawData(datadir)
    
    # 2. Filter out empty and unwanted rows
    noEmptiesDataSet <- removeUnwantedRows(defaultRawData, c("Empty"))
    humanDataSet <- standardRemoveRows(defaultRawData)
    
    # 3. Correct for bad flags and low-intensity background
    flagCorrectedDataSet <- correctForFlags(humanDataSet)
    flagCorrectedDataSet <- correctForFlags(humanDataSet, intensityCutoff = 50)
    
    # 4. Summarize replicate spot intensities
    summedData <- summarizeIntensitiesAsMedian(flagCorrectedDataSet, minSumlength = 0, madAdjust=FALSE)
    
    # 5. Generate diagnostic scatter and box plots
    # These functions automatically write files to the working directory with the specified prefixes
    plotIntensitiesScatter(exprs(summedData), NULL, "MiChipDemX", "SummarizedScatter")
    boxplotData(exprs(summedData), "MiChipDemX", "Summarized")
    
    # 6. Perform per-chip median normalization
    mednormedData <- normalizePerChipMedian(summedData)
    
    # 7. Export the annotated normalized data matrix
    outputAnnotatedDataMatrix(mednormedData, "MiChipDemo", "medNormedIntensity", "exprs")
    
    # Save R objects for downstream analysis
    saveRDS(defaultRawData, file = "defaultRawData.rds")
    saveRDS(noEmptiesDataSet, file = "noEmptiesDataSet.rds")
    saveRDS(humanDataSet, file = "humanDataSet.rds")
    saveRDS(flagCorrectedDataSet, file = "flagCorrectedDataSet.rds")
    saveRDS(summedData, file = "summedData.rds")
    saveRDS(mednormedData, file = "mednormedData.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MICHIP_STEP_BY_STEP_PROCESSING":
        michip: \$(Rscript -e 'cat(as.character(packageVersion("michip")))')
    END_VERSIONS
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
