#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AlphaMissenseR
// The AlphaMissense publication <https://www.science.org/doi/epdf/10.1126/science.adg7492> outlines ho
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AlphaMissenseR/inst/doc/alphafold.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("AlphaMissenseR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALPHAMISSENSER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alphamissenser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alphamissenser:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alphamissenser:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alphamissenser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alphamissenser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alphamissenser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AlphaMissenseR)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, am_available, am_data, aa_substitutions, hg38
    knitr::opts_chunk$set(
        collapse = TRUE,
        comment = "#>"
    )
    am_available()
    am_data("aa_substitutions")
    am_data("hg38")

    # --- P35557 [] ---
    # Key functions: am_data, filter, af_prediction_view, aa_substitutions, distinct, pull, af_predictions, glimpse
    P35557_aa <-
        am_data("aa_substitutions") |>
        dplyr::filter(uniprot_id == "P35557")

    ## ----median-pathogenicity-----------------------------------------------------
    af_prediction_view(P35557_aa)
    uniprot_ids <-
        am_data("aa_substitutions") |>
        dplyr::filter(uniprot_id %like% "P3555%") |>
        dplyr::distinct(uniprot_id) |>
        pull(uniprot_id)
    uniprot_ids
    prediction <- af_predictions(uniprot_ids)
    glimpse(prediction)

    # --- Pdb Url [] ---
    # Key functions: filter, pull, bfcrpath, basename, read.pdb, r3dmol, m_add_model, m_bio3d
    pdb_url <-
        prediction |>
        dplyr::filter(uniprotAccession == "P35557") |>
        dplyr::pull(pdbUrl)
    pdb_file <- BiocFileCache::bfcrpath(rnames = basename(pdb_url), fpath = pdb_url)
    pdb <- bio3d::read.pdb(pdb_file)
    pdb
    r3dmol::r3dmol() |>
        ## use the PDB representation
        r3dmol::m_add_model(r3dmol::m_bio3d(pdb)) |>
        ## visualize as a 'cartoon' with alpha helices and beta sheets
        r3dmol::m_set_style(style = r3dmol::m_style_cartoon(arrow = TRUE)) |>
        ## fit molecule into display area
        r3dmol::m_zoom_to()

    ## ----am_data-hg38-------------------------------------------------------------
    P35557 <-

    # --- Am Aa Pathogenicity [] ---
    # Key functions: am_aa_pathogenicity, js_template, colorfunc, tibble, af_colorfunc_by_position, pos, value
    pathogenicity <- am_aa_pathogenicity(P35557)
    pathogenicity
    cat(
        AlphaMissenseR:::js_template("colorfunc", colors = "..."),
        "\n"
    )
    df <- tibble(
        pos = 1 + 1:10, # no color information for position 1
        value = 10:1 / 10
    )
    colorfunc <- af_colorfunc_by_position(
        df,
        "pos", "value",
        pos_max = 12    # no color information for position 12
    )
    cat(colorfunc, "\n")

    # --- Colorfunc [] ---
    # Key functions: af_colorfunc_by_position, aa_pos, aa_pathogenicity_mean, r3dmol, m_add_model, m_bio3d, m_set_style, m_style_cartoon
    colorfunc <-
        pathogenicity |>
        af_colorfunc_by_position(
            "aa_pos", "aa_pathogenicity_mean",
            length(pdb$seqres)
        )
    r3dmol::r3dmol() |>
        ## use the PDB representation
        r3dmol::m_add_model(r3dmol::m_bio3d(pdb)) |>
        ## visualize as a 'cartoon' with alpha helices and beta sheets
    # --- Gosling Bar [] ---
    # Key functions: gosling_plot, bar, lollipop, db_disconnect_all
    gosling_plot(
        gpos, plot_type = "bar",
        title = "Q1W6H9 track",
        subtitle = "bar plot example"
    )
    gosling_plot(
        gpos, plot_type = "lollipop",
        title = "Q1W6H9 track",
        subtitle = "lollipop plot example"
    )
    db_disconnect_all()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alphamissenser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alphamissenser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alphamissenser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALPHAMISSENSER:", paste0("    alphamissenser: ", packageVersion("AlphaMissenseR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alphamissenser_results.csv
    touch ${prefix}_alphamissenser_output.rds
    echo "BIOC_ALPHAMISSENSER:" > versions.yml
    echo "    alphamissenser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALPHAMISSENSER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALPHAMISSENSER(ch_input)

    emit:
    results  = BIOC_ALPHAMISSENSER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALPHAMISSENSER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALPHAMISSENSER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALPHAMISSENSER.out.versions  // channel: path(versions.yml)
}
