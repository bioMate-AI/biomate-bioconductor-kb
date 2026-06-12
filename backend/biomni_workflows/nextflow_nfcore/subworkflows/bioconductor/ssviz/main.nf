#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ssviz — small_rna_distribution_analysis
// Load small RNA-seq BAM files, extract collapsed read counts, and visualize read length distributions and genomic region densities.
// Input: file1.bam, file2.bam
// Container: quay.io/biocontainers/bioconductor-ssviz:1.44.0--r45hdfd78af_0
// R packages: ssviz
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ssviz:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("ssviz")
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
    library(ssviz)
    
    # --- Identify and load BAM files ---
    # The pipeline reads exactly these files from the working directory
    file1 <- "file1.bam"
    file2 <- "file2.bam"
    
    ctrlbam <- readBam(file1)
    treatbam <- readBam(file2)
    
    # --- Extract collapsed read counts and append them to the data ---
    ctrl.count <- getCountMatrix(ctrlbam)
    treat.count <- getCountMatrix(treatbam)
    
    # Save the count matrices to disk
    write.csv(as.data.frame(ctrl.count), "control_counts.csv", row.names = FALSE)
    write.csv(as.data.frame(treat.count), "treatment_counts.csv", row.names = FALSE)
    saveRDS(ctrl.count, "control_counts.rds")
    saveRDS(treat.count, "treatment_counts.rds")
    
    # Define the total mapped reads (counts) for normalization
    # We calculate this from the extracted counts column
    counts <- c(sum(ctrl.count\$counts, na.rm = TRUE), sum(treat.count\$counts, na.rm = TRUE))
    
    # --- Plot read length distribution for single or multiple ---
    # Plot single dataset (Control)
    pdf("plot_distro_control.pdf")
    plotDistro(list(ctrl.count), type = "qwidth", samplenames = c("Control"), ncounts = counts[1])
    dev.off()
    
    # Plot multiple datasets (Control vs Treatment)
    pdf("plot_distro_comparison.pdf")
    plotDistro(list(ctrl.count, treat.count), type = "qwidth", samplenames = c("Control", "Treatment"), ncounts = counts)
    dev.off()
    
    # --- Plot read density over a specific genomic region ---
    region <- 'chr1:3015526-3080526'
    pdf("plot_region_density.pdf")
    plotRegion(list(ctrl.count), region = region)
    dev.off()

    writeLines(c(
        '"BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS":',
        paste0('        ssviz: ', as.character(packageVersion("ssviz")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_small_rna_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file1.bam, file2.bam ] ]

    main:
    BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS.out.versions
}
