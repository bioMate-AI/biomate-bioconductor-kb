#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FlowSOM
// FlowSOM offers visualization options for cytometry data, by using Self-Organizing Map clustering and
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FlowSOM/inst/doc/FlowSOM.R
// Upstream  : flowCore
// Downstream: none
//
// Install: BiocManager::install("FlowSOM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWSOM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowsom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowsom:2.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowsom:2.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowsom_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowsom_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowsom_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BuildMST)
    library(BuildSOM)
    library(FlowSOMmary)
    library(GetClusters)
    library(GetMetaclusters)
    library(Plot2DScatters)
    library(PlotLabels)
    library(PlotMarker)
    library(PlotPies)
    library(PlotStars)
    library(jsonlite)

    # --- Packages [] ---
    # Key functions: packages
    # install.packages("BiocManager")
    # BiocManager::install("FlowSOM")
    # --- Plotstars [] ---
    # Key functions: PlotStars
    p <- PlotStars(fSOM, backgroundValues = fSOM$metaclustering)
    print(p, newpage = FALSE)
    # --- Flowsommary [] ---
    # Key functions: FlowSOMmary
    FlowSOMmary(fsom = fSOM,
                plotFile = "FlowSOMmary.pdf")
    # --- Head [] ---
    # Key functions: GetClusters, GetMetaclusters
    head(GetClusters(fSOM))
    head(GetMetaclusters(fSOM))
    # --- Buildsom [] ---
    # Key functions: BuildSOM
    fSOM <- BuildSOM(fSOM, colsToUse = c(9, 12, 14:18))
    str(fSOM$map, max.level = 2)
    # --- Buildmst [] ---
    # Key functions: BuildMST
    fSOM <- BuildMST(fSOM)
    str(fSOM$MST, max.level =  1)
    # --- Plotstars [] ---
    # Key functions: PlotStars
    PlotStars(fSOM, view = "grid")
    # --- Plotpies [] ---
    # Key functions: PlotPies
    PlotPies(fSOM, cellTypes = gatingResult$manual)
    # --- Plotmarker [] ---
    # Key functions: PlotMarker
    p <- PlotMarker(fSOM, "PE-Cy5-A")
    print(p, newpage = FALSE)
    # --- Plot2 D Scatters [] ---
    # Key functions: Plot2DScatters
    plot <- Plot2DScatters(fSOM,
                           channelpairs = list(c("PE-Texas Red-A", "Pacific Blue-A")),
                           clusters = list(c(81, 82, 91, 92, 93)),
                           plotFile = NULL)
    print(plot[[1]])
    # --- Character [] ---
    # Key functions: metaClustering_consensus
    metaClustering <- as.character(metaClustering_consensus(fSOM$map$codes,k = 7))
    # --- Plotpies [] ---
    # Key functions: PlotPies
    PlotPies(fSOM,
             cellTypes=gatingResult$manual,
             backgroundValues = metaClustering)
    # --- Plotlabels [] ---
    # Key functions: PlotLabels
    PlotLabels(fSOM, labels = metaClustering)
    # --- Getmetaclusters [] ---
    # Key functions: GetMetaclusters
    metaClustering_perCell <- GetMetaclusters(fSOM, metaClustering)
    table(metaClustering_perCell)
    # --- Plotstars [] ---
    # Key functions: PlotStars
    p <- PlotStars(fSOM, backgroundValues=cellTypes,
                   backgroundColor=c("#FFFFFF00","#0000FF"))
    print(p, newpage = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowsom_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowsom_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowsom_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWSOM:", paste0("    flowsom: ", packageVersion("FlowSOM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowsom_results.csv
    touch ${prefix}_flowsom_output.rds
    echo "BIOC_FLOWSOM:" > versions.yml
    echo "    flowsom: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWSOM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWSOM(ch_input)

    emit:
    results  = BIOC_FLOWSOM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWSOM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWSOM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWSOM.out.versions  // channel: path(versions.yml)
}
