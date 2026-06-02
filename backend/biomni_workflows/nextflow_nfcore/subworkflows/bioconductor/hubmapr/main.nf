#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HuBMAPR
// 'HuBMAP' provides an open, global bio-molecular atlas of the human body at the cellular level. The `
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
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hubmapr:1.0.8--r44_0' :
        'quay.io/biocontainers/bioconductor-hubmapr:1.0.8--r44_0'}"

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
    library(HuBMAPR)
    library(jsonlite)

    # --- 'datasets' [] ---
    # Key functions: datasets, object_size
    system.time({
    datasets_df <- datasets()
    object_size(datasets_df)
    # --- 'plot' [] ---
    # Key functions: group_by, ggplot, aes, geom_histogram, scale_fill_manual
    select(organ, dataset_type) |>
    group_by(organ) |>
    mutate(count = n()) |>
    # --- 'cols' [] ---
    # Key functions: datasets_default_columns
    as = "tibble" (default)
    datasets_col_tbl <- datasets_default_columns(as = "tibble")
    datasets_col_char <- datasets_default_columns(as = "character")
    # --- 'summary cols' [] ---
    # Key functions: bind_cols
    tbl <- bind_cols(
    dataset = datasets_default_columns(as = "character"),
    sample = c(samples_default_columns(as = "character"), rep(NA, 7)),
    # --- 'datasets filter' [] ---
    # Key functions: count
    Example from datasets()
    filter(organ == 'Small Intestine') |>
    count()
    # --- 'derived using left join' [] ---
    # Key functions: donors, left_join, rename, samples
    donors_df <- donors()
    filter(Sex == "Female",
    head(1)
    # --- '* detail()' [] ---
    # Key functions: pull, dataset_detail, unnest_longer, unnest_wider
    filter(dataset_type == "Auto-fluorescence",
    organ == "Kidney (Right)") |>
    head(1) |>
    # --- 'metadata' [] ---
    # Key functions: dataset_metadata, sample_metadata, donor_metadata
    dataset_metadata("993bb1d6fa02e2755fd69613bb9d6e08")
    sample_metadata("8ecdbdc3e2d04898e2563d666658b6a9")
    donor_metadata("b2c75c96558c18c9e13ba31629f541b6")
    # --- 'dataset derived' [] ---
    # Key functions: dataset_derived
    dataset_derived(uuid = dataset_uuid_1)
    dataset_derived(uuid = dataset_uuid_2) |> glimpse()
    # --- 'derived using sample derived' [] ---
    # Key functions: pull, sample_derived
    filter(last_modified_timestamp >= "2023-01-01" &
    organ == "Kidney (Left)") |>
    head(1) |>
    # --- 'provenance' [] ---
    # Key functions: uuid_provenance
    uuid_provenance(dataset_uuid)
    uuid_provenance(sample_uuid)
    uuid_provenance(donor_uuid)
    # --- 'collection datasets' [] ---
    # Key functions: collections, pull, collection_data
    collections_df <- collections()
    filter(last_modified_timestamp >= "2023-01-01") |>
    head(1) |>
    # --- 'publication data' [] ---
    # Key functions: publications, pull, publication_data
    publications_df <- publications()
    filter(publication_venue == "Nature") |>
    head(1) |>
    # --- 'information' [] ---
    # Key functions: collection_information, publication_information
    collection_information(uuid = collection_uuid)
    publication_information(uuid = publication_uuid)
    # --- 'author' [] ---
    # Key functions: dataset_contributors, collection_contacts, collection_contributors, publication_authors
    dataset_contributors(uuid = dataset_uuid)
    collection_contacts(uuid = collection_uuid)
    collection_contributors(uuid = collection_uuid)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hubmapr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hubmapr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hubmapr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HUBMAPR:", paste0("    hubmapr: ", packageVersion("HuBMAPR"))),
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
