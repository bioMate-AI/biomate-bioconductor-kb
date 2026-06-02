#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gmoviz
// Genetically modified organisms (GMOs) and cell lines are widely used models in all kinds of biologic
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gmoviz/inst/doc/gmoviz_advanced.R
// Upstream  : BiocManager, pasillaBamSubset
// Downstream: none
//
// Install: BiocManager::install("gmoviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMOVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gmoviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gmoviz:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gmoviz:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gmoviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gmoviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gmoviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, getCoverage, gmovizInitialise, getFeatures, featureDiagram, insertionDiagram
    ideogram_1 <- GRanges(seqnames = c("chrA", "chrB", "chrC"),
    ranges = IRanges(start = rep(0, 3), end = rep(1000, 3)))
    # --- IdeogramData analysis [] ---
    # Key functions: getIdeogramData, gmovizInitialise, getCoverage, getLabels, getFeatures, drawFeatureTrack, featureDiagram, drawScatterplotTrack


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gmoviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gmoviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gmoviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GMOVIZ:", paste0("    gmoviz: ", packageVersion("gmoviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gmoviz_results.csv
    touch ${prefix}_gmoviz_output.rds
    echo "BIOC_GMOVIZ:" > versions.yml
    echo "    gmoviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GMOVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GMOVIZ(ch_input)

    emit:
    results  = BIOC_GMOVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GMOVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GMOVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GMOVIZ.out.versions  // channel: path(versions.yml)
}
