#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RNAAgeCalc — predict_age_dataframe
// Calculate transcriptional age and age acceleration residuals from a gene expression data frame or matrix and visualize the results.
// Input: fpkm, chronage
// Container: quay.io/biocontainers/bioconductor-rnaagecalc:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RNAAgeCalc
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the package and expression data
//  * 2. [Visualization & Output] Define chronological age data frame
//  * 3. [Visualization & Output] Predict age using predict_age
//  * 4. [Visualization & Output] Visualize results using makeplot

nextflow.enable.dsl = 2

process BIOC_RNAAGECALC_PREDICT_AGE_DATAFRAME {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("RNAAgeCalc")
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
        
        # --- Load the package and expression data ---
        library(RNAAgeCalc)
        
        # Helper function to robustly read the fpkm input file
        read_fpkm <- function() {
          files <- c("fpkm", "fpkm.csv", "fpkm.tsv", "fpkm.txt")
          for (f in files) {
            if (file.exists(f)) {
              expr <- tryCatch({
                read.csv(f, row.names = 1, check.names = FALSE)
              }, error = function(e) {
                read.table(f, header = TRUE, row.names = 1, check.names = FALSE)
              })
              return(as.matrix(expr))
            }
          }
          stop("Required input file 'fpkm' (or with .csv/.tsv/.txt extension) not found in the working directory.")
        }
        
        fpkm <- read_fpkm()
        
        # --- Define chronological age data frame ---
        # Helper function to robustly read the chronage input file
        read_chronage <- function() {
          files <- c("chronage", "chronage.csv", "chronage.tsv", "chronage.txt")
          for (f in files) {
            if (file.exists(f)) {
              df <- tryCatch({
                read.csv(f, check.names = FALSE)
              }, error = function(e) {
                read.table(f, header = TRUE, check.names = FALSE)
              })
              return(df)
            }
          }
          stop("Required input file 'chronage' (or with .csv/.tsv/.txt extension) not found in the working directory.")
        }
        
        chronage <- read_chronage()
        
        # --- Predict age using predict_age ---
        res <- predict_age(exprdata = fpkm, exprtype = "FPKM", 
                          chronage = chronage)
        
        # Save the prediction results
        write.csv(res, "rna_age_results.csv", row.names = TRUE)
        saveRDS(res, "rna_age_results.rds")
        
        # --- Visualize results using makeplot ---
        pdf("rna_age_plot.pdf", width = 7, height = 7)
        print(makeplot(res))
        dev.off()

    writeLines(c(
        '"BIOC_RNAAGECALC_PREDICT_AGE_DATAFRAME":',
        paste0('    RNAAgeCalc: ', as.character(packageVersion('RNAAgeCalc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_age_dataframe.csv versions.yml
    """
}

workflow BIOC_RNAAGECALC_PREDICT_AGE_DATAFRAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fpkm, chronage ] ]

    main:
    BIOC_RNAAGECALC_PREDICT_AGE_DATAFRAME(ch_input)

    emit:
    tables   = BIOC_RNAAGECALC_PREDICT_AGE_DATAFRAME.out.tables
    plots    = BIOC_RNAAGECALC_PREDICT_AGE_DATAFRAME.out.plots
    objects  = BIOC_RNAAGECALC_PREDICT_AGE_DATAFRAME.out.objects
    versions = BIOC_RNAAGECALC_PREDICT_AGE_DATAFRAME.out.versions
}
