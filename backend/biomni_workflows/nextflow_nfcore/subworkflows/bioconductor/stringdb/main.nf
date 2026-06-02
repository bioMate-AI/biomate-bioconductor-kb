#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: STRINGdb
// The STRINGdb package provides a R interface to the STRING protein-protein interactions database (htt
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/STRINGdb/inst/doc/STRINGdb.R
// Upstream  : none
// Downstream: PPInfer
//
// Install: BiocManager::install("STRINGdb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STRINGDB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-stringdb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-stringdb:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-stringdb:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_stringdb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_stringdb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_stringdb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(STRINGdb)
    library(jsonlite)

    # --- Help [] ---
    # Key functions: methods
    STRINGdb$methods()              # To list all the methods available.
    STRINGdb$help("get_graph")      # To visualize their documentation.
    # --- Load Data [] ---
    # Key functions: data
    data(diff_exp_example1)
    head(diff_exp_example1)
    # --- Map [] ---
    # Key functions: map
    example1_mapped <- string_db$map( diff_exp_example1, "gene", removeUnmappedRows = TRUE )
    # --- Plot Network [] ---
    # Key functions: getOption, plot_network
    getOption("SweaveHooks")[["fig"]]()
    string_db$plot_network( hits )
    # --- Add Diff Exp Color [] ---
    # Key functions: add_diff_exp_color
    # filter by p-value and add a color column
    # (i.e. green down-regulated gened and red for up-regulated genes)
    example1_mapped_pval05 <- string_db$add_diff_exp_color( subset(example1_mapped, pvalue<0.05),
                                                                logFcColStr="logFC" )
    # --- Post Payload [] ---
    # Key functions: post_payload
    # post payload information to the STRING server
    payload_id <- string_db$post_payload( example1_mapped_pval05$STRING_id,
                                            colors=example1_mapped_pval05$color )
    # --- Plot Halo Network [] ---
    # Key functions: getOption, plot_network
    getOption("SweaveHooks")[["fig"]]()
    # display a STRING network png with the "halo"
    string_db$plot_network( hits, payload_id=payload_id )
    # --- Enrichment [] ---
    # Key functions: get_enrichment
    enrichment <- string_db$get_enrichment( hits )
    head(enrichment, n=20)
    # --- Enrichment [] ---
    # Key functions: get_annotations
    annotations <- string_db$get_annotations( hits )
    head(annotations, n=20)
    # --- Clustering1 [] ---
    # Key functions: get_clusters
    # get clusters
    clustersList <- string_db$get_clusters(example1_mapped$STRING_id[1:600])
    # --- Clustering2 [] ---
    # Key functions: getOption, plot_network
    getOption("SweaveHooks")[["fig"]]()
    # plot first 4 clusters
    par(mfrow=c(2,2))
    # --- Proteins [] ---
    # Key functions: get_proteins
    string_proteins <- string_db$get_proteins()
    # --- Atmtp [] ---
    # Key functions: mp
    tp53 = string_db$mp( "tp53" )
    atm = string_db$mp( "atm" )
    # --- Neighbors [] ---
    # Key functions: get_neighbors
    string_db$get_neighbors( c(tp53, atm) )
    # --- Interactions [] ---
    # Key functions: get_interactions
    string_db$get_interactions( c(tp53, atm) )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_stringdb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_stringdb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_stringdb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STRINGDB:", paste0("    stringdb: ", packageVersion("STRINGdb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stringdb_results.csv
    touch ${prefix}_stringdb_output.rds
    echo "BIOC_STRINGDB:" > versions.yml
    echo "    stringdb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STRINGDB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STRINGDB(ch_input)

    emit:
    results  = BIOC_STRINGDB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STRINGDB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STRINGDB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STRINGDB.out.versions  // channel: path(versions.yml)
}
