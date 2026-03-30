#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPseeker
// This package implements functions to retrieve the nearest genes around the peak, annotate genomic re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPseeker/inst/doc/ChIPseeker.html
// Upstream  : GenomicFeatures, GenomicRanges, ReactomePA, clusterProfiler, ggplot2
// Downstream: none
//
// Install: BiocManager::install("ChIPseeker")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSEEKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipseeker"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipseeker:1.42.1--r44_0' :
        'quay.io/biocontainers/bioconductor-chipseeker:1.42.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipseeker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipseeker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipseeker_plots.pdf"),    emit: plots, optional: true
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
    library(Region)
    library(jsonlite)

    # --- ChIP peaks coverage plot [] ---
    # Key functions: covplot, theme
    covplot(peak, weightCol="V5")
    
    covplot(peak, weightCol="V5", chrs=c("chr17", "chr18"), xlim=c(4.5e7, 5e7))
    
    peaks = lapply(files[4:5], readPeakFile)
    covplot(peaks, weightCol = "V5", fill_color = c("red","blue")) +
      theme(legend.position = "inside",
            legend.position.inside = c(0.8,0.2))
    # --- Profile of ChIP peaks binding to TSS regions [] ---
    # Key functions: getPromoters, getTagMatrix, data
    ## promoter <- getPromoters(TxDb=txdb, upstream=3000, downstream=3000)
    ## tagMatrix <- getTagMatrix(peak, windows=promoter)
    ##
    ## to speed up the compilation of this vignettes, we use a precalculated tagMatrix
    data("tagMatrixList")
    tagMatrix <- tagMatrixList[[4]]
    # --- Heatmap of ChIP binding to TSS regions [] ---
    # Key functions: tagHeatmap, peakHeatmap, scale_fill_distiller, rel, transcripts, unlist, fiveUTRsByTranscript, peakHeatmap_multiple_Sets
    tagHeatmap(tagMatrix)
    
    peakHeatmap(files[[4]], TxDb=txdb, upstream=3000, downstream=3000)
    
    peakHeatmap(files[[4]],TxDb = txdb,nbin = 800,upstream=3000, downstream=3000)
    
    peakHeatmap(files[[4]],TxDb = txdb,nbin = 800,upstream=3000, downstream=3000) +
      scale_fill_distiller(palette = "RdYlGn")
    
    peakHeatmap(peak = files[[4]],
                TxDb = txdb,
                upstream = rel(0.2),
    # --- Average Profile of ChIP peaks binding to TSS region [] ---
    # Key functions: plotAvgProf, Region, plotAvgProf2
    plotAvgProf(tagMatrix, xlim=c(-3000, 3000),
                xlab="Genomic Region (5'->3')", ylab = "Read Count Frequency")
    
    plotAvgProf2(files[[4]], TxDb=txdb, upstream=3000, downstream=3000,
                 xlab="Genomic Region (5'->3')", ylab = "Read Count Frequency")
    
    plotAvgProf(tagMatrix, xlim=c(-3000, 3000), conf = 0.95, resample = 1000)
    # --- Binning method for profile of ChIP peaks binding to TSS regions [] ---
    # Key functions: getTagMatrix
    ## The results of binning method and normal method are nearly the same.
    tagMatrix_binning <- getTagMatrix(peak = peak, TxDb = txdb,
                                      upstream = 3000, downstream = 3000,
                                      type = "start_site", by = "gene",
                                      weightCol = "V5", nbin = 800)
    # --- Profile of ChIP peaks binding to body regions [] ---
    # Key functions: peaks, plotPeakProf2, rel, getBioRegion, getTagMatrix, plotPeakProf
    ## Here uses `plotPeakProf2` to do all things in one step.
    ## Gene body regions having lengths smaller than nbin will be filtered
    ## A message will be given to warning users about that.
    ## >> 9 peaks(0.872093%), having lengths smaller than 800bp, are filtered...
    
    ## the ignore_strand is FALSE in default. We put here to emphasize that.
    ## We will not show it again in the below example
    plotPeakProf2(peak = peak, upstream = rel(0.2), downstream = rel(0.2),
                  conf = 0.95, by = "gene", type = "body", nbin = 800,
                  TxDb = txdb, weightCol = "V5",ignore_strand = F)
    
    ## The first method using getBioRegion(), getTagMatrix() and plotPeakProf() to plot in three steps.
    # --- Profile of ChIP peaks binding to TTS regions [] ---
    # Key functions: getTagMatrix, plotPeakProf, annotatePeak, seqlevelsStyle
    TTS_matrix <- getTagMatrix(peak = peak,
                               TxDb = txdb,
                               upstream = 3000,
                               downstream = 3000,
                               type = "end_site",
                               by = "gene",
                               weightCol = "V5")
    
    plotPeakProf(tagMatrix = TTS_matrix, conf = 0.95)
    
    peakAnno <- annotatePeak(files[[4]], tssRegion=c(-3000, 3000),
                             TxDb=txdb, annoDb="org.Hs.eg.db")
    # --- Visualize Genomic Annotation [] ---
    # Key functions: plotAnnoPie, plotAnnoBar, vennpie, upsetplot
    plotAnnoPie(peakAnno)
    
    plotAnnoBar(peakAnno)
    
    vennpie(peakAnno)
    
    upsetplot(peakAnno)
    
    upsetplot(peakAnno, vennpie=TRUE)
    # --- Visualize distribution of TF-binding loci relative to TSS [] ---
    # Key functions: plotDistToTSS, enrichPathway, seq2gene, dotplot
    plotDistToTSS(peakAnno,
                  title="Distribution of transcription factor-binding loci\nrelative to TSS")
    
    library(ReactomePA)
    
    pathway1 <- enrichPathway(as.data.frame(peakAnno)$geneId)
    head(pathway1, 2)
    
    gene <- seq2gene(peak, tssRegion = c(-1000, 1000), flankDistance = 3000, TxDb=txdb)
    pathway2 <- enrichPathway(gene)
    head(pathway2, 2)
    
    # --- Average profiles [] ---
    # Key functions: getPromoters, data, plotAvgProf, plotPeakProf2
    ## promoter <- getPromoters(TxDb=txdb, upstream=3000, downstream=3000)
    ## tagMatrixList <- lapply(files, getTagMatrix, windows=promoter)
    ##
    ## to speed up the compilation of this vigenette, we load a precaculated tagMatrixList
    data("tagMatrixList")
    plotAvgProf(tagMatrixList, xlim=c(-3000, 3000))
    
    plotAvgProf(tagMatrixList, xlim=c(-3000, 3000), conf=0.95,resample=500, facet="row")
    
    ## normal method
    plotPeakProf2(files, upstream = 3000, downstream = 3000, conf = 0.95,
                  by = "gene", type = "start_site", TxDb = txdb,
    # --- Peak heatmaps [] ---
    # Key functions: tagHeatmap
    tagHeatmap(tagMatrixList)
    # --- Profile of several ChIP peak data binding to body region [] ---
    # Key functions: plotPeakProf2, rel
    plotPeakProf2(files, upstream = rel(0.2), downstream = rel(0.2),
                  conf = 0.95, by = "gene", type = "body",
                  TxDb = txdb, facet = "row", nbin = 800)
    # --- ChIP peak annotation comparision [] ---
    # Key functions: plotAnnoBar, plotDistToTSS
    peakAnnoList <- lapply(files, annotatePeak, TxDb=txdb,
                           tssRegion=c(-3000, 3000), verbose=FALSE)
    
    plotAnnoBar(peakAnnoList)
    
    plotDistToTSS(peakAnnoList)
    # --- Functional profiles comparison [] ---
    # Key functions: compareCluster, dotplot
    genes = lapply(peakAnnoList, function(i) as.data.frame(i)$geneId)
    names(genes) = sub("_", "\n", names(genes))
    compKEGG <- compareCluster(geneCluster   = genes,
                             fun           = "enrichKEGG",
                             pvalueCutoff  = 0.05,
                             pAdjustMethod = "BH")
    dotplot(compKEGG, showCategory = 15, title = "KEGG Pathway Enrichment Analysis")
    # --- Overlap of peaks and annotated genes [] ---
    # Key functions: vennplot
    genes= lapply(peakAnnoList, function(i) as.data.frame(i)$geneId)
    vennplot(genes)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipseeker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipseeker_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipseeker_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPSEEKER:", paste0("    chipseeker: ", packageVersion("ChIPseeker"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseeker_results.csv
    touch ${prefix}_chipseeker_output.rds
    echo "BIOC_CHIPSEEKER:" > versions.yml
    echo "    chipseeker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPSEEKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPSEEKER(ch_input)

    emit:
    results  = BIOC_CHIPSEEKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPSEEKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPSEEKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPSEEKER.out.versions  // channel: path(versions.yml)
}
