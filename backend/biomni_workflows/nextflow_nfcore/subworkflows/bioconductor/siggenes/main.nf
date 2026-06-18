#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: siggenes — sam_analysis_and_visualization
// Perform Significance Analysis of Microarrays (SAM) to identify differentially expressed genes and visualize the results via SAM and Delta plots.
// Input: golub, golub.cl
// Container: quay.io/biocontainers/bioconductor-siggenes:1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: multtest, siggenes
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the dataset and class labels
//  * 2. [Core Analysis] Run Significance Analysis of Microarrays (SAM) using sam()
//  * 3. [Visualization & Output] Generate a SAM plot for a specific delta value using sam.plot2() or plot()
//  * 4. [Visualization & Output] Generate Delta plots for a range of delta values using delta.plot() or plot()

nextflow.enable.dsl = 2

process BIOC_SIGGENES_SAM_ANALYSIS_AND_VISUALIZATION {
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
    .bm_deps <- c("siggenes", "multtest")
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
    library(siggenes)
    library(multtest)
    
    # Helper functions to read user input files robustly from the working directory
    read_matrix <- function(filepath) {
      if (grepl("\\\\.rds\$", filepath, ignore.case = TRUE)) {
        return(as.matrix(readRDS(filepath)))
      }
      mat <- tryCatch({
        df <- read.table(filepath, header = TRUE, row.names = 1, check.names = FALSE)
        as.matrix(df)
      }, error = function(e) {
        tryCatch({
          df <- read.table(filepath, header = TRUE, check.names = FALSE)
          as.matrix(df)
        }, error = function(e2) {
          df <- read.csv(filepath, header = TRUE, row.names = 1, check.names = FALSE)
          as.matrix(df)
        })
      })
      return(mat)
    }
    
    read_vector <- function(filepath) {
      if (grepl("\\\\.rds\$", filepath, ignore.case = TRUE)) {
        return(as.vector(readRDS(filepath)))
      }
      vec <- tryCatch({
        scan(filepath, quiet = TRUE)
      }, error = function(e) {
        df <- read.table(filepath, header = FALSE)
        as.vector(unlist(df))
      })
      return(vec)
    }
    
    find_and_read <- function(base_name, is_matrix) {
      extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        filepath <- paste0(base_name, ext)
        if (file.exists(filepath)) {
          if (is_matrix) {
            return(read_matrix(filepath))
          } else {
            return(read_vector(filepath))
          }
        }
      }
      stop(paste("Error: Could not find file for", base_name))
    }
    
    # 1. Load the dataset and class labels
    golub <- find_and_read("golub", is_matrix = TRUE)
    golub.cl <- find_and_read("golub.cl", is_matrix = FALSE)
    
    # 2. Run Significance Analysis of Microarrays (SAM) using sam()
    sam.out<-sam(golub,golub.cl,B=100,rand=123)
    
    # Save the SAM results object and summary text
    saveRDS(sam.out, "sam_results.rds")
    
    sink("sam_summary.txt")
    print(sam.out)
    cat("\nSummary at Delta = 2:\n")
    summary(sam.out, 2)
    sink()
    
    # 3 & 4. Generate SAM and Delta plots and save them to a PDF file
    pdf("sam_analysis_plots.pdf", width = 8, height = 8)
    
    sam.plot2(sam.out,2)
    plot(sam.out,2)
    delta.plot(sam.out)
    plot(sam.out)
    plot(sam.out,seq(0.2,2,0.2))
    
    dev.off()
    
    message("SAM analysis completed successfully. Outputs saved to 'sam_results.rds', 'sam_summary.txt', and 'sam_analysis_plots.pdf'.")

    writeLines(c(
        '"BIOC_SIGGENES_SAM_ANALYSIS_AND_VISUALIZATION":',
        paste0('    siggenes: ', as.character(packageVersion('siggenes')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sam_analysis_and_visualization.csv versions.yml
    """
}

workflow BIOC_SIGGENES_SAM_ANALYSIS_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ golub, golub.cl ] ]

    main:
    BIOC_SIGGENES_SAM_ANALYSIS_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SIGGENES_SAM_ANALYSIS_AND_VISUALIZATION.out.tables
    plots    = BIOC_SIGGENES_SAM_ANALYSIS_AND_VISUALIZATION.out.plots
    objects  = BIOC_SIGGENES_SAM_ANALYSIS_AND_VISUALIZATION.out.objects
    versions = BIOC_SIGGENES_SAM_ANALYSIS_AND_VISUALIZATION.out.versions
}
