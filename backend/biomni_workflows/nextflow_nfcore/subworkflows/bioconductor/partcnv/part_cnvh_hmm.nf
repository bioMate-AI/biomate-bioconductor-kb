#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: partCNV — part_cnvh_hmm
// Identify locally aneuploid cells using partCNVH which integrates a Hidden Markov Model for feature selection.
// Input: scRNA_seq_counts.rds, cytogenetics_info.txt
// Container: quay.io/biocontainers/bioconductor-partcnv:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, ggplot2, partCNV
// Visualizations: UMAP/t-SNE plot, UMAP plot
// QC: count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve genomic coordinates for the cytogenetics feature
//  * 2. [Core Analysis] Subset and filter the count matrix
//  * 3. [Core Analysis] Run the EM algorithm with HMM feature selection

nextflow.enable.dsl = 2

process BIOC_PARTCNV_PART_CNVH_HMM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("partCNV", "Seurat", "ggplot2")
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
    library(partCNV)
    
    # 1. Read user input files
    # Read scRNA-seq counts
    Counts <- readRDS("scRNA_seq_counts.rds")
    
    # Read cytogenetics info with robust fallbacks
    cyto_feature <- "chr20(q11.1-q13.1)"
    cyto_p <- 0.40
    cyto_type <- "del"
    
    if (file.exists("cytogenetics_info.txt")) {
      tryCatch({
        cyto_info <- read.table("cytogenetics_info.txt", header = TRUE, sep = "", stringsAsFactors = FALSE)
        if ("feature" %in% colnames(cyto_info)) cyto_feature <- cyto_info\$feature[1]
        if ("proportion" %in% colnames(cyto_info)) cyto_p <- as.numeric(cyto_info\$proportion[1])
        if ("type" %in% colnames(cyto_info)) cyto_type <- cyto_info\$type[1]
      }, error = function(e) {
        try({
          lines <- readLines("cytogenetics_info.txt")
          for (line in lines) {
            parts <- strsplit(line, "[:=\\t]")[[1]]
            if (length(parts) >= 2) {
              key <- trimws(parts[1])
              val <- trimws(parts[2])
              if (grepl("feature", key, ignore.case = TRUE)) cyto_feature <- val
              if (grepl("proportion", key, ignore.case = TRUE) || grepl("p", key, ignore.case = TRUE)) cyto_p <- as.numeric(val)
              if (grepl("type", key, ignore.case = TRUE)) cyto_type <- val
            }
          }
        }, silent = TRUE)
      })
    }
    
    # 2. Retrieve genomic coordinates for the cytogenetics feature
    res <- GetCytoLocation(cyto_feature = cyto_feature)
    
    # 3. Subset and filter the count matrix
    GEout <- GetExprCountCyto(cytoloc_output = res, Counts = as.matrix(Counts), normalization = TRUE, qt_cutoff = 0.99)
    
    # 4. Run the EM algorithm with HMM feature selection
    pcHout <- partCNVH(int_counts = GEout\$ProcessedCount,
                       cyto_type = cyto_type,
                       cyto_p = cyto_p)
    
    # 5. Save outputs
    saveRDS(pcHout, "partCNVH_output.rds")
    
    # Create and save labels data frame
    results_df <- data.frame(
      Cell = colnames(GEout\$ProcessedCount),
      EMlabel = pcHout\$EMlabel,
      EMHMMlabel = pcHout\$EMHMMlabel
    )
    write.csv(results_df, "partCNVH_labels.csv", row.names = FALSE)
    
    # 6. Optional Seurat visualization
    tryCatch({
      library(Seurat)
      library(ggplot2)
      
      sim_seurat <- CreateSeuratObject(counts = Counts)
      sim_seurat <- NormalizeData(sim_seurat, normalization.method = "LogNormalize", scale.factor = 10000)
      sim_seurat <- FindVariableFeatures(sim_seurat, selection.method = "vst", nfeatures = min(2000, nrow(Counts)))
      all.genes <- rownames(sim_seurat)
      sim_seurat <- ScaleData(sim_seurat, features = all.genes)
      sim_seurat <- RunPCA(sim_seurat, features = VariableFeatures(object = sim_seurat), verbose = FALSE)
      sim_seurat <- RunUMAP(sim_seurat, dims = 1:10, verbose = FALSE)
      
      labels_vector <- rep(NA, ncol(Counts))
      names(labels_vector) <- colnames(Counts)
      labels_vector[colnames(GEout\$ProcessedCount)] <- pcHout\$EMHMMlabel
      
      sim_seurat <- AddMetaData(
        object = sim_seurat,
        metadata = labels_vector,
        col.name = "partCNVH_label"
      )
      
      sim_seurat\$partCNVH_label <- factor(sim_seurat\$partCNVH_label, levels = c(1,0), labels = c("aneuploid", "diploid"))
      
      p2 <- sum(pcHout\$EMHMMlabel == 1, na.rm = TRUE) / length(pcHout\$EMHMMlabel)
      
      pdf("umap_partCNVH.pdf", width = 8, height = 6)
      p <- DimPlot(sim_seurat, reduction = "umap", group.by = "partCNVH_label") + 
        ggtitle(paste0("partCNVH (", signif(p2, 2) * 100, "%)"))
      print(p)
      dev.off()
    }, error = function(e) {
      message("Seurat visualization skipped or failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_PARTCNV_PART_CNVH_HMM":',
        paste0('    partCNV: ', as.character(packageVersion('partCNV')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_part_cnvh_hmm.csv versions.yml
    """
}

workflow BIOC_PARTCNV_PART_CNVH_HMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scRNA_seq_counts.rds, cytogenetics_info.txt ] ]

    main:
    BIOC_PARTCNV_PART_CNVH_HMM(ch_input)

    emit:
    tables   = BIOC_PARTCNV_PART_CNVH_HMM.out.tables
    plots    = BIOC_PARTCNV_PART_CNVH_HMM.out.plots
    objects  = BIOC_PARTCNV_PART_CNVH_HMM.out.objects
    versions = BIOC_PARTCNV_PART_CNVH_HMM.out.versions
}
