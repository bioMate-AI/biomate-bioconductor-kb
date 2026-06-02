#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggbio
// The ggbio package extends and specializes the grammar of graphics for biological data. The graphics 
//
// Source : https://raw.githubusercontent.com/tengfei/ggbio/master/vignettes/realvignettes/ggbio.Rnw
// Upstream  : none
// Downstream: CAFE, intansv
//
// Install: BiocManager::install("ggbio")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGBIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggbio"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggbio:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggbio:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggbio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggbio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggbio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(GRangesFilter)
    library(GeneIdFilter)
    library(GeneNameFilter)
    library(IRanges)
    library(Ideogram)
    library(jsonlite)

    # --- ggbio: Genome visualization [] ---
    # Key functions: set
    library(knitr)
    opts_chunk$set(fig.path='./figures/ggbio-',
                   fig.align='center', fig.show='asis',
                   eval = TRUE,
                   fig.width = 4.5,
                   fig.height = 4.5,
                   tidy = FALSE,
                   message = FALSE,
                   warning = FALSE)
    options(replace.assign=TRUE,width=80)
    # --- Add an ideogram track [] ---
    # Key functions: Ideogram, xlim, GRanges, IRanges
    library(ggbio)
    p.ideo <- Ideogram(genome = "hg19")
    p.ideo
    library(GenomicRanges)
    ## special highlights instead of zoomin!
    p.ideo + xlim(GRanges("chr2", IRanges(1e8, 1e8+10000000)))
    # --- Make gene model from {OrganismDb [] ---
    # Key functions: class, data, autoplot, columns
    library(ggbio)
    library(Homo.sapiens)
    class(Homo.sapiens)
    ##
    data(genesymbol, package = "biovizBase")
    wh <- genesymbol[c("BRCA1", "NBR1")]
    wh <- range(wh, ignore.strand = TRUE)
    
    
    p.txdb <- autoplot(Homo.sapiens, which  = wh)
    p.txdb
    
    # --- Make gene model from {TxDb [] ---
    # Key functions: autoplot
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    autoplot(txdb, which = wh)
    # --- Make gene model from {EnsDb [] ---
    # Key functions: autoplot, GeneNameFilter, GRanges, IRanges, GRangesFilter, GeneIdFilter
    library(EnsDb.Hsapiens.v75)
    ensdb <- EnsDb.Hsapiens.v75
    autoplot(ensdb, GeneNameFilter("PHKG2"))
    
    autoplot(ensdb, ~ symbol == "PHKG2", names.expr="gene_name")
    
    ## We specify "*" as strand, thus we query for genes encoded  on both strands
    gr <- GRanges(seqnames = 16, IRanges(30768000, 30770000), strand = "*")
    autoplot(ensdb, GRangesFilter(gr), names.expr = "gene_name")
    
    autoplot(ensdb, GeneIdFilter(c("ENSG00000196118", "ENSG00000156873")))
    # --- Make gene model from {GRangesList [] ---
    # Key functions: crunch, values, split, sample, autoplot, aes, ggplot
    library(biovizBase)
    gr.txdb <- crunch(txdb, which = wh)
    ## change column to 'model'
    colnames(values(gr.txdb))[4] <- "model"
    grl <- split(gr.txdb, gr.txdb$tx_id)
    ## fake some randome names
    names(grl) <- sample(LETTERS, size = length(grl), replace = TRUE)
    grl
    
    autoplot(grl, aes(type = model))
    ggplot() + geom_alignment(grl, type = "model")
    # --- Semantic zoom [] ---
    # Key functions: autoplot, zoom, resize, width
    library(BSgenome.Hsapiens.UCSC.hg19)
    bg <- BSgenome.Hsapiens.UCSC.hg19
    p.bg <- autoplot(bg, which = wh)
    ## no geom
    p.bg
    ## segment
    p.bg + zoom(1/100)
    ## rectangle
    p.bg + zoom(1/1000)
    ## text
    p.bg + zoom(1/2500)
    
    # --- Add an alignment track [] ---
    # Key functions: keepSeqlevels, autoplot, resize, width, aes
    fl.bam <- system.file("extdata", "wg-brca1.sorted.bam", package  = "biovizBase")
    wh <- keepSeqlevels(wh, "chr17")
    autoplot(fl.bam, which = wh)
    
    fl.bam <- system.file("extdata", "wg-brca1.sorted.bam", package  = "biovizBase")
    wh <- keepSeqlevels(wh, "chr17")
    autoplot(fl.bam, which = resize(wh, width = width(wh)/10), geom = "gapped.pair")
    
    library(BSgenome.Hsapiens.UCSC.hg19)
    bg <- BSgenome.Hsapiens.UCSC.hg19
    p.mis <- autoplot(fl.bam, bsgenome = bg, which = wh, stat = "mismatch")
    p.mis
    # --- Add a variants track [] ---
    # Key functions: readVcf, renameSeqlevels, GRanges, IRanges, autoplot, xlim, zoom
    library(VariantAnnotation)
    fl.vcf <- system.file("extdata", "17-1409-CEU-brca1.vcf.bgz", package="biovizBase")
    vcf <- readVcf(fl.vcf, "hg19")
    vr <- as(vcf[, 1:3], "VRanges")
    vr <- renameSeqlevels(vr, value = c("17" = "chr17"))
    ## small region contains data
    gr17 <- GRanges("chr17", IRanges(41234400, 41234530))
    p.vr <- autoplot(vr, which = wh)
    ## none geom
    p.vr
    ## rect geom
    p.vr + xlim(gr17)
    # --- Building your tracks [] ---
    # Key functions: tracks, xlim, GRanges, IRanges, theme_tracks_sunset, zoom, nextView, prevView
    ## tks <- tracks(p.ideo, mismatch = p.mis, dbSNP = p.vr, ref = p.bs, gene = p.txdb)
    ## tks <- tracks(fl.bam, fl.vcf, bs, Homo.sapiens) ## default ideo = FALSE, turned on
    ## tks <- tracks(fl.bam, fl.vcf, bs, Homo.sapiens, ideo = TRUE)
    ## tks + xlim(gr17)
    gr17 <- GRanges("chr17", IRanges(41234415, 41234569))
    tks <- tracks(p.ideo, mismatch = p.mis, dbSNP = p.vr, ref = p.bg, gene = p.txdb,
                  heights = c(2, 3, 3, 1, 4)) + xlim(gr17) + theme_tracks_sunset()
    tks
    
    ## zoom in
    tks + zoom()
    
    # --- Buidling circular plot layer by layer [] ---
    # Key functions: data, autoplot, ggbio, circle, aes, values, scale_size
    data("CRC", package  = "biovizBase")
    
    head(hg19sub)
    autoplot(hg19sub, layout = "circle", fill  = "gray70")
    
    p <- ggbio() + circle(hg19sub, geom = "ideo", fill = "gray70") +
        circle(hg19sub, geom = "scale", size = 2) +
      circle(hg19sub, geom = "text", aes(label = seqnames), vjust = 0, size = 3)
    p
    
    p <- ggbio(trackWidth = 10, buffer = 0, radius = 10) + circle(hg19sub, geom = "ideo", fill = "gray70") +
        circle(hg19sub, geom = "scale", size = 2) +
    # --- Complex arragnment of plots [] ---
    # Key functions: split, values, brewer.pal
    grl <- split(crc.gr, values(crc.gr)$individual)
    ## need "unit", load grid
    library(grid)
    # --- Introduction [] ---
    # Key functions: transformDfToGr, keepSeqlevels, seqlengths, data
    snp <- read.table(system.file("extdata", "plink.assoc.sub.txt", package = "biovizBase"),
                      header = TRUE)
    require(biovizBase)
    gr.snp <- transformDfToGr(snp, seqnames = "CHR", start = "BP", width = 1)
    head(gr.snp)
    ## change the seqname order
    require(GenomicRanges)
    gr.snp <- keepSeqlevels(gr.snp, as.character(1:22))
    seqlengths(gr.snp)
    ## need to assign seqlengths
    data(ideoCyto, package = "biovizBase")
    seqlengths(gr.snp) <- as.numeric(seqlengths(ideoCyto$hg18)[1:22])
    # --- Corrdinate genome [] ---
    # Key functions: autoplot, aes
    autoplot(gr.snp, geom = "point", coord = "genome", aes(y = pvalue))
    # --- Convenient {plotGrandLinear [] ---
    # Key functions: plotGrandLinear, aes
    plotGrandLinear(gr.snp, aes(y = pvalue), color = c("#7fc97f", "#fdc086"))
    
    plotGrandLinear(gr.snp, aes(y = pvalue), color = c("#7fc97f", "#fdc086"),
                    cutoff = 3, cutoff.color = "blue", cutoff.size = 0.2)
    
    plotGrandLinear(gr.snp, aes(y = pvalue, color = OR), spaceline = TRUE, legend = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggbio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggbio_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggbio_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGBIO:", paste0("    ggbio: ", packageVersion("ggbio"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggbio_results.csv
    touch ${prefix}_ggbio_output.rds
    echo "BIOC_GGBIO:" > versions.yml
    echo "    ggbio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGBIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGBIO(ch_input)

    emit:
    results  = BIOC_GGBIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGBIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGBIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGBIO.out.versions  // channel: path(versions.yml)
}
