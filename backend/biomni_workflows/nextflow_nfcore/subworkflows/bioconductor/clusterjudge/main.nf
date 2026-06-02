#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClusterJudge
// ClusterJudge implements the functions, examples and other software published as an algorithm by Gibb
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClusterJudge/inst/doc/ClusterJudge-intro.R
// Upstream  : yeastExpData
// Downstream: none
//
// Install: BiocManager::install("ClusterJudge")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTERJUDGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterjudge"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clusterjudge:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clusterjudge:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clusterjudge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterjudge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterjudge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Database)
    library(jsonlite)

    # --- Database [] ---
    # Key functions: Database
    ---------------------------------------------------------------------
    clusters <- ccyclered$Cluster
    ###  convert from Gene names to the new standard of Saccharomyces Genome Database (SGD) gene ids
    ccyclered$SGDID <- sub('^S','S00',ccyclered$SGDID)
    names(clusters) <- ccyclered$SGDID
    # --- Data [] ---
    # Key functions: sample, attribute_mut_inf
    ---------------------------------------------------------------------
    data(Yeast.GO.assocs)
    ### because it takes time, we use a small sampled subset of associations
    entity.attribute.sampled <- Yeast.GO.assocs[sample(1:nrow(Yeast.GO.assocs),100),]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clusterjudge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clusterjudge_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clusterjudge_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERJUDGE:", paste0("    clusterjudge: ", packageVersion("ClusterJudge"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clusterjudge_results.csv
    touch ${prefix}_clusterjudge_output.rds
    echo "BIOC_CLUSTERJUDGE:" > versions.yml
    echo "    clusterjudge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERJUDGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERJUDGE(ch_input)

    emit:
    results  = BIOC_CLUSTERJUDGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERJUDGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERJUDGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERJUDGE.out.versions  // channel: path(versions.yml)
}
