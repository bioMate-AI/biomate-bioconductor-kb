#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trackViewer — genomic_track_visualization
// Import NGS coverage data (WIG/BED), build gene models, and visualize them as aligned track layers.
// Input: file1.wig, file2.wig, file3.bed
// Container: quay.io/biocontainers/bioconductor-trackviewer:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, TxDb.Hsapiens.UCSC.hg19.knownGene, org.Hs.eg.db, rtracklayer, trackViewer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import score data using importScore
//  * 2. [Core Analysis] Set strand information manually
//  * 3. [Core Analysis] Calculate coverage using coverageGR
//  * 4. [Input & Preparation] Build gene models using geneModelFromTxdb
//  * 5. [Core Analysis] Optimize track styles using optimizeStyle
//  * 6. [Visualization & Output] Plot tracks using viewTracks

nextflow.enable.dsl = 2

process BIOC_TRACKVIEWER_GENOMIC_TRACK_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(trackViewer)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    library(GenomicRanges)
    library(rtracklayer)
    
    # 1. Import score data using importScore
    # file1.wig is forward strand signal (+), file2.wig is reverse strand signal (-)
    repA <- importScore("file2.wig", "file1.wig", format="WIG")
    
    # 2. Set strand information manually
    strand(repA\$dat) <- "-"
    strand(repA\$dat2) <- "+"
    
    # Read BED file to dynamically determine the genomic coordinates
    bed_data <- rtracklayer::import("file3.bed", format="BED")
    chrom <- as.character(seqnames(bed_data)[1])
    start_pos <- min(start(bed_data))
    end_pos <- max(end(bed_data))
    
    # Define the genomic range of interest (gr) for gene model and visualization
    # We center it around the middle of the BED features
    mid_pos <- round((start_pos + end_pos) / 2)
    gr <- GRanges(chrom, IRanges(mid_pos - 500, mid_pos + 500), strand="-")
    
    # Import BED features using importScore
    fox2 <- importScore("file3.bed", format="BED", ranges=GRanges(chrom, IRanges(start_pos, end_pos)))
    
    # 3. Calculate coverage using coverageGR
    dat <- coverageGR(fox2\$dat)
    fox2\$dat <- dat[strand(dat)=="+"]
    fox2\$dat2 <- dat[strand(dat)=="-"]
    
    # 4. Build gene models using geneModelFromTxdb
    trs <- geneModelFromTxdb(TxDb.Hsapiens.UCSC.hg19.knownGene, org.Hs.eg.db, gr=gr)
    
    # 5. Optimize track styles using optimizeStyle
    optSty <- optimizeStyle(trackList(repA, fox2, trs))
    trackList <- optSty\$tracks
    viewerStyle <- optSty\$style
    
    # 6. Plot tracks using viewTracks and save to PDF
    pdf("genomic_tracks.pdf", width=10, height=8)
    viewTracks(trackList, gr=gr, viewerStyle=viewerStyle)
    dev.off()
    
    # Save outputs as RDS objects
    saveRDS(trackList, "trackList.rds")
    saveRDS(viewerStyle, "viewerStyle.rds")

    writeLines(c(
        '"BIOC_TRACKVIEWER_GENOMIC_TRACK_VISUALIZATION":',
        paste0('    trackViewer: ', as.character(packageVersion('trackViewer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_track_visualization.csv versions.yml
    """
}

workflow BIOC_TRACKVIEWER_GENOMIC_TRACK_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file1.wig, file2.wig, file3.bed ] ]

    main:
    BIOC_TRACKVIEWER_GENOMIC_TRACK_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TRACKVIEWER_GENOMIC_TRACK_VISUALIZATION.out.tables
    plots    = BIOC_TRACKVIEWER_GENOMIC_TRACK_VISUALIZATION.out.plots
    objects  = BIOC_TRACKVIEWER_GENOMIC_TRACK_VISUALIZATION.out.objects
    versions = BIOC_TRACKVIEWER_GENOMIC_TRACK_VISUALIZATION.out.versions
}
