#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TOAST — correlated_differential_analysis_cedar
// Detect cell-type specific differential signals by incorporating DE/DM state correlation among cell types using a hierarchical tree structure (CEDAR).
// Input: Y_raw, Prop, design
// Container: quay.io/biocontainers/bioconductor-toast:1.24.0--r45hdfd78af_0
// R packages: TOAST
// Bioconductor: 3.20 | R: 4.4
// Requires: TOAST
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the CEDAR algorithm using cedar() to perform joint inference of differential signals across correlated cell types. 2. Extract 

nextflow.enable.dsl = 2

process BIOC_TOAST_CORRELATED_DIFFERENTIAL_ANALYSIS_CEDAR {
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
    .bm_deps <- c("TOAST")
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
    library(TOAST)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    # The pipeline reads Y_raw, Prop, and design from the working directory.
    # We support both RDS (recommended for preserving matrix/SE structures)
    # and CSV formats.
    
    # Read Y_raw (matrix or SummarizedExperiment)
    if (file.exists("Y_raw.rds")) {
      Y_raw <- readRDS("Y_raw.rds")
    } else if (file.exists("Y_raw.csv")) {
      Y_raw <- as.matrix(read.csv("Y_raw.csv", row.names = 1))
    } else {
      stop("Error: Y_raw file not found. Please provide Y_raw.rds or Y_raw.csv in the working directory.")
    }
    
    # Read Prop (matrix of cell type proportions)
    if (file.exists("Prop.rds")) {
      Prop <- readRDS("Prop.rds")
    } else if (file.exists("Prop.csv")) {
      Prop <- as.matrix(read.csv("Prop.csv", row.names = 1))
    } else {
      stop("Error: Prop file not found. Please provide Prop.rds or Prop.csv in the working directory.")
    }
    
    # Read design (data frame of sample phenotypes)
    if (file.exists("design.rds")) {
      design <- readRDS("design.rds")
    } else if (file.exists("design.csv")) {
      design <- read.csv("design.csv", row.names = 1)
    } else {
      stop("Error: design file not found. Please provide design.rds or design.csv in the working directory.")
    }
    
    # ----------------------------------------------------------------------
    # 2. Preprocessing & Validation
    # ----------------------------------------------------------------------
    # Ensure the factor of interest ('disease') is present and formatted as a factor
    if (!"disease" %in% colnames(design)) {
      stop("Error: The design data frame must contain a 'disease' column for this workflow.")
    }
    design\$disease <- as.factor(design\$disease)
    
    # Ensure column names of Prop match cell types and dimensions are compatible
    if (is.null(colnames(Prop))) {
      colnames(Prop) <- paste0("CellType", seq_len(ncol(Prop)))
    }
    
    # ----------------------------------------------------------------------
    # 3. Run CEDAR Algorithm (Documented Code)
    # ----------------------------------------------------------------------
    # Run the CEDAR algorithm to perform joint inference of differential signals
    # across correlated cell types using a hierarchical tree structure.
    res_cedar <- cedar(
      Y_raw = Y_raw,
      prop = Prop,
      design.1 = design,
      factor.to.test = 'disease',
      cutoff.tree = c('pval', 0.01),
      cutoff.prior.prob = c('pval', 0.01)
    )
    
    # Extract and display posterior probabilities and tree structures
    head(res_cedar\$tree_res\$full\$pp)
    res_cedar\$tree_res\$full\$tree_structure
    res_cedar\$tree_res\$single\$tree_structure
    
    # ----------------------------------------------------------------------
    # 4. Write Outputs
    # ----------------------------------------------------------------------
    # Save the complete results object
    saveRDS(res_cedar, "res_cedar_output.rds")
    
    # Save posterior probabilities for the full tree structure
    if (!is.null(res_cedar\$tree_res\$full\$pp)) {
      write.csv(res_cedar\$tree_res\$full\$pp, "cedar_posterior_probabilities_full.csv", row.names = TRUE)
    }
    
    # Save posterior probabilities for the single tree structure
    if (!is.null(res_cedar\$tree_res\$single\$pp)) {
      write.csv(res_cedar\$tree_res\$single\$pp, "cedar_posterior_probabilities_single.csv", row.names = TRUE)
    }
    
    # Save estimated tree structures
    if (!is.null(res_cedar\$tree_res\$full\$tree_structure)) {
      write.csv(res_cedar\$tree_res\$full\$tree_structure, "cedar_tree_structure_full.csv", row.names = TRUE)
    }
    
    if (!is.null(res_cedar\$tree_res\$single\$tree_structure)) {
      write.csv(res_cedar\$tree_res\$single\$tree_structure, "cedar_tree_structure_single.csv", row.names = TRUE)
    }
    
    cat("CEDAR workflow completed successfully. Outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_TOAST_CORRELATED_DIFFERENTIAL_ANALYSIS_CEDAR":',
        paste0('    TOAST: ', as.character(packageVersion('TOAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlated_differential_analysis_cedar.csv versions.yml
    """
}

workflow BIOC_TOAST_CORRELATED_DIFFERENTIAL_ANALYSIS_CEDAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y_raw, Prop, design ] ]

    main:
    BIOC_TOAST_CORRELATED_DIFFERENTIAL_ANALYSIS_CEDAR(ch_input)

    emit:
    tables   = BIOC_TOAST_CORRELATED_DIFFERENTIAL_ANALYSIS_CEDAR.out.tables
    plots    = BIOC_TOAST_CORRELATED_DIFFERENTIAL_ANALYSIS_CEDAR.out.plots
    objects  = BIOC_TOAST_CORRELATED_DIFFERENTIAL_ANALYSIS_CEDAR.out.objects
    versions = BIOC_TOAST_CORRELATED_DIFFERENTIAL_ANALYSIS_CEDAR.out.versions
}
