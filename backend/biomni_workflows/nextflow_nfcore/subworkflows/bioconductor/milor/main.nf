#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miloR — standard_da_glm
// Perform standard differential abundance testing using a Negative Binomial GLM, followed by neighbourhood annotation, grouping, and marker gene identification.
// Input: embryo_data, embryo_design
// Container: quay.io/biocontainers/bioconductor-milor:2.6.0--r45ha27e39d_0
// R packages: SingleCellExperiment, dplyr, ExperimentHub, miloR, patchwork, scater, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, dplyr, miloR, patchwork, scater, scran
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create Milo object
//  * 2. [Input & Preparation] Build KNN graph
//  * 3. [Input & Preparation] Define representative neighbourhoods
//  * 4. [Core Analysis] Count cells in neighbourhoods
//  * 5. [Core Analysis] Compute neighbourhood connectivity (distances)
//  * 6. [Core Analysis] Test for differential abundance
//  * 7. [Core Analysis] Annotate and group neighbourhoods
//  * 8. [Core Analysis] Find marker genes for neighbourhood groups
//  * 9. [Core Analysis] Perform differential expression within a group

nextflow.enable.dsl = 2

process BIOC_MILOR_STANDARD_DA_GLM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    .bm_deps <- c("SingleCellExperiment", "dplyr", "ExperimentHub", "miloR", "patchwork", "scater", "scran", "SummarizedExperiment")
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
        library(miloR)
        library(SummarizedExperiment)
        library(scater)
        library(scran)
        library(dplyr)
        library(patchwork)
        
        # 1. Load user input files from the working directory
        embryo_data <- readRDS("embryo_data.rds")
        embryo_design <- readRDS("embryo_design.rds")
        
        # 2. Create Milo object
        embryo_milo <- Milo(embryo_data)
        
        # Dynamically identify the first reduced dimension to avoid hardcoding
        red_dim <- reducedDimNames(embryo_milo)[1]
        
        # 3. Build KNN graph
        embryo_milo <- buildGraph(embryo_milo, k = 30, d = 30, reduced.dim = red_dim)
        
        # 4. Define representative neighbourhoods
        embryo_milo <- makeNhoods(embryo_milo, prop = 0.1, k = 30, d=30, refined = TRUE, reduced_dims = red_dim)
        
        # Plot and save neighbourhood size histogram
        pdf("nhood_size_histogram.pdf")
        plotNhoodSizeHist(embryo_milo)
        dev.off()
        
        # 5. Count cells in neighbourhoods
        embryo_milo <- countCells(embryo_milo, meta.data = as.data.frame(colData(embryo_milo)), samples="sample")
        
        # 6. Compute neighbourhood connectivity (distances)
        embryo_milo <- calcNhoodDistance(embryo_milo, d=30, reduced.dim = red_dim)
        
        # 7. Test for differential abundance
        # Dynamically construct design formula from embryo_design columns
        if ("sample" %in% colnames(embryo_design)) {
          rownames(embryo_design) <- embryo_design\$sample
          design_cols <- setdiff(colnames(embryo_design), "sample")
        } else {
          design_cols <- colnames(embryo_design)
        }
        design_form <- as.formula(paste("~", paste(design_cols, collapse=" + ")))
        
        da_results <- testNhoods(embryo_milo, design = design_form, design.df = embryo_design, reduced.dim=red_dim)
        
        # 8. Build neighbourhood graph
        embryo_milo <- buildNhoodGraph(embryo_milo)
        
        # 9. Annotate and group neighbourhoods
        # Dynamically identify a celltype column from colData
        cd_colnames <- colnames(colData(embryo_milo))
        possible_cols <- setdiff(cd_colnames, c("sample", "barcode", "cell", "sizeFactor"))
        celltype_col <- grep("celltype|cluster|ident|label|type", possible_cols, ignore.case=TRUE, value=TRUE)[1]
        if (is.na(celltype_col)) {
          celltype_col <- possible_cols[1]
        }
        
        da_results <- annotateNhoods(embryo_milo, da_results, coldata_col = celltype_col)
        da_results <- groupNhoods(embryo_milo, da_results, max.lfc.delta = 10, overlap=1)
        
        # 10. Find marker genes for neighbourhood groups
        # Compute log-normalized counts before running modelGeneVar to prevent runtime errors
        embryo_milo <- logNormCounts(embryo_milo)
        
        # Compute highly variable genes (hvgs) as required by findNhoodGroupMarkers
        dec <- modelGeneVar(embryo_milo)
        hvgs <- getTopHVGs(dec, n=2000)
        
        nhood_markers <- findNhoodGroupMarkers(embryo_milo, da_results, subset.row = hvgs, aggregate.samples = TRUE, sample_col = "sample")
        
        # 11. Perform differential expression within a group (robustly handled in case group "6" is absent)
        # Ensure design columns are present in meta_data for testDiffExp
        meta_data <- as.data.frame(colData(embryo_milo))
        for (col in design_cols) {
          if (!(col %in% colnames(meta_data))) {
            if ("sample" %in% colnames(embryo_design)) {
              meta_data[[col]] <- embryo_design[[col]][match(meta_data\$sample, embryo_design\$sample)]
            } else {
              meta_data[[col]] <- embryo_design[[col]][match(meta_data\$sample, rownames(embryo_design))]
            }
          }
        }
        
        dge_6 <- tryCatch({
          if ("6" %in% da_results\$NhoodGroup) {
            testDiffExp(embryo_milo, da_results, design = design_form, meta.data = meta_data, subset.nhoods=da_results\$NhoodGroup=="6")
          } else {
            message("NhoodGroup '6' not found in grouping results. Skipping testDiffExp.")
            NULL
          }
        }, error = function(e) {
          warning("Error in testDiffExp: ", e\$message)
          NULL
        })
        
        # 12. Save outputs
        write.csv(da_results, "da_results.csv", row.names = FALSE)
        write.csv(nhood_markers, "nhood_markers.csv", row.names = FALSE)
        if (!is.null(dge_6)) {
          saveRDS(dge_6, "dge_6_results.rds")
        }
        saveRDS(embryo_milo, "embryo_milo_final.rds")

    writeLines(c(
        '"BIOC_MILOR_STANDARD_DA_GLM":',
        paste0('    miloR: ', as.character(packageVersion('miloR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_da_glm.csv versions.yml
    """
}

workflow BIOC_MILOR_STANDARD_DA_GLM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ embryo_data, embryo_design ] ]

    main:
    BIOC_MILOR_STANDARD_DA_GLM(ch_input)

    emit:
    tables   = BIOC_MILOR_STANDARD_DA_GLM.out.tables
    plots    = BIOC_MILOR_STANDARD_DA_GLM.out.plots
    objects  = BIOC_MILOR_STANDARD_DA_GLM.out.objects
    versions = BIOC_MILOR_STANDARD_DA_GLM.out.versions
}
