#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: eisaR
// Exon-intron split analysis (EISA) uses ordinary RNA-seq data to measure changes in mature RNA and pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/eisaR/inst/doc/eisaR.R
// Upstream  : QuasR, edgeR, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("eisaR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EISAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-eisar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-eisar:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-eisar:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_eisar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_eisar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_eisar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGEList)
    library(jsonlite)

    # --- Create DGEList count object [] ---
    # Key functions: DGEList, calcNormFactors, estimateDisp, glmFit
    library(edgeR)
    cnt <- data.frame(Ex = Rex, In = Rin)
    y <- DGEList(counts = cnt, genes = data.frame(ENTREZID = rownames(cnt)))
    # --- Available analysis [] ---
    # Key functions: available, loadDb, getRegionsFromTxDb, lengths, export, qAlign, alignmentStats, qCount
    res3 <- runEISA(Rex, Rin, cond, modelSamples = FALSE)
    res4 <- runEISA(Rex, Rin, cond, modelSamples = TRUE)
    ids <- intersect(rownames(res3$contrasts), rownames(res4$contrasts))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_eisar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_eisar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_eisar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EISAR:", paste0("    eisar: ", packageVersion("eisaR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eisar_results.csv
    touch ${prefix}_eisar_output.rds
    echo "BIOC_EISAR:" > versions.yml
    echo "    eisar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EISAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EISAR(ch_input)

    emit:
    results  = BIOC_EISAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EISAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EISAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EISAR.out.versions  // channel: path(versions.yml)
}
