#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: celaref — scrnaseq_to_microarray_comparison
// Compare a query single-cell RNA-seq dataset to a purified cell-type microarray reference dataset to annotate query clusters.
// Input: 10X_pbmc4k, watkins_expression.txt, watkins_samples.txt
// Container: quay.io/biocontainers/bioconductor-celaref:1.28.0--r45hdfd78af_0
// R packages: celaref, dplyr, ggplot2, illuminaHumanv2.db, readr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: violin plot

nextflow.enable.dsl = 2

process BIOC_CELAREF_SCRNASEQ_TO_MICROARRAY_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-celaref:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("celaref", "dplyr", "ggplot2", "illuminaHumanv2.db", "readr")
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
    library(celaref)
    library(readr)
    library(dplyr)
    library(illuminaHumanv2.db)
    library(ggplot2)
    
    # --- Load and filter query 10X scRNA-seq dataset ---
    dataset_se.10X_pbmc4k_k7 <- load_dataset_10Xdata(
       dataset_path   = '10X_pbmc4k',
       dataset_genome = "GRCh38",
       clustering_set = "kmeans_7_clusters",
       id_to_use      = "GeneSymbol")
    
    dataset_se.10X_pbmc4k_k7 <- trim_small_groups_and_low_expression_genes(dataset_se.10X_pbmc4k_k7)
    
    # --- Run within-experiment differential expression for the ---
    de_table.10X_pbmc4k_k7   <- contrast_each_group_to_the_rest(dataset_se.10X_pbmc4k_k7, dataset_name="10X_pbmc4k_k7", num_cores=7)
    
    # --- Prepare microarray reference dataset and run ---
    norm_expression_file <- "watkins_expression.txt"
    samples_file <- "watkins_samples.txt"
    
    norm_expression_table.full <- read.table(norm_expression_file, sep="\t", header=TRUE, quote="", comment.char="", row.names=1, check.names=FALSE)
    samples_table <- read_tsv(samples_file, col_types = cols())
    
    # Avoid group or extra_factor names starting with numbers, for microarrays
    samples_table\$description <- make.names(samples_table\$description)
    
    # Filter to only consider the peripheral blood samples
    samples_table <- samples_table[samples_table\$tissue == "Peripheral Blood",]
    
    # Map Illumina probes to gene symbols
    probes_with_gene_symbol_and_with_data <- intersect(keys(illuminaHumanv2SYMBOL), rownames(norm_expression_table.full))
    probe_to_symbol <- select(illuminaHumanv2.db, keys=rownames(norm_expression_table.full), columns=c("SYMBOL"), keytype="PROBEID")
    probe_to_symbol <- unique(probe_to_symbol[! is.na(probe_to_symbol\$SYMBOL),])
    
    genes_per_probe <- table(probe_to_symbol\$PROBEID)
    multimap_probes <- names(genes_per_probe)[genes_per_probe > 1]
    probe_to_symbol <- probe_to_symbol[!probe_to_symbol\$PROBEID %in% multimap_probes, ]
    
    convert_expression_table_ids <- function(expression_table, the_probes_table, old_id_name, new_id_name){
       the_probes_table <- the_probes_table[,c(old_id_name, new_id_name)]
       colnames(the_probes_table) <- c("old_id", "new_id")
       probe_expression_levels <- rowSums(expression_table)
       the_probes_table\$avgexpr <- probe_expression_levels[as.character(the_probes_table\$old_id)]
       the_genes_table <- the_probes_table %>% group_by(new_id) %>% top_n(1, avgexpr)
       expression_table <- expression_table[the_genes_table\$old_id,]
       rownames(expression_table) <- the_genes_table\$new_id
       return(expression_table)
    }
    
    norm_expression_table.genes <- convert_expression_table_ids(norm_expression_table.full, probe_to_symbol, old_id_name="PROBEID", new_id_name="SYMBOL")
    
    de_table.Watkins2009PBMCs <- contrast_each_group_to_the_rest_for_norm_ma_with_limma(
                     norm_expression_table = norm_expression_table.genes,
                     sample_sheet_table    = samples_table,
                     dataset_name          = "Watkins2009PBMCs",
                     extra_factor_name     = 'description',
                     sample_name           = "sampleId",
                     group_name            = 'celltype')
    
    # --- Compare query to microarray reference and generate plots ---
    pdf("ranking_violin_plots.pdf", width=12, height=8)
    
    p1 <- make_ranking_violin_plot(de_table.test=de_table.10X_pbmc4k_k7, de_table.ref=de_table.Watkins2009PBMCs)
    print(p1)
    
    p2 <- make_ranking_violin_plot(de_table.test=de_table.10X_pbmc4k_k7, de_table.ref=de_table.Watkins2009PBMCs, log10trans = TRUE)
    print(p2)
    
    dev.off()
    
    # --- Generate similarity labels ---
    label_table.pbmc4k_k7_vs_Watkins2009PBMCs <- make_ref_similarity_names(de_table.10X_pbmc4k_k7, de_table.Watkins2009PBMCs)
    
    # Save outputs
    write.csv(label_table.pbmc4k_k7_vs_Watkins2009PBMCs, "label_table_pbmc4k_k7_vs_Watkins2009PBMCs.csv", row.names=FALSE)
    saveRDS(de_table.10X_pbmc4k_k7, "de_table_10X_pbmc4k_k7.rds")
    saveRDS(de_table.Watkins2009PBMCs, "de_table_Watkins2009PBMCs.rds")

    writeLines(c(
        '"BIOC_CELAREF_SCRNASEQ_TO_MICROARRAY_COMPARISON":',
        paste0('        celaref: ', as.character(packageVersion("celaref")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrnaseq_to_microarray_comparison.csv versions.yml
    """
}

workflow BIOC_CELAREF_SCRNASEQ_TO_MICROARRAY_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 10X_pbmc4k, watkins_expression.txt, watkins_samples.txt ] ]

    main:
    BIOC_CELAREF_SCRNASEQ_TO_MICROARRAY_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CELAREF_SCRNASEQ_TO_MICROARRAY_COMPARISON.out.tables
    plots    = BIOC_CELAREF_SCRNASEQ_TO_MICROARRAY_COMPARISON.out.plots
    objects  = BIOC_CELAREF_SCRNASEQ_TO_MICROARRAY_COMPARISON.out.objects
    versions = BIOC_CELAREF_SCRNASEQ_TO_MICROARRAY_COMPARISON.out.versions
}
