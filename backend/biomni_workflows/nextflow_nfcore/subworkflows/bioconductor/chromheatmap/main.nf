#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChromHeatMap
// The ChromHeatMap package can be used to plot genome-wide data (e.g. expression, CGH, SNP) along each
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChromHeatMap/inst/doc/ChromHeatMap.R
// Upstream  : ALL
// Downstream: none
//
// Install: BiocManager::install("ChromHeatMap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHROMHEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chromheatmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chromheatmap:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chromheatmap:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chromheatmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chromheatmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chromheatmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChromHeatMap)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: makeChrStrandData, exprs
    library('ALL')
    data('ALL')
    selSamples <- ALL$mol.biol %in% c('ALL1/AF4', 'E2A/PBX1')
    ALLs <- ALL[, selSamples]
    library('ChromHeatMap')
    # --- Ifelse [] ---
    # Key functions: ifelse, plotChrMap
    groupcol <- ifelse( ALLs$mol.biol == 'ALL1/AF4', 'red', 'green' )
    plotChrMap(chrdata, 19, strands='both', RowSideColors=groupcol)
    # --- Plotchrmap [] ---
    # Key functions: plotChrMap
    plotmap<-plotChrMap(chrdata, 1, cytoband='q23', interval=50000, srtCyto=0, cexCyto=1.2)
    # --- Grabchrmapprobes [] ---
    # Key functions: grabChrMapProbes, unlist, mget
    ## probes <- grabChrMapProbes( plotmap )
    ## genes <- unlist(mget(probes, envir=hgu95av2SYMBOL, ifnotfound=NA))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chromheatmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chromheatmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chromheatmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHROMHEATMAP:", paste0("    chromheatmap: ", packageVersion("ChromHeatMap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromheatmap_results.csv
    touch ${prefix}_chromheatmap_output.rds
    echo "BIOC_CHROMHEATMAP:" > versions.yml
    echo "    chromheatmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHROMHEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHROMHEATMAP(ch_input)

    emit:
    results  = BIOC_CHROMHEATMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHROMHEATMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHROMHEATMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHROMHEATMAP.out.versions  // channel: path(versions.yml)
}
