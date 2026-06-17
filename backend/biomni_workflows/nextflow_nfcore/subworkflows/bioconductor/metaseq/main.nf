#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaSeq — noiseq_meta_analysis
// Perform meta-analysis on RNA-seq count data from multiple studies using one-sided NOISeq probabilities combined via Fisher's or Stouffer's method.
// Input: BreastCancer, flag1, flag2
// Container: quay.io/biocontainers/bioconductor-metaseq:1.50.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metaSeq, snow
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the count data and metadata using meta.readData
//  * 2. [Core Analysis] Run one-sided NOISeq on each study using meta.oneside.noiseq
//  * 3. [Core Analysis] Combine the probabilities using Fisher.test and Stouffer.test

nextflow.enable.dsl = 2

process BIOC_METASEQ_NOISEQ_META_ANALYSIS {
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
    .bm_deps <- c("metaSeq", "snow")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    
    # Load required libraries
    library("metaSeq")
    library("snow")
    
    # Helper function to robustly read user input files from the working directory
    read_input_file <- function(filename) {
      if (!file.exists(filename)) {
        stop(paste("Required input file not found in the working directory:", filename))
      }
      
      # Try reading as RDS
      res <- tryCatch(readRDS(filename), error = function(e) NULL)
      if (!is.null(res)) return(res)
      
      # Try reading as CSV
      res <- tryCatch({
        df <- read.csv(filename, header = TRUE, row.names = 1, check.names = FALSE)
        as.matrix(df)
      }, error = function(e) NULL)
      if (!is.null(res)) return(res)
      
      # Try reading as TSV
      res <- tryCatch({
        df <- read.table(filename, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        as.matrix(df)
      }, error = function(e) NULL)
      if (!is.null(res)) return(res)
      
      # Try reading as a simple vector (for flag1 and flag2)
      res <- tryCatch({
        val <- scan(filename, what = character(), quiet = TRUE)
        if (!any(is.na(as.numeric(val)))) {
          as.numeric(val)
        } else {
          val
        }
      }, error = function(e) NULL)
      if (!is.null(res)) return(res)
      
      stop(paste("Could not parse file format for:", filename))
    }
    
    # 1. Read the declared user input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    BreastCancer <- read_input_file("BreastCancer")
    flag1 <- read_input_file("flag1")
    flag2 <- read_input_file("flag2")
    
    # 2. Format the count data and metadata
    cds <- meta.readData(data = BreastCancer, factor = flag1, studies = flag2)
    
    # 3. Run one-sided NOISeq on each study using parallel processing
    cl <- makeCluster(4, "SOCK")
    result <- meta.oneside.noiseq(cds, k = 0.5, norm = "tmm", replicates = "biological", factor = flag1, conditions = c(1, 0), studies = flag2, cl = cl)
    stopCluster(cl)
    
    # 4. Combine the probabilities using Fisher's and Stouffer's methods
    F <- Fisher.test(result)
    S <- Stouffer.test(result)
    
    # Print documented outputs to console
    head(F\$Upper)
    head(F\$Lower)
    F\$Weight
    head(S\$Upper)
    head(S\$Lower)
    S\$Weight
    
    # 5. Write meaningful results to output files
    # Align gene names for tabular output
    genes <- names(F\$Upper)
    if (is.null(genes)) {
      genes <- seq_along(F\$Upper)
    }
    
    # Save Fisher's method results
    fisher_df <- data.frame(
      Gene = genes,
      Upper_Probability = F\$Upper,
      Lower_Probability = F\$Lower,
      row.names = NULL
    )
    write.csv(fisher_df, "fisher_results.csv", row.names = FALSE)
    
    # Save Stouffer's method results
    stouffer_df <- data.frame(
      Gene = genes,
      Upper_Probability = S\$Upper,
      Lower_Probability = S\$Lower,
      row.names = NULL
    )
    write.csv(stouffer_df, "stouffer_results.csv", row.names = FALSE)
    
    # Save RDS objects for downstream analysis
    saveRDS(F, "fisher_results.rds")
    saveRDS(S, "stouffer_results.rds")
    saveRDS(result, "noiseq_raw_results.rds")
    
    # Generate diagnostic plots of the combined probabilities
    pdf("meta_analysis_probabilities.pdf", width = 8, height = 8)
    par(mfrow = c(2, 2))
    hist(F\$Upper, main = "Fisher Upper Probabilities", xlab = "Probability", col = "skyblue", breaks = 20)
    hist(F\$Lower, main = "Fisher Lower Probabilities", xlab = "Probability", col = "salmon", breaks = 20)
    hist(S\$Upper, main = "Stouffer Upper Probabilities", xlab = "Probability", col = "lightgreen", breaks = 20)
    hist(S\$Lower, main = "Stouffer Lower Probabilities", xlab = "Probability", col = "wheat", breaks = 20)
    dev.off()

    writeLines(c(
        '"BIOC_METASEQ_NOISEQ_META_ANALYSIS":',
        paste0('    metaSeq: ', as.character(packageVersion('metaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_noiseq_meta_analysis.csv versions.yml
    """
}

workflow BIOC_METASEQ_NOISEQ_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BreastCancer, flag1, flag2 ] ]

    main:
    BIOC_METASEQ_NOISEQ_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METASEQ_NOISEQ_META_ANALYSIS.out.tables
    plots    = BIOC_METASEQ_NOISEQ_META_ANALYSIS.out.plots
    objects  = BIOC_METASEQ_NOISEQ_META_ANALYSIS.out.objects
    versions = BIOC_METASEQ_NOISEQ_META_ANALYSIS.out.versions
}
