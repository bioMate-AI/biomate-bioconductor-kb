#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: safe — covariate_adjusted_safe_analysis
// Perform pathway analysis adjusting for confounding covariates.
// Input: e3.upp, p3.upp$p53, p3.upp$er, C.mat
// Container: quay.io/biocontainers/bioconductor-safe:3.50.0--r45hdfd78af_0
// R packages: safe
// Bioconductor: 3.20 | R: 4.4
// Requires: safe
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute residuals adjusting for covariates using getXYresiduals
//  * 2. [Core Analysis] Run safe on the residuals

nextflow.enable.dsl = 2

process BIOC_SAFE_COVARIATE_ADJUSTED_SAFE_ANALYSIS {
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
    .bm_deps <- c("safe")
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
        library(safe)
        
        # Helper function to robustly load user input files
        load_input <- function(base_name) {
          rds_file <- paste0(base_name, ".rds")
          csv_file <- paste0(base_name, ".csv")
          
          if (file.exists(base_name)) {
            # Try reading as RDS first, then fallback to table
            obj <- tryCatch({
              readRDS(base_name)
            }, error = function(e) {
              tryCatch({
                read.csv(base_name, header = TRUE, row.names = 1, check.names = FALSE)
              }, error = function(e2) {
                read.table(base_name, header = TRUE, check.names = FALSE)
              })
            })
            return(obj)
          } else if (file.exists(rds_file)) {
            return(readRDS(rds_file))
          } else if (file.exists(csv_file)) {
            return(read.csv(csv_file, header = TRUE, row.names = 1, check.names = FALSE))
          } else {
            stop(paste("Required input file not found:", base_name))
          }
        }
        
        # 1. Load User Inputs
        e3.upp <- load_input("e3.upp")
        p3.upp <- load_input("p3.upp")
        C.mat  <- load_input("C.mat")
        
        # Ensure correct data types
        e3.upp <- as.matrix(e3.upp)
        
        # 2. Compute residuals adjusting for covariates using getXYresiduals
        Xy <- getXYresiduals(e3.upp, p3.upp\$p53, Z.mat = p3.upp\$er)
        
        # 3. Run safe on the residuals
        results2 <- safe(Xy\$X.star, Xy\$y.star, C.mat, 
                         print.it = FALSE)
        
        # 4. Save meaningful results
        saveRDS(results2, file = "safe_results.rds")
        
        # Generate and save top table of results
        tryCatch({
          # Get the number of categories to display in the table
          num_categories <- length(results2@global.pval)
          if (is.null(num_categories) || num_categories == 0) {
            num_categories <- 10
          }
          
          tab <- safe.toptable(results2, number = num_categories)
          write.csv(tab, file = "safe_toptable.csv", row.names = FALSE)
          
          # Plot the top significant category if available
          if (nrow(tab) > 0) {
            top_cat <- tab\$GenesetID[1]
            pdf("safe_plot_top_category.pdf")
            safeplot(results2, cat.name = top_cat, gene.names = rownames(e3.upp))
            dev.off()
          }
        }, error = function(e) {
          message("Optional output generation (table/plot) failed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_SAFE_COVARIATE_ADJUSTED_SAFE_ANALYSIS":',
        paste0('    safe: ', as.character(packageVersion('safe')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_covariate_adjusted_safe_analysis.csv versions.yml
    """
}

workflow BIOC_SAFE_COVARIATE_ADJUSTED_SAFE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ e3.upp, p3.upp$p53, p3.upp$er, C.mat ] ]

    main:
    BIOC_SAFE_COVARIATE_ADJUSTED_SAFE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SAFE_COVARIATE_ADJUSTED_SAFE_ANALYSIS.out.tables
    plots    = BIOC_SAFE_COVARIATE_ADJUSTED_SAFE_ANALYSIS.out.plots
    objects  = BIOC_SAFE_COVARIATE_ADJUSTED_SAFE_ANALYSIS.out.objects
    versions = BIOC_SAFE_COVARIATE_ADJUSTED_SAFE_ANALYSIS.out.versions
}
