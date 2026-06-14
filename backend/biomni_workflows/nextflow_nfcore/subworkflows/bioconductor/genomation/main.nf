#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomation — genomic_signal_extraction_and_visualization
// Extract genomic signal (e.g., CAGE, ChIP-seq) over windows of interest (e.g., promoters, exons) and visualize via heatmaps or meta-plots.
// Input: aligned_reads.bam, genomic_features.gtf
// Container: quay.io/biocontainers/bioconductor-genomation:1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicAlignments, GenomicRanges, Rsamtools, genomation
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read genomic annotations using gffToGRanges
//  * 2. [Input & Preparation] Build score matrices over windows using ScoreMatrix (equal width) or ScoreMatrixBin (unequal width)
//  * 3. [Core Analysis] Combine multiple targets into a ScoreMatrixList
//  * 4. [Core Analysis] Scale matrices using scaleScoreMatrix or scaleScoreMatrixList
//  * 5. [Visualization & Output] Visualize using heatMatrix, plotMeta, or multiHeatMatrix

nextflow.enable.dsl = 2

process BIOC_GENOMATION_GENOMIC_SIGNAL_EXTRACTION_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("genomation", "GenomicRanges", "Rsamtools", "GenomicAlignments")
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
    library(genomation)
    library(GenomicRanges)
    library(Rsamtools)
    library(GenomicAlignments)
    
    # Define input files
    bam.file = "aligned_reads.bam"
    gff.file = "genomic_features.gtf"
    
    # Ensure BAM index exists
    if (!file.exists(paste0(bam.file, ".bai"))) {
      Rsamtools::indexBam(bam.file)
    }
    
    # 1. Read genomic annotations and alignments
    # Read BAM file as the primary genomic signal (cage)
    cage = bam.file
    
    # Read GTF file
    gff = gffToGRanges(gff.file)
    
    # Extract exons
    exons = gffToGRanges(gff.file, filter='exon')
    
    # Extract promoters (using transcripts/mRNA if available, otherwise exons)
    transcripts_for_prom = gff[gff\$type %in% c("transcript", "mRNA")]
    if (length(transcripts_for_prom) == 0) {
      transcripts_for_prom = exons
    }
    promoters = GenomicRanges::promoters(transcripts_for_prom, upstream=1000, downstream=1000)
    promoters = unique(promoters)
    
    # Align seqlevels to avoid out-of-bounds or mismatch errors
    bam_seqlevels = names(Rsamtools::scanBamHeader(cage)[[1]]\$targets)
    common_seqlevels = intersect(bam_seqlevels, seqlevelsInUse(promoters))
    promoters = keepSeqlevels(promoters, common_seqlevels, pruning.mode="coarse")
    exons = keepSeqlevels(exons, common_seqlevels, pruning.mode="coarse")
    
    # Define a second target feature (cpgi) from a subset of exons to avoid external dependencies
    cpgi = exons
    if (length(cpgi) > 100) {
      cpgi = cpgi[seq(1, length(cpgi), by=5)]
    }
    
    # 2. Build score matrices over windows
    # Equal width windows using ScoreMatrix
    sm = ScoreMatrix(target=cage, windows=promoters)
    sm
    
    # Unequal width windows (exons) using ScoreMatrixBin
    sm = ScoreMatrixBin(target=cage, windows=exons, bin.num=50)
    sm
    
    # Grouped unequal width windows (transcripts) using ScoreMatrixBin
    transcripts = split(exons, exons\$transcript_id)
    sm = ScoreMatrixBin(target=cage, windows=transcripts, bin.num=10)
    sm
    
    # 3. Combine multiple targets into a ScoreMatrixList
    # ScoreMatrixList requires all targets to be of the same type.
    # Convert BAM file to GRanges to match the cpgi GRanges object.
    cage_gr = as(GenomicAlignments::readGAlignments(bam.file), "GRanges")
    targets = list(cage=cage_gr, cpgi=cpgi)
    sml_base = ScoreMatrixList(targets=targets, windows=promoters, bin.num=50)
    sml_base
    
    # 4. Visualization and advanced analysis
    # Open PDF device for plots
    pdf("genomation_visualization_plots.pdf", width=10, height=8)
    
    # Heatmap and Meta-plot of the ScoreMatrixList
    multiHeatMatrix(sml_base, xcoords=c(-1000, 1000))
    plotMeta(sml_base, xcoords=c(-1000, 1000))
    
    # Strand-aware ScoreMatrix and grouping by overlap
    sm_strand = ScoreMatrix(target=cage, windows=promoters, strand.aware=TRUE)
    
    # Filter promoters to match the windows kept by ScoreMatrix to avoid out-of-bounds errors
    valid_promoters = promoters[as.numeric(rownames(sm_strand))]
    cpg.ind = which(countOverlaps(valid_promoters, cpgi)>0)
    nocpg.ind = which(countOverlaps(valid_promoters, cpgi)==0)
    
    # Heatmap with grouping (split the ScoreMatrix prior to plotting)
    heatMatrix(sm_strand[cpg.ind, ], xcoords=c(-1000, 1000))
    heatMatrix(sm_strand[nocpg.ind, ], xcoords=c(-1000, 1000))
    
    # Scaling the ScoreMatrix
    sm.scaled = scaleScoreMatrix(sm_strand)
    heatMatrix(sm.scaled[cpg.ind, ], xcoords=c(-1000, 1000))
    heatMatrix(sm.scaled[nocpg.ind, ], xcoords=c(-1000, 1000))
    
    # Strand-aware ScoreMatrixList and multi-heatmap visualization
    sml = ScoreMatrixList(targets=targets, windows=promoters, bin.num=50, strand.aware=TRUE)
    multiHeatMatrix(sml, xcoords=c(-1000, 1000))
    
    # Multi-heatmap with k-means clustering (wrapped in tryCatch for robustness)
    tryCatch({
      multiHeatMatrix(sml, xcoords=c(-1000, 1000), clustfun=function(x) kmeans(x, centers=2)\$cluster)
    }, error = function(e) {
      warning("K-means clustering failed: ", e\$message)
    })
    
    dev.off()
    
    # 5. Save meaningful outputs
    saveRDS(sml_base, "score_matrix_list.rds")
    saveRDS(sml, "score_matrix_list_strand_aware.rds")
    
    # Export a summary table of the scaled score matrix
    sm_matrix = as(sm.scaled, "matrix")
    write.csv(head(sm_matrix, 100), "scaled_score_matrix_head.csv", row.names=TRUE)
    
    message("Pipeline completed successfully. Outputs saved to 'genomation_visualization_plots.pdf', 'score_matrix_list.rds', and 'scaled_score_matrix_head.csv'.")

    writeLines(c(
        '"BIOC_GENOMATION_GENOMIC_SIGNAL_EXTRACTION_AND_VISUALIZATION":',
        paste0('    genomation: ', as.character(packageVersion('genomation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_signal_extraction_and_visualization.csv versions.yml
    """
}

workflow BIOC_GENOMATION_GENOMIC_SIGNAL_EXTRACTION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ aligned_reads.bam, genomic_features.gtf ] ]

    main:
    BIOC_GENOMATION_GENOMIC_SIGNAL_EXTRACTION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GENOMATION_GENOMIC_SIGNAL_EXTRACTION_AND_VISUALIZATION.out.tables
    plots    = BIOC_GENOMATION_GENOMIC_SIGNAL_EXTRACTION_AND_VISUALIZATION.out.plots
    objects  = BIOC_GENOMATION_GENOMIC_SIGNAL_EXTRACTION_AND_VISUALIZATION.out.objects
    versions = BIOC_GENOMATION_GENOMIC_SIGNAL_EXTRACTION_AND_VISUALIZATION.out.versions
}
