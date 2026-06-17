#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SimBu — custom_data_simulation
// Simulate pseudo-bulk RNA-seq data from custom single-cell count matrices or Seurat objects with controlled cell-type fractions and mRNA bias scaling.
// Input: counts_matrix, tpm_matrix, annotation_dataframe, seurat_obj
// Container: quay.io/biocontainers/bioconductor-simbu:1.12.0--r45hdfd78af_0
// R packages: BiocParallel, Matrix, SummarizedExperiment, curl, Seurat, SimBu
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Matrix, Seurat, SeuratObject, SimBu, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a SimBu dataset using dataset() or dataset_seurat()
//  * 2. [Core Analysis] Optionally merge multiple datasets using dataset_merge()
//  * 3. [Core Analysis] Simulate pseudo-bulk samples using simulate_bulk()
//  * 4. [Core Analysis] Optionally merge simulations using merge_simulations()
//  * 5. [Visualization & Output] Plot the simulation results using plot_simulation()

nextflow.enable.dsl = 2

process BIOC_SIMBU_CUSTOM_DATA_SIMULATION {
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
    .bm_deps <- c("BiocParallel", "Matrix", "SummarizedExperiment", "curl", "Seurat", "SimBu")
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
            library(SimBu)
            library(SummarizedExperiment)
            library(Seurat)
            library(BiocParallel)
            library(utils)
            library(Matrix)
            
            # Helper function to find and read user input files with various extensions
            find_and_read <- function(name, is_matrix = FALSE) {
              extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
              for (ext in extensions) {
                path <- paste0(name, ext)
                if (file.exists(path)) {
                  if (ext == ".rds") {
                    return(readRDS(path))
                  } else if (ext %in% c(".csv", ".tsv", ".txt")) {
                    sep <- if (ext == ".csv") "," else "\t"
                    df <- read.table(path, header = TRUE, sep = sep, row.names = 1, check.names = FALSE)
                    if (is_matrix) {
                      return(as.matrix(df))
                    }
                    return(df)
                  } else {
                    # Try reading as RDS first, then table
                    obj <- tryCatch(readRDS(path), error = function(e) NULL)
                    if (!is.null(obj)) return(obj)
                    df <- tryCatch(read.table(path, header = TRUE, row.names = 1, check.names = FALSE), error = function(e) NULL)
                    if (!is.null(df)) {
                      if (is_matrix) return(as.matrix(df))
                      return(df)
                    }
                  }
                }
              }
              return(NULL)
            }
            
            # Read user input files
            counts <- find_and_read("counts_matrix", is_matrix = TRUE)
            tpm <- find_and_read("tpm_matrix", is_matrix = TRUE)
            annotation <- find_and_read("annotation_dataframe", is_matrix = FALSE)
            seurat_obj <- find_and_read("seurat_obj", is_matrix = FALSE)
            
            # Validate mandatory inputs
            if (is.null(counts)) {
              stop("Mandatory input 'counts_matrix' not found in the working directory.")
            }
            if (is.null(annotation)) {
              stop("Mandatory input 'annotation_dataframe' not found in the working directory.")
            }
            
            # Ensure annotation has the required 'ID' column if it's in the row names
            if (!"ID" %in% colnames(annotation)) {
              annotation\$ID <- rownames(annotation)
            }
            
            # Reconstruct optional TPM matrix if missing
            if (is.null(tpm)) {
              message("Optional 'tpm_matrix' not found. Generating TPM-like matrix from 'counts_matrix'...")
              tpm <- t(1e6 * t(counts) / colSums(counts))
            }
            
            # Reconstruct optional Seurat object if missing
            if (is.null(seurat_obj)) {
              message("Optional 'seurat_obj' not found. Constructing Seurat object from 'counts_matrix' and 'annotation_dataframe'...")
              seurat_obj <- Seurat::CreateSeuratObject(counts = counts, assay = "gene_expression", meta.data = annotation)
              SeuratObject::LayerData(seurat_obj, assay = "gene_expression", layer = "data") <- tpm
            }
            
            # 1. Create SimBu datasets
            ds <- SimBu :: dataset ( annotation = annotation, count_matrix = counts, tpm_matrix = tpm, name = "test_dataset" )
            
            ds_seurat <- SimBu::dataset_seurat( seurat_obj = seurat_obj, counts_layer = "counts", cell_id_col = "ID", cell_type_col = "cell_type", tpm_layer = "data", name = "seurat_dataset" )
            
            # 2. Merge datasets
            ds_multiple <- SimBu::dataset_merge( dataset_list = list(ds_seurat, ds), name = "ds_multiple" )
            
            # 3. Simulate pseudo-bulk samples
            simulation <- SimBu :: simulate_bulk ( data = ds, scenario = "random" , scaling_factor = "NONE" , ncells = 100 , nsamples = 10 , BPPARAM = BiocParallel :: MulticoreParam ( workers = 4 ), run_parallel = TRUE )
            
            # Extract full simulated bulk counts and TPM
            full_counts <- SummarizedExperiment :: assays (simulation \$ bulk)[["bulk_counts"]]
            full_tpm <- SummarizedExperiment :: assays (simulation \$ bulk)[["bulk_tpm"]]
            
            # Extract and display head of simulated bulk counts and TPM
            head_counts <- utils :: head (full_counts)
            head_tpm <- utils :: head (full_tpm)
            
            print("Head of simulated bulk counts:")
            print(head_counts)
            print("Head of simulated bulk TPM:")
            print(head_tpm)
            
            # Generate simulation2 for merging
            simulation2 <- SimBu :: simulate_bulk ( data = ds, scenario = "even" , scaling_factor = "NONE" , ncells = 1000 , nsamples = 10 , BPPARAM = BiocParallel :: MulticoreParam ( workers = 4 ), run_parallel = TRUE )
            
            # 4. Merge simulations
            merged_simulations <- SimBu :: merge_simulations ( list (simulation, simulation2))
            
            # 5. Plot the simulation results
            pdf("simulation_plot.pdf", width = 10, height = 7)
            print(SimBu :: plot_simulation ( simulation = merged_simulations))
            dev.off()
            
            # Save meaningful outputs to files
            write.csv(as.matrix(full_counts), "simulation_counts.csv")
            write.csv(as.matrix(full_tpm), "simulation_tpm.csv")
            saveRDS(simulation, "simulation.rds")
            saveRDS(merged_simulations, "merged_simulations.rds")
            
            message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SIMBU_CUSTOM_DATA_SIMULATION":',
        paste0('    SimBu: ', as.character(packageVersion('SimBu')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_data_simulation.csv versions.yml
    """
}

workflow BIOC_SIMBU_CUSTOM_DATA_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix, tpm_matrix, annotation_dataframe, seurat_obj ] ]

    main:
    BIOC_SIMBU_CUSTOM_DATA_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SIMBU_CUSTOM_DATA_SIMULATION.out.tables
    plots    = BIOC_SIMBU_CUSTOM_DATA_SIMULATION.out.plots
    objects  = BIOC_SIMBU_CUSTOM_DATA_SIMULATION.out.objects
    versions = BIOC_SIMBU_CUSTOM_DATA_SIMULATION.out.versions
}
