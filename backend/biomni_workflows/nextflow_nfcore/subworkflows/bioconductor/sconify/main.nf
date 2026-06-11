#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Sconify — scone_differential_analysis
// Perform KNN-based differential expression and abundance analysis on CyTOF data, including neighborhood size optimization, statistical testing, t-SNE visualizati
// Input: markers.csv, cell_data.csv
// Container: quay.io/biocontainers/bioconductor-sconify:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Sconify, dplyr, magrittr, tibble
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse marker classifications into input (static) and functional markers using ParseMarkers
//  * 2. [Core Analysis] Optimize the neighborhood size parameter k using ImputeTesting
//  * 3. [Core Analysis] Generate the k-nearest neighbor matrix using Fnn
//  * 4. [Core Analysis] Compute fold changes and statistical significance (q-values) per KNN using SconeValues
//  * 5. [Core Analysis] Merge Scone statistics with original cell data and compute t-SNE coordinates using PostProcessing (or SubsampleAndTsne for large d
//  * 6. [Visualization & Output] Visualize results using MakeHist and TsneVis
//  * 7. [Core Analysis] Optionally extract KNN lists or density estimations using MakeKnnList and GetKnnDe

nextflow.enable.dsl = 2

process BIOC_SCONIFY_SCONE_DIFFERENTIAL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Sconify", "dplyr", "magrittr")
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
        library(Sconify)
        library(dplyr)
        library(magrittr)
        
        # ==========================================
        # 1. Parse Marker Classifications
        # ==========================================
        # Read the user-provided markers.csv file from the working directory
        marker.file <- "markers.csv"
        markers <- ParseMarkers(marker.file)
        
        input.markers <- markers[[1]]
        funct.markers <- markers[[2]]
        
        # ==========================================
        # Data Preparation from User Input
        # ==========================================
        # Read the concatenated single-cell expression data
        wand.combined <- read.csv("cell_data.csv", check.names = FALSE)
        
        # Ensure 'condition' column exists and has "basal" and "IL7" to match the vignette's hardcoded names
        if (!"condition" %in% colnames(wand.combined)) {
          wand.combined\$condition <- rep(c("basal", "IL7"), length.out = nrow(wand.combined))
        } else {
          # Map non-basal condition to "IL7" to ensure output columns match the vignette's "IL7" suffix
          wand.combined\$condition <- ifelse(wand.combined\$condition == "basal", "basal", "IL7")
        }
        
        # Convert to tibble as Sconify functions are optimized for tibbles
        if (requireNamespace("tibble", quietly = TRUE)) {
          wand.combined <- tibble::as_tibble(wand.combined)
        }
        
        # Subset the data for the stimulated condition (IL7)
        wand.il7 <- wand.combined %>% filter(condition == "IL7")
        
        # ==========================================
        # 2. Optimize Neighborhood Size (k)
        # ==========================================
        wand.k.titration <- 1 : 100 %>% .[. %% 10 == 0 ]
        wand.ideal.k <- ImputeTesting ( k.titration = wand.k.titration, cells = wand.il7, input.markers = input.markers, test.markers = funct.markers)
        
        # Save the ideal k titration results
        saveRDS(wand.ideal.k, "wand_ideal_k.rds")
        
        # ==========================================
        # 3. Generate k-Nearest Neighbor Matrix
        # ==========================================
        k <- as.numeric(names(which.min(wand.ideal.k)))
        wand.nn <- Fnn(cell.df = wand.combined, input.markers = input.markers, k = k)
        
        # ==========================================
        # 4. Compute Fold Changes and Significance
        # ==========================================
        wand.scone <- SconeValues(nn.matrix = wand.nn, cell.data = wand.combined, scone.markers = funct.markers, unstim = "basal")
        
        # ==========================================
        # 5. Merge Statistics and Compute t-SNE
        # ==========================================
        wand.final <- PostProcessing ( scone.output = wand.scone, cell.data = wand.combined, input = input.markers)
        wand.final.sub <- SubsampleAndTsne ( dat = wand.final, input = input.markers, numcells = 500 )
        
        # Save processed data tables
        write.csv(wand.final, "wand_final.csv", row.names = FALSE)
        saveRDS(wand.final, "wand_final.rds")
        
        if (!is.null(wand.final.sub)) {
          write.csv(wand.final.sub, "wand_final_subsampled.csv", row.names = FALSE)
          saveRDS(wand.final.sub, "wand_final_subsampled.rds")
        }
        
        # ==========================================
        # 6. Visualize Results
        # ==========================================
        pdf("sconify_plots.pdf", width = 8, height = 6)
        
        fraction_col <- grep("fraction\\\\.cond", colnames(wand.final), value = TRUE)[1]
        
        tryCatch({
          p1 <- MakeHist (wand.final, k , fraction_col , "fraction IL7" )
          print(p1\$plot)
        }, error = function(e) message("MakeHist failed: ", e\$message))
        
        tryCatch({
          p2 <- TsneVis (wand.final, input.markers[1] , paste("Raw", input.markers[1], "expression") )
          print(p2\$plot)
        }, error = function(e) message("TsneVis input marker failed: ", e\$message))
        
        tryCatch({
          p3 <- TsneVis (wand.final, fraction_col , "Fraction cells in IL7 condition" )
          print(p3\$plot)
        }, error = function(e) message("TsneVis IL7 fraction failed: ", e\$message))
        
        tryCatch({
          p4 <- TsneVis (wand.final, paste0(funct.markers[1], ".IL7.change") , paste("IL7 ->", funct.markers[1], "change") )
          print(p4\$plot)
        }, error = function(e) message("TsneVis functional change failed: ", e\$message))
        
        tryCatch({
          p5 <- TsneVis (wand.final, paste0(funct.markers[1], ".IL7.qvalue") , paste("IL7 ->", funct.markers[1], "-log10(qvalue)") )
          print(p5\$plot)
        }, error = function(e) message("TsneVis functional qvalue failed: ", e\$message))
        
        tryCatch({
          p6 <- TsneVis (wand.final, "density" )
          print(p6\$plot)
        }, error = function(e) message("TsneVis density failed: ", e\$message))
        
        dev.off()
        
        # ==========================================
        # 7. Extract KNN Lists and Density Estimations
        # ==========================================
        wand.knn.list <- MakeKnnList(cell.data = wand.combined, nn.matrix = wand.nn)
        wand.knn.density <- GetKnnDe(nn.matrix = wand.nn)
        
        # Save KNN lists and density estimations
        saveRDS(wand.knn.list, "wand_knn_list.rds")
        saveRDS(wand.knn.density, "wand_knn_density.rds")

    writeLines(c(
        '"BIOC_SCONIFY_SCONE_DIFFERENTIAL_ANALYSIS":',
        paste0('    Sconify: ', as.character(packageVersion('Sconify')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scone_differential_analysis.csv versions.yml
    """
}

workflow BIOC_SCONIFY_SCONE_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ markers.csv, cell_data.csv ] ]

    main:
    BIOC_SCONIFY_SCONE_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCONIFY_SCONE_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_SCONIFY_SCONE_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_SCONIFY_SCONE_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_SCONIFY_SCONE_DIFFERENTIAL_ANALYSIS.out.versions
}
