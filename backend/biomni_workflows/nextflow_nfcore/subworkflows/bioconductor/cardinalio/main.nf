#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CardinalIO
// Fast and efficient reading and writing of mass spectrometry imaging data files. Supports imzML and A
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CardinalIO/inst/doc/CardinalIO-guide.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CardinalIO")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_CARDINALIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cardinalio"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cardinalio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cardinalio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cardinalio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("CardinalIO", "ImzMeta", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(CardinalIO)
    library(ImzMeta)
    library(jsonlite)

    # --- Extracting Spectra and Spatial Coordinates [] ---
    # Key functions: as
    e2 <- as(p, "ImzMeta")
    positions <- p\$run\$spectrumList\$positions
    mz_arrays <- p\$run\$spectrumList\$mzArrays
    intensity_arrays <- p\$run\$spectrumList\$intensityArrays
    mz1 <- p\$ibd\$mz[[1L]]
    int1 <- p\$ibd\$intensity[[1L]]


    # --- Metadata Construction and Conversion [] ---
    # Key functions: ImzMeta, as
    meta <- ImzMeta(
        spectrumType="MS1 spectrum",
        spectrumRepresentation="profile",
        instrumentModel="LTQ FT Ultra",
        ionSource="electrospray ionization",
        analyzer="ion trap",
        detectorType="electron multiplier"
    )
    p2 <- as(meta, "ImzML")
    file_desc2 <- p2\$fileDescription


    # --- Exporting Mass Spectrometry Imaging Datasets [] ---
    # Key functions: writeImzML, ImzMeta
    meta <- ImzMeta(
        spectrumType="MS1 spectrum",
        spectrumRepresentation="profile"
    )
    nx <- 3
    ny <- 3
    nmz <- 500
    mz <- seq(500, 510, length.out=nmz)
    intensity <- matrix(runif(nx * ny * nmz), nrow=nmz)
    positions <- expand.grid(x=seq_len(nx), y=seq_len(ny))
    path3 <- tempfile(fileext=".imzML")
    writeImzML(
        meta,
        file=path3,
        positions=positions,
        mz=mz,
        intensity=intensity
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
        write.csv(as.data.frame(.main), "${prefix}_cardinalio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_cardinalio_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_cardinalio_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_CARDINALIO:", paste0("    cardinalio: ", as.character(packageVersion("CardinalIO")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cardinalio_results.csv
    touch ${prefix}_cardinalio_output.rds
    echo "BIOC_CARDINALIO:" > versions.yml
    echo "    cardinalio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CARDINALIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CARDINALIO(ch_input)

    emit:
    results  = BIOC_CARDINALIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CARDINALIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CARDINALIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CARDINALIO.out.versions  // channel: path(versions.yml)
}
