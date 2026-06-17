#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MOSim — single_cell_multi_omics_simulation
// Simulate single-cell multi-omics data (scRNA-seq and scATAC-seq) with custom cell types and regulatory associations.
// Input: Seurat_obj, associationList.csv
// Container: quay.io/biocontainers/bioconductor-mosim:2.6.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MOSim, Seurat
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format input data using sc_omicData
//  * 2. [Input & Preparation] Define cell types and load association lists
//  * 3. [Core Analysis] Run single-cell simulation using sc_mosim
//  * 4. [Core Analysis] Retrieve settings and results using sc_omicSettings and sc_omicResults

nextflow.enable.dsl = 2

process BIOC_MOSIM_SINGLE_CELL_MULTI_OMICS_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("MOSim", "Seurat")
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
        library(MOSim)
        library(Seurat)
        
        # ==========================================
        # 1. READ USER INPUTS
        # ==========================================
        # Read the association list containing peak IDs related to gene names
        associationList <- read.csv("associationList.csv", stringsAsFactors = FALSE)
        
        # Read the Seurat object containing single-cell count data
        Seurat_obj <- readRDS("Seurat_obj.rds")
        
        # ==========================================
        # 2. STAGE 1 & 2: FORMAT INPUT DATA & DEFINE CELL TYPES
        # ==========================================
        # Set Seurat object assay version option as documented
        options(Seurat.object.assay.version = "v3")
        
        # Format the multi-omics list structure using the user's Seurat object
        omicsList <- sc_omicData(list("scRNA-seq", "scATAC-seq"), data = list(Seurat_obj, Seurat_obj))
        
        # Define cell types for the experiment dynamically from the Seurat object
        cell_types <- split(seq_len(ncol(Seurat_obj)), Idents(Seurat_obj))
        
        # ==========================================
        # 3. STAGE 3: RUN SINGLE-CELL SIMULATION
        # ==========================================
        # Simulate multi-omics data with specific parameters using the user's association list
        # and combine into a single simulation with TF enabled
        testing_groups <- sc_mosim(
          omicsList,
          cell_types,
          numberReps = 2,
          numberGroups = 3,
          diffGenes = list(c(0.2, 0.3), c(0.2, 0.3)),
          minFC = 0.25,
          maxFC = 4,
          numberCells = NULL,
          mean = NULL,
          sd = NULL,
          regulatorEffect = list(c(0.1, 0.2), c(0.1, 0.2), c(0.1, 0.2)),
          associationList = associationList,
          TF = TRUE
        )
        
        # Assign to sim to match the rest of the script
        sim <- testing_groups
        
        # ==========================================
        # 4. STAGE 4: RETRIEVE SETTINGS AND RESULTS
        # ==========================================
        # Retrieve standard simulation settings
        settings <- sc_omicSettings(sim)
        
        # Retrieve simulation settings including TF regulatory relationships
        settings_tf <- sc_omicSettings(sim, TF = TRUE)
        
        # Extract the simulated count matrices/results
        res <- sc_omicResults(sim)
        
        # ==========================================
        # 5. WRITE OUTPUT FILES
        # ==========================================
        # Save the simulation objects
        saveRDS(testing_groups, "testing_groups_simulation.rds")
        saveRDS(sim, "sc_simulation_object.rds")
        
        # Save the retrieved settings
        saveRDS(settings, "sc_simulation_settings.rds")
        saveRDS(settings_tf, "sc_simulation_settings_tf.rds")
        
        # Save the final simulated results (Seurat objects containing synthetic counts)
        saveRDS(res, "sc_simulation_results.rds")

    writeLines(c(
        '"BIOC_MOSIM_SINGLE_CELL_MULTI_OMICS_SIMULATION":',
        paste0('    MOSim: ', as.character(packageVersion('MOSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_multi_omics_simulation.csv versions.yml
    """
}

workflow BIOC_MOSIM_SINGLE_CELL_MULTI_OMICS_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Seurat_obj, associationList.csv ] ]

    main:
    BIOC_MOSIM_SINGLE_CELL_MULTI_OMICS_SIMULATION(ch_input)

    emit:
    tables   = BIOC_MOSIM_SINGLE_CELL_MULTI_OMICS_SIMULATION.out.tables
    plots    = BIOC_MOSIM_SINGLE_CELL_MULTI_OMICS_SIMULATION.out.plots
    objects  = BIOC_MOSIM_SINGLE_CELL_MULTI_OMICS_SIMULATION.out.objects
    versions = BIOC_MOSIM_SINGLE_CELL_MULTI_OMICS_SIMULATION.out.versions
}
