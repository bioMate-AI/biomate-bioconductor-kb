#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Gviz — sequence_alignment_visualization
// Visualize next-generation sequencing alignments from BAM files, including coverage, pileups, and sashimi junction plots.
// Input: gapped.bam
// Container: quay.io/biocontainers/bioconductor-gviz:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Gviz, Rsamtools
// Visualizations: genomic tracks (Gviz)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Specify the path to the BAM file
//  * 2. [Input & Preparation] Construct an AlignmentsTrack object
//  * 3. [Visualization & Output] Plot the alignments using different visualization types (coverage, pileup, sashimi)

nextflow.enable.dsl = 2

process BIOC_GVIZ_SEQUENCE_ALIGNMENT_VISUALIZATION {
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
    .bm_deps <- c("Gviz", "Rsamtools")
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
    library(Gviz)
    library(Rsamtools)
    
    # Ensure the BAM file is indexed (Gviz requires a .bai file for AlignmentsTrack)
    bam_file <- "gapped.bam"
    if (file.exists(bam_file) && !file.exists(paste0(bam_file, ".bai"))) {
      tryCatch({
        Rsamtools::indexBam(bam_file)
      }, error = function(e) {
        warning("Could not index BAM file automatically: ", e\$message)
      })
    }
    
    # Dynamically determine chromosome and a reasonable plotting range from the BAM file
    # We read a chunk of reads to avoid loading a potentially massive BAM file into memory
    bf <- Rsamtools::BamFile(bam_file, yieldSize = 10000)
    open(bf)
    bam_data <- Rsamtools::scanBam(bf, param = Rsamtools::ScanBamParam(what = c("rname", "pos", "qwidth")))[[1]]
    close(bf)
    
    valid_idx <- which(!is.na(bam_data\$rname) & !is.na(bam_data\$pos) & !is.na(bam_data\$qwidth))
    if (length(valid_idx) == 0) {
      # Fallback if first 10000 reads are unmapped
      bam_data <- Rsamtools::scanBam(bam_file, param = Rsamtools::ScanBamParam(what = c("rname", "pos", "qwidth")))[[1]]
      valid_idx <- which(!is.na(bam_data\$rname) & !is.na(bam_data\$pos) & !is.na(bam_data\$qwidth))
      if (length(valid_idx) == 0) stop("BAM file contains no mapped reads.")
    }
    
    chrom <- as.character(bam_data\$rname[valid_idx[1]])
    chrom_idx <- valid_idx[bam_data\$rname[valid_idx] == chrom]
    
    afrom <- as.integer(min(bam_data\$pos[chrom_idx], na.rm = TRUE))
    ato <- as.integer(max((bam_data\$pos + bam_data\$qwidth)[chrom_idx], na.rm = TRUE))
    
    span <- ato - afrom
    if (span < 100) {
      afrom <- as.integer(afrom - 50)
      ato <- as.integer(ato + 50)
      span <- ato - afrom
    }
    
    # Create a local GeneRegionTrack to represent 'bmt' (Biomart/Gene model track)
    # used in the vignette, avoiding external API calls or bundled demo data.
    # Dynamically scaled to fit the BAM file's range.
    bmt <- GeneRegionTrack(
      start = as.integer(c(afrom + span * 0.05, afrom + span * 0.45, afrom + span * 0.75)),
      end = as.integer(c(afrom + span * 0.15, afrom + span * 0.55, afrom + span * 0.85)),
      chromosome = chrom,
      genome = "hg19",
      name = "Gene Model"
    )
    
    # Construct the AlignmentsTrack object using the user-provided BAM file
    alTrack <- AlignmentsTrack(
      bam_file, 
      isPaired = TRUE
    )
    
    # Open a PDF device to save the visualization results
    pdf("sequence_alignment_visualization.pdf", width = 12, height = 10)
    
    # Execute the plotting steps exactly as documented
    plotTracks(c(bmt, alTrack), from = afrom, to = ato, chromosome = chrom)
    
    plotTracks(c(bmt, alTrack), from = afrom, to = ato, chromosome = chrom, min.height = 0, coverageHeight = 0.08, minCoverageHeight = 0)
    
    plotTracks(c(alTrack, bmt), from = afrom, to = ato, chromosome = chrom, type = "coverage")
    
    zoom_from <- as.integer(afrom + span * 0.25)
    zoom_to <- as.integer(ato - span * 0.25)
    plotTracks(c(bmt, alTrack), from = zoom_from, to = zoom_to, chromosome = chrom, type = c("coverage", "sashimi"))
    
    # Close the plotting device
    dev.off()
    
    # Save the constructed AlignmentsTrack object to an RDS file for downstream use
    saveRDS(alTrack, "alignments_track.rds")

    writeLines(c(
        '"BIOC_GVIZ_SEQUENCE_ALIGNMENT_VISUALIZATION":',
        paste0('    Gviz: ', as.character(packageVersion('Gviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_alignment_visualization.csv versions.yml
    """
}

workflow BIOC_GVIZ_SEQUENCE_ALIGNMENT_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gapped.bam ] ]

    main:
    BIOC_GVIZ_SEQUENCE_ALIGNMENT_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GVIZ_SEQUENCE_ALIGNMENT_VISUALIZATION.out.tables
    plots    = BIOC_GVIZ_SEQUENCE_ALIGNMENT_VISUALIZATION.out.plots
    objects  = BIOC_GVIZ_SEQUENCE_ALIGNMENT_VISUALIZATION.out.objects
    versions = BIOC_GVIZ_SEQUENCE_ALIGNMENT_VISUALIZATION.out.versions
}
