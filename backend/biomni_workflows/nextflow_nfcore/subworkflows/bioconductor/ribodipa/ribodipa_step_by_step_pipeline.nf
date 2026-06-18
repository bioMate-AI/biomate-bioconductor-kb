#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribodipa — ribodipa_step_by_step_pipeline
// Run the RiboDiPA pipeline step-by-step to allow customization of P-site mapping and data binning parameters.
// Input: bam_path[1:4], bam_path[5]
// Container: quay.io/biocontainers/bioconductor-ribodipa:1.18.0--r45ha27e39d_0
// R packages: RiboDiPA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_RIBODIPA_RIBODIPA_STEP_BY_STEP_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribodipa:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("RiboDiPA")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(RiboDiPA)
    
    # -----------------------------------------------------------------------------
    # 1. Input File Verification and Setup
    # -----------------------------------------------------------------------------
    # The pipeline expects exactly 4 BAM files and 1 GTF file in the working directory.
    bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    gtf_files <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)
    
    if (length(bam_files) < 4) {
      stop("Error: At least 4 BAM files (.bam) are required in the working directory.")
    }
    if (length(gtf_files) < 1) {
      stop("Error: A reference genome GTF file (.gtf) is required in the working directory.")
    }
    
    # Construct the bam_path vector as specified:
    # bam_path[1:4] are the BAM files, bam_path[5] is the GTF file.
    bam_path <- c(bam_files[1:4], gtf_files[1])
    
    message("Using BAM files:")
    print(bam_path[1:4])
    message("Using GTF file:")
    print(bam_path[5])
    
    # Define the experimental design (class label)
    # 1 represents the reference condition (wildtype), 2 represents the treatment (mutant)
    classlabel <- data.frame(
        condition = c("mutant", "mutant", "wildtype", "wildtype"),
        comparison = c(2, 2, 1, 1)
    )
    rownames(classlabel) <- c("mutant1", "mutant2", "wildtype1", "wildtype2")
    
    # -----------------------------------------------------------------------------
    # 2. Step-by-Step RiboDiPA Pipeline
    # -----------------------------------------------------------------------------
    
    # --- Map RPFs to P-sites and generate total transcript ---
    message("Step 1: Performing P-site mapping...")
    data.psite <- psiteMapping(bam_file_list = bam_path[1:4], 
        gtf_file = bam_path[5], psite.mapping = "auto", cores = 2)
    
    # Display the automatically generated P-site mapping offset rules
    message("P-site mapping offsets generated:")
    print(data.psite\$psite.mapping)
    
    # --- Group P-site counts into bins using adaptive binning ---
    message("Step 2: Performing data binning...")
    data.binned <- dataBinning(data = data.psite\$coverage, bin.width = 0,
        zero.omit = FALSE, bin.from.5UTR = TRUE, cores = 2)
    
    # --- Perform bin-wise and gene-wise differential pattern ---
    message("Step 3: Performing differential pattern testing...")
    result.pst <- diffPatternTest(data = data.binned,
        classlabel = classlabel, method=c('gtxr', 'qvalue'))
    
    # -----------------------------------------------------------------------------
    # 3. Save Results and Generate Plots
    # -----------------------------------------------------------------------------
    message("Saving results...")
    
    # Save the main results as CSV tables
    write.csv(result.pst\$gene, "ribodipa_gene_results.csv", row.names = TRUE)
    write.csv(result.pst\$bin, "ribodipa_bin_results.csv", row.names = TRUE)
    
    # Save the complete results object as an RDS file
    saveRDS(result.pst, "ribodipa_results.rds")
    saveRDS(data.psite, "ribodipa_data_psite.rds")
    
    # Generate visualization plots
    pdf("ribodipa_plots.pdf", width = 10, height = 8)
    
    # Plot ribosome per nucleotide tracks for the top 2 genes with coverage
    available_genes <- names(data.psite\$coverage)
    if (length(available_genes) > 0) {
        genes_to_plot <- head(available_genes, 2)
        message("Plotting tracks for genes: ", paste(genes_to_plot, collapse = ", "))
        tryCatch({
            plotTrack(data = data.psite, genes.list = genes_to_plot,
                      replicates = NULL, exons = FALSE)
        }, error = function(e) {
            warning("Could not generate track plot: ", e\$message)
        })
    }
    
    # Plot binned ribosome tracks of significant genes (threshold q-value <= 0.05)
    message("Plotting binned tracks for significant genes...")
    tryCatch({
        plotTest(result = result.pst, genes.list = NULL, threshold = 0.05)
    }, error = function(e) {
        warning("Could not generate test plot (possibly no genes passed the threshold): ", e\$message)
    })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_RIBODIPA_RIBODIPA_STEP_BY_STEP_PIPELINE":',
        paste0('        ribodipa: ', as.character(packageVersion("ribodipa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ribodipa_step_by_step_pipeline.csv versions.yml
    """
}

workflow BIOC_RIBODIPA_RIBODIPA_STEP_BY_STEP_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_path[1:4], bam_path[5] ] ]

    main:
    BIOC_RIBODIPA_RIBODIPA_STEP_BY_STEP_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RIBODIPA_RIBODIPA_STEP_BY_STEP_PIPELINE.out.tables
    plots    = BIOC_RIBODIPA_RIBODIPA_STEP_BY_STEP_PIPELINE.out.plots
    objects  = BIOC_RIBODIPA_RIBODIPA_STEP_BY_STEP_PIPELINE.out.objects
    versions = BIOC_RIBODIPA_RIBODIPA_STEP_BY_STEP_PIPELINE.out.versions
}
