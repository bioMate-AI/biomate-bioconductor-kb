#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifStack — motif_cloud_and_signatures
// Cluster multiple motifs, extract motif signatures, and visualize them as a tag-cloud or grouped radial phylogeny.
// Input: pfms
// Container: quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0
// Requires: RColorBrewer, ade4, motifStack
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Cluster motifs using clusterMotifs
//  * 2. [Core Analysis] Convert hclust to phylog using ade4::hclust2phylog
//  * 3. [Core Analysis] Extract signatures using motifSignature
//  * 4. [Visualization & Output] Plot using motifCloud or plotMotifStackWithRadialPhylog

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK_MOTIF_CLOUD_AND_SIGNATURES {
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(motifStack)
        library(RColorBrewer)
        library(ade4)
        
        # Read user input
        # The pipeline expects a file named 'pfms.rds' containing a list of PFM objects or matrices
        if (!file.exists("pfms.rds")) {
          stop("Error: 'pfms.rds' not found in the working directory.")
        }
        pfms <- readRDS("pfms.rds")
        
        # Ensure the list of PFM objects has names to prevent mapply from failing
        if (is.null(names(pfms))) {
          names(pfms) <- paste0("motif", seq_along(pfms))
        }
        
        # Pre-process input to ensure all elements are valid PFM objects
        # Preserves existing PFM/PCM/PSAM objects to keep metadata (colors, markers)
        pfms <- mapply(names(pfms), pfms, FUN=function(.ele, .pfm){
          if (inherits(.pfm, "pfm") || inherits(.pfm, "pcm") || inherits(.pfm, "psam")) {
            if (length(.pfm@name) == 0 || .pfm@name == "") .pfm@name <- .ele
            return(.pfm)
          } else {
            return(new("pfm", mat=as.matrix(.pfm), name=.ele))
          }
        }, SIMPLIFY = FALSE)
        
        # Define color palette (used in the radial phylog plot)
        color <- brewer.pal(10, "Set3")
        
        # Dynamically adjust groups to match the number of input motifs
        n_pfms <- length(pfms)
        each_val <- ceiling(n_pfms / 5)
        groups <- rep(paste("group", 1:5, sep=""), each=each_val)[1:n_pfms]
        names(groups) <- names(pfms)
        
        group.col <- brewer.pal(5, "Set3")
        names(group.col) <- paste("group", 1:5, sep="")
        
        # 1. Cluster motifs
        hc <- clusterMotifs(pfms)
        
        # 2. Convert hclust to phylog
        phylog <- ade4::hclust2phylog(hc)
        leaves <- names(phylog\$leaves)
        pfms <- pfms[leaves]
        
        # 3. Extract motif signatures
        motifSig <- motifSignature(pfms, phylog, cutoffPval=0.0001, min.freq=1)
        
        # 4. Plot and save outputs
        # Plot 1: Motif Cloud
        pdf("motif_cloud.pdf", width=8, height=8)
        motifCloud(motifSig, scale=c(6, .5), 
                   layout="rectangles", 
                   group.col=group.col, 
                   groups=groups, 
                   draw.legend=TRUE)
        dev.off()
        
        # Plot 2: Radial Phylog
        sig <- signatures(motifSig)
        gpCol <- sigColor(motifSig)
        
        pdf("motif_radial_phylog.pdf", width=8, height=8)
        plotMotifStackWithRadialPhylog(phylog=phylog, pfms=sig, 
                                      circle=0.4, cleaves = 0.3, 
                                      clabel.leaves = 0.5, 
                                      col.bg=rep(color, length.out=n_pfms), col.bg.alpha=0.3, 
                                      col.leaves=rep(rev(color), length.out=n_pfms),
                                      col.inner.label.circle=gpCol, 
                                      inner.label.circle.width=0.03,
                                      angle=350, circle.motif=1.2, 
                                      motifScale="logarithmic")
        dev.off()
        
        # Save RDS outputs
        saveRDS(motifSig, "motif_signatures.rds")
        saveRDS(phylog, "phylog.rds")
        
        message("Pipeline completed successfully. Outputs saved to 'motif_cloud.pdf', 'motif_radial_phylog.pdf', 'motif_signatures.rds', and 'phylog.rds'.")

    writeLines(c(
        '"BIOC_MOTIFSTACK_MOTIF_CLOUD_AND_SIGNATURES":',
        paste0('    motifStack: ', as.character(packageVersion('motifStack')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_cloud_and_signatures.csv versions.yml
    """
}

workflow BIOC_MOTIFSTACK_MOTIF_CLOUD_AND_SIGNATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pfms ] ]

    main:
    BIOC_MOTIFSTACK_MOTIF_CLOUD_AND_SIGNATURES(ch_input)

    emit:
    tables   = BIOC_MOTIFSTACK_MOTIF_CLOUD_AND_SIGNATURES.out.tables
    plots    = BIOC_MOTIFSTACK_MOTIF_CLOUD_AND_SIGNATURES.out.plots
    objects  = BIOC_MOTIFSTACK_MOTIF_CLOUD_AND_SIGNATURES.out.objects
    versions = BIOC_MOTIFSTACK_MOTIF_CLOUD_AND_SIGNATURES.out.versions
}
