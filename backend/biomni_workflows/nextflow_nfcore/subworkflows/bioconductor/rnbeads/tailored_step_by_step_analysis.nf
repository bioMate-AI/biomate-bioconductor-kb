#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RnBeads — tailored_step_by_step_analysis
// Execute individual RnBeads modules step-by-step for fine-grained control over array preprocessing, normalization, covariate inference, and differential methylat
// Input: idat, sample_annotation.csv
// Container: quay.io/biocontainers/bioconductor-rnbeads:2.28.0--r45hdfd78af_0
// R packages: RnBeads
// Bioconductor: 3.20 | R: 4.4
// Requires: RnBeads
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize the report directory and start the logger
//  * 2. [Input & Preparation] Import raw data into an RnBSet object
//  * 3. [Core Analysis] Run quality control
//  * 4. [Core Analysis] Run preprocessing (filtering and normalization)
//  * 5. [Core Analysis] Run covariate inference (SVA, cell type estimation, age prediction)
//  * 6. [Core Analysis] Run exploratory analysis (dimension reduction, clustering)
//  * 7. [Core Analysis] Run differential methylation analysis

nextflow.enable.dsl = 2

process BIOC_RNBEADS_TAILORED_STEP_BY_STEP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("RnBeads")
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
    library(RnBeads)
    
    # Define input paths from the working directory
    idat.dir <- "idat"
    sample.annotation <- "sample_annotation.csv"
    
    # Verify that the required user inputs exist
    if (!dir.exists(idat.dir)) {
      stop("Error: 'idat' directory not found in the working directory.")
    }
    if (!file.exists(sample.annotation)) {
      stop("Error: 'sample_annotation.csv' not found in the working directory.")
    }
    
    # Read sample annotation to dynamically configure options
    annot <- read.csv(sample.annotation, stringsAsFactors = FALSE)
    
    # Determine a suitable identifier column
    id_col <- colnames(annot)[1]
    if ("Sample_ID" %in% colnames(annot)) {
      id_col <- "Sample_ID"
    } else if ("Sample_Name" %in% colnames(annot)) {
      id_col <- "Sample_Name"
    }
    
    # Determine potential comparison columns for differential analysis
    # Select columns with more than 1 but fewer than the total number of samples categories
    potential_cmp_cols <- c()
    for (col in colnames(annot)) {
      val_count <- length(unique(na.omit(annot[[col]])))
      if (val_count > 1 && val_count < nrow(annot)) {
        potential_cmp_cols <- c(potential_cmp_cols, col)
      }
    }
    
    # Configure RnBeads options
    rnb.options(
      filtering.sex.chromosomes.removal = TRUE,
      identifiers.column = id_col,
      disk.dump.big.matrices = TRUE,
      import.sex.prediction = TRUE
    )
    
    if (length(potential_cmp_cols) > 0) {
      rnb.options(differential.comparison.columns = potential_cmp_cols)
    }
    
    # Define analysis and report directories
    analysis.dir <- "analysis"
    if (!dir.exists(analysis.dir)) {
      dir.create(analysis.dir, recursive = TRUE)
    }
    
    report.dir <- file.path(analysis.dir, "reports_details")
    if (dir.exists(report.dir)) {
      unlink(report.dir, recursive = TRUE)
    }
    
    # ==========================================
    # EXECUTE DOCUMENTED WORKFLOW STEP-BY-STEP
    # ==========================================
    
    # 1. Initialize reports and start logger
    rnb.initialize.reports(report.dir)
    logger.start(fname = NA)
    
    # 2. Import raw data
    data.source <- c(idat.dir, sample.annotation)
    result <- rnb.run.import(data.source = data.source,
        data.type = "infinium.idat.dir", dir.reports = report.dir)
    rnb.set <- result\$rnb.set
    
    # 3. Run quality control
    rnb.run.qc(rnb.set, report.dir)
    
    # 4. Run preprocessing (filtering and normalization)
    rnb.set.unfiltered <- rnb.set
    result <- rnb.run.preprocessing(rnb.set.unfiltered, dir.reports = report.dir)
    rnb.set <- result\$rnb.set
    
    # 5. Run covariate inference
    rnb.set <- rnb.run.inference(rnb.set, report.dir)\$rnb.set
    
    # 6. Run exploratory analysis
    rnb.run.exploratory(rnb.set, report.dir)
    
    # 7. Run differential methylation analysis
    rnb.run.differential(rnb.set, report.dir)
    
    # Close the logger
    logger.completed()
    
    # ==========================================
    # WRITE MEANINGFUL OUTPUTS
    # ==========================================
    
    # 1. Save the final RnBSet object
    save.dir <- file.path(analysis.dir, "rnb_set_final")
    if (dir.exists(save.dir)) {
      unlink(save.dir, recursive = TRUE)
    }
    save.rnb.set(rnb.set, path = save.dir, archive = TRUE)
    
    # 2. Export methylation beta values to CSV
    beta_values <- meth(rnb.set)
    write.csv(beta_values, file = file.path(analysis.dir, "methylation_beta_values.csv"), row.names = TRUE)
    
    # 3. Export phenotypic metadata to CSV
    pheno_data <- pheno(rnb.set)
    write.csv(pheno_data, file = file.path(analysis.dir, "phenotypic_metadata_cleaned.csv"), row.names = TRUE)
    
    # 4. Generate and save a diagnostic PDF plot of Beta Distributions
    pdf(file = file.path(analysis.dir, "beta_distribution_summary.pdf"), width = 8, height = 6)
    if (ncol(beta_values) > 0) {
      plot(density(beta_values[, 1], na.rm = TRUE), 
           main = "Density Plot of Methylation Beta Values", 
           xlab = "Beta Value", 
           ylab = "Density", 
           col = "blue", 
           lty = 1, 
           lwd = 1.5)
      if (ncol(beta_values) > 1) {
        for (i in 2:ncol(beta_values)) {
          lines(density(beta_values[, i], na.rm = TRUE), col = "blue", lty = 1)
        }
      }
    } else {
      plot(1, type = "n", xlab = "", ylab = "", main = "No Beta Values Available")
    }
    dev.off()

    writeLines(c(
        '"BIOC_RNBEADS_TAILORED_STEP_BY_STEP_ANALYSIS":',
        paste0('    RnBeads: ', as.character(packageVersion('RnBeads')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tailored_step_by_step_analysis.csv versions.yml
    """
}

workflow BIOC_RNBEADS_TAILORED_STEP_BY_STEP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ idat, sample_annotation.csv ] ]

    main:
    BIOC_RNBEADS_TAILORED_STEP_BY_STEP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNBEADS_TAILORED_STEP_BY_STEP_ANALYSIS.out.tables
    plots    = BIOC_RNBEADS_TAILORED_STEP_BY_STEP_ANALYSIS.out.plots
    objects  = BIOC_RNBEADS_TAILORED_STEP_BY_STEP_ANALYSIS.out.objects
    versions = BIOC_RNBEADS_TAILORED_STEP_BY_STEP_ANALYSIS.out.versions
}
