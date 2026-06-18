#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RTN — trn_reconstruction_and_enrichment
// Reconstruct a transcriptional regulatory network from gene expression data and perform enrichment analysis (MRA, GSEA-1T, GSEA-2T) against a gene expression sig
// Input: expression_matrix.csv, tf_list.txt, gene_annotation.csv, sample_annotation.csv, phenotype_signature.tsv
// Container: quay.io/biocontainers/bioconductor-rtn:2.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RTN
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the TNI object using tni.constructor
//  * 2. [Core Analysis] Run permutation analysis to compute mutual information using tni.permutation
//  * 3. [Core Analysis] Run bootstrap analysis to remove unstable interactions using tni.bootstrap
//  * 4. [Core Analysis] Apply the ARACNe DPI filter to remove indirect interactions using tni.dpi.filter
//  * 5. [Visualization & Output] Summarize and retrieve regulons using tni.regulon.summary and tni.get
//  * 6. [Core Analysis] Preprocess the TNI object into a TNA object using tni2tna.preprocess
//  * 7. [Core Analysis] Run Master Regulator Analysis (MRA) using tna.mra
//  * 8. [Core Analysis] Run one-tailed GSEA using tna.gsea1
//  * 9. [Core Analysis] Run two-tailed GSEA using tna.gsea2
//  * 10. [Core Analysis] Retrieve enrichment results using tna.get

nextflow.enable.dsl = 2

process BIOC_RTN_TRN_RECONSTRUCTION_AND_ENRICHMENT {
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
    .bm_deps <- c("RTN")
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
    library(RTN)
    
    # ---------------------------------------------------------
    # 1. Read User Inputs and Align Data
    # ---------------------------------------------------------
    
    # Read expression matrix (genes on rows, samples on columns)
    exp_matrix <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Read transcription factors list
    tfs <- readLines("tf_list.txt")
    tfs <- tfs[tfs != ""]
    
    # Read gene annotations
    gene_annot <- read.csv("gene_annotation.csv", row.names = 1, check.names = FALSE)
    
    # Read sample annotations
    sample_annot <- read.csv("sample_annotation.csv", row.names = 1, check.names = FALSE)
    
    # Read phenotype signature
    pheno_df <- read.delim("phenotype_signature.tsv", sep="\t", header=TRUE, stringsAsFactors=FALSE)
    
    # Align expression matrix with annotations
    common_samples <- intersect(colnames(exp_matrix), rownames(sample_annot))
    exp_matrix <- exp_matrix[, common_samples, drop=FALSE]
    sample_annot <- sample_annot[common_samples, , drop=FALSE]
    
    common_genes <- intersect(rownames(exp_matrix), rownames(gene_annot))
    exp_matrix <- exp_matrix[common_genes, , drop=FALSE]
    gene_annot <- gene_annot[common_genes, , drop=FALSE]
    
    # Filter TFs to those present in the expression matrix
    tfs <- intersect(tfs, rownames(exp_matrix))
    
    # Construct tniData list to match documented code structure
    tniData <- list(
      expData = exp_matrix,
      rowAnnotation = gene_annot,
      colAnnotation = sample_annot
    )
    
    # Parse phenotype signature
    gene_col <- grep("gene|symbol|id", colnames(pheno_df), ignore.case=TRUE, value=TRUE)[1]
    if(is.na(gene_col)) gene_col <- colnames(pheno_df)[1]
    
    fc_col <- grep("log2|fc|fold|change|value", colnames(pheno_df), ignore.case=TRUE, value=TRUE)[1]
    if(is.na(fc_col)) fc_col <- colnames(pheno_df)[2]
    
    hit_col <- grep("hit|diff|de|sig", colnames(pheno_df), ignore.case=TRUE, value=TRUE)[1]
    
    phenotype_vec <- as.numeric(pheno_df[[fc_col]])
    names(phenotype_vec) <- pheno_df[[gene_col]]
    phenotype_vec <- phenotype_vec[!is.na(phenotype_vec)]
    
    if(!is.na(hit_col)) {
      hits_vec <- as.character(pheno_df[[gene_col]][as.logical(pheno_df[[hit_col]])])
    } else {
      hits_vec <- as.character(pheno_df[[gene_col]][abs(pheno_df[[fc_col]]) > 1])
    }
    hits_vec <- hits_vec[!is.na(hits_vec)]
    
    # Align phenoIDs with phenotype vector
    phenoIDs_df <- gene_annot[intersect(rownames(gene_annot), names(phenotype_vec)), , drop=FALSE]
    
    # Construct tnaData list to match documented code structure
    tnaData <- list(
      phenotype = phenotype_vec,
      hits = hits_vec,
      phenoIDs = phenoIDs_df
    )
    
    # ---------------------------------------------------------
    # 2. Reconstruct Transcriptional Regulatory Network (TNI)
    # ---------------------------------------------------------
    
    # Initialize the TNI object
    rtni <- tni.constructor(expData = tniData\$expData, 
                            regulatoryElements = tfs, 
                            rowAnnotation = tniData\$rowAnnotation, 
                            colAnnotation = tniData\$colAnnotation)
    
    # Run permutation analysis to compute mutual information
    rtni <- tni.permutation(rtni, nPermutations = 100)
    
    # Run bootstrap analysis to remove unstable interactions
    rtni <- tni.bootstrap(rtni)
    
    # Apply the ARACNe DPI filter to remove indirect interactions
    rtni <- tni.dpi.filter(rtni)
    
    # Summarize and retrieve regulons
    tni.regulon.summary(rtni)
    
    tryCatch({
      tni.regulon.summary(rtni, regulatoryElements = "FOXM1")
    }, error = function(e) {
      if (length(tfs) > 0) {
        tni.regulon.summary(rtni, regulatoryElements = tfs[1])
      }
    })
    
    regulons <- tni.get(rtni, what = "regulons.and.mode", idkey = "SYMBOL")
    
    tryCatch({
      print(head(regulons\$FOXM1))
    }, error = function(e) {
      if (length(regulons) > 0) {
        print(head(regulons[[1]]))
      }
    })
    
    # ---------------------------------------------------------
    # 3. Transcriptional Network Analysis (TNA)
    # ---------------------------------------------------------
    
    # Preprocess the TNI object into a TNA object
    rtna <- tni2tna.preprocess(object = rtni, 
                               phenotype = tnaData\$phenotype, 
                               hits = tnaData\$hits, 
                               phenoIDs = tnaData\$phenoIDs)
    
    # Run Master Regulator Analysis (MRA)
    rtna <- tna.mra(rtna)
    
    # Retrieve MRA results
    mra <- tna.get(rtna, what="mra", ntop = -1)
    print(head(mra))
    
    # Run one-tailed GSEA
    rtna <- tna.gsea1(rtna, nPermutations=100)
    
    # Retrieve GSEA1 results
    gsea1 <- tna.get(rtna, what="gsea1", ntop = -1)
    print(head(gsea1))
    
    # Run two-tailed GSEA
    rtna <- tna.gsea2(rtna, nPermutations = 100)
    
    # Retrieve GSEA2 results
    gsea2 <- tna.get(rtna, what = "gsea2", ntop = -1)
    print(head(gsea2\$differential))
    
    # ---------------------------------------------------------
    # 4. Save Outputs (RDS, CSV, PDF)
    # ---------------------------------------------------------
    
    # Save RDS objects
    saveRDS(rtni, "rtni_object.rds")
    saveRDS(rtna, "rtna_object.rds")
    saveRDS(regulons, "regulons_and_mode.rds")
    
    # Save CSV tables
    write.csv(mra, "mra_results.csv", row.names = TRUE)
    write.csv(gsea1, "gsea1_results.csv", row.names = TRUE)
    write.csv(gsea2\$differential, "gsea2_differential_results.csv", row.names = TRUE)
    
    # Save PDF plots
    pdf("gsea1_plots.pdf")
    tryCatch({
      tna.plot.gsea1(rtna, labPheno="abs(log2 fold changes)", ntop = -1)
    }, error = function(e) {
      warning("Could not plot GSEA1: ", e\$message)
    })
    dev.off()
    
    pdf("gsea2_plots.pdf")
    tryCatch({
      tna.plot.gsea2(rtna, labPheno="log2 fold changes", tfs="PTTG1")
    }, error = function(e) {
      if (length(tfs) > 0) {
        tryCatch({
          tna.plot.gsea2(rtna, labPheno="log2 fold changes", tfs=tfs[1])
        }, error = function(e2) {
          warning("Could not plot GSEA2: ", e2\$message)
        })
      }
    })
    dev.off()

    writeLines(c(
        '"BIOC_RTN_TRN_RECONSTRUCTION_AND_ENRICHMENT":',
        paste0('    RTN: ', as.character(packageVersion('RTN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trn_reconstruction_and_enrichment.csv versions.yml
    """
}

workflow BIOC_RTN_TRN_RECONSTRUCTION_AND_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, tf_list.txt, gene_annotation.csv, sample_annotation.csv, phenotype_signature.tsv ] ]

    main:
    BIOC_RTN_TRN_RECONSTRUCTION_AND_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_RTN_TRN_RECONSTRUCTION_AND_ENRICHMENT.out.tables
    plots    = BIOC_RTN_TRN_RECONSTRUCTION_AND_ENRICHMENT.out.plots
    objects  = BIOC_RTN_TRN_RECONSTRUCTION_AND_ENRICHMENT.out.objects
    versions = BIOC_RTN_TRN_RECONSTRUCTION_AND_ENRICHMENT.out.versions
}
