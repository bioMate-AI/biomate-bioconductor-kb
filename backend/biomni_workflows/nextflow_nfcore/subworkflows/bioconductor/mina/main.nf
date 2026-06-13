#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mina — community_diversity_analysis
// Perform data normalization, calculate community dissimilarity, evaluate unexplained variance, and visualize beta-diversity using PCoA.
// Input: maize_asv2, maize_des2
// Container: quay.io/biocontainers/bioconductor-mina:1.18.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mina
// Visualizations: diversity plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create mina object and align tables
//  * 2. [Core Analysis] Normalize data using total sum scaling or rarefaction
//  * 3. [Core Analysis] Calculate community dissimilarity (e.g., Bray-Curtis)
//  * 4. [Core Analysis] Calculate unexplained variance ratio
//  * 5. [Visualization & Output] Perform dimensionality reduction and plot beta-diversity

nextflow.enable.dsl = 2

process BIOC_MINA_COMMUNITY_DIVERSITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("mina")
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
        library(mina)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files from Working Directory
        # -----------------------------------------------------------------------------
        
        # Read quantitative OTU/ASV count table (maize_asv2)
        if (file.exists("maize_asv2.csv")) {
          maize_asv2 <- read.csv("maize_asv2.csv", row.names = 1, check.names = FALSE)
        } else if (file.exists("maize_asv2.tsv")) {
          maize_asv2 <- read.delim("maize_asv2.tsv", row.names = 1, check.names = FALSE)
        } else if (file.exists("maize_asv2.txt")) {
          maize_asv2 <- read.table("maize_asv2.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        } else if (file.exists("maize_asv2")) {
          maize_asv2 <- tryCatch(
            read.table("maize_asv2", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE),
            error = function(e) read.csv("maize_asv2", row.names = 1, check.names = FALSE)
          )
        } else {
          stop("Error: 'maize_asv2' file not found in the working directory.")
        }
        
        # Convert quantitative table to matrix as expected by mina
        maize_asv2 <- as.matrix(maize_asv2)
        
        # Read descriptive sample metadata table (maize_des2)
        if (file.exists("maize_des2.csv")) {
          maize_des2 <- read.csv("maize_des2.csv", check.names = FALSE)
        } else if (file.exists("maize_des2.tsv")) {
          maize_des2 <- read.delim("maize_des2.tsv", check.names = FALSE)
        } else if (file.exists("maize_des2.txt")) {
          maize_des2 <- read.table("maize_des2.txt", header = TRUE, sep = "\t", check.names = FALSE)
        } else if (file.exists("maize_des2")) {
          maize_des2 <- tryCatch(
            read.table("maize_des2", header = TRUE, sep = "\t", check.names = FALSE),
            error = function(e) read.csv("maize_des2", check.names = FALSE)
          )
        } else {
          stop("Error: 'maize_des2' file not found in the working directory.")
        }
        
        # Ensure maize_des is defined for the get_r2 step
        maize_des <- maize_des2
        
        # -----------------------------------------------------------------------------
        # 2. Execute Documented Workflow
        # -----------------------------------------------------------------------------
        
        # Create mina object and align tables
        maize <- new("mina", tab = maize_asv2, des = maize_des2)
        maize <- fit_tabs(maize)
        
        # Normalized by rarefaction and bootstrap 9 times
        maize <- norm_tab(maize, method = "raref", depth = 5000, multi = 9)
        
        # Tidy the norm tab, initial tab and des tab
        maize <- fit_tabs(maize)
        
        # Community dissimilarity calculation, Bray-Curtis used in example
        maize <- com_dis(maize, method = "bray")
        
        # Get the unexplained variance ratio of quantitative table according to the
        # group information indicated in descriptive table.
        r2_val1 <- com_r2(maize, group = c("Compartment", "Soil", "Host_genotype"))
        
        # Use tables as input
        maize_dis <- dis(maize)
        r2_val2 <- get_r2(maize_dis, maize_des, group = c("Compartment", "Soil", "Host_genotype"))
        
        # Dimensionality reduction
        maize <- dmr(maize)
        
        # Plot the community beta-diversity
        # Separate samples from different conditions by color, plot PCo1 and PCo2
        p1 <- com_plot(maize, match = "Sample_ID", color = "Compartment")
        
        # Plot PCo3 and PCo4
        p2 <- com_plot(maize, match = "Sample_ID", d1 = 3, d2 = 4, color =
                        "Compartment")
        
        # In addition, separate samples from different soil type by shape
        p3 <- com_plot(maize, match = "Sample_ID", color = "Compartment", shape =
                        "Soil")
        
        # Plot PCo1 and PCo4
        p4 <- com_plot(maize, match = "Sample_ID", d1 = 1, d2 = 4, color =
                        "Compartment", shape = "Soil")
        
        # -----------------------------------------------------------------------------
        # 3. Save Outputs to Working Directory
        # -----------------------------------------------------------------------------
        
        # Save unexplained variance R2 values
        r2_results <- data.frame(
          Analysis = c("com_r2", "get_r2"),
          Unexplained_Variance_Ratio = c(r2_val1, r2_val2)
        )
        write.csv(r2_results, file = "unexplained_variance_r2.csv", row.names = FALSE)
        
        # Save community dissimilarity matrix
        write.csv(as.matrix(maize_dis), file = "community_dissimilarity_matrix.csv")
        
        # Save beta-diversity plots to a PDF file
        pdf("beta_diversity_plots.pdf", width = 10, height = 8)
        print(p1)
        print(p2)
        print(p3)
        print(p4)
        dev.off()
        
        # Save the final processed mina object
        saveRDS(maize, file = "mina_community_analysis.rds")
        
        cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_MINA_COMMUNITY_DIVERSITY_ANALYSIS":',
        paste0('    mina: ', as.character(packageVersion('mina')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_community_diversity_analysis.csv versions.yml
    """
}

workflow BIOC_MINA_COMMUNITY_DIVERSITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ maize_asv2, maize_des2 ] ]

    main:
    BIOC_MINA_COMMUNITY_DIVERSITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MINA_COMMUNITY_DIVERSITY_ANALYSIS.out.tables
    plots    = BIOC_MINA_COMMUNITY_DIVERSITY_ANALYSIS.out.plots
    objects  = BIOC_MINA_COMMUNITY_DIVERSITY_ANALYSIS.out.objects
    versions = BIOC_MINA_COMMUNITY_DIVERSITY_ANALYSIS.out.versions
}
