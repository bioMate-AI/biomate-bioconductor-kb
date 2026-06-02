#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bambu
// bambu is a R package for multi-sample transcript discovery and quantification using long read RNA-Se
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bambu/inst/doc/bambu.R
// Upstream  : BiocFileCache, DESeq2, DEXSeq, ExperimentHub, NanoporeRNASeq
// Downstream: none
//
// Install: BiocManager::install("bambu")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAMBU {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bambu"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bambu:3.8.3--r44_0' :
        'quay.io/biocontainers/bioconductor-bambu:3.8.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bambu_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bambu_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bambu_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamFileList)
    library(BiocFileCache)
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(DEXSeq)
    library(DEXSeqDataSet)
    library(ExperimentHub)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: query, ExperimentHub, BamFileList
    ---------------------------------------------------------------------
    library(bambu)
    library(NanoporeRNASeq)
    data("SGNexSamples")
    SGNexSamples
    # --- Query [] ---
    # Key functions: query, ExperimentHub
    ---------------------------------------------------------------------
    # get path to fasta file
    genomeSequenceData <- query(ExperimentHub(), c("NanoporeRNA", "GRCh38","FASTA"))
    genomeSequence <- genomeSequenceData[["EH7260"]]
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("HsChr22BambuAnnotation")
    HsChr22BambuAnnotation
    # --- Coldata [] ---
    # Key functions: colData, factor
    ---------------------------------------------------------------------
    colData(se.multiSample)$condition <- as.factor(SGNexSamples$cellLine)
    # --- Transcripttogeneexpression [] ---
    # Key functions: transcriptToGeneExpression
    ---------------------------------------------------------------------
    seGene.multiSample <- transcriptToGeneExpression(se.multiSample)
    seGene.multiSample
    # --- Biocfilecache [] ---
    # Key functions: BiocFileCache, bfcinfo
    ---------------------------------------------------------------------
    library(BiocFileCache)
    bfc <- BiocFileCache(save.dir, ask = FALSE)
    info <- bfcinfo(bfc)
    # --- Bambu [] ---
    # Key functions: bambu
    ---------------------------------------------------------------------
    info
    # running bambu using the first file
    se <- bambu(reads = info$rpath[1:3], annotations = HsChr22BambuAnnotation, genome = genomeSequence)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    rowData(se[[1]])
    # --- Bambu [] ---
    # Key functions: bambu, metadata
    ---------------------------------------------------------------------
    se <- bambu(reads = bamFiles, annotations = HsChr22BambuAnnotation, genome = genomeSequence, trackReads = TRUE)
    metadata(se)$readToTranscriptMaps[[1]]
    # --- Bambu [] ---
    # Key functions: bambu
    ---------------------------------------------------------------------
    se <- bambu(reads = bamFiles, annotations = HsChr22BambuAnnotation, genome = genomeSequence, opt.discovery = list(min.txScore.singleExon = 0))
    # --- Deseqdatasetfrommatrix [] ---
    # Key functions: DESeqDataSetFromMatrix, assays, colData, DESeq, results
    ---------------------------------------------------------------------
    library(DESeq2)
    dds <- DESeqDataSetFromMatrix(round(assays(seGene.multiSample)$counts),
                                        colData = colData(se.multiSample),
                                        design = ~ condition)
    # --- Dexseqdataset [] ---
    # Key functions: DEXSeqDataSet, assays, frame, colData, rowData, DEXSeq
    ---------------------------------------------------------------------
    library(DEXSeq)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bambu_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bambu_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bambu_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAMBU:", paste0("    bambu: ", packageVersion("bambu"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bambu_results.csv
    touch ${prefix}_bambu_output.rds
    echo "BIOC_BAMBU:" > versions.yml
    echo "    bambu: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAMBU_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BAMBU(ch_input)

    emit:
    results  = BIOC_BAMBU.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAMBU.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAMBU.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAMBU.out.versions  // channel: path(versions.yml)
}
