#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: demuxSNP — supervised_demultiplexing_hashing_snps
// Demultiplex multiplexed scRNA-seq cells by training a classifier on high-confidence cell hashing assignments and predicting unassigned cells using SNP profiles.
// Input: multiplexed_scrnaseq_sce, commonvariants_1kgenomes_subset, vartrix_consensus_snps, EnsDb.Hsapiens.v86
// Container: quay.io/biocontainers/bioconductor-demuxsnp:1.8.0--r45hdfd78af_0
// R packages: SingleCellExperiment, VariantAnnotation, ComplexHeatmap, demuxSNP, dittoSeq, ggpubr, Seurat, viridisLite
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, EnsDb.Hsapiens.v86, SingleCellExperiment, VariantAnnotation, demuxSNP, viridisLite
// Visualizations: heatmap (ComplexHeatmap)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify top commonly expressed genes in the scRNA-seq data using common_genes
//  * 2. [Core Analysis] Subset the common variants VCF file to those within the top expressed genes using subset_vcf
//  * 3. [Core Analysis] Identify high-confidence cell hashing assignments using high_conf_calls
//  * 4. [Core Analysis] Add the externally generated VarTrix SNP matrix to the SingleCellExperiment object using add_snps
//  * 5. [Core Analysis] Reassign low-confidence or unassigned cells to their genetic groups using reassign_centroid

nextflow.enable.dsl = 2

process BIOC_DEMUXSNP_SUPERVISED_DEMULTIPLEXING_HASHING_SNPS {
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
    .bm_deps <- c("SingleCellExperiment", "VariantAnnotation", "ComplexHeatmap", "demuxSNP", "dittoSeq", "ggpubr", "Seurat", "viridisLite")
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
    library(demuxSNP)
    library(VariantAnnotation)
    library(ComplexHeatmap)
    library(viridisLite)
    library(grid)
    
    # ==========================================
    # 1. Read User Input Files from Working Dir
    # ==========================================
    
    # Read multiplexed_scrnaseq_sce
    if (file.exists("multiplexed_scrnaseq_sce.rds")) {
      multiplexed_scrnaseq_sce <- readRDS("multiplexed_scrnaseq_sce.rds")
    } else if (file.exists("multiplexed_scrnaseq_sce")) {
      multiplexed_scrnaseq_sce <- readRDS("multiplexed_scrnaseq_sce")
    } else {
      stop("Error: Required input file 'multiplexed_scrnaseq_sce' (RDS format) not found in the working directory.")
    }
    
    # Read commonvariants_1kgenomes_subset
    if (file.exists("commonvariants_1kgenomes_subset.vcf")) {
      commonvariants_1kgenomes_subset <- readVcf("commonvariants_1kgenomes_subset.vcf")
    } else if (file.exists("commonvariants_1kgenomes_subset.vcf.gz")) {
      commonvariants_1kgenomes_subset <- readVcf("commonvariants_1kgenomes_subset.vcf.gz")
    } else if (file.exists("commonvariants_1kgenomes_subset")) {
      commonvariants_1kgenomes_subset <- readVcf("commonvariants_1kgenomes_subset")
    } else {
      stop("Error: Required input file 'commonvariants_1kgenomes_subset' (VCF format) not found in the working directory.")
    }
    
    # Read vartrix_consensus_snps
    if (file.exists("vartrix_consensus_snps.rds")) {
      vartrix_consensus_snps <- readRDS("vartrix_consensus_snps.rds")
    } else if (file.exists("vartrix_consensus_snps.csv")) {
      vartrix_consensus_snps <- as.matrix(read.csv("vartrix_consensus_snps.csv", row.names = 1))
    } else if (file.exists("vartrix_consensus_snps")) {
      vartrix_consensus_snps <- readRDS("vartrix_consensus_snps")
    } else {
      stop("Error: Required input file 'vartrix_consensus_snps' (RDS or CSV format) not found in the working directory.")
    }
    
    # ==========================================
    # 2. Execute Documented Workflow
    # ==========================================
    
    top_genes <- common_genes(sce = multiplexed_scrnaseq_sce, n = 100)
    ensdb <- EnsDb.Hsapiens.v86::EnsDb.Hsapiens.v86
    new_vcf <- subset_vcf(commonvariants_1kgenomes_subset, top_genes = top_genes, ensdb)
    multiplexed_scrnaseq_sce <- high_conf_calls(multiplexed_scrnaseq_sce)
    multiplexed_scrnaseq_sce <- add_snps(multiplexed_scrnaseq_sce, vartrix_consensus_snps, thresh = 0.95)
    set.seed(1)
    multiplexed_scrnaseq_sce\$labels<-as.character(multiplexed_scrnaseq_sce\$labels)
    multiplexed_scrnaseq_sce\$knn <- reassign_centroid(multiplexed_scrnaseq_sce,
        train_cells = multiplexed_scrnaseq_sce\$train,
        predict_cells = multiplexed_scrnaseq_sce\$predict,
        min_cells = 5
    )
    
    # ==========================================
    # 3. Write Named Output Files
    # ==========================================
    
    # Save the subsetted VCF file
    writeVcf(new_vcf, "subsetted_commonvariants.vcf")
    
    # Save the updated SingleCellExperiment object
    saveRDS(multiplexed_scrnaseq_sce, "multiplexed_scrnaseq_sce_demultiplexed.rds")
    
    # Save the KNN assignments table
    knn_table <- data.frame(
      Cell = colnames(multiplexed_scrnaseq_sce),
      Original_Labels = multiplexed_scrnaseq_sce\$labels,
      KNN_Assignment = multiplexed_scrnaseq_sce\$knn,
      Is_Train = multiplexed_scrnaseq_sce\$train,
      Is_Predict = multiplexed_scrnaseq_sce\$predict
    )
    write.csv(knn_table, "knn_assignments.csv", row.names = FALSE)
    
    # Generate and save the updated SNP profiles heatmap
    colors <- structure(viridis(n = 3), names = c("-1", "0", "1"))
    hm <- Heatmap(counts(altExp(multiplexed_scrnaseq_sce, "SNP")),
        column_split = multiplexed_scrnaseq_sce\$knn,
        cluster_rows = FALSE,
        show_column_names = FALSE,
        cluster_column_slices = FALSE,
        column_names_rot = 45,
        column_title_rot = -45,
        row_title = "SNPs",
        show_row_names = FALSE,
        col = colors
    )
    
    pdf("snp_profiles_knn_updated.pdf", width = 10, height = 8)
    draw(hm,
        column_title = "SNP profiles split by updated knn classification",
        padding = unit(c(2, 15, 2, 2), "mm")
    )
    dev.off()

    writeLines(c(
        '"BIOC_DEMUXSNP_SUPERVISED_DEMULTIPLEXING_HASHING_SNPS":',
        paste0('    demuxSNP: ', as.character(packageVersion('demuxSNP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_demultiplexing_hashing_snps.csv versions.yml
    """
}

workflow BIOC_DEMUXSNP_SUPERVISED_DEMULTIPLEXING_HASHING_SNPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multiplexed_scrnaseq_sce, commonvariants_1kgenomes_subset, vartrix_consensus_snps, EnsDb.Hsapiens.v86 ] ]

    main:
    BIOC_DEMUXSNP_SUPERVISED_DEMULTIPLEXING_HASHING_SNPS(ch_input)

    emit:
    tables   = BIOC_DEMUXSNP_SUPERVISED_DEMULTIPLEXING_HASHING_SNPS.out.tables
    plots    = BIOC_DEMUXSNP_SUPERVISED_DEMULTIPLEXING_HASHING_SNPS.out.plots
    objects  = BIOC_DEMUXSNP_SUPERVISED_DEMULTIPLEXING_HASHING_SNPS.out.objects
    versions = BIOC_DEMUXSNP_SUPERVISED_DEMULTIPLEXING_HASHING_SNPS.out.versions
}
