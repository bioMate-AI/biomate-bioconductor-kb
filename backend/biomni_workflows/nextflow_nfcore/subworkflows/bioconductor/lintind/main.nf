#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LinTInd
// When we combine gene-editing technology and sequencing technology, we need to reconstruct a lineage 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LinTInd/inst/doc/tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("LinTInd")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LINTIND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lintind"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lintind:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lintind:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lintind_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lintind_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lintind_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BuildTree)
    library(FindIndel)
    library(IndelForm)
    library(IndelIdents)
    library(IndelPlot)
    library(PlotTree)
    library(TagProcess)
    library(jsonlite)

    # --- Indel analysis [] ---
    # Key functions: FindIndel, IndelForm, IndelIdents, IndelPlot, TagProcess, BuildTree, PlotTree
    scarinfo<-FindIndel(data=data,scarfull=ref,scar=cutsite,indel.coverage="All",type="test",cln=1)
    scarinfo<-IndelForm(scarinfo,cln=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lintind_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lintind_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lintind_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LINTIND:", paste0("    lintind: ", packageVersion("LinTInd"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lintind_results.csv
    touch ${prefix}_lintind_output.rds
    echo "BIOC_LINTIND:" > versions.yml
    echo "    lintind: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LINTIND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LINTIND(ch_input)

    emit:
    results  = BIOC_LINTIND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LINTIND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LINTIND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LINTIND.out.versions  // channel: path(versions.yml)
}
