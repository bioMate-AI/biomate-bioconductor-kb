#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chimeraviz — fusion_reads_alignment_and_plotting
// Align supporting RNA-seq reads to a custom fusion junction reference sequence and visualize the alignment.
// Input: defuse_833ke_results.filtered.tsv, reads_supporting_defuse_fusion_5267.1.fq, reads_supporting_defuse_fusion_5267.2.fq
// Container: quay.io/biocontainers/bioconductor-chimeraviz:1.36.0--r45hdfd78af_0
// R packages: chimeraviz
// Bioconductor: 3.20 | R: 4.4
// Requires: chimeraviz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import fusion data using import_defuse
//  * 2. [Core Analysis] Retrieve specific fusion by ID using get_fusion_by_id
//  * 3. [Visualization & Output] Write fusion junction reference FASTA using write_fusion_reference
//  * 4. [Core Analysis] Align reads using Rsubread wrapper functions rsubread_index and rsubread_align
//  * 5. [Core Analysis] Add BAM alignment to Fusion object using add_fusion_reads_alignment
//  * 6. [Visualization & Output] Plot fusion reads using plot_fusion_reads

nextflow.enable.dsl = 2

process BIOC_CHIMERAVIZ_FUSION_READS_ALIGNMENT_AND_PLOTTING {
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
    
    # 1. Import fusion data using import_defuse
    # Read the user input file directly from the working directory
    defuse833ke <- "defuse_833ke_results.filtered.tsv"
    fusions <- import_defuse(defuse833ke, "hg19", 1)
    
    # 2. Retrieve specific fusion by ID using get_fusion_by_id
    fusion <- get_fusion_by_id(fusions, 5267)
    
    # Define paths to the user input FASTQ files in the working directory
    fastq1 <- "reads_supporting_defuse_fusion_5267.1.fq"
    fastq2 <- "reads_supporting_defuse_fusion_5267.2.fq"
    
    # 3. Write fusion junction reference FASTA using write_fusion_reference
    referenceFilename <- "reference.fa"
    write_fusion_reference(fusion = fusion, filename = referenceFilename)
    
    # Define reference_filename to match the variable name used in the alignment functions
    reference_filename <- referenceFilename
    
    # Source the rsubread wrapper script from the package installation directory (avoiding system.file)
    rsubread_script <- file.path(find.package("chimeraviz"), "scripts", "rsubread.R")
    source(rsubread_script)
    
    # 4. Align reads using Rsubread wrapper functions rsubread_index and rsubread_align
    rsubread_index(reference_fasta = reference_filename)
    rsubread_align(
      reference_name = reference_filename,
      fastq1 = fastq1,
      fastq2 = fastq2,
      output_bam_filename = "fusion_alignment"
    )
    
    # 5. Add BAM alignment to Fusion object using add_fusion_reads_alignment
    # Use the newly generated BAM file from the alignment step
    bamfile5267 <- "fusion_alignment.bam"
    fusion <- add_fusion_reads_alignment(fusion, bamfile5267)
    
    # 6. Plot fusion reads using plot_fusion_reads and save to a PDF file
    pdf("fusion_reads_plot.pdf", width = 12, height = 6)
    plot_fusion_reads(fusion)
    dev.off()
    
    # Save the final fusion object with alignment data as an RDS file
    saveRDS(fusion, "fusion_object_with_alignment.rds")

    writeLines(c(
        '"BIOC_CHIMERAVIZ_FUSION_READS_ALIGNMENT_AND_PLOTTING":',
        paste0('    chimeraviz: ', as.character(packageVersion('chimeraviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fusion_reads_alignment_and_plotting.csv versions.yml
    """
}

workflow BIOC_CHIMERAVIZ_FUSION_READS_ALIGNMENT_AND_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ defuse_833ke_results.filtered.tsv, reads_supporting_defuse_fusion_5267.1.fq, reads_supporting_defuse_fusion_5267.2.fq ] ]

    main:
    BIOC_CHIMERAVIZ_FUSION_READS_ALIGNMENT_AND_PLOTTING(ch_input)

    emit:
    tables   = BIOC_CHIMERAVIZ_FUSION_READS_ALIGNMENT_AND_PLOTTING.out.tables
    plots    = BIOC_CHIMERAVIZ_FUSION_READS_ALIGNMENT_AND_PLOTTING.out.plots
    objects  = BIOC_CHIMERAVIZ_FUSION_READS_ALIGNMENT_AND_PLOTTING.out.objects
    versions = BIOC_CHIMERAVIZ_FUSION_READS_ALIGNMENT_AND_PLOTTING.out.versions
}
