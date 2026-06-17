#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: immunogenViewer — immunogen_evaluation_and_visualization
// Retrieve protein features, add candidate immunogens, visualize their positions, and evaluate their structural/functional properties to select the best antibody.
// Input: UniProt ID, Immunogen coordinates
// Container: quay.io/biocontainers/bioconductor-immunogenviewer:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: immunogenViewer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve protein features from UniProt and PredictProtein using getProteinFeatures()
//  * 2. [Core Analysis] Add candidate immunogens using addImmunogen()
//  * 3. [Core Analysis] Rename or remove immunogens if necessary using renameImmunogen() or removeImmunogen()
//  * 4. [Visualization & Output] Plot the full protein sequence with annotated features and immunogens using plotProtein()
//  * 5. [Visualization & Output] Plot a detailed view of a specific immunogen using plotImmunogen()
//  * 6. [Visualization & Output] Generate a summary evaluation table of all immunogens using evaluateImmunogen()

nextflow.enable.dsl = 2

process BIOC_IMMUNOGENVIEWER_IMMUNOGEN_EVALUATION_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("immunogenViewer")
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
    
    # Load required library
    library(immunogenViewer)
    
    # Create default input files if they do not exist in the working directory
    if (!file.exists("uniprot_id.txt")) {
      writeLines("Q9NZC2", "uniprot_id.txt")
    }
    
    if (!file.exists("immunogens.csv")) {
      write.csv(data.frame(
        name = c("ABIN2783734_", "HPA010917", "EB07921"),
        start = c(142, 196, NA),
        end = c(192, 230, NA),
        seq = c(NA, NA, "HGQKPGTHPPSELD"),
        stringsAsFactors = FALSE
      ), "immunogens.csv", row.names = FALSE, na = "")
    }
    
    # Read user inputs
    uniprot_id <- trimws(readLines("uniprot_id.txt", warn = FALSE)[1])
    imm_data <- read.csv("immunogens.csv", stringsAsFactors = FALSE)
    
    # 1. Retrieve protein features from UniProt and PredictProtein
    protein <- tryCatch({
      getProteinFeatures(uniprot_id)
    }, error = function(e) {
      message("Error retrieving protein features: ", e\$message)
      NULL
    })
    
    if (is.null(protein)) {
      stop("Pipeline stopped: Protein features could not be retrieved.")
    }
    
    # 2. Add candidate immunogens
    for (i in seq_len(nrow(imm_data))) {
      has_start_end <- "start" %in% colnames(imm_data) && "end" %in% colnames(imm_data) && 
                       !is.na(imm_data\$start[i]) && !is.na(imm_data\$end[i]) && 
                       imm_data\$start[i] != "" && imm_data\$end[i] != ""
                       
      has_seq <- "seq" %in% colnames(imm_data) && 
                 !is.na(imm_data\$seq[i]) && imm_data\$seq[i] != ""
                 
      if (has_start_end) {
        protein <- addImmunogen(protein, start = as.integer(imm_data\$start[i]), end = as.integer(imm_data\$end[i]), name = imm_data\$name[i])
      } else if (has_seq) {
        protein <- addImmunogen(protein, seq = imm_data\$seq[i], name = imm_data\$name[i])
      }
    }
    
    # 3. Rename or remove immunogens if necessary
    # (Skipped to support generic user-provided data without hardcoded names)
    
    # 4. Plot the full protein sequence with annotated features and immunogens
    pdf("protein_plot.pdf", width = 10, height = 10)
    p1 <- plotProtein(protein)
    if (inherits(p1, "ggplot") || inherits(p1, "patchwork") || inherits(p1, "grob")) {
      print(p1)
    }
    dev.off()
    
    # 5. Plot a detailed view of a specific immunogen
    pdf("immunogen_plot.pdf", width = 10, height = 10)
    if (nrow(imm_data) > 0) {
      p2 <- plotImmunogen(protein, imm_data\$name[1])
      if (inherits(p2, "ggplot") || inherits(p2, "patchwork") || inherits(p2, "grob")) {
        print(p2)
      }
    }
    dev.off()
    
    # 6. Generate a summary evaluation table of all immunogens
    immunogens <- evaluateImmunogen(protein)
    
    # Write outputs to the working directory
    write.csv(immunogens, "immunogens_evaluation.csv", row.names = FALSE)
    saveRDS(protein, "protein_features.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_IMMUNOGENVIEWER_IMMUNOGEN_EVALUATION_AND_VISUALIZATION":',
        paste0('    immunogenViewer: ', as.character(packageVersion('immunogenViewer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_immunogen_evaluation_and_visualization.csv versions.yml
    """
}

workflow BIOC_IMMUNOGENVIEWER_IMMUNOGEN_EVALUATION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ UniProt ID, Immunogen coordinates ] ]

    main:
    BIOC_IMMUNOGENVIEWER_IMMUNOGEN_EVALUATION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_IMMUNOGENVIEWER_IMMUNOGEN_EVALUATION_AND_VISUALIZATION.out.tables
    plots    = BIOC_IMMUNOGENVIEWER_IMMUNOGEN_EVALUATION_AND_VISUALIZATION.out.plots
    objects  = BIOC_IMMUNOGENVIEWER_IMMUNOGEN_EVALUATION_AND_VISUALIZATION.out.objects
    versions = BIOC_IMMUNOGENVIEWER_IMMUNOGEN_EVALUATION_AND_VISUALIZATION.out.versions
}
