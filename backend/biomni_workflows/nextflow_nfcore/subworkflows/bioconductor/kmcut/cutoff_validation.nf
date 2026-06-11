#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kmcut — cutoff_validation
// Validate previously determined stratification cutoffs on an independent validation dataset.
// Input: expression_data_1.txt, expression_data_2.txt, survival_data.txt
// Container: quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0
// R packages: kmcut
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KMCUT_CUTOFF_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0"

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
    .bm_deps <- c("kmcut")
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
    
    # Load the required Bioconductor package
    library(kmcut)
    
    # Define input file paths from the working directory
    fdat1 <- "expression_data_1.txt"
    fdat2 <- "expression_data_2.txt"
    sdat <- "survival_data.txt"
    
    # Validate that the required user input files exist
    if (!file.exists(fdat1)) {
      stop("Error: Training expression file 'expression_data_1.txt' not found in the working directory.")
    }
    if (!file.exists(fdat2)) {
      stop("Error: Validation expression file 'expression_data_2.txt' not found in the working directory.")
    }
    if (!file.exists(sdat)) {
      stop("Error: Survival data file 'survival_data.txt' not found in the working directory.")
    }
    
    # 1. Create SummarizedExperiment for training data
    se1 <- create_se_object(efile = fdat1, sfile = sdat)
    saveRDS(se1, "se1_training.rds")
    
    # 2. Run training stratification to generate a cutoff file
    # This generates "training_data_KM_quant_50.txt" and "training_data_KM_quant_50_labels.csv"
    km_qcut(obj = se1, bfname = "training_data", quant = 50, min_uval = 40)
    
    # 3. Create SummarizedExperiment for validation data
    se2 <- create_se_object(efile = fdat2, sfile = sdat)
    saveRDS(se2, "se2_validation.rds")
    
    # 4. Validate the training cutoffs on the validation data
    # This generates "test_KM_val.pdf", "test_KM_val.txt", and "test_KM_val_labels.csv"
    km_val_cut(infile = "training_data_KM_quant_50.txt", obj = se2, bfname = "test", wpdf = TRUE, min_uval = 40)

    writeLines(c(
        '"BIOC_KMCUT_CUTOFF_VALIDATION":',
        paste0('        kmcut: ', as.character(packageVersion("kmcut")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cutoff_validation.csv versions.yml
    """
}

workflow BIOC_KMCUT_CUTOFF_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data_1.txt, expression_data_2.txt, survival_data.txt ] ]

    main:
    BIOC_KMCUT_CUTOFF_VALIDATION(ch_input)

    emit:
    tables   = BIOC_KMCUT_CUTOFF_VALIDATION.out.tables
    plots    = BIOC_KMCUT_CUTOFF_VALIDATION.out.plots
    objects  = BIOC_KMCUT_CUTOFF_VALIDATION.out.objects
    versions = BIOC_KMCUT_CUTOFF_VALIDATION.out.versions
}
