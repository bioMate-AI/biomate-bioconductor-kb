#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirlab — validate_top_overall_interactions
// Predict miRNA-mRNA relationships and validate the top overall predicted interactions across all miRNAs against ground truth.
// Input: dataset.csv, groundtruth.csv
// Container: quay.io/biocontainers/bioconductor-mirlab:1.40.0--r45hdfd78af_0
// R packages: miRLAB
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRLAB_VALIDATE_TOP_OVERALL_INTERACTIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mirlab:1.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("miRLAB")
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
    
    # Load required library
    library(miRLAB)
    
    # Define input file paths
    dataset <- "dataset.csv"
    groundtruth <- "groundtruth.csv"
    
    # Verify that input files exist
    if (!file.exists(dataset)) {
      stop("Error: 'dataset.csv' not found in the working directory.")
    }
    if (!file.exists(groundtruth)) {
      stop("Error: 'groundtruth.csv' not found in the working directory.")
    }
    
    # Dynamically determine cause (miRNA) and effect (mRNA) column indices from dataset.csv
    # miRLAB expects the first row to contain gene symbols.
    header <- colnames(read.csv(dataset, check.names = FALSE, header = TRUE, nrows = 1))
    
    # Identify miRNAs based on common naming patterns (e.g., mir, let, miR)
    is_mirna <- grepl("^(mir|mirna|let|hsa-|-mir-|-let-|mirna)", header, ignore.case = TRUE)
    
    # If pattern matching fails, attempt to use the ground truth file to identify miRNAs
    if (sum(is_mirna) == 0) {
      gt_data <- read.csv(groundtruth, check.names = FALSE, header = TRUE)
      if (ncol(gt_data) >= 1) {
        is_mirna <- header %in% unique(gt_data[, 1])
      }
    }
    
    cause <- which(is_mirna)
    effect <- which(!is_mirna)
    
    # Fallback: if no miRNAs could be identified, assume the first 10% of columns are miRNAs
    if (length(cause) == 0 || length(effect) == 0) {
      n_col <- length(header)
      n_mir <- max(1, floor(n_col * 0.1))
      cause <- 1:n_mir
      effect <- (n_mir + 1):n_col
    }
    
    # 1. Predict miRNA-mRNA relationships using Pearson correlation
    message("Calculating Pearson correlation coefficients...")
    EMTresults = Pearson(dataset, cause, effect)
    
    # 2. Extract the top overall predicted interactions
    message("Extracting top 10 predicted interactions...")
    top10 = Extopk(EMTresults, 10)
    
    # 3. Validate the top interactions against the ground truth
    message("Validating top predictions against ground truth...")
    top10Confirmed = Validation(top10, groundtruth)
    
    # Save results to output files
    message("Saving results...")
    write.csv(as.data.frame(top10), "top10_predictions.csv", row.names = FALSE)
    write.csv(as.data.frame(top10Confirmed), "top10_confirmed.csv", row.names = FALSE)
    saveRDS(top10Confirmed, "top10_confirmed.rds")
    
    message("Pipeline completed successfully. Outputs saved to 'top10_predictions.csv', 'top10_confirmed.csv', and 'top10_confirmed.rds'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MIRLAB_VALIDATE_TOP_OVERALL_INTERACTIONS":
        mirlab: \$(Rscript -e 'cat(as.character(packageVersion("mirlab")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_validate_top_overall_interactions.csv versions.yml
    """
}

workflow BIOC_MIRLAB_VALIDATE_TOP_OVERALL_INTERACTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset.csv, groundtruth.csv ] ]

    main:
    BIOC_MIRLAB_VALIDATE_TOP_OVERALL_INTERACTIONS(ch_input)

    emit:
    tables   = BIOC_MIRLAB_VALIDATE_TOP_OVERALL_INTERACTIONS.out.tables
    plots    = BIOC_MIRLAB_VALIDATE_TOP_OVERALL_INTERACTIONS.out.plots
    objects  = BIOC_MIRLAB_VALIDATE_TOP_OVERALL_INTERACTIONS.out.objects
    versions = BIOC_MIRLAB_VALIDATE_TOP_OVERALL_INTERACTIONS.out.versions
}
