#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: COMPASS — simple_compass
// Fit a COMPASS model directly to tabular cell count data of boolean combinations using SimpleCOMPASS.
// Input: SimpleCOMPASSExamples.csv
// Container: quay.io/biocontainers/bioconductor-compass:1.48.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: COMPASS, dplyr, ggplot2
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and format tabular data, separating metadata and counts
//  * 2. [Core Analysis] Split counts into stimulated (n_s) and unstimulated (n_u) matrices
//  * 3. [Core Analysis] Format and translate marker names to COMPASS-compatible boolean format using COMPASS:::translate_marker_names()
//  * 4. [Core Analysis] Ensure the last column is the all-negative combination
//  * 5. [Core Analysis] Fit the model using COMPASS::SimpleCOMPASS()
//  * 6. [Visualization & Output] Extract and plot scores using scores() and plot()

nextflow.enable.dsl = 2

process BIOC_COMPASS_SIMPLE_COMPASS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("COMPASS", "ggplot2", "dplyr")
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
    
    library(COMPASS)
    library(ggplot2)
    library(dplyr)
    
    # Define the cytokine renaming function as documented in the vignette
    rename_cytokines = function(nms){
      #2 to IL2
      nms = gsub("([&!])2([&!])", 
           "\\1IL2\\2", nms)
      #10 to IL10
      nms = gsub("([&!])10([&!])",
            "\\1IL10\\2", nms)
      # 17A to IL17A
      nms = gsub("([&!])17A([&!])", 
          "\\1IL17A\\2", nms)
      # 17F to IL17F
      nms = gsub("([&!])17F([&!])", 
          "\\1IL17F\\2", nms)
      # 22 to IL22
      nms = gsub("([&!])22([&!])", 
          "\\1IL22\\2", nms)
      return(nms)
    }
    
    # 1. Read and format tabular data, separating metadata and counts
    example_data_path = "SimpleCOMPASSExamples.csv"
    compass_data = read.csv(example_data_path, check.names=FALSE)
    
    metadata = compass_data[,2:4]
    metadata = as.data.frame(metadata)
    
    counts = as.matrix(compass_data[,5:261])
    counts = counts[,-1L] 
    
    # Identify and correct typos in Stimulation column
    typos = which(metadata\$Stimulation=="UnStimulated")
    metadata\$Stimulation[typos] = "Unstimulated"
    
    # 2. Split counts into stimulated (n_s) and unstimulated (n_u) matrices
    n_u = subset(counts, metadata\$Stimulation == "Unstimulated")
    n_s = subset(counts, metadata\$Stimulation == "ESAT6/CFP10")
    
    metadata\$unique_id = metadata\$`PATIENT ID`
    
    rownames(n_u) = subset(metadata\$unique_id,
           metadata\$Stimulation=="Unstimulated")
    
    rownames(n_s) = subset(metadata\$unique_id,
           metadata\$Stimulation=="ESAT6/CFP10")
    
    metadata = subset(metadata,
           metadata\$Stimulation=="ESAT6/CFP10")
    
    # 3. Format and translate marker names to COMPASS-compatible boolean format
    nms = basename(colnames(n_s))
    nms = COMPASS:::translate_marker_names(nms)
    colnames(n_s) = nms
    
    nms = basename(colnames(n_u))
    nms = COMPASS:::translate_marker_names(nms)
    colnames(n_u) = nms
    
    colnames(n_s) = rename_cytokines(colnames(n_s))
    colnames(n_u) = rename_cytokines(colnames(n_u))
    
    # 4. Ensure the last column is the all-negative combination (verified by colnames check)
    message("Last column of n_s: ", colnames(n_s)[ncol(n_s)])
    message("Last column of n_u: ", colnames(n_u)[ncol(n_u)])
    
    # 5. Fit the model using COMPASS::SimpleCOMPASS()
    fit = COMPASS::SimpleCOMPASS(n_s = n_s,
                           n_u = n_u, 
                           meta = metadata,
                           individual_id = "unique_id",
                           iterations = 1000,
                           replications = 3)
    
    # Save the fitted model object
    saveRDS(fit, "compass_fit.rds")
    
    # 6. Extract and plot scores using scores() and plot()
    fit_scores <- scores(fit)
    write.csv(fit_scores, "compass_scores.csv", row.names = FALSE)
    
    # Generate and save the boxplot of functionality scores
    p1 <- fit_scores %>%
      ggplot() + 
      geom_boxplot(outlier.colour = NA) +
      geom_jitter() +
      aes(y = FS, x = GROUP)
    ggsave("compass_scores_plot.pdf", plot = p1, width = 7, height = 5)
    
    # Generate and save the COMPASS heatmap plot
    pdf("compass_heatmap.pdf", width = 10, height = 8)
    plot(fit, "GROUP")
    dev.off()

    writeLines(c(
        '"BIOC_COMPASS_SIMPLE_COMPASS":',
        paste0('    COMPASS: ', as.character(packageVersion('COMPASS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simple_compass.csv versions.yml
    """
}

workflow BIOC_COMPASS_SIMPLE_COMPASS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SimpleCOMPASSExamples.csv ] ]

    main:
    BIOC_COMPASS_SIMPLE_COMPASS(ch_input)

    emit:
    tables   = BIOC_COMPASS_SIMPLE_COMPASS.out.tables
    plots    = BIOC_COMPASS_SIMPLE_COMPASS.out.plots
    objects  = BIOC_COMPASS_SIMPLE_COMPASS.out.objects
    versions = BIOC_COMPASS_SIMPLE_COMPASS.out.versions
}
