#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ComPrAn — protein_only_workflow
// Analyze SILAC complexome profiling data starting directly from pre-normalized protein intensity tables to perform clustering and visualization.
// Input: normalized_proteins.txt, exampleGroup.txt
// Container: quay.io/biocontainers/bioconductor-compran:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComPrAn, data.table
// Visualizations: heatmap, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import normalized protein data
//  * 2. [Visualization & Output] Visualize individual protein profiles
//  * 3. [Visualization & Output] Visualize group profiles and co-migration
//  * 4. [Core Analysis] Perform hierarchical clustering
//  * 5. [Visualization & Output] Assign clusters and export results
//  * 6. [Visualization & Output] Visualize cluster summaries

nextflow.enable.dsl = 2

process BIOC_COMPRAN_PROTEIN_ONLY_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("ComPrAn", "data.table")
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
    library(ComPrAn)
    library(data.table)
    
    # 1. Import normalized protein data
    inputFile <- "normalized_proteins.txt"
    forAnalysis <- protImportForAnalysis(inputFile)
    
    # Determine max fraction dynamically from the column names of forAnalysis
    # The columns "1" to "n" are numeric fraction columns.
    fraction_cols <- grep("^[0-9]+\$", colnames(forAnalysis), value = TRUE)
    if (length(fraction_cols) > 0) {
      max_frac <- max(as.numeric(fraction_cols))
    } else {
      max_frac <- 23
    }
    
    # Determine a valid protein for individual plotting
    protein <- "P52815"
    if (!(protein %in% forAnalysis[["Protein Group Accessions"]])) {
      protein <- forAnalysis[["Protein Group Accessions"]][1]
    }
    
    # 2. Visualize individual protein profiles
    pdf("protein_profile_plot.pdf")
    proteinPlot(forAnalysis[forAnalysis\$scenario == "B" ,], protein, max_frac)
    dev.off()
    
    # 3. Visualize group profiles and co-migration
    groupDataFileName <- "exampleGroup.txt"
    groupName <- 'group1'
    groupData <- data.table::fread(groupDataFileName)
    
    pdf("group_heatmap.pdf")
    groupHeatMap(dataFrame = forAnalysis[forAnalysis\$scenario == "B" ,], groupData, groupName)
    dev.off()
    
    # Extract proteins from groupData if available to make the vectors realistic
    id_col <- grep("Accession", colnames(groupData), value = TRUE)
    if (length(id_col) == 0) id_col <- colnames(groupData)[1]
    group_prots <- unique(as.character(groupData[[id_col]]))
    
    groupDataVector <- c("Q16540", "P52815", "P09001", "Q13405", "Q9H2W6")
    # If the hardcoded ones aren't in the dataset, use the ones from the group file
    if (!any(groupDataVector %in% forAnalysis[["Protein Group Accessions"]]) && length(group_prots) > 0) {
      groupDataVector <- intersect(group_prots, forAnalysis[["Protein Group Accessions"]])
      if (length(groupDataVector) == 0) {
        groupDataVector <- head(unique(forAnalysis[["Protein Group Accessions"]]), 5)
      }
    }
    
    pdf("one_group_two_labels_co_migration.pdf")
    oneGroupTwoLabelsCoMigration(forAnalysis, max_frac = max_frac, groupDataVector, groupName)
    dev.off()
    
    group1DataVector <- c("Q16540", "P52815", "P09001", "Q13405", "Q9H2W6")
    if (!any(group1DataVector %in% forAnalysis[["Protein Group Accessions"]]) && length(group_prots) > 0) {
      group1DataVector <- intersect(group_prots, forAnalysis[["Protein Group Accessions"]])
      if (length(group1DataVector) == 0) {
        group1DataVector <- head(unique(forAnalysis[["Protein Group Accessions"]]), 5)
      }
    }
    group1Name <- 'group1'
    
    group2DataVector <- c("Q9NVS2", "Q9NWU5", "Q9NX20", "Q9NYK5", "Q9NZE8")
    if (!any(group2DataVector %in% forAnalysis[["Protein Group Accessions"]])) {
      all_prots <- unique(forAnalysis[["Protein Group Accessions"]])
      remaining_prots <- setdiff(all_prots, group1DataVector)
      if (length(remaining_prots) >= 5) {
        group2DataVector <- remaining_prots[1:5]
      } else {
        group2DataVector <- head(all_prots, 5)
      }
    }
    group2Name <- 'group2'
    
    pdf("two_groups_within_label_co_migration.pdf")
    twoGroupsWithinLabelCoMigration(dataFrame = forAnalysis, max_frac = max_frac, group1Data = group1DataVector, group1Name = group1Name, group2Data = group2DataVector, group2Name = group2Name)
    dev.off()
    
    # 4. Perform hierarchical clustering
    clusteringDF <- clusterComp(forAnalysis, scenar = "A", PearsCor = "centered")
    saveRDS(clusteringDF, "clustering_components.rds")
    
    # 5. Assign clusters and export results
    labTab_clust <- assignClusters(.listDf = clusteringDF, sample = "labeled", method = 'average', cutoff = 0.85)
    unlabTab_clust <- assignClusters(.listDf = clusteringDF, sample = "unlabeled", method = 'average', cutoff = 0.85)
    
    tableForClusterExport <- exportClusterAssignments(labTab_clust, unlabTab_clust)
    write.table(tableForClusterExport, "cluster_assignments.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # 6. Visualize cluster summaries
    pdf("cluster_summary_plots.pdf")
    makeBarPlotClusterSummary(labTab_clust, name = 'labeled')
    makeBarPlotClusterSummary(unlabTab_clust, name = 'unlabeled')
    dev.off()

    writeLines(c(
        '"BIOC_COMPRAN_PROTEIN_ONLY_WORKFLOW":',
        paste0('    ComPrAn: ', as.character(packageVersion('ComPrAn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_only_workflow.csv versions.yml
    """
}

workflow BIOC_COMPRAN_PROTEIN_ONLY_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ normalized_proteins.txt, exampleGroup.txt ] ]

    main:
    BIOC_COMPRAN_PROTEIN_ONLY_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_COMPRAN_PROTEIN_ONLY_WORKFLOW.out.tables
    plots    = BIOC_COMPRAN_PROTEIN_ONLY_WORKFLOW.out.plots
    objects  = BIOC_COMPRAN_PROTEIN_ONLY_WORKFLOW.out.objects
    versions = BIOC_COMPRAN_PROTEIN_ONLY_WORKFLOW.out.versions
}
