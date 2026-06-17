#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: benchdamic — concordance_analysis
// Measure the agreement between different DA methods (BMC) and within a single method (WMC) across split datasets.
// Input: ps_plaque_16S
// Container: quay.io/biocontainers/bioconductor-benchdamic:1.6.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, benchdamic, ggplot2, phyloseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Split the dataset randomly into two balanced subsets
//  * 2. [Input & Preparation] Set up normalizations and DA methods
//  * 3. [Core Analysis] Run DA methods on the split subsets
//  * 4. [Core Analysis] Compute concordance at the top (CAT) metrics
//  * 5. [Visualization & Output] Plot concordance dendrogram and heatmap

nextflow.enable.dsl = 2

process BIOC_BENCHDAMIC_CONCORDANCE_ANALYSIS {
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
    .bm_deps <- c("benchdamic", "phyloseq", "BiocParallel", "ggplot2")
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
    library(benchdamic)
    library(phyloseq)
    library(BiocParallel)
    library(ggplot2)
    
    # 1. Read the declared USER INPUT file from the working directory
    if (file.exists("ps_plaque_16S")) {
      ps_plaque_16S <- readRDS("ps_plaque_16S")
    } else if (file.exists("ps_plaque_16S.rds")) {
      ps_plaque_16S <- readRDS("ps_plaque_16S.rds")
    } else {
      stop("Error: Input file 'ps_plaque_16S' or 'ps_plaque_16S.rds' not found in the working directory.")
    }
    
    # 2. Split the dataset randomly into two balanced subsets
    set.seed(123)
    sample_data(ps_plaque_16S)\$HMP_BODY_SUBSITE <- factor(sample_data(ps_plaque_16S)\$HMP_BODY_SUBSITE)
    sample_data(ps_plaque_16S)\$RSID <- factor(sample_data(ps_plaque_16S)\$RSID)
    
    my_splits <- createSplits(
      object = ps_plaque_16S,
      varName = "HMP_BODY_SUBSITE",
      paired = "RSID",
      balanced = TRUE,
      N = 2
    )
    
    # 3. Set up normalizations and DA methods
    my_edgeR_noWeights <- set_edgeR(
        group_name = "HMP_BODY_SUBSITE", 
        design = ~ 1 + RSID + HMP_BODY_SUBSITE, 
        coef = "HMP_BODY_SUBSITESupragingival Plaque", 
        norm = "TMM")
    
    my_DESeq2_noWeights <- set_DESeq2(
        contrast = c("HMP_BODY_SUBSITE", "Supragingival Plaque", "Subgingival Plaque"),
        design = ~ 1 + RSID + HMP_BODY_SUBSITE,
        norm = "poscounts")
    
    my_limma_noWeights <- set_limma(
        design = ~ 1 + RSID + HMP_BODY_SUBSITE,
        coef = "HMP_BODY_SUBSITESupragingival Plaque",
        norm = "TMM")
    
    my_methods_noWeights <- c(my_edgeR_noWeights, my_DESeq2_noWeights, my_limma_noWeights)
    
    my_normalizations <- setNormalizations(
        fun = c("norm_edgeR", "norm_DESeq2", "norm_CSS"),
        method = c("TMM", "poscounts", "CSS")
    )
    
    # 4. Run DA methods on the split subsets
    bpparam <- BiocParallel::SerialParam()
    Plaque_16S_splitsDA <- runSplits(
        split_list = my_splits, 
        method_list = my_methods_noWeights, 
        normalization_list = my_normalizations, 
        object = ps_plaque_16S, 
        min_counts = 0, min_samples = 2, 
        verbose = FALSE,
        BPPARAM = bpparam)
    
    # 5. Compute concordance at the top (CAT) metrics
    concordance <- createConcordance(
        object = Plaque_16S_splitsDA,
        slot = "pValMat",
        colName = "rawP",
        type = "pvalue"
    )
    
    # 6. Plot concordance dendrogram and heatmap
    pC <- plotConcordance(concordance = concordance, threshold = 30)
    
    # 7. Write named output files for the meaningful results
    saveRDS(Plaque_16S_splitsDA, "Plaque_16S_splitsDA.rds")
    write.csv(concordance\$BMC, "concordance_BMC_results.csv", row.names = FALSE)
    write.csv(concordance\$WMC, "concordance_WMC_results.csv", row.names = FALSE)
    ggsave("concordance_plot.pdf", plot = pC, width = 8, height = 6)

    writeLines(c(
        '"BIOC_BENCHDAMIC_CONCORDANCE_ANALYSIS":',
        paste0('    benchdamic: ', as.character(packageVersion('benchdamic')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_concordance_analysis.csv versions.yml
    """
}

workflow BIOC_BENCHDAMIC_CONCORDANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ps_plaque_16S ] ]

    main:
    BIOC_BENCHDAMIC_CONCORDANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BENCHDAMIC_CONCORDANCE_ANALYSIS.out.tables
    plots    = BIOC_BENCHDAMIC_CONCORDANCE_ANALYSIS.out.plots
    objects  = BIOC_BENCHDAMIC_CONCORDANCE_ANALYSIS.out.objects
    versions = BIOC_BENCHDAMIC_CONCORDANCE_ANALYSIS.out.versions
}
