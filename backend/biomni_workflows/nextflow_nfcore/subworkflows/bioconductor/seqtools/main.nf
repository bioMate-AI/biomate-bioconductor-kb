#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqTools
// Analyze read length, phred scores and alphabet frequency and DNA k-mers on uncompressed and compress
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqTools/inst/doc/seqTools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seqTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqtools:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqtools:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seqTools)
    library(jsonlite)

    # --- Head [] ---
    # Key functions: phredTable
    library(seqTools)
    head(phredTable())
    # --- Computation [] ---
    # Key functions: path, fastqq
    basedir <- system.file("extdata", package="seqTools")
    filenames <- file.path(basedir, c("g4_l101_n100.fq.gz", "g5_l101_n100.fq.gz"))
    fq <- fastqq(filenames, k=6, probeLabel=c("g4", "g5"))
    # --- Meltdownk [] ---
    # Key functions: meltDownK, kmerCount
    fqm <- meltDownK(fq, newK=2)
    kmerCount(fqm)[, 1]
    # --- Computation [] ---
    # Key functions: path, fastqq
    files1 <- file.path(basedir, c("sfq1_ctrl.fq.gz", "sfq2_ctrl.fq.gz"))
    files2 <- file.path(basedir, c("sfq1_cont.fq.gz", "sfq2_cont.fq.gz"))
    fq1 <- fastqq(files1, k=3, probeLabel=c("ctrl1","ctrl2"))
    fq2 <- fastqq(files2 , k=3, probeLabel=c("cont1", "cont2"))
    # --- Mergefastqq [] ---
    # Key functions: mergeFastqq
    mrg <- mergeFastqq(fq1, fq2)
    mrg
    # --- Plotnuccount [] ---
    # Key functions: plotNucCount
    plotNucCount(fq, c(2, 3))
    # --- Plotphredquant [] ---
    # Key functions: plotPhredQuant
    plotPhredQuant(fq, 1, "Phred quantiles for 1st file")
    # --- Plotmergedphredquant [] ---
    # Key functions: plotMergedPhredQuant
    plotMergedPhredQuant(fq, main = "Phred quantiles for all files")
    # --- Phreddist [] ---
    # Key functions: phredDist
    phred<-phredDist(fq, 1)
    phred<-phredDist(fq)
    head(phred)
    # --- Kmerindex [] ---
    # Key functions: kMerIndex
    kMerIndex(c("CCC", "GGG"))
    # --- Plotkmercount [] ---
    # Key functions: plotKmerCount
    plotKmerCount(fq, 1)
    # --- Cbdistmatrix [] ---
    # Key functions: cbDistMatrix
    mtx <- cbDistMatrix(mrg)
    mtx
    # --- Hclust [] ---
    # Key functions: hclust, dist, dendrogram
    hc <- hclust(as.dist(mtx))
    hcd <- as.dendrogram(hc, lty=2, lwd=2)
    op <- par(mar = c(3, 1, 1, 5))
    plot(hcd, horiz=TRUE, las=1, edgePar=list(lwd=2, lty=2, col="blue"))
    par(op)
    # --- char2ascii [] ---
    # Key functions: char2ascii, ascii2char
    char2ascii("a")
    ascii2char(97:99)
    # --- Phredtable [] ---
    # Key functions: phredTable
    ## phredTable()
    ## phredTable(20:30)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQTOOLS:", paste0("    seqtools: ", packageVersion("seqTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqtools_results.csv
    touch ${prefix}_seqtools_output.rds
    echo "BIOC_SEQTOOLS:" > versions.yml
    echo "    seqtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQTOOLS(ch_input)

    emit:
    results  = BIOC_SEQTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQTOOLS.out.versions  // channel: path(versions.yml)
}
