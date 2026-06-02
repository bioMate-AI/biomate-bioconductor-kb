#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BindingSiteFinder
// Precise knowledge on the binding sites of an RNA-binding protein (RBP) is key to understand (post-) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BindingSiteFinder/inst/doc/vignette.R
// Upstream  : ComplexHeatmap, GenomicAlignments, GenomicRanges, dplyr, forcats
// Downstream: none
//
// Install: BiocManager::install("BindingSiteFinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BINDINGSITEFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bindingsitefinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bindingsitefinder:2.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bindingsitefinder:2.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bindingsitefinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bindingsitefinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bindingsitefinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BindingSiteFinder)
    library(BSFind)
    library(jsonlite)

    # --- Binding Site Discovery [BSFind] ---
    # Key functions: BSFind, getRanges
    bdsOut <- BSFind(
        object = bds,
        anno.genes = gns,
        anno.transcriptRegionList = regions,
        est.subsetChromosome = "chr22",
        veryQuiet = TRUE,
        est.maxBsWidth = 29
    )
    finalRanges <- getRanges(bdsOut)

    # --- Quality Control Diagnostics [QC] ---
    # Key functions: processingStepsFlowChart, pureClipGlobalFilterPlot, estimateBsWidthPlot, duplicatedSitesPlot, mergeCrosslinkDiagnosticsPlot
    processingStepsFlowChart(bdsOut)
    pureClipGlobalFilterPlot(bdsOut)
    estimateBsWidthPlot(bdsOut)
    duplicatedSitesPlot(bdsOut)
    mergeCrosslinkDiagnosticsPlot(bdsOut)

    # --- Reproducibility Analysis [Reproducibility] ---
    # Key functions: reproducibilityFilterPlot, reproducibilitySamplesPlot, reproducibilityScatterPlot, makeBsSummaryPlot
    reproducibilityFilterPlot(bdsOut)
    reproducibilitySamplesPlot(bdsOut)
    reproducibilityScatterPlot(bdsOut)
    makeBsSummaryPlot(bdsOut)

    # --- Genomic Annotation Overlaps [Annotation] ---
    # Key functions: geneOverlapsPlot, targetGeneSpectrumPlot, transcriptRegionOverlapsPlot, transcriptRegionSpectrumPlot
    geneOverlapsPlot(bdsOut)
    targetGeneSpectrumPlot(bdsOut)
    transcriptRegionOverlapsPlot(bdsOut)
    transcriptRegionSpectrumPlot(
        bdsOut,
        normalize = TRUE,
        values = "percentage",
        normalize.factor = "median"
    )

    # --- Binding Site Coverage Visualization [Coverage] ---
    # Key functions: bindingSiteDefinednessPlot, bindingSiteCoveragePlot
    bindingSiteDefinednessPlot(bdsOut, by = "transcript")
    bindingSiteCoveragePlot(
        bdsOut,
        plotIdx = 8,
        flankPos = 100,
        autoscale = TRUE
    )

    # --- Binding Site Size Exploration [Sizing] ---
    # Key functions: makeBindingSites
    bds1 <- makeBindingSites(object = bds, bsSize = 3)
    bds2 <- makeBindingSites(object = bds, bsSize = 9)
    bds3 <- makeBindingSites(object = bds, bsSize = 19)
    bds4 <- makeBindingSites(object = bds, bsSize = 29)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bindingsitefinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bindingsitefinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bindingsitefinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BINDINGSITEFINDER:", paste0("    bindingsitefinder: ", packageVersion("BindingSiteFinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bindingsitefinder_results.csv
    touch ${prefix}_bindingsitefinder_output.rds
    echo "BIOC_BINDINGSITEFINDER:" > versions.yml
    echo "    bindingsitefinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BINDINGSITEFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BINDINGSITEFINDER(ch_input)

    emit:
    results  = BIOC_BINDINGSITEFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BINDINGSITEFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BINDINGSITEFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BINDINGSITEFINDER.out.versions  // channel: path(versions.yml)
}
