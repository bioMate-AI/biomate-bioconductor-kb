#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genega — joint_codon_and_structure_optimization
// Optimize a gene sequence considering both codon usage bias and mRNA secondary structure using a genetic algorithm.
// Input: EGFP.fasta
// Container: quay.io/biocontainers/bioconductor-genega:1.60.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEGA_JOINT_CODON_AND_STRUCTURE_OPTIMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genega:1.60.0--r45hdfd78af_0"

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
    .bm_deps <- c("genega", "seqinr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(GeneGA)
    library(seqinr)
    
    # 1. Read the sequence from the FASTA file in the working directory
    seqfile <- "EGFP.fasta"
    if (!file.exists(seqfile)) {
      stop("Error: Input file 'EGFP.fasta' not found in the working directory.")
    }
    
    seq <- unlist(getSequence(read.fasta(seqfile), as.string = TRUE))
    
    # 2. Run the genetic algorithm optimization using GeneGA
    # (Using exact arguments from the documented vignette)
    GeneGA.result <- GeneGA(
      sequence = seq,
      popSize = 40,
      iters = 150,
      crossoverRate = 0.3,
      mutationChance = 0.05,
      region = c(1, 60),
      organism = "ec",
      showGeneration = FALSE
    )
    
    # 3. Display and save the optimized sequences and their evaluation metrics
    # Save the console output of show() to a text file
    sink("GeneGA_summary.txt")
    show(GeneGA.result)
    sink()
    
    # Also print to standard output
    show(GeneGA.result)
    
    # Save the GeneGA result object as an RDS file
    saveRDS(GeneGA.result, file = "GeneGA_result.rds")
    
    # 4. Plot the optimization progress (CAI, Free Energy, and joint distribution)
    # Save the plots to a PDF file
    pdf("GeneGA_plots.pdf", width = 7, height = 7)
    plotGeneGA(GeneGA.result, type = 1)
    plotGeneGA(GeneGA.result, type = 2)
    plotGeneGA(GeneGA.result, type = 3)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GENEGA_JOINT_CODON_AND_STRUCTURE_OPTIMIZATION":
        genega: \$(Rscript -e 'cat(as.character(packageVersion("genega")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_joint_codon_and_structure_optimization.csv versions.yml
    """
}

workflow BIOC_GENEGA_JOINT_CODON_AND_STRUCTURE_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ EGFP.fasta ] ]

    main:
    BIOC_GENEGA_JOINT_CODON_AND_STRUCTURE_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_GENEGA_JOINT_CODON_AND_STRUCTURE_OPTIMIZATION.out.tables
    plots    = BIOC_GENEGA_JOINT_CODON_AND_STRUCTURE_OPTIMIZATION.out.plots
    objects  = BIOC_GENEGA_JOINT_CODON_AND_STRUCTURE_OPTIMIZATION.out.objects
    versions = BIOC_GENEGA_JOINT_CODON_AND_STRUCTURE_OPTIMIZATION.out.versions
}
