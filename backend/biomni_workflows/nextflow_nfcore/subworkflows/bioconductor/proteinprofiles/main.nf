#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: proteinProfiles
// Significance assessment for distance measures of time-course protein profiles
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/proteinProfiles/inst/doc/proteinProfiles.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("proteinProfiles")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTEINPROFILES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proteinprofiles"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proteinprofiles:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-proteinprofiles:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proteinprofiles_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proteinprofiles_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proteinprofiles_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(proteinProfiles)
    library(jsonlite)

    # --- Install Package [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("proteinProfiles")
    # --- Remove Na [] ---
    # Key functions: filterFeatures
    ratios_filtered <- filterFeatures(ratios, 0.3, verbose=TRUE)
    # --- Grep Anno Protein Name [] ---
    # Key functions: grepAnnotation
    names(annotation)
    index_28S <- grepAnnotation(annotation, pattern="^28S", column="Protein.Name")
    index_28S
    # --- Grep Anno Ribosome Kegg [] ---
    # Key functions: grepAnnotation
    index_ribosome <- grepAnnotation(annotation, "Ribosome", "KEGG")
    index_ribosome
    # --- Profile 1 [] ---
    # Key functions: profileDistance, plotProfileDistance
    z1 <- profileDistance(ratios, index_28S)
    z1$d0
    z1$p.value
    plotProfileDistance(z1)
    # --- Profile 2 [] ---
    # Key functions: profileDistance, plotProfileDistance
    z2 <- profileDistance(ratios, index_ribosome, nSample=2000)
    plotProfileDistance(z2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proteinprofiles_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proteinprofiles_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proteinprofiles_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROTEINPROFILES:", paste0("    proteinprofiles: ", packageVersion("proteinProfiles"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteinprofiles_results.csv
    touch ${prefix}_proteinprofiles_output.rds
    echo "BIOC_PROTEINPROFILES:" > versions.yml
    echo "    proteinprofiles: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROTEINPROFILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROTEINPROFILES(ch_input)

    emit:
    results  = BIOC_PROTEINPROFILES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROTEINPROFILES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROTEINPROFILES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROTEINPROFILES.out.versions  // channel: path(versions.yml)
}
