#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: yarn
// Expedite large RNA-Seq analyses using a combination of previously developed tools. YARN is meant to 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/yarn/inst/doc/yarn.R
// Upstream  : RColorBrewer
// Downstream: netZooR
//
// Install: BiocManager::install("yarn")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_YARN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-yarn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-yarn:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-yarn:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_yarn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_yarn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_yarn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(yarn)
    library(jsonlite)

    # --- check Mis Annotation [] ---
    # Key functions: checkMisAnnotation
    checkMisAnnotation(skin,"GENDER",controlGenes="Y",legendPosition="topleft")
    # --- check Tissues To Merge [] ---
    # Key functions: checkTissuesToMerge
    checkTissuesToMerge(skin,"SMTS","SMTSD")
    # --- plot Density [] ---
    # Key functions: plotDensity, plotHeatmap
    plotDensity(skin_filtered,"SMTSD",main=expression('log'[2]*' raw expression'))
    skin_filtered = normalizeTissueAware(skin_filtered,"SMTSD")
    plotDensity(skin_filtered,"SMTSD",normalized=TRUE,main="Normalized")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_yarn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_yarn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_yarn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_YARN:", paste0("    yarn: ", packageVersion("yarn"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_yarn_results.csv
    touch ${prefix}_yarn_output.rds
    echo "BIOC_YARN:" > versions.yml
    echo "    yarn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_YARN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_YARN(ch_input)

    emit:
    results  = BIOC_YARN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_YARN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_YARN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_YARN.out.versions  // channel: path(versions.yml)
}
