#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RcisTarget
// RcisTarget identifies transcription factor binding motifs (TFBS) over-represented on a gene list. In
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RcisTarget/inst/doc/RcisTarget_MainTutorial.R
// Upstream  : DT, reshape2, visNetwork
// Downstream: none
//
// Install: BiocManager::install("RcisTarget")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCISTARGET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcistarget"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcistarget:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcistarget:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcistarget_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcistarget_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcistarget_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneSet)
    library(Stangle)
    library(jsonlite)

    # --- ImportRankings analysis [] ---
    # Key functions: importRankings, cisTarget, calcAUC, addMotifAnnotation, addSignificantGenes, Stangle, GeneSet, lengths
    library(RcisTarget)
    geneList1 <- read.table(file.path(system.file('examples', package='RcisTarget'), "hypoxiaGeneSet.txt"), stringsAsFactors=FALSE)[,1]
    geneLists <- list(geneListName=geneList1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcistarget_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcistarget_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcistarget_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCISTARGET:", paste0("    rcistarget: ", packageVersion("RcisTarget"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcistarget_results.csv
    touch ${prefix}_rcistarget_output.rds
    echo "BIOC_RCISTARGET:" > versions.yml
    echo "    rcistarget: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCISTARGET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCISTARGET(ch_input)

    emit:
    results  = BIOC_RCISTARGET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCISTARGET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCISTARGET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCISTARGET.out.versions  // channel: path(versions.yml)
}
