#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DOSE
// This package implements five methods proposed by Resnik, Schlicker, Jiang, Lin and Wang respectively
//
// Source : https://yulab-smu.top/biomedical-knowledge-mining-book/012-DOSE-semantic-similarity.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DOSE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dose"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dose:4.0.1--r44_0' :
        'quay.io/biocontainers/bioconductor-dose:4.0.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dose_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dose_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dose_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DOSE)
    library(jsonlite)

    # --- DO term semantic similarity measurement [] ---
    # Key functions: doSim
    library(DOSE)
    
    a <- c("DOID:14095", "DOID:5844", "DOID:2044", "DOID:8432", "DOID:9146",
           "DOID:10588", "DOID:3209", "DOID:848", "DOID:3341", "DOID:252")
    b <- c("DOID:9409", "DOID:2491", "DOID:4467", "DOID:3498", "DOID:11256")
    doSim(a[1], b[1], measure="Wang")
    
    doSim(a[1], b[1], measure="Resnik")
    
    doSim(a[1], b[1], measure="Lin")
    
    s <- doSim(a, b, measure="Wang")
    # --- Gene semantic similarity measurement [] ---
    # Key functions: geneSim
    g1 <- c("84842", "2524", "10590", "3070", "91746")
    g2 <- c("84289", "6045", "56999", "9869")
    
    DOSE::geneSim(g1[1], g2[1], measure="Wang", combine="BMA")
    
    gs <- DOSE::geneSim(g1, g2, measure="Wang", combine="BMA")
    gs
    # --- Gene cluster semantic similarity measurement [] ---
    # Key functions: clusterSim, mclusterSim
    DOSE::clusterSim(g1, g2, measure="Wang", combine="BMA")
    
    g3 <- c("57491", "6296", "51438", "5504", "27319", "1643")
    clusters <- list(a=g1, b=g2, c=g3)
    DOSE::mclusterSim(clusters, measure="Wang", combine="BMA")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dose_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dose_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dose_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DOSE:", paste0("    dose: ", packageVersion("DOSE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dose_results.csv
    touch ${prefix}_dose_output.rds
    echo "BIOC_DOSE:" > versions.yml
    echo "    dose: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DOSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DOSE(ch_input)

    emit:
    results  = BIOC_DOSE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DOSE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DOSE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DOSE.out.versions  // channel: path(versions.yml)
}
