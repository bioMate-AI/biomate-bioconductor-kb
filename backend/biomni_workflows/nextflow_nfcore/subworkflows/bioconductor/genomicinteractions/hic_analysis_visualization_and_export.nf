#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicInteractions — hic_analysis_visualization_and_export
// Load binned Hi-C data from HOMER, filter by FDR, annotate with promoters and enhancers, visualize interactions using Gviz, and export to BED12.
// Input: hic_file, mm9_refseq_promoters, thymus_enhancers
// Container: quay.io/biocontainers/bioconductor-genomicinteractions:1.44.0--r45hdfd78af_0
// R packages: GenomicInteractions, GenomicRanges, Gviz, InteractionSet
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: gene count plot, genomic tracks (Gviz), density plot

nextflow.enable.dsl = 2

process BIOC_GENOMICINTERACTIONS_HIC_ANALYSIS_VISUALIZATION_AND_EXPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genomicinteractions:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicInteractions", "GenomicRanges", "Gviz", "InteractionSet")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(Gviz)
    library(GenomicInteractions)
    library(GenomicRanges)
    library(InteractionSet)
    
    # ==========================================
    # --- Load Hi-C data and User Inputs ---
    # ==========================================
    
    # Define input file paths in the working directory
    hic_file <- "Seitan2013_WT_100kb_interactions.txt"
    
    # Fallback to any .txt file if the exact filename is not found
    if (!file.exists(hic_file)) {
      txt_files <- list.files(pattern = "\\\\.txt\$")
      if (length(txt_files) > 0) {
        hic_file <- txt_files[1]
      } else {
        stop("Error: HOMER interaction text file not found in the working directory.")
      }
    }
    
    # Load mm9 RefSeq promoters (GRanges)
    if (file.exists("mm9_refseq_promoters.rds")) {
      mm9_refseq_promoters <- readRDS("mm9_refseq_promoters.rds")
    } else if (file.exists("mm9_refseq_promoters")) {
      mm9_refseq_promoters <- readRDS("mm9_refseq_promoters")
    } else {
      stop("Error: mm9_refseq_promoters file not found in the working directory.")
    }
    
    # Load thymus enhancers (GRanges)
    if (file.exists("thymus_enhancers.rds")) {
      thymus_enh <- readRDS("thymus_enhancers.rds")
    } else if (file.exists("thymus_enhancers")) {
      thymus_enh <- readRDS("thymus_enhancers")
    } else {
      stop("Error: thymus_enhancers file not found in the working directory.")
    }
    
    # Load binned Hi-C data from HOMER
    hic_data <- makeGenomicInteractionsFromFile(hic_file, 
                                                type = "homer", 
                                                experiment_name = "HiC 100kb", 
                                                description = "HiC 100kb resolution")
    
    # ==========================================
    # --- Set Chromosome Lengths ---
    # ==========================================
    seqlengths(hic_data) <- c(chr15 = 103494974, chr14 = 125194864)
    
    # ==========================================
    # --- Calculate P-values and Filter by FDR ---
    # ==========================================
    hic_data\$p.value <- exp(hic_data\$LogP)
    
    # Inspect basic properties of the object
    regions(hic_data)
    anchors(hic_data, type = "first")
    head(anchors(hic_data, type = "first", id = TRUE))
    anchorOne(hic_data)
    summary(width(regions(hic_data)))
    head(interactionCounts(hic_data))
    mean(interactionCounts(hic_data))
    
    # Plot density of p-values and FDR
    pdf("density_plots.pdf", width = 8, height = 6)
    plot(density(hic_data\$p.value))
    
    # Dynamically map the FDR column to ensure the exact vignette line runs successfully
    actual_fdr_col <- grep("FDR.Benjamini", colnames(mcols(hic_data)), value = TRUE)
    if (length(actual_fdr_col) > 0 && actual_fdr_col[1] != "FDR.Benjamini..based.on.3.68e.08.total.tests.") {
      hic_data\$FDR.Benjamini..based.on.3.68e.08.total.tests. <- mcols(hic_data)[[actual_fdr_col[1]]]
    }
    
    hic_data\$fdr <- hic_data\$FDR.Benjamini..based.on.3.68e.08.total.tests.
    plot(density(hic_data\$fdr))
    dev.off()
    
    sum(hic_data\$fdr < 0.1)
    hic_data_subset <- hic_data[hic_data\$fdr < 0.1]
    
    # ==========================================
    # --- Plot Summary Statistics ---
    # ==========================================
    pdf("cis_trans_plots.pdf", width = 8, height = 6)
    plotCisTrans(hic_data)
    plotCisTrans(hic_data_subset)
    dev.off()
    
    pdf("counts_plots.pdf", width = 8, height = 6)
    plotCounts(hic_data, cut=30)
    plotCounts(hic_data_subset, cut=30)
    dev.off()
    
    # ==========================================
    # --- Annotate Interactions ---
    # ==========================================
    annotation.features <- list(promoter = mm9_refseq_promoters, enhancer = thymus_enh)
    annotateInteractions(hic_data_subset, annotation.features)
    
    head(regions(hic_data_subset))
    head(regions(hic_data_subset)\$promoter.id)
    table(regions(hic_data_subset)\$node.class)
    
    pdf("interaction_annotations.pdf", width = 8, height = 6)
    plotInteractionAnnotations(hic_data_subset, legend = TRUE)
    dev.off()
    
    # ==========================================
    # --- Subset Specific Interaction Types ---
    # ==========================================
    length(hic_data_subset[isInteractionType(hic_data_subset, "promoter", "distal")])
    length(hic_data_subset[is.pd(hic_data_subset)])
    sum(is.trans(hic_data_subset))
    
    hic_data_ep <- hic_data_subset[isInteractionType(hic_data_subset, "promoter", "enhancer")]
    max(interactionCounts(hic_data_ep))
    most_counts <- hic_data_ep[which.max(interactionCounts(hic_data_ep))]
    most_counts
    min(hic_data_ep\$p.value)
    min_pval <- hic_data_ep[which.min(hic_data_ep\$p.value)]
    min_pval
    
    calculateDistances(most_counts, method="midpoint")
    calculateDistances(min_pval, method="midpoint")
    summary(calculateDistances(hic_data_subset, method="midpoint"))
    
    anchorOne(most_counts)\$promoter.id
    anchorTwo(most_counts)\$enhancer.id
    
    # ==========================================
    # --- Visualize Interactions using Gviz ---
    # ==========================================
    Trib1_region <- resize(mm9_refseq_promoters["Trib1"], fix = "center", width = 1000000)
    interaction_track <- InteractionTrack(hic_data_subset, name = "HiC", chromosome = "chr15")
    
    pdf("gviz_tracks.pdf", width = 10, height = 8)
    plotTracks(interaction_track, chromosome="chr15", from=start(Trib1_region), to=end(Trib1_region))
    
    promoterTrack <- AnnotationTrack(mm9_refseq_promoters, genome="mm9", name="Promoters", id=names(mm9_refseq_promoters), featureAnnotation="id")
    enhTrack <- AnnotationTrack(thymus_enh, genome="mm9", name="Enhancers", stacking = "dense")
    
    displayPars(promoterTrack) <- list(fill = "deepskyblue", col = NA, fontcolor.feature = "black", fontsize=8, just.group="below")
    displayPars(enhTrack) <- list(fill = "black", col = NA)
    displayPars(interaction_track) = list(col.interactions="red", col.anchors.fill ="blue", col.anchors.line = "black", interaction.dimension="height", interaction.measure ="counts", plot.trans=FALSE, plot.outside = TRUE, col.outside="lightblue", anchor.height = 0.1)
    
    plotTracks(list(interaction_track, promoterTrack, enhTrack), chromosome="chr15", from=start(Trib1_region), to=end(Trib1_region), sizes=c(0.6, 0.2, 0.2))
    dev.off()
    
    # ==========================================
    # --- Export Filtered Interactions to BED12 ---
    # ==========================================
    export.bed12(hic_data_subset, fn="hic_data_FDR0.1.bed", drop.trans = TRUE)
    
    # Save processed R objects for downstream analysis
    saveRDS(hic_data_subset, "hic_data_subset.rds")
    saveRDS(hic_data_ep, "hic_data_ep.rds")
    
    # Write a summary text file of the analysis
    sink("pipeline_summary.txt")
    cat("=== GenomicInteractions Pipeline Summary ===\n")
    cat("Total interactions loaded:", length(hic_data), "\n")
    cat("Interactions after FDR < 0.1 filtering:", length(hic_data_subset), "\n")
    cat("Enhancer-Promoter interactions identified:", length(hic_data_ep), "\n")
    cat("\nNode class distribution:\n")
    print(table(regions(hic_data_subset)\$node.class))
    cat("\nMost counts promoter-enhancer interaction:\n")
    print(most_counts)
    cat("\nMost significant promoter-enhancer interaction:\n")
    print(min_pval)
    sink()

    writeLines(c(
        '"BIOC_GENOMICINTERACTIONS_HIC_ANALYSIS_VISUALIZATION_AND_EXPORT":',
        paste0('        GenomicInteractions: ', as.character(packageVersion("GenomicInteractions")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hic_analysis_visualization_and_export.csv versions.yml
    """
}

workflow BIOC_GENOMICINTERACTIONS_HIC_ANALYSIS_VISUALIZATION_AND_EXPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hic_file, mm9_refseq_promoters, thymus_enhancers ] ]

    main:
    BIOC_GENOMICINTERACTIONS_HIC_ANALYSIS_VISUALIZATION_AND_EXPORT(ch_input)

    emit:
    tables   = BIOC_GENOMICINTERACTIONS_HIC_ANALYSIS_VISUALIZATION_AND_EXPORT.out.tables
    plots    = BIOC_GENOMICINTERACTIONS_HIC_ANALYSIS_VISUALIZATION_AND_EXPORT.out.plots
    objects  = BIOC_GENOMICINTERACTIONS_HIC_ANALYSIS_VISUALIZATION_AND_EXPORT.out.objects
    versions = BIOC_GENOMICINTERACTIONS_HIC_ANALYSIS_VISUALIZATION_AND_EXPORT.out.versions
}
