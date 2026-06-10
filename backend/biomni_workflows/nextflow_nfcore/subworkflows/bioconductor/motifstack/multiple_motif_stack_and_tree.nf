#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifStack — multiple_motif_stack_and_tree
// Align and visualize multiple motifs in a vertical stack, hierarchical tree, or radial phylogeny.
// Input: motifs_folder
// Container: quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0
// Requires: RColorBrewer, motifStack
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import multiple motifs
//  * 2. [Core Analysis] (Optional) Convert DNA to RNA motifs
//  * 3. [Visualization & Output] Plot using motifStack with "stack", "tree", or "radialPhylog" layouts

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK_MULTIPLE_MOTIF_STACK_AND_TREE {
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
    .bm_deps <- c("RColorBrewer", "motifStack")
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
    
    # Define input directory
    motifs_folder <- "motifs_folder"
    
    # Check if input directory exists
    if (!dir.exists(motifs_folder)) {
      stop(paste("Error: Input directory", motifs_folder, "does not exist."))
    }
    
    # Get list of .pcm files
    pcm_files <- dir(motifs_folder, pattern = "pcm\$", full.names = TRUE)
    if (length(pcm_files) == 0) {
      stop(paste("Error: No .pcm files found in", motifs_folder))
    }
    
    # 1. Import multiple motifs
    motifs <- importMatrix(pcm_files)
    
    # Save imported motifs to RDS
    saveRDS(motifs, "imported_motifs.rds")
    
    # Open PDF device to capture all plots
    pdf("motifStack_pipeline_plots.pdf", width = 8, height = 8)
    
    # Plot 1: Stack layout
    motifStack(motifs, layout="stack", ncex=1.0)
    
    # 2. Convert DNA to RNA motifs
    rnaMotifs <- DNAmotifToRNAmotif(motifs)
    names(rnaMotifs)
    
    # Plot 2: RNA motifs stack layout
    motifStack(rnaMotifs, layout = "stack", 
               reorder=FALSE)
    
    # Save RNA motifs to RDS
    saveRDS(rnaMotifs, "rna_motifs.rds")
    
    # Prepare a psam motif from the first imported motif for the affinity logo stack
    psam_mat <- motifs[[1]]\$mat
    # Ensure the matrix has at least 12 columns for the subsetting step
    if (ncol(psam_mat) < 12) {
      padding <- matrix(0.25, nrow = 4, ncol = 12 - ncol(psam_mat))
      rownames(padding) <- rownames(psam_mat)
      psam_mat <- cbind(psam_mat, padding)
    }
    motif <- new("psam", mat = psam_mat, name = "affinity logo")
    
    # Plot 3: Affinity logo stack
    motif2 <- motif
    motif2\$mat <- motif\$mat[, 5:12]
    motif2\$name <- "logo2"
    psamMotifs <- list(motif, motif2)
    motifStack(psamMotifs)
    
    # Plot 4: Hierarchical tree layout
    motifStack(motifs, layout="tree")
    
    # 3. Prepare motifs for radial phylogeny layout
    # Convert imported PCM matrices to PFM matrices
    pfms_list <- lapply(motifs, function(m) {
      pcm2pfm(m\$mat)
    })
    names(pfms_list) <- sapply(motifs, function(m) m\$name)
    
    # Sample 30 PFMs (with replacement if fewer than 30 are available)
    set.seed(42)
    if (length(pfms_list) < 30) {
      sampled_indices <- sample(seq_along(pfms_list), 30, replace = TRUE)
      pfms <- pfms_list[sampled_indices]
      names(pfms) <- paste0(names(pfms), "_", seq_along(pfms))
    } else {
      pfms <- sample(pfms_list, 30)
    }
    
    # Create a list of pfm objects
    motifs2 <- mapply(pfms, names(pfms), FUN=function(.ele, .name){
      new("pfm",mat=.ele, name=.name)}, SIMPLIFY = FALSE)
    
    # Trim the motifs
    motifs2 <- lapply(motifs2, trimMotif, t=0.4)
    
    # Save processed radial motifs to RDS
    saveRDS(motifs2, "radial_phylog_motifs.rds")
    
    # Plot 5: Radial phylogeny layout
    color <- brewer.pal(10, "Set3")
    motifStack(motifs2, layout="radialPhylog", 
               circle=0.3, cleaves = 0.2, 
               clabel.leaves = 0.5, 
               col.bg=rep(color, each=3), col.bg.alpha=0.3, 
               col.leaves=rep(color, each=3),
               col.inner.label.circle=rep(color, each=3), 
               inner.label.circle.width=0.05,
               col.outer.label.circle=rep(color, each=3), 
               outer.label.circle.width=0.02, 
               circle.motif=1.2,
               angle=350)
    
    # Close PDF device
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to 'motifStack_pipeline_plots.pdf' and RDS files.\n")

    writeLines(c(
        '"BIOC_MOTIFSTACK_MULTIPLE_MOTIF_STACK_AND_TREE":',
        paste0('    motifStack: ', as.character(packageVersion('motifStack')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_motif_stack_and_tree.csv versions.yml
    """
}

workflow BIOC_MOTIFSTACK_MULTIPLE_MOTIF_STACK_AND_TREE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ motifs_folder ] ]

    main:
    BIOC_MOTIFSTACK_MULTIPLE_MOTIF_STACK_AND_TREE(ch_input)

    emit:
    tables   = BIOC_MOTIFSTACK_MULTIPLE_MOTIF_STACK_AND_TREE.out.tables
    plots    = BIOC_MOTIFSTACK_MULTIPLE_MOTIF_STACK_AND_TREE.out.plots
    objects  = BIOC_MOTIFSTACK_MULTIPLE_MOTIF_STACK_AND_TREE.out.objects
    versions = BIOC_MOTIFSTACK_MULTIPLE_MOTIF_STACK_AND_TREE.out.versions
}
