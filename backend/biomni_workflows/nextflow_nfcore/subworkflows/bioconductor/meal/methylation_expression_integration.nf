#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEAL — methylation_expression_integration
// Integrate methylation and expression datasets to evaluate regional associations and calculate probe-level correlations.
// Input: brge_methy, brge_gexp
// Container: quay.io/biocontainers/bioconductor-meal:1.28.0--r42hdfd78af_0
// R packages: Biobase, GenomicRanges, MEAL, MultiDataSet, minfi
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GenomicRanges, MEAL, MultiDataSet, minfi
// Visualizations: genomic region plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Co-visualize regional results using plotRegion
//  * 2. [Input & Preparation] Create a MultiDataSet and add both expression and methylation datasets
//  * 3. [Core Analysis] Subset the MultiDataSet to a target genomic range
//  * 4. [Core Analysis] Calculate correlation between CpGs and expression probes using correlationMethExprs

nextflow.enable.dsl = 2

process BIOC_MEAL_METHYLATION_EXPRESSION_INTEGRATION {
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
    .bm_deps <- c("Biobase", "GenomicRanges", "MEAL", "MultiDataSet", "minfi", "SummarizedExperiment")
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
    library(MEAL)
    library(SummarizedExperiment)
    library(MultiDataSet)
    library(GenomicRanges)
    library(minfi)
    library(Biobase)
    
    # Helper function to read the exact user input files from the working directory
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file not found in working directory:", filename))
      }
    }
    
    # Read the user-provided datasets
    brge_methy <- read_input("brge_methy")
    brge_gexp <- read_input("brge_gexp")
    
    # Define the target genomic range
    targetRange <- GRanges("chr11:102600000-103300000")
    
    # Run differential analyses to generate the required ResultSet objects
    cellCounts <- colnames(colData(brge_methy))[3:9]
    methRes <- runDiffMeanAnalysis(
      set = brge_methy, 
      model = formula(paste("~ sex +", paste(cellCounts, collapse = "+")))
    )
    
    gexpRes <- runDiffMeanAnalysis(
      set = brge_gexp, 
      model = ~ sex
    )
    
    # Stage 1: Co-visualize regional results using plotRegion
    pdf("regional_association_plot.pdf", width = 10, height = 8)
    plotRegion(rset = methRes, rset2 = gexpRes, range = targetRange)
    dev.off()
    
    # Stage 2: Create a MultiDataSet and add both expression and methylation datasets
    multi <- createMultiDataSet()
    multi <- add_genexp(multi, brge_gexp)
    multi <- add_methy(multi, brge_methy)
    
    # Stage 3: Subset the MultiDataSet to a target genomic range
    multi.filt <- multi[, , targetRange]
    
    # Stage 4: Calculate correlation between CpGs and expression probes using correlationMethExprs
    methExprs <- correlationMethExprs(multi.filt)
    
    # Print the head of the correlation results to standard output
    print(head(methExprs))
    
    # Save meaningful results to output files
    write.csv(methExprs, "meth_exprs_correlation.csv", row.names = FALSE)
    saveRDS(methRes, "methRes.rds")
    saveRDS(gexpRes, "gexpRes.rds")
    saveRDS(multi.filt, "multi_filt.rds")

    writeLines(c(
        '"BIOC_MEAL_METHYLATION_EXPRESSION_INTEGRATION":',
        paste0('    MEAL: ', as.character(packageVersion('MEAL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_expression_integration.csv versions.yml
    """
}

workflow BIOC_MEAL_METHYLATION_EXPRESSION_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brge_methy, brge_gexp ] ]

    main:
    BIOC_MEAL_METHYLATION_EXPRESSION_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_MEAL_METHYLATION_EXPRESSION_INTEGRATION.out.tables
    plots    = BIOC_MEAL_METHYLATION_EXPRESSION_INTEGRATION.out.plots
    objects  = BIOC_MEAL_METHYLATION_EXPRESSION_INTEGRATION.out.objects
    versions = BIOC_MEAL_METHYLATION_EXPRESSION_INTEGRATION.out.versions
}
