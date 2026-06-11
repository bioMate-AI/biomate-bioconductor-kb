#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioNERO — consensus_modules
// Identify common coexpression modules across multiple expression datasets (e.g., different subsets or conditions).
// Input: zma.se
// Container: quay.io/biocontainers/bioconductor-bionero:1.18.0--r45hdfd78af_0
// R packages: BioNERO, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: BioNERO, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess and subset expression data into a list of datasets
//  * 2. [Core Analysis] Determine consensus scale-free topology fit power using consensus_SFT_fit()
//  * 3. [Core Analysis] Identify consensus modules using consensus_modules()
//  * 4. [Visualization & Output] Correlate consensus modules to traits using consensus_trait_cor() and plot using plot_module_trait_cor()

nextflow.enable.dsl = 2

process BIOC_BIONERO_CONSENSUS_MODULES {
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
    .bm_deps <- c("BioNERO", "SummarizedExperiment")
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
    library(BioNERO)
    
    # Set seed for reproducibility
    set.seed(123)
    
    # Read user input file
    zma.se <- readRDS("zma.se")
    
    # Preprocess data and create subsets
    filt_zma <- exp_preprocess(zma.se, variance_filter = TRUE, n = 2000)
    zma_set1 <- filt_zma[, sample(colnames(filt_zma), size=min(22, ncol(filt_zma)), replace=FALSE)]
    zma_set2 <- filt_zma[, sample(colnames(filt_zma), size=min(22, ncol(filt_zma)), replace=FALSE)]
    zma_list <- list(set1 = zma_set1, set2 = zma_set2)
    
    # Consensus SFT fit
    cons_sft <- consensus_SFT_fit(zma_list, setLabels = c("Maize 1", "Maize 2"), cor_method = "pearson")
    powers <- cons_sft\$power
    
    # Identification of consensus modules
    consensus <- consensus_modules(zma_list, power = powers, cor_method = "pearson")
    
    # Consensus module-trait correlation
    consensus_trait <- consensus_trait_cor(consensus, cor_method = "pearson")
    
    # Save outputs
    # 1. Save the consensus modules object
    saveRDS(consensus, file = "consensus_modules_output.rds")
    
    # 2. Save the consensus trait correlation table
    write.csv(consensus_trait, file = "consensus_trait_correlation.csv", row.names = FALSE)
    
    # 3. Save the plot
    pdf("consensus_module_trait_cor_plot.pdf", width = 8, height = 8)
    print(plot_module_trait_cor(consensus_trait))
    dev.off()

    writeLines(c(
        '"BIOC_BIONERO_CONSENSUS_MODULES":',
        paste0('    BioNERO: ', as.character(packageVersion('BioNERO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consensus_modules.csv versions.yml
    """
}

workflow BIOC_BIONERO_CONSENSUS_MODULES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zma.se ] ]

    main:
    BIOC_BIONERO_CONSENSUS_MODULES(ch_input)

    emit:
    tables   = BIOC_BIONERO_CONSENSUS_MODULES.out.tables
    plots    = BIOC_BIONERO_CONSENSUS_MODULES.out.plots
    objects  = BIOC_BIONERO_CONSENSUS_MODULES.out.objects
    versions = BIOC_BIONERO_CONSENSUS_MODULES.out.versions
}
