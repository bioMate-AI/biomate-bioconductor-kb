#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: busparse — bus_to_sparse_matrix_and_filtering
// Convert sorted BUS output files into sparse gene count and TCC matrices, and filter out empty droplets using knee plots.
// Input: ./out_hgmm100/output.sorted.txt, ./out_hgmm100/matrix.ec
// Container: quay.io/biocontainers/bioconductor-busparse:1.24.0--r45ha27e39d_0
// R packages: BUSpaRse, ggplot2, Matrix, tenxbusdata, zeallot
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUSPARSE_BUS_TO_SPARSE_MATRIX_AND_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-busparse:1.24.0--r45ha27e39d_0"

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
    .bm_deps <- c("BUSpaRse", "ggplot2", "Matrix", "tenxbusdata", "zeallot")
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
    library(BUSpaRse)
    library(Matrix)
    library(zeallot)
    library(ggplot2)
    
    # Define input paths
    input_dir <- "./out_hgmm100"
    bus_file <- file.path(input_dir, "output.sorted.txt")
    ec_file <- file.path(input_dir, "matrix.ec")
    
    # Verify input files exist
    if (!dir.exists(input_dir)) {
      stop(paste("Error: Input directory does not exist:", input_dir))
    }
    if (!file.exists(bus_file)) {
      stop(paste("Error: Sorted BUS file does not exist:", bus_file))
    }
    if (!file.exists(ec_file)) {
      stop(paste("Error: Equivalence class file does not exist:", ec_file))
    }
    
    # Create output directory if it doesn't exist
    output_dir <- "./output_results"
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }
    
    # Stage 1: Generate transcript-to-gene mapping using transcript2gene
    message("Generating transcript-to-gene mapping...")
    tr2g <- transcript2gene(species = c("Homo sapiens", "Mus musculus"), 
                            kallisto_out_path = "./out_hgmm100", ensembl_version = 99,
                            write_tr2g = FALSE)
    
    # Save the tr2g mapping
    write.csv(tr2g, file = file.path(output_dir, "tr2g_mapping.csv"), row.names = FALSE)
    message("Saved transcript-to-gene mapping to output_results/tr2g_mapping.csv")
    
    # Stage 2: Convert sorted BUS file to sparse gene count and TCC matrices using make_sparse_matrix
    message("Converting BUS file to sparse matrices...")
    c(gene_count, tcc) %<-% make_sparse_matrix("./out_hgmm100/output.sorted.txt",
                                   tr2g = tr2g, est_ncells = 1e5,
                                   est_ngenes = nrow(tr2g))
    
    # Save raw matrices
    saveRDS(gene_count, file = file.path(output_dir, "gene_count_raw.rds"))
    saveRDS(tcc, file = file.path(output_dir, "tcc_raw.rds"))
    
    # Stage 3-7 for Gene Count Matrix: Filter empty droplets using knee plot
    message("Processing gene count matrix...")
    tot_counts_gene <- Matrix::colSums(gene_count)
    df1 <- get_knee_df(gene_count)
    infl1 <- get_inflection(df1)
    
    # Plot and save knee plot for gene count
    p1 <- knee_plot(df1, infl1)
    ggsave(filename = file.path(output_dir, "knee_plot_gene_count.pdf"), plot = p1, width = 6, height = 5)
    
    # Filter gene count matrix
    gene_count_filtered <- gene_count[, tot_counts_gene > infl1]
    saveRDS(gene_count_filtered, file = file.path(output_dir, "gene_count_filtered.rds"))
    message(paste("Filtered gene count matrix saved. Original dimensions:", 
                  paste(dim(gene_count), collapse="x"), 
                  "| Filtered dimensions:", 
                  paste(dim(gene_count_filtered), collapse="x")))
    
    # Stage 3-7 for TCC Matrix: Filter empty droplets using knee plot
    message("Processing TCC matrix...")
    tot_counts_tcc <- Matrix::colSums(tcc)
    df2 <- get_knee_df(tcc)
    infl2 <- get_inflection(df2)
    
    # Plot and save knee plot for TCC
    p2 <- knee_plot(df2, infl2)
    ggsave(filename = file.path(output_dir, "knee_plot_tcc.pdf"), plot = p2, width = 6, height = 5)
    
    # Filter TCC matrix
    tcc_filtered <- tcc[, tot_counts_tcc > infl2]
    saveRDS(tcc_filtered, file = file.path(output_dir, "tcc_filtered.rds"))
    message(paste("Filtered TCC matrix saved. Original dimensions:", 
                  paste(dim(tcc), collapse="x"), 
                  "| Filtered dimensions:", 
                  paste(dim(tcc_filtered), collapse="x")))
    
    message("Pipeline completed successfully. All outputs are saved in './output_results'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_BUSPARSE_BUS_TO_SPARSE_MATRIX_AND_FILTERING":
        busparse: \$(Rscript -e 'cat(as.character(packageVersion("busparse")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bus_to_sparse_matrix_and_filtering.csv versions.yml
    """
}

workflow BIOC_BUSPARSE_BUS_TO_SPARSE_MATRIX_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ./out_hgmm100/output.sorted.txt, ./out_hgmm100/matrix.ec ] ]

    main:
    BIOC_BUSPARSE_BUS_TO_SPARSE_MATRIX_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_BUSPARSE_BUS_TO_SPARSE_MATRIX_AND_FILTERING.out.tables
    plots    = BIOC_BUSPARSE_BUS_TO_SPARSE_MATRIX_AND_FILTERING.out.plots
    objects  = BIOC_BUSPARSE_BUS_TO_SPARSE_MATRIX_AND_FILTERING.out.objects
    versions = BIOC_BUSPARSE_BUS_TO_SPARSE_MATRIX_AND_FILTERING.out.versions
}
