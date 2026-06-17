#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snm — double_channel_normalization
// Normalize two-color microarray data (e.g., Agilent dye-swap) by modeling biological variables, probe-specific adjustment variables, and intensity-dependent arra
// Input: raw.data, bio.var, adj.var, int.var
// Container: quay.io/biocontainers/bioconductor-snm:1.58.0--r45hdfd78af_0
// R packages: snm
// Bioconductor: 3.20 | R: 4.4
// Requires: snm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the snm function with raw data and design matrices
//  * 2. [Visualization & Output] Perform diagnostic checks on the output null p-values

nextflow.enable.dsl = 2

process BIOC_SNM_DOUBLE_CHANNEL_NORMALIZATION {
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
    .bm_deps <- c("snm")
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
    library(snm)
    
    # Helper function to read input files (supporting RDS and CSV)
    read_input <- function(base_name, is_matrix = FALSE, is_df = FALSE) {
      rds_path <- paste0(base_name, ".rds")
      csv_path <- paste0(base_name, ".csv")
      
      if (file.exists(rds_path)) {
        data <- readRDS(rds_path)
        if (is_matrix) {
          return(as.matrix(data))
        }
        if (is_df) {
          return(as.data.frame(data))
        }
        return(data)
      } else if (file.exists(csv_path)) {
        df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
        if (is_matrix) {
          return(as.matrix(df))
        }
        return(df)
      } else {
        stop(paste("Error: Required input file not found:", base_name))
      }
    }
    
    # Helper function to read true.nulls vector
    read_vector <- function(base_name) {
      rds_path <- paste0(base_name, ".rds")
      csv_path <- paste0(base_name, ".csv")
      
      if (file.exists(rds_path)) {
        return(as.vector(readRDS(rds_path)))
      } else if (file.exists(csv_path)) {
        df <- read.csv(csv_path, header = FALSE)
        return(as.vector(df[[1]]))
      } else {
        return(NULL)
      }
    }
    
    # 1. Load User Inputs
    doubleChannel <- list()
    doubleChannel\$raw.data <- read_input("raw.data", is_matrix = TRUE)
    doubleChannel\$bio.var  <- read_input("bio.var", is_matrix = TRUE)
    doubleChannel\$adj.var  <- read_input("adj.var", is_matrix = TRUE)
    doubleChannel\$int.var  <- read_input("int.var", is_df = TRUE)
    
    # Read true.nulls if available, otherwise default to all probes
    t_nulls <- read_vector("true.nulls")
    if (is.null(t_nulls)) {
      doubleChannel\$true.nulls <- 1:nrow(doubleChannel\$raw.data)
    } else {
      doubleChannel\$true.nulls <- t_nulls
    }
    
    # 2. Run the snm function with raw data and design matrices
    snm.obj2 <- snm(doubleChannel\$raw.data,
                                doubleChannel\$bio.var,
                                doubleChannel\$adj.var,
                                doubleChannel\$int.var)
    
    # 3. Perform diagnostic checks on the output null p-values
    ks_res <- ks.test(snm.obj2\$pval[doubleChannel\$true.nulls],"punif")
    
    # 4. Save Outputs
    # Save the full SNM object
    saveRDS(snm.obj2, file = "snm_output.rds")
    
    # Save normalized data
    write.csv(snm.obj2\$norm.dat, file = "normalized_data.csv", row.names = TRUE)
    saveRDS(snm.obj2\$norm.dat, file = "normalized_data.rds")
    
    # Save p-values
    probe_names <- rownames(doubleChannel\$raw.data)
    if (is.null(probe_names)) {
      probe_names <- 1:nrow(doubleChannel\$raw.data)
    }
    pvals_df <- data.frame(Probe = probe_names, PValue = snm.obj2\$pval)
    write.csv(pvals_df, file = "pvalues.csv", row.names = FALSE)
    
    # Save KS-test results
    capture.output(print(ks_res), file = "ks_test_results.txt")
    
    # Save diagnostic plots
    pdf("diagnostic_plots.pdf")
    plot(snm.obj2)
    dev.off()

    writeLines(c(
        '"BIOC_SNM_DOUBLE_CHANNEL_NORMALIZATION":',
        paste0('    snm: ', as.character(packageVersion('snm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_double_channel_normalization.csv versions.yml
    """
}

workflow BIOC_SNM_DOUBLE_CHANNEL_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw.data, bio.var, adj.var, int.var ] ]

    main:
    BIOC_SNM_DOUBLE_CHANNEL_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SNM_DOUBLE_CHANNEL_NORMALIZATION.out.tables
    plots    = BIOC_SNM_DOUBLE_CHANNEL_NORMALIZATION.out.plots
    objects  = BIOC_SNM_DOUBLE_CHANNEL_NORMALIZATION.out.objects
    versions = BIOC_SNM_DOUBLE_CHANNEL_NORMALIZATION.out.versions
}
