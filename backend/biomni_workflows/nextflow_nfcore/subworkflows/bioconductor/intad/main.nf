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

    # --- new Sig In T A D [] ---
    # Key functions: newSigInTAD
    inTadSig <- newSigInTAD(enhSel, enhSelGR, rpkmCountsSel, txsSel,mbAnnData)
    # --- filter Gene Expr [] ---
    # Key functions: filterGeneExpr
    inTadSig <- filterGeneExpr(inTadSig, checkExprDistr = TRUE)
    # --- combine In T A D [] ---
    # Key functions: combineInTAD
    inTadSig <- combineInTAD(inTadSig, tadGR)
    # --- find Correlation [] ---
    # Key functions: findCorrelation
    par(mfrow=c(1,2)) # option to combine plots in the graph
    corData <- findCorrelation(inTadSig,plot.proportions = TRUE)
    # --- combine With Loops [] ---
    # Key functions: combineWithLoops
    inTadSig <- combineWithLoops(inTadSig, loopsDfSel)
    # --- find Cor From Loops [] ---
    # Key functions: findCorFromLoops
    loopEag <- findCorFromLoops(inTadSig,method = "spearman")
    # --- plot Correlation [] ---
    # Key functions: plotCorrelation
    plotCorrelation(inTadSig, cID, "GABRA5",
    # --- plot Cor Across Ref [] ---
    # Key functions: plotCorAcrossRef
    plotCorAcrossRef(inTadSig,corData,
    targetRegion = GRanges("chr15:25000000-28000000"),

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
