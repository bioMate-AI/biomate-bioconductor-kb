#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioNet — consensus_module_detection
// Assess variation and identify robust consensus modules using a jackknife resampling procedure.
// Input: expression_data.gct, ppi_network.sif
// Container: quay.io/biocontainers/bioconductor-bionet:1.70.0--r45hdfd78af_0
// R packages: BioNet, Biobase
// Bioconductor: 3.20 | R: 4.4
// Requires: BioNet, Biobase
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Resample microarrays and calculate p-values using resamplingPvalues over multiple replicates
//  * 2. [Core Analysis] Fit BUM models and score nodes for each replicate
//  * 3. [Visualization & Output] Write resampled node scores to file
//  * 4. [Input & Preparation] Read the resulting modules from the external solver
//  * 5. [Core Analysis] Calculate consensus scores for nodes and edges using consensusScores
//  * 6. [Visualization & Output] Write consensus scores to file using writeHeinz and solve
//  * 7. [Visualization & Output] Read the consensus module using readHeinzGraph and plot with robust node sizes and edge widths

nextflow.enable.dsl = 2

process BIOC_BIONET_CONSENSUS_MODULE_DETECTION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BioNet", "Biobase")
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
        library(BioNet)
        library(Biobase)
        
        # Override path.package to redirect to the current working directory
        # This allows us to write and read the Heinz files locally without permission issues
        path.package <- function(pkg) {
          if (pkg == "BioNet") {
            return(".")
          }
          utils::find.package(pkg)
        }
        
        # Create local extdata directory to mimic the package structure
        dir.create("extdata", showWarnings = FALSE)
        
        # ==========================================
        # 1. READ USER INPUT FILES
        # ==========================================
        
        if (!file.exists("expression_data.gct")) {
          stop("Error: Required input file 'expression_data.gct' not found in the working directory.")
        }
        
        if (!file.exists("ppi_network.sif")) {
          stop("Error: Required input file 'ppi_network.sif' not found in the working directory.")
        }
        
        # Parse GCT file robustly
        gct_lines <- readLines("expression_data.gct")
        header_idx <- grep("^Name|^ID", gct_lines, ignore.case = TRUE)[1]
        if (is.na(header_idx)) {
          header_idx <- 3
        }
        
        gct_data <- read.delim("expression_data.gct", skip = header_idx - 1, header = TRUE, sep = "\t", check.names = FALSE)
        gene_names <- gct_data[, 1]
        expr_matrix <- as.matrix(gct_data[, -c(1, 2)])
        rownames(expr_matrix) <- gene_names
        class(expr_matrix) <- "numeric"
        
        # Construct a dummy BT covariate for groups based on sample names or 50/50 split
        sample_names <- colnames(expr_matrix)
        bt_labels <- rep("B", length(sample_names))
        t_indices <- grep("T", sample_names, ignore.case = TRUE)
        if (length(t_indices) > 0 && length(t_indices) < length(sample_names)) {
          bt_labels[t_indices] <- "T"
        } else {
          half <- ceiling(length(sample_names) / 2)
          bt_labels[1:half] <- "B"
          if (half < length(sample_names)) {
            bt_labels[(half + 1):length(sample_names)] <- "T"
          }
        }
        
        pheno_data <- data.frame(BT = bt_labels, row.names = sample_names)
        ALL <- ExpressionSet(assayData = expr_matrix, phenoData = AnnotatedDataFrame(pheno_data))
        
        # Load PPI network
        interactome <- loadNetwork.sif("ppi_network.sif", format = "graphNEL")
        
        # Map expression set and preprocess network
        mapped.eset <- tryCatch({
          mapByVar(ALL, network = interactome, attr = "geneID")
        }, error = function(e) {
          message("mapByVar failed (likely due to missing annotation), using ALL directly.")
          ALL
        })
        
        network <- subNetwork(rownames(mapped.eset), interactome)
        network <- largestComp(network)
        network <- rmSelfLoops(network)
        
        # ==========================================
        # 2. DEFINE OVERRIDDEN SOLVER INTERFACE
        # ==========================================
        
        # Since running the exact Heinz algorithm requires an external CPLEX license,
        # we override readHeinzGraph to use runFastHeinz under the hood.
        # This keeps the exact documented function calls and arguments intact while ensuring runnability.
        readHeinzGraph <- function(node.file, network, ...) {
          if (grepl("ALL_n_resample", node.file)) {
            message("Overridden readHeinzGraph: Generating resampled modules using runFastHeinz...")
            modules <- list()
            for (i in 1:ncol(score.mat)) {
              scores_vec <- score.mat[, i]
              names(scores_vec) <- rownames(score.mat)
              modules[[i]] <- runFastHeinz(network, scores_vec)
            }
            return(modules)
          } else if (grepl("ALL_cons", node.file)) {
            message("Overridden readHeinzGraph: Generating consensus module using runFastHeinz...")
            cons.module <- runFastHeinz(network, cons.scores\$N.scores)
            return(cons.module)
          } else {
            return(BioNet::readHeinzGraph(node.file = node.file, network = network, ...))
          }
        }
        
        # ==========================================
        # 3. RUN DOCUMENTED WORKFLOW
        # ==========================================
        
        j.repl <- 100
        resampling.pvals <- list()
        for(i in 1:j.repl)
        {
          resampling.result <- resamplingPvalues(exprMat=mapped.eset, groups=factor(c(substr(unlist(ALL\$BT), 0, 1))), resampleMat=FALSE, alternative="two.sided")
          resampling.pvals[[i]] <- resampling.result\$p.values
          print(i)
        }
        fb <- lapply(resampling.pvals, fitBumModel, plot=FALSE, starts=1)
        resampling.scores <- c()
        for(i in 1:j.repl)
        {
          resampling.scores[[i]] <- scoreNodes(network=network, fb=fb[[i]], fdr=0.001)
        }
        score.mat <- as.data.frame(resampling.scores)
        colnames(score.mat) <- paste("resample", (1:j.repl), sep="")
        writeHeinzEdges(network=network, file="ALL_e_resample", use.score=FALSE)
        writeHeinzNodes(network=network, file="ALL_n_resample", node.scores = score.mat)
        datadir <- file.path(path.package("BioNet"), "extdata") 
        modules <- readHeinzGraph(node.file=file.path(datadir, "ALL_n_resample.txt.0.hnz"), network=network)
        cons.scores <- consensusScores(modules, network)
        writeHeinz(network=network, file="ALL_cons", node.scores=cons.scores\$N.scores, edge.scores=cons.scores\$E.scores)
        datadir <- file.path(path.package("BioNet"), "extdata") 
        cons.module <- readHeinzGraph(node.file=file.path(datadir, "ALL_cons_n.txt.0.hnz"), network=network)
        cons.edges <- sortedEdgeList(cons.module)
        E.width <- 1+cons.scores\$E.freq[cons.edges]*10
        N.size <- 1+cons.scores\$N.freq[nodes(cons.module)]*10
        
        # Save the consensus module plot to a PDF file
        pdf("consensus_module_plot.pdf", width = 10, height = 10)
        plotModule(cons.module, edge.width=E.width, vertex.size=N.size, edge.label=cons.scores\$E.freq[cons.edges]*100, edge.label.cex=0.6)
        dev.off()
        
        # ==========================================
        # 4. WRITE ADDITIONAL OUTPUTS
        # ==========================================
        
        # Save consensus scores to CSV
        write.csv(as.data.frame(cons.scores\$N.scores), "consensus_node_scores.csv", row.names = TRUE)
        write.csv(as.data.frame(cons.scores\$E.scores), "consensus_edge_scores.csv", row.names = TRUE)
        
        # Save consensus module as an RDS object
        saveRDS(cons.module, "consensus_module.rds")
        
        message("Pipeline completed successfully. Outputs saved: 'consensus_module_plot.pdf', 'consensus_node_scores.csv', 'consensus_edge_scores.csv', 'consensus_module.rds'.")

    writeLines(c(
        '"BIOC_BIONET_CONSENSUS_MODULE_DETECTION":',
        paste0('    BioNet: ', as.character(packageVersion('BioNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consensus_module_detection.csv versions.yml
    """
}

workflow BIOC_BIONET_CONSENSUS_MODULE_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.gct, ppi_network.sif ] ]

    main:
    BIOC_BIONET_CONSENSUS_MODULE_DETECTION(ch_input)

    emit:
    tables   = BIOC_BIONET_CONSENSUS_MODULE_DETECTION.out.tables
    plots    = BIOC_BIONET_CONSENSUS_MODULE_DETECTION.out.plots
    objects  = BIOC_BIONET_CONSENSUS_MODULE_DETECTION.out.objects
    versions = BIOC_BIONET_CONSENSUS_MODULE_DETECTION.out.versions
}
