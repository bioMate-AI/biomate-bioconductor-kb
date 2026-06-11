#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pairedGSEA — paired_dge_dgs_ora_workflow
// Run a paired differential gene expression and differential gene splicing analysis from transcript-level counts, aggregate to gene-level, perform over-representa
// Input: counts.csv, metadata.xlsx
// Container: quay.io/biocontainers/bioconductor-pairedgsea:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: S4Vectors, SummarizedExperiment, ggplot2, pairedGSEA, readxl
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the package and define experiment parameters. 2. Run the paired differential expression and splicing analysis using paired_di

nextflow.enable.dsl = 2

process BIOC_PAIREDGSEA_PAIRED_DGE_DGS_ORA_WORKFLOW {
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
        
        library("pairedGSEA")
        library("SummarizedExperiment")
        library("S4Vectors")
        library("readxl")
        library("ggplot2")
        
        # Defining plotting theme
        ggplot2::theme_set(ggplot2::theme_classic(base_size = 20))
        
        ## Load data from user input files
        counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
        counts_mat <- as.matrix(counts_df)
        
        metadata_df <- as.data.frame(readxl::read_excel("metadata.xlsx"))
        
        ## Experiment parameters
        group_col <- "group_nr" # Column with the groups you would like to compare
        sample_col <- "id" # Name of column that specifies the sample id of each sample.
        
        # Ensure sample_col and group_col exist in metadata, fallback if necessary
        if (!sample_col %in% colnames(metadata_df)) {
            sample_col <- colnames(metadata_df)[1]
        }
        if (!group_col %in% colnames(metadata_df)) {
            group_col <- colnames(metadata_df)[2]
        }
        
        # Align counts and metadata
        common_samples <- intersect(colnames(counts_mat), metadata_df[[sample_col]])
        if (length(common_samples) == 0) {
            stop("No matching sample IDs found between counts.csv columns and metadata.xlsx sample_col.")
        }
        counts_mat <- counts_mat[, common_samples, drop = FALSE]
        metadata_df <- metadata_df[metadata_df[[sample_col]] %in% common_samples, , drop = FALSE]
        rownames(metadata_df) <- metadata_df[[sample_col]]
        metadata_df <- metadata_df[common_samples, , drop = FALSE]
        
        # Construct the SummarizedExperiment object named 'example_se' to match documented code
        example_se <- SummarizedExperiment::SummarizedExperiment(
            assays = list(counts = counts_mat),
            colData = S4Vectors::DataFrame(metadata_df)
        )
        
        # Determine baseline and case dynamically from the group column
        unique_groups <- unique(metadata_df[[group_col]])
        if (length(unique_groups) < 2) {
            stop("At least two groups are required in the group column for comparison.")
        }
        baseline <- unique_groups[1]
        case <- unique_groups[2]
        experiment_title <- "TGFb treatment for 12h"
        
        # Check if parameters above fit with metadata
        SummarizedExperiment::colData(example_se)
        
        # Check that all data samples are in the metadata
        all(colnames(example_se) %in%
                SummarizedExperiment::colData(example_se)[[sample_col]])
        
        set.seed(500) # For reproducible results
        
        diff_results <- paired_diff(
            object = example_se,
            metadata = NULL, # Use with count matrix or if you want to change it in
            # the input object
            group_col = group_col,
            sample_col = sample_col,
            baseline = baseline,
            case = case,
            experiment_title = experiment_title,
            store_results = FALSE # Set to TRUE (recommended)  if you want
            # to store intermediate results, such as the results on transcript level 
            )
        
        # Save differential expression and splicing results
        write.csv(as.data.frame(diff_results), "diff_results.csv", row.names = TRUE)
        saveRDS(diff_results, "diff_results.rds")
        
        # Define gene sets in your preferred way
        gene_sets <- pairedGSEA::prepare_msigdb(
            species = "Homo sapiens", 
            collection = "C5", 
            gene_id_type = "ensembl_gene"
            )
        
        ora <- paired_ora(
            paired_diff_result = diff_results,
            gene_sets = gene_sets,
            experiment_title = NULL # experiment_title - if not NULL,
            # the results will be stored in an RDS object in the 'results' folder
            )
        
        # Save ORA results
        write.csv(as.data.frame(ora), "ora_results.csv", row.names = FALSE)
        saveRDS(ora, "ora_results.rds")
        
        # Scatter plot function with default settings saved to PDF
        pdf("ora_scatterplot.pdf", width = 10, height = 8)
        print(plot_ora(
            ora,
            paired = FALSE,
            plotly = FALSE,
            pattern = "Telomer", # Identify all gene sets about telomeres
            cutoff = 0.05, # Only include significant gene sets
            lines = TRUE # Guide lines
            ))
        dev.off()

    writeLines(c(
        '"BIOC_PAIREDGSEA_PAIRED_DGE_DGS_ORA_WORKFLOW":',
        paste0('    pairedGSEA: ', as.character(packageVersion('pairedGSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_dge_dgs_ora_workflow.csv versions.yml
    """
}

workflow BIOC_PAIREDGSEA_PAIRED_DGE_DGS_ORA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.csv, metadata.xlsx ] ]

    main:
    BIOC_PAIREDGSEA_PAIRED_DGE_DGS_ORA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_PAIREDGSEA_PAIRED_DGE_DGS_ORA_WORKFLOW.out.tables
    plots    = BIOC_PAIREDGSEA_PAIRED_DGE_DGS_ORA_WORKFLOW.out.plots
    objects  = BIOC_PAIREDGSEA_PAIRED_DGE_DGS_ORA_WORKFLOW.out.objects
    versions = BIOC_PAIREDGSEA_PAIRED_DGE_DGS_ORA_WORKFLOW.out.versions
}
