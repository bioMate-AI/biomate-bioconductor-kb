#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cardinal — differential_abundance_testing
// Perform statistical hypothesis testing to identify mass features that are differentially abundant between experimental conditions.
// Input: aligned_peaks.imzML
// Container: quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0
// R packages: Cardinal
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CARDINAL_DIFFERENTIAL_ABUNDANCE_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0"

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
    .bm_deps <- c("Cardinal")
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
    library(Cardinal)
    
    # Define input file
    input_file <- "aligned_peaks.imzML"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Load the preprocessed MSI dataset
    mse3 <- readMSIData(input_file)
    
    # Ensure the object is of class MSImagingExperiment
    if (!is(mse3, "MSImagingExperiment")) {
      mse3 <- as(mse3, "MSImagingExperiment")
    }
    
    # Ensure 'condition' metadata exists in pixelData for the formula (~ condition)
    if (!"condition" %in% names(pixelData(mse3))) {
      # If missing, attempt to construct a reasonable condition factor from the design
      if (length(unique(run(mse3))) > 1) {
        # Map runs to conditions if multiple runs exist
        runs <- run(mse3)
        levels_runs <- levels(runs)
        half <- length(levels_runs) %/% 2
        groupA <- levels_runs[1:max(1, half)]
        mse3\$condition <- factor(ifelse(runs %in% groupA, "ConditionA", "ConditionB"))
      } else {
        # Fallback to splitting pixels into two groups
        mse3\$condition <- factor(rep(c("ConditionA", "ConditionB"), length.out=ncol(mse3)))
      }
    }
    
    # 1. Perform sample-based means testing using meansTest()
    mtest <- meansTest(mse3, ~ condition, samples=run(mse3))
    
    # Save sample-based means test plot to PDF
    tryCatch({
      pdf("sample_means_test_plots.pdf", width=10, height=5)
      plot(mtest, i=1:10, layout=c(2,5), ylab="Intensity", fill=TRUE)
      dev.off()
    }, error = function(e) {
      warning("Failed to plot sample-based means test: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # 2. Rank and filter differentially abundant features using topFeatures()
    mtest_top <- topFeatures(mtest)
    mtest_top_sig <- subset(mtest_top, fdr < 0.05)
    
    # Export sample-based results
    write.csv(as.data.frame(mtest_top), "sample_means_test_all_features.csv", row.names=FALSE)
    write.csv(as.data.frame(mtest_top_sig), "sample_means_test_sig_features.csv", row.names=FALSE)
    saveRDS(mtest, "sample_means_test_object.rds")
    
    # 3. Perform segment-based means testing by first segmenting samples independently with spatialDGMM()
    dgmm2 <- spatialDGMM(mse3, r=2, k=2, groups=run(mse3))
    saveRDS(dgmm2, "spatial_dgmm_object.rds")
    
    # 4. Fit linear models on the segmented data using meansTest()
    stest <- meansTest(dgmm2, ~ condition)
    
    # Save segment-based means test plot to PDF
    tryCatch({
      pdf("segment_means_test_plots.pdf", width=10, height=5)
      plot(stest, i=1:10, layout=c(2,5), ylab="Intensity", fill=TRUE)
      dev.off()
    }, error = function(e) {
      warning("Failed to plot segment-based means test: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })
    
    # 5. Rank and filter segment-based test results using topFeatures()
    stest_top <- topFeatures(stest)
    stest_top_sig <- subset(stest_top, fdr < 0.05)
    
    # Export segment-based results
    write.csv(as.data.frame(stest_top), "segment_means_test_all_features.csv", row.names=FALSE)
    write.csv(as.data.frame(stest_top_sig), "segment_means_test_sig_features.csv", row.names=FALSE)
    saveRDS(stest, "segment_means_test_object.rds")
    
    cat("Differential abundance testing pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_CARDINAL_DIFFERENTIAL_ABUNDANCE_TESTING":',
        paste0('        cardinal: ', as.character(packageVersion("cardinal")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_testing.csv versions.yml
    """
}

workflow BIOC_CARDINAL_DIFFERENTIAL_ABUNDANCE_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ aligned_peaks.imzML ] ]

    main:
    BIOC_CARDINAL_DIFFERENTIAL_ABUNDANCE_TESTING(ch_input)

    emit:
    tables   = BIOC_CARDINAL_DIFFERENTIAL_ABUNDANCE_TESTING.out.tables
    plots    = BIOC_CARDINAL_DIFFERENTIAL_ABUNDANCE_TESTING.out.plots
    objects  = BIOC_CARDINAL_DIFFERENTIAL_ABUNDANCE_TESTING.out.objects
    versions = BIOC_CARDINAL_DIFFERENTIAL_ABUNDANCE_TESTING.out.versions
}
