#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HuBMAPR
// 'HuBMAP' provides an open, global bio-molecular atlas of the human body at the cellular level. The `
//
// Input: dataset_uuids.txt (required; one HuBMAP Dataset UUID per line); sample_uuids.txt, donor_uuids.txt, collection_uuids.txt, publication_uuids.txt (optional)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HuBMAPR/inst/doc/hubmapr_vignettes.R
// Upstream  : dplyr, ggplot2, pryr, tidyr
// Downstream: none
//
// Install: BiocManager::install("HuBMAPR")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_HUBMAPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hubmapr"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hubmapr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hubmapr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hubmapr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("HuBMAPR", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(HuBMAPR)
    library(jsonlite)

    # --- Read user input [] ---
    # dataset_uuids.txt : one HuBMAP Dataset UUID (32-digit hexadecimal) per
    #   line. These drive the per-entity metadata, detail and provenance
    #   queries below. Optional companion files (one ID per line) select the
    #   entity used for sample / donor / collection / publication queries:
    #     sample_uuids.txt, donor_uuids.txt, collection_uuids.txt,
    #     publication_uuids.txt
    if (!file.exists("dataset_uuids.txt")) {
        stop("Required input file 'dataset_uuids.txt' not found in the working directory. Provide one HuBMAP Dataset UUID per line.")
    }
    .read_ids <- function(path) {
        if (!file.exists(path)) return(character(0))
        ids <- trimws(readLines(path, warn = FALSE))
        ids[nzchar(ids)]
    }
    dataset_uuids <- .read_ids("dataset_uuids.txt")
    if (length(dataset_uuids) == 0) {
        stop("Input file 'dataset_uuids.txt' is empty. Provide at least one HuBMAP Dataset UUID.")
    }
    sample_uuids      <- .read_ids("sample_uuids.txt")
    donor_uuids       <- .read_ids("donor_uuids.txt")
    collection_uuids  <- .read_ids("collection_uuids.txt")
    publication_uuids <- .read_ids("publication_uuids.txt")

    # --- Catalog Retrieval and Exploration [] ---
    # Key functions: datasets, donors, samples, collections, publications
    datasets_df <- datasets()
    donors_df <- donors()
    samples_df <- samples()
    collections_df <- collections()
    publications_df <- publications()
    female_donors <- donors_df[donors_df\$Sex == "Female", ]
    kidney_samples <- samples_df[samples_df\$organ == "Kidney (Left)", ]

    # Fall back to catalog-derived IDs when an optional entity file is absent,
    # so downstream entity queries always have a valid UUID to operate on.
    if (length(sample_uuids) == 0 && nrow(samples_df) > 0)
        sample_uuids <- samples_df\$uuid[1]
    if (length(donor_uuids) == 0 && nrow(donors_df) > 0)
        donor_uuids <- donors_df\$uuid[1]
    if (length(collection_uuids) == 0 && nrow(collections_df) > 0)
        collection_uuids <- collections_df\$uuid[1]
    if (length(publication_uuids) == 0 && nrow(publications_df) > 0)
        publication_uuids <- publications_df\$uuid[1]

    # --- Metadata and Schema Inspection [] ---
    # Key functions: datasets_default_columns, organ, dataset_metadata, sample_metadata, donor_metadata
    default_cols <- datasets_default_columns(as = "character")
    organs_list <- organ()
    ds_meta <- dataset_metadata(dataset_uuids[1])
    sm_meta <- if (length(sample_uuids)) sample_metadata(sample_uuids[1]) else NULL
    dn_meta <- if (length(donor_uuids)) donor_metadata(donor_uuids[1]) else NULL

    # --- Entity Detail and Provenance Tracking [] ---
    # Key functions: dataset_detail, uuid_provenance, dataset_derived, sample_derived
    target_uuid <- dataset_uuids[1]
    detail_info <- dataset_detail(uuid = target_uuid)
    provenance_info <- uuid_provenance(uuid = target_uuid)
    derived_datasets <- dataset_derived(uuid = target_uuid)
    derived_samples <- if (length(sample_uuids)) sample_derived(
        uuid = sample_uuids[1],
        entity_type = "Sample"
    ) else NULL

    # --- Collection and Publication Data Association [] ---
    # Key functions: collection_data, publication_data, collection_information, publication_information
    coll_data <- if (length(collection_uuids)) collection_data(uuid = collection_uuids[1]) else NULL
    pub_data  <- if (length(publication_uuids)) publication_data(uuid = publication_uuids[1], entity_type = "Dataset") else NULL
    coll_info <- if (length(collection_uuids)) collection_information(uuid = collection_uuids[1]) else NULL
    pub_info  <- if (length(publication_uuids)) publication_information(uuid = publication_uuids[1]) else NULL


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
        write.csv(as.data.frame(.main), "${prefix}_hubmapr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_hubmapr_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_hubmapr_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_HUBMAPR:", paste0("    hubmapr: ", as.character(packageVersion("HuBMAPR")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hubmapr_results.csv
    touch ${prefix}_hubmapr_output.rds
    echo "BIOC_HUBMAPR:" > versions.yml
    echo "    hubmapr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HUBMAPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HUBMAPR(ch_input)

    emit:
    results  = BIOC_HUBMAPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HUBMAPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HUBMAPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HUBMAPR.out.versions  // channel: path(versions.yml)
}
