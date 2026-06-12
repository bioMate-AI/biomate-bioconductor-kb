#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowPlots — compute_summary_data
// Compute profile, marginal, PFD, and PFD parts summary datasets from stacked ICS flow cytometry data using the StackedData class.
// Input: stacked_data.csv
// Container: quay.io/biocontainers/bioconductor-flowplots:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowPlots
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize StackedData object
//  * 2. [Input & Preparation] Define and assign marker combinations
//  * 3. [Core Analysis] Compute and assign profile data
//  * 4. [Core Analysis] Compute and assign marginal data
//  * 5. [Core Analysis] Compute and assign PFD data
//  * 6. [Core Analysis] Compute and assign PFD parts data

nextflow.enable.dsl = 2

process BIOC_FLOWPLOTS_COMPUTE_SUMMARY_DATA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("flowPlots")
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
    library(flowPlots)
    
    # 1. Read the user input file
    # The input file 'stacked_data.csv' is expected to be in the working directory.
    stackedDF <- read.csv("stacked_data.csv", stringsAsFactors = FALSE)
    
    # Initialize StackedData object
    stackedDataObject <- new("StackedData", stackedData = stackedDF)
    
    # Compute markers
    markerNames <- c("TNFa", "IL6", "IL12", "IFNa")
    markers <- computeMarkers(markerNames, includeAllNegativeRow = TRUE)
    markers(stackedDataObject) <- markers
    
    # Compute summary datasets
    byVarNames <- c("stim", "concGroup", "cell")
    
    profileData <- computeProfileData(stackedDataObject, byVarNames, "id", "percentAll", "group")
    profileData(stackedDataObject) <- profileData
    
    marginalData <- computeMarginalData(stackedDataObject, byVarNames, "id", "percentAll", "group")
    marginalData(stackedDataObject) <- marginalData
    
    pfdData <- computePFDData(stackedDataObject, byVarNames, "id", "percentAll", "group")
    pfdData(stackedDataObject) <- pfdData
    
    pfdPartsData <- computePFDPartsData(stackedDataObject, byVarNames, "id", "percentAll", "group")
    pfdPartsData(stackedDataObject) <- pfdPartsData
    
    # Write summary datasets to CSV files
    write.csv(profileData, "profile_data.csv", row.names = FALSE)
    write.csv(marginalData, "marginal_data.csv", row.names = FALSE)
    write.csv(pfdData, "pfd_data.csv", row.names = FALSE)
    for (i in seq_along(pfdPartsData)) {
        write.csv(pfdPartsData[[i]], paste0("pfd_parts_data_", i, ".csv"), row.names = FALSE)
    }
    
    # Use the computed profile data for plotting
    profileDF <- profileData
    
    # Subset the summary data for the condition of interest robustly.
    # If the input is already subsetted, we use it directly.
    profileDataSubset <- profileDF
    main_title <- "Profile Data"
    if (all(byVarNames %in% colnames(profileDF))) {
        # Pick the first unique combination of byVarNames to plot
        cond <- profileDF[1, byVarNames, drop = FALSE]
        subset_idx <- rep(TRUE, nrow(profileDF))
        for (v in byVarNames) {
            subset_idx <- subset_idx & (profileDF[[v]] == cond[[v]][1])
        }
        profileDataSubset <- profileDF[subset_idx, , drop = FALSE]
        main_title <- paste(paste(byVarNames, cond[1, ], sep=" = "), collapse=", ")
    }
    
    # 2. Define x-axis labels using markerMatrix and determine markers
    # We programmatically reconstruct the markerMatrix using computeMarkers to avoid data() calls.
    first_col <- colnames(profileDataSubset)[1]
    detected_markers <- unlist(strsplit(first_col, "[+-]"))
    detected_markers <- detected_markers[detected_markers != ""]
    
    if (length(detected_markers) > 0) {
        theMarkers <- detected_markers
    } else {
        theMarkers <- c("TNFa", "IL6", "IL12", "IFNa")
    }
    
    markerMatrix <- computeMarkers(theMarkers, includeAllNegativeRow = TRUE)
    xTickLabels <- cbind(theMarkers, t(markerMatrix))
    
    # 3. Prepare the data list using makeDataList
    num_marker_cols <- 2^length(theMarkers)
    groupDataList <- makeDataList(profileDataSubset, "group", 1:num_marker_cols)
    
    # Save the prepared data list to an RDS file
    saveRDS(groupDataList, file = "group_data_list.rds")
    
    # 4. Plot the group comparisons using GroupListBoxplot and save to PDF
    unique_groups <- as.character(unique(profileDataSubset\$group))
    num_groups <- length(unique_groups)
    group_colors <- seq_len(num_groups) + 1
    
    pdf("group_comparison_boxplot.pdf", width = 12, height = 8)
    
    GroupListBoxplot(groupDataList, xlabel="", 
       ylabel="Percent of All Cells", boxOutliers=FALSE,
       xAxisLabels=xTickLabels, xMtext="Marker Category", 
       mainTitle=main_title, 
       legendGroupNames=unique_groups, pointColor=group_colors,    
       testTitleCEX=.8, nCEX=.6, pCEX=.6, legendColor=group_colors, legendCEX=.6,
       xAxisCEX=.7, xAtMtext=-1)
    mtext("PROFILE DATA", side=3, line=2)
    
    dev.off()

    writeLines(c(
        '"BIOC_FLOWPLOTS_COMPUTE_SUMMARY_DATA":',
        paste0('    flowPlots: ', as.character(packageVersion('flowPlots')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compute_summary_data.csv versions.yml
    """
}

workflow BIOC_FLOWPLOTS_COMPUTE_SUMMARY_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ stacked_data.csv ] ]

    main:
    BIOC_FLOWPLOTS_COMPUTE_SUMMARY_DATA(ch_input)

    emit:
    tables   = BIOC_FLOWPLOTS_COMPUTE_SUMMARY_DATA.out.tables
    plots    = BIOC_FLOWPLOTS_COMPUTE_SUMMARY_DATA.out.plots
    objects  = BIOC_FLOWPLOTS_COMPUTE_SUMMARY_DATA.out.objects
    versions = BIOC_FLOWPLOTS_COMPUTE_SUMMARY_DATA.out.versions
}
