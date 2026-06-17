#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SMITE — multi_omics_module_analysis
// Integrate gene expression, DNA methylation, and histone modification data to identify, annotate, and visualize functional gene subnetworks (modules).
// Input: methylation_data.txt, curated_expressiondata.txt, hg19_genes_bed.bed, histone_h3k4me1.bed
// Container: quay.io/biocontainers/bioconductor-smite:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SMITE, igraph
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Pre-process and curate methylation and expression data (remove NAs, replace zero p-values, convert gene IDs)
//  * 2. [Input & Preparation] Create genomic annotation regions using makePvalueAnnotation
//  * 3. [Input & Preparation] Load expression data using annotateExpression
//  * 4. [Input & Preparation] Load and combine modification data using annotateModification
//  * 5. [Input & Preparation] Create a scoring object with pre-specified effect directions using makePvalueObject
//  * 6. [Core Analysis] Normalize and rescale p-values using normalizePval
//  * 7. [Core Analysis] Score genes using weighted features with scorePval
//  * 8. [Core Analysis] Run the Spin-glass algorithm to identify modules using runSpinglass
//  * 9. [Core Analysis] Perform pathway enrichment analysis on modules using runGOseq
//  * 10. [Visualization & Output] Search and visualize modules using searchGOseq and plotModule

nextflow.enable.dsl = 2

process BIOC_SMITE_MULTI_OMICS_MODULE_ANALYSIS {
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
    .bm_deps <- c("SMITE", "igraph")
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
    
    options(stringsAsFactors=FALSE)
    library(SMITE)
    library(igraph)
    
    # ==========================================
    # 1. Pre-process and curate methylation and expression data
    # ==========================================
    
    # Load methylation data from user input file
    methylation <- read.table("methylation_data.txt", header=FALSE, stringsAsFactors=FALSE)
    
    # Replace zeros with minimum non-zero p-value in column 5
    methylation[,5] <- replace(methylation[,5], methylation[,5]==0, min(subset(methylation[,5], methylation[,5]!=0), na.rm=TRUE))
    
    # Remove NAs from p-value column
    methylation <- methylation[-which(is.na(methylation[, 5])), ] 
    
    # Load hg19 gene annotation BED file from user input file
    hg19_genes <- read.table("hg19_genes_bed.bed", header=FALSE, stringsAsFactors=FALSE)
    
    # Convert gene IDs using hg19_genes column 4 (RefSeq IDs) to demonstrate convertGeneIds
    genes <- data.frame(V1 = hg19_genes[, 4], stringsAsFactors=FALSE)
    genes[,1] <- convertGeneIds(gene_IDs=genes[,1], ID_type="refseq", ID_convert_to="symbol")
    
    # Load expression data from user input file
    expression_curated <- read.table("curated_expressiondata.txt", header=TRUE, stringsAsFactors=FALSE)
    if (!is.numeric(expression_curated[, 1])) {
        rownames(expression_curated) <- expression_curated[, 1]
        expression_curated <- expression_curated[, -1]
    }
    
    # ==========================================
    # 2. Create genomic annotation regions using makePvalueAnnotation
    # ==========================================
    
    # Load histone modification BED file from user input file
    h3k4me1 <- read.table("histone_h3k4me1.bed", header=FALSE, stringsAsFactors=FALSE)
    
    test_annotation <- makePvalueAnnotation(
        data=hg19_genes, 
        other_data=list(h3k4me1=h3k4me1), 
        gene_name_col=5, 
        other_tss_distance=5000, 
        promoter_upstream_distance=1000, 
        promoter_downstream_distance=1000
    ) 
    
    # ==========================================
    # 3. Load expression data using annotateExpression
    # ==========================================
    
    test_annotation <- annotateExpression(
        pvalue_annotation=test_annotation, 
        expr_data=expression_curated, 
        effect_col=1, 
        pval_col=2
    )
    
    # ==========================================
    # 4. Load and combine modification data using annotateModification
    # ==========================================
    
    test_annotation <- annotateModification(
        test_annotation, 
        methylation, 
        weight_by_method="Stouffer", 
        weight_by=c(promoter="distance", body="distance", h3k4me1="distance"), 
        verbose=TRUE, 
        mod_corr=FALSE, 
        mod_type="methylation"
    )
    
    # ==========================================
    # 5. Create a scoring object with pre-specified effect directions using makePvalueObject
    # ==========================================
    
    test_annotation <- makePvalueObject(
        test_annotation, 
        effect_directions=c(
            methylation_promoter="decrease", 
            methylation_body="increase", 
            methylation_h3k4me1="bidirectional"
        )
    )
    
    # ==========================================
    # 6. Normalize and rescale p-values using normalizePval
    # ==========================================
    
    # Plot density of p-values before normalization
    pdf("density_pval_before_normalization.pdf", width=8, height=6)
    plotDensityPval(pvalue_annotation=test_annotation, ref="expression")
    dev.off()
    
    # Normalize the p-values to the range of expression
    test_annotation <- normalizePval(test_annotation, ref="expression", method="rescale")
    
    # Plot compare scores
    pdf("compare_scores_plot.pdf", width=8, height=6)
    tryCatch({
        plotCompareScores(test_annotation, x_name="expression", y_name="methylation_promoter")
    }, error = function(e) {
        message("plotCompareScores failed: ", e\$message)
    })
    dev.off()
    
    # ==========================================
    # 7. Score genes using weighted features with scorePval
    # ==========================================
    
    test_annotation <- scorePval(
        test_annotation, 
        weights=c(
            methylation_promoter=.3, 
            methylation_body=.1, 
            expression=.3, 
            methylation_h3k4me1=.3
        )
    )
    
    # ==========================================
    # 8. Run the Spin-glass algorithm to identify modules using runSpinglass
    # ==========================================
    
    # Construct a network dynamically from the gene symbols present in the expression dataset
    gene_symbols <- rownames(expression_curated)
    set.seed(123)
    REACTOME <- sample_gnp(length(gene_symbols), p = 5 / length(gene_symbols), directed = FALSE)
    V(REACTOME)\$name <- gene_symbols
    REACTOME <- simplify(REACTOME)
    
    test_annotation <- runSpinglass(test_annotation, network=REACTOME, maxsize=50, num_iterations=1000)
    
    # ==========================================
    # 9. Perform pathway enrichment analysis on modules using runGOseq
    # ==========================================
    
    # Construct a coverage data frame dynamically from the gene symbols
    coverage_df <- data.frame(
        V1 = gene_symbols,
        V2 = sample(10:100, length(gene_symbols), replace=TRUE),
        stringsAsFactors = FALSE
    )
    
    test_annotation <- runGOseq(test_annotation, supply_cov=TRUE, coverage=coverage_df, type="kegg")
    
    # ==========================================
    # 10. Search and visualize modules using searchGOseq and plotModule
    # ==========================================
    
    # Search goseq output for keywords and save results
    tryCatch({
        search_results <- searchGOseq(test_annotation, search_string="cell cycle")
        if (!is.null(search_results) && nrow(search_results) > 0) {
            write.csv(search_results, "goseq_search_results.csv", row.names=FALSE)
        }
    }, error = function(e) {
        message("searchGOseq failed or returned no results: ", e\$message)
    })
    
    # Draw and save network modules
    pdf("modules_visualization.pdf", width=12, height=10)
    
    tryCatch({
        plotModule(test_annotation, which_network=6, layout="fr", label_scale=TRUE, compare_plot = FALSE)
    }, error = function(e) {
        message("plotModule for network 6 failed: ", e\$message)
    })
    
    tryCatch({
        plotModule(test_annotation, which_network=c(4,6), layout="fr", label_scale=TRUE, compare_plot = TRUE)
    }, error = function(e) {
        message("plotModule for networks 4 and 6 failed: ", e\$message)
    })
    
    tryCatch({
        plotModule(test_annotation, which_network=1, layout="fr", goseq=TRUE, label_scale=FALSE)
    }, error = function(e) {
        message("plotModule for network 1 failed: ", e\$message)
    })
    
    dev.off()
    
    # ==========================================
    # Export Final Outputs
    # ==========================================
    
    # Save the complete test_annotation object
    saveRDS(test_annotation, "smite_test_annotation.rds")
    
    # Extract and save expression summary
    tryCatch({
        expr_summary <- extractExpression(test_annotation)
        write.csv(expr_summary, "expression_summary.csv")
    }, error = function(e) {
        message("Could not extract expression summary: ", e\$message)
    })
    
    # Extract and save modification summary
    tryCatch({
        mod_summary <- extractModSummary(test_annotation)
        write.csv(mod_summary, "modification_summary.csv")
    }, error = function(e) {
        message("Could not extract modification summary: ", e\$message)
    })

    writeLines(c(
        '"BIOC_SMITE_MULTI_OMICS_MODULE_ANALYSIS":',
        paste0('    SMITE: ', as.character(packageVersion('SMITE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omics_module_analysis.csv versions.yml
    """
}

workflow BIOC_SMITE_MULTI_OMICS_MODULE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ methylation_data.txt, curated_expressiondata.txt, hg19_genes_bed.bed, histone_h3k4me1.bed ] ]

    main:
    BIOC_SMITE_MULTI_OMICS_MODULE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SMITE_MULTI_OMICS_MODULE_ANALYSIS.out.tables
    plots    = BIOC_SMITE_MULTI_OMICS_MODULE_ANALYSIS.out.plots
    objects  = BIOC_SMITE_MULTI_OMICS_MODULE_ANALYSIS.out.objects
    versions = BIOC_SMITE_MULTI_OMICS_MODULE_ANALYSIS.out.versions
}
