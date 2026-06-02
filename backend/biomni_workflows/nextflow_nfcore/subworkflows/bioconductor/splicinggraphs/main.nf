#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SplicingGraphs
// This package allows the user to create, manipulate, and visualize splicing graphs and their bubbles 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SplicingGraphs/inst/doc/SplicingGraphs.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SplicingGraphs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLICINGGRAPHS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-splicinggraphs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-splicinggraphs:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-splicinggraphs:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_splicinggraphs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_splicinggraphs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_splicinggraphs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CharacterList)
    library(FALSE)
    library(GRanges)
    library(IRanges)
    library(ScanBamParam)
    library(SplicingGraphs)
    library(jsonlite)

    # --- Settings [] ---
    # Key functions: path, env, emptyenv, updateObject
    options(width=90)
    .precomputed_results_path <- "precomputed_results"
    .loadPrecomputed <- function(objname)
    # --- Isactiveseq [] ---
    # Key functions: isActiveSeq
    isActiveSeq(txdb)[1:25]
    # --- Keep Chr14 Only [] ---
    # Key functions: isActiveSeq
    isActiveSeq(txdb)[-match("chr14", names(isActiveSeq(txdb)))] <- FALSE
    names(which(isActiveSeq(txdb)))
    # --- Splicinggraphs Constructor [] ---
    # Key functions: SplicingGraphs
    library(SplicingGraphs)
    sg <- SplicingGraphs(txdb)  # should take between 5 and 10 sec on
                                # a modern laptop
    sg
    # --- Load Sg With Bubbles [] ---
    # Key functions: loadPrecomputed, flag, FALSE, isCircular
    ## We load a precomputed 'sg' that contains all the bubbles in
    ## 'sg@.bubbles_cache'.
    sg_with_bubbles <- .loadPrecomputed("sg_with_bubbles")
    sg@.bubbles_cache <- sg_with_bubbles@.bubbles_cache
    # --- Seqnames Sg [] ---
    # Key functions: seqnames, strand
    seqnames(sg)[1:20]
    strand(sg)[1:20]
    table(strand(sg))
    # --- Elementnrows Sg [] ---
    # Key functions: elementNROWS
    elementNROWS(sg)[1:20]
    # --- Mcols Sg Double Bracket 3183 [] ---
    # Key functions: mcols
    mcols(sg[["3183"]])$txpath
    # --- Txpath Sg 3183 [] ---
    # Key functions: txpath
    txpath(sg[["3183"]])
    # --- Plottranscripts Sg 3183 [] ---
    # Key functions: plotTranscripts
    ## plotTranscripts(sg[["3183"]])
    # --- Plottranscripts Sg 3183 As Pdf [] ---
    # Key functions: plotTranscripts, off
    pdf("3183-transcripts.pdf", width=6, height=3)
    plotTranscripts(sg[["3183"]])
    dev.off()
    # --- Unlist Sg [] ---
    # Key functions: unlist
    ex_by_tx <- unlist(sg)
    head(names(ex_by_tx))
    # --- Single Bracket Subsetting [] ---
    # Key functions: strand
    sg[strand(sg) == "-"]
    sg[1:20]
    tail(sg)  # equivalent to 'sg[tail(seq_along(sg))]'
    sg["3183"]
    # --- Sgedgesbygene Sg [] ---
    # Key functions: sgedgesByGene
    edges_by_gene <- sgedgesByGene(sg)
    # --- Plot Sg 3183 [] ---
    # Key functions: sgraph
    ## plot(sg["3183"])
    ## plot(sgraph(sg["3183"], tx_id.as.edge.label=TRUE))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_splicinggraphs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_splicinggraphs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_splicinggraphs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPLICINGGRAPHS:", paste0("    splicinggraphs: ", packageVersion("SplicingGraphs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splicinggraphs_results.csv
    touch ${prefix}_splicinggraphs_output.rds
    echo "BIOC_SPLICINGGRAPHS:" > versions.yml
    echo "    splicinggraphs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPLICINGGRAPHS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPLICINGGRAPHS(ch_input)

    emit:
    results  = BIOC_SPLICINGGRAPHS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPLICINGGRAPHS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPLICINGGRAPHS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPLICINGGRAPHS.out.versions  // channel: path(versions.yml)
}
