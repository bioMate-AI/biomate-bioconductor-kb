#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: safe — survival_safe_analysis
// Perform pathway analysis for right-censored survival data using martingale residuals.
// Input: e3.upp, p3.upp$t.rfs, p3.upp$e.rfs, C.mat
// Container: quay.io/biocontainers/bioconductor-safe:3.50.0--r45hdfd78af_0
// R packages: safe, survival
// Bioconductor: 3.20 | R: 4.4
// Requires: safe, survival
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute Cox residuals using getCOXresiduals
//  * 2. [Core Analysis] Run safe on the residuals

nextflow.enable.dsl = 2

process BIOC_SAFE_SURVIVAL_SAFE_ANALYSIS {
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
    .bm_deps <- c("safe", "survival")
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
        library(safe)
        library(survival)
        
        # ----------------------------------------------------------------------
        # 1. Read User Input Files
        # ----------------------------------------------------------------------
        
        # Load e3.upp (gene expression matrix)
        if (file.exists("e3.upp.rds")) {
          e3.upp <- readRDS("e3.upp.rds")
        } else if (file.exists("e3.upp")) {
          e3.upp <- readRDS("e3.upp")
        } else if (file.exists("e3.upp.csv")) {
          e3.upp <- as.matrix(read.csv("e3.upp.csv", row.names = 1))
        } else {
          stop("Required input file 'e3.upp' (RDS or CSV) not found in the working directory.")
        }
        
        # Load p3.upp (survival data frame/list containing t.rfs and e.rfs)
        if (file.exists("p3.upp.rds")) {
          p3.upp <- readRDS("p3.upp.rds")
        } else if (file.exists("p3.upp")) {
          p3.upp <- readRDS("p3.upp")
        } else if (file.exists("p3.upp.csv")) {
          p3.upp <- read.csv("p3.upp.csv")
        } else {
          stop("Required input file 'p3.upp' (RDS or CSV) not found in the working directory.")
        }
        
        # Load C.mat (category matrix)
        if (file.exists("C.mat.rds")) {
          C.mat <- readRDS("C.mat.rds")
        } else if (file.exists("C.mat")) {
          C.mat <- readRDS("C.mat")
        } else if (file.exists("C.mat.csv")) {
          C.mat <- as.matrix(read.csv("C.mat.csv", row.names = 1))
        } else {
          stop("Required input file 'C.mat' (RDS or CSV) not found in the working directory.")
        }
        
        # ----------------------------------------------------------------------
        # 2. Execute Documented Workflow
        # ----------------------------------------------------------------------
        
        drop <- is.na(p3.upp\$t.rfs)
        Xy <- getCOXresiduals(e3.upp[,!drop], p3.upp\$t.rfs[!drop], 
                              p3.upp\$e.rfs[!drop])
        results2 <- safe(Xy\$X.star, Xy\$y.star, C.mat, 
                         print.it = FALSE)
        
        # ----------------------------------------------------------------------
        # 3. Save Outputs
        # ----------------------------------------------------------------------
        
        # Save the complete SAFE results object
        saveRDS(results2, "safe_survival_results.rds")
        
        # Generate and save the top table of results
        toptable_df <- safe.toptable(results2, number = 10)
        write.csv(toptable_df, "safe_survival_toptable.csv", row.names = FALSE)
        
        # Attempt to generate a SAFE plot for the top category
        tryCatch({
          if (nrow(toptable_df) > 0) {
            top_cat <- toptable_df\$GenesetID[1]
            pdf("safe_survival_plot.pdf")
            safeplot(results2, cat.name = top_cat)
            dev.off()
          }
        }, error = function(e) {
          message("Could not generate SAFE plot: ", e\$message)
        })

    writeLines(c(
        '"BIOC_SAFE_SURVIVAL_SAFE_ANALYSIS":',
        paste0('    safe: ', as.character(packageVersion('safe')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_safe_analysis.csv versions.yml
    """
}

workflow BIOC_SAFE_SURVIVAL_SAFE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ e3.upp, p3.upp$t.rfs, p3.upp$e.rfs, C.mat ] ]

    main:
    BIOC_SAFE_SURVIVAL_SAFE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SAFE_SURVIVAL_SAFE_ANALYSIS.out.tables
    plots    = BIOC_SAFE_SURVIVAL_SAFE_ANALYSIS.out.plots
    objects  = BIOC_SAFE_SURVIVAL_SAFE_ANALYSIS.out.objects
    versions = BIOC_SAFE_SURVIVAL_SAFE_ANALYSIS.out.versions
}
