#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenVisR — mutation_landscape_waterfall
// Visualize somatic mutations, mutation burden, and clinical data at the cohort level using a waterfall plot.
// Input: brcaMAF, clinical
// Container: quay.io/biocontainers/bioconductor-genvisr:1.42.2--r45hdfd78af_0
// R packages: GenVisR, ggplot2, knitr, reshape2
// Bioconductor: 3.20 | R: 4.4
// Requires: GenVisR, reshape2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the GenVisR and reshape2 packages
//  * 2. [Core Analysis] Format and melt clinical data into long format
//  * 3. [Visualization & Output] Generate the waterfall plot with customized gene filtering, clinical annotations, and color palettes

nextflow.enable.dsl = 2

process BIOC_GENVISR_MUTATION_LANDSCAPE_WATERFALL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("GenVisR", "ggplot2", "knitr", "reshape2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    
    # Stage 1: Load the GenVisR and reshape2 packages
    library(GenVisR)
    library(reshape2)
    
    set.seed(383)
    
    # Helper function to robustly read user input files from the working directory
    read_input_file <- function(base_name) {
      if (file.exists(paste0(base_name, ".rds"))) {
        return(readRDS(paste0(base_name, ".rds")))
      } else if (file.exists(paste0(base_name, ".csv"))) {
        return(read.csv(paste0(base_name, ".csv"), stringsAsFactors = FALSE))
      } else if (file.exists(paste0(base_name, ".tsv"))) {
        return(read.delim(paste0(base_name, ".tsv"), stringsAsFactors = FALSE))
      } else if (file.exists(base_name)) {
        return(read.csv(base_name, stringsAsFactors = FALSE))
      } else {
        stop(paste("Required input file not found in working directory:", base_name))
      }
    }
    
    # Read the user-provided input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    brcaMAF <- read_input_file("brcaMAF")
    clinical_input <- read_input_file("clinical")
    
    # Stage 2: Format and melt clinical data into long format
    # If the input clinical data is already in long format (contains sample, variable, value),
    # we use it directly. Otherwise, we format and melt it.
    if (all(c("sample", "variable", "value") %in% colnames(clinical_input))) {
      clinical <- clinical_input
    } else {
      # Ensure the sample identifier column is named "sample"
      if (!"sample" %in% colnames(clinical_input)) {
        if ("Tumor_Sample_Barcode" %in% colnames(clinical_input)) {
          colnames(clinical_input)[colnames(clinical_input) == "Tumor_Sample_Barcode"] <- "sample"
        } else if ("Sample" %in% colnames(clinical_input)) {
          colnames(clinical_input)[colnames(clinical_input) == "Sample"] <- "sample"
        }
      }
      clinical <- melt(clinical_input, id.vars = c("sample"))
    }
    
    # Save the formatted long clinical data as a CSV output
    write.csv(clinical, "clinical_melted.csv", row.names = FALSE)
    
    # Stage 3: Generate the waterfall plots with customized gene filtering, clinical annotations, and color palettes
    # Save Plot 1: Waterfall plot with recurrence cutoff
    pdf("waterfall_recurrence_cutoff.pdf", width = 12, height = 8)
    plot1 <- waterfall(brcaMAF, mainRecurCutoff = 0.06)
    print(plot1)
    dev.off()
    
    # Save Plot 2: Waterfall plot with specific genes
    pdf("waterfall_selected_genes.pdf", width = 12, height = 8)
    plot2 <- waterfall(brcaMAF, plotGenes = c("PIK3CA", "TP53", "USH2A", "MLL3", "BRCA1"))
    print(plot2)
    dev.off()
    
    # Save Plot 3: Waterfall plot with clinical annotations and custom colors
    pdf("waterfall_with_clinical.pdf", width = 14, height = 10)
    plot3 <- waterfall(brcaMAF, 
                       clinDat = clinical, 
                       clinVarCol = c(lumA = "blue4", 
                                      lumB = "deepskyblue", 
                                      her2 = "hotpink2", 
                                      basal = "firebrick2", 
                                      normal = "green4", 
                                      `20-30` = "#ddd1e7", 
                                      `31-50` = "#bba3d0", 
                                      `51-60` = "#9975b9", 
                                      `61+` = "#7647a2"), 
                       plotGenes = c("PIK3CA", "TP53", "USH2A", "MLL3", "BRCA1"), 
                       clinLegCol = 2, 
                       clinVarOrder = c("lumA", "lumB", "her2", "basal", "normal", "20-30", "31-50", "51-60", "61+"))
    print(plot3)
    dev.off()
    
    # Save the final plot object as an RDS file for downstream use
    saveRDS(plot3, "waterfall_final_plot.rds")

    writeLines(c(
        '"BIOC_GENVISR_MUTATION_LANDSCAPE_WATERFALL":',
        paste0('    GenVisR: ', as.character(packageVersion('GenVisR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mutation_landscape_waterfall.csv versions.yml
    """
}

workflow BIOC_GENVISR_MUTATION_LANDSCAPE_WATERFALL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brcaMAF, clinical ] ]

    main:
    BIOC_GENVISR_MUTATION_LANDSCAPE_WATERFALL(ch_input)

    emit:
    tables   = BIOC_GENVISR_MUTATION_LANDSCAPE_WATERFALL.out.tables
    plots    = BIOC_GENVISR_MUTATION_LANDSCAPE_WATERFALL.out.plots
    objects  = BIOC_GENVISR_MUTATION_LANDSCAPE_WATERFALL.out.objects
    versions = BIOC_GENVISR_MUTATION_LANDSCAPE_WATERFALL.out.versions
}
