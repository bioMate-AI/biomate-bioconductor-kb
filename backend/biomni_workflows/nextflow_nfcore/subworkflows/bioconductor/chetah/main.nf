#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CHETAH — cell_type_classification
// Classify single-cell RNA-seq query data using a reference dataset and explore or adjust the classification results.
// Input: input_counts, input_tsne, ref_counts, ref_ct
// Container: quay.io/biocontainers/bioconductor-chetah:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CHETAH, Matrix, S4Vectors, SingleCellExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create SingleCellExperiment objects for both reference and input data
//  * 2. [Core Analysis] Run the hierarchical classification using CHETAHclassifier
//  * 3. [Visualization & Output] Visualize the classification tree and t-SNE map using PlotCHETAH
//  * 4. [Core Analysis] Adjust the classification confidence threshold using Classify
//  * 5. [Core Analysis] Rename intermediate or final cell types using RenameBelowNode
//  * 6. [Core Analysis] Launch the interactive Shiny application using CHETAHshiny

nextflow.enable.dsl = 2

process BIOC_CHETAH_CELL_TYPE_CLASSIFICATION {
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
    .bm_deps <- c("CHETAH", "Matrix", "S4Vectors")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    
    library(CHETAH)
    library(Matrix)
    library(S4Vectors)
    
    # Helper function to robustly read input files from the working directory
    read_input_file <- function(name, is_vector = FALSE) {
      # Check RDS format first
      if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      }
      # Check CSV format
      if (file.exists(paste0(name, ".csv"))) {
        if (is_vector) {
          df <- read.csv(paste0(name, ".csv"), header = TRUE)
          return(setNames(as.character(df[[2]]), as.character(df[[1]])))
        } else {
          return(as.matrix(read.csv(paste0(name, ".csv"), row.names = 1, check.names = FALSE)))
        }
      }
      # Check TSV format
      if (file.exists(paste0(name, ".tsv"))) {
        if (is_vector) {
          df <- read.delim(paste0(name, ".tsv"), header = TRUE)
          return(setNames(as.character(df[[2]]), as.character(df[[1]])))
        } else {
          return(as.matrix(read.delim(paste0(name, ".tsv"), row.names = 1, check.names = FALSE)))
        }
      }
      # Check TXT format
      if (file.exists(paste0(name, ".txt"))) {
        if (is_vector) {
          df <- read.table(paste0(name, ".txt"), header = TRUE, sep = "\t")
          return(setNames(as.character(df[[2]]), as.character(df[[1]])))
        } else {
          return(as.matrix(read.table(paste0(name, ".txt"), row.names = 1, sep = "\t", check.names = FALSE)))
        }
      }
      # Direct file check
      if (file.exists(name)) {
        return(readRDS(name))
      }
      stop(paste("Required input file not found for:", name))
    }
    
    # Read user inputs
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    input_counts <- read_input_file("input_counts")
    input_tsne <- read_input_file("input_tsne")
    ref_counts <- read_input_file("ref_counts")
    ref_ct <- read_input_file("ref_ct", is_vector = TRUE)
    
    # 1. Create SingleCellExperiment objects for both reference and input data
    reference <- SingleCellExperiment(assays = list(counts = ref_counts),
                                      colData = DataFrame(celltypes = ref_ct))
    
    input <- SingleCellExperiment(assays = list(counts = input_counts),
                                  reducedDims = SimpleList(TSNE = input_tsne))
    
    # 2. Run the hierarchical classification using CHETAHclassifier
    input <- CHETAHclassifier(input = input, ref_cells = reference)
    
    # Set up PDF device to capture all PlotCHETAH visualizations
    pdf("CHETAH_plots.pdf", width = 12, height = 8)
    
    # 3. Visualize the classification tree and t-SNE map using PlotCHETAH
    PlotCHETAH(input)
    
    celltypes <- input\$celltype_CHETAH
    
    # Assign input_mel to input to match the vignette's variable naming
    input_mel <- input
    
    PlotCHETAH(input = input_mel, interm = TRUE)
    
    colors <- PlotCHETAH(input = input_mel, return_col = TRUE)
    
    # 6. Launch the interactive Shiny application using CHETAHshiny (guarded for non-interactive environments)
    if (interactive()) {
      CHETAHshiny(input = input_mel)
    } else {
      message("Skipping interactive CHETAHshiny call in non-interactive mode.")
    }
    
    # 4. Adjust the classification confidence threshold using Classify
    input_mel <- Classify(input = input_mel, 0.8)
    PlotCHETAH(input = input_mel, tree = FALSE)
    
    input_mel <- Classify(input_mel, 0)
    PlotCHETAH(input = input_mel, tree = FALSE)
    
    # 5. Rename intermediate or final cell types using RenameBelowNode
    tryCatch({
      input_mel <- RenameBelowNode(input_mel, whichnode = 6, replacement = "T cell")
      PlotCHETAH(input = input_mel, tree = FALSE)
    }, error = function(e) {
      message("RenameBelowNode failed (likely because node 6 does not exist in this reference tree): ", e\$message)
    })
    
    input_mel <- Classify(input_mel)
    PlotCHETAH(input = input_mel, tree = FALSE)
    
    dev.off()
    
    # Write meaningful results to output files
    write.csv(data.frame(Cell = names(celltypes), CellType = celltypes),
              file = "classified_celltypes.csv", row.names = FALSE)
    
    saveRDS(colors, file = "chetah_colors.rds")
    saveRDS(input_mel, file = "input_mel_classified.rds")

    writeLines(c(
        '"BIOC_CHETAH_CELL_TYPE_CLASSIFICATION":',
        paste0('    CHETAH: ', as.character(packageVersion('CHETAH')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_type_classification.csv versions.yml
    """
}

workflow BIOC_CHETAH_CELL_TYPE_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_counts, input_tsne, ref_counts, ref_ct ] ]

    main:
    BIOC_CHETAH_CELL_TYPE_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_CHETAH_CELL_TYPE_CLASSIFICATION.out.tables
    plots    = BIOC_CHETAH_CELL_TYPE_CLASSIFICATION.out.plots
    objects  = BIOC_CHETAH_CELL_TYPE_CLASSIFICATION.out.objects
    versions = BIOC_CHETAH_CELL_TYPE_CLASSIFICATION.out.versions
}
