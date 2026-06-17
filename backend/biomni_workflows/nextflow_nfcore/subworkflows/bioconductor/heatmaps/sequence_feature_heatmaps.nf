#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: heatmaps — sequence_feature_heatmaps
// Plot heatmaps of sequence features (k-mer occurrences or PWM match scores) across genomic windows, applying smoothing to handle data sparsity.
// Input: genomic_intervals.bed, reference_genome, pwm_matrix
// Container: quay.io/biocontainers/bioconductor-heatmaps:1.34.0--r45hdfd78af_0
// R packages: Biostrings, GenomicRanges, heatmaps, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GenomicRanges, heatmaps, rtracklayer
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import genomic intervals and define centered genomic windows
//  * 2. [Core Analysis] Extract DNA sequences using getSeq
//  * 3. [Visualization & Output] Generate pattern heatmaps for k-mers or PWMs using PatternHeatmap or PWMScanHeatmap
//  * 4. [Visualization & Output] Smooth the sparse/binary heatmap using smoothHeatmap
//  * 5. [Visualization & Output] Plot individual or grouped heatmaps using plotHeatmapList

nextflow.enable.dsl = 2

process BIOC_HEATMAPS_SEQUENCE_FEATURE_HEATMAPS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "GenomicRanges", "heatmaps", "rtracklayer")
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
        library(heatmaps)
        library(rtracklayer)
        library(GenomicRanges)
        library(Biostrings)
        
        # 1. Import genomic intervals and define centered genomic windows
        # Read the reference genome (BSgenome object) from the working directory
        Drerio = readRDS("reference_genome")
        
        # Import the genomic intervals BED file
        zf_30p_promoters = import("genomic_intervals.bed", genome=seqinfo(Drerio))
        
        # Define coordinates and genomic windows
        coords = c(-500, 500)
        windows_30p = promoters(zf_30p_promoters, -coords[1], coords[2])
        windows_30p = windows_30p[width(trim(windows_30p)) == 1000]
        
        # 2. Extract DNA sequences using getSeq
        seq_30p = getSeq(Drerio, windows_30p)
        
        # Set up PDF device to capture all plots
        pdf("sequence_feature_heatmaps.pdf", width=10, height=8)
        
        # 3. Generate pattern heatmaps for k-mers or PWMs using PatternHeatmap or PWMScanHeatmap
        ta_30p = PatternHeatmap(seq_30p, "TA", coords=coords)
        plotHeatmapList(ta_30p)
        
        # 4. Smooth the sparse/binary heatmap using smoothHeatmap
        ta_30p_smoothed = smoothHeatmap(ta_30p, output.size=c(250, 500), algorithm="kernel")
        plotHeatmapList(ta_30p_smoothed)
        
        # Read the Position Weight Matrix (PWM) from the working directory
        tata_pwm = readRDS("pwm_matrix")
        
        tata_pwm_30p = PatternHeatmap(seq_30p, tata_pwm, coords=coords, label="TATA", min.score="60%")
        plotHeatmapList(smoothHeatmap(tata_pwm_30p, output.size=c(250, 500)))
        
        tata_pwm_scan_30p = PWMScanHeatmap(seq_30p, tata_pwm, coords=coords, label="TATA")
        tata_pwm_scan_30p_smoothed = smoothHeatmap(tata_pwm_scan_30p, algorithm="blur", output.size=c(250, 500))
        scale(tata_pwm_scan_30p_smoothed) = c(40, 60)
        plotHeatmapList(tata_pwm_scan_30p_smoothed, color="Spectral", legend=TRUE, legend.width=0.3)
        
        cg_30p = PatternHeatmap(seq_30p, "CG", coords=coords)
        cg_30p_smoothed = smoothHeatmap(cg_30p, output.size=c(250, 500))
        
        # 5. Plot individual or grouped heatmaps using plotHeatmapList
        hm_list = list(
            ta_30p_smoothed,
            cg_30p_smoothed,
            tata_pwm_scan_30p_smoothed
        )
        
        plotHeatmapList(hm_list,
                        groups=c(1, 1, 2),
                        color=list("Blues", "Spectral"),
                        cex.label=list(2, 2))
        
        # Close the PDF device
        dev.off()
        
        # Save

    writeLines(c(
        '"BIOC_HEATMAPS_SEQUENCE_FEATURE_HEATMAPS":',
        paste0('    heatmaps: ', as.character(packageVersion('heatmaps')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_feature_heatmaps.csv versions.yml
    """
}

workflow BIOC_HEATMAPS_SEQUENCE_FEATURE_HEATMAPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomic_intervals.bed, reference_genome, pwm_matrix ] ]

    main:
    BIOC_HEATMAPS_SEQUENCE_FEATURE_HEATMAPS(ch_input)

    emit:
    tables   = BIOC_HEATMAPS_SEQUENCE_FEATURE_HEATMAPS.out.tables
    plots    = BIOC_HEATMAPS_SEQUENCE_FEATURE_HEATMAPS.out.plots
    objects  = BIOC_HEATMAPS_SEQUENCE_FEATURE_HEATMAPS.out.objects
    versions = BIOC_HEATMAPS_SEQUENCE_FEATURE_HEATMAPS.out.versions
}
