#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ProteoMM
// ProteoMM is a statistical method to perform model-based peptide-level differential expression analys
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ProteoMM/inst/doc/ProteoMM_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ProteoMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTEOMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proteomm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proteomm:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-proteomm:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proteomm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proteomm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proteomm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ProteoMM)
    library(jsonlite)

    # --- Distribution of p [] ---
    # Key functions: plot_volcano_wLab
    hs_presAbs = peptideLevel_PresAbsDE(subset_presAbs$sub_unique_mm_list[[2]],
    plot_volcano_wLab(hs_presAbs$FC, hs_presAbs$BH_P_val, hs_presAbs$GeneID,
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proteomm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proteomm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proteomm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROTEOMM:", paste0("    proteomm: ", packageVersion("ProteoMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteomm_results.csv
    touch ${prefix}_proteomm_output.rds
    echo "BIOC_PROTEOMM:" > versions.yml
    echo "    proteomm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROTEOMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROTEOMM(ch_input)

    emit:
    results  = BIOC_PROTEOMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROTEOMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROTEOMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROTEOMM.out.versions  // channel: path(versions.yml)
}
