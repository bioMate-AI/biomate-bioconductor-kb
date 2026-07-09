#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methimpute — interacting_context_calling
// Call and impute methylation status for individual cytosines using a single HMM that considers both within-context and between-context correlations.
// Input: arabidopsis_bsseeker.txt.gz, arabidopsis_sequence.fa.gz
// Container: quay.io/biocontainers/bioconductor-methimpute:1.32.0--r45ha27e39d_0
// R packages: methimpute
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING {
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
    
    # Load the required library
    library(methimpute)
    
    # Define input file paths as specified by the user
    file <- "arabidopsis_bsseeker.txt.gz"
    fasta.file <- "arabidopsis_sequence.fa.gz"
    
    # ===== Step 1: Importing the data =====
    message("Importing BSSeeker data...")
    bsseeker.data <- importBSSeeker(file)
    print(bsseeker.data)
    
    # ===== Step 2: Extract genomic cytosine positions =====
    message("Extracting cytosine positions from FASTA...")
    cytosine.positions <- extractCytosinesFromFASTA(fasta.file,
                                                   contexts = c('CG','CHG','CHH'))
    
    # ===== Step 3: Inflate the methylome =====
    message("Inflating methylome to include non-covered cytosines...")
    methylome <- inflateMethylome(bsseeker.data, cytosine.positions)
    print(methylome)
    
    # Save the inflated methylome object
    saveRDS(methylome, file = "inflated_methylome.rds")
    
    # ===== Step 4: Calculate distance correlation =====
    message("Calculating distance correlation...")
    distcor <- distanceCorrelation(methylome)
    
    # ===== Step 5: Estimate transition distance parameters =====
    message("Estimating transition distance parameters...")
    fit <- estimateTransDist(distcor)
    print(fit)
    
    # Save the transition distance fit
    saveRDS(fit, file = "transition_distance_fit.rds")
    
    # ===== Step 6: Call and impute methylation status =====
    message("Calling methylation status using interacting-context HMM...")
    model <- callMethylation(data = methylome, transDist = fit\$transDist)
    print(model)
    
    # Save the final model object
    saveRDS(model, file = "methimpute_model.rds")
    
    # Calculate and save bisulfite conversion rates
    message("Calculating bisulfite conversion rates...")
    conversion_rates <- 1 - model\$params\$emissionParams\$Unmethylated
    print(conversion_rates)
    write.csv(as.data.frame(conversion_rates), file = "bisulfite_conversion_rates.csv", row.names = TRUE)
    
    # ===== Step 7: Export results =====
    message("Exporting methylome results...")
    exportMethylome(model, filename = "methimpute_output.tsv")
    
    # ===== Step 8: Generate Diagnostic Plots =====
    message("Generating diagnostic plots...")
    pdf("methimpute_diagnostics.pdf", width = 10, height = 7)
    
    tryCatch({
      print(plotConvergence(model))
    }, error = function(e) {
      message("Could not plot convergence: ", e\$message)
    })
    
    tryCatch({
      print(plotTransitionProbs(model))
    }, error = function(e) {
      message("Could not plot transition probabilities: ", e\$message)
    })
    
    tryCatch({
      print(plotHistogram(model, total.counts = 10))
    }, error = function(e) {
      message("Could not plot histogram: ", e\$message)
    })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")
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
      process = "BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING":',
        paste0('        methimpute: ', as.character(packageVersion("methimpute")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interacting_context_calling.csv versions.yml
    """
}

workflow BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ arabidopsis_bsseeker.txt.gz, arabidopsis_sequence.fa.gz ] ]

    main:
    BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING(ch_input)

    emit:
    tables   = BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING.out.tables
    plots    = BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING.out.plots
    objects  = BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING.out.objects
    versions = BIOC_METHIMPUTE_INTERACTING_CONTEXT_CALLING.out.versions
}
