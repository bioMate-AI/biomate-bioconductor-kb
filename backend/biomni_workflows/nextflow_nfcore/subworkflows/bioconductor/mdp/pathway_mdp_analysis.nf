#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mdp — pathway_mdp_analysis
// Quantify sample perturbation scores within specific biological pathways using gene sets.
// Input: expression_data.csv, phenotype_data.csv, pathways.gmt
// Container: quay.io/biocontainers/bioconductor-mdp:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: fgsea, mdp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the mdp package and input datasets
//  * 2. [Input & Preparation] Read the pathway GMT file using fgsea::gmtPathways
//  * 3. [Core Analysis] Run the mdp function with the pathways argument
//  * 4. [Core Analysis] Extract pathway signal-to-noise ratios and pathway-specific sample scores
//  * 5. [Visualization & Output] Plot sample scores for a specific pathway

nextflow.enable.dsl = 2

process BIOC_MDP_PATHWAY_MDP_ANALYSIS {
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
    .bm_deps <- c("mdp", "fgsea")
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
    library(mdp)
    library(fgsea)
    
    # 1. Read the declared user input files from the working directory
    expression_data <- read.csv("expression_data.csv", row.names = 1, check.names = FALSE)
    phenotype_data <- read.csv("phenotype_data.csv", stringsAsFactors = FALSE)
    pathways <- fgsea::gmtPathways("pathways.gmt")
    
    # Determine control label dynamically
    classes <- unique(phenotype_data\$Class)
    control_label <- classes[tolower(classes) %in% c("baseline", "control", "healthy", "normal", "wt", "wildtype")]
    if (length(control_label) > 0) {
      control_label <- control_label[1]
    } else {
      control_label <- classes[1]
    }
    
    # 2. Run the mdp function with the pathways argument
    # Keeping the exact argument names and structure as documented
    mdp.results <- mdp(data = expression_data, pdata = phenotype_data, control_lab = control_label, pathways = pathways)
    
    # 3. Extract pathway signal-to-noise ratios and pathway-specific sample scores
    # Save the pathway signal-to-noise ratios table
    write.csv(mdp.results\$pathways, "pathway_signal_to_noise.csv", row.names = FALSE)
    
    # Determine the pathway to extract and plot.
    # We default to "Interferon alpha/beta signaling" as in the documentation,
    # but fallback to the first available pathway if it is not present in the user's GMT.
    target_pathway <- "Interferon alpha/beta signaling"
    available_pathways <- names(mdp.results\$sample_scores)
    if (!(target_pathway %in% available_pathways)) {
      # Exclude "perturbedgenes" if possible to get an actual pathway
      pathway_candidates <- available_pathways[available_pathways != "perturbedgenes"]
      if (length(pathway_candidates) > 0) {
        target_pathway <- pathway_candidates[1]
      } else if (length(available_pathways) > 0) {
        target_pathway <- available_pathways[1]
      }
    }
    
    # Extract sample scores for the selected pathway
    sample_scores <- mdp.results\$sample_scores[[target_pathway]]
    
    # Save the sample scores to a CSV file
    write.csv(sample_scores, "sample_scores_selected_pathway.csv", row.names = TRUE)
    
    # 4. Plot sample scores for the specific pathway and save to PDF
    pdf("sample_scores_plot.pdf", width = 8, height = 6)
    print(sample_plot(sample_scores, control_lab = control_label, title = target_pathway))
    dev.off()
    
    # Save the full results object as RDS
    saveRDS(mdp.results, "mdp_results.rds")

    writeLines(c(
        '"BIOC_MDP_PATHWAY_MDP_ANALYSIS":',
        paste0('    mdp: ', as.character(packageVersion('mdp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_mdp_analysis.csv versions.yml
    """
}

workflow BIOC_MDP_PATHWAY_MDP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv, phenotype_data.csv, pathways.gmt ] ]

    main:
    BIOC_MDP_PATHWAY_MDP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MDP_PATHWAY_MDP_ANALYSIS.out.tables
    plots    = BIOC_MDP_PATHWAY_MDP_ANALYSIS.out.plots
    objects  = BIOC_MDP_PATHWAY_MDP_ANALYSIS.out.objects
    versions = BIOC_MDP_PATHWAY_MDP_ANALYSIS.out.versions
}
