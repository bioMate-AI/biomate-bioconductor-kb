#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: magar — compare_meth_qtl_results
// Compare and overlap multiple methQTL result objects to identify shared and dataset-specific QTLs.
// Input: meth.qtl.res, MethQTLResult_chr18
// Container: quay.io/biocontainers/bioconductor-magar:1.18.0--r45hdfd78af_0
// R packages: MAGAR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAGAR_COMPARE_METH_QTL_RESULTS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-magar:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("MAGAR")
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
    
    # Load required packages
    suppressPackageStartupMessages(library(MAGAR))
    
    # Define input file paths in the working directory
    input_file_1 <- "meth.qtl.res"
    input_file_2 <- "MethQTLResult_chr18"
    
    # Verify that the required input files exist
    if (!file.exists(input_file_1)) {
      stop(paste("Required input file missing:", input_file_1))
    }
    if (!file.exists(input_file_2)) {
      stop(paste("Required input file missing:", input_file_2))
    }
    
    # --- Load the methQTLResult objects ---
    message("Loading first methQTLResult object...")
    meth.qtl.res <- loadMethQTLResult(input_file_1)
    
    message("Loading second methQTLResult object...")
    meth.qtl.res.2 <- loadMethQTLResult(input_file_2)
    
    # --- Combine results into a named list ---
    meth.qtl.list <- list(First=meth.qtl.res, Second=meth.qtl.res.2)
    
    # --- Generate Venn diagram using qtlVennPlot ---
    message("Generating Venn diagram...")
    qtlVennPlot(meth.qtl.list, out.folder=getwd())
    
    # --- Generate UpSet plot using qtlUpsetPlot and save to PDF ---
    message("Generating UpSet plot...")
    pdf("qtl_upset_plot.pdf", width=10, height=8)
    tryCatch({
      print(qtlUpsetPlot(meth.qtl.list, type = "cor.block"))
    }, error = function(e) {
      message("Error generating UpSet plot: ", e\$message)
    })
    dev.off()
    
    # --- Identify specific QTLs using getSpecificQTL ---
    message("Identifying dataset-specific QTLs...")
    spec.first <- getSpecificQTL(meth.qtl.list\$First, meth.qtl.list[-1])
    
    # Save the specific QTLs to output files
    saveRDS(spec.first, "specific_qtls_first.rds")
    
    if (is.data.frame(spec.first) || is.matrix(spec.first)) {
      write.csv(spec.first, "specific_qtls_first.csv", row.names=FALSE)
    } else if (is.list(spec.first)) {
      # If it's a list of data frames or other structures, save them accordingly
      tryCatch({
        for (name in names(spec.first)) {
          if (is.data.frame(spec.first[[name]])) {
            write.csv(spec.first[[name]], paste0("specific_qtls_first_", name, ".csv"), row.names=FALSE)
          }
        }
      }, error = function(e) {
        message("Could not write specific QTLs to CSV: ", e\$message)
      })
    }
    
    message("Workflow completed successfully.")

    writeLines(c(
        '"BIOC_MAGAR_COMPARE_METH_QTL_RESULTS":',
        paste0('        magar: ', as.character(packageVersion("magar")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_meth_qtl_results.csv versions.yml
    """
}

workflow BIOC_MAGAR_COMPARE_METH_QTL_RESULTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ meth.qtl.res, MethQTLResult_chr18 ] ]

    main:
    BIOC_MAGAR_COMPARE_METH_QTL_RESULTS(ch_input)

    emit:
    tables   = BIOC_MAGAR_COMPARE_METH_QTL_RESULTS.out.tables
    plots    = BIOC_MAGAR_COMPARE_METH_QTL_RESULTS.out.plots
    objects  = BIOC_MAGAR_COMPARE_METH_QTL_RESULTS.out.objects
    versions = BIOC_MAGAR_COMPARE_METH_QTL_RESULTS.out.versions
}
