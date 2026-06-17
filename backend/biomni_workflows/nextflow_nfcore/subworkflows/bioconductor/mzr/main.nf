#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mzR
// mzR provides a unified API to the common file formats and parsers available for mass spectrometry da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mzR/inst/doc/mzR.R
// Upstream  : msdata
// Downstream: MSnbase
//
// Install: BiocManager::install("mzR")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MZR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mzr"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mzr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mzr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mzr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("mzR", "msdata", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(mzR)
    library(msdata)
    library(jsonlite)


    # --- Openraw [] ---
    # Key functions: openMSfile, msdata
    library(mzR)
    library(msdata)

    mzxml <- system.file("threonine/threonine_i2_e35_pH_tree.mzXML",
                         package = "msdata")
    aa <- openMSfile(mzxml)

    # --- Get Header Information [] ---
    # Key functions: runInfo, instrumentInfo, header
    runInfo(aa)
    instrumentInfo(aa)
    header(aa,1)

    # --- Plotspectrum [] ---
    # Key functions: peaks, peaksCount
    pl <- peaks(aa,10)
    peaksCount(aa,10)
    head(pl)
    plot(pl[,1], pl[,2], type="h", lwd=1)

    # --- Close The File [] ---
    # Key functions: close
    close(aa)

    # --- Openid [] ---
    # Key functions: openIDfile, mzid, msdata
    library(mzR)
    library(msdata)

    file <- system.file("mzid", "Tandem.mzid.gz", package="msdata")
    x <- openIDfile(file)

    # --- Metadata [] ---
    # Key functions: mzidInfo
    mzidInfo(x)

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
        write.csv(as.data.frame(.main), "${prefix}_mzr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_mzr_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_mzr_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MZR:", paste0("    mzr: ", as.character(packageVersion("mzR")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mzr_results.csv
    touch ${prefix}_mzr_output.rds
    echo "BIOC_MZR:" > versions.yml
    echo "    mzr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MZR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MZR(ch_input)

    emit:
    results  = BIOC_MZR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MZR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MZR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MZR.out.versions  // channel: path(versions.yml)
}
