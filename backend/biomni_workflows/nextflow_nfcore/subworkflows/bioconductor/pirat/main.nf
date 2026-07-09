#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Pirat — standard_imputation_and_diagnostics
// Perform diagnostic correlation analysis and standard imputation on proteomics data.
// Input: subbouyssie, ropers
// Container: quay.io/biocontainers/bioconductor-pirat:1.4.4--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Pirat
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and dataset
//  * 2. [Core Analysis] Set seed for reproducibility
//  * 3. [Core Analysis] Run standard imputation using my_pipeline_llkimpute
//  * 4. [Core Analysis] Inspect imputed values and parameters
//  * 5. [Visualization & Output] Run diagnostic correlation analysis using plot_pep_correlations

nextflow.enable.dsl = 2

process BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Pirat")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(Pirat)
    library(utils)
    library(grDevices)
    
    # Read user input files from the working directory
    subbouyssie <- readRDS("subbouyssie.rds")
    ropers <- readRDS("ropers.rds")
    
    # Set seed for reproducibility
    set.seed(12345)
    
    # Run standard imputation using my_pipeline_llkimpute
    imp.res <- my_pipeline_llkimpute(subbouyssie)
    
    # Inspect imputed values and parameters
    print("First 5 columns of imputed data:")
    print(head(imp.res\$data.imputed[ ,seq(5)]))
    
    print("Computed parameters:")
    print(imp.res\$params)
    
    # Save imputation results to output files
    write.csv(imp.res\$data.imputed, "subbouyssie_imputed.csv", row.names = TRUE)
    saveRDS(imp.res, "subbouyssie_imputed_results.rds")
    
    # Run diagnostic correlation analysis and save plot to PDF
    pdf("ropers_pep_correlations.pdf", width = 8, height = 6)
    plot_pep_correlations(ropers, titlename = "Ropers2021")
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS":',
        paste0('    Pirat: ', as.character(packageVersion('Pirat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_imputation_and_diagnostics.csv versions.yml
    """
}

workflow BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ subbouyssie, ropers ] ]

    main:
    BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS(ch_input)

    emit:
    tables   = BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS.out.tables
    plots    = BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS.out.plots
    objects  = BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS.out.objects
    versions = BIOC_PIRAT_STANDARD_IMPUTATION_AND_DIAGNOSTICS.out.versions
}
