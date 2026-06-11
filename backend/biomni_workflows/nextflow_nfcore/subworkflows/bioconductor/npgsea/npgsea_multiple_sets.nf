#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: npGSEA — npgsea_multiple_sets
// Run moment-based gene set enrichment analysis for a collection of gene sets and generate an HTML report.
// Input: expression_matrix.csv, phenotype_data.csv, gene_sets.gmt
// Container: quay.io/biocontainers/bioconductor-npgsea:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, ReportingTools, npGSEA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load expression data and phenotype factor. 2. Define a collection of gene sets using GeneSetCollection. 3. Run npGSEA on the colle

nextflow.enable.dsl = 2

process BIOC_NPGSEA_NPGSEA_MULTIPLE_SETS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        library(Biobase)
        library(GSEABase)
        library(npGSEA)
        library(ReportingTools)
        
        # 1. Load expression data and phenotype factor
        if (!file.exists("expression_matrix.csv")) {
          stop("Error: 'expression_matrix.csv' not found in the working directory.")
        }
        if (!file.exists("phenotype_data.csv")) {
          stop("Error: 'phenotype_data.csv' not found in the working directory.")
        }
        if (!file.exists("gene_sets.gmt")) {
          stop("Error: 'gene_sets.gmt' not found in the working directory.")
        }
        
        # Read expression matrix
        expr_mat <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Read phenotype data
        pheno_data <- read.csv("phenotype_data.csv", row.names = 1, check.names = FALSE)
        
        # Align samples between expression matrix and phenotype data
        common_samples <- intersect(colnames(expr_mat), rownames(pheno_data))
        if (length(common_samples) == 0) {
          stop("Error: No matching sample names found between expression_matrix.csv and phenotype_data.csv")
        }
        
        expr_mat <- expr_mat[, common_samples, drop = FALSE]
        pheno_data <- pheno_data[common_samples, , drop = FALSE]
        
        # Define the target variable/factor
        yFactor <- as.factor(pheno_data[[1]])
        
        # Construct the ExpressionSet object named 'ALL' to match documented code
        ALL <- ExpressionSet(exprs = expr_mat, phenoData = AnnotatedDataFrame(pheno_data))
        
        # 2. Define a collection of gene sets using GeneSetCollection
        gsc <- getGmt("gene_sets.gmt")
        
        # 3. Run npGSEA on the collection to obtain a npGSEAResultNormCollection
        resgsc_norm <- npGSEA(x = ALL, y = yFactor, set = gsc)  
        
        # 4. Extract statistics and p-values across all sets using unlisted accessors
        p_left_vals <- unlist( pLeft(resgsc_norm) )
        stat_vals   <- unlist( stat (resgsc_norm) )
        z_stat_vals <- unlist( zStat (resgsc_norm) )
        pvals       <- p.adjust( unlist(pTwoSided(resgsc_norm)), method= "BH" )
        
        # Save extracted statistics to a CSV file
        results_df <- data.frame(
          GeneSet = names(p_left_vals),
          pLeft = p_left_vals,
          Stat = stat_vals,
          zStat = z_stat_vals,
          pTwoSided = unlist(pTwoSided(resgsc_norm)),
          pTwoSided_BH = pvals,
          stringsAsFactors = FALSE
        )
        write.csv(results_df, "npgsea_results.csv", row.names = FALSE)
        
        # Save the raw collection object
        saveRDS(resgsc_norm, "npgsea_results.rds")
        
        # 5. Adjust p-values for multiple testing and publish results to an HTML report
        npgseaReport <- HTMLReport (shortName = "npGSEA",
                title = "npGSEA Results", reportDirectory = "./reports")
        publish(gsc, npgseaReport,
                setStats = unlist(zStat (resgsc_norm)), setPValues = pvals)
        finish(npgseaReport)

    writeLines(c(
        '"BIOC_NPGSEA_NPGSEA_MULTIPLE_SETS":',
        paste0('    npGSEA: ', as.character(packageVersion('npGSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_npgsea_multiple_sets.csv versions.yml
    """
}

workflow BIOC_NPGSEA_NPGSEA_MULTIPLE_SETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_data.csv, gene_sets.gmt ] ]

    main:
    BIOC_NPGSEA_NPGSEA_MULTIPLE_SETS(ch_input)

    emit:
    tables   = BIOC_NPGSEA_NPGSEA_MULTIPLE_SETS.out.tables
    plots    = BIOC_NPGSEA_NPGSEA_MULTIPLE_SETS.out.plots
    objects  = BIOC_NPGSEA_NPGSEA_MULTIPLE_SETS.out.objects
    versions = BIOC_NPGSEA_NPGSEA_MULTIPLE_SETS.out.versions
}
