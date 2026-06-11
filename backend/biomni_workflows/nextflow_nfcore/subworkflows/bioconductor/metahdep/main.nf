#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metahdep — gene_expression_meta_analysis
// Format and perform meta-analysis on multiple gene expression datasets (AffyBatch) accounting for sampling and hierarchical dependence.
// Input: Multiple AffyBatch objects, A data frame mapping probesets to common gene identifiers
// Container: quay.io/biocontainers/bioconductor-metahdep:1.64.0--r44h3df3fcb_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, affyPLM, metahdep
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Map probesets to common gene identifiers (Entrez IDs) to create a mapping data frame
//  * 2. [Core Analysis] Calculate effect sizes and covariance matrices for each study using getPLM.es
//  * 3. [Core Analysis] Combine study-specific effect sizes into a list
//  * 4. [Core Analysis] Format the list for meta-analysis using metahdep.format
//  * 5. [Core Analysis] Run meta-analysis (FEMA, REMA, or HBLM) using metahdep

nextflow.enable.dsl = 2

process BIOC_METAHDEP_GENE_EXPRESSION_META_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(metahdep)
    library(affy)
    library(affyPLM)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read the AffyBatch objects from the working directory
    MLL.A <- readRDS("MLL.A.rds")
    spikein95 <- readRDS("spikein95.rds")
    Dilution <- readRDS("Dilution.rds")
    MLL.B <- readRDS("MLL.B.rds")
    
    # Read the mapping data frame
    if (file.exists("HGU.newnames.rds")) {
      HGU.newnames <- readRDS("HGU.newnames.rds")
    } else {
      HGU.newnames <- read.csv("HGU.newnames.csv", stringsAsFactors = FALSE)
    }
    
    # Extract the gene lists for each chip version from the mapping data frame
    use.hgu133a.gn <- HGU.newnames\$old.name[HGU.newnames\$chip == "hgu133a"]
    use.hgu95a.gn <- HGU.newnames\$old.name[HGU.newnames\$chip == "hgu95a"]
    use.hgu95av2.gn <- HGU.newnames\$old.name[HGU.newnames\$chip == "hgu95av2"]
    use.hgu133b.gn <- HGU.newnames\$old.name[HGU.newnames\$chip == "hgu133b"]
    
    # ==========================================
    # 2. Calculate Effect Sizes and Covariances
    # ==========================================
    
    ES.exp1 <- getPLM.es(
      abatch = MLL.A, 
      trt1 = list(c(1:5), c(6:10)), 
      trt2 = list(c(11:15), c(16:20)), 
      sub.gn = use.hgu133a.gn, 
      covariates = data.frame(Tissue = c(0, 1)), 
      dep.grp = 1
    )
    
    ES.exp2 <- getPLM.es(
      abatch = spikein95, 
      trt1 = 1:3, 
      trt2 = 4:6, 
      sub.gn = use.hgu95a.gn, 
      covariates = data.frame(Tissue = 0), 
      dep.grp = 1
    )
    
    ES.exp3 <- getPLM.es(
      abatch = Dilution, 
      trt1 = 1:2, 
      trt2 = 3:4, 
      sub.gn = use.hgu95av2.gn, 
      covariates = data.frame(Tissue = 0), 
      dep.grp = 2
    )
    
    ES.exp4 <- getPLM.es(
      abatch = MLL.B, 
      trt1 = 1:9, 
      trt2 = 10:20, 
      sub.gn = use.hgu133b.gn, 
      covariates = data.frame(Tissue = 1), 
      dep.grp = 3
    )
    
    # ==========================================
    # 3. Combine and Format for Meta-Analysis
    # ==========================================
    
    HGU.DifExp.list <- list(ES.exp1, ES.exp2, ES.exp3, ES.exp4)
    
    HGU.prep.list <- metahdep.format(HGU.DifExp.list, HGU.newnames)
    
    # Save the formatted list
    saveRDS(HGU.prep.list, "HGU_prep_list.rds")
    
    # ==========================================
    # 4. Perform Meta-Analysis
    # ==========================================
    
    set.seed(123)
    available_genes <- names(HGU.prep.list)
    gene.subset <- sample(available_genes, min(50, length(available_genes)))
    
    # Fixed Effects Meta-Analysis
    FEMA <- metahdep(HGU.prep.list, method = "FEMA", genelist = gene.subset, center.X = TRUE)
    
    # Random Effects Meta-Analysis (without and with delta-splitting)
    REMA <- metahdep(HGU.prep.list, method = "REMA", genelist = gene.subset, delta.split = FALSE, center.X = TRUE)
    REMA.ds <- metahdep(HGU.prep.list, method = "REMA", genelist = gene.subset, delta.split = TRUE, center.X = TRUE)
    
    # Hierarchical Bayes Meta-Analysis (without and with delta-splitting)
    HBLM <- metahdep(HGU.prep.list, method = "HBLM", genelist = gene.subset, delta.split = FALSE, center.X = TRUE, two.sided = TRUE)
    HBLM.ds <- metahdep(HGU.prep.list, method = "HBLM", genelist = gene.subset, delta.split = TRUE, center.X = TRUE, two.sided = TRUE)
    
    # ==========================================
    # 5. Save Results and Generate Plots
    # ==========================================
    
    # Write CSV tables
    write.csv(FEMA, "FEMA_results.csv", row.names = TRUE)
    write.csv(REMA, "REMA_results.csv", row.names = TRUE)
    write.csv(REMA.ds, "REMA_ds_results.csv", row.names = TRUE)
    write.csv(HBLM, "HBLM_results.csv", row.names = TRUE)
    write.csv(HBLM.ds, "HBLM_ds_results.csv", row.names = TRUE)
    
    # Generate comparison plot of Intercept P-values
    pvals <- data.frame(
      FEMA = FEMA\$Intercept.pval, 
      REMA = REMA\$Intercept.pval, 
      REMA.ds = REMA.ds\$Intercept.pval,
      HBLM = HBLM\$Intercept.pval, 
      HBLM.ds = HBLM.ds\$Intercept.pval
    )
    
    pdf("pvalues_comparison.pdf", width = 8, height = 8)
    plot(pvals, main = 'Comparison of Intercept P-values from Meta-Analysis', pch = 16, cex = .5)
    dev.off()

    writeLines(c(
        '"BIOC_METAHDEP_GENE_EXPRESSION_META_ANALYSIS":',
        paste0('    metahdep: ', as.character(packageVersion('metahdep')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_expression_meta_analysis.csv versions.yml
    """
}

workflow BIOC_METAHDEP_GENE_EXPRESSION_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Multiple AffyBatch objects, A data frame mapping probesets to common gene identifiers ] ]

    main:
    BIOC_METAHDEP_GENE_EXPRESSION_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METAHDEP_GENE_EXPRESSION_META_ANALYSIS.out.tables
    plots    = BIOC_METAHDEP_GENE_EXPRESSION_META_ANALYSIS.out.plots
    objects  = BIOC_METAHDEP_GENE_EXPRESSION_META_ANALYSIS.out.objects
    versions = BIOC_METAHDEP_GENE_EXPRESSION_META_ANALYSIS.out.versions
}
