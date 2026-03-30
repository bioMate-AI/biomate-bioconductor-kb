#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GOfuncR
// GOfuncR performs a gene ontology enrichment analysis based on the ontology enrichment software FUNC.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GOfuncR/inst/doc/GOfuncR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GOfuncR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOFUNCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gofuncr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gofuncr:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gofuncr:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gofuncr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gofuncr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gofuncr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GOfuncR)
    library(jsonlite)

    # --- Head [] ---
    # Key functions: by
    ---------------------------------------------------------------------------------------------------
    ## first element of go_enrich result has the stats
    stats = res_hyper[[1]]
    ## top-GO categories
    head(stats)
    # --- Used [] ---
    # Key functions: used
    ---------------------------------------------------------------------------------------------------
    ## annotation package used (default='Homo.sapiens') and GO-graph version
    res_hyper[[3]]
    # --- Go Enrich [] ---
    # Key functions: go_enrich
    ---------------------------------------------------------------------------------------------------
    ## run binomial test, excluding the 'biological_process' domain,
    ## suppress output to screen
    res_binom = go_enrich(input_binom, test='binomial', n_randsets=100,
        silent=TRUE, domains=c('molecular_function', 'cellular_component'))
    # --- Plot Anno Scores [] ---
    # Key functions: plot_anno_scores
    ---------------------------------------------------------------------------------------------------
    ## hypergeometric test
    top_gos_hyper = res_hyper[[1]][1:5, 'node_id']
    # GO-categories with a high proportion of candidate genes
    top_gos_hyper
    # --- Nodes [] ---
    # Key functions: nodes, get_parent_nodes, get_child_nodes
    ---------------------------------------------------------------------------------------------------
    ## get the parent nodes (higher level GO-categories) of two GO-IDs
    get_parent_nodes(c('GO:0051082', 'GO:0042254'))
    ## get the child nodes (sub-categories) of two GO-IDs
    get_child_nodes(c('GO:0090070', 'GO:0000112'))
    # --- Get Names [] ---
    # Key functions: get_names
    ---------------------------------------------------------------------------------------------------
    ## get the full names and domains of two GO-IDs
    get_names(c('GO:0090070', 'GO:0000112'))
    # --- Get Ids [] ---
    # Key functions: get_ids
    ---------------------------------------------------------------------------------------------------
    ## get GO-IDs of categories that contain 'blood-brain barrier' in their names
    bbb = get_ids('blood-brain barrier')
    head(bbb)
    # --- Head [] ---
    # Key functions: get_anno_genes, get_names
    ---------------------------------------------------------------------------------------------------
    ## find all genes that are annotated to GO:0000109
    ## using default database 'Homo.sapiens'
    head(get_anno_genes(go_ids='GO:0000109'))
    ## find out wich genes from a set of genes
    # --- Get Anno Categories [] ---
    # Key functions: get_anno_categories
    ---------------------------------------------------------------------------------------------------
    ## get the GO-annotations for two random genes
    anno = get_anno_categories(c('BTC', 'SPAG5'))
    head(anno)
    # --- Get Anno Categories [] ---
    # Key functions: get_anno_categories, get_parent_nodes, get_names
    ---------------------------------------------------------------------------------------------------
    # get all direct annotations of NXPH4
    direct_anno = get_anno_categories('NXPH4')
    direct_anno
    # get parent nodes of directly annotated GO-categories

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gofuncr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gofuncr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gofuncr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOFUNCR:", paste0("    gofuncr: ", packageVersion("GOfuncR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gofuncr_results.csv
    touch ${prefix}_gofuncr_output.rds
    echo "BIOC_GOFUNCR:" > versions.yml
    echo "    gofuncr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOFUNCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOFUNCR(ch_input)

    emit:
    results  = BIOC_GOFUNCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOFUNCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOFUNCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOFUNCR.out.versions  // channel: path(versions.yml)
}
