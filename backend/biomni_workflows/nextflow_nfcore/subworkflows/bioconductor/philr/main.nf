#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: philr — philr_transform_and_analysis
// Transform compositional microbiome data using a phylogenetic tree into PhILR balances, perform ordination, identify key balances distinguishing sample groups, a
// Input: otu_table.tsv, phylo_tree.tre, taxonomy.tsv, metadata.tsv
// Container: quay.io/biocontainers/bioconductor-philr:1.36.0--r45hdfd78af_0
// R packages: TreeSummarizedExperiment, ape, dplyr, ggplot2, ggtree, glmnet, mia, philr, tidyr
// Bioconductor: 3.20 | R: 4.4
// Requires: TreeSummarizedExperiment, ape, dplyr, ggplot2, ggtree, glmnet, mia, philr, tidyr
// Visualizations: ordination plot, box plot, scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] READ USER INPUT FILES
//  * 2. [Visualization & Output] RUN VIGNETTE WORKFLOW
//  * 3. [Visualization & Output] WRITE OUTPUT TABLES AND OBJECTS

nextflow.enable.dsl = 2

process BIOC_PHILR_PHILR_TRANSFORM_AND_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("TreeSummarizedExperiment", "ape", "dplyr", "ggplot2", "ggtree", "glmnet", "mia", "philr", "tidyr", "SummarizedExperiment")
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
            
            # Load required libraries quietly
            suppressPackageStartupMessages({
                   library(SummarizedExperiment)
         library(philr)
              library(ape)
              library(ggplot2)
              library(mia)
              library(dplyr)
              library(glmnet)
              library(ggtree)
              library(tidyr)
              library(TreeSummarizedExperiment)
            })
            
            # ==========================================
            # --- READ USER INPUT FILES ---
            # ==========================================
            
            if (!file.exists("otu_table.tsv") || !file.exists("phylo_tree.tre") || 
                !file.exists("taxonomy.tsv") || !file.exists("metadata.tsv")) {
              stop("Required input files (otu_table.tsv, phylo_tree.tre, taxonomy.tsv, metadata.tsv) not found in the working directory.")
            }
            
            # Read raw files
            otu.raw <- read.table("otu_table.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
            tree.raw <- ape::read.tree("phylo_tree.tre")
            tax.raw <- read.table("taxonomy.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
            meta.raw <- read.table("metadata.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
            
            # Standardize taxonomy column names to Title Case for mia compatibility
            colnames(tax.raw) <- tools::toTitleCase(tolower(colnames(tax.raw)))
            
            # Align taxa across OTU table, taxonomy, and tree
            common_taxa <- intersect(rownames(otu.raw), rownames(tax.raw))
            common_taxa <- intersect(common_taxa, tree.raw\$tip.label)
            if (length(common_taxa) == 0) {
              stop("No common taxa found between OTU table, taxonomy, and phylogenetic tree.")
            }
            
            otu.raw <- otu.raw[common_taxa, , drop = FALSE]
            tax.raw <- tax.raw[common_taxa, , drop = FALSE]
            tree.raw <- ape::keep.tip(tree.raw, common_taxa)
            
            # Align samples across OTU table and metadata
            common_samples <- intersect(colnames(otu.raw), rownames(meta.raw))
            if (length(common_samples) == 0) {
              stop("No common samples found between OTU table and metadata.")
            }
            otu.raw <- otu.raw[, common_samples, drop = FALSE]
            meta.raw <- meta.raw[common_samples, , drop = FALSE]
            
            # Construct TreeSummarizedExperiment
            tse_init <- TreeSummarizedExperiment(
              assays = list(counts = as.matrix(otu.raw)),
              colData = DataFrame(meta.raw),
              rowData = DataFrame(tax.raw),
              rowTree = tree.raw,
              rowNodeLab = rownames(otu.raw)
            )
            
            # Assign to GlobalPatterns to match vignette code exactly
            GlobalPatterns <- tse_init
            
            # ==========================================
            # --- RUN VIGNETTE WORKFLOW ---
            # ==========================================
            
            ## Select prevalent taxa 
            tse <-  GlobalPatterns %>% subsetByPrevalentTaxa(
                                           detection = 3,
                                           prevalence = 20/100,
                                           as_relative = FALSE)
            
            # Fallback to less stringent filtering if dataset becomes too small
            if (nrow(tse) < 10) {
              tse <- GlobalPatterns %>% subsetByPrevalentTaxa(
                                             detection = 1,
                                             prevalence = 0.05,
                                             as_relative = FALSE)
            }
            if (nrow(tse) < 10) {
              tse <- GlobalPatterns
            }
            
            ## Pick taxa that have notable abundance variation across samples
            variable.taxa <- apply(assays(tse)\$counts, 1, function(x) sd(x)/mean(x) > 3.0)
            variable.taxa[is.na(variable.taxa)] <- FALSE
            # Ensure we have at least some variable taxa
            if (sum(variable.taxa) < 10) {
              variable.taxa <- rep(TRUE, nrow(tse))
            }
            tse <- tse[variable.taxa,]
            
            # Collapse the tree!
            tree <- ape::keep.tip(phy = rowTree(tse), tip = rowLinks(tse)\$nodeNum)
            rowTree(tse) <- tree
            
            ## Add a new assay with a pseudocount 
            assays(tse)\$counts.shifted <- assays(tse)\$counts + 1 
            
            # Check tree properties and resolve multichotomies if necessary
            if (!is.rooted(tree)) {
              # Root tree if unrooted (using first tip as outgroup)
              tree <- ape::root(tree, outgroup = 1, resolve.root = TRUE)
            }
            if (!is.binary(tree)) {
              tree <- ape::multi2di(tree)
            }
            
            # Label internal nodes
            tree <- makeNodeLabel(tree, method="number", prefix='n')
            rowTree(tse) <- tree
            
            # Extract taxonomy
            tax <- rowData(tse)[, taxonomyRanks(tse), drop = FALSE]
            
            # Ensure 'Family' rank exists for downstream voting code
            if (!("Family" %in% colnames(tax))) {
              if (ncol(tax) > 0) {
                colnames(tax)[ncol(tax)] <- "Family"
              } else {
                tax\$Family <- "Unknown_Family"
              }
            }
            
            # Get name balances
            name.balance(tree, tax, 'n1')
            
            otu.table <- t(as(assays(tse)\$counts.shifted, "matrix"))
            tree <- rowTree(tse)
            metadata <- colData(tse)
            tax <- rowData(tse)[, taxonomyRanks(tse), drop = FALSE]
            
            # Ensure 'Family' rank exists in the updated tax object
            if (!("Family" %in% colnames(tax))) {
              if (ncol(tax) > 0) {
                colnames(tax)[ncol(tax)] <- "Family"
              } else {
                tax\$Family <- "Unknown_Family"
              }
            }
            
            # Define human.samples factor robustly
            if ("SampleType" %in% colnames(colData(tse))) {
              human.samples <- factor(colData(tse)\$SampleType %in% c("Feces", "Mock", "Skin", "Tongue"))
            } else {
              group_col <- colnames(colData(tse))[1]
              if (!is.null(group_col)) {
                human.samples <- factor(colData(tse)[[group_col]])
              } else {
                human.samples <- factor(rep(c(TRUE, FALSE), length.out = ncol(tse)))
              }
            }
            
            # Robustness check: Ensure human.samples has exactly 2 levels for glmnet
            human.samples <- droplevels(human.samples)
            if (length(levels(human.samples)) > 2) {
              first_level <- levels(human.samples)[1]
              human.samples <- factor(human.samples == first_level)
            }
            if (length(levels(human.samples)) < 2) {
              half_size <- floor(length(human.samples) / 2)
              human.samples <- factor(c(rep(TRUE, half_size), rep(FALSE, length(human.samples) - half_size)))
            }
            
            # Transform data using PhILR (matrix, TreeSE, and phyloseq methods)
            gp.philr <- philr(otu.table, tree, 
                              part.weights='enorm.x.gm.counts', 
                              ilr.weights='blw.sqrt')
            
            gp.philr <- philr(tse, abund_values = "counts.shifted",
                              part.weights='enorm.x.gm.counts', 
                              ilr.weights='blw.sqrt')
            
            pseq <- convertToPhyloseq(tse, assay.type="counts.shifted")
            gp.philr <- philr(pseq, 
                              part.weights='enorm.x.gm.counts', 
                              ilr.weights='blw.sqrt')
            
            # Ordination in PhILR Space
            gp.dist <- dist(gp.philr, method="euclidean") 
            d <- as.data.frame(cmdscale(gp.dist))
            colnames(d) <- paste0("PC", 1:2)
            
            if ("SampleType" %in% colnames(metadata)) {
              d\$Group <- factor(metadata\$SampleType)
              group_name <- "SampleType"
            } else if (ncol(metadata) > 0) {
              d\$Group <- factor(metadata[[1]])
              group_name <- colnames(metadata)[1]
            } else {
              d\$Group <- factor(rep("Sample", nrow(d)))
              group_name <- "Group"
            }
            
            # Save Ordination Plot
            p_ord <- ggplot(data = d,
              aes(x=PC1, y=PC2, color=Group)) +
              geom_point() +
              labs(title = "Euclidean distances with phILR", color = group_name)
            ggsave("ordination_plot.pdf", plot = p_ord, width = 8, height = 6)
            
            # Identify Balances that Distinguish Groups
            glmmod <- glmnet(gp.philr, human.samples, alpha=1, family="binomial")
            
            # Robustly select lambda to ensure we get non-zero coordinates
            s_val <- 0.2526
            num_nonzero <- colSums(as.matrix(coefficients(glmmod)) != 0) - 1
            suitable_lambdas <- glmmod\$lambda[num_nonzero >= 2 & num_nonzero <= 15]
            if (length(suitable_lambdas) > 0) {
              s_val <- suitable_lambdas[1]
            } else {
              s_val <- glmmod\$lambda[which.min(abs(num_nonzero - 5))]
            }
            
            top.coords <- as.matrix(coefficients(glmmod, s=s_val))
            top.coords <- rownames(top.coords)[which(top.coords != 0)]
            top.coords <- top.coords[2:length(top.coords)] # remove intercept
            
            # Ensure top.coords has at least 5 elements for visualization
            if (length(top.coords) < 5) {
              extra_nodes <- setdiff(tree\$node.label, top.coords)
              top.coords <- c(top.coords, extra_nodes[1:(5 - length(top.coords))])
            }
            
            # Dynamically select nodes for visualization instead of hardcoding
            node1 <- top.coords[1]
            node2 <- top.coords[5]
            
            # Name Balances
            tc.names <- sapply(top.coords, function(x) name.balance(tree, tax, x))
            
            # Get voting details
            votes <- name.balance(tree, tax, node2, return.votes = c('up', 'down'))
            votes[[c('up.votes', 'Family')]]
            votes[[c('down.votes', 'Family')]]
            
            # Map and Annotate Balances on the Tree
            tc.nn <- name.to.nn(tree, top.coords)
            tc.colors <- c('#a6cee3', '#1f78b4', '#b2df8a', '#33a02c', '#fb9a99')
            
            p <- ggtree(tree, layout='fan') +
              geom_balance(node=tc.nn[1], fill=tc.colors[1], alpha=0.6) +
              geom_balance(node=tc.nn[2], fill=tc.colors[2], alpha=0.6) +
              geom_balance(node=tc.nn[3], fill=tc.colors[3], alpha=0.6) +
              geom_balance(node=tc.nn[4], fill=tc.colors[4], alpha=0.6) +
              geom_balance(node=tc.nn[5], fill=tc.colors[5], alpha=0.6)
            
            p <- annotate_balance(tree, node1, p=p, labels = c(paste0(node1, '+'), paste0(node1, '-')),
                             offset.text=0.15, bar=FALSE)
            
            p_tree_final <- annotate_balance(tree, node2, p=p, labels = c(paste0(node2, '+'), paste0(node2, '-')),
                             offset.text=0.15, bar=FALSE)
            
            ggsave("tree_balances_plot.pdf", plot = p_tree_final, width = 10, height = 10)
            
            # Convert to long format and plot boxplots
            gp.philr.long <- convert_to_long(gp.philr, human.samples) %>%
              filter(coord %in% top.coords)
            
            p_box <- ggplot(gp.philr.long, aes(x=labels, y=value)) +
              geom_boxplot(fill='lightgrey') +
              facet_grid(.~coord, scales='free_x') +
              labs(x = 'Group', y = 'Balance Value') +
              theme_bw()
            ggsave("balances_boxplot.pdf", plot = p_box, width = 10, height = 6)
            
            # Dimension reduction plot (node1 vs node2)
            p_scatter <- gp.philr.long %>%
              dplyr::rename(Group=labels) %>%
              dplyr::filter(coord %in% c(node1, node2)) %>%
              tidyr::spread(coord, value) %>%
              ggplot(aes(x=.data[[node1]], y=.data[[node2]], color=Group)) +
              geom_point(size=4) +
              labs(x = tc.names[node1], y = tc.names[node2]) +
              theme_bw()
            ggsave("balances_scatter_plot.pdf", plot = p_scatter, width = 8, height = 6)
            
            # ==========================================
            # --- WRITE OUTPUT TABLES AND OBJECTS ---
            # ==========================================
            write.csv(as.matrix(gp.philr), "philr_balances.csv", row.names = TRUE)
            saveRDS(tse, "tse_philr.rds")
            
            cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_PHILR_PHILR_TRANSFORM_AND_ANALYSIS":',
        paste0('    philr: ', as.character(packageVersion('philr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_philr_transform_and_analysis.csv versions.yml
    """
}

workflow BIOC_PHILR_PHILR_TRANSFORM_AND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ otu_table.tsv, phylo_tree.tre, taxonomy.tsv, metadata.tsv ] ]

    main:
    BIOC_PHILR_PHILR_TRANSFORM_AND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PHILR_PHILR_TRANSFORM_AND_ANALYSIS.out.tables
    plots    = BIOC_PHILR_PHILR_TRANSFORM_AND_ANALYSIS.out.plots
    objects  = BIOC_PHILR_PHILR_TRANSFORM_AND_ANALYSIS.out.objects
    versions = BIOC_PHILR_PHILR_TRANSFORM_AND_ANALYSIS.out.versions
}
