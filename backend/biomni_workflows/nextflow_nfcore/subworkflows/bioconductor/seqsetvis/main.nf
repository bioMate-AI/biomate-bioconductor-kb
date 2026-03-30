#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqsetvis
// seqsetvis enables the visualization and analysis of sets of genomic sites in next gen sequencing dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqsetvis/inst/doc/seqsetvis_overview.R
// Upstream  : BiocFileCache, ChIPpeakAnno, GenomicRanges, cowplot
// Downstream: none
//
// Install: BiocManager::install("seqsetvis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQSETVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqsetvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqsetvis:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqsetvis:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqsetvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqsetvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqsetvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(GRangesList)
    library(jsonlite)

    # --- load optional libs [] ---
    # Key functions: theme_set
    library(GenomicRanges)
    library(data.table)
    library(cowplot)
    # --- overlap GRangesList [] ---
    # Key functions: GRangesList
    olaps_fromGRangesList = ssvOverlapIntervalSets(
    GenomicRanges::GRangesList(CTCF_in_10a_narrowPeak_grs))
    # --- ssvMakeMembTable numeric [] ---
    # Key functions: ssvMakeMembTable
    my_set_list = list(1:3, 2:3, 3:6)
    ssvMakeMembTable(my_set_list)
    # --- ssvMakeMembTable named numeric [] ---
    # Key functions: ssvMakeMembTable
    names(my_set_list) = c("first", "second", "third")
    ssvMakeMembTable(my_set_list)
    # --- ssvMakeMembTable character [] ---
    # Key functions: ssvMakeMembTable
    my_set_list_char = lapply(my_set_list, function(x)letters[x])
    ssvMakeMembTable(my_set_list_char)
    # --- ssv Feature Bars [] ---
    # Key functions: ssvFeatureBars
    ssvFeatureBars(olaps)
    # --- ssv Feature Pie [] ---
    # Key functions: ssvFeaturePie
    ssvFeaturePie(olaps)
    # --- ssv Feature Venn [] ---
    # Key functions: ssvFeatureVenn
    ssvFeatureVenn(olaps)
    # --- ssv Feature Euler [] ---
    # Key functions: ssvFeatureEuler
    ssvFeatureEuler(olaps)
    # --- ssv Feature Binary Heatmap [] ---
    # Key functions: ssvFeatureBinaryHeatmap
    ssvFeatureBinaryHeatmap(olaps)
    # --- ssv Signal Lineplot [] ---
    # Key functions: ssvSignalLineplot
    bw_gr$facet_label = sub("_", "\n", bw_gr$sample)
    ssvSignalLineplot(bw_data = subset(bw_gr, id %in% 1:12), facet_ = "facet_label")
    # --- lineplot region facet [] ---
    # Key functions: ssvSignalLineplot
    ssvSignalLineplot(bw_data = subset(bw_gr, id %in% 1:4), facet_ = "id")
    # --- lineplot aggregated [] ---
    # Key functions: ssvSignalLineplotAgg
    ssvSignalLineplotAgg(bw_data = bw_gr)
    # --- lineplot aggregated smoothed [] ---
    # Key functions: ssvSignalLineplotAgg
    ssvSignalLineplotAgg(bw_data = bw_gr, spline_n = 10)
    # --- ssv Signal Lineplot Agg [] ---
    # Key functions: ssvSignalLineplotAgg, facet_wrap, labs
    olap_2groups = ssvFactorizeMembTable(ssvMakeMembTable(olap_gr)[, 1:2])
    grouped_gr = GRanges(merge(bw_gr, olap_2groups))
    grouped_gr = subset(grouped_gr, sample %in% c("MCF10A_CTCF", "MCF10AT1_CTCF"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqsetvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqsetvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqsetvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQSETVIS:", paste0("    seqsetvis: ", packageVersion("seqsetvis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqsetvis_results.csv
    touch ${prefix}_seqsetvis_output.rds
    echo "BIOC_SEQSETVIS:" > versions.yml
    echo "    seqsetvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQSETVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQSETVIS(ch_input)

    emit:
    results  = BIOC_SEQSETVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQSETVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQSETVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQSETVIS.out.versions  // channel: path(versions.yml)
}
