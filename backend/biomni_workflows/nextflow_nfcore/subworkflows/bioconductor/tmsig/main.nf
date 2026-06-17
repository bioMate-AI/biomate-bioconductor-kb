#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TMSig — gene_set_enrichment_and_visualization
// Read, filter, cluster, and analyze gene sets for competitive enrichment using pre-ranked statistics, followed by bubble heatmap visualization.
// Input: c5.go.v2023.2.Hs.symbols.gmt.gz, y
// Container: quay.io/biocontainers/bioconductor-tmsig:1.4.0--r45hdfd78af_0
// R packages: data.table, limma, TMSig
// Bioconductor: 3.20 | R: 4.4
// Requires: TMSig, data.table, limma
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read gene sets from a GMT file
//  * 2. [Core Analysis] Filter gene sets by size and background genes
//  * 3. [Core Analysis] Compute set similarity and cluster redundant sets
//  * 4. [Core Analysis] Decompose or invert sets (optional)
//  * 5. [Core Analysis] Perform competitive gene set testing using CAMERA-PR
//  * 6. [Visualization & Output] Visualize differential expression and gene set enrichment results using bubble heatmaps

nextflow.enable.dsl = 2

process BIOC_TMSIG_GENE_SET_ENRICHMENT_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("data.table", "limma", "TMSig")
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
        library(TMSig)
        library(limma)
        library(data.table)
        library(grid)
        
        # ==========================================
        # 1. Read Input Files
        # ==========================================
        
        # Path to GMT file
        pathToGMT <- "c5.go.v2023.2.Hs.symbols.gmt.gz"
        if (!file.exists(pathToGMT)) {
            stop("Error: Input file 'c5.go.v2023.2.Hs.symbols.gmt.gz' not found in the working directory.")
        }
        
        geneSets <- readGMT(path = pathToGMT)
        
        # Robustly read y (matrix of gene expression data or pre-calculated gene-level statistics)
        y_file <- NULL
        for (f in c("y.rds", "y", "y.csv", "y.tsv", "y.txt")) {
            if (file.exists(f)) {
                y_file <- f
                break
            }
        }
        
        if (is.null(y_file)) {
            stop("Error: Input file 'y' (matrix of gene expression data) not found in the working directory.")
        }
        
        if (grepl("\\\\.rds\$", y_file, ignore.case = TRUE) || y_file == "y") {
            y <- tryCatch({
                readRDS(y_file)
            }, error = function(e) {
                as.matrix(read.table(y_file, header = TRUE, row.names = 1, check.names = FALSE))
            })
        } else if (grepl("\\\\.csv\$", y_file, ignore.case = TRUE)) {
            y <- as.matrix(read.csv(y_file, row.names = 1, check.names = FALSE))
        } else {
            y <- as.matrix(read.table(y_file, header = TRUE, row.names = 1, check.names = FALSE))
        }
        
        # Ensure y is a matrix
        y <- as.matrix(y)
        
        # ==========================================
        # 2. Filter Gene Sets
        # ==========================================
        
        # Filter by size - no background
        filt <- filterSets(x = geneSets, 
                           min_size = 10L, 
                           max_size = 500L)
        
        # Use the genes quantified in the experiment (rownames of y) as background
        background <- rownames(y)
        
        # Restrict gene sets to background of genes
        geneSetsFilt <- filterSets(
            x = geneSets, 
            background = background, 
            min_size = 10L
        )
        
        # Calculate proportion of overlap with background
        setSizes <- lengths(geneSetsFilt)
        setSizesOld <- lengths(geneSets)[names(geneSetsFilt)]
        overlapProp <- setSizes / setSizesOld
        
        # Keep gene sets with an overlap of at least 70%
        geneSetsFilt <- geneSetsFilt[overlapProp >= 0.7]
        
        # ==========================================
        # 3. Incidence Matrix & Set Similarity
        # ==========================================
        
        imat <- sparseIncidence(x = geneSetsFilt)
        
        jaccard <- similarity(x = geneSetsFilt)
        overlap <- similarity(x = geneSetsFilt, type = "overlap")
        otsuka <- similarity(x = geneSetsFilt, type = "otsuka")
        
        # ==========================================
        # 4. Cluster Similar Sets
        # ==========================================
        
        clusterDF <- clusterSets(x = geneSetsFilt, 
                                 type = "jaccard", 
                                 cutoff = 0.85, 
                                 method = "complete",
                                 h = 0.9)
        
        clusterDF\$overlap_prop <- overlapProp[clusterDF\$set]
        clusterDF\$n_char <- nchar(clusterDF\$set)
        
        # Reorder rows so that the first set in each cluster is the one to keep
        o <- with(clusterDF, 
                  order(cluster, set_size, overlap_prop, n_char, set,
                        decreasing = c(FALSE, TRUE, TRUE, FALSE, TRUE),
                        method = "radix"))
        clusterDF <- clusterDF[o, ]
        
        # Select sets to keep for analysis
        keepSets <- with(clusterDF, set[!duplicated(cluster)])
        geneSetsFilt <- geneSetsFilt[keepSets]
        
        # ==========================================
        # 5. Decompose & Invert Sets
        # ==========================================
        
        geneSetsFilt2 <- filterSets(geneSetsFilt, max_size = 50L)
        decompSets <- decomposeSets(x = geneSetsFilt2, overlap = 10L)
        
        invertedSets <- invertSets(x = geneSetsFilt)
        
        # ==========================================
        # 6. Differential Gene Expression Analysis
        # ==========================================
        
        # Extract groups from column names of y (e.g., "ctrl.1" -> "ctrl")
        group <- gsub("\\\\.\\\\d+\$", "", colnames(y))
        design <- model.matrix(~ 0 + group)
        colnames(design) <- gsub("^group", "", colnames(design))
        
        # Dynamically build contrasts comparing treatment groups to control
        all_groups <- unique(group)
        ctrl_grp <- all_groups[grep("ctrl|control|mock|wild|wt", all_groups, ignore.case = TRUE)][1]
        if (is.na(ctrl_grp)) {
            ctrl_grp <- all_groups[1]
        }
        treat_grps <- setdiff(all_groups, ctrl_grp)
        
        if (length(treat_grps) == 0) {
            stop("Error: No treatment groups found to compare against control.")
        }
        
        contrast_formulas <- paste0(treat_grps, " - ", ctrl_grp)
        contrasts <- limma::makeContrasts(
            contrasts = contrast_formulas,
            levels = colnames(design)
        )
        colnames(contrasts) <- treat_grps
        
        # Run LIMMA pipeline
        fit <- lmFit(y, design)
        fit.contr <- contrasts.fit(fit, contrasts = contrasts)
        fit.smooth <- eBayes(fit.contr)
        
        # Matrix of z-score equivalents of moderated t-statistics
        modz <- with(fit.smooth, zscoreT(x = t, df = df.total))
        
        # Reformat differential analysis results for enrichmap
        resDA <- lapply(colnames(contrasts), function(contrast_i) {
            res_i <- topTable(fit.smooth, 
                              coef = contrast_i, 
                              number = Inf, 
                              sort.by = "none")
            res_i\$contrast <- contrast_i
            res_i\$gene <- rownames(res_i)
            res_i\$df.total <- fit.smooth\$df.total
            return(res_i)
        })
        resDA <- data.table::rbindlist(resDA)
        
        # Add z-statistic column
        resDA\$z <- with(resDA, zscoreT(x = t, df = df.total))
        
        # Reorder rows
        resDA <- resDA[with(resDA, order(contrast, P.Value, z)), ]
        
        # ==========================================
        # 7. CAMERA-PR Gene Set Testing
        # ==========================================
        
        res <- cameraPR(statistic = modz, 
                        index = geneSetsFilt)
        
        # ==========================================
        # 8. Visualization & Output Generation
        # ==========================================
        
        # Save tabular outputs
        write.csv(as.data.frame(clusterDF), "cluster_results.csv", row.names = FALSE)
        write.csv(as.data.frame(resDA), "differential_expression_results.csv", row.names = FALSE)
        write.csv(as.data.frame(res), "camera_pr_results.csv", row.names = FALSE)
        saveRDS(decompSets, "decomposed_sets.rds")
        saveRDS(invertedSets, "inverted_sets.rds")
        saveRDS(geneSetsFilt, "filtered_gene_sets.rds")
        
        # Generate and save bubble heatmaps
        pdf("differential_expression_bubble_heatmap.pdf", width = 8, height = 8)
        print(enrichmap(x = resDA, 
                  scale_by = "max",
                  n_top = 15L,
                  plot_sig_only = TRUE,
                  set_column = "gene", 
                  statistic_column = "z", 
                  contrast_column = "contrast", 
                  padj_column = "adj.P.Val", 
                  padj_legend_title = "BH Adjusted\nP-Value", 
                  padj_cutoff = 0.05,
                  cell_size = grid::unit(20, "pt"),
                  heatmap_args = list(
                      name = "Z-Score",
                      column_names_rot = 60,
                      column_names_side = "top"
                  )))
        dev.off()
        
        pdf("camera_pr_bubble_heatmap.pdf", width = 10, height = 10)
        print(enrichmap(x = res, 
                  scale_by = "row",
                  n_top = 20L,
                  set_column = "GeneSet", 
                  statistic_column = "ZScore", 
                  contrast_column = "Contrast",
                  padj_column = "FDR",
                  padj_legend_title = "BH Adjusted\nP-Value",
                  padj_cutoff = 0.05,
                  cell_size = grid::unit(13, "pt"),
                  heatmap_args = list(
                      name = "Z-Score", 
                      column_names_rot = 60,
                      column_names_side = "top"
                  )))
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_TMSIG_GENE_SET_ENRICHMENT_AND_VISUALIZATION":',
        paste0('    TMSig: ', as.character(packageVersion('TMSig')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_set_enrichment_and_visualization.csv versions.yml
    """
}

workflow BIOC_TMSIG_GENE_SET_ENRICHMENT_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ c5.go.v2023.2.Hs.symbols.gmt.gz, y ] ]

    main:
    BIOC_TMSIG_GENE_SET_ENRICHMENT_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TMSIG_GENE_SET_ENRICHMENT_AND_VISUALIZATION.out.tables
    plots    = BIOC_TMSIG_GENE_SET_ENRICHMENT_AND_VISUALIZATION.out.plots
    objects  = BIOC_TMSIG_GENE_SET_ENRICHMENT_AND_VISUALIZATION.out.objects
    versions = BIOC_TMSIG_GENE_SET_ENRICHMENT_AND_VISUALIZATION.out.versions
}
