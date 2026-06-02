#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gage
// GAGE is a published method for gene set (enrichment or GSEA) or pathway analysis. GAGE is generally 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gage/inst/doc/RNA-seqWorkflow.R
// Upstream  : DESeq, DESeq2, GenomicAlignments, edgeR, gageData
// Downstream: EGSEA
//
// Install: BiocManager::install("gage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gage:2.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gage:2.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamFileList)
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(DGEList)
    library(DataFrame)
    library(ScanBamParam)
    library(jsonlite)

    # --- Synopsis0 [] ---
    # Key functions: setup, requireNamespace, packages
    ## ##step 0: setup (also need to map the reads outside R)
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install(c("pathview", "gage", "gageData", "GenomicAlignments",
    ##             "TxDb.Hsapiens.UCSC.hg19.knownGene"))
    # --- Synopsis1 [] ---
    # Key functions: exonsBy, files, BamFileList, scanBamFlag, ScanBamParam, summarizeOverlaps, assay
    ## ##step 1: read counts
    ## library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    ## exByGn <- exonsBy(TxDb.Hsapiens.UCSC.hg19.knownGene, "gene")
    ## library(GenomicAlignments)
    ## fls <- list.files("tophat_all/", pattern="bam$", full.names =T)
    # --- Synopsis2 [] ---
    # Key functions: rowSums, colSums
    ## ##step 2: preprocessing
    ## require(gageData) #demo only
    ## data(hnrnp.cnts) #demo only
    ## cnts=hnrnp.cnts
    ## sel.rn=rowSums(cnts) != 0
    # --- Synopsis3 [] ---
    # Key functions: gage
    ## ##step 3: gage
    ## ##joint workflow with DEseq/edgeR/limma/Cufflinks merges around here
    ## library(gage)
    ## ref.idx=5:8
    ## samp.idx=1:4
    # --- Synopsis4 [] ---
    # Key functions: rowMeans, na, pathview
    ## ##step 4: pathview
    ## cnts.d= cnts.norm[, samp.idx]-rowMeans(cnts.norm[, ref.idx])
    ## sel <- cnts.kegg.p$greater[, "q.val"] < 0.1 &
    ##          !is.na(cnts.kegg.p$greater[,"q.val"])
    ## path.ids <- rownames(cnts.kegg.p$greater)[sel]
    # --- Readcount [] ---
    # Key functions: exonsBy, files, BamFileList, scanBamFlag, ScanBamParam, summarizeOverlaps
    ## library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    ## exByGn <- exonsBy(TxDb.Hsapiens.UCSC.hg19.knownGene, "gene")
    ## library(GenomicAlignments)
    ## fls <- list.files("tophat_all/", pattern="bam$", full.names =T)
    ## bamfls <- BamFileList(fls)
    # --- Preprocessing [] ---
    # Key functions: rowSums, colSums
    require(gageData)
    data(hnrnp.cnts)
    cnts=hnrnp.cnts
    dim(cnts)
    sel.rn=rowSums(cnts) != 0
    # --- Gage [] ---
    # Key functions: gage
    library(gage)
    ref.idx=5:8
    samp.idx=1:4
    data(kegg.gs)
    #knockdown and control samples are unpaired
    # --- Pathview [] ---
    # Key functions: rowMeans, pathways, na
    #differential expression: log2 ratio or fold change, uppaired samples
    cnts.d= cnts.norm[, samp.idx]-rowMeans(cnts.norm[, ref.idx])
    #up-regulated pathways (top 3) visualized by pathview
    sel <- cnts.kegg.p$greater[, "q.val"] < 0.1 &
             !is.na(cnts.kegg.p$greater[,"q.val"])
    # --- Goanalysis [] ---
    # Key functions: gage
    library(gageData)
    data(go.sets.hs)
    data(go.subs.hs)
    lapply(go.subs.hs, head)
    #Molecular Function analysis is quicker, hence run as demo
    # --- Goresults [] ---
    # Key functions: geneData
    for (gs in rownames(cnts.mf.p$less)[1:3]) {
        outname = gsub(" |:|/", "_", substr(gs, 12, 100))
        geneData(genes = go.sets.hs[[gs]], exprs = cnts.norm, ref = ref.idx,
            samp = samp.idx, outname = outname, txt = T, heatmap = T,
            limit = 3, scatterplot = T)
    # --- Pergenescore [] ---
    # Key functions: test, rowMeans, gage
    cnts.t= apply(cnts.norm, 1, function(x) t.test(x[samp.idx], x[ref.idx],
                  alternative = "two.sided", paired = F)$statistic)
    cnts.meanfc= rowMeans(cnts.norm[, samp.idx]-cnts.norm[, ref.idx])
    range(cnts.t)
    range(cnts.meanfc)
    # --- Deseq2 [] ---
    # Key functions: DataFrame, factor, DESeqDataSetFromMatrix, DESeq, results
    library(DESeq2)
    grp.idx <- rep(c("knockdown", "control"), each=4)
    coldat=DataFrame(grp=factor(grp.idx))
    dds <- DESeqDataSetFromMatrix(cnts, colData=coldat, design = ~ grp)
    dds <- DESeq(dds)
    # --- Deseq2 [] ---
    # Key functions: gage, na
    require(gage)
    data(kegg.gs)
    fc.kegg.p <- gage(exp.fc, gsets = kegg.gs, ref = NULL, samp = NULL)
    sel <- fc.kegg.p$greater[, "q.val"] < 0.1 &
            !is.na(fc.kegg.p$greater[, "q.val"])
    # --- Deseq [] ---
    # Key functions: newCountDataSet, estimateSizeFactors, estimateDispersions, time, nbinomTest
    ## library(DESeq)
    ## grp.idx <- rep(c("knockdown", "control"), each=4)
    ## cds <- newCountDataSet(cnts, grp.idx)
    ## cds = estimateSizeFactors(cds)
    ## cds = estimateDispersions(cds)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GAGE:", paste0("    gage: ", packageVersion("gage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gage_results.csv
    touch ${prefix}_gage_output.rds
    echo "BIOC_GAGE:" > versions.yml
    echo "    gage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GAGE(ch_input)

    emit:
    results  = BIOC_GAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GAGE.out.versions  // channel: path(versions.yml)
}
