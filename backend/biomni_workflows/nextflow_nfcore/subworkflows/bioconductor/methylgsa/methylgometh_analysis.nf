#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylGSA — methylgometh_analysis
// Perform gene set analysis adjusting for CpG probe density using weighted resampling and Wallenius non-central hypergeometric approximation via missMethyl.
// Input: cpg.pval
// Container: quay.io/biocontainers/bioconductor-methylgsa:1.16.0--r42hdfd78af_0
// R packages: IlluminaHumanMethylation450kanno.ilmn12.hg19, methylGSA
// Bioconductor: 3.20 | R: 4.4
// Requires: IlluminaHumanMethylation450kanno.ilmn12.hg19, methylGSA
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and array annotation
//  * 2. [Core Analysis] Run hypergeometric-based testing using methylgometh with a specified significance cutoff

nextflow.enable.dsl = 2

process BIOC_METHYLGSA_METHYLGOMETH_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("IlluminaHumanMethylation450kanno.ilmn12.hg19", "methylGSA")
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
        
        # Load required libraries
        library(methylGSA)
        library(IlluminaHumanMethylation450kanno.ilmn12.hg19)
        
        # Helper function to robustly read the user input file 'cpg.pval'
        read_cpg_pval <- function(filepath) {
          if (!file.exists(filepath)) {
            stop(paste("Required input file '", filepath, "' not found in the working directory.", sep = ""))
          }
          
          # Attempt 1: Read as RDS
          res <- tryCatch({
            readRDS(filepath)
          }, error = function(e) {
            NULL
          })
          
          if (!is.null(res) && is.numeric(res) && !is.null(names(res))) {
            message("Successfully loaded 'cpg.pval' as an RDS named numeric vector.")
            return(res)
          }
          
          # Attempt 2: Read as a two-column table (e.g., TSV or CSV)
          message("Attempting to read 'cpg.pval' as a table...")
          tbl <- tryCatch({
            read.table(filepath, header = TRUE, stringsAsFactors = FALSE)
          }, error = function(e) {
            read.table(filepath, header = FALSE, stringsAsFactors = FALSE)
          })
          
          if (ncol(tbl) >= 2) {
            vec <- as.numeric(tbl[, 2])
            names(vec) <- as.character(tbl[, 1])
            message("Successfully loaded 'cpg.pval' from table format.")
            return(vec)
          }
          
          stop("Failed to parse 'cpg.pval'. It must be a named numeric vector (RDS) or a two-column table (CpG ID, p-value).")
        }
        
        # Read the user input
        cpg.pval <- read_cpg_pval("cpg.pval")
        
        # Run hypergeometric-based testing using methylgometh with specified parameters
        message("Running methylgometh analysis...")
        res4 = methylgometh(cpg.pval = cpg.pval, sig.cut = 0.001,
                                minsize = 200, maxsize = 210)
        
        # Save meaningful results
        message("Saving results...")
        write.csv(res4, file = "methylgometh_results.csv", row.names = FALSE)
        saveRDS(res4, file = "methylgometh_results.rds")
        
        # Generate and save visualization plot
        message("Generating barplot...")
        pdf("methylgometh_barplot.pdf", width = 8, height = 6)
        tryCatch({
          print(barplot(res4, num = 8, colorby = "pvalue"))
        }, error = function(e) {
          warning("Could not generate barplot: ", e\$message)
        })
        dev.off()
        
        message("Pipeline completed successfully. Outputs written to 'methylgometh_results.csv', 'methylgometh_results.rds', and 'methylgometh_barplot.pdf'.")

    writeLines(c(
        '"BIOC_METHYLGSA_METHYLGOMETH_ANALYSIS":',
        paste0('    methylGSA: ', as.character(packageVersion('methylGSA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylgometh_analysis.csv versions.yml
    """
}

workflow BIOC_METHYLGSA_METHYLGOMETH_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cpg.pval ] ]

    main:
    BIOC_METHYLGSA_METHYLGOMETH_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHYLGSA_METHYLGOMETH_ANALYSIS.out.tables
    plots    = BIOC_METHYLGSA_METHYLGOMETH_ANALYSIS.out.plots
    objects  = BIOC_METHYLGSA_METHYLGOMETH_ANALYSIS.out.objects
    versions = BIOC_METHYLGSA_METHYLGOMETH_ANALYSIS.out.versions
}
