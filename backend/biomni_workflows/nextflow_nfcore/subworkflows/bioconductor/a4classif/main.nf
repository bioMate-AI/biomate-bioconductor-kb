#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: a4Classif
// Functionalities for classification of Affymetrix microarray data, integrating within the Automated A
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/a4Classif/inst/doc/a4Classif-vignette.R
// Upstream  : ALL
// Downstream: a4
//
// Install: BiocManager::install("a4Classif")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_A4CLASSIF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-a4classif"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-a4classif:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-a4classif:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_a4classif_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_a4classif_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_a4classif_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ROCcurve)
    library(jsonlite)

    # --- add Gene Info [] ---
    # Key functions: addGeneInfo
    data(ALL, package = "ALL")
    ALL <- addGeneInfo(ALL)
    ALL$BTtype <- as.factor(substr(ALL$BT,0,1))
    # --- Get top DE genes table (limma) [] ---
    # Key functions: lassoClass, topTable
    resultLasso <- lassoClass(object = ALL, groups = "BTtype")
    plot(resultLasso,
    topTable(resultLasso, n = 15)
    # --- Get top DE genes table (limma) [] ---
    # Key functions: pamClass, topTable, confusionMatrix
    resultPam <- pamClass(object = ALL, groups = "BTtype")
    plot(resultPam,
    topTable(resultPam, n = 15)
    # --- Get top DE genes table (limma) [] ---
    # Key functions: rfClass, topTable
    ALLSubset <- ALL[sample.int(n = nrow(ALL), size = 100, replace = FALSE), ]
    resultRf <- rfClass(object = ALLSubset, groups = "BTtype")
    plot(resultRf)
    # --- R O Ccurve [] ---
    # Key functions: ROCcurve
    ROCcurve(gene = "ABL1", object = ALL, groups = "BTtype")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_a4classif_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_a4classif_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_a4classif_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_A4CLASSIF:", paste0("    a4classif: ", packageVersion("a4Classif"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_a4classif_results.csv
    touch ${prefix}_a4classif_output.rds
    echo "BIOC_A4CLASSIF:" > versions.yml
    echo "    a4classif: 0.0.0" >> versions.yml
    """
}


workflow BIOC_A4CLASSIF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_A4CLASSIF(ch_input)

    emit:
    results  = BIOC_A4CLASSIF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_A4CLASSIF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_A4CLASSIF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_A4CLASSIF.out.versions  // channel: path(versions.yml)
}
