#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phyloseq — data_import_and_assembly
// Import raw microbiome data components from various formats and assemble them into a single unified phyloseq object.
// Input: file.biom, file.tre, map.txt
// Container: quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0
// R packages: genefilter, ggplot2, phyloseq, reshape2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHYLOSEQ_DATA_IMPORT_AND_ASSEMBLY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0"

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
    .bm_deps <- c("genefilter", "ggplot2", "phyloseq", "reshape2")
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
    library(phyloseq)
    
    # Define input file paths as specified by the user
    BIOMfilename <- "file.biom"
    my_tree_file <- "file.tre"
    map.txt <- "map.txt"
    
    # ==========================================
    # Stage 1 & 2: Import BIOM, Tree, and Sample Data
    # ==========================================
    
    # Import BIOM file (contains OTU and taxonomy data)
    x <- import_biom(BIOMfilename)
    
    # Import sample metadata
    y <- import_qiime_sample_data(map.txt)
    
    # ==========================================
    # Stage 3: Merge components using merge_phyloseq
    # ==========================================
    
    # Merge the imported BIOM and sample data components
    merged_obj <- merge_phyloseq(x, y)
    
    # ==========================================
    # Stage 4: Alternative manual construction
    # ==========================================
    
    # Extract raw matrices/data frames from the imported objects to avoid data fabrication
    raw_abundance_matrix <- as(otu_table(x), "matrix")
    
    # Adjust orientation to match the documented parameter taxa_are_rows=FALSE
    if (taxa_are_rows(x)) {
      raw_abundance_matrix <- t(raw_abundance_matrix)
    }
    
    raw_sample_data.frame <- as(sample_data(y), "data.frame")
    raw_taxonomy_matrix <- as(tax_table(x), "matrix")
    
    # Construct components manually using documented functions
    otu1 <- otu_table(raw_abundance_matrix, taxa_are_rows=FALSE)
    sam1 <- sample_data(raw_sample_data.frame)
    tax1 <- tax_table(raw_taxonomy_matrix)
    tre1 <- read_tree(my_tree_file)
    
    # Assign to the documented variable names
    my_otu_table <- otu1
    my_sample_data <- sam1
    my_taxonomyTable <- tax1
    my_tree <- tre1
    
    # Combine components into phyloseq objects using documented signatures
    ex1b <- phyloseq(my_otu_table, my_sample_data, my_taxonomyTable, my_tree)
    ex1c <- phyloseq(my_otu_table, my_sample_data)
    
    # ==========================================
    # Save Outputs
    # ==========================================
    
    # Save the constructed phyloseq objects as RDS files
    saveRDS(merged_obj, "merged_phyloseq.rds")
    saveRDS(ex1b, "assembled_phyloseq_with_tree.rds")
    saveRDS(ex1c, "assembled_phyloseq_basic.rds")
    
    # Write a text summary of the assembled objects
    sink("pipeline_summary.txt")
    cat("=== Merged Phyloseq Object ===\n")
    print(merged_obj)
    cat("\n=== Assembled Phyloseq Object (with Tree) ===\n")
    print(ex1b)
    cat("\n=== Assembled Phyloseq Object (Basic) ===\n")
    print(ex1c)
    sink()
    
    # Generate a diagnostic tree plot if possible
    tryCatch({
      pdf("phyloseq_tree_plot.pdf", width = 10, height = 8)
      plot_tree(ex1b)
      dev.off()
    }, error = function(e) {
      warning("Could not generate tree plot: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PHYLOSEQ_DATA_IMPORT_AND_ASSEMBLY":
        phyloseq: \$(Rscript -e 'cat(as.character(packageVersion("phyloseq")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_data_import_and_assembly.csv versions.yml
    """
}

workflow BIOC_PHYLOSEQ_DATA_IMPORT_AND_ASSEMBLY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.biom, file.tre, map.txt ] ]

    main:
    BIOC_PHYLOSEQ_DATA_IMPORT_AND_ASSEMBLY(ch_input)

    emit:
    tables   = BIOC_PHYLOSEQ_DATA_IMPORT_AND_ASSEMBLY.out.tables
    plots    = BIOC_PHYLOSEQ_DATA_IMPORT_AND_ASSEMBLY.out.plots
    objects  = BIOC_PHYLOSEQ_DATA_IMPORT_AND_ASSEMBLY.out.objects
    versions = BIOC_PHYLOSEQ_DATA_IMPORT_AND_ASSEMBLY.out.versions
}
