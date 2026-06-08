#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifStack — ggplot2_motif_plotting
// Plot motifs inside a ggplot2 canvas using geom_motif.
// Input: bin_SOLEXA.pcm
// Container: quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0
// Requires: ggplot2, motifStack
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a data frame with motif coordinates and PFM objects
//  * 2. [Core Analysis] Initialize ggplot and add geom_motif()

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(motifStack)
    library(ggplot2)
    library(grid)
    
    # 1. Read the Position Count Matrix (PCM) from the working directory
    pcm <- read.table("bin_SOLEXA.pcm")
    pcm <- pcm[, 3:ncol(pcm)]
    rownames(pcm) <- c("A", "C", "G", "T")
    
    # 2. Define markers for the motif
    markerRect <- new("marker", type="rect", start=6, stop=7, gp=gpar(lty=2, fill=NA, col="orange"))
    markerLine <- new("marker", type="line", start=3, stop=5, gp=gpar(lwd=2, col="red"))
    markerText <- new("marker", type="text", start=1, label="*", gp=gpar(cex=2, col="red"))
    
    # 3. Construct the PCM and PFM objects
    motif <- new("pcm", mat=as.matrix(pcm), name="bin_SOLEXA", 
                 markers=c(markerRect, markerLine, markerText))
    pfm <- pcm2pfm(motif)
    
    # 4. Create a data frame with motif coordinates (xmin, ymin, xmax, ymax) and PFM objects
    df1 <- data.frame(xmin=c(.25, .25), ymin=c(.25, .75), xmax=c(.75, .75), ymax=c(.5, 1), 
                     fontfamily=c("serif", "mono"), fontface=c(2, 1))
    df1\$motif <- list(pfm, pfm)
    
    # 5. Initialize ggplot and add geom_motif() using coordinate bounds
    p1 <- ggplot(df1, aes(xmin=xmin, ymin=ymin, xmax=xmax, ymax=ymax, motif=motif, 
                   fontfamily=fontfamily, fontface=fontface)) + 
        geom_motif() + theme_bw() + ylim(0, 1) + xlim(0, 1)
    
    # 6. Create a data frame with motif coordinates (x, y, width, height) and PFM objects
    df2 <- data.frame(x=.5, y=c(.25, .75), width=.5, height=.25, 
                     fontfamily=c("serif", "mono"), fontface=c(2, 1))
    df2\$motif <- list(pfm, pfm)
    
    # 7. Initialize ggplot and add geom_motif() using x, y, width, height
    p2 <- ggplot(df2, aes(x=x, y=y, width=width, height=height, motif=motif, 
                   fontfamily=fontfamily, fontface=fontface)) + 
        geom_motif(use.xy=TRUE) + theme_bw() + ylim(0, 1) + xlim(0, 1)
    
    # 8. Save outputs to files
    ggsave("motif_plot_coords.pdf", plot=p1, width=6, height=6)
    ggsave("motif_plot_xy.pdf", plot=p2, width=6, height=6)
    saveRDS(df1, "motif_df_coords.rds")
    saveRDS(df2, "motif_df_xy.rds")

    writeLines(c(
        '"BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING":',
        paste0('    motifStack: ', as.character(packageVersion('motifStack')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggplot2_motif_plotting.csv versions.yml
    """
}

workflow BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bin_SOLEXA.pcm ] ]

    main:
    BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING(ch_input)

    emit:
    tables   = BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING.out.tables
    plots    = BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING.out.plots
    objects  = BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING.out.objects
    versions = BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING.out.versions
}
