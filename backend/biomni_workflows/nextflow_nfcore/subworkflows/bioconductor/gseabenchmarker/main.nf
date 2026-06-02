#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSEABenchmarkeR
// The GSEABenchmarkeR package implements an extendable framework for reproducible evaluation of set- a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSEABenchmarkeR/inst/doc/GSEABenchmarkeR.R
// Upstream  : EnrichmentBrowser
// Downstream: none
//
// Install: BiocManager::install("GSEABenchmarkeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEABENCHMARKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gseabenchmarker"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gseabenchmarker:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gseabenchmarker:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gseabenchmarker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gseabenchmarker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gseabenchmarker_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(jsonlite)

    # --- Feature metadata inspection [] ---
    # Key functions: loadEData, maPreproc, runDE, rowData, runEA, runif, bpPlot, lengths
    all.kegg.res <- evalRelevance(ea.ranks, mala.kegg, d2d.map[names(geo2kegg)])
    bpPlot(all.kegg.res, what="rel.sets")
    rel.ranks$REL.SCORE <- runif(nrow(rel.ranks), min=1, max=100)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gseabenchmarker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gseabenchmarker_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gseabenchmarker_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSEABENCHMARKER:", paste0("    gseabenchmarker: ", packageVersion("GSEABenchmarkeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gseabenchmarker_results.csv
    touch ${prefix}_gseabenchmarker_output.rds
    echo "BIOC_GSEABENCHMARKER:" > versions.yml
    echo "    gseabenchmarker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSEABENCHMARKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSEABENCHMARKER(ch_input)

    emit:
    results  = BIOC_GSEABENCHMARKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSEABENCHMARKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSEABENCHMARKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSEABENCHMARKER.out.versions  // channel: path(versions.yml)
}
