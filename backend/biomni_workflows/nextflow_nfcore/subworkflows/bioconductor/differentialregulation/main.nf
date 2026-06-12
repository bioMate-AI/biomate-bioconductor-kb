#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: differentialregulation — single_cell_rna_seq_pipeline
// Detect cell-type specific differentially regulated genes between two groups of samples using single-cell RNA-seq data.
// Input: quants_mat.mtx, quants_mat_rows.txt, quants_mat_cols.txt, geqc_counts.mtx, gene_eqclass.txt.gz, DF_cell_types.txt
// Container: quay.io/biocontainers/bioconductor-differentialregulation:2.8.0--r45ha27e39d_0
// R packages: DifferentialRegulation
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFERENTIALREGULATION_SINGLE_CELL_RNA_SEQ_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-differentialregulation:2.8.0--r45ha27e39d_0"

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
    .bm_deps <- c("DifferentialRegulation")
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
    
    # Load the package
    library(DifferentialRegulation)
    
    # Define sample IDs and paths to user input files in the working directory
    # Since DifferentialRegulation requires multiple samples to model sample-to-sample variability,
    # we map the user-provided single-sample files across 6 mock sample IDs to satisfy the design.
    sample_ids = paste0("sample", 1:6)
    
    path_to_counts = rep("quants_mat.mtx", 6)
    path_to_cell_id = rep("quants_mat_rows.txt", 6)
    path_to_gene_id = rep("quants_mat_cols.txt", 6)
    
    # --- Load USA counts ---
    sce = load_USA(path_to_counts,
                   path_to_cell_id,
                   path_to_gene_id,
                   sample_ids)
    
    # --- Assign cell types to the SingleCellExperiment object ---
    path_to_DF = "DF_cell_types.txt"
    DF_cell_types = read.csv(path_to_DF, sep = "\t", header = TRUE)
    matches = match(colnames(sce), DF_cell_types\$cell_id)
    
    # Robustness fallback: if cell IDs in DF_cell_types do not contain the sample prefix,
    # strip the prefix from colnames(sce) to perform matching.
    if (all(is.na(matches))) {
      cell_ids_clean = sub("^[^\\\\.]+\\\\.", "", colnames(sce))
      matches = match(cell_ids_clean, DF_cell_types\$cell_id)
    }
    sce\$cell_type = DF_cell_types\$cell_type[matches]
    
    # --- Load equivalence classes ---
    path_to_EC_counts = rep("geqc_counts.mtx", 6)
    path_to_EC = rep("gene_eqclass.txt.gz", 6)
    
    EC_list = load_EC(path_to_EC_counts,
                      path_to_EC,
                      path_to_cell_id,
                      path_to_gene_id,
                      sample_ids)
    
    # --- Define experimental design ---
    design = data.frame(sample = sample_ids,
                        group = c( rep("3 mon", 3), rep("6 mon", 3) ))
    
    # --- Compute pseudo-bulk counts ---
    PB_counts = compute_PB_counts(sce = sce,
                                  EC_list = EC_list,
                                  design =  design,
                                  sample_col_name = "sample",
                                  group_col_name = "group",
                                  sce_cluster_name = "cell_type")
    
    rm(EC_list)
    
    # --- Run differential testing ---
    set.seed(1609612)
    results = DifferentialRegulation(PB_counts,
                                     n_cores = 2,
                                     traceplot = TRUE)
    
    # Save results to files
    saveRDS(results, "differential_regulation_results.rds")
    write.csv(results\$Differential_results, "differential_results.csv", row.names = FALSE)
    write.csv(results\$US_results, "US_results.csv", row.names = FALSE)
    write.csv(results\$USA_results, "USA_results.csv", row.names = FALSE)
    
    # --- Visualize results ---
    pdf("pi_plot_US.pdf")
    plot_pi(results,
            type = "US",
            gene_id = results\$Differential_results\$Gene_id[1],
            cluster_id = results\$Differential_results\$Cluster_id[1])
    dev.off()
    
    pdf("traceplot.pdf")
    plot_traceplot(results,
                   gene_id = results\$Differential_results\$Gene_id[1],
                   cluster_id = results\$Differential_results\$Cluster_id[1])
    dev.off()

    writeLines(c(
        '"BIOC_DIFFERENTIALREGULATION_SINGLE_CELL_RNA_SEQ_PIPELINE":',
        paste0('        differentialregulation: ', as.character(packageVersion("differentialregulation")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_rna_seq_pipeline.csv versions.yml
    """
}

workflow BIOC_DIFFERENTIALREGULATION_SINGLE_CELL_RNA_SEQ_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quants_mat.mtx, quants_mat_rows.txt, quants_mat_cols.txt, geqc_counts.mtx, gene_eqclass.txt.gz, DF_cell_types.txt ] ]

    main:
    BIOC_DIFFERENTIALREGULATION_SINGLE_CELL_RNA_SEQ_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DIFFERENTIALREGULATION_SINGLE_CELL_RNA_SEQ_PIPELINE.out.tables
    plots    = BIOC_DIFFERENTIALREGULATION_SINGLE_CELL_RNA_SEQ_PIPELINE.out.plots
    objects  = BIOC_DIFFERENTIALREGULATION_SINGLE_CELL_RNA_SEQ_PIPELINE.out.objects
    versions = BIOC_DIFFERENTIALREGULATION_SINGLE_CELL_RNA_SEQ_PIPELINE.out.versions
}
