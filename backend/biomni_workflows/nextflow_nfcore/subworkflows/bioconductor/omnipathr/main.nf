#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OmnipathR
// A client for the OmniPath web service (https://www.omnipathdb.org) and many other resources. It also
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OmnipathR/inst/doc/bioc_workshop.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("OmnipathR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMNIPATHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omnipathr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omnipathr:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omnipathr:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omnipathr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omnipathr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omnipathr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OmnipathR)
    library(jsonlite)


    # --- Network [] ---
    # Key functions: transcriptional, interaction_graph
    gri <- transcriptional()
    gri

    ## ----network-igraph-----------------------------------------------------------------------------------------
    gr_graph <- interaction_graph(gri)
    gr_graph

    # --- Paths [] ---
    # Key functions: find_all_paths
    paths <- find_all_paths(
        graph = gr_graph,
        start = c('EGFR', 'STAT3'),
        end = c('AKT1', 'ULK1'),
        attr = 'name'
    )

    # --- Enzsub [] ---
    # Key functions: enzyme_substrate, enzsub_graph, signed_ptms
    enz_sub <- enzyme_substrate()
    enz_sub

    ## ----enzsub-igraph------------------------------------------------------------------------------------------
    es_graph <- enzsub_graph(enz_sub)
    es_graph

    ## ----enzsub-signs-------------------------------------------------------------------------------------------
    es_signed <- signed_ptms(enz_sub)

    # --- Complexes [] ---
    # Key functions: complexes, annotations, omnipath, annotated_network
    cplx <- complexes()
    cplx

    ## ----uniprot-loc--------------------------------------------------------------------------------------------
    uniprot_loc <- annotations(
        resources = 'UniProt_location',
        wide = TRUE
    )
    uniprot_loc

    # --- Intercell [] ---
    # Key functions: intercell, intercell_network, filter_intercell_network, annotation_resources, intercell_generic_categories, intercell_categories, translate_ids, omnipath
    ic <- intercell()
    ic

    ## ----intercell-network--------------------------------------------------------------------------------------
    icn <- intercell_network(high_confidence = TRUE)
    icn

    ## ----intercell-filter---------------------------------------------------------------------------------------
    icn <- intercell_network()
    # --- GO [] ---
    # Key functions: go_ontology_download, relations_table_to_graph, ontology_ensure_name
    go <- go_ontology_download()
    go$rel_tbl_c2p

    ## ----go-graph-----------------------------------------------------------------------------------------------
    go_graph <- relations_table_to_graph(go$rel_tbl_c2p)
    go_graph

    ## ----go-name------------------------------------------------------------------------------------------------
    ontology_ensure_name('GO:0000022')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omnipathr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omnipathr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omnipathr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMNIPATHR:", paste0("    omnipathr: ", packageVersion("OmnipathR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omnipathr_results.csv
    touch ${prefix}_omnipathr_output.rds
    echo "BIOC_OMNIPATHR:" > versions.yml
    echo "    omnipathr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMNIPATHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMNIPATHR(ch_input)

    emit:
    results  = BIOC_OMNIPATHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMNIPATHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMNIPATHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMNIPATHR.out.versions  // channel: path(versions.yml)
}
