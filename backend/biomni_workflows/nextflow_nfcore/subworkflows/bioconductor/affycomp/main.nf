#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: affycomp
// The package contains functions that can be used to compare expression measures for Affymetrix Oligon
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/affycomp/inst/doc/affycomp.R
// Upstream  : none
// Downstream: affycompData
//
// Install: BiocManager::install("affycomp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYCOMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affycomp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affycomp:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affycomp:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affycomp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affycomp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affycomp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(affycomp)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(mas5.assessment)
    data(rma.assessment)
    # --- Affycompplot [] ---
    # Key functions: affycompPlot
    affycompPlot(mas5.assessment$MA)
    # --- Figure2 [] ---
    # Key functions: figure2
    affycomp.figure2(mas5.assessment$Dilution)
    # --- Figure3 [] ---
    # Key functions: figure3
    affycomp.figure3(mas5.assessment$Dilution)
    # --- Compfig2 [] ---
    # Key functions: compfig2
    affycomp.compfig2(list(mas5.assessment$Dilution, rma.assessment$Dilution),
                      method.names=c("MAS 5.0","RMA"))
    # --- Compfig3 [] ---
    # Key functions: compfig3
    affycomp.compfig3(list(mas5.assessment$Dilution, rma.assessment$Dilution),
                      method.names=c("MAS 5.0","RMA"))
    # --- Data [] ---
    # Key functions: tableAll
    data(rma.assessment)
    data(mas5.assessment)
    tableAll(rma.assessment, mas5.assessment)
    # --- Affycomptable [] ---
    # Key functions: affycompTable
    affycompTable(rma.assessment, mas5.assessment)
    # --- Data [] ---
    # Key functions: tableAll
    data(rma.sd.assessment)
    data(lw.sd.assessment)
    tableAll(rma.sd.assessment, lw.sd.assessment)
    # --- Affycompplot [] ---
    # Key functions: affycompPlot
    affycompPlot(lw.sd.assessment, rma.sd.assessment)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affycomp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affycomp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affycomp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFYCOMP:", paste0("    affycomp: ", packageVersion("affycomp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affycomp_results.csv
    touch ${prefix}_affycomp_output.rds
    echo "BIOC_AFFYCOMP:" > versions.yml
    echo "    affycomp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFYCOMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFYCOMP(ch_input)

    emit:
    results  = BIOC_AFFYCOMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFYCOMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFYCOMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFYCOMP.out.versions  // channel: path(versions.yml)
}
