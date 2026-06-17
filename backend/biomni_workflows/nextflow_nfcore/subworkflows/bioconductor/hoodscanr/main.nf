#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hoodscanR — cellular_neighborhood_analysis
// Perform cellular neighborhood scanning, colocalization analysis, and neighborhood-based clustering on single-cell spatial transcriptomics data.
// Input: spe
// Container: quay.io/biocontainers/bioconductor-hoodscanr:1.8.0--r45ha27e39d_0
// R packages: SpatialExperiment, ggplot2, hoodscanR, scico
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, ggplot2, hoodscanR, scico
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the SpatialExperiment input object using readHoodData
//  * 2. [Visualization & Output] Visualize cell positions and annotations using plotTissue
//  * 3. [Core Analysis] Identify nearest neighbor cells using findNearCells
//  * 4. [Core Analysis] Calculate neighborhood association probabilities using scanHoods
//  * 5. [Core Analysis] Merge probabilities by cell type groups using mergeByGroup
//  * 6. [Visualization & Output] Visualize neighborhood probabilities using plotHoodMat
//  * 7. [Core Analysis] Merge neighborhood results back into the SpatialExperiment object using mergeHoodSpe
//  * 8. [Visualization & Output] Calculate neighborhood entropy and perplexity using calcMetrics and visualize them using plotTissue
//  * 9. [Visualization & Output] Perform neighborhood colocalization analysis using plotColocal
//  * 10. [Core Analysis] Cluster cells by neighborhood probability distribution using clustByHood
//  * 11. [Visualization & Output] Visualize cluster probability distributions using plotProbDist and spatial clusters using plotTissue

nextflow.enable.dsl = 2

process BIOC_HOODSCANR_CELLULAR_NEIGHBORHOOD_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("SpatialExperiment", "ggplot2", "hoodscanR", "scico", "SummarizedExperiment")
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
           library(SummarizedExperiment)
     library(hoodscanR)
        library(SpatialExperiment)
        library(scico)
        library(ggplot2)
        
        # 1. Read the input SpatialExperiment object from the working directory
        if (file.exists("spe")) {
          spe <- readRDS("spe")
        } else if (file.exists("spe.rds")) {
          spe <- readRDS("spe.rds")
        } else {
          stop("Error: Input SpatialExperiment object 'spe' or 'spe.rds' not found in the working directory.")
        }
        
        # Identify the cell annotation column in the input SpatialExperiment object
        anno_col_to_use <- "celltypes"
        if (!"celltypes" %in% colnames(colData(spe))) {
          candidates <- c("cell_annotation", "celltype", "cell_type", "cell_types", "annotations", "class")
          found <- intersect(candidates, colnames(colData(spe)))
          if (length(found) > 0) {
            anno_col_to_use <- found[1]
          } else {
            # Fallback to the first character or factor column
            is_char <- sapply(colData(spe), function(x) is.character(x) || is.factor(x))
            if (any(is_char)) {
              anno_col_to_use <- names(which(is_char))[1]
            }
          }
        }
        
        # Format the SpatialExperiment input object using readHoodData
        spe <- readHoodData(spe, anno_col = anno_col_to_use)
        
        # Define col.pal dynamically based on the number of unique cell annotations
        unique_annos <- unique(colData(spe)\$cell_annotation)
        num_types <- length(unique_annos)
        col.pal <- c("red3", "royalblue", "gold", "cyan2", "purple3", "darkgreen", "orange", "magenta", "brown", "gray")
        if (num_types > length(col.pal)) {
          col.pal <- grDevices::rainbow(num_types)
        } else {
          col.pal <- col.pal[1:num_types]
        }
        
        # 2. Visualize cell positions and annotations using plotTissue
        p_anno <- plotTissue(spe, color = cell_annotation, size = 1.5, alpha = 0.8) +
          scale_color_manual(values = col.pal)
        ggsave("plot_tissue_annotations.pdf", plot = p_anno, width = 8, height = 6)
        
        # 3. Identify nearest neighbor cells using findNearCells
        fnc <- findNearCells(spe, k = 100)
        saveRDS(fnc, "fnc_neighbors.rds")
        
        # 4. Calculate neighborhood association probabilities using scanHoods
        pm <- scanHoods(fnc\$distance)
        
        # 5. Merge probabilities by cell type groups using mergeByGroup
        hoods <- mergeByGroup(pm, fnc\$cells)
        write.csv(as.data.frame(hoods), "hoods_probabilities.csv", row.names = TRUE)
        
        # 6. Visualize neighborhood probabilities using plotHoodMat
        pdf("plot_hood_mat_n10.pdf", height = 5, width = 7)
        print(plotHoodMat(hoods, n = 10, hm_height = 5))
        dev.off()
        
        pdf("plot_hood_mat_targets.pdf", height = 3, width = 7)
        tryCatch({
          target_cells <- head(rownames(hoods), 2)
          print(plotHoodMat(hoods, targetCells = target_cells, hm_height = 3))
        }, error = function(e) {
          message("Skipping target cells plot: ", e\$message)
        })
        dev.off()
        
        # 7. Merge neighborhood results back into the SpatialExperiment object using mergeHoodSpe
        spe <- mergeHoodSpe(spe, hoods)
        
        # 8. Calculate neighborhood entropy and perplexity using calcMetrics and visualize them using plotTissue
        spe <- calcMetrics(spe, pm_cols = colnames(hoods))
        
        p_entropy <- plotTissue(spe, size = 1.5, color = entropy) +
          scale_color_scico(palette = "tokyo")
        ggsave("plot_tissue_entropy.pdf", plot = p_entropy, width = 8, height = 6)
        
        p_perplexity <- plotTissue(spe, size = 1.5, color = perplexity) +
          scale_color_scico(palette = "tokyo")
        ggsave("plot_tissue_perplexity.pdf", plot = p_perplexity, width = 8, height = 6)
        
        # 9. Perform neighborhood colocalization analysis using plotColocal
        pdf("plot_colocal.pdf", width = 6, height = 5)
        print(plotColocal(spe, pm_cols = colnames(hoods)))
        dev.off()
        
        # 10. Cluster cells by neighborhood probability distribution using clustByHood
        spe <- clustByHood(spe, pm_cols = colnames(hoods), k = 10)
        
        # 11. Visualize cluster probability distributions using plotProbDist and spatial clusters using plotTissue
        p_prob <- plotProbDist(spe, pm_cols = colnames(hoods), by_cluster = TRUE, plot_all = TRUE, show_clusters = as.character(seq(10)))
        ggsave("plot_prob_dist.pdf", plot = p_prob, width = 10, height = 8)
        
        p_clust <- plotTissue(spe, color = clusters)
        ggsave("plot_tissue_clusters.pdf", plot = p_clust, width = 8, height = 6)
        
        # Save the final SpatialExperiment object
        saveRDS(spe, "spe_output.rds")

    writeLines(c(
        '"BIOC_HOODSCANR_CELLULAR_NEIGHBORHOOD_ANALYSIS":',
        paste0('    hoodscanR: ', as.character(packageVersion('hoodscanR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellular_neighborhood_analysis.csv versions.yml
    """
}

workflow BIOC_HOODSCANR_CELLULAR_NEIGHBORHOOD_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_HOODSCANR_CELLULAR_NEIGHBORHOOD_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HOODSCANR_CELLULAR_NEIGHBORHOOD_ANALYSIS.out.tables
    plots    = BIOC_HOODSCANR_CELLULAR_NEIGHBORHOOD_ANALYSIS.out.plots
    objects  = BIOC_HOODSCANR_CELLULAR_NEIGHBORHOOD_ANALYSIS.out.objects
    versions = BIOC_HOODSCANR_CELLULAR_NEIGHBORHOOD_ANALYSIS.out.versions
}
