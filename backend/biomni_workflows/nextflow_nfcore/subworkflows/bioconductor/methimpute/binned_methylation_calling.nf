#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methimpute — binned_methylation_calling
// Call and impute methylation status on binned genomic data (e.g., 100bp bins).
// Input: arabidopsis_bsseeker.txt.gz, arabidopsis_sequence.fa.gz
// Container: quay.io/biocontainers/bioconductor-methimpute:1.32.0--r45ha27e39d_0
// R packages: methimpute
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-methimpute:1.32.0--r45ha27e39d_0"

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
    .bm_deps <- c("methimpute")
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
    
    # Load required library
    library(methimpute)
    
    # Define input files (expected to be in the working directory)
    file <- "arabidopsis_bsseeker.txt.gz"
    fasta.file <- "arabidopsis_sequence.fa.gz"
    
    # Verify input files exist
    if (!file.exists(file)) {
      stop(paste("Required input file missing in working directory:", file))
    }
    if (!file.exists(fasta.file)) {
      stop(paste("Required input file missing in working directory:", fasta.file))
    }
    
    # --- Import the BSSeeker data ---
    message("Importing BSSeeker data...")
    bsseeker.data <- importBSSeeker(file)
    print(bsseeker.data)
    
    # --- Extract all genomic cytosine positions from the FASTA ---
    message("Extracting cytosine positions from FASTA...")
    cytosine.positions <- extractCytosinesFromFASTA(fasta.file,
                                                    contexts = c('CG','CHG','CHH'))
    
    # --- Inflate the methylome to include non-covered cytosines ---
    message("Inflating methylome...")
    methylome <- inflateMethylome(bsseeker.data, cytosine.positions)
    print(methylome)
    
    # --- Bin the inflated methylome into fixed-size windows ---
    message("Binning methylome...")
    binnedMethylome <- binMethylome(methylome, binsize = 100, contexts = c('total','CG'))
    print(binnedMethylome\$CG)
    
    # --- Call and impute methylation status on the binned data ---
    message("Calling methylation on binned data...")
    binnedModel <- callMethylation(data = binnedMethylome\$CG)
    print(binnedModel)
    
    # Save the model object and export results
    message("Saving binned model to RDS...")
    saveRDS(binnedModel, file = "binned_model.rds")
    
    message("Exporting binned model data to CSV...")
    binned_df <- as.data.frame(binnedModel\$data)
    write.csv(binned_df, file = "binned_methylation_calls.csv", row.names = FALSE)
    
    # --- Plot diagnostics and save to PDF ---
    message("Generating diagnostic plots...")
    pdf("binned_methylation_plots.pdf", width = 8, height = 6)
    
    # Plot convergence
    p1 <- plotConvergence(binnedModel)
    print(p1)
    
    # Plot transition probabilities
    p2 <- plotTransitionProbs(binnedModel)
    print(p2)
    
    # Plot histogram
    p3 <- plotHistogram(binnedModel, total.counts = 150)
    print(p3)
    
    dev.off()
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING":',
        paste0('        methimpute: ', as.character(packageVersion("methimpute")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binned_methylation_calling.csv versions.yml
    """
}

workflow BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ arabidopsis_bsseeker.txt.gz, arabidopsis_sequence.fa.gz ] ]

    main:
    BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING(ch_input)

    emit:
    tables   = BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING.out.tables
    plots    = BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING.out.plots
    objects  = BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING.out.objects
    versions = BIOC_METHIMPUTE_BINNED_METHYLATION_CALLING.out.versions
}
