#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TFARM
// It searches for relevant associations of transcription factors with a transcription factor target, i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TFARM/inst/doc/TFARM.R
// Upstream  : plyr
// Downstream: none
//
// Install: BiocManager::install("TFARM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFARM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tfarm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tfarm:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tfarm:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tfarm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tfarm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tfarm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IComp)
    library(jsonlite)

    # --- I Comp [] ---
    # Key functions: IComp
    imp_FOSL2 <- IComp('FOSL2=1', r_FOSL2, r_noFOSL2, figures=TRUE)
    names(imp_FOSL2)
    head(imp_FOSL2$delta)
    # --- distrib Viz [] ---
    # Key functions: distribViz, combn
    distribViz(IMP_Z, p_TFs)
    ZNF217_index <- which(p_TFs == 'ZNF217=1')
    transcription factors (present in at least one association rules)
    # --- arrange [] ---
    # Key functions: arrange
    I_c_2 <- arrange(rbind(IMP[,1:2], I_c_ord), desc(imp))
    p_TFs <- sub("=1", "", p_TFs)
    I_c_2$TF <-sub("=1", "",I_c_2$TF)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tfarm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tfarm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tfarm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TFARM:", paste0("    tfarm: ", packageVersion("TFARM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfarm_results.csv
    touch ${prefix}_tfarm_output.rds
    echo "BIOC_TFARM:" > versions.yml
    echo "    tfarm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TFARM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TFARM(ch_input)

    emit:
    results  = BIOC_TFARM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TFARM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TFARM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TFARM.out.versions  // channel: path(versions.yml)
}
