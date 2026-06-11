#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IMMAN — reconstruct_interlog_protein_network
// Reconstruct an integrated Interlog Protein Network (IPN) from protein lists of different species using sequence alignment and STRING database interactions.
// Input: ProteinLists, Species_IDs
// Container: quay.io/biocontainers/bioconductor-imman:1.30.0--r45hdfd78af_0
// R packages: IMMAN
// Bioconductor: 3.20 | R: 4.4
// Requires: IMMAN
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the IMMAN package and example datasets
//  * 2. [Input & Preparation] Define the list of proteins and their corresponding taxonomy IDs
//  * 3. [Core Analysis] Set alignment and network integration parameters
//  * 4. [Input & Preparation] Run the IMMAN function to download sequences, perform alignment, query STRING, and build the IPN
//  * 5. [Core Analysis] Extract and inspect the resulting IPN edges, nodes, species-specific networks, and UniProt-to-STRING mappings

nextflow.enable.dsl = 2

process BIOC_IMMAN_RECONSTRUCT_INTERLOG_PROTEIN_NETWORK {
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
    .bm_deps <- c("IMMAN")
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
    
    # 1. Load the IMMAN package
    library(IMMAN)
    
    # 2. Read the user input files from the working directory
    if (!file.exists("ProteinLists.rds") || !file.exists("Species_IDs.rds")) {
      stop("Required input files 'ProteinLists.rds' and/or 'Species_IDs.rds' not found in the working directory.")
    }
    
    ProteinLists <- readRDS("ProteinLists.rds")
    Species_IDs <- readRDS("Species_IDs.rds")
    
    # 3. Set alignment and network integration parameters
    identityU = 30
    substitutionMatrix = "BLOSUM62"
    gapOpening = -8
    gapExtension = -8
    NetworkShrinkage = FALSE
    coverage = 1
    BestHit = TRUE
    score_threshold = 400
    STRINGversion="11"
    
    # 4. Run the IMMAN function to download sequences, perform alignment, query STRING, and build the IPN
    output = IMMAN(ProteinLists, fileNames=NULL, Species_IDs,
                  identityU, substitutionMatrix,
                  gapOpening, gapExtension, BestHit,
                  coverage, NetworkShrinkage,
                  score_threshold, STRINGversion,
                  InputDirectory = getwd())
    
    # 5. Extract and inspect the resulting IPN edges, nodes, species-specific networks, and UniProt-to-STRING mappings
    output\$IPNEdges
    output\$IPNNodes
    output\$Networks
    output\$Networks[[1]]
    output\$maps
    output\$maps[[2]]
    
    # 6. Save outputs to files
    saveRDS(output, "IMMAN_output.rds")
    
    if (!is.null(output\$IPNEdges)) {
      write.csv(output\$IPNEdges, "IPNEdges.csv", row.names = FALSE)
    }
    
    if (!is.null(output\$IPNNodes)) {
      write.csv(output\$IPNNodes, "IPNNodes.csv", row.names = FALSE)
    }
    
    if (!is.null(output\$Networks)) {
      for (i in seq_along(output\$Networks)) {
        write.csv(output\$Networks[[i]], paste0("Network_species_", i, ".csv"), row.names = FALSE)
      }
    }
    
    if (!is.null(output\$maps)) {
      for (i in seq_along(output\$maps)) {
        write.csv(output\$maps[[i]], paste0("Map_species_", i, ".csv"), row.names = FALSE)
      }
    }

    writeLines(c(
        '"BIOC_IMMAN_RECONSTRUCT_INTERLOG_PROTEIN_NETWORK":',
        paste0('    IMMAN: ', as.character(packageVersion('IMMAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reconstruct_interlog_protein_network.csv versions.yml
    """
}

workflow BIOC_IMMAN_RECONSTRUCT_INTERLOG_PROTEIN_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ProteinLists, Species_IDs ] ]

    main:
    BIOC_IMMAN_RECONSTRUCT_INTERLOG_PROTEIN_NETWORK(ch_input)

    emit:
    tables   = BIOC_IMMAN_RECONSTRUCT_INTERLOG_PROTEIN_NETWORK.out.tables
    plots    = BIOC_IMMAN_RECONSTRUCT_INTERLOG_PROTEIN_NETWORK.out.plots
    objects  = BIOC_IMMAN_RECONSTRUCT_INTERLOG_PROTEIN_NETWORK.out.objects
    versions = BIOC_IMMAN_RECONSTRUCT_INTERLOG_PROTEIN_NETWORK.out.versions
}
