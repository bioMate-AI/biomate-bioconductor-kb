#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsExperiment
// Infrastructure to store and manage all aspects related to a complete proteomics or metabolomics mass
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsExperiment/inst/doc/MsExperiment.R
// Upstream  : BiocStyle, MsBackendSql, RSQLite, Spectra, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("MsExperiment")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MSEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msexperiment"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("S4Vectors", "MsExperiment", "MsExperimentFiles", "PXDataset", "Spectra", "jsonlite", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(S4Vectors)
    library(SummarizedExperiment)
    library(MsExperiment)
    library(MsExperimentFiles)
    library(PXDataset)
    library(Spectra)
    library(jsonlite)

    # --- Experiment Initialization [Initialization] ---
    # Key functions: MsExperiment, MsExperimentFiles, experimentFiles<-, sampleData<-
    fls <- c("sample1.mzML", "sample2.mzML")
    msexp <- MsExperiment()
    msfls <- MsExperimentFiles(
        mzmls = fls,
        fasta = "homo_sapiens.fasta"
    )
    experimentFiles(msexp) <- msfls
    sd <- S4Vectors::DataFrame(
        mzmls = basename(fls),
        fractions = 1:2
    )
    sampleData(msexp) <- sd

    # --- Spectra Loading and Association [Spectra Loading] ---
    # Key functions: Spectra, spectra<-
    mz_files <- experimentFiles(msexp)[["mzmls"]]
    sp <- Spectra::Spectra(mz_files)
    spectra(msexp) <- sp

    # --- Sample Data Linking [Sample Linking] ---
    # Key functions: linkSampleData, spectraSampleIndex
    sampleData(msexp)\$raw_file <- normalizePath(
        experimentFiles(msexp)[["mzmls"]]
    )
    msexp <- linkSampleData(
        msexp,
        with = "sampleData.raw_file = spectra.dataOrigin"
    )
    idx <- spectraSampleIndex(msexp)

    # --- Quantitative Data Integration [Quantification Integration] ---
    # Key functions: qdata<-, linkSampleData, qdata
    sd <- S4Vectors::DataFrame(sample = c("QC2", "QC1"), idx = c(3, 1))
    se <- SummarizedExperiment::SummarizedExperiment(
        colData = sd,
        assay = list(counts = matrix(1:20, ncol = 2))
    )
    qdata(msexp) <- se
    msexp <- linkSampleData(
        msexp,
        with = "sampleData.mzmls = qdata.sample"
    )


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
        write.csv(as.data.frame(.main), "${prefix}_msexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_msexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_msexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSEXPERIMENT:", paste0("    msexperiment: ", as.character(packageVersion("MsExperiment")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msexperiment_results.csv
    touch ${prefix}_msexperiment_output.rds
    echo "BIOC_MSEXPERIMENT:" > versions.yml
    echo "    msexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSEXPERIMENT(ch_input)

    emit:
    results  = BIOC_MSEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSEXPERIMENT.out.versions  // channel: path(versions.yml)
}
