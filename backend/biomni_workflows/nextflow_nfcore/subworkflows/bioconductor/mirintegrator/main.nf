#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mirIntegrator
// Tools for augmenting signaling pathways to perform pathway analysis of microRNA and mRNA expression 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mirIntegrator/inst/doc/mirIntegrator.R
// Upstream  : ROntoTools, graph
// Downstream: none
//
// Install: BiocManager::install("mirIntegrator")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRINTEGRATOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mirintegrator"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mirintegrator:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mirintegrator:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mirintegrator_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mirintegrator_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mirintegrator_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mirIntegrator)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: integrate_mir
    require("mirIntegrator")
     data(kegg_pathways)
     data(mirTarBase)
     kegg_pathways <- kegg_pathways[18:20] #delete this for augmenting all pathways.
     augmented_pathways <- integrate_mir(kegg_pathways, mirTarBase)
    # --- Data [] ---
    # Key functions: plot_augmented_pathway
    data(names_pathways)
    plot_augmented_pathway(kegg_pathways$"path:hsa04122",
                           augmented_pathways$"path:hsa04122",
                           names_pathways["path:hsa04122"] )
    # --- Plot Augmented Pathway [] ---
    # Key functions: plot_augmented_pathway
    plot_augmented_pathway(kegg_pathways$"path:hsa04122",
                             augmented_pathways$"path:hsa04122",
                             names_pathways["path:hsa04122"] )
    # --- Data [] ---
    # Key functions: plot_change
    data(augmented_pathways)
      data(kegg_pathways)
      data(names_pathways)
      plot_change(kegg_pathways,augmented_pathways, names_pathways)
    # --- Plot Change [] ---
    # Key functions: plot_change
    plot_change(kegg_pathways,augmented_pathways, names_pathways, sizeT = 10)
    # --- Data [] ---
    # Key functions: pathways2pdf
    data(augmented_pathways)
      data(kegg_pathways)
      data(names_pathways)
      pathways2pdf(kegg_pathways[18:20],augmented_pathways[18:20],
                   names_pathways[18:20], "three_pathways.pdf")
    # --- Data [] ---
    # Key functions: data
    data(GSE43592_miRNA)
      data(GSE43592_mRNA)
    # --- Data [] ---
    # Key functions: unlist, intersect, pe
    require(graph)
      require(ROntoTools)
      data(GSE43592_mRNA)
      data(GSE43592_miRNA)
      data(augmented_pathways)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mirintegrator_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mirintegrator_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mirintegrator_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRINTEGRATOR:", paste0("    mirintegrator: ", packageVersion("mirIntegrator"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirintegrator_results.csv
    touch ${prefix}_mirintegrator_output.rds
    echo "BIOC_MIRINTEGRATOR:" > versions.yml
    echo "    mirintegrator: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRINTEGRATOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIRINTEGRATOR(ch_input)

    emit:
    results  = BIOC_MIRINTEGRATOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRINTEGRATOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRINTEGRATOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRINTEGRATOR.out.versions  // channel: path(versions.yml)
}
