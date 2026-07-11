#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CGHcall — acgh_aberration_calling
// Preprocess, normalize, segment, and call copy number aberrations from raw array CGH data while correcting for tumor cellularity.
// Input: Wilting
// Container: quay.io/biocontainers/bioconductor-cghcall:2.72.0--r45hdfd78af_0
// R packages: CGHcall
// Bioconductor: 3.20 | R: 4.4
// Requires: CGHcall
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert raw data to cghRaw object
//  * 2. [Core Analysis] Preprocess data to filter missing values and impute
//  * 3. [Core Analysis] Normalize log2 ratios and smooth outliers
//  * 4. [Core Analysis] Segment data using DNAcopy wrapper
//  * 5. [Core Analysis] Perform post-segmentation normalization to adjust zero level
//  * 6. [Core Analysis] Call copy number aberrations with cellularity correction
//  * 7. [Core Analysis] Expand the call object for downstream analysis
//  * 8. [Visualization & Output] Plot individual profiles and summary/frequency plots

nextflow.enable.dsl = 2

process BIOC_CGHCALL_ACGH_ABERRATION_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("CGHcall")
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
    library(CGHcall)
    
    # 1. Read the user input file 'Wilting' from the working directory
    # The input can be in RDS, CSV, TSV, or TXT format.
    input_file <- "Wilting"
    if (file.exists("Wilting.rds")) {
      Wilting <- readRDS("Wilting.rds")
    } else {
      files <- list.files(pattern = "^Wilting(\\\\..+)?\$")
      if (length(files) == 0) {
        stop("Required input file 'Wilting' not found in the working directory.")
      }
      file_to_read <- files[1]
      if (grepl("\\\\.rds\$", file_to_read, ignore.case = TRUE)) {
        Wilting <- readRDS(file_to_read)
      } else if (grepl("\\\\.csv\$", file_to_read, ignore.case = TRUE)) {
        Wilting <- read.csv(file_to_read, header = TRUE, check.names = FALSE)
      } else {
        Wilting <- read.table(file_to_read, header = TRUE, sep = "\t", check.names = FALSE)
      }
    }
    
    # Ensure Wilting is a data frame
    Wilting <- as.data.frame(Wilting)
    
    # Convert raw data to cghRaw object
    Wilting <- make_cghRaw(Wilting)
    
    # 2. Preprocess data to filter missing values and impute
    cghdata <- preprocess(Wilting, maxmiss=30, nchrom=22)
    
    # 3. Normalize log2 ratios and smooth outliers
    norm.cghdata <- normalize(cghdata, method="median", smoothOutliers=TRUE)
    
    # 4. Segment data using DNAcopy wrapper
    seg.cghdata <- segmentData(norm.cghdata, method="DNAcopy", undo.splits="sdundo", undo.SD=3, clen=10, relSDlong=5)
    
    # 5. Perform post-segmentation normalization to adjust zero level
    postseg.cghdata <- postsegnormalize(seg.cghdata)
    
    # 6. Call copy number aberrations with cellularity correction
    tumor.prop <- rep(1, ncol(postseg.cghdata))
    result <- CGHcall(postseg.cghdata, nclass=5, cellularity=tumor.prop)
    
    # 7. Expand the call object for downstream analysis
    result <- ExpandCGHcall(result, postseg.cghdata)
    
    # 8. Plot individual profiles and summary/frequency plots to a PDF file
    pdf("cghcall_plots.pdf", width = 10, height = 8)
    for (i in seq_len(ncol(result))) {
      plot(result[,i])
    }
    summaryPlot(result)
    frequencyPlotCalls(result)
    dev.off()
    
    # Save meaningful results to output files
    saveRDS(result, "cghcall_result.rds")
    write.csv(calls(result), "calls.csv", row.names = TRUE)
    write.csv(segmented(result), "segmented.csv", row.names = TRUE)
    write.csv(copynumber(result), "copynumber.csv", row.names = TRUE)
    write.csv(probloss(result), "probloss.csv", row.names = TRUE)
    write.csv(probnorm(result), "probnorm.csv", row.names = TRUE)
    write.csv(probgain(result), "probgain.csv", row.names = TRUE)
    write.csv(probamp(result), "probamp.csv", row.names = TRUE)
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
      process = "BIOC_CGHCALL_ACGH_ABERRATION_CALLING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CGHCALL_ACGH_ABERRATION_CALLING":',
        paste0('    CGHcall: ', as.character(packageVersion('CGHcall')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acgh_aberration_calling.csv versions.yml
    """
}

workflow BIOC_CGHCALL_ACGH_ABERRATION_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Wilting ] ]

    main:
    BIOC_CGHCALL_ACGH_ABERRATION_CALLING(ch_input)

    emit:
    tables   = BIOC_CGHCALL_ACGH_ABERRATION_CALLING.out.tables
    plots    = BIOC_CGHCALL_ACGH_ABERRATION_CALLING.out.plots
    objects  = BIOC_CGHCALL_ACGH_ABERRATION_CALLING.out.objects
    versions = BIOC_CGHCALL_ACGH_ABERRATION_CALLING.out.versions
}
