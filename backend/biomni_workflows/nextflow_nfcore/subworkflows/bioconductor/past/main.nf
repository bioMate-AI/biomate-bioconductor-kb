#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: past — gwas_pathway_enrichment
// Run a complete GWAS-based metabolic pathway enrichment analysis from raw TASSEL outputs and GFF annotations to pathway significance plotting.
// Input: association.txt.xz, effects.txt.xz, LD.txt.xz, genes.gff, pathways.txt.xz
// Container: quay.io/biocontainers/bioconductor-past:1.26.0--r45hdfd78af_0
// R packages: PAST
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAST_GWAS_PATHWAY_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-past:1.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("PAST")
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
    
    # Load required library
    library(PAST)
    
    # Define input files in the working directory
    association_file <- "association.txt.xz"
    effects_file <- "effects.txt.xz"
    LD_file <- "LD.txt.xz"
    genes_file <- "genes.gff"
    pathways_file <- "pathways.txt.xz"
    
    # Verify input files exist
    input_files <- c(association_file, effects_file, LD_file, genes_file, pathways_file)
    missing_files <- input_files[!file.exists(input_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # 1. Load GWAS association and effects data
    message("Loading GWAS data...")
    gwas_data <- load_GWAS_data(association_file, 
                                effects_file)
    
    # 2. Load Linkage Disequilibrium (LD) data
    message("Loading LD data...")
    LD <- load_LD(LD_file)
    
    # 3. Assign SNPs to genes based on LD blocks and physical distance
    message("Assigning SNPs to genes...")
    genes <- assign_SNPs_to_genes(gwas_data, 
                                 LD, 
                                 genes_file,
                                 c("gene"),
                                 1000, 
                                 0.8, 
                                 2)
    
    # Save assigned genes data
    saveRDS(genes, "assigned_genes.rds")
    tryCatch({
      write.csv(as.data.frame(genes), "assigned_genes.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not write genes to CSV, saved as RDS.")
    })
    
    # 4. Calculate pathway enrichment scores and significance
    message("Calculating pathway significance...")
    rugplots_data <- find_pathway_significance(genes, 
                                               pathways_file, 
                                               5,
                                               "increasing", 
                                               1000, 
                                               2)
    
    # Save pathway significance data
    saveRDS(rugplots_data, "pathway_significance.rds")
    tryCatch({
      write.csv(as.data.frame(rugplots_data), "pathway_significance.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not write pathway significance to CSV, saved as RDS.")
    })
    
    # 5. Plot enrichment rugplots for significant pathways
    message("Plotting pathways...")
    output_plot_dir <- "pathway_plots"
    if (!dir.exists(output_plot_dir)) {
      dir.create(output_plot_dir, recursive = TRUE)
    }
    
    plot_pathways(rugplots_data, 
                  "pvalue", 
                  0.02, 
                  "increasing", 
                  output_plot_dir)
    
    message("Pipeline completed successfully. Outputs saved to 'assigned_genes.rds', 'pathway_significance.rds', and the 'pathway_plots' directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PAST_GWAS_PATHWAY_ENRICHMENT":
        past: \$(Rscript -e 'cat(as.character(packageVersion("past")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwas_pathway_enrichment.csv versions.yml
    """
}

workflow BIOC_PAST_GWAS_PATHWAY_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ association.txt.xz, effects.txt.xz, LD.txt.xz, genes.gff, pathways.txt.xz ] ]

    main:
    BIOC_PAST_GWAS_PATHWAY_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_PAST_GWAS_PATHWAY_ENRICHMENT.out.tables
    plots    = BIOC_PAST_GWAS_PATHWAY_ENRICHMENT.out.plots
    objects  = BIOC_PAST_GWAS_PATHWAY_ENRICHMENT.out.objects
    versions = BIOC_PAST_GWAS_PATHWAY_ENRICHMENT.out.versions
}
