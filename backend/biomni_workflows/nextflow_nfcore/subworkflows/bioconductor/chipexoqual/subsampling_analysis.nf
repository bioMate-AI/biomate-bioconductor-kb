#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChIPexoQual — subsampling_analysis
// Assess quality of deeply sequenced ChIP-exo/nexus experiments by subsampling reads to various depths.
// Input: file.bam
// Container: quay.io/biocontainers/bioconductor-chipexoqual:1.34.0--r45hdfd78af_0
// Requires: ChIPexoQual, Rsamtools, gridExtra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define target sampling depths
//  * 2. [Input & Preparation] Perform subsampling and build a list of ExoData objects using ExoDataSubsampling
//  * 3. [Visualization & Output] Visualize parameter distributions across depths using paramDistBoxplot

nextflow.enable.dsl = 2

process BIOC_CHIPEXOQUAL_SUBSAMPLING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("ChIPexoQual", "Rsamtools", "gridExtra")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(ChIPexoQual)
    library(gridExtra)
    library(Rsamtools)
    
    # Define input file
    input_bam <- "file.bam"
    
    if (!file.exists(input_bam)) {
      stop("Error: Input file 'file.bam' not found in the working directory.")
    }
    
    # Ensure BAM index exists to prevent downstream errors
    if (!file.exists(paste0(input_bam, ".bai"))) {
      message("BAM index not found. Creating index...")
      Rsamtools::indexBam(input_bam)
    }
    
    # Set up the files vector to match the documented code's indexing
    files <- c(NA, NA, input_bam)
    
    # 1. Define target sampling depths
    sample.depth = seq(1e5,2e5,5e4)
    
    # 2. Perform subsampling and build a list of ExoData objects using ExoDataSubsampling
    message("Running ExoDataSubsampling...")
    exoList = ExoDataSubsampling(file = files[3],sample.depth = sample.depth, verbose=FALSE)
    
    # Save the generated ExoData list object
    saveRDS(exoList, file = "exoList_subsampled.rds")
    
    # 3. Visualize parameter distributions across depths using paramDistBoxplot
    message("Generating parameter distribution plots...")
    p1 = paramDistBoxplot(exoList,which.param = "beta1")
    p2 = paramDistBoxplot(exoList,which.param = "beta2")
    
    # Save the visualization to a PDF file
    pdf("subsampling_param_dist.pdf", width = 10, height = 5)
    gridExtra::grid.arrange(p1,p2,nrow = 1)
    dev.off()
    
    # Extract and save summary statistics to a CSV file
    message("Saving summary statistics...")
    beta1_medians <- sapply(exoList, function(x) median(beta1(x)))
    beta2_medians <- sapply(exoList, function(x) median(-beta2(x)))
    
    summary_df <- data.frame(
      Sample_Depth = sample.depth,
      Median_Beta1 = beta1_medians,
      Median_Beta2 = beta2_medians
    )
    
    write.csv(summary_df, "subsampling_summary.csv", row.names = FALSE)
    message("Pipeline completed successfully. Outputs saved: 'exoList_subsampled.rds', 'subsampling_param_dist.pdf', 'subsampling_summary.csv'")

    writeLines(c(
        '"BIOC_CHIPEXOQUAL_SUBSAMPLING_ANALYSIS":',
        paste0('    ChIPexoQual: ', as.character(packageVersion('ChIPexoQual')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subsampling_analysis.csv versions.yml
    """
}

workflow BIOC_CHIPEXOQUAL_SUBSAMPLING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.bam ] ]

    main:
    BIOC_CHIPEXOQUAL_SUBSAMPLING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CHIPEXOQUAL_SUBSAMPLING_ANALYSIS.out.tables
    plots    = BIOC_CHIPEXOQUAL_SUBSAMPLING_ANALYSIS.out.plots
    objects  = BIOC_CHIPEXOQUAL_SUBSAMPLING_ANALYSIS.out.objects
    versions = BIOC_CHIPEXOQUAL_SUBSAMPLING_ANALYSIS.out.versions
}
