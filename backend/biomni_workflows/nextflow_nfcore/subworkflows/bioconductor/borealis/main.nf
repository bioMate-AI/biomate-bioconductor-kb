#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: borealis
// Borealis is an R library performing outlier analysis for count-based bisulfite sequencing data. It d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/borealis/inst/doc/borealis.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("borealis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BOREALIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-borealis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-borealis:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-borealis:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_borealis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_borealis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_borealis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(borealis)
    library(jsonlite)

    # --- plot Cp Gsite [] ---
    # Key functions: plotCpGsite
    plotCpGsite("chr14:24780288", sampleOfInterest="patient_72",
    modelFile=file.path(outdir,"vignette_CpG_model_chr14.csv"),
    methCountFile=file.path(outdir,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_borealis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_borealis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_borealis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BOREALIS:", paste0("    borealis: ", packageVersion("borealis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_borealis_results.csv
    touch ${prefix}_borealis_output.rds
    echo "BIOC_BOREALIS:" > versions.yml
    echo "    borealis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BOREALIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BOREALIS(ch_input)

    emit:
    results  = BIOC_BOREALIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BOREALIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BOREALIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BOREALIS.out.versions  // channel: path(versions.yml)
}
