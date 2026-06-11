#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioNERO — gene_regulatory_network
// Infer a directed gene regulatory network from expression data and a list of regulators (TFs/miRNAs) using consensus or individual algorithms, and identify regul
// Input: zma.se, zma.tfs
// Container: quay.io/biocontainers/bioconductor-bionero:1.18.0--r45hdfd78af_0
// R packages: BioNERO, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: BioNERO, SummarizedExperiment, htmlwidgets
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess expression data using exp_preprocess()
//  * 2. [Core Analysis] Infer consensus GRN using exp2grn() or individual algorithms using grn_infer() or grn_combined()
//  * 3. [Core Analysis] Identify regulatory hub genes using get_hubs_grn()
//  * 4. [Visualization & Output] Visualize the regulatory network using plot_grn()

nextflow.enable.dsl = 2

process BIOC_BIONERO_GENE_REGULATORY_NETWORK {
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
        
        # Read user input files from the working directory
        zma.se <- readRDS("zma.se")
        zma.tfs <- read.table("zma.tfs", header = TRUE)
        
        # 1. Preprocess the expression data
        final_exp <- exp_preprocess(
            zma.se, min_exp = 10, variance_filter = TRUE, n = 2000
        )
        saveRDS(final_exp, "final_exp.rds")
        
        # 2. Consensus GRN inference
        grn <- exp2grn(
            exp = final_exp, regulators = zma.tfs\$Gene, nTrees = 10
        )
        write.csv(grn, "consensus_grn.csv", row.names = FALSE)
        
        # 3. Algorithm-specific GRN inference
        genie3 <- grn_infer(
            final_exp, method = "genie3", regulators = zma.tfs\$Gene, nTrees = 10
        )
        write.csv(genie3, "genie3_grn.csv", row.names = FALSE)
        
        aracne <- grn_infer(final_exp, method = "aracne", regulators = zma.tfs\$Gene)
        write.csv(aracne, "aracne_grn.csv", row.names = FALSE)
        
        clr <- grn_infer(final_exp, method = "clr", regulators = zma.tfs\$Gene)
        write.csv(clr, "clr_grn.csv", row.names = FALSE)
        
        grn_list <- grn_combined(final_exp, regulators = zma.tfs\$Gene, nTrees = 10)
        saveRDS(grn_list, "grn_list.rds")
        
        # 4. Hub gene identification
        hubs <- get_hubs_grn(grn)
        write.csv(hubs, "grn_hubs.csv", row.names = FALSE)
        
        # 5. Network visualization
        # Save static network plot to PDF
        pdf("grn_plot.pdf", width = 7, height = 7)
        print(plot_grn(grn))
        dev.off()
        
        # Save interactive network plot to HTML if htmlwidgets is available
        tryCatch({
            p_interactive <- plot_grn(grn, interactive = TRUE, dim_interactive = c(500,500))
            htmlwidgets::saveWidget(p_interactive, "grn_interactive.html")
        }, error = function(e) {
            message("Interactive plot could not be saved as HTML: ", e\$message)
        })

    writeLines(c(
        '"BIOC_BIONERO_GENE_REGULATORY_NETWORK":',
        paste0('    BioNERO: ', as.character(packageVersion('BioNERO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_regulatory_network.csv versions.yml
    """
}

workflow BIOC_BIONERO_GENE_REGULATORY_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zma.se, zma.tfs ] ]

    main:
    BIOC_BIONERO_GENE_REGULATORY_NETWORK(ch_input)

    emit:
    tables   = BIOC_BIONERO_GENE_REGULATORY_NETWORK.out.tables
    plots    = BIOC_BIONERO_GENE_REGULATORY_NETWORK.out.plots
    objects  = BIOC_BIONERO_GENE_REGULATORY_NETWORK.out.objects
    versions = BIOC_BIONERO_GENE_REGULATORY_NETWORK.out.versions
}
