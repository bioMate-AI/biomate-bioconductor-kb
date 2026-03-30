#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SingleR
// Performs unbiased cell type recognition from single-cell RNA sequencing data, by leveraging referenc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SingleR/inst/doc/SingleR.R
// Upstream  : BiocStyle, celldex, scRNAseq, scuttle
// Downstream: OSCA.advanced, OSCA.basic, OSCA.multisample, OSCA.workflows, SingleRBook
//
// Install: BiocManager::install("SingleR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGLER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singler"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-singler:2.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-singler:2.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_singler_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singler_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singler_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GrunPancreasData)
    library(HumanPrimaryCellAtlasData)
    library(LaMannoBrainData)
    library(MuraroPancreasData)
    library(SingleR)
    library(jsonlite)

    # --- Humanprimarycellatlasdata [] ---
    # Key functions: HumanPrimaryCellAtlasData
    ---------------------------------------------------------------------
    library(celldex)
    hpca.se <- HumanPrimaryCellAtlasData()
    hpca.se
    # --- Lamannobraindata [] ---
    # Key functions: LaMannoBrainData
    ---------------------------------------------------------------------
    library(scRNAseq)
    hESCs <- LaMannoBrainData('human-es')
    hESCs <- hESCs[,1:100]
    # --- Singler [] ---
    # Key functions: SingleR
    ---------------------------------------------------------------------
    library(SingleR)
    pred.hesc <- SingleR(test = hESCs, ref = hpca.se, assay.type.test=1,
        labels = hpca.se$label.main)
    # --- Muraropancreasdata [] ---
    # Key functions: MuraroPancreasData, na, SingleR, logNormCounts
    ---------------------------------------------------------------------
    library(scRNAseq)
    sceM <- MuraroPancreasData()
    # One should normally do cell-based quality control at this point, but for
    # brevity's sake, we will just remove the unlabelled libraries here.
    # --- Grunpancreasdata [] ---
    # Key functions: GrunPancreasData, colSums, counts, logNormCounts
    ---------------------------------------------------------------------
    sceG <- GrunPancreasData()
    sceG <- sceG[,colSums(counts(sceG)) > 0] # Remove libraries with no counts.
    sceG <- logNormCounts(sceG)
    # --- Singler [] ---
    # Key functions: SingleR
    ---------------------------------------------------------------------
    pred.grun <- SingleR(test=sceG, ref=sceM, labels=sceM$label, de.method="wilcox")
    table(pred.grun$labels)
    # --- Plotscoreheatmap [] ---
    # Key functions: plotScoreHeatmap
    ---------------------------------------------------------------------
    plotScoreHeatmap(pred.grun)
    # --- Plotdeltadistribution [] ---
    # Key functions: plotDeltaDistribution
    ---------------------------------------------------------------------
    plotDeltaDistribution(pred.grun, ncol = 3)
    # --- Summary [] ---
    # Key functions: na
    ---------------------------------------------------------------------
    summary(is.na(pred.grun$pruned.labels))
    # --- Plotmarkerheatmap [] ---
    # Key functions: plotMarkerHeatmap
    ---------------------------------------------------------------------
    plotMarkerHeatmap(pred.grun, sceG, label="beta")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_singler_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_singler_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_singler_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGLER:", paste0("    singler: ", packageVersion("SingleR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singler_results.csv
    touch ${prefix}_singler_output.rds
    echo "BIOC_SINGLER:" > versions.yml
    echo "    singler: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGLER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SINGLER(ch_input)

    emit:
    results  = BIOC_SINGLER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGLER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGLER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGLER.out.versions  // channel: path(versions.yml)
}
