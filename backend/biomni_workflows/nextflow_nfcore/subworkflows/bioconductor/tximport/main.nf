#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tximport
// Imports transcript-level abundance, estimated counts and transcript lengths, and summarizes into mat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tximport/inst/doc/tximport.R
// Upstream  : DESeq2, edgeR, knitr, limma, readr
// Downstream: none
//
// Install: BiocManager::install("tximport")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TXIMPORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tximport"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tximport:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tximport:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tximport_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tximport_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tximport_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSetFromTximport)
    library(DGEList)
    library(jsonlite)

    # --- Table [] ---
    # Key functions: path, all
    ---------------------------------------------------------------------
    samples <- read.table(file.path(dir,"samples.txt"), header=TRUE)
    samples
    files <- file.path(dir, "salmon", samples$run, "quant.sf.gz")
    names(files) <- paste0("sample",1:6)
    # --- Keys [] ---
    # Key functions: keys, select
    ---------------------------------------------------------------------
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    k <- keys(txdb, keytype="TXNAME")
    tx2gene <- select(txdb, k, "GENEID", "TXNAME")
    # --- Read Csv [] ---
    # Key functions: read_csv, path
    ---------------------------------------------------------------------
    library(readr)
    tx2gene <- read_csv(file.path(dir, "tx2gene.gencode.v27.csv"))
    head(tx2gene)
    # --- Tximport [] ---
    # Key functions: tximport
    ---------------------------------------------------------------------
    library(tximport)
    txi <- tximport(files, type="salmon", tx2gene=tx2gene)
    names(txi)
    head(txi$counts)
    # --- Summarizetogene [] ---
    # Key functions: summarizeToGene, equal
    ---------------------------------------------------------------------
    txi.sum <- summarizeToGene(txi.tx, tx2gene)
    all.equal(txi$counts, txi.sum$counts)
    # --- Read Csv [] ---
    # Key functions: read_csv, path, tximport
    ---------------------------------------------------------------------
    tx2knownGene <- read_csv(file.path(dir, "tx2gene.csv"))
    files <- file.path(dir,"sailfish", samples$run, "quant.sf")
    names(files) <- paste0("sample",1:6)
    txi.sailfish <- tximport(files, type="sailfish", tx2gene=tx2knownGene)
    # --- Frame [] ---
    # Key functions: frame, factor
    ---------------------------------------------------------------------
    sampleTable <- data.frame(condition=factor(rep(c("A","B"),each=3)))
    rownames(sampleTable) <- colnames(txi$counts)
    # --- Deseqdatasetfromtximport [] ---
    # Key functions: DESeqDataSetFromTximport, DESeq
    ---------------------------------------------------------------------
    dds <- DESeqDataSetFromTximport(txi, sampleTable, ~ condition)
    # dds is now ready for DESeq()
    # see DESeq2 vignette
    # --- Exp [] ---
    # Key functions: rowMeans, calcNormFactors, colSums, sweep, DGEList
    ---------------------------------------------------------------------
    cts <- txi$counts
    normMat <- txi$length
    # Obtaining per-observation scaling factors for length,
    # adjusted to avoid changing the magnitude of the counts.
    # --- Cpm [] ---
    # Key functions: cpm
    ---------------------------------------------------------------------
    cpms <- edgeR::cpm(y, offset=y$offset, log=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tximport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tximport_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tximport_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TXIMPORT:", paste0("    tximport: ", packageVersion("tximport"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tximport_results.csv
    touch ${prefix}_tximport_output.rds
    echo "BIOC_TXIMPORT:" > versions.yml
    echo "    tximport: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TXIMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TXIMPORT(ch_input)

    emit:
    results  = BIOC_TXIMPORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TXIMPORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TXIMPORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TXIMPORT.out.versions  // channel: path(versions.yml)
}
