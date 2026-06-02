#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiSeq
// The BiSeq package provides useful classes and functions to handle and analyze targeted bisulfite seq
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiSeq/inst/doc/BiSeq.R
// Upstream  : none
// Downstream: RRBSdata
//
// Install: BiocManager::install("BiSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BISEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biseq:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biseq:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BSraw)
    library(BSrel)
    library(DataFrame)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- List [] ---
    # Key functions: GRanges, IRanges, DataFrame, BSraw
    metadata <- list(Sequencer = "Instrument", Year = "2013")
    rowRanges <- GRanges(seqnames = "chr1",
                      ranges = IRanges(start = c(1,2,3), end = c(1,2,3)))
    colData <- DataFrame(group = c("cancer", "control"),
                         row.names = c("sample_1", "sample_2"))
    # --- Head [] ---
    # Key functions: rowRanges
    head(rowRanges(rrbs))
    # --- Head [] ---
    # Key functions: totalReads
    head(totalReads(rrbs))
    # --- Head [] ---
    # Key functions: methReads
    head(methReads(rrbs))
    # --- Matrix [] ---
    # Key functions: BSrel
    methLevel <- matrix(c(rep(0.5, 3), rep(1, 3)), ncol = 2)
    BSrel(metadata = metadata,
          rowRanges = rowRanges,
          colData = colData,
          methLevel = methLevel)
    # --- Rawtorel [] ---
    # Key functions: rawToRel
    rrbs.rel <- rawToRel(rrbs)
    rrbs.rel
    # --- Head [] ---
    # Key functions: methLevel
    head(methLevel(rrbs.rel))
    # --- Which [] ---
    # Key functions: seqnames
    rrbs[,"APL2"]
    ind.chr1 <- which(seqnames(rrbs) == "chr1")
    rrbs[ind.chr1,]
    # --- Granges [] ---
    # Key functions: GRanges, IRanges
    region <- GRanges(seqnames="chr1",
                      ranges=IRanges(start = 875200,
                                     end = 875500))
    # --- Findoverlaps [] ---
    # Key functions: findOverlaps, subsetByOverlaps
    findOverlaps(rrbs, region)
    subsetByOverlaps(rrbs, region)
    # --- Combine [] ---
    # Key functions: combine, split, rowRanges, factor, seqnames
    combine(rrbs[1:10,1:2], rrbs[1:1000, 3:10])
    split(rowRanges(rrbs),
          f = as.factor(as.character(seqnames(rrbs))))
    # --- Covboxplots [] ---
    # Key functions: covBoxplots
    covBoxplots(rrbs, col = "cornflowerblue", las = 2)
    # --- Clustersites [] ---
    # Key functions: clusterSites, colData
    rrbs.small <- rrbs[1:1000,]
    rrbs.clust.unlim <- clusterSites(object = rrbs.small,
                                     groups = colData(rrbs)$group,
                                     perc.samples = 4/5,
                                     min.sites = 20,
    # --- Head [] ---
    # Key functions: rowRanges
    head(rowRanges(rrbs.clust.unlim))
    # --- Clustersitestogr [] ---
    # Key functions: clusterSitesToGR
    clusterSitesToGR(rrbs.clust.unlim)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BISEQ:", paste0("    biseq: ", packageVersion("BiSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biseq_results.csv
    touch ${prefix}_biseq_output.rds
    echo "BIOC_BISEQ:" > versions.yml
    echo "    biseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BISEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BISEQ(ch_input)

    emit:
    results  = BIOC_BISEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BISEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BISEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BISEQ.out.versions  // channel: path(versions.yml)
}
