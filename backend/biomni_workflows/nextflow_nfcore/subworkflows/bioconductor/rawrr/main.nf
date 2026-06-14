#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rawrr
// This package wraps the functionality of the RawFileReader .NET assembly. Within the R environment, s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rawrr/inst/doc/rawrr.R
// Upstream  : ExperimentHub
// Downstream: none
//
// Install: BiocManager::install("rawrr")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_RAWRR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rawrr"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rawrr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rawrr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rawrr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("rawrr", "ExperimentHub", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(rawrr)
    library(ExperimentHub)
    library(jsonlite)

    # --- Assembly Installation [Assembly Installation] ---
    # Key functions: installRawFileReaderDLLs, installRawrrExe, .checkDllInMonoPath
    if (isFALSE(rawrr::.checkDllInMonoPath())) {
        rawrr::installRawFileReaderDLLs()
    }
    rawrr::installRawrrExe()

    # --- Metadata and Index Extraction [Metadata Extraction] ---
    # Key functions: sampleFilePath, readFileHeader, readIndex
    rawfile <- rawrr::sampleFilePath()
    header_info <- rawrr::readFileHeader(rawfile = rawfile)
    file_index <- rawrr::readIndex(rawfile = rawfile)
    ms2_index <- subset(
        file_index,
        file_index\$MSOrder == "Ms2"
    )

    # --- Spectrum Extraction and Accessors [Spectrum Extraction] ---
    # Key functions: sampleFilePath, readSpectrum, scanNumber, makeAccessor
    rawfile <- rawrr::sampleFilePath()
    scans <- c(1, 2, 3)
    spectra <- rawrr::readSpectrum(rawfile = rawfile, scan = scans)
    scan_num <- rawrr::scanNumber(spectra[[1]])
    max_ion_time_acc <- rawrr::makeAccessor(
        key = "Max. Ion Time (ms):",
        returnType = "double"
    )
    ion_time <- max_ion_time_acc(spectra[[1]])

    # --- Chromatogram Extraction [Chromatogram Extraction] ---
    # Key functions: sampleFilePath, readChromatogram
    rawfile <- rawrr::sampleFilePath()
    tic_chrom <- rawrr::readChromatogram(rawfile = rawfile, type = "tic")
    bpc_chrom <- rawrr::readChromatogram(rawfile = rawfile, type = "bpc")
    iRTmz <- c(487.2571, 547.2984)
    names(iRTmz) <- c("LGGNEQVTR", "YILAGVENSK")
    xic_chrom <- rawrr::readChromatogram(
        rawfile = rawfile,
        mass = iRTmz,
        tol = 10,
        type = "xic",
        filter = "ms"
    )

    # --- Peak Fitting and Analysis [Peak Analysis] ---
    # Key functions: sampleFilePath, readChromatogram
    rawfile <- rawrr::sampleFilePath()
    iRTmz <- c(487.2571, 547.2984)
    names(iRTmz) <- c("LGGNEQVTR", "YILAGVENSK")
    chroms <- rawrr::readChromatogram(
        rawfile = rawfile,
        mass = iRTmz,
        tol = 10,
        type = "xic",
        filter = "ms"
    )
    peaks <- rawrr:::pickPeak.rawrrChromatogram(chroms)
    fitted_peaks <- rawrr:::fitPeak.rawrrChromatogram(peaks)
    rt_fitted <- sapply(fitted_peaks, function(x) {
        x\$xx[which.max(x\$yp)[1]]
    })


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_rawrr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rawrr_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rawrr_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAWRR:", paste0("    rawrr: ", as.character(packageVersion("rawrr")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rawrr_results.csv
    touch ${prefix}_rawrr_output.rds
    echo "BIOC_RAWRR:" > versions.yml
    echo "    rawrr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAWRR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAWRR(ch_input)

    emit:
    results  = BIOC_RAWRR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAWRR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAWRR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAWRR.out.versions  // channel: path(versions.yml)
}
