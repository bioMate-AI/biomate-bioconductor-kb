#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tximeta
// Transcript quantification import from Salmon and other quantifiers with automatic attachment of tran
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tximeta/inst/doc/tximeta.R
// Upstream  : BiocFileCache, DESeq2, SummarizedExperiment, devtools, edgeR
// Downstream: rnaseqGene
//
// Install: BiocManager::install("tximeta")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TXIMETA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tximeta"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tximeta:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tximeta:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tximeta_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tximeta_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tximeta_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(DGEList)
    library(jsonlite)

    # --- Tximeta [] ---
    # Key functions: tximeta
    ---------------------------------------------------------------------
    se <- tximeta(coldata)
    # --- Assaynames [] ---
    # Key functions: assayNames
    ---------------------------------------------------------------------
    assayNames(se)
    # --- Rowranges [] ---
    # Key functions: rowRanges
    ---------------------------------------------------------------------
    rowRanges(se)
    # --- Seqinfo [] ---
    # Key functions: seqinfo
    ---------------------------------------------------------------------
    seqinfo(se)
    # --- Retrievedb [] ---
    # Key functions: retrieveDb
    ---------------------------------------------------------------------
    edb <- retrieveDb(se)
    class(edb)
    # --- Addexons [] ---
    # Key functions: addExons, rowRanges
    ---------------------------------------------------------------------
    se.exons <- addExons(se)
    rowRanges(se.exons)[[1]]
    # --- Summarizetogene [] ---
    # Key functions: summarizeToGene, rowRanges
    ---------------------------------------------------------------------
    gse <- summarizeToGene(se)
    rowRanges(gse)
    # --- Addids [] ---
    # Key functions: addIds, mcols
    ---------------------------------------------------------------------
    library(org.Dm.eg.db)
    gse <- addIds(gse, "REFSEQ", gene=TRUE)
    mcols(gse)
    # --- Scaleinfreps [] ---
    # Key functions: scaleInfReps, labelKeep, swish
    ---------------------------------------------------------------------
    library(fishpond)
    y <- se
    # y <- scaleInfReps(y)
    # y <- labelKeep(y)
    # --- Assays [] ---
    # Key functions: assays, rowMeans, calcNormFactors, colSums, DGEList, scaleOffset
    ---------------------------------------------------------------------
    cts <- assays(gse)[["counts"]]
    normMat <- assays(gse)[["length"]]
    normMat <- normMat / exp(rowMeans(log(normMat)))
    o <- log(calcNormFactors(cts/normMat)) + log(colSums(cts/normMat))
    # --- Summarizetogene [] ---
    # Key functions: summarizeToGene, DGEList, assays
    ---------------------------------------------------------------------
    gse <- summarizeToGene(se, countsFromAbundance="lengthScaledTPM")
    library(limma)
    y <- DGEList(assays(gse)[["counts"]])
    # see limma User's Guide for further steps
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    metadata(gse)$countsFromAbundance
    # --- Biocfilecache [] ---
    # Key functions: BiocFileCache
    ---------------------------------------------------------------------
    library(BiocFileCache)
    bfc <- BiocFileCache()
    # --- Tximeta [] ---
    # Key functions: tximeta
    ---------------------------------------------------------------------
    se <- tximeta(coldata)
    # --- Rowranges [] ---
    # Key functions: rowRanges, seqinfo
    ---------------------------------------------------------------------
    rowRanges(se)
    seqinfo(se)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tximeta_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tximeta_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tximeta_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TXIMETA:", paste0("    tximeta: ", packageVersion("tximeta"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tximeta_results.csv
    touch ${prefix}_tximeta_output.rds
    echo "BIOC_TXIMETA:" > versions.yml
    echo "    tximeta: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TXIMETA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TXIMETA(ch_input)

    emit:
    results  = BIOC_TXIMETA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TXIMETA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TXIMETA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TXIMETA.out.versions  // channel: path(versions.yml)
}
