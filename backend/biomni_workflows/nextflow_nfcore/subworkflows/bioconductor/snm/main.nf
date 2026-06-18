#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snm — single_channel_normalization
// Normalize single-channel microarray data (e.g., Affymetrix) by modeling biological variables, probe-specific adjustment variables (e.g., batch, age), and intens
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
//  * 2. [Visualization & Output] Perform diagnostic checks on the output (e.g., Kolmogorov-Smirnov test on null p-values or plotting the snm object)

nextflow.enable.dsl = 2

process BIOC_SNM_SINGLE_CHANNEL_NORMALIZATION {
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
    
    # Helper function to read input files with various extensions
    read_file <- function(name, as_matrix = FALSE, as_df = FALSE) {
      exts <- c(".rds", ".csv", ".tsv", ".txt", "")
      for (ext in exts) {
        file_path <- paste0(name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", file_path)) {
            obj <- readRDS(file_path)
            if (as_matrix) obj <- as.matrix(obj)
            if (as_df) obj <- as.data.frame(obj)
            return(obj)
          } else {
            sep <- if (grepl("\\\\.tsv\$", file_path)) "\t" else ","
            df <- tryCatch({
              read.table(file_path, header = TRUE, sep = sep, row.names = 1, check.names = FALSE)
            }, error = function(e) {
              read.table(file_path, header = TRUE, sep = sep, check.names = FALSE)
            })
            if (as_matrix) {
              return(as.matrix(df))
            } else if (as_df) {
              return(as.data.frame(df))
            } else {
              return(df)
            }
          }
        }
      }
      stop(paste("Required input file not found:", name))
    }
    
    # Construct the singleChannel list from user input files
    singleChannel <- list()
    singleChannel\$raw.data <- read_file("raw.data", as_matrix = TRUE)
    singleChannel\$bio.var <- read_file("bio.var", as_matrix = TRUE)
    singleChannel\$adj.var <- read_file("adj.var", as_matrix = TRUE)
    singleChannel\$int.var <- read_file("int.var", as_df = TRUE)
    
    # Attempt to read true.nulls if available, otherwise default to all probes
    singleChannel\$true.nulls <- tryCatch({
      tn <- read_file("true.nulls")
      if (is.data.frame(tn) || is.matrix(tn)) {
        tn <- as.vector(as.matrix(tn))
      }
      as.integer(tn)
    }, error = function(e) {
      seq_len(nrow(singleChannel\$raw.data))
    })
    
    # 1. Run the snm function with raw data and design matrices
    snm.obj1 <- snm(singleChannel\$raw.data,
    				singleChannel\$bio.var,
    				singleChannel\$adj.var,
    			        singleChannel\$int.var)
    
    # 2. Perform diagnostic checks on the output
    # Kolmogorov-Smirnov test on null p-values
    ks_res <- ks.test(snm.obj1\$pval[singleChannel\$true.nulls],"punif")
    capture.output(print(ks_res), file = "ks_test_results.txt")
    
    # Plotting the snm object
    pdf("snm_diagnostics.pdf")
    plot(snm.obj1)
    dev.off()
    
    # Write named output files for the meaningful results
    write.csv(snm.obj1\$norm.dat, file = "normalized_data.csv", row.names = TRUE)
    saveRDS(snm.obj1\$norm.dat, file = "normalized_data.rds")
    
    probe_names <- rownames(singleChannel\$raw.data)
    if (is.null(probe_names)) {
      probe_names <- seq_len(nrow(singleChannel\$raw.data))
    }
    pvals_df <- data.frame(
      probe = probe_names,
      pvalue = snm.obj1\$pval,
      stringsAsFactors = FALSE
    )
    write.csv(pvals_df, file = "pvalues.csv", row.names = FALSE)
    
    saveRDS(snm.obj1, file = "snm_object.rds")

    writeLines(c(
        '"BIOC_SNM_SINGLE_CHANNEL_NORMALIZATION":',
        paste0('    snm: ', as.character(packageVersion('snm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_channel_normalization.csv versions.yml
    """
}

workflow BIOC_SNM_SINGLE_CHANNEL_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw.data, bio.var, adj.var, int.var ] ]

    main:
    BIOC_SNM_SINGLE_CHANNEL_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SNM_SINGLE_CHANNEL_NORMALIZATION.out.tables
    plots    = BIOC_SNM_SINGLE_CHANNEL_NORMALIZATION.out.plots
    objects  = BIOC_SNM_SINGLE_CHANNEL_NORMALIZATION.out.objects
    versions = BIOC_SNM_SINGLE_CHANNEL_NORMALIZATION.out.versions
}
