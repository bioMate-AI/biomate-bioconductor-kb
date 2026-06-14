#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LinTInd — lineage_reconstruction
// Reconstruct a lineage tree and visualize indel patterns from CRISPR-edited amplicon sequencing data.
// Input: reads.fastq, reference.fasta
// Container: quay.io/biocontainers/bioconductor-lintind:1.10.0--r44hdfd78af_0
// R packages: LinTInd
// Bioconductor: 3.20 | R: 4.4
// Requires: LinTInd
// Visualizations: phylogenetic tree
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify indels from sequencing reads using FindIndel()
//  * 2. [Core Analysis] Generate allele profiles from identified indels using IndelForm()
//  * 3. [Core Analysis] Reconstruct the lineage tree using BuildTree()
//  * 4. [Visualization & Output] Visualize the reconstructed lineage tree using PlotTree()
//  * 5. [Visualization & Output] Plot the indel alignment patterns using IndelPlot()

nextflow.enable.dsl = 2

process BIOC_LINTIND_LINEAGE_RECONSTRUCTION {
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
    .bm_deps <- c("LinTInd")
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
    
    # Check if input files exist
    if (!file.exists("reads.fastq")) {
      stop("Error: Input file 'reads.fastq' not found in the working directory.")
    }
    if (!file.exists("reference.fasta")) {
      stop("Error: Input file 'reference.fasta' not found in the working directory.")
    }
    
    # Load the required package
    library(LinTInd)
    
    # 1. Identify indels from sequencing reads using FindIndel()
    message("Step 1: Identifying indels from sequencing reads...")
    indels <- FindIndel(fq = "reads.fastq", ref = "reference.fasta", cutsite = 17)
    saveRDS(indels, file = "indels.rds")
    
    # 2. Generate allele profiles from identified indels using IndelForm()
    message("Step 2: Generating allele profiles...")
    allele_table <- IndelForm(indels)
    write.csv(allele_table, file = "allele_table.csv", row.names = FALSE)
    
    # 3. Reconstruct the lineage tree using BuildTree()
    message("Step 3: Reconstructing the lineage tree...")
    tree <- BuildTree(allele_table)
    saveRDS(tree, file = "tree.rds")
    
    # 4. Visualize the reconstructed lineage tree using PlotTree()
    message("Step 4: Plotting the lineage tree...")
    pdf("tree_plot.pdf", width = 10, height = 8)
    PlotTree(tree)
    dev.off()
    
    # 5. Plot the indel alignment patterns using IndelPlot()
    message("Step 5: Plotting indel alignment patterns...")
    pdf("indel_plot.pdf", width = 12, height = 8)
    IndelPlot(allele_table)
    dev.off()
    
    message("Workflow completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_LINTIND_LINEAGE_RECONSTRUCTION":',
        paste0('    LinTInd: ', as.character(packageVersion('LinTInd')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lineage_reconstruction.csv versions.yml
    """
}

workflow BIOC_LINTIND_LINEAGE_RECONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reads.fastq, reference.fasta ] ]

    main:
    BIOC_LINTIND_LINEAGE_RECONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_LINTIND_LINEAGE_RECONSTRUCTION.out.tables
    plots    = BIOC_LINTIND_LINEAGE_RECONSTRUCTION.out.plots
    objects  = BIOC_LINTIND_LINEAGE_RECONSTRUCTION.out.objects
    versions = BIOC_LINTIND_LINEAGE_RECONSTRUCTION.out.versions
}
