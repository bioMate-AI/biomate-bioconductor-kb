#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msa — phylogenetic_tree_reconstruction
// Convert a multiple sequence alignment to a seqinr alignment object, calculate identity distances, and reconstruct a neighbor-joining phylogenetic tree.
// Input: HemoglobinAA.fasta
// Container: quay.io/biocontainers/bioconductor-msa:1.42.0--r45he8cd136_0
// R packages: ape, msa, seqinr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSA_PHYLOGENETIC_TREE_RECONSTRUCTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msa:1.42.0--r45he8cd136_0"

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
    .bm_deps <- c("ape", "msa", "seqinr")
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
    library(msa)
    library(seqinr)
    library(ape)
    
    # --- Read and align sequences ---
    # Read the user-provided FASTA file from the working directory
    hemoSeq <- readAAStringSet("HemoglobinAA.fasta")
    
    # Perform multiple sequence alignment
    hemoAln <- msa(hemoSeq)
    
    # --- Convert the alignment to seqinr format using msaConvert ---
    hemoAln2 <- msaConvert(hemoAln, type="seqinr::alignment")
    
    # --- Compute a distance matrix using dist.alignment from seqinr ---
    d <- dist.alignment(hemoAln2, "identity")
    
    # Save the distance matrix as a CSV file
    write.csv(as.matrix(d), "hemoglobin_distance_matrix.csv", row.names = TRUE)
    
    # --- Reconstruct a neighbor-joining tree using nj from ape ---
    hemoTree <- nj(d)
    
    # Save the phylogenetic tree object in RDS format and Newick format
    saveRDS(hemoTree, "hemoglobin_tree.rds")
    write.tree(hemoTree, file = "hemoglobin_tree.nwk")
    
    # --- Plot the phylogenetic tree and save as a PDF ---
    pdf("hemoglobin_phylogenetic_tree.pdf", width = 10, height = 8)
    plot(hemoTree, main="Phylogenetic Tree of Hemoglobin Alpha Sequences")
    dev.off()

    writeLines(c(
        '"BIOC_MSA_PHYLOGENETIC_TREE_RECONSTRUCTION":',
        paste0('        msa: ', as.character(packageVersion("msa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phylogenetic_tree_reconstruction.csv versions.yml
    """
}

workflow BIOC_MSA_PHYLOGENETIC_TREE_RECONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HemoglobinAA.fasta ] ]

    main:
    BIOC_MSA_PHYLOGENETIC_TREE_RECONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_MSA_PHYLOGENETIC_TREE_RECONSTRUCTION.out.tables
    plots    = BIOC_MSA_PHYLOGENETIC_TREE_RECONSTRUCTION.out.plots
    objects  = BIOC_MSA_PHYLOGENETIC_TREE_RECONSTRUCTION.out.objects
    versions = BIOC_MSA_PHYLOGENETIC_TREE_RECONSTRUCTION.out.versions
}
