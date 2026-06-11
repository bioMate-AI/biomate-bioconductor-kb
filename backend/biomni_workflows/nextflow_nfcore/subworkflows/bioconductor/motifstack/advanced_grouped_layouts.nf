#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifStack — advanced_grouped_layouts
// Plot grouped motifs with multi-ring annotations (Circos) or aligned piles with heatmap annotations.
// Input: pfms, df
// Container: quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0
// R packages: RColorBrewer, ade4, motifStack
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, ade4, motifStack
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Align PFMs using DNAmotifAlignment
//  * 2. [Core Analysis] Map annotation data to colors
//  * 3. [Visualization & Output] Plot using motifCircos or motifPiles

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK_ADVANCED_GROUPED_LAYOUTS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("RColorBrewer", "ade4", "motifStack")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(motifStack)
        library(ade4)
        library(RColorBrewer)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        # Read the list of PFM objects
        if (file.exists("pfms.rds")) {
          pfms <- readRDS("pfms.rds")
        } else {
          stop("Error: Required input file 'pfms.rds' not found in the working directory.")
        }
        
        # Read the data frame containing numeric annotation values
        if (file.exists("df.csv")) {
          df <- read.csv("df.csv", row.names = 1)
        } else if (file.exists("df.rds")) {
          df <- readRDS("df.rds")
        } else {
          stop("Error: Required input file 'df.csv' or 'df.rds' not found in the working directory.")
        }
        
        # ==========================================
        # 2. Prepare Hierarchical Clustering & Signatures
        # ==========================================
        # Calculate distances and cluster motifs
        hc <- clusterMotifs(pfms)
        
        # Convert hclust to phylog object
        phylog <- ade4::hclust2phylog(hc)
        
        # Reorder the pfms by the order of hclust leaves
        leaves <- names(phylog\$leaves)
        pfms <- pfms[leaves]
        
        # Reorder df to match the hierarchical clustering leaves
        df <- df[leaves, , drop = FALSE]
        
        # Extract the motif signatures
        motifSig <- motifSignature(pfms, phylog, cutoffPval=0.0001, min.freq=1)
        
        # Get the signatures from object of motifSignature
        sig <- signatures(motifSig)
        
        # Set the inner-circle color for each signature
        gpCol <- sigColor(motifSig)
        
        # Setting colors
        color <- brewer.pal(10, "Set3")
        
        # ==========================================
        # 3. Plot Grouped Motifs with Multi-Ring Annotations (Circos)
        # ==========================================
        pdf("motif_circos.pdf", width=8, height=8)
        motifCircos(phylog=phylog, pfms=pfms, pfms2=sig, 
                    col.tree.bg=rep(color, length.out=length(pfms)), col.tree.bg.alpha=0.3, 
                    col.leaves=rep(rev(color), length.out=length(pfms)),
                    col.inner.label.circle=gpCol, 
                    inner.label.circle.width=0.03,
                    col.outer.label.circle=gpCol, 
                    outer.label.circle.width=0.03,
                    r.rings=c(0.02, 0.03, 0.04), 
                    col.rings=list(sample(colors(), length(pfms), replace=TRUE), 
                                   sample(colors(), length(pfms), replace=TRUE), 
                                   sample(colors(), length(pfms), replace=TRUE)),
                    angle=350, motifScale="logarithmic")
        dev.off()
        
        # ==========================================
        # 4. Map Annotation Data to Colors & Align PFMs
        # ==========================================
        map2col <- function(x, pal){
          rg <- range(x)
          pal[findInterval(x, seq(rg[1], rg[2], length.out = length(pal)+1), 
                           all.inside = TRUE)]
        }
        dl <- lapply(df, map2col, pal=heat.colors(10))
        
        # Alignment of the PFMs
        pfmsAligned <- DNAmotifAlignment(pfms)
        
        # ==========================================
        # 5. Plot Aligned Piles with Heatmap Annotations
        # ==========================================
        pdf("motif_piles.pdf", width=8, height=8)
        motifPiles(phylog=phylog, pfms=pfmsAligned, 
                    col.tree=rep(color, length.out=length(pfms)),
                    col.leaves=rep(rev(color), length.out=length(pfms)),
                    col.pfms2=gpCol, 
                    r.anno=rep(0.02, length(dl)), 
                    col.anno=dl,
                    motifScale="logarithmic",
                    plotIndex=TRUE,
                    groupDistance=10)
        dev.off()
        
        # ==========================================
        # 6. Save Meaningful Results
        # ==========================================
        saveRDS(pfmsAligned, "pfms_aligned.rds")
        saveRDS(dl, "mapped_colors.rds")

    writeLines(c(
        '"BIOC_MOTIFSTACK_ADVANCED_GROUPED_LAYOUTS":',
        paste0('    motifStack: ', as.character(packageVersion('motifStack')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_advanced_grouped_layouts.csv versions.yml
    """
}

workflow BIOC_MOTIFSTACK_ADVANCED_GROUPED_LAYOUTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pfms, df ] ]

    main:
    BIOC_MOTIFSTACK_ADVANCED_GROUPED_LAYOUTS(ch_input)

    emit:
    tables   = BIOC_MOTIFSTACK_ADVANCED_GROUPED_LAYOUTS.out.tables
    plots    = BIOC_MOTIFSTACK_ADVANCED_GROUPED_LAYOUTS.out.plots
    objects  = BIOC_MOTIFSTACK_ADVANCED_GROUPED_LAYOUTS.out.objects
    versions = BIOC_MOTIFSTACK_ADVANCED_GROUPED_LAYOUTS.out.versions
}
