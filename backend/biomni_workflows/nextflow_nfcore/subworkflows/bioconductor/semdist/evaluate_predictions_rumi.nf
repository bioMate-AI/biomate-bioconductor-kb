#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: semdist — evaluate_predictions_rumi
// Evaluate multi-label annotation predictions by calculating remaining uncertainty, misinformation, and semantic distance across thresholds.
// Input: MFO_LABELS_TEST.txt, MFO_PREDS_TEST.txt
// Container: quay.io/biocontainers/bioconductor-semdist:1.44.0--r45hdfd78af_0
// R packages: SemDist
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEMDIST_EVALUATE_PREDICTIONS_RUMI {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-semdist:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("SemDist")
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
    library(SemDist)
    
    # Define input files (must exist in the working directory)
    truefile <- "MFO_LABELS_TEST.txt"
    predfile <- "MFO_PREDS_TEST.txt"
    
    # Check if files exist before proceeding
    if (!file.exists(truefile)) {
      stop(paste("Required true annotations file not found:", truefile))
    }
    if (!file.exists(predfile)) {
      stop(paste("Required predicted annotations file not found:", predfile))
    }
    
    # --- Load true and predicted annotation files ---
    predictions <- read.table(predfile, colClasses = "character")
    message("First few rows of predictions:")
    print(head(predictions))
    
    # --- Calculate RU and MI at a single threshold using findRUMI ---
    message("Calculating RU and MI at threshold 0.75...")
    rumiTable <- findRUMI("MF", "human", 0.75, truefile, predfile)
    avgRU <- mean(rumiTable\$RU)
    avgMI <- mean(rumiTable\$MI)
    
    message(paste("Average RU at 0.75:", avgRU))
    message(paste("Average MI at 0.75:", avgMI))
    
    # Save single threshold results
    write.csv(rumiTable, "rumiTable_threshold_0.75.csv", row.names = TRUE)
    
    # --- Generate a RU-MI curve across multiple thresholds using ---
    message("Generating RU-MI curve with step 0.05...")
    avgRUMIvals <- RUMIcurve("MF", "human", 0.05, truefile, predfile)
    firstset <- avgRUMIvals[[1]]
    
    # Save curve data
    write.csv(firstset, "rumi_curve_data.csv", row.names = FALSE)
    
    # Plot RU vs MI and save to PDF
    pdf("ru_mi_curve_plot.pdf")
    plot(firstset\$RU, firstset\$MI, xlab="Remaining Uncertainty (RU)", ylab="Misinformation (MI)", main="RU-MI Curve")
    dev.off()
    
    # --- Calculate semantic distance from the RU-MI curve ---
    semdist <- min(sqrt(firstset\$MI^2 + firstset\$RU^2))
    message(paste("Semantic Distance:", semdist))
    writeLines(as.character(semdist), "semantic_distance.txt")
    
    # --- Generate weighted metrics and precision/recall curves ---
    message("Generating weighted metrics and precision/recall curves...")
    rumiout <- RUMIcurve("MF", "human", 0.05, truefile, predfile,
                         add.prec.rec=TRUE, add.weighted=TRUE)
    firstset_weighted <- rumiout[[1]]
    
    # Save weighted curve data
    write.csv(firstset_weighted, "rumi_curve_weighted_data.csv", row.names = FALSE)
    
    # Plot WRU vs WMI and save to PDF
    pdf("weighted_ru_mi_curve_plot.pdf")
    plot(firstset_weighted\$WRU, firstset_weighted\$WMI, xlab="Weighted RU (WRU)", ylab="Weighted MI (WMI)", main="Weighted RU-MI Curve")
    dev.off()
    
    # Save full R objects for downstream analysis
    saveRDS(avgRUMIvals, "avgRUMIvals.rds")
    saveRDS(rumiout, "rumiout_weighted.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SEMDIST_EVALUATE_PREDICTIONS_RUMI":',
        paste0('        semdist: ', as.character(packageVersion("semdist")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_evaluate_predictions_rumi.csv versions.yml
    """
}

workflow BIOC_SEMDIST_EVALUATE_PREDICTIONS_RUMI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MFO_LABELS_TEST.txt, MFO_PREDS_TEST.txt ] ]

    main:
    BIOC_SEMDIST_EVALUATE_PREDICTIONS_RUMI(ch_input)

    emit:
    tables   = BIOC_SEMDIST_EVALUATE_PREDICTIONS_RUMI.out.tables
    plots    = BIOC_SEMDIST_EVALUATE_PREDICTIONS_RUMI.out.plots
    objects  = BIOC_SEMDIST_EVALUATE_PREDICTIONS_RUMI.out.objects
    versions = BIOC_SEMDIST_EVALUATE_PREDICTIONS_RUMI.out.versions
}
