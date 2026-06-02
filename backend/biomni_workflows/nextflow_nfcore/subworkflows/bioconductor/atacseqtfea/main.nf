#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ATACseqTFEA
// Assay for Transpose-Accessible Chromatin using sequencing (ATAC-seq) is a technique to assess genome
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ATACseqTFEA/inst/doc/ATACseqTFEA.R
// Upstream  : ATACseqQC, Rsamtools
// Downstream: none
//
// Install: BiocManager::install("ATACseqTFEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ATACSEQTFEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-atacseqtfea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-atacseqtfea:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-atacseqtfea:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_atacseqtfea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_atacseqtfea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_atacseqtfea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ESvolcanoplot)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Preparebindingsites [] ---
    # Key functions: prepareBindingSites, GRanges, IRanges
    ---------------------------------------------------------------------
    # for test run, we use a subset of data within chr1:5000-100000
    # for real data, use the merged peaklist as grange input.
    # Drerio is the short-link of BSgenome.Drerio.UCSC.danRer10
    seqlev <- "chr1"
    # --- Esvolcanoplot [] ---
    # Key functions: ESvolcanoplot, plotES, factorFootprints, getBindingSites, csv
    ---------------------------------------------------------------------
    TF <- "Tal1::Gata1"
    ## volcanoplot
    ESvolcanoplot(TFEAresults=res, TFnameToShow=TF)
    ### plot enrichment score for one TF
    # --- Expandbindingsites [] ---
    # Key functions: expandBindingSites, count5ends
    ---------------------------------------------------------------------
    # prepare the counting region
    exbs <- expandBindingSites(bindingSites=bindingSites,
                               proximal=40,
                               distal=40,
    # --- Colnames [] ---
    # Key functions: eventsFilter
    ---------------------------------------------------------------------
    colnames(counts)
    counts <- eventsFilter(counts, "proximalRegion>0")
    # --- Countsnormalization [] ---
    # Key functions: countsNormalization
    ---------------------------------------------------------------------
    counts <- countsNormalization(counts, proximal=40, distal=40)
    # --- Getweightedbindingscore [] ---
    # Key functions: getWeightedBindingScore
    ---------------------------------------------------------------------
    counts <- getWeightedBindingScore(counts)
    # --- Dotfea [] ---
    # Key functions: doTFEA, plotES
    ---------------------------------------------------------------------
    res <- doTFEA(counts)
    res
    plotES(res, TF=TF, outfolder=NA) ## will show same figure as above one

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_atacseqtfea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_atacseqtfea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_atacseqtfea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ATACSEQTFEA:", paste0("    atacseqtfea: ", packageVersion("ATACseqTFEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_atacseqtfea_results.csv
    touch ${prefix}_atacseqtfea_output.rds
    echo "BIOC_ATACSEQTFEA:" > versions.yml
    echo "    atacseqtfea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ATACSEQTFEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ATACSEQTFEA(ch_input)

    emit:
    results  = BIOC_ATACSEQTFEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ATACSEQTFEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ATACSEQTFEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ATACSEQTFEA.out.versions  // channel: path(versions.yml)
}
