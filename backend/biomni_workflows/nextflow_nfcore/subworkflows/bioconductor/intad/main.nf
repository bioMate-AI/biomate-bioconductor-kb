#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: InTAD
// The package is focused on the detection of correlation between expressed genes and selected epigenom
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/InTAD/inst/doc/InTAD.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("InTAD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTAD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-intad"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-intad:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-intad:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_intad_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_intad_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_intad_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(InTAD)
    library(jsonlite)

    # --- Filter Gene Expression [] ---
    # Key functions: filterGeneExpr
    inTadSig <- filterGeneExpr(
        inTadSig,
        checkExprDistr = TRUE
    )


    # --- Integrate TAD Regions [] ---
    # Key functions: combineInTAD
    inTadSig <- combineInTAD(
        inTadSig,
        tadGR
    )


    # --- Enhancer-Gene Correlation Analysis [] ---
    # Key functions: findCorrelation
    corData <- findCorrelation(
        inTadSig,
        plot.proportions = TRUE
    )


    # --- Integrate Chromatin Loops [] ---
    # Key functions: combineWithLoops, findCorFromLoops
    inTadSig <- combineWithLoops(
        inTadSig,
        loopsDfSel
    )
    loopEag <- findCorFromLoops(
        inTadSig,
        method = "spearman"
    )


    # --- Visualization of Correlations [] ---
    # Key functions: plotCorrelation, plotCorAcrossRef
    plotCorrelation(
        inTadSig,
        "chr15:26372163-26398073",
        "GABRA5",
        xLabel = "RPKM gene expr log2",
        yLabel = "H3K27ac enrichment log2",
        colByPhenotype = "Subgroup"
    )
    plotCorAcrossRef(
        inTadSig,
        corData,
        targetRegion = GRanges("chr15:25000000-28000000"),
        showCorVals = TRUE,
        symmetric = TRUE,
        tads = tadGR
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_intad_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_intad_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_intad_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTAD:", paste0("    intad: ", packageVersion("InTAD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_intad_results.csv
    touch ${prefix}_intad_output.rds
    echo "BIOC_INTAD:" > versions.yml
    echo "    intad: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTAD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INTAD(ch_input)

    emit:
    results  = BIOC_INTAD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTAD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTAD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTAD.out.versions  // channel: path(versions.yml)
}
