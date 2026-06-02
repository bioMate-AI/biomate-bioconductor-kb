#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CAGEfightR
// CAGE is a widely used high throughput assay for measuring transcription start site (TSS) activity. C
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CAGEfightR/inst/doc/Introduction_to_CAGEfightR.R
// Upstream  : BiocParallel, Gviz, InteractionSet
// Downstream: CAGEWorkflow
//
// Install: BiocManager::install("CAGEfightR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAGEFIGHTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cagefightr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cagefightr:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cagefightr:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(cluster_object)

    output:
    tuple val(meta), path("${meta.id}_cagefightr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cagefightr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cagefightr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BigWigFileList)
    library(SeqinfoForUCSCGenome)
    library(jsonlite)

    # --- BigWigFileList analysis [] ---
    # Key functions: install_github, BigWigFileList, SeqinfoForUCSCGenome, quantifyCTSSs, quickTSSs, quickEnhancers, assignTxType, rowRanges
    CAGEclusters <- combineClusters(object1=exampleUnidirectional,
    CAGEclusters <- subsetBySupport(CAGEclusters,
    cluster_track <- trackClusters(CAGEclusters, name="Clusters", col=NA)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cagefightr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cagefightr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cagefightr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CAGEFIGHTR:", paste0("    cagefightr: ", packageVersion("CAGEfightR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cagefightr_results.csv
    touch ${prefix}_cagefightr_output.rds
    echo "BIOC_CAGEFIGHTR:" > versions.yml
    echo "    cagefightr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CAGEFIGHTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(cluster_object) ]

    main:
    BIOC_CAGEFIGHTR(ch_input)

    emit:
    results  = BIOC_CAGEFIGHTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CAGEFIGHTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CAGEFIGHTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CAGEFIGHTR.out.versions  // channel: path(versions.yml)
}
