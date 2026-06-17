#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Statial — context_aware_spatial_relationships
// Quantify context-aware spatial relationships between cell types using hierarchies and associate them with survival outcomes.
// Input: SingleCellExperiment_object.rds
// Container: quay.io/biocontainers/bioconductor-statial:1.12.0--r45hdfd78af_0
// R packages: BiocStyle, ClassifyR, dplyr, ggplot2, ggsurvfit, lisaClust, SingleCellExperiment, spicyR, Statial, survival, tibble, treekoR
// Bioconductor: 3.20 | R: 4.4
// Requires: ClassifyR, SingleCellExperiment, Statial, dplyr, ggplot2, ggsurvfit, lisaClust, spicyR, survival, tibble, treekoR
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define cell type hierarchy (manually or via treekoR)
//  * 2. [Core Analysis] Calculate pairwise relationships using parentCombinations
//  * 3. [Core Analysis] Run Kontextual to get context-aware spatial metrics
//  * 4. [Input & Preparation] Prepare the matrix using prepMatrix
//  * 5. [Visualization & Output] Perform survival analysis using spicyR::spicy or plot Kaplan-Meier curves

nextflow.enable.dsl = 2

process BIOC_STATIAL_CONTEXT_AWARE_SPATIAL_RELATIONSHIPS {
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
    .bm_deps <- c("BiocStyle", "ClassifyR", "dplyr", "ggplot2", "ggsurvfit", "lisaClust", "SingleCellExperiment", "spicyR", "Statial", "survival", "tibble", "treekoR", "SummarizedExperiment")
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
         library(SummarizedExperiment)
       library(Statial)
        library(spicyR)
        library(ClassifyR)
        library(lisaClust)
        library(dplyr)
        library(ggplot2)
        library(ggsurvfit)
        library(survival)
        library(tibble)
        library(treekoR)
        
        theme_set(theme_classic())
        nCores <- 1
        
        # Read user input
        kerenSCE <- readRDS("SingleCellExperiment_object.rds")
        
        # Dynamically identify the image/sample ID column and standardize to "imageID"
        cd_names <- colnames(colData(kerenSCE))
        if (!"imageID" %in% cd_names) {
          image_col <- grep("image|sample", cd_names, ignore.case = TRUE, value = TRUE)[1]
          if (!is.na(image_col)) {
            kerenSCE\$imageID <- kerenSCE[[image_col]]
          }
        }
        
        all <- unique(kerenSCE\$cellType)
        
        # 1. Data-driven hierarchy using treekoR
        assay_name <- assayNames(kerenSCE)[1]
        if (is.na(assay_name)) assay_name <- 1
        
        treekorParents <- tryCatch({
          kerenTree <- treekoR::getClusterTree(t(assay(kerenSCE, assay_name)),
                                      kerenSCE\$cellType,
                                      hierarchy_method="hopach",
                                      hopach_K = 1)
        
          tp <- getParentPhylo(kerenTree)
          saveRDS(tp, "treekorParents.rds")
          tp
        }, error = function(e) {
          message("treekoR hierarchy calculation skipped or failed: ", e\$message)
          list(all_cells = all)
        })
        
        # Define cellTypeNew for Kontextual demonstration
        kerenSCE\$cellTypeNew <- kerenSCE\$cellType
        marker_vals <- assay(kerenSCE, assay_name)[1, ]
        marker_name <- rownames(assay(kerenSCE, assay_name))[1]
        if (is.null(marker_name)) marker_name <- "Marker1"
        
        markerPos <- marker_vals > median(marker_vals, na.rm = TRUE)
        markerPos[is.na(markerPos)] <- FALSE
        
        target_ct <- all[1]
        other_ct <- all[2]
        if (is.na(other_ct)) other_ct <- target_ct
        
        pos_target_ct <- paste0(marker_name, "_", target_ct)
        kerenSCE\$cellTypeNew[kerenSCE\$cellType == target_ct & markerPos] <- pos_target_ct
        
        # Run Kontextual for a single relationship
        tryCatch({
          single_Kontextual <- Kontextual(
            cells = kerenSCE,
            r = 100,
            from = other_ct,
            to = pos_target_ct,
            parent = c(pos_target_ct, target_ct),
            cellType = "cellTypeNew"
          )
          write.csv(single_Kontextual, "single_Kontextual.csv", row.names = FALSE)
        }, error = function(e) {
          message("Single Kontextual run skipped or failed: ", e\$message)
        })
        
        # Plot Kontextual curves
        tryCatch({
          image_id <- unique(kerenSCE\$imageID)[1]
          curves <- kontextCurve(
            cells = kerenSCE,
            from = other_ct,
            to = pos_target_ct,
            parent = c(pos_target_ct, target_ct),
            rs = seq(50, 510, 50),
            image = image_id,
            cellType = "cellTypeNew",
            cores = nCores
          )
          pdf("kontext_curves.pdf", width = 6, height = 5)
          print(kontextPlot(curves))
          dev.off()
        }, error = function(e) {
          message("Kontext curve plotting skipped or failed: ", e\$message)
        })
        
        # 2. Calculate pairwise relationships using parentCombinations
        parentDf <- parentCombinations(
          all = all,
          parentList = treekorParents
        )
        write.csv(parentDf, "parentCombinations.csv", row.names = FALSE)
        
        # 3. Run Kontextual to get context-aware spatial metrics
        kerenKontextual <- Kontextual(
          cells = kerenSCE,
          parentDf = parentDf,
          r = 100,
          cores = nCores
        )
        write.csv(kerenKontextual, "kerenKontextual.csv", row.names = FALSE)
        
        # Prepare survival columns
        cd_names <- colnames(colData(kerenSCE))
        surv_col <- grep("survival|time|days", cd_names, ignore.case = TRUE, value = TRUE)[1]
        event_col <- grep("censored|event|status|death", cd_names, ignore.case = TRUE, value = TRUE)[1]
        
        if (!is.na(surv_col) && !is.na(event_col)) {
          if (grepl("cens", event_col, ignore.case = TRUE)) {
            kerenSCE\$event <- 1 - as.numeric(kerenSCE[[event_col]])
          } else {
            kerenSCE\$event <- as.numeric(kerenSCE[[event_col]])
          }
          kerenSCE\$survival <- Surv(as.numeric(kerenSCE[[surv_col]]), kerenSCE\$event)
        }
        
        # 4. Prepare the matrix using prepMatrix
        kontextMat <- prepMatrix(kerenKontextual)
        valid_ids <- intersect(as.character(unique(kerenSCE\$imageID)), rownames(kontextMat))
        kontextMat <- kontextMat[valid_ids, , drop = FALSE]
        kontextMat[is.na(kontextMat)] <- 0
        saveRDS(kontextMat, "kontextMat.rds")
        
        # 5. Perform survival analysis using spicyR::spicy
        if (!is.null(kerenSCE\$survival)) {
          survivalResults = spicy(cells = kerenSCE,
                                  alternateResult = kontextMat,
                                  condition = "survival",
                                  weights = TRUE)
          saveRDS(survivalResults, "survivalResults.rds")
          write.csv(survivalResults\$survivalResults, "survivalResults.csv", row.names = FALSE)
          
          # Plot significance plot
          tryCatch({
            pdf("signif_plot.pdf", width = 8, height = 6)
            print(signifPlot(survivalResults))
            dev.off()
          }, error = function(e) {
            message("Significance plot skipped or failed: ", e\$message)
          })
          
          # Plot Kaplan-Meier curves
          tryCatch({
            survData <- kerenSCE |>
              colData() |>
              data.frame() |>
              select(imageID, survival) |>
              unique()
          
            kerenSurv <- survData\$survival
            names(kerenSurv) <- as.character(survData\$imageID)
          
            top_rel <- survivalResults\$survivalResults\$test[1]
            if (!is.na(top_rel)) {
              survRelationship <- kontextMat[, top_rel]
              survRelationship <- ifelse(survRelationship > median(survRelationship, na.rm = TRUE), "Localised", "Dispersed")
            
              # Align by name to prevent mismatched survival times and relationships
              common_ids <- intersect(names(kerenSurv), names(survRelationship))
              kerenSurv_aligned <- kerenSurv[common_ids]
              survRelationship_aligned <- survRelationship[common_ids]
            
              pdf("kaplan_meier_curve.pdf", width = 6, height = 5)
              p_km <- survfit2(kerenSurv_aligned ~ survRelationship_aligned) |>
                ggsurvfit() +
                ggtitle(top_rel)
              print(p_km)
              dev.off()
            }
          }, error = function(e) {
            message("Kaplan-Meier curve plotting skipped or failed: ", e\$message)
          })
        } else {
          message("Survival data not found, skipping survival analysis.")
        }

    writeLines(c(
        '"BIOC_STATIAL_CONTEXT_AWARE_SPATIAL_RELATIONSHIPS":',
        paste0('    Statial: ', as.character(packageVersion('Statial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_context_aware_spatial_relationships.csv versions.yml
    """
}

workflow BIOC_STATIAL_CONTEXT_AWARE_SPATIAL_RELATIONSHIPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SingleCellExperiment_object.rds ] ]

    main:
    BIOC_STATIAL_CONTEXT_AWARE_SPATIAL_RELATIONSHIPS(ch_input)

    emit:
    tables   = BIOC_STATIAL_CONTEXT_AWARE_SPATIAL_RELATIONSHIPS.out.tables
    plots    = BIOC_STATIAL_CONTEXT_AWARE_SPATIAL_RELATIONSHIPS.out.plots
    objects  = BIOC_STATIAL_CONTEXT_AWARE_SPATIAL_RELATIONSHIPS.out.objects
    versions = BIOC_STATIAL_CONTEXT_AWARE_SPATIAL_RELATIONSHIPS.out.versions
}
