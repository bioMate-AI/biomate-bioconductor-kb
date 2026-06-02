#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cellxgenedp
// The cellxgene data portal (https://cellxgene.cziscience.com/) provides a graphical user interface to
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cellxgenedp/inst/doc/a_using_cellxgenedp.R
// Upstream  : SingleCellExperiment, dplyr, zellkonverter
// Downstream: none
//
// Install: BiocManager::install("cellxgenedp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLXGENEDP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellxgenedp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellxgenedp:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellxgenedp:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellxgenedp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellxgenedp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellxgenedp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cellxgenedp)
    library(jsonlite)

    # --- facets [] ---
    # Key functions: facets
    facets(db, "assay")
    facets(db, "self_reported_ethnicity")
    facets(db, "sex")
    # --- african american female [] ---
    # Key functions: datasets, facets_filter, summarise, left_join, collections
    datasets(db) |>
    filter(
    facets_filter(assay, "ontology_term_id", "EFO:0009922"),
    # --- left_join [] ---
    # Key functions: left_join, files
    left_join(
    african_american_female |> select(dataset_id),
    files(db),
    # --- local file from dataset id [] ---
    # Key functions: files_download
    filter(
    files_download(dry.run = FALSE)
    basename(local_file)
    # --- read H5 A D [] ---
    # Key functions: readH5AD, colData, as_tibble, count
    h5ad <- readH5AD(local_file, use_hdf5 = TRUE, reader = "R")
    colData(h5ad) |>
    as_tibble() |>

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellxgenedp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellxgenedp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellxgenedp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLXGENEDP:", paste0("    cellxgenedp: ", packageVersion("cellxgenedp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellxgenedp_results.csv
    touch ${prefix}_cellxgenedp_output.rds
    echo "BIOC_CELLXGENEDP:" > versions.yml
    echo "    cellxgenedp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLXGENEDP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLXGENEDP(ch_input)

    emit:
    results  = BIOC_CELLXGENEDP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLXGENEDP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLXGENEDP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLXGENEDP.out.versions  // channel: path(versions.yml)
}
