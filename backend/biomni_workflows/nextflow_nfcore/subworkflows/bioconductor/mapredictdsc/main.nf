#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: maPredictDSC
// This package implements the classification pipeline of the best overall team (Team221) in the IMPROV
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/maPredictDSC/inst/doc/maPredictDSC.R
// Upstream  : LungCancerACvsSCCGEO
// Downstream: none
//
// Install: BiocManager::install("maPredictDSC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAPREDICTDSC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mapredictdsc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mapredictdsc:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mapredictdsc:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mapredictdsc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mapredictdsc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mapredictdsc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(maPredictDSC)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(maPredictDSC)
    library(LungCancerACvsSCCGEO)
    data(LungCancerACvsSCCGEO)
    anoLC
    gsLC
    # --- Predictdsc [] ---
    # Key functions: predictDSC
    modlist=predictDSC(ano=anoLC,
    celfile.path=system.file("extdata/lungcancer",package="LungCancerACvsSCCGEO"),
    annotation="hgu133plus2.db", preprocs=c("rma"),
    filters=c("mttest","ttest"),classifiers=c("LDA","kNN"),
    CVP=2,NF=4, NR=1,FCT=1.0)
    # --- Sort [] ---
    # Key functions: unlist
    trainingAUC=sort(unlist(lapply(modlist,"[[","best_AUC")),decreasing=TRUE)
    cbind(trainingAUC)
    # --- Function [] ---
    # Key functions: perfDSC, frame
    perF=function(out){
    perfDSC(pred=out$predictions,gs=gsLC)
    }
    testPerf=t(data.frame(lapply(modlist,perF)))
    testPerf=testPerf[order(testPerf[,"AUC"],decreasing=TRUE),]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mapredictdsc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mapredictdsc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mapredictdsc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAPREDICTDSC:", paste0("    mapredictdsc: ", packageVersion("maPredictDSC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mapredictdsc_results.csv
    touch ${prefix}_mapredictdsc_output.rds
    echo "BIOC_MAPREDICTDSC:" > versions.yml
    echo "    mapredictdsc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAPREDICTDSC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAPREDICTDSC(ch_input)

    emit:
    results  = BIOC_MAPREDICTDSC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAPREDICTDSC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAPREDICTDSC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAPREDICTDSC.out.versions  // channel: path(versions.yml)
}
