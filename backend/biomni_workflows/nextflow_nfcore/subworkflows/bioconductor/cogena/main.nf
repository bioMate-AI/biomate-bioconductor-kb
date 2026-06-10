#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cogena — pathway_and_go_analysis
// Perform co-expression clustering on differentially expressed genes followed by pathway or GO term enrichment analysis.
// Input: DEexprs, sampleLabel, annofile
// Container: quay.io/biocontainers/bioconductor-cogena:1.44.0--r45hdfd78af_0
// R packages: cogena
// Bioconductor: 3.20 | R: 4.4
// Requires: cogena
// Visualizations: heatmap, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run co-expression clustering using coExp
//  * 2. [Core Analysis] Run gene set enrichment analysis using clEnrich
//  * 3. [Visualization & Output] Summarize results using summary and extract enrichment tables using enrichment
//  * 4. [Visualization & Output] Visualize co-expression profiles using heatmapCluster
//  * 5. [Visualization & Output] Visualize enrichment results using heatmapPEI (with optional circle layout)
//  * 6. [Core Analysis] Query genes in specific clusters using geneInCluster or extract expression profiles using geneExpInCluster
//  * 7. [Core Analysis] Check gene correlation within a cluster using corInCluster

nextflow.enable.dsl = 2

process BIOC_COGENA_PATHWAY_AND_GO_ANALYSIS {
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
    .bm_deps <- c("cogena")
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
        library(cogena)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        # Read DEexprs (matrix, data.frame, or ExpressionSet)
        if (file.exists("DEexprs.csv")) {
          DEexprs <- as.matrix(read.csv("DEexprs.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("DEexprs.tsv")) {
          DEexprs <- as.matrix(read.delim("DEexprs.tsv", row.names = 1, check.names = FALSE))
        } else if (file.exists("DEexprs.rds")) {
          DEexprs <- readRDS("DEexprs.rds")
        } else if (file.exists("DEexprs")) {
          DEexprs <- as.matrix(read.table("DEexprs", header = TRUE, row.names = 1, check.names = FALSE))
        } else {
          stop("Error: DEexprs file not found in the working directory.")
        }
        
        # Read sampleLabel (vector of sample names/labels)
        if (file.exists("sampleLabel.txt")) {
          sampleLabel <- readLines("sampleLabel.txt")
        } else if (file.exists("sampleLabel.csv")) {
          sampleLabel <- read.csv("sampleLabel.csv", header = FALSE)[[1]]
        } else if (file.exists("sampleLabel.rds")) {
          sampleLabel <- readRDS("sampleLabel.rds")
        } else if (file.exists("sampleLabel")) {
          sampleLabel <- readLines("sampleLabel")
        } else {
          stop("Error: sampleLabel file not found in the working directory.")
        }
        
        # Ensure sampleLabel is a factor with correct ordering (control first, interest second)
        if (!is.factor(sampleLabel)) {
          unique_labels <- unique(sampleLabel)
          if ("ct" %in% unique_labels && "Psoriasis" %in% unique_labels) {
            sampleLabel <- factor(sampleLabel, levels = c("ct", "Psoriasis"))
          } else {
            sampleLabel <- factor(sampleLabel, levels = unique_labels)
          }
        }
        
        # Read annofile (path to a GMT gene set file)
        if (file.exists("annofile")) {
          annofile <- "annofile"
        } else if (file.exists("annofile.gmt")) {
          annofile <- "annofile.gmt"
        } else if (file.exists("annofile.gmt.xz")) {
          annofile <- "annofile.gmt.xz"
        } else if (file.exists("annofile.txt")) {
          annofile <- readLines("annofile.txt", n = 1)
        } else {
          stop("Error: annofile (GMT gene set file) not found in the working directory.")
        }
        
        # ==========================================
        # 2. Define Key Parameters
        # ==========================================
        nClust <- 10
        clMethods <- c("hierarchical", "pam")
        metric <- "correlation"
        method <- "complete"
        ncore <- 1
        
        # ==========================================
        # 3. Run Co-expression Clustering
        # ==========================================
        genecl_result <- coExp(
          DEexprs, 
          nClust = nClust, 
          clMethods = clMethods, 
          metric = metric, 
          method = method, 
          ncore = ncore
        )
        
        # ==========================================
        # 4. Run Gene Set Enrichment Analysis
        # ==========================================
        clen_res <- clEnrich(
          genecl_result, 
          annofile = annofile, 
          sampleLabel = sampleLabel
        )
        
        # Save the core enrichment result object
        saveRDS(clen_res, "clen_res.rds")
        
        # ==========================================
        # 5. Summarize and Extract Enrichment Tables
        # ==========================================
        sink("clen_res_summary.txt")
        summary(clen_res)
        sink()
        
        enrichment.table <- enrichment(clen_res, "pam", "10")
        write.csv(enrichment.table, "enrichment_table_pam_10.csv", row.names = TRUE)
        
        # ==========================================
        # 6. Visualize Co-expression Profiles
        # ==========================================
        pdf("heatmap_cluster_pam_10.pdf", width = 10, height = 7)
        heatmapCluster(clen_res, "pam", "10", maintitle = "Psoriasis")
        dev.off()
        
        # ==========================================
        # 7. Visualize Enrichment Results
        # ==========================================
        pdf("heatmap_pei_pam_10.pdf", width = 11, height = 7)
        print(heatmapPEI(
          clen_res, 
          "pam", 
          "10", 
          printGS = FALSE, 
          maintitle = "Pathway analysis for Psoriasis"
        ))
        dev.off()
        
        pdf("heatmap_pei_circle_pam_10.pdf", width = 11, height = 7)
        print(heatmapPEI(
          clen_res, 
          "pam", 
          "10", 
          printGS = FALSE, 
          maintitle = "Pathway analysis for Psoriasis", 
          geom = "circle"
        ))
        dev.off()
        
        # ==========================================
        # 8. Query Genes and Expression Profiles
        # ==========================================
        geneC <- geneInCluster(clen_res, "pam", "10", "4")
        writeLines(geneC, "genes_in_cluster_pam_10_4.txt")
        
        gec <- geneExpInCluster(clen_res, "pam", "10")
        write.csv(gec\$clusterGeneExp, "gene_exp_in_cluster_pam_10.csv", row.names = TRUE)
        
        # ==========================================
        # 9. Check Gene Correlation Within a Cluster
        # ==========================================
        pdf("cor_in_cluster_pam_10_10.pdf", width = 6, height = 6)
        corInCluster(clen_res, "pam", "10", "10")
        dev.off()

    writeLines(c(
        '"BIOC_COGENA_PATHWAY_AND_GO_ANALYSIS":',
        paste0('    cogena: ', as.character(packageVersion('cogena')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_and_go_analysis.csv versions.yml
    """
}

workflow BIOC_COGENA_PATHWAY_AND_GO_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DEexprs, sampleLabel, annofile ] ]

    main:
    BIOC_COGENA_PATHWAY_AND_GO_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_COGENA_PATHWAY_AND_GO_ANALYSIS.out.tables
    plots    = BIOC_COGENA_PATHWAY_AND_GO_ANALYSIS.out.plots
    objects  = BIOC_COGENA_PATHWAY_AND_GO_ANALYSIS.out.objects
    versions = BIOC_COGENA_PATHWAY_AND_GO_ANALYSIS.out.versions
}
