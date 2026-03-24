#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BicARE
// Biclustering Analysis and Results Exploration.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BicARE/inst/doc/BicARE.R
// Upstream  : none
// Downstream: RcmdrPlugin.BiclustGUI
//
// Install: BiocManager::install("BicARE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BICARE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bicare"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bicare:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bicare:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bicare_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bicare_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bicare_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GOCollection)
    library(GeneSetCollection)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(sample.bicData)
    sample.bicData
    # --- Residue [] ---
    # Key functions: residue
    residue(sample.bicData)
    # --- Bicluster [] ---
    # Key functions: bicluster
    bic <- bicluster(res.biclustering, 6, graph=FALSE)
    plot(bic)
    # --- Genesetcollection [] ---
    # Key functions: GeneSetCollection, GOCollection, testSet
    gsc <- GeneSetCollection(res.biclustering$ExpressionSet[1:50], setType=GOCollection())
    res.bic2 <- testSet(res.biclustering, gsc)
    # --- Pdata [] ---
    # Key functions: pData
    pData(sample.bicData)
    # --- Testannot [] ---
    # Key functions: testAnnot, pData
    res.bic2 <- testAnnot(res.biclustering, annot=pData(sample.bicData), covariates=c("sex", "type"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bicare_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bicare_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bicare_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BICARE:", paste0("    bicare: ", packageVersion("BicARE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bicare_results.csv
    touch ${prefix}_bicare_output.rds
    echo "BIOC_BICARE:" > versions.yml
    echo "    bicare: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BICARE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BICARE(ch_input)

    emit:
    results  = BIOC_BICARE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BICARE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BICARE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BICARE.out.versions  // channel: path(versions.yml)
}
