#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: proloc — supervised_classification_svm
// Optimize SVM parameters and predict protein sub-cellular localization using supervised machine learning.
// Input: exprsFile.csv, fdataFile.csv, pdataFile.csv
// Container: quay.io/biocontainers/bioconductor-proloc:1.50.0--r45ha27e39d_0
// R packages: biocmanager, class, knitr, MSnbase, pRoloc, pRolocGUI
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROLOC_SUPERVISED_CLASSIFICATION_SVM {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-proloc:1.50.0--r45ha27e39d_0"

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
    .bm_deps <- c("biocmanager", "class", "knitr", "MSnbase", "pRoloc", "pRolocGUI")
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
    library(MSnbase)
    library(pRoloc)
    
    # Define input file paths
    f1 <- "exprsFile.csv"
    f2 <- "fdataFile.csv"
    f3 <- "pdataFile.csv"
    
    # Check for existence of input files
    if (!file.exists(f1)) {
      stop(paste("Error: Input file missing:", f1))
    }
    if (!file.exists(f2)) {
      stop(paste("Error: Input file missing:", f2))
    }
    if (!file.exists(f3)) {
      stop(paste("Error: Input file missing:", f3))
    }
    
    # 1. Import quantitative and metadata files into an MSnSet object
    tan2009r1 <- readMSnSet(exprsFile = f1, featureDataFile = f2, phenoDataFile = f3, sep = ",")
    
    # Ensure the markers column exists
    if (!"markers" %in% fvarLabels(tan2009r1)) {
      stop("The feature metadata must contain a 'markers' column for supervised classification.")
    }
    
    # 2. Normalize the expression data to sum to 1
    itraqdata <- tan2009r1
    itraqnorm <- normalise(itraqdata, method = "sum")
    tan2009r1 <- itraqnorm
    
    # 3. Optimize SVM hyperparameters (cost and sigma) via grid search and cross-validation
    params <- svmOptimisation(tan2009r1, times = 10, xval = 5, verbose = FALSE)
    
    # 4. Train the classifier and predict localization of unknown proteins
    tan2009r1 <- svmClassification(tan2009r1, params)
    
    # Write outputs
    # Save the classification results to CSV
    write.csv(fData(tan2009r1), file = "svm_classification_results.csv", row.names = TRUE)
    
    # Save the optimized parameters and the final MSnSet object to RDS
    saveRDS(params, file = "svm_params.rds")
    saveRDS(tan2009r1, file = "svm_classified_msnset.rds")
    
    # Generate a PCA plot of the classification results and save to PDF
    tryCatch({
      pdf("svm_classification_plot.pdf", width = 8, height = 6)
      plot2D(tan2009r1, fcol = "svm")
      addLegend(tan2009r1, fcol = "svm", where = "topright", bty = "n", cex = 0.8)
      dev.off()
    }, error = function(e) {
      warning("Could not generate the PDF plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_PROLOC_SUPERVISED_CLASSIFICATION_SVM":',
        paste0('        proloc: ', as.character(packageVersion("proloc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_classification_svm.csv versions.yml
    """
}

workflow BIOC_PROLOC_SUPERVISED_CLASSIFICATION_SVM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprsFile.csv, fdataFile.csv, pdataFile.csv ] ]

    main:
    BIOC_PROLOC_SUPERVISED_CLASSIFICATION_SVM(ch_input)

    emit:
    tables   = BIOC_PROLOC_SUPERVISED_CLASSIFICATION_SVM.out.tables
    plots    = BIOC_PROLOC_SUPERVISED_CLASSIFICATION_SVM.out.plots
    objects  = BIOC_PROLOC_SUPERVISED_CLASSIFICATION_SVM.out.objects
    versions = BIOC_PROLOC_SUPERVISED_CLASSIFICATION_SVM.out.versions
}
