#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendMgf
// Mass spectrometry (MS) data backend supporting import and export of MS/MS spectra data from Mascot G
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendMgf/inst/doc/MsBackendMgf.R
// Upstream  : BiocStyle, Spectra
// Downstream: none
//
// Install: BiocManager::install("MsBackendMgf")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MSBACKENDMGF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendmgf"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msbackendmgf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msbackendmgf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msbackendmgf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MsBackendMgf", "Spectra", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(MsBackendMgf)
    library(Spectra)
    library(jsonlite)

    # --- Spectra Import ---
    # Key functions: MsBackendMgf, Spectra, spectraVariables
    fls <- dir(system.file("extdata", package = "MsBackendMgf"),
               full.names = TRUE, pattern = "mgf\$")
    sps <- Spectra::Spectra(fls, source = MsBackendMgf())
    sps_vars <- Spectra::spectraVariables(sps)
    rtime_vals <- sps\$rtime

    # --- Custom Variable Mapping ---
    # Key functions: spectraVariableMapping, MsBackendMgf, Spectra
    fls <- dir(system.file("extdata", package = "MsBackendMgf"),
               full.names = TRUE, pattern = "mgf\$")
    custom_map <- c(spectrumName = "TITLE",
                    spectraVariableMapping(MsBackendMgf()))
    sps_mapped <- Spectra::Spectra(fls, source = MsBackendMgf(),
                                  mapping = custom_map)
    spec_names <- sps_mapped\$spectrumName

    # --- Spectra Data Extraction ---
    # Key functions: mz, intensity, Spectra
    fls <- dir(system.file("extdata", package = "MsBackendMgf"),
               full.names = TRUE, pattern = "mgf\$")
    sps <- Spectra::Spectra(fls, source = MsBackendMgf())
    mz_list <- Spectra::mz(sps)
    int_list <- Spectra::intensity(sps)

    # --- Spectra Export ---
    # Key functions: export, MsBackendMgf, Spectra
    fls <- dir(system.file("extdata", package = "MsBackendMgf"),
               full.names = TRUE, pattern = "mgf\$")
    sps <- Spectra::Spectra(fls, source = MsBackendMgf())
    sps\$new_variable <- "A"
    out_file <- tempfile(fileext = ".mgf")
    Spectra::export(sps, backend = MsBackendMgf(), file = out_file)

    # --- Subsetting and Exporting ---
    # Key functions: selectSpectraVariables, export, MsBackendMgf
    fls <- dir(system.file("extdata", package = "MsBackendMgf"),
               full.names = TRUE, pattern = "mgf\$")
    sps <- Spectra::Spectra(fls, source = MsBackendMgf())
    sps_ex <- Spectra::selectSpectraVariables(
        sps, 
        c("mz", "intensity", "rtime", "acquisitionNum", 
          "precursorMz", "precursorCharge")
    )
    out_file_sub <- tempfile(fileext = ".mgf")
    Spectra::export(sps_ex, backend = MsBackendMgf(), 
                    file = out_file_sub, exportTitle = FALSE)


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
        write.csv(as.data.frame(.main), "${prefix}_msbackendmgf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_msbackendmgf_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_msbackendmgf_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDMGF:", paste0("    msbackendmgf: ", as.character(packageVersion("MsBackendMgf")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendmgf_results.csv
    touch ${prefix}_msbackendmgf_output.rds
    echo "BIOC_MSBACKENDMGF:" > versions.yml
    echo "    msbackendmgf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDMGF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSBACKENDMGF(ch_input)

    emit:
    results  = BIOC_MSBACKENDMGF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSBACKENDMGF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSBACKENDMGF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSBACKENDMGF.out.versions  // channel: path(versions.yml)
}
