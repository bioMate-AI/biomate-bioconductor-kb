#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MAGeCKFlute
// CRISPR (clustered regularly interspaced short palindrome repeats) coupled with nuclease Cas9 (CRISPR
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MAGeCKFlute/inst/doc/MAGeCKFlute.R
// Upstream  : clusterProfiler, enrichplot, ggplot2
// Downstream: none
//
// Install: BiocManager::install("MAGeCKFlute")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAGECKFLUTE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mageckflute"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mageckflute:2.9.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mageckflute:2.9.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mageckflute_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mageckflute_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mageckflute_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BarView)
    library(ConsistencyView)
    library(DensityView)
    library(EnrichedView)
    library(FluteMLE)
    library(FluteRRA)
    library(HeatmapView)
    library(MAView)
    library(MapRatesView)
    library(RankView)
    library(jsonlite)

    # --- FluteRRA analysis [] ---
    # Key functions: FluteRRA, FluteMLE, BarView, MapRatesView, RankView, EnrichedView, HeatmapView, DensityView
    gdata_cc$Entrez = TransGeneID(gdata_cc$Gene, "symbol", "entrez", organism = "mmu")
    genedata = gdata_cc[, c("Entrez", "Control","Treatment")]
    arrangePathview(genedata, pathways = "mmu04630", organism = "mmu", sub = NULL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mageckflute_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mageckflute_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mageckflute_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAGECKFLUTE:", paste0("    mageckflute: ", packageVersion("MAGeCKFlute"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mageckflute_results.csv
    touch ${prefix}_mageckflute_output.rds
    echo "BIOC_MAGECKFLUTE:" > versions.yml
    echo "    mageckflute: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAGECKFLUTE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAGECKFLUTE(ch_input)

    emit:
    results  = BIOC_MAGECKFLUTE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAGECKFLUTE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAGECKFLUTE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAGECKFLUTE.out.versions  // channel: path(versions.yml)
}
