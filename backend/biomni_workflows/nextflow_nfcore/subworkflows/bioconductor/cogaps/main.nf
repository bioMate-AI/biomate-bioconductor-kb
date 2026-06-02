#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CoGAPS
// Coordinated Gene Activity in Pattern Sets (CoGAPS) implements a Bayesian MCMC matrix factorization a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CoGAPS/inst/doc/CoGAPS.R
// Upstream  : Seurat, viridis
// Downstream: none
//
// Install: BiocManager::install("CoGAPS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COGAPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cogaps"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cogaps:3.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cogaps:3.26.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_cogaps_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cogaps_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cogaps_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(CoGAPS)
    library(CogapsParams)
    library(DefaultAssay)
    library(FeaturePlot)
    library(MANOVA)
    library(jsonlite)

    # --- CoGAPS Execution [] ---
    # Key functions: CoGAPS, toCSV
    cogaps_res <- CoGAPS(
        data = modsimdata,
        allParams = params,
        outputFrequency = 10000
    )
    toCSV(cogaps_res, "cogaps_output")


    # --- Pattern Marker Identification [] ---
    # Key functions: patternMarkers
    pm_markers <- patternMarkers(cogaps_res)
    sample_facs <- cogaps_res@sampleFactors
    feat_loads <- cogaps_res@featureLoadings


    # --- Gene Set Enrichment Analysis [] ---
    # Key functions: getPatternGeneSet, plotPatternGeneSet
    hallmarks_ora <- getPatternGeneSet(
        cogaps_res,
        gene.sets = hallmark_ls,
        method = "overrepresentation"
    )
    pl_pattern7 <- plotPatternGeneSet(
        patterngeneset = hallmarks_ora,
        whichpattern = 7,
        padj_threshold = 0.05
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cogaps_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cogaps_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cogaps_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COGAPS:", paste0("    cogaps: ", packageVersion("CoGAPS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cogaps_results.csv
    touch ${prefix}_cogaps_output.rds
    echo "BIOC_COGAPS:" > versions.yml
    echo "    cogaps: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COGAPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_COGAPS(ch_input)

    emit:
    results  = BIOC_COGAPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COGAPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COGAPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COGAPS.out.versions  // channel: path(versions.yml)
}
