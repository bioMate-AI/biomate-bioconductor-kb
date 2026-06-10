#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isobayes — isobayes_isoform_inference
// Perform protein isoform presence and abundance inference, optionally integrating transcript TPMs, starting from MetaMorpheus, OpenMS/Percolator, or custom user-
// Input: AllPeptides.psmtsv, AllQuantifiedPeptides.tsv, file.idXML, custom_peptides.tsv, jurkat_isoform_kallisto.tsv, map_iso_gene.csv
// Container: quay.io/biocontainers/bioconductor-isobayes:1.8.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOBAYES_ISOBAYES_ISOFORM_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-isobayes:1.8.0--r45ha27e39d_0"

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
    .bm_deps <- c("isobayes")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required package
    library(IsoBayes)
    
    # -----------------------------------------------------------------------------
    # 1. Check and resolve input file paths from the working directory
    # -----------------------------------------------------------------------------
    
    tpm_path <- if (file.exists("jurkat_isoform_kallisto.tsv")) {
      "jurkat_isoform_kallisto.tsv"
    } else {
      NULL
    }
    
    path_to_map_iso_gene <- if (file.exists("map_iso_gene.csv")) {
      "map_iso_gene.csv"
    } else {
      NULL
    }
    
    # Determine which peptide input files are available and construct the SummarizedExperiment (SE)
    if (file.exists("AllPeptides.psmtsv")) {
      path_to_peptides_psm <- "AllPeptides.psmtsv"
      
      if (file.exists("AllQuantifiedPeptides.tsv")) {
        path_to_peptides_intensities <- "AllQuantifiedPeptides.tsv"
        message("Found MetaMorpheus PSM and Intensity files. Generating SE with intensities...")
        SE = generate_SE(path_to_peptides_psm = path_to_peptides_psm,
                         path_to_peptides_intensities = path_to_peptides_intensities,
                         abundance_type = "intensities",
                         input_type = "metamorpheus")
      } else {
        message("Found MetaMorpheus PSM file. Generating SE with PSM counts...")
        SE = generate_SE(path_to_peptides_psm = path_to_peptides_psm,
                         abundance_type = "psm",
                         input_type = "metamorpheus")
      }
    } else if (file.exists("file.idXML")) {
      message("Found OpenMS Percolator file. Generating SE...")
      SE = generate_SE(path_to_peptides_psm = "file.idXML",
                       abundance_type = "psm",
                       input_type = "openMS")
    } else if (file.exists("custom_peptides.tsv")) {
      message("Found custom peptide file. Generating SE...")
      SE = generate_SE(path_to_peptides_psm = "custom_peptides.tsv",
                       abundance_type = "psm",
                       input_type = "other")
    } else {
      stop("Error: No valid peptide input files found in the working directory.\n",
           "Expected at least one of: AllPeptides.psmtsv, file.idXML, custom_peptides.tsv")
    }
    
    # Print SummarizedExperiment details
    print(SE)
    
    # -----------------------------------------------------------------------------
    # 2. Preprocess the SummarizedExperiment and integrate transcript TPMs
    # -----------------------------------------------------------------------------
    message("Preprocessing input data...")
    data_loaded = input_data(SE, path_to_tpm = tpm_path)
    
    # -----------------------------------------------------------------------------
    # 3. Run the Bayesian inference model
    # -----------------------------------------------------------------------------
    message("Running Bayesian inference...")
    set.seed(169612)
    results_normalized = inference(data_loaded, map_iso_gene = path_to_map_iso_gene, traceplot = TRUE)
    
    # Display structure of results
    print(names(results_normalized))
    
    if (!is.null(results_normalized\$isoform_results)) {
      message("Isoform results preview:")
      print(head(results_normalized\$isoform_results))
      write.csv(results_normalized\$isoform_results, "isoform_results.csv", row.names = FALSE)
    }
    
    if (!is.null(results_normalized\$normalized_isoform_results)) {
      message("Normalized isoform results preview:")
      print(head(results_normalized\$normalized_isoform_results))
      write.csv(results_normalized\$normalized_isoform_results, "normalized_isoform_results.csv", row.names = FALSE)
    }
    
    if (!is.null(results_normalized\$gene_abundance)) {
      message("Gene abundance results preview:")
      print(head(results_normalized\$gene_abundance))
      write.csv(results_normalized\$gene_abundance, "gene_abundance.csv", row.names = FALSE)
    }
    
    # Save the complete results object
    saveRDS(results_normalized, "results_normalized.rds")
    
    # -----------------------------------------------------------------------------
    # 4. Visualize relative abundances and assess MCMC convergence
    # -----------------------------------------------------------------------------
    message("Generating plots...")
    
    # Documented plotting calls (wrapped in tryCatch to handle cases where 'TUBB' is absent)
    tryCatch({
      pdf("plot_relative_abundances_TUBB.pdf")
      plot_relative_abundances(results_normalized, gene_id = "TUBB")
      dev.off()
    }, error = function(e) {
      warning("Could not plot relative abundances for TUBB: ", e\$message)
    })
    
    tryCatch({
      pdf("plot_relative_abundances_TUBB_no_norm.pdf")
      plot_relative_abundances(results_normalized, gene_id = "TUBB", normalize_gene = FALSE)
      dev.off()
    }, error = function(e) {
      warning("Could not plot relative abundances (no norm) for TUBB: ", e\$message)
    })
    
    tryCatch({
      pdf("plot_traceplot_TUBB_205.pdf")
      plot_traceplot(results_normalized, "TUBB-205")
      dev.off()
    }, error = function(e) {
      warning("Could not plot traceplot for TUBB-205: ", e\$message)
    })
    
    tryCatch({
      pdf("plot_traceplot_TUBB_206.pdf")
      plot_traceplot(results_normalized, "TUBB-206")
      dev.off()
    }, error = function(e) {
      warning("Could not plot traceplot for TUBB-206: ", e\$message)
    })
    
    tryCatch({
      pdf("plot_traceplot_TUBB_208.pdf")
      plot_traceplot(results_normalized, "TUBB-208")
      dev.off()
    }, error = function(e) {
      warning("Could not plot traceplot for TUBB-208: ", e\$message)
    })
    
    # Dynamic plotting for the first available gene/isoform in the dataset (if TUBB is not present)
    if (!is.null(results_normalized\$normalized_isoform_results) && nrow(results_normalized\$normalized_isoform_results) > 0) {
      available_genes <- unique(results_normalized\$normalized_isoform_results\$Gene)
      if (length(available_genes) > 0) {
        sample_gene <- available_genes[1]
        if (sample_gene != "TUBB") {
          message("Plotting relative abundances for available gene: ", sample_gene)
          tryCatch({
            pdf(paste0("plot_relative_abundances_", sample_gene, ".pdf"))
            plot_relative_abundances(results_normalized, gene_id = sample_gene)
            dev.off()
          }, error = function(e) {
            warning("Failed to plot relative abundances for ", sample_gene, ": ", e\$message)
          })
          
          sample_isoforms <- results_normalized\$normalized_isoform_results\$Isoform[results_normalized\$normalized_isoform_results\$Gene == sample_gene]
          if (length(sample_isoforms) > 0) {
            sample_iso <- sample_isoforms[1]
            message("Plotting traceplot for available isoform: ", sample_iso)
            tryCatch({
              pdf(paste0("plot_traceplot_", sample_iso, ".pdf"))
              plot_traceplot(results_normalized, sample_iso)
              dev.off()
            }, error = function(e) {
              warning("Failed to plot traceplot for ", sample_iso, ": ", e\$message)
            })
          }
        }
      }
    }
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ISOBAYES_ISOBAYES_ISOFORM_INFERENCE":
        isobayes: \$(Rscript -e 'cat(as.character(packageVersion("isobayes")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isobayes_isoform_inference.csv versions.yml
    """
}

workflow BIOC_ISOBAYES_ISOBAYES_ISOFORM_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ AllPeptides.psmtsv, AllQuantifiedPeptides.tsv, file.idXML, custom_peptides.tsv, jurkat_isoform_kallisto.tsv, map_iso_gene.csv ] ]

    main:
    BIOC_ISOBAYES_ISOBAYES_ISOFORM_INFERENCE(ch_input)

    emit:
    tables   = BIOC_ISOBAYES_ISOBAYES_ISOFORM_INFERENCE.out.tables
    plots    = BIOC_ISOBAYES_ISOBAYES_ISOFORM_INFERENCE.out.plots
    objects  = BIOC_ISOBAYES_ISOBAYES_ISOFORM_INFERENCE.out.objects
    versions = BIOC_ISOBAYES_ISOBAYES_ISOFORM_INFERENCE.out.versions
}
