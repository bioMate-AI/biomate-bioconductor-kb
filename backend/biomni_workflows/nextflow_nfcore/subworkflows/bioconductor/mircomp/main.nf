#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miRcomp
// Based on a large miRNA dilution study, this package provides tools to read in the raw amplification 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miRcomp/inst/doc/miRcomp.R
// Upstream  : miRcompData
// Downstream: none
//
// Install: BiocManager::install("miRcomp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRCOMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mircomp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mircomp:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mircomp:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mircomp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mircomp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mircomp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(miRcomp)
    library(jsonlite)

    # --- quality Assessment [] ---
    # Key functions: qualityAssessment
    qualityAssessment(lifetech, plotType="scatter", label1="LifeTech AmpScore")
    # --- quality scatter2 [] ---
    # Key functions: qualityAssessment
    qualityAssessment(lifetech, object2=qpcRdefault, cloglog2=TRUE, plotType="scatter", label1="LifeTech AmpScore", label2="qpcR R-squared")
    # --- quality boxplot na [] ---
    # Key functions: qualityAssessment
    qualityAssessment(lifetech, plotType="boxplot", na.rm=TRUE, label1="LifeTech AmpScore")
    # --- complete Features [] ---
    # Key functions: completeFeatures
    completeFeatures(lifetech, qcThreshold1=1.25, label1="LifeTech")
    # --- complete features2 [] ---
    # Key functions: completeFeatures
    completeFeatures(lifetech, qcThreshold1=1.25, object2=qpcRdefault, qcThreshold2=0.99, label1="LifeTech", label2="qpcR")
    # --- complete features3 [] ---
    # Key functions: completeFeatures
    completeFeatures(lifetech, qcThreshold1=1.25, object2=lifetech, qcThreshold2=1.4, label1="LT 1.25", label2="LT 1.4")
    # --- limit detect boxplot [] ---
    # Key functions: limitOfDetection
    par(mar=c(6,6,2,2))
    boxes <- limitOfDetection(lifetech, qcThreshold=1.25, plotType="boxplot")
    str(boxes)
    # --- limit detect scatter [] ---
    # Key functions: limitOfDetection
    par(mfrow=c(1,3))
    lods <- limitOfDetection(lifetech, qcThreshold=1.25, plotType="scatter")
    # --- limit detect maplot [] ---
    # Key functions: limitOfDetection
    par(mfrow=c(1,3))
    lods <- limitOfDetection(lifetech, qcThreshold=1.25, plotType="MAplot")
    print(round(lods,digits=2))
    # --- titration response [] ---
    # Key functions: titrationResponse
    titrationResponse(lifetech, qcThreshold1=1.25)
    # --- titration response2 [] ---
    # Key functions: titrationResponse
    titrationResponse(lifetech, qcThreshold1=1.25, object2=qpcRdefault, qcThreshold2=0.99, label1="LifeTech", label2="qpcR")
    # --- titration response3 [] ---
    # Key functions: titrationResponse
    titrationResponse(lifetech, qcThreshold1=1.25, object2=qpcRdefault, qcThreshold2=0.99, commonFeatures=FALSE, label1="LifeTech", label2="qpcR")
    # --- titration response4 [] ---
    # Key functions: titrationResponse
    titrationResponse(lifetech, qcThreshold1=1.25, object2=lifetech, qcThreshold2=1.4, commonFeatures=FALSE, label1="AmpScore 1.25", label2="AmpScore 1.4")
    # --- accuracy [] ---
    # Key functions: accuracy
    accuracy(lifetech, qcThreshold1=1.25)
    # --- precision sd [] ---
    # Key functions: precision
    boxes <- precision(lifetech, qcThreshold1=1.25, statistic="sd")
    str(boxes)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mircomp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mircomp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mircomp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRCOMP:", paste0("    mircomp: ", packageVersion("miRcomp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mircomp_results.csv
    touch ${prefix}_mircomp_output.rds
    echo "BIOC_MIRCOMP:" > versions.yml
    echo "    mircomp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRCOMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIRCOMP(ch_input)

    emit:
    results  = BIOC_MIRCOMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRCOMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRCOMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRCOMP.out.versions  // channel: path(versions.yml)
}
