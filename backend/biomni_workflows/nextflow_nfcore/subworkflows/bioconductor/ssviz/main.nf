#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ssviz — small_rna_distribution_analysis
// Load small RNA-seq BAM files, extract collapsed read counts, and visualize read length distributions and genomic region densities.
// Input: file1.bam, file2.bam
// Container: quay.io/biocontainers/bioconductor-ssviz:1.44.0--r45hdfd78af_0
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ssviz)
    
    # 1. Identify and load BAM files
    # The pipeline reads exactly these files from the working directory
    file1 <- "file1.bam"
    file2 <- "file2.bam"
    
    ctrlbam <- readBam(file1)
    treatbam <- readBam(file2)
    
    # 2. Extract collapsed read counts and append them to the data frame
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
    
    # 3. Plot read length distribution for single or multiple datasets
    # Plot single dataset (Control)
    pdf("plot_distro_control.pdf")
    plotDistro(list(ctrl.count), type = "qwidth", samplenames = c("Control"), ncounts = counts[1])
    dev.off()
    
    # Plot multiple datasets (Control vs Treatment)
    pdf("plot_distro_comparison.pdf")
    plotDistro(list(ctrl.count, treat.count), type = "qwidth", samplenames = c("Control", "Treatment"), ncounts = counts)
    dev.off()
    
    # 4. Plot read density over a specific genomic region
    region <- 'chr1:3015526-3080526'
    pdf("plot_region_density.pdf")
    plotRegion(list(ctrl.count), region = region)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SSVIZ_SMALL_RNA_DISTRIBUTION_ANALYSIS":
        ssviz: \$(Rscript -e 'cat(as.character(packageVersion("ssviz")))')
    END_VERSIONS
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
