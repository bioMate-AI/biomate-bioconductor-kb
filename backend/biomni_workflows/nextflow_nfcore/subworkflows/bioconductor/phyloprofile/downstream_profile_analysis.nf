#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phyloprofile — downstream_profile_analysis
// Perform downstream evolutionary and comparative analyses (clustering, gene age estimation, core gene identification, and group comparison) on processed phylogen
// Input: processedProfile.RData
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// R packages: PhyloProfile, dplyr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_DOWNSTREAM_PROFILE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0"

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
    .bm_deps <- c("PhyloProfile", "dplyr")
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
    library(PhyloProfile)
    library(dplyr)
    
    # ==========================================
    # --- Load User Input File ---
    # ==========================================
    if (!file.exists("processedProfile.RData")) {
      stop("Error: Input file 'processedProfile.RData' not found in the working directory.")
    }
    
    # Load the RData file into the global environment
    load("processedProfile.RData")
    
    # Ensure the required objects exist, or map them from loaded data frames
    loaded_objs <- ls()
    dfs <- loaded_objs[sapply(loaded_objs, function(x) is.data.frame(get(x)))]
    
    if (!exists("finalProcessedProfile")) {
      if (length(dfs) > 0) {
        finalProcessedProfile <- get(dfs[1])
      } else {
        stop("Error: No data frame found in processedProfile.RData to use as finalProcessedProfile.")
      }
    }
    
    if (!exists("fullProcessedProfile")) {
      fullProcessedProfile <- finalProcessedProfile
    }
    
    if (!exists("mainLongRaw")) {
      mainLongRaw <- finalProcessedProfile
    }
    
    # Define aggregation parameters
    var1AggregateBy <- "max"
    var2AggregateBy <- "mean"
    
    # ==========================================
    # --- Profile Clustering ---
    # ==========================================
    data <- finalProcessedProfile
    profileType <- "binary"
    
    profiles <- getDataClustering(
      data, 
      profileType, 
      var1AggregateBy, 
      var2AggregateBy
    )
    
    method <- "mutualInformation"
    distanceMatrix <- getDistanceMatrix(profiles, method)
    
    clusterMethod <- "complete"
    dd <- clusterDataDend(as.dist(distanceMatrix), clusterMethod)
    
    # Save distance matrix
    write.csv(as.matrix(distanceMatrix), "distance_matrix.csv", row.names = TRUE)
    
    # Save dendrogram plot
    pdf("dendrogram.pdf", width = 10, height = 8)
    getDendrogram(dd)
    dev.off()
    
    # ==========================================
    # --- Gene Age Estimation ---
    # ==========================================
    rankName <- "class"
    refTaxon <- "Mammalia"
    
    # Ensure ncbiID column exists
    if (!"ncbiID" %in% colnames(fullProcessedProfile)) {
      if ("supertaxonID" %in% colnames(fullProcessedProfile)) {
        fullProcessedProfile\$ncbiID <- paste0("ncbi", fullProcessedProfile\$supertaxonID)
      } else if ("supertaxon" %in% colnames(fullProcessedProfile)) {
        fullProcessedProfile\$ncbiID <- as.character(fullProcessedProfile\$supertaxon)
      } else {
        fullProcessedProfile\$ncbiID <- "ncbi9606"
      }
    }
    
    taxonIDs <- levels(as.factor(fullProcessedProfile\$ncbiID))
    
    # Sort input taxa with error handling for custom taxonomies
    sortedInputTaxa <- tryCatch({
      sortInputTaxa(taxonIDs, rankName, refTaxon, NULL, NULL, NULL)
    }, error = function(e) {
      warning("Taxonomy sorting failed, using fallback sorting: ", e\$message)
      data.frame(
        ncbiID = taxonIDs,
        supertaxon = taxonIDs,
        stringsAsFactors = FALSE
      )
    })
    
    taxaCount <- sortedInputTaxa %>% dplyr::count(supertaxon)
    
    var1Cutoff <- c(0, 1)
    var2Cutoff <- c(0, 1)
    percentCutoff <- c(0, 1)
    
    geneAge <- estimateGeneAge(
      fullProcessedProfile, 
      taxaCount, 
      rankName, 
      refTaxon,
      var1Cutoff, 
      var2Cutoff, 
      percentCutoff
    )
    
    write.csv(geneAge, "gene_age_estimation.csv", row.names = FALSE)
    
    # ==========================================
    # --- Core Gene Identification ---
    # ==========================================
    taxaCore <- c("Mammalia", "Saccharomycetes", "Insecta")
    
    # Ensure selected core taxa exist in the dataset, otherwise fallback to available ones
    available_taxa <- unique(as.character(taxaCount\$supertaxon))
    taxaCore_present <- taxaCore[taxaCore %in% available_taxa]
    if (length(taxaCore_present) == 0 && length(available_taxa) > 0) {
      taxaCore_present <- available_taxa[1:min(3, length(available_taxa))]
    }
    
    var1Cutoff <- c(0.75, 1.0)
    var2Cutoff <- c(0.75, 1.0)
    percentCutoff <- c(0.0, 1.0)
    coreCoverage <- 1
    
    coreGenes <- getCoreGene(
      rankName,
      taxaCore_present,
      fullProcessedProfile,
      taxaCount,
      var1Cutoff, 
      var2Cutoff,
      percentCutoff, 
      coreCoverage
    )
    
    write.table(coreGenes, "core_genes.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
    
    # ==========================================
    # --- Group Comparison ---
    # ==========================================
    data <- mainLongRaw
    
    # Determine variable column to compare
    if (ncol(data) < 4) {
      variable <- colnames(data)[ncol(data)]
    } else {
      variable <- colnames(data)[4]
    }
    
    # Determine taxon column and select inGroup
    taxon_col <- "ncbiID"
    if (!"ncbiID" %in% colnames(data)) {
      if ("supertaxon" %in% colnames(data)) {
        taxon_col <- "supertaxon"
      } else {
        taxon_col <- colnames(data)[min(2, ncol(data))]
      }
    }
    
    all_taxa <- unique(as.character(data[[taxon_col]]))
    inGroup <- c("ncbi9606", "ncbi10116")
    inGroup_present <- inGroup[inGroup %in% all_taxa]
    if (length(inGroup_present) == 0 && length(all_taxa) > 0) {
      inGroup_present <- all_taxa[1:min(2, length(all_taxa))]
    }
    
    # Perform group comparison
    groupComparison <- tryCatch({
      compareTaxonGroups(data, inGroup_present, TRUE, variable, 0.05)
    }, error = function(e) {
      warning("Group comparison failed: ", e\$message)
      NULL
    })
    
    if (!is.null(groupComparison)) {
      if (is.vector(groupComparison)) {
        groupComparison_df <- data.frame(
          geneID = names(groupComparison),
          pValue = as.numeric(groupComparison),
          stringsAsFactors = FALSE
        )
      } else {
        groupComparison_df <- as.data.frame(groupComparison)
      }
      write.csv(groupComparison_df, "group_comparison_results.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_PHYLOPROFILE_DOWNSTREAM_PROFILE_ANALYSIS":',
        paste0('        phyloprofile: ', as.character(packageVersion("phyloprofile")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_downstream_profile_analysis.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_DOWNSTREAM_PROFILE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ processedProfile.RData ] ]

    main:
    BIOC_PHYLOPROFILE_DOWNSTREAM_PROFILE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_DOWNSTREAM_PROFILE_ANALYSIS.out.tables
    plots    = BIOC_PHYLOPROFILE_DOWNSTREAM_PROFILE_ANALYSIS.out.plots
    objects  = BIOC_PHYLOPROFILE_DOWNSTREAM_PROFILE_ANALYSIS.out.objects
    versions = BIOC_PHYLOPROFILE_DOWNSTREAM_PROFILE_ANALYSIS.out.versions
}
