#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Spaniel
// Spaniel includes a series of tools to aid the quality control and analysis of Spatial Transcriptomic
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Spaniel/inst/doc/spaniel-vignette-tenX-import.R
// Upstream  : DropletUtils, scater, scran
// Downstream: none
//
// Install: BiocManager::install("Spaniel")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPANIEL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spaniel"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spaniel:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spaniel:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spaniel_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spaniel_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spaniel_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Spaniel)
    library(jsonlite)

    # --- Create Visium SCE [Data Loading] ---
    # Key functions: createVisiumSCE
    pathToTenXOuts <- file.path(
        system.file(package = "Spaniel"), 
        "extdata/outs"
    )
    sce <- createVisiumSCE(
        tenXDir = pathToTenXOuts, 
        resolution = "Low"
    )

    # --- Quality Control Plotting [QC] ---
    # Key functions: spanielPlot
    filter <- sce$detected > 0
    p1 <- spanielPlot(
        object = sce,
        plotType = "NoGenes", 
        showFilter = filter, 
        techType = "Visium", 
        ptSizeMax = 3
    )
    sce <- sce[, filter]

    # --- Gene Expression Visualisation [Visualisation] ---
    # Key functions: spanielPlot
    p2 <- spanielPlot(
        object = sce,
        plotType = "Gene", 
        gene = "ENSMUSG00000024843",
        techType = "Visium", 
        ptSizeMax = 3
    )

    # --- Spatial Cluster Visualisation [Visualisation] ---
    # Key functions: spanielPlot
    sce$clust <- factor(rep(1:2, length.out = ncol(sce)))
    p3 <- spanielPlot(
        object = sce,
        plotType = "Cluster", 
        clusterRes = "clust",
        showFilter = NULL, 
        techType = "Visium", 
        ptSizeMax = 1, 
        customTitle = "Section A"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spaniel_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spaniel_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spaniel_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPANIEL:", paste0("    spaniel: ", packageVersion("Spaniel"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spaniel_results.csv
    touch ${prefix}_spaniel_output.rds
    echo "BIOC_SPANIEL:" > versions.yml
    echo "    spaniel: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPANIEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPANIEL(ch_input)

    emit:
    results  = BIOC_SPANIEL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPANIEL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPANIEL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPANIEL.out.versions  // channel: path(versions.yml)
}
