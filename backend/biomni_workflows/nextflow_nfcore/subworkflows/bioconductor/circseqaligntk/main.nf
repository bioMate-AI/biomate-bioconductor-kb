#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: circseqaligntk — circular_genome_alignment_and_coverage
// Align small RNA-Seq reads to a circular reference genome using a two-stage alignment process, calculate strand-specific coverage, and visualize the coverage pro
// Input: genome_seq.fa, trimmed_reads.fq
// Container: quay.io/biocontainers/bioconductor-circseqaligntk:1.12.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CIRCSEQALIGNTK_CIRCULAR_GENOME_ALIGNMENT_AND_COVERAGE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-circseqaligntk:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("circseqaligntk", "ggplot2", "rbowtie2", "shiny")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(CircSeqAlignTk)
    
    # Define working directory and input file paths
    ws <- getwd()
    genome_seq <- file.path(ws, "genome_seq.fa")
    trimmed_fq <- file.path(ws, "trimmed_reads.fq")
    
    # Validate that the required user input files exist
    if (!file.exists(genome_seq)) {
      stop("Required input file 'genome_seq.fa' is missing from the working directory.")
    }
    if (!file.exists(trimmed_fq)) {
      stop("Required input file 'trimmed_reads.fq' is missing from the working directory.")
    }
    
    # Create output directories if they do not exist
    dir.create(file.path(ws, 'index'), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(ws, 'align_results'), recursive = TRUE, showWarnings = FALSE)
    
    # 1. Build circular-aware index files (Type 1 and Type 2 references)
    message("Building circular-aware index...")
    ref_index <- build_index(input = genome_seq, 
                             output = file.path(ws, 'index'))
    
    # 2. Align trimmed reads to the generated index
    message("Aligning reads...")
    aln <- align_reads(input = trimmed_fq, 
                       index = ref_index,
                       output = file.path(ws, 'align_results'))
    
    # 3. Calculate strand-specific coverage from the alignment results
    message("Calculating coverage...")
    alncov <- calc_coverage(aln)
    
    # Display preview of the coverage data
    message("Forward strand coverage preview:")
    print(head(slot(alncov, 'forward')))
    
    message("Reverse strand coverage preview:")
    print(head(slot(alncov, 'reverse')))
    
    # 4. Write meaningful results to output files
    message("Saving results...")
    
    # Save coverage tables as CSV
    write.csv(as.data.frame(slot(alncov, 'forward')), 
              file = file.path(ws, "coverage_forward.csv"), 
              row.names = FALSE)
    write.csv(as.data.frame(slot(alncov, 'reverse')), 
              file = file.path(ws, "coverage_reverse.csv"), 
              row.names = FALSE)
    
    # Save the coverage object as an RDS file
    saveRDS(alncov, file = file.path(ws, "coverage_object.rds"))
    
    # Visualize the coverage profile and save as PDF
    pdf(file = file.path(ws, "coverage_profile.pdf"), width = 10, height = 6)
    plot(alncov)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CIRCSEQALIGNTK_CIRCULAR_GENOME_ALIGNMENT_AND_COVERAGE":
        circseqaligntk: \$(Rscript -e 'cat(as.character(packageVersion("circseqaligntk")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_circular_genome_alignment_and_coverage.csv versions.yml
    """
}

workflow BIOC_CIRCSEQALIGNTK_CIRCULAR_GENOME_ALIGNMENT_AND_COVERAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome_seq.fa, trimmed_reads.fq ] ]

    main:
    BIOC_CIRCSEQALIGNTK_CIRCULAR_GENOME_ALIGNMENT_AND_COVERAGE(ch_input)

    emit:
    tables   = BIOC_CIRCSEQALIGNTK_CIRCULAR_GENOME_ALIGNMENT_AND_COVERAGE.out.tables
    plots    = BIOC_CIRCSEQALIGNTK_CIRCULAR_GENOME_ALIGNMENT_AND_COVERAGE.out.plots
    objects  = BIOC_CIRCSEQALIGNTK_CIRCULAR_GENOME_ALIGNMENT_AND_COVERAGE.out.objects
    versions = BIOC_CIRCSEQALIGNTK_CIRCULAR_GENOME_ALIGNMENT_AND_COVERAGE.out.versions
}
