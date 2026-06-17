#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mimager — transformed_array_visualization
// Convert microarray data to a 3D array and apply custom transformations (like RLE or rank) to highlight spatial biases.
// Input: raw_microarray_data.RData
// Container: quay.io/biocontainers/bioconductor-mimager:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mimager, scales
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input
//  * 2. [Visualization & Output] Execute Documented Code Workflow
//  * 3. [Visualization & Output] Save Outputs

nextflow.enable.dsl = 2

process BIOC_MIMAGER_TRANSFORMED_ARRAY_VISUALIZATION {
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
    .bm_deps <- c("mimager", "scales")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(mimager)
    library(scales)
    
    # -----------------------------------------------------------------------------
    # --- Load User Input ---
    # -----------------------------------------------------------------------------
    input_file <- "raw_microarray_data.RData"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    # Load the RData file into a temporary environment to identify the object
    temp_env <- new.env()
    load(input_file, envir = temp_env)
    
    object_names <- ls(temp_env)
    if (length(object_names) == 0) {
      stop("Error: No objects found in the loaded RData file.")
    }
    
    # Assign the loaded microarray object (AffyBatch or FeatureSet) to 'Dilution'
    # to match the documented code variable name.
    Dilution <- temp_env[[object_names[1]]]
    
    # -----------------------------------------------------------------------------
    # --- Execute Documented Code Workflow ---
    # -----------------------------------------------------------------------------
    
    # Define custom divergent color palette
    div.colors <- scales::brewer_pal(palette = "RdBu")(9)
    
    # Plot the transformed array with custom color palettes and save to PDF
    pdf("rle_mimage_plot.pdf", width = 10, height = 8)
    mimage(Dilution, transform = arle, legend.label = "RLE", colors = div.colors)
    dev.off()
    
    # Convert microarray object to a 3D array
    DilutionArray <- marray(Dilution)
    array_dim <- dim(DilutionArray)
    
    # Apply rank transformation to the 3D array
    DilutionRank <- arank(DilutionArray)
    rank_dim <- dim(DilutionRank)
    
    # -----------------------------------------------------------------------------
    # --- Save Outputs ---
    # -----------------------------------------------------------------------------
    
    # Save the processed 3D arrays as RDS objects
    saveRDS(DilutionArray, file = "DilutionArray.rds")
    saveRDS(DilutionRank, file = "DilutionRank.rds")
    
    # Save dimensions to a CSV file for downstream verification
    dimensions_summary <- data.frame(
      Object = c("DilutionArray", "DilutionRank"),
      Rows = c(array_dim[1], rank_dim[1]),
      Columns = c(array_dim[2], rank_dim[2]),
      Samples = c(array_dim[3], rank_dim[3])
    )
    write.csv(dimensions_summary, "array_dimensions.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MIMAGER_TRANSFORMED_ARRAY_VISUALIZATION":',
        paste0('    mimager: ', as.character(packageVersion('mimager')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transformed_array_visualization.csv versions.yml
    """
}

workflow BIOC_MIMAGER_TRANSFORMED_ARRAY_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_microarray_data.RData ] ]

    main:
    BIOC_MIMAGER_TRANSFORMED_ARRAY_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_MIMAGER_TRANSFORMED_ARRAY_VISUALIZATION.out.tables
    plots    = BIOC_MIMAGER_TRANSFORMED_ARRAY_VISUALIZATION.out.plots
    objects  = BIOC_MIMAGER_TRANSFORMED_ARRAY_VISUALIZATION.out.objects
    versions = BIOC_MIMAGER_TRANSFORMED_ARRAY_VISUALIZATION.out.versions
}
