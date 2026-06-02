#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epigenomix
// A package for the integrative analysis of RNA-seq or microarray based gene transcription and histone
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epigenomix/inst/doc/epigenomix.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("epigenomix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIGENOMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epigenomix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epigenomix:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epigenomix:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epigenomix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epigenomix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epigenomix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExpressionSet)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Gedata [] ---
    # Key functions: pData
    library(epigenomix)
    data(eSet)
    pData(eSet)
    # --- Rnaseqimport [] ---
    # Key functions: data
    data(fpkm)
    head(fpkm[c(-2,-8), ])
    # --- Rnaseqtoeset [] ---
    # Key functions: ExpressionSet, pData, factor, fData
    mat <- log2(as.matrix(fpkm[, c("CEBPA_WT", "CEBPA_KO")]))
    rownames(mat) <- fpkm$tss_id
    eSet.seq <- ExpressionSet(mat)
    pData(eSet.seq)$CEBPA <- factor(c("wt", "ko"))
    fData(eSet.seq)$chr <- fpkm$chr
    # --- Chipdata [] ---
    # Key functions: data
    data(mappedReads)
    names(mappedReads)
    # --- Probetotranscript [] ---
    # Key functions: fData, featureNames
    probeToTrans <- fData(eSet)$transcript
    probeToTrans <- strsplit(probeToTrans, ",")
    names(probeToTrans) <- featureNames(eSet)
    # --- Transcripttotss [] ---
    # Key functions: data
    data(transToTSS)
    head(transToTSS)
    # --- Biomart [] ---
    # Key functions: unlist, useMart, getBM
    ## library("biomaRt")
    ## transcripts <- unique(unlist(probeToTrans))
    ## mart <- useMart("ENSEMBL_MART_ENSEMBL",dataset="mmusculus_gene_ensembl", host="www.ensembl.org")
    ## transToTSS <- getBM(attributes=c("ensembl_transcript_id",
    ##     "chromosome_name", "transcript_start",
    # --- Datamatching [] ---
    # Key functions: matchProbeToPromoter
    promoters <- matchProbeToPromoter(probeToTrans,
        transToTSS, promWidth=6000, mode="union")
    promoters[["10345616"]]
    # --- Makechipseqset [] ---
    # Key functions: summarizeReads, chipVals
    chipSetRaw <- summarizeReads(mappedReads, promoters, summarize="add")
    chipSetRaw
    head(chipVals(chipSetRaw))
    # --- Makechipseqset Rna [] ---
    # Key functions: GRanges, fData, IRanges, featureNames, resize, split, elementMetadata
    promoters.seq <- GRanges(seqnames=fData(eSet.seq)$chr,
                            ranges=IRanges(start=fData(eSet.seq)$tss, width=1),
                            probe=featureNames(eSet.seq))
    promoters.seq <- resize(promoters.seq, width=3000, fix="center")
    promoters.seq <- split(promoters.seq, elementMetadata(promoters.seq)$probe)
    # --- Makechipseqset [] ---
    # Key functions: summarizeReads, chipVals
    chipSetRaw.seq <- summarizeReads(mappedReads, promoters.seq, summarize="add")
    chipSetRaw.seq
    head(chipVals(chipSetRaw.seq))
    # --- Normalizedata [] ---
    # Key functions: normalize
    chipSet <- normalize(chipSetRaw, method="quantile")
    # --- Normalizationplot [] ---
    # Key functions: chipVals
    par(mfrow=c(1,2))
    plot(chipVals(chipSetRaw)[,1], chipVals(chipSetRaw)[,2],
         xlim=c(1,600), ylim=c(1,600), main="Raw")
    plot(chipVals(chipSet)[,1], chipVals(chipSet)[,2],
         xlim=c(1,600), ylim=c(1,600), main="Quantile")
    # --- Integratedata [] ---
    # Key functions: factor, colData, integrateData
    eSet$CEBPA
    colnames(chipSet)
    chipSet$CEBPA <- factor(c("wt", "ko"))
    colData(chipSet)
    intData <- integrateData(eSet, chipSet,
    # --- Mlmixmodel1 [] ---
    # Key functions: mlMixModel
    mlmm = mlMixModel(intData[,"z"],
        normNull=c(2, 3), expNeg=1, expPos=4,
        sdNormNullInit=c(0.5, 1), rateExpNegInit=0.5, rateExpPosInit=0.5,
        pi=rep(1/4, 4))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epigenomix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epigenomix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epigenomix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIGENOMIX:", paste0("    epigenomix: ", packageVersion("epigenomix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epigenomix_results.csv
    touch ${prefix}_epigenomix_output.rds
    echo "BIOC_EPIGENOMIX:" > versions.yml
    echo "    epigenomix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIGENOMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIGENOMIX(ch_input)

    emit:
    results  = BIOC_EPIGENOMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIGENOMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIGENOMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIGENOMIX.out.versions  // channel: path(versions.yml)
}
