#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EDASeq — gene_level_normalization_and_de
// Perform gene-level exploratory data analysis, within-lane and between-lane normalization, and prepare data for differential expression analysis.
// Input: geneLevelData, yeastGC, yeastLength
// Container: quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0
// R packages: DESeq2, EDASeq, edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, EDASeq, edgeR
// Visualizations: box plot
// QC: dispersion/size-factor estimation, low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input Files
//  * 2. [Visualization & Output] Filter and Align Gene Metadata
//  * 3. [Visualization & Output] Create SeqExpressionSet Object
//  * 4. [Visualization & Output] Exploratory Plotting
//  * 5. [Visualization & Output] Normalization (Within-lane and Between-lane)
//  * 6. [Visualization & Output] Generate Normalization Offsets
//  * 7. [Visualization & Output] Differential Expression Analysis: edgeR
//  * 8. [Visualization & Output] Differential Expression Analysis: DESeq2
//  * 9. [Visualization & Output] Unrounded Normalization & Verification
//  * 10. [Visualization & Output] Optional: Retrieve Gene Length and GC Content

nextflow.enable.dsl = 2

process BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE {
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
    .bm_deps <- c("DESeq2", "EDASeq", "edgeR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
            library(EDASeq)
            library(edgeR)
            library(DESeq2)
            
            # Define colors for plotting (as defined in the EDASeq vignette)
            colors <- c(rep(rgb(1,0,0,alpha=0.7),2),
                        rep(rgb(0,0,1,alpha=0.7),2),
                        rep(rgb(0,1,0,alpha=0.7),2),
                        rep(rgb(0,1,1,alpha=0.7),2))
            
            # ==========================================
            # --- Load User Input Files ---
            # ==========================================
            
            load_input <- function(var_name) {
              rds_path <- paste0(var_name, ".rds")
              csv_path <- paste0(var_name, ".csv")
              tsv_path <- paste0(var_name, ".tsv")
              txt_path <- paste0(var_name, ".txt")
              
              if (file.exists(rds_path)) {
                return(readRDS(rds_path))
              } else if (file.exists(csv_path)) {
                df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
                if (ncol(df) == 1 && var_name != "geneLevelData") {
                  vec <- df[[1]]
                  names(vec) <- rownames(df)
                  return(vec)
                }
                return(as.matrix(df))
              } else if (file.exists(tsv_path)) {
                df <- read.delim(tsv_path, row.names = 1, check.names = FALSE)
                if (ncol(df) == 1 && var_name != "geneLevelData") {
                  vec <- df[[1]]
                  names(vec) <- rownames(df)
                  return(vec)
                }
                return(as.matrix(df))
              } else if (file.exists(txt_path)) {
                df <- read.table(txt_path, header = TRUE, row.names = 1, check.names = FALSE)
                if (ncol(df) == 1 && var_name != "geneLevelData") {
                  vec <- df[[1]]
                  names(vec) <- rownames(df)
                  return(vec)
                }
                return(as.matrix(df))
              } else if (file.exists(var_name)) {
                res <- tryCatch(readRDS(var_name), error = function(e) NULL)
                if (!is.null(res)) return(res)
                df <- tryCatch(read.table(var_name, header = TRUE, row.names = 1, check.names = FALSE), error = function(e) NULL)
                if (!is.null(df)) {
                  if (ncol(df) == 1 && var_name != "geneLevelData") {
                    vec <- df[[1]]
                    names(vec) <- rownames(df)
                    return(vec)
                  }
                  return(as.matrix(df))
                }
              }
              stop(paste("Could not find or read input file for:", var_name))
            }
            
            message("Loading input files...")
            geneLevelData <- load_input("geneLevelData")
            yeastGC <- load_input("yeastGC")
            yeastLength <- load_input("yeastLength")
            
            # ==========================================
            # --- Filter and Align Gene Metadata ---
            # ==========================================
            
            message("Filtering low-count genes and aligning metadata...")
            filter <- apply(geneLevelData, 1, function(x) mean(x) > 10)
            print(table(filter))
            
            common_features <- intersect(names(yeastGC), names(yeastLength))
            common <- intersect(common_features, rownames(geneLevelData[filter, ]))
            message(paste("Number of common genes:", length(common)))
            
            # ==========================================
            # --- Create SeqExpressionSet Object ---
            # ==========================================
            
            message("Creating SeqExpressionSet...")
            feature <- data.frame(gc = yeastGC[common_features], 
                                  length = yeastLength[common_features], 
                                  row.names = common_features)
            
            n_samples <- ncol(geneLevelData)
            n_mut <- floor(n_samples / 2)
            n_wt <- n_samples - n_mut
            
            data <- newSeqExpressionSet(counts = as.matrix(geneLevelData[common, ]),
                                        featureData = feature[common, ],
                                        phenoData = data.frame(
                                          conditions = factor(c(rep("mut", n_mut), rep("wt", n_wt))),
                                          row.names = colnames(geneLevelData)))
            print(data)
            
            # Inspecting the object
            print(head(counts(data)))
            print(pData(data))
            print(head(fData(data)))
            print(head(offst(data)))
            
            # ==========================================
            # --- Exploratory Plotting ---
            # ==========================================
            
            message("Generating exploratory plots...")
            pdf("EDASeq_plots.pdf", width = 8, height = 8)
            
            # Boxplot of raw counts
            boxplot(data, col = colors[1:4], main = "Raw Counts Boxplot")
            
            # Mean-Difference Plot
            idx2 <- min(3, ncol(data))
            MDPlot(data, c(1, idx2))
            
            # Mean-Variance Plots
            meanVarPlot(data[, 1:2], log = TRUE, ylim = c(0, 16))
            meanVarPlot(data, log = TRUE, ylim = c(0, 16))
            
            # Bias Plot (GC-content)
            biasPlot(data, "gc", log = TRUE, ylim = c(1, 5))
            
            # Bias Boxplot
            lfc <- log(counts(data)[, idx2] + 0.1) - log(counts(data)[, 1] + 0.1)
            biasBoxplot(lfc, fData(data)\$gc)
            
            # ==========================================
            # --- Normalization (Within-lane and Between-lane) ---
            # ==========================================
            
            message("Performing within-lane and between-lane normalization...")
            dataWithin <- withinLaneNormalization(data, "gc", which = "full")
            dataNorm <- betweenLaneNormalization(dataWithin, which = "full")
            
            # Post-normalization plots
            biasPlot(dataNorm, "gc", log = TRUE, ylim = c(1, 5))
            boxplot(dataNorm, col = colors, main = "Normalized Counts Boxplot")
            
            # Save normalized counts
            write.csv(counts(dataNorm), "normalized_counts.csv", row.names = TRUE)
            saveRDS(dataNorm, "dataNorm.rds")
            
            # ==========================================
            # --- Generate Normalization Offsets ---
            # ==========================================
            
            message("Generating normalization offsets...")
            dataOffset <- withinLaneNormalization(data, "gc", which = "full", offset = TRUE)
            dataOffset <- betweenLaneNormalization(dataOffset, which = "full", offset = TRUE)
            saveRDS(dataOffset, "dataOffset.rds")
            
            # ==========================================
            # --- Differential Expression Analysis: edgeR ---
            # ==========================================
            
            message("Running edgeR analysis...")
            design <- model.matrix(~conditions, data = pData(dataOffset))
            
            y <- DGEList(counts = counts(dataOffset),
                         group = pData(dataOffset)\$conditions)
            y\$offset <- -offst(dataOffset)
            y <- estimateDisp(y, design)
            
            fit <- glmFit(y, design)
            lrt <- glmLRT(fit, coef = 2)
            print(topTags(lrt))
            
            # Save edgeR results
            write.csv(as.data.frame(topTags(lrt, n = Inf)), "edgeR_results.csv", row.names = TRUE)
            
            # ==========================================
            # --- Differential Expression Analysis: DESeq2 ---
            # ==========================================
            
            message("Running DESeq2 analysis...")
            dds <- DESeqDataSetFromMatrix(countData = counts(dataOffset),
                                          colData = pData(dataOffset),
                                          design = ~ conditions)
            
            normFactors <- exp(-1 * offst(dataOffset))
            normFactors <- normFactors / exp(rowMeans(log(normFactors)))
            normalizationFactors(dds) <- normFactors
            
            dds <- DESeq(dds)
            res <- results(dds)
            print(res)
            
            # Save DESeq2 results
            write.csv(as.data.frame(res), "DESeq2_results.csv", row.names = TRUE)
            
            # ==========================================
            # --- Unrounded Normalization & Verification ---
            # ==========================================
            
            message("Verifying unrounded normalization and offset calculations...")
            dataNorm_unrounded <- betweenLaneNormalization(data, round = FALSE, offset = TRUE)
            
            norm1 <- normCounts(dataNorm_unrounded)
            norm2 <- exp(log(counts(dataNorm_unrounded) + 0.1) + offst(dataNorm_unrounded)) - 0.1
            
            print(head(norm1 - norm2))
            print(head(round(normCounts(dataNorm_unrounded)) - round(counts(dataNorm_unrounded) * exp(offst(dataNorm_unrounded)))))
            
            # Close PDF device
            dev.off()
            message("Plots saved to 'EDASeq_plots.pdf'")
            
            # ==========================================
            # --- Optional: Retrieve Gene Length and GC Content ---
            # ==========================================
            
            message("Running optional gene length and GC content retrieval steps...")
            
            tryCatch({
              test_retrieval <- getGeneLengthAndGCContent(id = c("ENSG00000012048", "ENSG00000139618"), org = "hsa")
              print(test_retrieval)
            }, error = function(e) {
              message("Skipping human gene metadata retrieval (requires internet/biomaRt): ", e\$message)
            })
            
            message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE":',
        paste0('    EDASeq: ', as.character(packageVersion('EDASeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_normalization_and_de.csv versions.yml
    """
}

workflow BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneLevelData, yeastGC, yeastLength ] ]

    main:
    BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE(ch_input)

    emit:
    tables   = BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE.out.tables
    plots    = BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE.out.plots
    objects  = BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE.out.objects
    versions = BIOC_EDASEQ_GENE_LEVEL_NORMALIZATION_AND_DE.out.versions
}
