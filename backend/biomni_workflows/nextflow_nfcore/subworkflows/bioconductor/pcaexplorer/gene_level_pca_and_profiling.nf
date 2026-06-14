#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaExplorer — gene_level_pca_and_profiling
// Analyze and visualize gene-level PCA biplots and expression profiles across samples.
// Input: count_matrix.txt, metadata.txt
// Container: quay.io/biocontainers/bioconductor-pcaexplorer:3.4.0--r45hdfd78af_0
// R packages: DESeq2, pcaExplorer, scales
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, pcaExplorer, scales
// Visualizations: PCA plot, biplot, box plot
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Compute and plot gene-level PCA biplots using genespca
//  * 2. [Visualization & Output] Plot expression distributions across samples using distro_expr
//  * 3. [Visualization & Output] Plot standardized expression profiles for a subset of genes using geneprofiler

nextflow.enable.dsl = 2

process BIOC_PCAEXPLORER_GENE_LEVEL_PCA_AND_PROFILING {
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
    .bm_deps <- c("DESeq2", "pcaExplorer", "scales")
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
            library("pcaExplorer")
            library("DESeq2")
            library("scales")
            
            # ==========================================
            # 1. READ USER INPUT FILES & PREPROCESS
            # ==========================================
            
            # Read raw count matrix
            counts <- as.matrix(read.delim("count_matrix.txt", row.names = 1, check.names = FALSE))
            
            # Read sample metadata
            metadata <- read.delim("metadata.txt", row.names = 1, stringsAsFactors = FALSE, check.names = FALSE)
            
            # Align samples between counts and metadata
            common_samples <- intersect(colnames(counts), rownames(metadata))
            if (length(common_samples) == 0) {
              stop("Error: No matching sample names found between count_matrix.txt and metadata.txt")
            }
            counts <- counts[, common_samples, drop = FALSE]
            metadata <- metadata[common_samples, , drop = FALSE]
            
            # Ensure 'dex' column exists in metadata for the documented workflow.
            # If not present, fallback to the first column of metadata.
            if (!"dex" %in% colnames(metadata)) {
              metadata\$dex <- metadata[[1]]
            }
            
            # Ensure 'dex' is a factor
            metadata\$dex <- as.factor(metadata\$dex)
            
            # Create annotation data frame mapping gene IDs to gene names
            annotation_airway <- data.frame(
              gene_name = rownames(counts),
              row.names = rownames(counts),
              stringsAsFactors = FALSE
            )
            
            # Construct DESeqDataSet and DESeqTransform objects from user input
            dds_airway <- DESeqDataSetFromMatrix(
              countData = counts,
              colData = metadata,
              design = ~ dex
            )
            
            # Perform rlog transformation
            rld_airway <- DESeq2::rlogTransformation(dds_airway)
            
            # ==========================================
            # 2. EXECUTE DOCUMENTED WORKFLOW STAGES
            # ==========================================
            
            # Stage 1: Compute and plot gene-level PCA biplots using genespca
            groups_airway <- colData(dds_airway)\$dex
            cols_airway <- scales::hue_pal()(length(levels(groups_airway)))[groups_airway]
            
            pdf("gene_level_pca_biplot.pdf", width = 8, height = 8)
            print(genespca(
              rld_airway,
              ntop = 100,
              choices = c(1, 2),
              arrowColors = cols_airway,
              groupNames = groups_airway,
              alpha = 0.7,
              varname.size = 5,
              annotation = annotation_airway
            ))
            dev.off()
            
            # Stage 2: Plot expression distributions across samples using distro_expr
            pdf("expression_distribution_boxplot.pdf", width = 8, height = 6)
            print(distro_expr(rld_airway, plot_type = "boxplot"))
            dev.off()
            
            # Stage 3: Plot standardized expression profiles for a subset of genes using geneprofiler
            # Replace simulated data setup with the user-input-derived dds object
            dds <- dds_airway
            dst <- rld_airway
            
            pdf("gene_profiles.pdf", width = 10, height = 6)
            set.seed(42)
            print(geneprofiler(dst, sample(rownames(dst), min(20, nrow(dst))), plotZ = FALSE))
            dev.off()
            
            # ==========================================
            # 3. SAVE MEANINGFUL RESULTS
            # ==========================================
            saveRDS(dds_airway, "dds_airway.rds")
            saveRDS(rld_airway, "rld_airway.rds")
            saveRDS(dst, "dst_transformed.rds")
            
            message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_PCAEXPLORER_GENE_LEVEL_PCA_AND_PROFILING":',
        paste0('    pcaExplorer: ', as.character(packageVersion('pcaExplorer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_pca_and_profiling.csv versions.yml
    """
}

workflow BIOC_PCAEXPLORER_GENE_LEVEL_PCA_AND_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix.txt, metadata.txt ] ]

    main:
    BIOC_PCAEXPLORER_GENE_LEVEL_PCA_AND_PROFILING(ch_input)

    emit:
    tables   = BIOC_PCAEXPLORER_GENE_LEVEL_PCA_AND_PROFILING.out.tables
    plots    = BIOC_PCAEXPLORER_GENE_LEVEL_PCA_AND_PROFILING.out.plots
    objects  = BIOC_PCAEXPLORER_GENE_LEVEL_PCA_AND_PROFILING.out.objects
    versions = BIOC_PCAEXPLORER_GENE_LEVEL_PCA_AND_PROFILING.out.versions
}
