#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gypsum
// Client for the gypsum REST API (https://gypsum.artifactdb.com), a cloud-based file store in the Arti
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gypsum/inst/doc/userguide.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("gypsum")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_GYPSUM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gypsum"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gypsum_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gypsum_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gypsum_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("gypsum", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(gypsum)
    library(jsonlite)

    # --- Listing Assets and Versions [] ---
    # Key functions: listAssets, listVersions, listFiles
    all_assets <- listAssets("test-R")
    basic_versions <- listVersions("test-R", "basic")
    v1_files <- listFiles(
        project = "test-R",
        asset = "basic",
        version = "v1"
    )

    # --- Downloading Files and Versions [] ---
    # Key functions: saveFile, saveVersion
    local_file <- saveFile(
        project = "test-R",
        asset = "basic",
        version = "v1",
        path = "blah.txt"
    )
    local_dir <- saveVersion(
        project = "test-R",
        asset = "basic",
        version = "v1"
    )

    # --- Fetching Metadata and Manifests [] ---
    # Key functions: fetchManifest, fetchSummary, fetchLatest
    manifest <- fetchManifest("test-R", "basic", "v1")
    summary_info <- fetchSummary("test-R", "basic", "v1")
    latest_version <- fetchLatest("test-R", "basic")

    # --- Preparing Uploads [] ---
    # Key functions: cloneVersion, prepareDirectoryUpload
    dest_dir <- tempfile()
    cloneVersion(
        project = "test-R",
        asset = "basic",
        version = "v1",
        destination = dest_dir
    )
    write(c("Aaron", "Jayaram"), file = file.path(dest_dir, "BFFs"))
    upload_info <- prepareDirectoryUpload(dest_dir)

    # --- Validating Metadata [] ---
    # Key functions: fetchMetadataSchema, validateMetadata
    schema_path <- fetchMetadataSchema()
    meta_list <- list(
        title = "Fatherhood",
        description = "Luke ich bin dein Vater.",
        sources = list(list(provider = "GEO", id = "GSE12345")),
        taxonomy_id = list("9606"),
        genome = list("GRCm38"),
        maintainer_name = "Darth Vader",
        maintainer_email = "vader@empire.gov",
        bioconductor_version = "3.10"
    )
    validation_res <- validateMetadata(meta_list, schema_path)

    # --- Querying Permissions and Quotas [] ---
    # Key functions: fetchPermissions, fetchQuota, fetchUsage
    perms <- fetchPermissions("test-R")
    quota <- fetchQuota("test-R")
    usage <- fetchUsage("test-R")


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
        write.csv(as.data.frame(.main), "${prefix}_gypsum_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_gypsum_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_gypsum_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_GYPSUM:", paste0("    gypsum: ", as.character(packageVersion("gypsum")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gypsum_results.csv
    touch ${prefix}_gypsum_output.rds
    echo "BIOC_GYPSUM:" > versions.yml
    echo "    gypsum: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GYPSUM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GYPSUM(ch_input)

    emit:
    results  = BIOC_GYPSUM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GYPSUM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GYPSUM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GYPSUM.out.versions  // channel: path(versions.yml)
}
