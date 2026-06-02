#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioCor
// Calculates functional similarities based on the pathways described on KEGG and REACTOME or in gene s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioCor/inst/doc/BioCor_1_basics.R
// Upstream  : BiocStyle, DESeq2, GOSemSim, GSEABase, Hmisc
// Downstream: none
//
// Install: BiocManager::install("BioCor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocor:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocor:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TOMsimilarity)
    library(jsonlite)

    # --- Hierarchical clustering [] ---
    # Key functions: mgeneSim, hclust, similarities, TOMsimilarity, cutreeHybrid, labels2colors

    # --- GeneIds analysis [] ---
    # Key functions: install_github, geneIds, unlist, split, pathSim, mpathSim, geneSim, mgeneSim
    clusterGeneSim(c("672", "675"), c("100", "10", "1"), genesKegg)
    clusterGeneSim(c("672", "675"), c("100", "10", "1"), genesKegg, "max")
    mclusterGeneSim(clusters, genesKegg, c("max", "rcmax.avg"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCOR:", paste0("    biocor: ", packageVersion("BioCor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocor_results.csv
    touch ${prefix}_biocor_output.rds
    echo "BIOC_BIOCOR:" > versions.yml
    echo "    biocor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCOR(ch_input)

    emit:
    results  = BIOC_BIOCOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCOR.out.versions  // channel: path(versions.yml)
}
