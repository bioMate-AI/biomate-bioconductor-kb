#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chimeraviz — supporting_reads_alignment_and_plotting
// Extract and align supporting RNA-seq reads to a custom fusion junction reference sequence and visualize the alignment.
// Input: defuse_833ke_results.filtered.tsv, reads_supporting_defuse_fusion_5267.1.fq, reads_supporting_defuse_fusion_5267.2.fq
// Container: quay.io/biocontainers/bioconductor-chimeraviz:1.36.0--r45hdfd78af_0
// R packages: chimeraviz
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIMERAVIZ_SUPPORTING_READS_ALIGNMENT_AND_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chimeraviz:1.36.0--r45hdfd78af_0"

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
    .bm_deps <- c("chimeraviz")
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
    
    # Load chimeraviz library
    library(chimeraviz)
    
    # Define input files from the working directory
    defuse833ke <- "defuse_833ke_results.filtered.tsv"
    fastq1 <- "reads_supporting_defuse_fusion_5267.1.fq"
    fastq2 <- "reads_supporting_defuse_fusion_5267.2.fq"
    
    # 1. Import fusion data and select the target fusion event
    fusions <- import_defuse(defuse833ke, "hg19", 1)
    fusion <- get_fusion_by_id(fusions, 5267)
    
    # 2. Write the fusion junction reference sequence to a FASTA file
    referenceFilename <- "reference.fa"
    reference_filename <- "reference.fa" # Define both to ensure compatibility with documented code variables
    write_fusion_reference(fusion = fusion, filename = referenceFilename)
    
    # 3. Source alignment wrapper scripts and align supporting reads to the reference
    # Using find.package to locate the script without using system.file
    rsubread_script <- file.path(find.package("chimeraviz"), "scripts", "rsubread.R")
    source(rsubread_script)
    
    # Create index
    rsubread_index(reference_fasta = reference_filename)
    
    # Align reads
    rsubread_align(
      reference_name = reference_filename,
      fastq1 = fastq1,
      fastq2 = fastq2,
      output_bam_filename = "fusion_alignment")
    
    # 4. Add the resulting BAM alignment to the Fusion object
    bamfile5267 <- "fusion_alignment.bam"
    fusion <- add_fusion_reads_alignment(fusion, bamfile5267)
    
    # 5. Plot the aligned supporting reads across the fusion junction and save to PDF
    pdf("fusion_reads_plot.pdf", width = 12, height = 6)
    plot_fusion_reads(fusion)
    dev.off()
    
    # Save the final fusion object as an RDS file
    saveRDS(fusion, "fusion_object.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHIMERAVIZ_SUPPORTING_READS_ALIGNMENT_AND_PLOTTING":
        chimeraviz: \$(Rscript -e 'cat(as.character(packageVersion("chimeraviz")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supporting_reads_alignment_and_plotting.csv versions.yml
    """
}

workflow BIOC_CHIMERAVIZ_SUPPORTING_READS_ALIGNMENT_AND_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ defuse_833ke_results.filtered.tsv, reads_supporting_defuse_fusion_5267.1.fq, reads_supporting_defuse_fusion_5267.2.fq ] ]

    main:
    BIOC_CHIMERAVIZ_SUPPORTING_READS_ALIGNMENT_AND_PLOTTING(ch_input)

    emit:
    tables   = BIOC_CHIMERAVIZ_SUPPORTING_READS_ALIGNMENT_AND_PLOTTING.out.tables
    plots    = BIOC_CHIMERAVIZ_SUPPORTING_READS_ALIGNMENT_AND_PLOTTING.out.plots
    objects  = BIOC_CHIMERAVIZ_SUPPORTING_READS_ALIGNMENT_AND_PLOTTING.out.objects
    versions = BIOC_CHIMERAVIZ_SUPPORTING_READS_ALIGNMENT_AND_PLOTTING.out.versions
}
