#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BASiCS — two_group_differential_expression
// Identify changes in gene expression mean, over-dispersion, and residual over-dispersion between two groups of cells.
// Input: chain1.RData, chain2.RData
// Container: quay.io/biocontainers/bioconductor-basics:2.22.0--r45ha27e39d_0
// Requires: BASiCS, SingleCellExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform differential expression testing using BASiCS_TestDE
//  * 2. [Core Analysis] Extract results for mean, dispersion, or residual over-dispersion parameters using as.data.frame
//  * 3. [Core Analysis] Append custom gene metadata using rowData
//  * 4. [Visualization & Output] Visualize differential expression results using BASiCS_PlotDE

nextflow.enable.dsl = 2

process BIOC_BASICS_TWO_GROUP_DIFFERENTIAL_EXPRESSION {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(BASiCS)
        library(SingleCellExperiment)
        
        # Check for user input files
        if (!file.exists("chain1.RData") || !file.exists("chain2.RData")) {
          stop("Error: Required input files 'chain1.RData' and/or 'chain2.RData' not found in the working directory.")
        }
        
        # Helper function to robustly load BASiCS_Chain object from RData file
        load_chain <- function(file_path) {
          env <- new.env()
          load(file_path, envir = env)
          objs <- ls(env)
          for (o in objs) {
            if (inherits(env[[o]], "BASiCS_Chain")) {
              return(env[[o]])
            }
          }
          # Fallback to first object if no BASiCS_Chain class is explicitly detected
          if (length(objs) > 0) {
            return(env[[objs[1]]])
          }
          stop(paste("Error: No objects found in", file_path))
        }
        
        # Load the chains from the user-provided files
        ChainSC <- load_chain("chain1.RData")
        ChainRNA <- load_chain("chain2.RData")
        
        # 1. Run differential expression test
        # Open a PDF device to capture diagnostic plots generated during the test
        pdf("BASiCS_TestDE_diagnostics.pdf", width = 10, height = 8)
        
        Test <- BASiCS_TestDE(
          Chain1 = ChainSC, Chain2 = ChainRNA,
          GroupLabel1 = "SC", GroupLabel2 = "PaS",
          EpsilonM = log2(1.5), EpsilonD = log2(1.5),
          EFDR_M = 0.10, EFDR_D = 0.10,
          Offset = TRUE, PlotOffset = TRUE, Plot = TRUE
        )
        
        dev.off()
        
        # 2. Access results for different parameters
        mean_df <- as.data.frame(Test, Parameter = "Mean")
        disp_df <- as.data.frame(Test, Parameter = "Disp")
        
        print("Head of Mean Parameter Results:")
        print(head(mean_df))
        print("Head of Disp Parameter Results:")
        print(head(disp_df))
        
        # Save initial results to CSV
        write.csv(mean_df, "BASiCS_TestDE_Mean_results_initial.csv", row.names = FALSE)
        write.csv(disp_df, "BASiCS_TestDE_Disp_results.csv", row.names = FALSE)
        
        # 3. Add and format row metadata
        rowData(Test) <- cbind(rowData(Test), Index = 1:nrow(rowData(Test)))
        mean_df_updated <- as.data.frame(Test, Parameter = "Mean")
        
        # Save updated results with metadata
        write.csv(mean_df_updated, "BASiCS_TestDE_Mean_results_with_metadata.csv", row.names = FALSE)
        
        # 4. Visualize results
        # Open a PDF device to capture the differential expression plots
        pdf("BASiCS_PlotDE_results.pdf", width = 10, height = 8)
        
        print(BASiCS_PlotDE(Test))
        print(BASiCS_PlotDE(Test, Plots = c("MA", "Volcano")))
        print(BASiCS_PlotDE(Test, Plots = "MA", Parameters = "Mean"))
        
        dev.off()
        
        # Save the final S4 Results object
        saveRDS(Test, "BASiCS_TestDE_results.rds")
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_BASICS_TWO_GROUP_DIFFERENTIAL_EXPRESSION":',
        paste0('    BASiCS: ', as.character(packageVersion('BASiCS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_group_differential_expression.csv versions.yml
    """
}

workflow BIOC_BASICS_TWO_GROUP_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chain1.RData, chain2.RData ] ]

    main:
    BIOC_BASICS_TWO_GROUP_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_BASICS_TWO_GROUP_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_BASICS_TWO_GROUP_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_BASICS_TWO_GROUP_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_BASICS_TWO_GROUP_DIFFERENTIAL_EXPRESSION.out.versions
}
