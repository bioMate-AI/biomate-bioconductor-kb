#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ontoProc — map_and_subset_single_cell_data
// Map informal cell type labels in a SingleCellExperiment to formal Cell Ontology tags and subset the dataset to descendants of a specific cell type.
// Input: hpca_sce, hpca.csv
// Container: quay.io/biocontainers/bioconductor-ontoproc:2.4.0--r45hdfd78af_0
// R packages: SingleCellExperiment, SummarizedExperiment, ontoProc
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, SummarizedExperiment, ontoProc
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the mapping file from the working directory
//  * 2. [Input & Preparation] Load the SingleCellExperiment object from the working
//  * 3. [Input & Preparation] Load the Cell Ontology (2023 version)
//  * 4. [Input & Preparation] Subset the SingleCellExperiment to descendants of the

nextflow.enable.dsl = 2

process BIOC_ONTOPROC_MAP_AND_SUBSET_SINGLE_CELL_DATA {
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
    .bm_deps <- c("SingleCellExperiment", "SummarizedExperiment", "ontoProc")
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
    library(ontoProc)
    
    # --- Load the mapping file from the working directory ---
    if (file.exists("hpca.csv")) {
      hpca_map = read.csv("hpca.csv", stringsAsFactors = FALSE)
    } else {
      stop("Required input file 'hpca.csv' not found in the working directory.")
    }
    
    # Rename columns to "informal" and "formal" as required by bind_formal_tags
    names(hpca_map) = c("informal", "formal")
    
    # --- Load the SingleCellExperiment object from the working ---
    if (file.exists("hpca_sce")) {
      hpca_sce = readRDS("hpca_sce")
    } else if (file.exists("hpca_sce.rds")) {
      hpca_sce = readRDS("hpca_sce.rds")
    } else {
      stop("Required input file 'hpca_sce' or 'hpca_sce.rds' not found in the working directory.")
    }
    
    # Bind formal ontology tags to the SingleCellExperiment object
    hpca_sce = bind_formal_tags(hpca_sce, "label.fine", hpca_map)
    
    # --- Load the Cell Ontology (2023 version) ---
    cell_onto = ontoProc::getOnto("cellOnto", "2023")
    
    # --- Subset the SingleCellExperiment to descendants of the ---
    hpca_mono = subset_descendants( hpca_sce, cell_onto, "^monocyte\$" )
    
    # Save the resulting subsetted SingleCellExperiment object
    saveRDS(hpca_mono, "hpca_mono.rds")
    
    # Save the metadata of the subsetted cells as a CSV table
    write.csv(as.data.frame(SummarizedExperiment::colData(hpca_mono)), "hpca_mono_metadata.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_ONTOPROC_MAP_AND_SUBSET_SINGLE_CELL_DATA":',
        paste0('    ontoProc: ', as.character(packageVersion('ontoProc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_map_and_subset_single_cell_data.csv versions.yml
    """
}

workflow BIOC_ONTOPROC_MAP_AND_SUBSET_SINGLE_CELL_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hpca_sce, hpca.csv ] ]

    main:
    BIOC_ONTOPROC_MAP_AND_SUBSET_SINGLE_CELL_DATA(ch_input)

    emit:
    tables   = BIOC_ONTOPROC_MAP_AND_SUBSET_SINGLE_CELL_DATA.out.tables
    plots    = BIOC_ONTOPROC_MAP_AND_SUBSET_SINGLE_CELL_DATA.out.plots
    objects  = BIOC_ONTOPROC_MAP_AND_SUBSET_SINGLE_CELL_DATA.out.objects
    versions = BIOC_ONTOPROC_MAP_AND_SUBSET_SINGLE_CELL_DATA.out.versions
}
