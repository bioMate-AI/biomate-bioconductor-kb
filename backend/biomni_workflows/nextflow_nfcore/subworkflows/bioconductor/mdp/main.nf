#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mdp — standard_mdp_analysis
// Quantify sample and gene perturbation scores relative to a control group using omic expression data.
// Input: expression_data.csv, phenotype_data.csv
// Container: quay.io/biocontainers/bioconductor-mdp:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mdp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the mdp package and input datasets
//  * 2. [Core Analysis] Run the main mdp function to calculate perturbation scores
//  * 3. [Visualization & Output] Extract and plot sample scores for the perturbed genes
//  * 4. [Core Analysis] Extract thresholded z-scores, gene scores, gene frequencies, and the list of perturbed genes

nextflow.enable.dsl = 2

process BIOC_MDP_STANDARD_MDP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("mdp")
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
    
    # Load the required library
    library(mdp)
    
    # 1. Load the input datasets from the working directory
    # The expression data must have gene names in the rows and samples in the columns.
    example_data <- read.csv("expression_data.csv", row.names = 1, check.names = FALSE)
    
    # The phenotype data must contain 'Sample' and 'Class' columns.
    example_pheno <- read.csv("phenotype_data.csv", stringsAsFactors = FALSE)
    
    # Dynamically determine the control label to avoid hardcoding
    possible_controls <- c("baseline", "Baseline", "control", "Control", "WT", "wt", "Normal", "normal")
    control_label <- intersect(possible_controls, example_pheno\$Class)[1]
    if (is.na(control_label)) {
      control_label <- unique(example_pheno\$Class)[1]
    }
    
    # 2. Run the main mdp function to calculate perturbation scores
    mdp.results <- mdp(data=example_data, pdata=example_pheno, control_lab = control_label)
    
    # 3. Extract and plot sample scores for the perturbed genes
    sample_scores_list <- mdp.results\$sample_scores
    sample_scores <- sample_scores_list[["perturbedgenes"]]
    head(sample_scores)
    
    # Save the sample perturbation plot to a PDF file
    pdf("sample_scores_plot.pdf", width = 10, height = 7)
    print(sample_plot(sample_scores, control_lab = control_label, title="perturbed"))
    dev.off()
    
    # 4. Extract thresholded z-scores, gene scores, gene frequencies, and the list of perturbed genes
    zscore <- mdp.results\$zscore
    gene_scores <- mdp.results\$gene_scores
    gene_freq <- mdp.results\$gene_freq
    head(gene_scores)
    perturbed_genes <- mdp.results\$perturbed_genes
    
    # 5. Write meaningful results to output files
    write.csv(sample_scores, "sample_scores.csv", row.names = TRUE)
    write.csv(zscore, "zscore_matrix.csv", row.names = TRUE)
    write.csv(gene_scores, "gene_scores.csv", row.names = TRUE)
    write.csv(gene_freq, "gene_freq.csv", row.names = TRUE)
    write.csv(data.frame(Perturbed_Genes = perturbed_genes), "perturbed_genes.csv", row.names = FALSE)
    saveRDS(mdp.results, "mdp_results.rds")

    writeLines(c(
        '"BIOC_MDP_STANDARD_MDP_ANALYSIS":',
        paste0('    mdp: ', as.character(packageVersion('mdp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_mdp_analysis.csv versions.yml
    """
}

workflow BIOC_MDP_STANDARD_MDP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv, phenotype_data.csv ] ]

    main:
    BIOC_MDP_STANDARD_MDP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MDP_STANDARD_MDP_ANALYSIS.out.tables
    plots    = BIOC_MDP_STANDARD_MDP_ANALYSIS.out.plots
    objects  = BIOC_MDP_STANDARD_MDP_ANALYSIS.out.objects
    versions = BIOC_MDP_STANDARD_MDP_ANALYSIS.out.versions
}
