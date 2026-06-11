#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: M3Drop — umi_nbumi_workflow
// Perform dropout-based feature selection and calculate Pearson residuals for UMI-tagged single-cell RNA-seq data using the depth-adjusted negative binomial (DANB
// Input: count_mat
// Container: quay.io/biocontainers/bioconductor-m3drop:1.36.0--r45hdfd78af_0
// R packages: M3Drop
// Bioconductor: 3.20 | R: 4.4
// Requires: M3Drop
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert and format raw counts using NBumiConvertData
//  * 2. [Core Analysis] Fit the depth-adjusted negative binomial model using NBumiFitModel
//  * 3. [Core Analysis] Check model fit using NBumiCheckFitFS
//  * 4. [Core Analysis] Perform feature selection using NBumiFeatureSelectionCombinedDrop
//  * 5. [Core Analysis] Calculate exact or approximate Pearson residuals using NBumiPearsonResiduals or NBumiPearsonResidualsApprox
//  * 6. [Core Analysis] Clip residuals to reduce the effect of extreme outliers

nextflow.enable.dsl = 2

process BIOC_M3DROP_UMI_NBUMI_WORKFLOW {
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
    .bm_deps <- c("M3Drop")
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
    library(M3Drop)
    
    # Locate and read the input count matrix
    # The pipeline expects a file named 'count_mat' (with .rds, .csv, or .tsv extension, or no extension)
    input_file <- NULL
    possible_files <- c("count_mat.rds", "count_mat.csv", "count_mat.tsv", "count_mat")
    
    for (f in possible_files) {
      if (file.exists(f)) {
        input_file <- f
        break
      }
    }
    
    if (is.null(input_file)) {
      stop("Error: Input file 'count_mat' (RDS, CSV, or TSV) not found in the working directory.")
    }
    
    message("Reading input file: ", input_file)
    if (grepl("\\\\.rds\$", input_file, ignore.case = TRUE)) {
      raw_counts <- readRDS(input_file)
    } else if (grepl("\\\\.csv\$", input_file, ignore.case = TRUE)) {
      raw_counts <- as.matrix(read.csv(input_file, row.names = 1, check.names = FALSE))
    } else if (grepl("\\\\.tsv\$", input_file, ignore.case = TRUE)) {
      raw_counts <- as.matrix(read.delim(input_file, row.names = 1, check.names = FALSE))
    } else {
      # Fallback for extensionless file: try RDS first, then CSV
      raw_counts <- tryCatch({
        readRDS(input_file)
      }, error = function(e) {
        tryCatch({
          as.matrix(read.csv(input_file, row.names = 1, check.names = FALSE))
        }, error = function(e2) {
          stop("Failed to parse 'count_mat' as RDS or CSV.")
        })
      })
    }
    
    # Ensure raw_counts is a matrix or sparse matrix
    if (!is.matrix(raw_counts) && !inherits(raw_counts, "Matrix")) {
      raw_counts <- as.matrix(raw_counts)
    }
    
    # 1. Convert and format raw counts using NBumiConvertData
    count_mat <- NBumiConvertData(raw_counts, is.counts=TRUE)
    
    # 2. Fit the depth-adjusted negative binomial model using NBumiFitModel
    DANB_fit <- NBumiFitModel(count_mat)
    
    # 3. Check model fit using NBumiCheckFitFS and save plots
    pdf("nbumi_fit_plots.pdf", width = 10, height = 5)
    par(mfrow=c(1,2))
    stats <- NBumiCheckFitFS(count_mat, DANB_fit)
    dev.off()
    
    # Print fit errors
    print(c(stats\$gene_error, stats\$cell_error))
    
    # 4. Perform feature selection using NBumiFeatureSelectionCombinedDrop
    pdf("nbumi_feature_selection_plot.pdf", width = 7, height = 7)
    NBDropFS <- NBumiFeatureSelectionCombinedDrop(DANB_fit, method="fdr", qval.thres=0.01, suppress.plot=FALSE)
    dev.off()
    
    # 5. Calculate exact or approximate Pearson residuals
    pearson1 <- NBumiPearsonResiduals(count_mat, DANB_fit)
    pearson2 <- NBumiPearsonResidualsApprox(count_mat, DANB_fit)
    
    # 6. Clip residuals to reduce the effect of extreme outliers
    pearson1[pearson1 > sqrt(ncol(count_mat))] <- sqrt(ncol(count_mat))
    pearson1[pearson1 < -sqrt(ncol(count_mat))] <- -1*sqrt(ncol(count_mat))
    
    # Save outputs
    message("Saving outputs...")
    write.csv(NBDropFS, "nbumi_feature_selection_results.csv", row.names = TRUE)
    write.csv(data.frame(gene_error = stats\$gene_error, cell_error = stats\$cell_error), "fit_stats.csv", row.names = FALSE)
    saveRDS(pearson1, "pearson_residuals_exact.rds")
    saveRDS(pearson2, "pearson_residuals_approx.rds")
    saveRDS(DANB_fit, "danb_fit.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_M3DROP_UMI_NBUMI_WORKFLOW":',
        paste0('    M3Drop: ', as.character(packageVersion('M3Drop')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_umi_nbumi_workflow.csv versions.yml
    """
}

workflow BIOC_M3DROP_UMI_NBUMI_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_mat ] ]

    main:
    BIOC_M3DROP_UMI_NBUMI_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_M3DROP_UMI_NBUMI_WORKFLOW.out.tables
    plots    = BIOC_M3DROP_UMI_NBUMI_WORKFLOW.out.plots
    objects  = BIOC_M3DROP_UMI_NBUMI_WORKFLOW.out.objects
    versions = BIOC_M3DROP_UMI_NBUMI_WORKFLOW.out.versions
}
