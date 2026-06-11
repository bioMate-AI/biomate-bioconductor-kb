#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: signatureSearch — gess_and_fea_analysis
// Perform a gene expression signature search (GESS) using a query signature against a reference database, followed by functional enrichment analysis (TSEA/DSEA) a
// Input: query_mat, upset, downset, db_path
// Container: quay.io/biocontainers/bioconductor-signaturesearch:1.24.0--r45ha27e39d_0
// R packages: BiocParallel, DT, ExperimentHub, HDF5Array, signatureSearch, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: signatureSearch
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the query signature object using qSig
//  * 2. [Core Analysis] Run GESS using a specific method (e.g., CMAP, LINCS, gCMAP, Fisher, or Cor)
//  * 3. [Core Analysis] Extract search results using result
//  * 4. [Core Analysis] Perform Target Set Enrichment Analysis (TSEA) using tsea_dup_hyperG, tsea_mGSEA, or tsea_mabs
//  * 5. [Core Analysis] Perform Drug Set Enrichment Analysis (DSEA) using dsea_hyperG or dsea_GSEA
//  * 6. [Core Analysis] Compare FEA results using comp_fea_res
//  * 7. [Visualization & Output] Visualize drug-target networks using dtnetplot

nextflow.enable.dsl = 2

process BIOC_SIGNATURESEARCH_GESS_AND_FEA_ANALYSIS {
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
    .bm_deps <- c("BiocParallel", "DT", "ExperimentHub", "HDF5Array", "signatureSearch", "SummarizedExperiment")
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
        library(signatureSearch)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        # Read query_mat (matrix of quantitative gene expression changes)
        if (file.exists("query_mat.rds")) {
          query_mat <- readRDS("query_mat.rds")
        } else if (file.exists("query_mat.csv")) {
          query_mat <- as.matrix(read.csv("query_mat.csv", row.names = 1))
        } else {
          stop("Required input file 'query_mat' (RDS or CSV) not found in the working directory.")
        }
        
        # Read upset (character vector of up-regulated gene IDs)
        if (file.exists("upset.rds")) {
          upset <- readRDS("upset.rds")
        } else if (file.exists("upset.txt")) {
          upset <- readLines("upset.txt")
        } else {
          stop("Required input file 'upset' (RDS or TXT) not found in the working directory.")
        }
        
        # Read downset (character vector of down-regulated gene IDs)
        if (file.exists("downset.rds")) {
          downset <- readRDS("downset.rds")
        } else if (file.exists("downset.txt")) {
          downset <- readLines("downset.txt")
        } else {
          stop("Required input file 'downset' (RDS or TXT) not found in the working directory.")
        }
        
        # Read db_path (path to the reference HDF5 database file)
        if (file.exists("db_path.txt")) {
          db_path <- trimws(readLines("db_path.txt", n = 1))
        } else if (file.exists("database.h5")) {
          db_path <- "database.h5"
        } else {
          stop("Required input file 'db_path.txt' or 'database.h5' not found in the working directory.")
        }
        
        # ==========================================
        # 2. Gene Expression Signature Search (GESS)
        # ==========================================
        
        # CMAP Method
        qsig_cmap <- qSig(query = list(upset=upset, downset=downset), 
                          gess_method="CMAP", refdb=db_path)
        cmap <- gess_cmap(qSig=qsig_cmap, chunk_size=5000, workers=1, addAnnotations = TRUE)
        cmap_res <- result(cmap)
        write.csv(cmap_res, "gess_cmap_results.csv", row.names = FALSE)
        saveRDS(cmap, "cmap.rds")
        
        # LINCS Method
        qsig_lincs <- qSig(query=list(upset=upset, downset=downset), 
                           gess_method="LINCS", refdb=db_path)
        lincs <- gess_lincs(qsig_lincs, sortby="NCS", tau=FALSE, workers=1, 
                            addAnnotations = TRUE, GeneType = "reference")
        lincs_res <- result(lincs)
        write.csv(lincs_res, "gess_lincs_results.csv", row.names = FALSE)
        saveRDS(lincs, "lincs.rds")
        
        # gCMAP Method
        qsig_gcmap <- qSig(query = query_mat, gess_method = "gCMAP", refdb = db_path)
        gcmap <- gess_gcmap(qsig_gcmap, higher=1, lower=-1, workers=1, addAnnotations = TRUE)
        gcmap_res <- result(gcmap)
        write.csv(gcmap_res, "gess_gcmap_results.csv", row.names = FALSE)
        saveRDS(gcmap, "gcmap.rds")
        
        # Fisher Method
        qsig_fisher <- qSig(query = query_mat, gess_method = "Fisher", refdb = db_path)
        fisher <- gess_fisher(qSig=qsig_fisher, higher=1, lower=-1, workers=1, addAnnotations = TRUE)
        fisher_res <- result(fisher)
        write.csv(fisher_res, "gess_fisher_results.csv", row.names = FALSE)
        saveRDS(fisher, "fisher.rds")
        
        # Correlation Method (Spearman)
        qsig_sp <- qSig(query=query_mat, gess_method="Cor", refdb=db_path)
        sp <- gess_cor(qSig=qsig_sp, method="spearman", workers=1, addAnnotations = TRUE)
        sp_res <- result(sp)
        write.csv(sp_res, "gess_cor_results.csv", row.names = FALSE)
        saveRDS(sp, "sp.rds")
        
        # ==========================================
        # 3. Functional Enrichment Analysis (FEA)
        # ==========================================
        
        # Extract top 10 drugs from LINCS search results
        drugs <- unique(result(lincs)\$pert[1:10])
        
        # TSEA: Duplication Adjusted Hypergeometric Test (GO MF)
        dup_hyperG_res <- tsea_dup_hyperG(drugs=drugs, universe="Default", 
                                          type="GO", ont="MF", pvalueCutoff=0.05, 
                                          pAdjustMethod="BH", qvalueCutoff=0.1, 
                                          minGSSize=10, maxGSSize=500)
        dup_hyperG_df <- result(dup_hyperG_res)
        write.csv(dup_hyperG_df, "tsea_dup_hyperG_GO_results.csv", row.names = FALSE)
        saveRDS(dup_hyperG_res, "dup_hyperG_res.rds")
        
        # TSEA: Duplication Adjusted Hypergeometric Test (Reactome)
        dup_rct_res <- tsea_dup_hyperG(drugs=drugs, type="Reactome",
                                       pvalueCutoff=0.5, qvalueCutoff=0.5, readable=TRUE)
        dup_rct_df <- result(dup_rct_res)
        write.csv(dup_rct_df, "tsea_dup_hyperG_Reactome_results.csv", row.names = FALSE)
        saveRDS(dup_rct_res, "dup_rct_res.rds")
        
        # TSEA: Modified GSEA (GO MF)
        mgsea_res <- tsea_mGSEA(drugs=drugs, type="GO", ont="MF", exponent=1, 
                                nPerm=1000, pvalueCutoff=1, minGSSize=5)
        mgsea_df <- result(mgsea_res)
        write.csv(mgsea_df, "tsea_mGSEA_results.csv", row.names = FALSE)
        saveRDS(mgsea_res, "mgsea_res.rds")
        
        # TSEA: MeanAbs Method (GO MF)
        mabs_res <- tsea_mabs(drugs=drugs, type="GO", ont="MF", nPerm=1000, 
                              pvalueCutoff=0.05, minGSSize=5)
        mabs_df <- result(mabs_res)
        write.csv(mabs_df, "tsea_mabs_results.csv", row.names = FALSE)
        saveRDS(mabs_res, "mabs_res.rds")
        
        # DSEA: Hypergeometric Test (GO MF)
        hyperG_res <- dsea_hyperG(drugs=drugs, type="GO", ont="MF")
        hyperG_df <- result(hyperG_res)
        write.csv(hyperG_df, "dsea_hyperG_results.csv", row.names = FALSE)
        saveRDS(hyperG_res, "hyperG_res.rds")
        
        # DSEA: GSEA Method (GO MF)
        dl <- abs(result(lincs)\$NCS); names(dl) <- result(lincs)\$pert
        dl <- dl[dl>0]
        dl <- dl[!duplicated(names(dl))]
        dl <- sort(dl, decreasing = TRUE)
        gsea_res <- dsea_GSEA(drugList=dl, type="GO", ont="MF", exponent=1, nPerm=1000,
                              pvalueCutoff=0.2, minGSSize=5)
        gsea_df <- result(gsea_res)
        write.csv(gsea_df, "dsea_GSEA_results.csv", row.names = FALSE)
        saveRDS(gsea_res, "gsea_res.rds")
        
        # ==========================================
        # 4. Compare FEA Results
        # ==========================================
        
        table_list = list("dup_hyperG" = dup_hyperG_res, 
                          "mGSEA" = mgsea_res, 
                          "mabs" = mabs_res, 
                          "hyperG" = hyperG_res, 
                          "GSEA" = gsea_res)
        compared_fea <- comp_fea_res(table_list, rank_stat="pvalue", Nshow=20)
        write.csv(compared_fea, "compared_fea_results.csv", row.names = FALSE)
        
        # ==========================================
        # 5. Drug-Target Network Visualization
        # ==========================================
        
        pdf("drug_target_network.pdf", width = 10, height = 8)
        tryCatch({
          # Attempt the exact documented call
          dtnetplot(drugs = drugs(dup_hyperG_res), set = "GO:0032041", ont = "MF", 
                    desc="NAD-dependent histone deacetylase activity (H3-K14 specific)")
        }, error = function(e) {
          warning("Could not plot specific GO:0032041 network: ", e\$message)
          # Fallback: Attempt to plot the top enriched term from the hypergeometric results
          if (nrow(dup_hyperG_df) > 0) {
            top_set <- dup_hyperG_df\$ID[1]
            top_desc <- dup_hyperG_df\$Description[1]
            message("Attempting fallback plot with top enriched term: ", top_set)
            dtnetplot(drugs = drugs(dup_hyperG_res), set = top_set, ont = "MF", desc = top_desc)
          } else {
            message("No enriched terms found to plot.")
          }
        })
        dev.off()

    writeLines(c(
        '"BIOC_SIGNATURESEARCH_GESS_AND_FEA_ANALYSIS":',
        paste0('    signatureSearch: ', as.character(packageVersion('signatureSearch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gess_and_fea_analysis.csv versions.yml
    """
}

workflow BIOC_SIGNATURESEARCH_GESS_AND_FEA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query_mat, upset, downset, db_path ] ]

    main:
    BIOC_SIGNATURESEARCH_GESS_AND_FEA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SIGNATURESEARCH_GESS_AND_FEA_ANALYSIS.out.tables
    plots    = BIOC_SIGNATURESEARCH_GESS_AND_FEA_ANALYSIS.out.plots
    objects  = BIOC_SIGNATURESEARCH_GESS_AND_FEA_ANALYSIS.out.objects
    versions = BIOC_SIGNATURESEARCH_GESS_AND_FEA_ANALYSIS.out.versions
}
