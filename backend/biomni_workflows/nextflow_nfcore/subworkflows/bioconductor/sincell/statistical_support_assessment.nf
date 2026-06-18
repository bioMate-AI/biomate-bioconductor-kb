#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sincell — statistical_support_assessment
// Evaluate the robustness of reconstructed cell-state hierarchies against noise using gene resampling and in silico cell replicates.
// Input: EMlog_t0
// Container: quay.io/biocontainers/bioconductor-sincell:1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sincell
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Initialize the Sincell object, perform dimensionality reduction, and build the base hierarchy
//  * 2. [Core Analysis] Assess statistical support via gene resampling
//  * 3. [Core Analysis] Generate in silico cell replicates based on a noise model
//  * 4. [Core Analysis] Assess statistical support via random cell substitution with the generated replicates

nextflow.enable.dsl = 2

process BIOC_SINCELL_STATISTICAL_SUPPORT_ASSESSMENT {
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
    .bm_deps <- c("sincell")
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
    library(sincell)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input and Initialize Sincell Object
    # -----------------------------------------------------------------------------
    
    # Locate and read the input file 'EMlog_t0' from the working directory.
    # We support RDS, CSV, TSV, or plain text formats.
    input_file <- NULL
    possible_files <- c("EMlog_t0", "EMlog_t0.rds", "EMlog_t0.csv", "EMlog_t0.tsv")
    
    for (f in possible_files) {
      if (file.exists(f)) {
        input_file <- f
        break
      }
    }
    
    if (is.null(input_file)) {
      stop("Required input file 'EMlog_t0' (or with .rds/.csv/.tsv extension) not found in the working directory.")
    }
    
    message("Reading input file: ", input_file)
    
    EMlog_t0 <- tryCatch({
      if (grepl("\\\\.rds\$", input_file, ignore.case = TRUE) || 
          (!grepl("\\\\.(csv|tsv)\$", input_file, ignore.case = TRUE) && 
           inherits(try(readRDS(input_file), silent = TRUE), "matrix"))) {
        readRDS(input_file)
      } else {
        # Try reading as a delimited text file
        df <- read.table(input_file, header = TRUE, row.names = 1, sep = "", check.names = FALSE)
        as.matrix(df)
      }
    }, error = function(e) {
      # Fallback to standard CSV reading
      df <- read.csv(input_file, row.names = 1, check.names = FALSE)
      as.matrix(df)
    })
    
    # Ensure the loaded object is a matrix
    if (!is.matrix(EMlog_t0)) {
      EMlog_t0 <- as.matrix(EMlog_t0)
    }
    
    # Initialize Sincell object, perform dimensionality reduction, and build base hierarchy
    message("Initializing Sincell object and building base hierarchy...")
    SO_t0 <- sc_InitializingSincellObject(EMlog_t0)
    SO_t0 <- sc_DimensionalityReductionObj(SO_t0, method="ICA",dim=2)
    SO_t0 <- sc_GraphBuilderObj(SO_t0, graph.algorithm="MST", 
    	graph.using.cells.clustering=FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Assess Statistical Support via Gene Resampling
    # -----------------------------------------------------------------------------
    message("Assessing statistical support by gene subsampling...")
    SO_t0<-sc_StatisticalSupportByGeneSubsampling(SO_t0, num_it=100)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Generate In Silico Cell Replicates
    # -----------------------------------------------------------------------------
    message("Generating in silico cell replicates...")
    SO_t0 <- sc_InSilicoCellsReplicatesObj(SO_t0, 
    	method="variance.deciles", multiplier=100)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Assess Statistical Support via Random Cell Substitution
    # -----------------------------------------------------------------------------
    message("Assessing statistical support by replacement with in silico replicates...")
    SO_t0<-sc_StatisticalSupportByReplacementWithInSilicoCellsReplicates(SO_t0,
    	num_it=100,fraction.cells.to.replace=1)
    
    # -----------------------------------------------------------------------------
    # Save Outputs
    # -----------------------------------------------------------------------------
    message("Saving results and generating output files...")
    
    # 1. Save the complete Sincell object as an RDS file
    saveRDS(SO_t0, file = "SO_t0_final.rds")
    
    # 2. Extract statistical support metrics and write a summary CSV
    support_gene <- SO_t0[["StatisticalSupportbyGeneSubsampling"]]
    support_replicates <- SO_t0[["StatisticalSupportByReplacementWithInSilicoCellReplicates"]]
    
    summary_df <- data.frame(
      Metric = c("GeneSubsampling", "InSilicoReplacement"),
      Min = c(min(support_gene, na.rm = TRUE), min(support_replicates, na.rm = TRUE)),
      Mean = c(mean(support_gene, na.rm = TRUE), mean(support_replicates, na.rm = TRUE)),
      Median = c(median(support_gene, na.rm = TRUE), median(support_replicates, na.rm = TRUE)),
      Max = c(max(support_gene, na.rm = TRUE), max(support_replicates, na.rm = TRUE)),
      Variance = c(var(support_gene, na.rm = TRUE), var(support_replicates, na.rm = TRUE))
    )
    
    write.csv(summary_df, file = "statistical_support_summary.csv", row.names = FALSE)
    
    # 3. Generate PDF plots of the statistical support distributions
    pdf("statistical_support_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    if (!is.null(support_gene)) {
      plot(density(support_gene), 
           col = "blue", 
           lwd = 3,
           main = "Similarities of Hierarchies\nupon Gene Subsampling",
           xlab = "Spearman rank correlation", 
           ylab = "Density")
    }
    
    if (!is.null(support_replicates)) {
      plot(density(support_replicates), 
           col = "red", 
           lwd = 3,
           main = "Similarities of Hierarchies\nupon Substitution with Replicates",
           xlab = "Spearman rank correlation", 
           ylab = "Density")
    }
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'SO_t0_final.rds', 'statistical_support_summary.csv', and 'statistical_support_plots.pdf'.")

    writeLines(c(
        '"BIOC_SINCELL_STATISTICAL_SUPPORT_ASSESSMENT":',
        paste0('    sincell: ', as.character(packageVersion('sincell')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_statistical_support_assessment.csv versions.yml
    """
}

workflow BIOC_SINCELL_STATISTICAL_SUPPORT_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ EMlog_t0 ] ]

    main:
    BIOC_SINCELL_STATISTICAL_SUPPORT_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_SINCELL_STATISTICAL_SUPPORT_ASSESSMENT.out.tables
    plots    = BIOC_SINCELL_STATISTICAL_SUPPORT_ASSESSMENT.out.plots
    objects  = BIOC_SINCELL_STATISTICAL_SUPPORT_ASSESSMENT.out.objects
    versions = BIOC_SINCELL_STATISTICAL_SUPPORT_ASSESSMENT.out.versions
}
