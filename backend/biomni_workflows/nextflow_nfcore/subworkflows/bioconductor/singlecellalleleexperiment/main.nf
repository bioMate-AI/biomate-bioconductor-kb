#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SingleCellAlleleExperiment — allele_aware_single_cell_analysis
// Read allele-level single-cell quantification data, aggregate it into gene and functional layers, filter cells, and perform layer-specific dimensionality reducti
// Input: cells_x_genes.barcodes.txt, cells_x_genes.features.txt, cells_x_genes_mtx.mtx, lookup_table.csv
// Container: quay.io/biocontainers/bioconductor-singlecellalleleexperiment:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DropletUtils, SingleCellAlleleExperiment, ggplot2, patchwork, scater, scran, scuttle
// Visualizations: ordination plot, t-SNE plot
// QC: cell QC metrics, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the lookup table mapping alleles to genes and functions
//  * 2. [Visualization & Output] Read raw allele counts and construct the SingleCellAlleleExperiment object using read_allele_counts(), applying knee-plot or custo
//  * 3. [Core Analysis] Subset the dataset into specific layers (non-immune, alleles, immune genes, functional groups) using scae_subset()
//  * 4. [Core Analysis] Model gene variance and identify highly variable genes (HVGs) for each layer using modelGeneVar() and getTopHVGs()
//  * 5. [Core Analysis] Run PCA on each layer using runPCA() with unique names to avoid overwriting
//  * 6. [Core Analysis] Run t-SNE on the reduced dimensions using runTSNE()
//  * 7. [Visualization & Output] Plot expression and reduced dimensions using plotExpression() and plotReducedDim()

nextflow.enable.dsl = 2

process BIOC_SINGLECELLALLELEEXPERIMENT_ALLELE_AWARE_SINGLE_CELL_ANALYSIS {
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
    .bm_deps <- c("SingleCellAlleleExperiment", "scater", "scran", "scuttle", "DropletUtils", "ggplot2", "patchwork")
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
    library(SingleCellAlleleExperiment)
    library(scater)
    library(scran)
    library(scuttle)
    library(DropletUtils)
    library(ggplot2)
    library(patchwork)
    
    # 1. Load the lookup table mapping alleles to genes and functions
    lookup <- utils::read.csv("lookup_table.csv")
    
    # 2. Read raw allele counts and construct the SingleCellAlleleExperiment object
    scae <- read_allele_counts(".",
                               sample_names="example_data",
                               filter_mode="yes",
                               lookup_file=lookup,
                               barcode_file="cells_x_genes.barcodes.txt",
                               gene_file="cells_x_genes.features.txt",
                               matrix_file="cells_x_genes_mtx.mtx",
                               log=TRUE)
    
    # 3. Subset the dataset into specific layers
    scae_nonimmune_subset <- scae_subset(scae, "nonimmune")
    scae_alleles_subset <- scae_subset(scae, "alleles")
    scae_immune_genes_subset <- scae_subset(scae, "immune_genes")
    scae_functional_groups_subset <- scae_subset(scae, "functional_groups")
    
    rn_scae_ni <- rownames(scae_subset(scae, "nonimmune"))
    rn_scae_alleles <- rownames(scae_subset(scae, "alleles"))
    
    scae_nonimmune__allels_subset <- scae[c(rn_scae_ni, rn_scae_alleles), ]
    
    rn_scae_i <- rownames(scae_subset(scae, "immune_genes"))
    
    scae_nonimmune__immune <- scae[c(rn_scae_ni, rn_scae_i), ]
    
    rn_scae_functional <- rownames(scae_subset(scae, "functional_groups"))
    
    scae_nonimmune__functional <- scae[c(rn_scae_ni, rn_scae_functional), ]
    
    # 4. Model gene variance and identify highly variable genes (HVGs)
    df_ni_a <- modelGeneVar(scae_nonimmune__allels_subset)
    top_ni_a <- getTopHVGs(df_ni_a, prop=0.1)
    
    df_ni_g <- modelGeneVar(scae_nonimmune__immune)
    top_ni_g <- getTopHVGs(df_ni_g, prop=0.1)
    
    df_ni_f <- modelGeneVar(scae_nonimmune__functional)
    top_ni_f <- getTopHVGs(df_ni_f, prop=0.1)
    
    # 5. Run PCA on each layer
    assay <- "logcounts"
    
    scae <- runPCA(scae, ncomponents=10, subset_row=top_ni_a,
                   exprs_values=assay, name="PCA_a")
    
    scae <- runPCA(scae, ncomponents=10, subset_row=top_ni_g,
                   exprs_values=assay, name="PCA_g")
    
    scae <- runPCA(scae, ncomponents=10, subset_row=top_ni_f,
                   exprs_values=assay, name="PCA_f")
    
    # 6. Run t-SNE on the reduced dimensions
    set.seed(18)
    scae <- runTSNE(scae, dimred="PCA_g",  name="TSNE_g")
    
    # 7. Plot expression and reduced dimensions
    tsne <- "TSNE_g"
    
    # Determine features to plot dynamically to avoid missing feature errors
    avail_features <- rownames(scae)
    gene_to_plot <- "HLA-DRB1"
    allele1_to_plot <- "DRB1*07:01:01:01"
    allele2_to_plot <- "DRB1*13:01:01:01"
    
    if (!gene_to_plot %in% avail_features) {
        imm_genes <- rownames(scae_subset(scae, "immune_genes"))
        if (length(imm_genes) > 0) {
            gene_to_plot <- imm_genes[1]
        } else {
            gene_to_plot <- avail_features[1]
        }
    }
    
    if (!allele1_to_plot %in% avail_features) {
        alleles <- rownames(scae_subset(scae, "alleles"))
        if (length(alleles) > 0) {
            allele1_to_plot <- alleles[1]
            if (length(alleles) > 1) {
                allele2_to_plot <- alleles[2]
            } else {
                allele2_to_plot <- alleles[1]
            }
        } else {
            allele1_to_plot <- avail_features[1]
            allele2_to_plot <- avail_features[1]
        }
    }
    
    tsne_g_a  <- plotReducedDim(scae, dimred=tsne, colour_by=gene_to_plot) +
                 ggtitle(paste(gene_to_plot, "gene"))
    
    tsne_g_a1 <- plotReducedDim(scae, dimred=tsne, colour_by=allele1_to_plot) + 
                 ggtitle(paste("Allele", allele1_to_plot))
    
    tsne_g_a2 <- plotReducedDim(scae, dimred=tsne, colour_by=allele2_to_plot) + 
                 ggtitle(paste("Allele", allele2_to_plot))
    
    p2 <- tsne_g_a + tsne_g_a1 + tsne_g_a2
    
    # Save outputs
    saveRDS(scae, "scae_processed.rds")
    ggsave("tsne_plots.pdf", plot=p2, width=12, height=4)
    
    write.csv(data.frame(HVG_alleles=top_ni_a), "hvg_alleles.csv", row.names=FALSE)
    write.csv(data.frame(HVG_genes=top_ni_g), "hvg_genes.csv", row.names=FALSE)
    write.csv(data.frame(HVG_functional=top_ni_f), "hvg_functional.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_SINGLECELLALLELEEXPERIMENT_ALLELE_AWARE_SINGLE_CELL_ANALYSIS":',
        paste0('    SingleCellAlleleExperiment: ', as.character(packageVersion('SingleCellAlleleExperiment')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_allele_aware_single_cell_analysis.csv versions.yml
    """
}

workflow BIOC_SINGLECELLALLELEEXPERIMENT_ALLELE_AWARE_SINGLE_CELL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cells_x_genes.barcodes.txt, cells_x_genes.features.txt, cells_x_genes_mtx.mtx, lookup_table.csv ] ]

    main:
    BIOC_SINGLECELLALLELEEXPERIMENT_ALLELE_AWARE_SINGLE_CELL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SINGLECELLALLELEEXPERIMENT_ALLELE_AWARE_SINGLE_CELL_ANALYSIS.out.tables
    plots    = BIOC_SINGLECELLALLELEEXPERIMENT_ALLELE_AWARE_SINGLE_CELL_ANALYSIS.out.plots
    objects  = BIOC_SINGLECELLALLELEEXPERIMENT_ALLELE_AWARE_SINGLE_CELL_ANALYSIS.out.objects
    versions = BIOC_SINGLECELLALLELEEXPERIMENT_ALLELE_AWARE_SINGLE_CELL_ANALYSIS.out.versions
}
