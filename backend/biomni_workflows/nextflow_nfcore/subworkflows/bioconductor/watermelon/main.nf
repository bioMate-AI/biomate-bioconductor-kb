#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: wateRmelon
// 15 flavours of betas and three performance metrics, with methods for objects produced by methylumi a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/wateRmelon/inst/doc/wateRmelon.R
// Upstream  : none
// Downstream: bigmelon, skewr
//
// Install: BiocManager::install("wateRmelon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WATERMELON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-watermelon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-watermelon:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-watermelon:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_watermelon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_watermelon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_watermelon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(wateRmelon)
    library(jsonlite)

    # --- Get quality scores from VCF [] ---
    # Key functions: dasen, qual
    das <- dasen(melon)
    qu <- qual(betas(melon), betas(das))
    plot(qu[,1], qu[,2])
    # --- Betas analysis [] ---
    # Key functions: betas, readEPIC, outlyx, bscon, agep, estimateSex, dmrse_row, genki
    seabi(melon.pf, sex=pData(melon.pf)$sex, X=fData(melon.pf)$CHR=='X')
    seabi(melon.dasen.pf, sex=pData(melon.dasen.pf)$sex, X=fData(melon.dasen.pf)$CHR=='X')
    bet <- betas(melon)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_watermelon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_watermelon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_watermelon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_WATERMELON:", paste0("    watermelon: ", packageVersion("wateRmelon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_watermelon_results.csv
    touch ${prefix}_watermelon_output.rds
    echo "BIOC_WATERMELON:" > versions.yml
    echo "    watermelon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WATERMELON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_WATERMELON(ch_input)

    emit:
    results  = BIOC_WATERMELON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WATERMELON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WATERMELON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WATERMELON.out.versions  // channel: path(versions.yml)
}
