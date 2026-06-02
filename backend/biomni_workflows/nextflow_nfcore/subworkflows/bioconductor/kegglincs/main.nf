#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: KEGGlincs
// See what is going on 'under the hood' of KEGG pathways by explicitly re-creating the pathway maps fr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/KEGGlincs/inst/doc/Example-workflow.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("KEGGlincs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEGGLINCS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-kegglincs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-kegglincs:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-kegglincs:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_kegglincs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_kegglincs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_kegglincs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KEGG_lincs)
    library(jsonlite)

    # --- get KGML [] ---
    # Key functions: get_KGML, slot
    FoxO_KGML <- get_KGML("hsa04068")
    slot(FoxO_KGML, "pathwayInfo")
    # --- access KGML [] ---
    # Key functions: slot
    slot(slot(FoxO_KGML, "pathwayInfo"), "image")
    # --- slot [] ---
    # Key functions: slot
    image_link <- slot(slot(FoxO_KGML, "pathwayInfo"), "image")
    download.file(image_link, basename(image_link), mode = "wb")
    # --- speed up for ex [] ---
    # Key functions: expand_KEGG_mappings
    FoxO_KEGG_mappings <- expand_KEGG_mappings(FoxO_KGML, convert_KEGG_IDs = FALSE)
    # --- expand mapping for show [] ---
    # Key functions: expand_KEGG_mappings
    FoxO_KEGG_mappings <- expand_KEGG_mappings(FoxO_KGML)
    # --- expand_ K E G G_edges [] ---
    # Key functions: expand_KEGG_edges
    FoxO_edges <- expand_KEGG_edges(FoxO_KGML, FoxO_KEGG_mappings)
    # --- node_mapping_info [] ---
    # Key functions: node_mapping_info, edge_mapping_info, get_graph_object
    FoxO_node_mapping_info <- node_mapping_info(FoxO_KEGG_mappings)
    FoxO_edge_mapping_info <- edge_mapping_info(FoxO_edges)
    GO <- get_graph_object(FoxO_node_mapping_info, FoxO_edge_mapping_info)
    # --- cyto_vis [] ---
    # Key functions: cyto_vis
    cyto_vis(GO, "FoxO Pathway with Expanded Edges[no data added]")
    # --- default p53 [] ---
    # Key functions: KEGG_lincs
    KEGG_lincs("hsa04115")
    # --- begin workflow1 [] ---
    # Key functions: get_KGML, expand_KEGG_mappings, expand_KEGG_edges
    p53_KGML <- get_KGML("hsa04115")
    p53_KEGG_mappings <- expand_KEGG_mappings(p53_KGML)
    p53_edges <- expand_KEGG_edges(p53_KGML, p53_KEGG_mappings)
    # --- show pathway genes [] ---
    # Key functions: path_genes_by_cell_type
    path_genes_by_cell_type(p53_KEGG_mappings)
    # --- show summary for ex [] ---
    # Key functions: path_genes_by_cell_type
    p53_L1000_summary <- path_genes_by_cell_type(p53_KEGG_mappings, get_KOs = TRUE)
    # --- avoid poor map render [] ---
    # Key functions: path_genes_by_cell_type

    # --- overlap_info [] ---
    # Key functions: overlap_info
    p53_PC3_data <- overlap_info(p53_KGML, p53_KEGG_mappings, "PC3")
    p53_HA1E_data <- overlap_info(p53_KGML, p53_KEGG_mappings, "HA1E")
    # --- show overlap data [] ---
    # Key functions: kable
    knitr::kable(head(p53_PC3_data[1:6]))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_kegglincs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_kegglincs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_kegglincs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KEGGLINCS:", paste0("    kegglincs: ", packageVersion("KEGGlincs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kegglincs_results.csv
    touch ${prefix}_kegglincs_output.rds
    echo "BIOC_KEGGLINCS:" > versions.yml
    echo "    kegglincs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KEGGLINCS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KEGGLINCS(ch_input)

    emit:
    results  = BIOC_KEGGLINCS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KEGGLINCS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KEGGLINCS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KEGGLINCS.out.versions  // channel: path(versions.yml)
}
