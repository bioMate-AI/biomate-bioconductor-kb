#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MMUPHin — discrete_structure_discovery
// Identify and validate discrete population subgroups (clusters) consistently across multiple independent studies.
// Input: adjusted_abundance_table.tsv, metadata.tsv
// Container: quay.io/biocontainers/bioconductor-mmuphin:1.16.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MMUPHin, dplyr, ggplot2, magrittr, vegan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate a sample-by-sample dissimilarity matrix using vegan::vegdist
//  * 2. [Core Analysis] Run discrete_discover to evaluate internal and external prediction strength across a range of cluster numbers (K)

nextflow.enable.dsl = 2

process BIOC_MMUPHIN_DISCRETE_STRUCTURE_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("MMUPHin", "vegan", "ggplot2", "dplyr", "magrittr")
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
    library(MMUPHin)
    library(vegan)
    library(ggplot2)
    library(dplyr)
    library(magrittr)
    
    # 1. Read User Input Files
    # The pipeline expects 'adjusted_abundance_table.tsv' and 'metadata.tsv' in the working directory.
    abundance_file <- "adjusted_abundance_table.tsv"
    metadata_file <- "metadata.tsv"
    
    if (!file.exists(abundance_file)) {
      stop(paste("Required input file missing:", abundance_file))
    }
    if (!file.exists(metadata_file)) {
      stop(paste("Required input file missing:", metadata_file))
    }
    
    # Read abundance matrix (feature-by-sample) and metadata
    abundance <- read.delim(abundance_file, row.names = 1, sep = "\t", check.names = FALSE)
    metadata <- read.delim(metadata_file, row.names = 1, sep = "\t", check.names = FALSE)
    
    # Align samples between abundance matrix and metadata
    common_samples <- intersect(colnames(abundance), rownames(metadata))
    if (length(common_samples) == 0) {
      stop("No common samples found between abundance table columns and metadata rows.")
    }
    
    abundance <- abundance[, common_samples, drop = FALSE]
    metadata <- metadata[common_samples, , drop = FALSE]
    
    # Subset to control samples if 'study_condition' column exists and contains 'control'
    # Otherwise, use the entire dataset as the control subset.
    if ("study_condition" %in% colnames(metadata) && any(metadata\$study_condition == "control")) {
      control_meta <- subset(metadata, study_condition == "control")
      control_abd_adj <- abundance[, rownames(control_meta), drop = FALSE]
    } else {
      control_meta <- metadata
      control_abd_adj <- abundance
    }
    
    # Ensure the batch variable 'studyID' exists in metadata
    if (!"studyID" %in% colnames(control_meta)) {
      stop("Metadata must contain a 'studyID' column representing the study/batch variable.")
    }
    
    # 2. Calculate Sample-by-Sample Dissimilarity Matrix
    D_control <- vegdist(t(control_abd_adj))
    
    # 3. Run Discrete Structure Discovery
    fit_discrete <- discrete_discover(D = D_control,
                                      batch = "studyID",
                                      data = control_meta,
                                      control = list(k_max = 8,
                                                     verbose = FALSE))
    
    # 4. Save Outputs
    # Save the main RDS object
    saveRDS(fit_discrete, file = "fit_discrete.rds")
    
    # Save prediction strength statistics as CSV tables
    write.csv(as.data.frame(fit_discrete\$internal_mean), "discrete_internal_mean.csv", row.names = TRUE)
    write.csv(as.data.frame(fit_discrete\$internal_se), "discrete_internal_se.csv", row.names = TRUE)
    write.csv(as.data.frame(fit_discrete\$external_mean), "discrete_external_mean.csv", row.names = TRUE)
    write.csv(as.data.frame(fit_discrete\$external_se), "discrete_external_se.csv", row.names = TRUE)
    
    # Generate and save custom diagnostic plots for all studies
    pdf("custom_diagnostic_discrete.pdf", width = 8, height = 6)
    unique_studies <- unique(control_meta\$studyID)
    k_max_evaluated <- nrow(fit_discrete\$internal_mean) + 1 # typically 2:k_max
    
    for (study_id in unique_studies) {
      if (study_id %in% colnames(fit_discrete\$internal_mean)) {
        internal <- data.frame(K = 2:k_max_evaluated,
                               statistic = fit_discrete\$internal_mean[, study_id],
                               se = fit_discrete\$internal_se[, study_id],
                               type = "internal")
        
        external <- data.frame(K = 2:k_max_evaluated,
                               statistic = fit_discrete\$external_mean[, study_id],
                               se = fit_discrete\$external_se[, study_id],
                               type = "external")
        
        plot_df <- rbind(internal, external)
        
        p <- ggplot(plot_df, aes(x = K, y = statistic, color = type)) +
          geom_point(position = position_dodge(width = 0.5)) + 
          geom_line(position = position_dodge(width = 0.5)) +
          geom_errorbar(aes(ymin = statistic - se, ymax = statistic + se),
                        position = position_dodge(width = 0.5), width = 0.5) +
          ggtitle(paste("Evaluation of discrete structure in", study_id)) +
          theme_minimal()
        
        print(p)
      }
    }
    dev.off()

    writeLines(c(
        '"BIOC_MMUPHIN_DISCRETE_STRUCTURE_DISCOVERY":',
        paste0('    MMUPHin: ', as.character(packageVersion('MMUPHin')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_discrete_structure_discovery.csv versions.yml
    """
}

workflow BIOC_MMUPHIN_DISCRETE_STRUCTURE_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ adjusted_abundance_table.tsv, metadata.tsv ] ]

    main:
    BIOC_MMUPHIN_DISCRETE_STRUCTURE_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_MMUPHIN_DISCRETE_STRUCTURE_DISCOVERY.out.tables
    plots    = BIOC_MMUPHIN_DISCRETE_STRUCTURE_DISCOVERY.out.plots
    objects  = BIOC_MMUPHIN_DISCRETE_STRUCTURE_DISCOVERY.out.objects
    versions = BIOC_MMUPHIN_DISCRETE_STRUCTURE_DISCOVERY.out.versions
}
