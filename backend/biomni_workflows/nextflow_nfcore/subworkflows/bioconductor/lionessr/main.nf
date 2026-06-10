#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lionessR — single_sample_network_reconstruction
// Reconstruct single-sample co-expression networks from gene expression data and identify differentially co-expressed edges between two patient groups.
// Input: exp, targets
// Container: quay.io/biocontainers/bioconductor-lionessr:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, igraph, limma, lionessR, reshape2
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Create a SummarizedExperiment object from the expression matrix and metadata
//  * 2. [Core Analysis] Subset the dataset to the top most variably expressed genes (e.g., top 500) to reduce computational complexity
//  * 3. [Input & Preparation] Construct condition-specific networks and calculate their difference to select highly variable edges
//  * 4. [Core Analysis] Run the LIONESS algorithm using lioness() to reconstruct single-sample networks
//  * 5. [Core Analysis] Subset the single-sample network edge weights to the pre-selected highly variable edges
//  * 6. [Core Analysis] Perform differential co-expression analysis on the edge weights using limma

nextflow.enable.dsl = 2

process BIOC_LIONESSR_SINGLE_SAMPLE_NETWORK_RECONSTRUCTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(lionessR)
    library(igraph)
    library(reshape2)
    library(limma)
    
    # Helper function to find and read input files with various extensions
    find_and_read <- function(base_name, is_matrix = FALSE) {
      extensions <- c(".csv", ".tsv", ".txt", ".rds")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          if (ext == ".rds") {
            data <- readRDS(file_path)
            if (is_matrix) return(as.matrix(data))
            return(data)
          } else if (ext == ".csv") {
            if (is_matrix) {
              return(as.matrix(read.csv(file_path, row.names = 1, check.names = FALSE)))
            } else {
              return(read.csv(file_path, check.names = FALSE))
            }
          } else { # .tsv or .txt
            if (is_matrix) {
              return(as.matrix(read.delim(file_path, row.names = 1, check.names = FALSE)))
            } else {
              return(read.delim(file_path, check.names = FALSE))
            }
          }
        }
      }
      stop(paste("Error: Could not find file for", base_name, "with supported extensions (.csv, .tsv, .txt, .rds)"))
    }
    
    # Read user input files
    exp <- find_and_read("exp", is_matrix = TRUE)
    targets <- find_and_read("targets", is_matrix = FALSE)
    
    # Fix 4: Replace underscores in gene names to prevent edge splitting issues later
    rownames(exp) <- gsub("_", "-", rownames(exp))
    
    # Fix 2: Align targets with exp to prevent SummarizedExperiment constructor errors
    valid_samples <- intersect(colnames(exp), targets[[1]])
    if (length(valid_samples) == 0) stop("No matching samples found between expression data and targets.")
    exp <- exp[, valid_samples, drop = FALSE]
    targets <- targets[match(valid_samples, targets[[1]]), , drop = FALSE]
    
    # 1. Create a SummarizedExperiment object from the expression matrix and metadata
    rowData <- DataFrame(row.names = rownames(exp), gene = rownames(exp))
    colData <- DataFrame(row.names = targets[[1]], sample = as.character(targets[[1]]), condition = targets[[2]])
    
    se <- SummarizedExperiment(assays = list(counts = as.matrix(exp)), 
                               colData = colData, rowData = rowData)
    
    # 2. Subset the dataset to the top most variably expressed genes (top 500)
    nsel=500
    cvar <- apply(assay(se), 1, sd)
    dat <- se[tail(order(cvar), 500), ]
    
    # 3. Construct condition-specific networks and calculate their difference
    cond_levels <- unique(as.character(dat\$condition))
    cond1 <- cond_levels[1]
    cond2 <- cond_levels[2]
    
    net1 <- cor(t(assay(dat)[, dat\$condition == cond1]))
    net2 <- cor(t(assay(dat)[, dat\$condition == cond2]))
    netdiff <- net1 - net2
    
    cormat2 <- rep(1:nsel, each=nsel)
    cormat1 <- rep(1:nsel,nsel)
    el <- cbind(cormat1, cormat2, c(netdiff))
    melted <- melt(upper.tri(netdiff))
    melted <- melted[which(melted\$value),]
    values <- netdiff[which(upper.tri(netdiff))]
    melted <- cbind(melted[,1:2], values)
    genes <- row.names(netdiff)
    melted[,1] <- genes[melted[,1]]
    melted[,2] <- genes[melted[,2]]
    row.names(melted) <- paste(melted[,1], melted[,2], sep="_")
    tosub <- melted
    
    # Fix 3: Fallback if hardcoded threshold results in too few edges
    tosel_idx <- which(abs(tosub[,3]) > 0.5)
    if (length(tosel_idx) < 50) {
      tosel_idx <- order(abs(tosub[,3]), decreasing = TRUE)[1:min(1000, nrow(tosub))]
    }
    tosel <- row.names(tosub[tosel_idx, ])
    
    # 4. Run the LIONESS algorithm to reconstruct single-sample networks
    # Fix 1: Define netFun which is missing
    netFun <- function(x) {
      if (inherits(x, "SummarizedExperiment")) {
        cor(t(assay(x)))
      } else {
        cor(t(x))
      }
    }
    cormat <- lioness(dat, netFun)
    
    # 5. Subset the single-sample network edge weights to the pre-selected highly variable edges
    corsub <- assay(cormat[which(row.names(cormat) %in% tosel), ])
    
    # 6. Perform differential co-expression analysis on the edge weights using limma
    group <- factor(make.names(se\$condition))
    design <- model.matrix(~0+group)
    contrast_formula <- paste0("group", levels(group)[1], " - group", levels(group)[2])
    cont.matrix <- makeContrasts(contrasts = contrast_formula, levels = design)  
    fit <- lmFit(corsub, design)
    fit2 <- contrasts.fit(fit, cont.matrix)
    fit2e <- eBayes(fit2)
    toptable <- topTable(fit2e, number=nrow(corsub), adjust="fdr")
    
    # Save primary tabular and object outputs
    write.csv(toptable, "lioness_differential_coexpression.csv", row.names = TRUE)
    saveRDS(cormat, "lioness_single_sample_networks.rds")
    
    # 7. Optional Network Visualization and igraph Export (wrapped in tryCatch for robustness)
    tryCatch({
      n_top <- min(50, nrow(toptable))
      if (n_top > 0) {
        toptable_edges <- t(matrix(unlist(c(strsplit(row.names(toptable), "_"))), 2))
        z <- cbind(toptable_edges[1:n_top, , drop=FALSE], toptable\$logFC[1:n_top])
        g <- graph.data.frame(z, directed=FALSE)
        E(g)\$weight <- as.numeric(z[,3])
        E(g)\$color <- "grey"
        E(g)\$color[E(g)\$weight<0] <- "blue"
        E(g)\$color[E(g)\$weight>0] <- "red"
        E(g)\$weight <- 1
    
        topgeneslist <- unique(c(toptable_edges[1:n_top,]))
        fit <- lmFit(exp, design)
        fit2 <- contrasts.fit(fit, cont.matrix)
        fit2e <- eBayes(fit2)
        topDE <- topTable(fit2e, number=nrow(exp), adjust="fdr")
        topDE <- topDE[which(row.names(topDE) %in% topgeneslist),]
        topgenesDE <- cbind(row.names(topDE), topDE\$t)
    
        # add t-statistic to network nodes
        nodeorder <- cbind(V(g)\$name, 1:length(V(g)))
        nodes <- merge(nodeorder, topgenesDE, by.x=1, by.y=1)
        nodes <- nodes[order(as.numeric(as.character(nodes[,2]))),]
        nodes[,3] <- as.numeric(as.character(nodes[,3]))
        nodes <- nodes[,-2]
        V(g)\$weight <- nodes[,2]
    
        # make a color palette
        mypalette4 <- colorRampPalette(c("blue","white","white","red"), space="Lab")(256) 
        breaks2a <- seq(min(V(g)\$weight), 0, length.out=128)
        breaks2b <- seq(0.00001, max(V(g)\$weight)+0.1, length.out=128)
        breaks4 <- c(breaks2a, breaks2b)
    
        # select bins for colors
        bincol <- rep(NA, length(V(g)))
        for(i in 1:length(V(g))){
            bincol[i] <- min(which(breaks4>V(g)\$weight[i]))
        }
        bincol <- mypalette4[bincol]
    
        # add colors to nodes
        V(g)\$color <- bincol
    
        # Save network plot to PDF
        pdf("lioness_network_plot.pdf", width=10, height=10)
        par(mar=c(0,0,0,0))
        plot(g, vertex.label.cex=0.7, vertex.size=10, vertex.label.color = "black", 
             vertex.label.font=3, edge.width=10*(abs(as.numeric(z[,3]))-0.7), vertex.color=V(g)\$color)
        dev.off()
        
        # Save igraph object
        saveRDS(g, "lioness_network.rds")
      }
    }, error = function(e) {
      warning("Network visualization or igraph generation failed: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_LIONESSR_SINGLE_SAMPLE_NETWORK_RECONSTRUCTION":',
        paste0('    lionessR: ', as.character(packageVersion('lionessR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_network_reconstruction.csv versions.yml
    """
}

workflow BIOC_LIONESSR_SINGLE_SAMPLE_NETWORK_RECONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exp, targets ] ]

    main:
    BIOC_LIONESSR_SINGLE_SAMPLE_NETWORK_RECONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_LIONESSR_SINGLE_SAMPLE_NETWORK_RECONSTRUCTION.out.tables
    plots    = BIOC_LIONESSR_SINGLE_SAMPLE_NETWORK_RECONSTRUCTION.out.plots
    objects  = BIOC_LIONESSR_SINGLE_SAMPLE_NETWORK_RECONSTRUCTION.out.objects
    versions = BIOC_LIONESSR_SINGLE_SAMPLE_NETWORK_RECONSTRUCTION.out.versions
}
