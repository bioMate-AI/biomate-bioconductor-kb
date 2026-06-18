#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: APL — step_by_step_apl
// Perform a detailed step-by-step Association Plot analysis, including Correspondence Analysis, dimension selection, coordinate calculation, specificity scoring, 
// Input: darmanis
// Container: quay.io/biocontainers/bioconductor-apl:1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: APL, SingleCellExperiment, ggplot2
// Visualizations: biplot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Compute Correspondence Analysis (CA) using cacomp
//  * 2. [Visualization & Output] Convert the object to a cacomp object using as.cacomp
//  * 3. [Visualization & Output] Determine the number of dimensions to retain using
//  * 4. [Visualization & Output] Subset the CA dimensions using subset_dims
//  * 5. [Visualization & Output] Calculate Association Plot coordinates for a target cell
//  * 6. [Visualization & Output] Plot the Association Plot using apl
//  * 7. [Visualization & Output] Compute cluster-specificity (S_alpha) scores using
//  * 8. [Visualization & Output] Plot the Association Plot with scores using apl with
//  * 9. [Visualization & Output] Visualize CA projections using ca_biplot
//  * 10. [Visualization & Output] Conduct GO enrichment analysis using apl_topGO and plot

nextflow.enable.dsl = 2

process BIOC_APL_STEP_BY_STEP_APL {
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
    .bm_deps <- c("APL", "ggplot2")
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
    library(APL)
    library(ggplot2)
    
    # Read input file
    if (file.exists("darmanis")) {
      darmanis <- readRDS("darmanis")
    } else if (file.exists("darmanis.rds")) {
      darmanis <- readRDS("darmanis.rds")
    } else {
      stop("Input file 'darmanis' or 'darmanis.rds' not found in the working directory.")
    }
    
    # --- Compute Correspondence Analysis (CA) using cacomp ---
    logcounts <- logcounts(darmanis)
    ca <- cacomp(
      obj = logcounts,
      top = 5000
    )
    
    # To allow as.cacomp(darmanis) to work, we compute CA on the SCE object and return it
    darmanis <- cacomp(
      obj = darmanis,
      assay = "logcounts",
      top = 5000,
      return_input = TRUE
    )
    
    # --- Convert the object to a cacomp object using as.cacomp ---
    ca <- as.cacomp(darmanis)
    
    # --- Determine the number of dimensions to retain using ---
    p_scree <- pick_dims(ca, method = "scree_plot") +
      xlim(c(0, 20))
    ggsave("scree_plot.pdf", plot = p_scree, width = 7, height = 5)
    
    pd <- pick_dims(
      ca,
      mat = logcounts(darmanis),
      method = "elbow_rule",
      reps = 3
    )
    
    # --- Subset the CA dimensions using subset_dims ---
    ca <- subset_dims(ca, dims = pd)
    
    # --- Calculate Association Plot coordinates for a target cell ---
    # Specifying a cell cluster of interest
    endo <- which(darmanis\$cell.type == "endothelial")
    
    # Calculate Association Plot coordinates for endothelial cells
    ca <- apl_coords(ca, group = endo)
    
    # --- Plot the Association Plot using apl ---
    # endothelial marker genes
    marker_genes <- c("APOLD1", "TM4SF1", "SULT1B1", "ESM1", "SELE")
    
    # Plot APL
    p_apl_endo <- apl(ca,
      row_labs = TRUE,
      rows_idx = marker_genes,
      type = "ggplot"
    )
    ggsave("apl_endothelial.pdf", plot = p_apl_endo, width = 7, height = 6)
    
    # --- Compute cluster-specificity (S_alpha) scores using ---
    ca <- apl_score(ca,
      mat = logcounts(darmanis),
      reps = 5
    )
    
    # --- Plot the Association Plot with scores using apl with ---
    p_apl_endo_score <- apl(ca,
      show_score = TRUE,
      type = "ggplot"
    )
    ggsave("apl_endothelial_scores.pdf", plot = p_apl_endo_score, width = 7, height = 6)
    
    # Save scores table
    scores_endo <- cacomp_slot(ca, "APL_score")
    write.csv(scores_endo, "endothelial_apl_scores.csv", row.names = FALSE)
    
    # --- Visualize CA projections using ca_biplot ---
    p_biplot <- ca_biplot(ca, col_labels = endo, type = "ggplot")
    ggsave("ca_biplot_endothelial.pdf", plot = p_biplot, width = 7, height = 6)
    
    # --- Conduct GO enrichment analysis using apl_topGO and plot ---
    # Get indices of microglia cells
    microglia <- which(darmanis\$cell.type == "microglia")
    
    # Calculate Association Plot coordinates of the genes and the S_alpha-scores
    ca <- apl_coords(ca, group = microglia)
    
    ca <- apl_score(ca,
      mat = logcounts(darmanis),
      reps = 5
    )
    
    enr <- apl_topGO(ca,
      ontology = "BP",
      organism = "hs",
      score_cutoff = 1
    )
    write.csv(enr, "microglia_go_enrichment.csv", row.names = FALSE)
    
    p_enrich <- plot_enrichment(enr)
    ggsave("go_enrichment_plot.pdf", plot = p_enrich, width = 8, height = 6)
    
    # Save final cacomp object
    saveRDS(ca, "ca_final.rds")

    writeLines(c(
        '"BIOC_APL_STEP_BY_STEP_APL":',
        paste0('    APL: ', as.character(packageVersion('APL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_apl.csv versions.yml
    """
}

workflow BIOC_APL_STEP_BY_STEP_APL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ darmanis ] ]

    main:
    BIOC_APL_STEP_BY_STEP_APL(ch_input)

    emit:
    tables   = BIOC_APL_STEP_BY_STEP_APL.out.tables
    plots    = BIOC_APL_STEP_BY_STEP_APL.out.plots
    objects  = BIOC_APL_STEP_BY_STEP_APL.out.objects
    versions = BIOC_APL_STEP_BY_STEP_APL.out.versions
}
