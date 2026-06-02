#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: monaLisa
// Useful functions to work with sequence motifs in the analysis of genomics data. These include method
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/monaLisa/inst/doc/selecting_motifs_with_randLassoStabSel.R
// Upstream  : Biostrings, ComplexHeatmap, JASPAR2020, SummarizedExperiment, TFBSTools
// Downstream: none
//
// Install: BiocManager::install("monaLisa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MONALISA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-monalisa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-monalisa:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-monalisa:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_monalisa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_monalisa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_monalisa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HeatmapAnnotation)
    library(RNGkind)
    library(jsonlite)

    # --- get Matrix Set [] ---
    # Key functions: getMatrixSet, toPWM, getSeq, findMotifHits
    get PFMs (vertebrate TFs from Jaspar)
    # --- rand Lasso Stab Sel [] ---
    # Key functions: randLassoStabSel, RNGkind
    randLassoStabSel() is stochastic, so if we run with parallelization
    (`mc.cores` argument), we must select a random number generator that can
    RNGkind("L'Ecuyer-CMRG")
    # --- plot Stability Paths [] ---
    # Key functions: plotStabilityPaths
    plotStabilityPaths(se)
    # --- plot Selection Prob [] ---
    # Key functions: plotSelectionProb
    plotSelectionProb(se, directional = TRUE)
    # --- TFBScor selected [] ---
    # Key functions: rowAnnotation, HeatmapAnnotation
    sel <- colnames(se)[se$selected]
    excl <- colnames(se_sub) %in% c("oeCpG", "fracGC")
    TFBSmatrixCorSel <- cor(TFBSmatrix[, colnames(se_sub)], method = "pearson")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_monalisa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_monalisa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_monalisa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MONALISA:", paste0("    monalisa: ", packageVersion("monaLisa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_monalisa_results.csv
    touch ${prefix}_monalisa_output.rds
    echo "BIOC_MONALISA:" > versions.yml
    echo "    monalisa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MONALISA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MONALISA(ch_input)

    emit:
    results  = BIOC_MONALISA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MONALISA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MONALISA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MONALISA.out.versions  // channel: path(versions.yml)
}
