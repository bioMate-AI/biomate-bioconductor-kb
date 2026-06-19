#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crlmm — copy_number_and_genotyping_pipeline
// Preprocess, genotype, and estimate copy number (including allele-specific copy number, log R ratios, and B allele frequencies) using a disk-backed CNSet contain
// Input: celFiles
// Container: quay.io/biocontainers/bioconductor-crlmm:1.68.0--r45h01b2380_0
// R packages: VanillaICE, crlmm, ff, lattice, oligoClasses
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crlmm:1.68.0--r45h01b2380_0"

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
    .bm_deps <- c("VanillaICE", "crlmm", "ff", "lattice", "oligoClasses")
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
    library(oligoClasses)
    library(crlmm)
    library(ff)
    library(VanillaICE)
    library(lattice)
    
    # --- Set up disk-backed storage and RAM limits ---
    outdir <- "./crlmm_output"
    if (!dir.exists(outdir)) {
      dir.create(outdir, recursive = TRUE)
    }
    ldPath(outdir)
    ocProbesets(100000)
    ocSamples(200)
    
    # Read user input CEL files from the working directory
    if (!exists("celFiles")) {
      celFiles <- list.celfiles(".", full.names = TRUE, pattern = "\\\\.CEL\$", ignore.case = TRUE)
    }
    
    if (length(celFiles) == 0) {
      stop("Error: No CEL files found in the working directory. Please provide raw Affymetrix CEL files.")
    }
    
    # Extract batch/plate information from CEL filenames
    plates <- substr(basename(celFiles), 13, 13)
    
    # --- Construct the CNSet container ---
    cnSet <- constructAffyCNSet(celFiles, batch=plates, cdfName="genomewidesnp6", genome="hg19")
    
    # --- Perform quantile normalization ---
    cnrmaAffy(cnSet)
    validCEL(celFiles)
    snprmaAffy(cnSet)
    
    # --- Genotype and impute gender ---
    genotypeAffy(cnSet, gender=NULL)
    gender_table <- table(c("male", "female")[cnSet\$gender[]])
    print(gender_table)
    
    # --- Fit linear model for copy number ---
    crlmmCopynumber(cnSet)
    
    # --- Extract raw copy number or coerce to BafLrrSetList for ---
    tmp <- totalCopynumber(cnSet, i=seq_len(nrow(cnSet)), j=1:2)
    snp.index <- which(isSnp(cnSet) & !is.na(chromosome(cnSet)))
    ca <- CA(cnSet, i=snp.index, j=1:2)
    cb <- CB(cnSet, i=snp.index, j=1:2)
    
    open(cnSet)
    oligoSetList <- BafLrrSetList(cnSet)
    close(cnSet)
    
    lrrList <- lrr(oligoSetList)
    bafList <- baf(oligoSetList)
    
    # Save meaningful results to output files
    saveRDS(cnSet, file = file.path(outdir, "cnSet.rds"))
    write.csv(as.data.frame(gender_table), file = file.path(outdir, "gender_table.csv"), row.names = FALSE)
    saveRDS(tmp, file = file.path(outdir, "total_copynumber_sample1_2.rds"))
    saveRDS(ca, file = file.path(outdir, "CA_sample1_2.rds"))
    saveRDS(cb, file = file.path(outdir, "CB_sample1_2.rds"))
    saveRDS(oligoSetList, file = file.path(outdir, "oligoSetList.rds"))
    saveRDS(lrrList, file = file.path(outdir, "lrrList.rds"))
    saveRDS(bafList, file = file.path(outdir, "bafList.rds"))
    
    # Generate and save SNR Quality Control Plot
    invisible(open(cnSet\$SNR))
    snr <- cnSet\$SNR[]
    close(cnSet\$SNR)
    
    pdf(file.path(outdir, "snr_histogram.pdf"))
    print(histogram(~snr,
                    panel=function(...){
                            panel.histogram(...)},
                    breaks=25, xlim=range(snr), xlab="SNR"))
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to:", outdir, "\n")
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
      process = "BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE":',
        paste0('        crlmm: ', as.character(packageVersion("crlmm")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_copy_number_and_genotyping_pipeline.csv versions.yml
    """
}

workflow BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ celFiles ] ]

    main:
    BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE.out.tables
    plots    = BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE.out.plots
    objects  = BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE.out.objects
    versions = BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE.out.versions
}
