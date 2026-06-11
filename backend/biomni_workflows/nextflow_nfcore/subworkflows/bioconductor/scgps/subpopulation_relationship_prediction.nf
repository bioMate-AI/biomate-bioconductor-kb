#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scGPS — subpopulation_relationship_prediction
// Estimate transition and relationship scores between subpopulations within one sample or between two samples and visualize them as a Sankey network.
// Input: mixedpop1, mixedpop2, genes
// Container: quay.io/biocontainers/bioconductor-scgps:1.24.0--r45ha27e39d_0
// R packages: dplyr, networkD3, scGPS
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, networkD3, scGPS
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run bootstrap prediction using LDA and Lasso/ElasticNet classifiers
//  * 2. [Visualization & Output] Summarize prediction results, accuracy, and deviance
//  * 3. [Visualization & Output] Reformat prediction results for Sankey visualization
//  * 4. [Visualization & Output] Plot the relationship network using networkD3

nextflow.enable.dsl = 2

process BIOC_SCGPS_SUBPOPULATION_RELATIONSHIP_PREDICTION {
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
    .bm_deps <- c("dplyr", "networkD3", "scGPS")
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
    library(scGPS)
    library(networkD3)
    library(dplyr)
    
    # Read user inputs from the working directory
    mixedpop1 <- readRDS("mixedpop1")
    mixedpop2 <- readRDS("mixedpop2")
    genes <- readRDS("genes")
    
    cluster_mixedpop1 <- colData(mixedpop1)[, 1]
    cluster_mixedpop2 <- colData(mixedpop2)[, 1]
    
    # Ensure genes are present in both datasets
    common_genes <- intersect(genes, rownames(assay(mixedpop1)))
    common_genes <- intersect(common_genes, rownames(assay(mixedpop2)))
    if (length(common_genes) < 10) {
      common_genes <- intersect(rownames(assay(mixedpop1)), rownames(assay(mixedpop2)))[1:100]
    }
    genes <- common_genes
    
    # Define parameters dynamically based on the data
    nboots <- 3
    unique_clusters_pop1 <- sort(unique(cluster_mixedpop1))
    row_cluster <- length(unique(cluster_mixedpop2))
    c_selectID <- unique_clusters_pop1[1]
    
    # 1. Run bootstrap prediction using LDA and Lasso/ElasticNet classifiers
    LSOLDA_dat <- bootstrap_prediction(nboots = nboots, mixedpop1 = mixedpop1, 
        mixedpop2 = mixedpop2, genes = genes, c_selectID  = c_selectID,
        listData = list(), cluster_mixedpop1 = cluster_mixedpop1, 
        cluster_mixedpop2 = cluster_mixedpop2, trainset_ratio = 0.7)
    
    # 2. Summarize prediction results, accuracy, and deviance
    sum_pred_lda <- summary_prediction_lda(LSOLDA_dat = LSOLDA_dat, nPredSubpop = row_cluster)
    
    sum_pred_lasso <- summary_prediction_lasso(LSOLDA_dat = LSOLDA_dat,
        nPredSubpop = row_cluster)
    
    sum_acc <- summary_accuracy(object = LSOLDA_dat)
    
    sum_dev <- summary_deviance(object = LSOLDA_dat)
    
    # Write summaries to files
    write.csv(sum_pred_lda, "summary_prediction_lda.csv", row.names = TRUE)
    write.csv(sum_pred_lasso, "summary_prediction_lasso.csv", row.names = TRUE)
    saveRDS(sum_acc, "summary_accuracy.rds")
    saveRDS(sum_dev, "summary_deviance.rds")
    
    # Run predictions for all clusters to enable Sankey visualization
    lasso_reformat_list <- list()
    
    # Define colors for nodes dynamically
    default_colors <- c("#7570b3", "#1b9e77", "#e7298a", "#00FFFF", "#d95f02", "#e6ab02", "#a6761d", "#666666")
    if (length(unique_clusters_pop1) > length(default_colors)) {
        default_colors <- colorRampPalette(default_colors)(length(unique_clusters_pop1))
    }
    
    for (i in seq_along(unique_clusters_pop1)) {
        c_id <- unique_clusters_pop1[i]
        
        if (c_id == c_selectID) {
            dat <- LSOLDA_dat
        } else {
            dat <- bootstrap_prediction(nboots = nboots, mixedpop1 = mixedpop1, 
                mixedpop2 = mixedpop2, genes = genes, c_selectID = c_id,
                listData = list(), cluster_mixedpop1 = cluster_mixedpop1, 
                cluster_mixedpop2 = cluster_mixedpop2, trainset_ratio = 0.7)
        }
        
        # 3. Reformat prediction results for Sankey visualization
        lasso_reformat_list[[i]] <- reformat_LASSO(c_selectID = c_id, mp_selectID = 2,
                                     LSOLDA_dat = dat,
                                     nPredSubpop = row_cluster,
                                     Nodes_group = default_colors[i])
    }
    
    combined <- do.call(rbind, lasso_reformat_list)
    combined <- combined[is.na(combined\$Value) != TRUE,]
    
    combined_D3obj <-list(Nodes=combined[,(nboots+3):(nboots+4)],
                         Links=combined[,c((nboots+2):(nboots+1),ncol(combined))])
    
    # Prepare node and link info for networkD3
    Node_source <- as.vector(sort(unique(combined_D3obj\$Links\$Source)))
    Node_target <- as.vector(sort(unique(combined_D3obj\$Links\$Target)))
    Node_all <- unique(c(Node_source, Node_target))
    
    # Assign IDs for Source (start from 0)
    Source <- combined_D3obj\$Links\$Source
    Target <- combined_D3obj\$Links\$Target
    
    for(i in 1:length(Node_all)){
       Source[Source==Node_all[i]] <- i-1
       Target[Target==Node_all[i]] <- i-1
    }
    
    combined_D3obj\$Links\$Source <- as.numeric(Source)
    combined_D3obj\$Links\$Target <- as.numeric(Target)
    combined_D3obj\$Links\$LinkColor <- combined\$NodeGroup
    
    # Prepare node info
    node_df <- data.frame(Node=Node_all)
    node_df\$id <- as.numeric(c(0, 1:(length(Node_all)-1)))
    
    # Robust color assignment
    tryCatch({
      Color <- combined %>% count(Node, color=NodeGroup) %>% select(2)
      node_df\$color <- Color\$color
    }, error = function(e) {
      node_df\$color <- rep("#7570b3", nrow(node_df))
    })
    
    # 4. Plot the relationship network using networkD3
    p1<-sankeyNetwork(Links =combined_D3obj\$Links, Nodes = node_df,
                     Value = "Value", NodeGroup ="color", LinkGroup = "LinkColor", 
                     NodeID="Node", Source="Source", Target="Target", fontSize = 22)
    
    # Save the network visualization
    saveNetwork(p1, file = "Subpopulation_Net.html")

    writeLines(c(
        '"BIOC_SCGPS_SUBPOPULATION_RELATIONSHIP_PREDICTION":',
        paste0('    scGPS: ', as.character(packageVersion('scGPS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subpopulation_relationship_prediction.csv versions.yml
    """
}

workflow BIOC_SCGPS_SUBPOPULATION_RELATIONSHIP_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mixedpop1, mixedpop2, genes ] ]

    main:
    BIOC_SCGPS_SUBPOPULATION_RELATIONSHIP_PREDICTION(ch_input)

    emit:
    tables   = BIOC_SCGPS_SUBPOPULATION_RELATIONSHIP_PREDICTION.out.tables
    plots    = BIOC_SCGPS_SUBPOPULATION_RELATIONSHIP_PREDICTION.out.plots
    objects  = BIOC_SCGPS_SUBPOPULATION_RELATIONSHIP_PREDICTION.out.objects
    versions = BIOC_SCGPS_SUBPOPULATION_RELATIONSHIP_PREDICTION.out.versions
}
