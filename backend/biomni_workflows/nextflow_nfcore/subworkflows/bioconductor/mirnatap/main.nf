#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miRNAtap
// The package facilitates implementation of workflows requiring miRNA predictions, it allows to integr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miRNAtap/inst/doc/miRNAtap.R
// Upstream  : none
// Downstream: miRNAtap.db
//
// Install: BiocManager::install("miRNAtap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRNATAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mirnatap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mirnatap:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mirnatap:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mirnatap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mirnatap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mirnatap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenTable)
    library(jsonlite)

    # --- Getpredictedtargets [] ---
    # Key functions: getPredictedTargets
    mir = 'miR-10b'
    predictions = getPredictedTargets(mir, species = 'hsa',
                                        method = 'geom', min_src = 2)
    # --- Function [] ---
    # Key functions: org, new
    rankedGenes = predictions[,'rank_product']
    selection = function(x) TRUE
    # we do not want to impose a cut off, instead we are using rank information
    allGO2genes = annFUN.org(whichOnto='BP', feasibleGenes = NULL,
                    mapping="org.Hs.eg.db", ID = "entrez")
    # --- Runtest [] ---
    # Key functions: runTest
    results.ks = runTest(GOdata, algorithm = "classic", statistic = "ks")
    results.ks
    # --- Gentable [] ---
    # Key functions: GenTable
    allRes = GenTable(GOdata, KS = results.ks, orderBy = "KS", topNodes = 20)
    allRes[,c('GO.ID','Term','KS')]
    # --- Tolatex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mirnatap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mirnatap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mirnatap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRNATAP:", paste0("    mirnatap: ", packageVersion("miRNAtap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirnatap_results.csv
    touch ${prefix}_mirnatap_output.rds
    echo "BIOC_MIRNATAP:" > versions.yml
    echo "    mirnatap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRNATAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIRNATAP(ch_input)

    emit:
    results  = BIOC_MIRNATAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRNATAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRNATAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRNATAP.out.versions  // channel: path(versions.yml)
}
