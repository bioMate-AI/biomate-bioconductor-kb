#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regioneReloaded
// RegioneReloaded is a package that allows simultaneous analysis of associations between genomic regio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regioneReloaded/inst/doc/regioneReloaded.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("regioneReloaded")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONERELOADED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regionereloaded"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regionereloaded:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regionereloaded:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regionereloaded_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regionereloaded_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regionereloaded_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(regioneReloaded)
    library(jsonlite)

    # --- Crosswise Permutation Testing [] ---
    # Key functions: crosswisePermTest, getParameters
    data("cw_Alien")
    cw_Alien_ReG <- crosswisePermTest(
        Alist = AlienRSList_narrow,
        sampling = FALSE,
        genome = AlienGenome,
        per.chromosome = TRUE,
        ranFUN = "resampleGenome",
        evFUN = "numOverlaps",
        ntimes = 10,
        mc.cores = 1
    )
    params <- getParameters(cw_Alien_ReG)


    # --- Matrix Construction and Clustering [] ---
    # Key functions: makeCrosswiseMatrix, getHClust
    data("cw_Alien")
    cw_Alien_ReG <- makeCrosswiseMatrix(cw_Alien_ReG, pvcut = 1)
    modX <- getHClust(cw_Alien_ReG, hctype = "rows")
    modY <- getHClust(cw_Alien_ReG, hctype = "cols")
    ord <- list(
        X = modX$labels[modX$order],
        Y = modY$labels[modY$order]
    )


    # --- Visualisation [] ---
    # Key functions: plotCrosswiseMatrix
    data("cw_Alien")
    cw_Alien_ReG <- makeCrosswiseMatrix(cw_Alien_ReG, pvcut = 1)
    p_ReG <- plotCrosswiseMatrix(
        cw_Alien_ReG,
        matrix_type = "association"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regionereloaded_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regionereloaded_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regionereloaded_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONERELOADED:", paste0("    regionereloaded: ", packageVersion("regioneReloaded"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regionereloaded_results.csv
    touch ${prefix}_regionereloaded_output.rds
    echo "BIOC_REGIONERELOADED:" > versions.yml
    echo "    regionereloaded: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONERELOADED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGIONERELOADED(ch_input)

    emit:
    results  = BIOC_REGIONERELOADED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONERELOADED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONERELOADED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONERELOADED.out.versions  // channel: path(versions.yml)
}
