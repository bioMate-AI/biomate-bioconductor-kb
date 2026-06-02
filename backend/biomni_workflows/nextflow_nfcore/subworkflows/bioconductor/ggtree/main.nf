#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggtree
// 'ggtree' extends the 'ggplot2' plotting system which implemented the grammar of graphics. 'ggtree' i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggtree/inst/doc/ggtree.R
// Upstream  : none
// Downstream: ggtreeDendro, tanggle
//
// Install: BiocManager::install("ggtree")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGTREE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggtree"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggtree:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggtree:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggtree_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggtree_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggtree_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggtree)
    library(jsonlite)


    # --- Treeman [] ---
    # Key functions: collapse, expand, flip, groupClade, groupOTU, identify, rotate, rotate_tree
    treeman <- matrix(c(
      "collapse", "collapse a selecting clade",
      "expand", "expand collapsed clade",
      "flip", "exchange position of 2 clades that share a parent node",
      "groupClade", "grouping clades",
      "groupOTU", "grouping OTUs by tracing back to most recent common ancestor",
      "identify", "interactive tree manipulation",
      "rotate", "rotating a selected clade by 180 degree",
      "rotate_tree", "rotating circular layout tree by specific angle",
      "scaleClade", "zoom in or zoom out selecting clade",
      "open_tree", "convert a tree to fan layout by specific open angle"
    ), ncol=2, byrow=TRUE)
    treeman <- as.data.frame(treeman)
    colnames(treeman) <- c("Function", "Descriptiotn")
    knitr::kable(treeman, caption = "Tree manipulation functions.", booktabs = T)

    # --- Geoms [] ---
    # Key functions: and, geom_balance, geom_cladelabel, geom_cladelabel2, geom_hilight, geom_hilight_encircle, geom_label2, geom_nodelab
    geoms <- matrix(c(
      "geom_balance", "highlights the two direct descendant clades of an internal node",
      "geom_cladelabel", "annotate a clade with bar and text label",
      "geom_cladelabel2", "annotate a clade with bar and text label for unrooted layout",
      "geom_hilight", "highlight a clade with rectangle",
      "geom_hilight_encircle", "highlight a clade with xspline for unrooted layout",
      "geom_label2", "modified version of geom_label, with subsetting supported",
      "geom_nodelab", "layer for node labels, which can be text or image",
      "geom_nodepoint", "annotate internal nodes with symbolic points",
      "geom_point2", "modified version of geom_point, with subsetting supported",
      "geom_range", "bar layer to present uncertainty of evolutionary inference",
      "geom_rootpoint", "annotate root node with symbolic point",
      "geom_segment2", "modified version of geom_segment, with subsetting supported",
      "geom_strip", "annotate associated taxa with bar and (optional) text label",
      "geom_taxalink", "associate two related taxa by linking them with a curve",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggtree_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggtree_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggtree_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGTREE:", paste0("    ggtree: ", packageVersion("ggtree"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggtree_results.csv
    touch ${prefix}_ggtree_output.rds
    echo "BIOC_GGTREE:" > versions.yml
    echo "    ggtree: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGTREE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGTREE(ch_input)

    emit:
    results  = BIOC_GGTREE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGTREE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGTREE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGTREE.out.versions  // channel: path(versions.yml)
}
