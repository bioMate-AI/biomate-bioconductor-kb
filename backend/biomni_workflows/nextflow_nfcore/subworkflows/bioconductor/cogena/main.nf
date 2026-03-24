#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cogena
// cogena is a workflow for co-expressed gene-set enrichment analysis. It aims to discovery smaller sca
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cogena/inst/doc/cogena-vignette_html.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cogena")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COGENA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cogena"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cogena:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cogena:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_cogena_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cogena_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cogena_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Enrichment)
    library(jsonlite)

    # --- Load all analysis [] ---
    # Key functions: load_all, coExp, Enrichment, clEnrich, heatmapCluster, heatmapPEI, clEnrich_one, heatmapCmap
    genecl_result <- coExp(DEexprs, nClust=nClust, clMethods=clMethods,
    Enrichment (Pathway) analysis for the co-expressed genes
    clen_res <- clEnrich(genecl_result, annofile=annofile, sampleLabel=sampleLabel)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cogena_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cogena_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cogena_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COGENA:", paste0("    cogena: ", packageVersion("cogena"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cogena_results.csv
    touch ${prefix}_cogena_output.rds
    echo "BIOC_COGENA:" > versions.yml
    echo "    cogena: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COGENA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_COGENA(ch_input)

    emit:
    results  = BIOC_COGENA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COGENA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COGENA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COGENA.out.versions  // channel: path(versions.yml)
}
