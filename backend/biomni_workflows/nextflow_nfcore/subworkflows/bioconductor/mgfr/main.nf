#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MGFR
// The package is designed to detect marker genes from RNA-seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MGFR/inst/doc/MGFR.R
// Upstream  : none
// Downstream: sampleClassifier
//
// Install: BiocManager::install("MGFR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MGFR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mgfr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mgfr:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mgfr:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mgfr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mgfr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mgfr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MGFR)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data("ref.mat")
    dim(ref.mat)
    colnames(ref.mat)
    # --- Reference [] ---
    # Key functions: rnaseq
    library(MGFR)
    data("ref.mat")
    markers.list <- getMarkerGenes.rnaseq(ref.mat, class.vec = colnames(ref.mat),samples2compare="all", annotate=TRUE, gene.ids.type="ensembl", score.cutoff=1)
    names(markers.list)
    # show the first 20 markers of liver

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mgfr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mgfr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mgfr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MGFR:", paste0("    mgfr: ", packageVersion("MGFR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mgfr_results.csv
    touch ${prefix}_mgfr_output.rds
    echo "BIOC_MGFR:" > versions.yml
    echo "    mgfr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MGFR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MGFR(ch_input)

    emit:
    results  = BIOC_MGFR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MGFR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MGFR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MGFR.out.versions  // channel: path(versions.yml)
}
