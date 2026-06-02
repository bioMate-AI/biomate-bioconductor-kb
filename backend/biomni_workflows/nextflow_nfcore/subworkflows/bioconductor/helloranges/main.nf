#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HelloRanges
// Translates bedtools command-line invocations to R code calling functions from the Bioconductor *Rang
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HelloRanges/inst/doc/tutorial.R
// Upstream  : HelloRangesData, parallel
// Downstream: none
//
// Install: BiocManager::install("HelloRanges")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HELLORANGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-helloranges"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-helloranges:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-helloranges:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_helloranges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_helloranges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_helloranges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(R_bedtools_intersect)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: import, time, pintersect, findOverlapPairs, unname, coverage
    genome <- import("hg19.genome")
    exons <- import("exons.bed", genome=genome)
    gwas <- import("gwas.bed", genome=genome)
    hesc.chromHmm <- import("hesc.chromHmm.bed", genome=genome)
    # --- Quality control and filtering [] ---
    # Key functions: bedtools_complement, setdiff, seqinfo, unstrand
    bedtools_complement("-i exons.bed -g hg19.genome")
    ## or without HelloRanges:
    setdiff(as(seqinfo(exons), "GRanges"), unstrand(exons))
    # --- Read alignment and quantification [] ---
    # Key functions: bedtools_makewindows, unlist, eval, R_bedtools_intersect, countOverlaps, tileGenome, seqinfo
    code <- bedtools_makewindows("-g hg19.genome -w 500000")
    code
    windows <- unlist(eval(code))
    R_bedtools_intersect(windows, exons, c=TRUE)
    ## or
    # --- Bedtools intersect analysis [] ---
    # Key functions: bedtools_intersect, eval, mcols, browserSession, genome, export, bedtools_merge, lengths
    code <- bedtools_jaccard(
        paste("-a fHeart-DS16621.hotspot.twopass.fdr0.05.merge.bed",
              "-b fHeart-DS15839.hotspot.twopass.fdr0.05.merge.bed"))
    heart_heart <- eval(code)
    code <- bedtools_jaccard(
    # --- Feature annotation [] ---
    # Key functions: exons
    ## library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    ## exons <- exons(TxDb.Hsapiens.UCSC.hg19.knownGene)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_helloranges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_helloranges_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_helloranges_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HELLORANGES:", paste0("    helloranges: ", packageVersion("HelloRanges"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_helloranges_results.csv
    touch ${prefix}_helloranges_output.rds
    echo "BIOC_HELLORANGES:" > versions.yml
    echo "    helloranges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HELLORANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HELLORANGES(ch_input)

    emit:
    results  = BIOC_HELLORANGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HELLORANGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HELLORANGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HELLORANGES.out.versions  // channel: path(versions.yml)
}
