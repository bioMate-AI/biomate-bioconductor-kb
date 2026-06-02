#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqPattern
// Visualising oligonucleotide patterns and sequence motifs occurrences across a large set of sequences
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqPattern/inst/doc/seqPattern.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seqPattern")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQPATTERN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqpattern"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqpattern:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqpattern:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqpattern_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqpattern_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqpattern_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(zebrafishPromoters)
    zebrafishPromoters
    head(zebrafishPromoters@elementMetadata)
    # --- Granges [] ---
    # Key functions: GRanges, IRanges, seqlengths, promoters, getSeq
    # create GRanges of dominant TSS position with associated metadata
    zebrafishPromotersTSS <- GRanges(seqnames = zebrafishPromoters24h$chr,
                ranges = IRanges(start = zebrafishPromoters24h$dominantTSS,
                end = zebrafishPromoters24h$dominantTSS),
                strand = zebrafishPromoters24h$strand,
    # --- Plotpatterndensitymap [] ---
    # Key functions: plotPatternDensityMap
    ## plotPatternDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq,
    ##             patterns = c("AA", "TA", "CG", "GC"),
    ##             seqOrder = order(zebrafishPromotersTSSflank$interquantileWidth),
    ##             flankUp = 400, flankDown = 800, color = "blue")
    # --- Promoters [] ---
    # Key functions: promoters, getSeq
    # get regions flanking dominant TSS - 200bp upstream and downstream
    zebrafishPromotersTSSflank <- promoters(zebrafishPromotersTSS, upstream = 200,
                                            downstream = 200)
    # obtain genomic sequence of the flanking regions
    zebrafishPromotersTSSflankSeq <- getSeq(Drerio, zebrafishPromotersTSSflank)
    # --- Plotpatterndensitymap [] ---
    # Key functions: plotPatternDensityMap
    ## # plot density of TATA-box consensus sequence in pink
    ## plotPatternDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq,
    ##             patterns = c("TATAWAWR", "YWTWTATA"),
    ##             seqOrder = order(zebrafishPromotersTSSflank$interquantileWidth),
    ##             flankUp = 200, flankDown = 200, nBin = c(400, 10000),
    # --- Plotmotifdensitymap [] ---
    # Key functions: plotMotifDensityMap
    ## plotMotifDensityMap(regionsSeq = zebrafishPromotersTSSflankSeq,
    ##             motifPWM = TBPpwm, minScore = "90%",
    ##             seqOrder = order(zebrafishPromotersTSSflank$interquantileWidth),
    ##             flankUp = 200, flankDown = 200, color = "red")
    # --- Plotmotifscanscores [] ---
    # Key functions: plotMotifScanScores
    ## plotMotifScanScores(regionsSeq = zebrafishPromotersTSSflankSeq,
    ##             motifPWM = TBPpwm,
    ##             seqOrder = order(zebrafishPromotersTSSflank$interquantileWidth),
    ##             flankUp = 200, flankDown = 200)
    # --- Plotmotifoccurrenceaverage [] ---
    # Key functions: plotMotifOccurrenceAverage
    ## # make index of sharp and broad promoters
    ## sIdx <- zebrafishPromotersTSSflank$interquantileWidth <= 9
    ## bIdx <- zebrafishPromotersTSSflank$interquantileWidth > 9
    ## # plot average motif occurrence profile for sharp promoters
    ## plotMotifOccurrenceAverage(regionsSeq = zebrafishPromotersTSSflankSeq[sIdx],
    # --- Motifscanhits [] ---
    # Key functions: motifScanHits
    motifOccurrence <- motifScanHits(regionsSeq =
                zebrafishPromotersTSSflankSeq[1:50],
                motifPWM = TBPpwm, minScore = "90%", seqOrder =
                order(zebrafishPromotersTSSflank$interquantileWidth[1:50]))
    head(motifOccurrence)
    # --- Motifscanscores [] ---
    # Key functions: motifScanScores
    scanScores <- motifScanScores(regionsSeq = zebrafishPromotersTSSflankSeq[1:50],
                motifPWM = TBPpwm, seqOrder =
                order(zebrafishPromotersTSSflank$interquantileWidth[1:50]))
    dim(scanScores)
    scanScores[1:6,1:6]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqpattern_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqpattern_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqpattern_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQPATTERN:", paste0("    seqpattern: ", packageVersion("seqPattern"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqpattern_results.csv
    touch ${prefix}_seqpattern_output.rds
    echo "BIOC_SEQPATTERN:" > versions.yml
    echo "    seqpattern: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQPATTERN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQPATTERN(ch_input)

    emit:
    results  = BIOC_SEQPATTERN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQPATTERN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQPATTERN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQPATTERN.out.versions  // channel: path(versions.yml)
}
