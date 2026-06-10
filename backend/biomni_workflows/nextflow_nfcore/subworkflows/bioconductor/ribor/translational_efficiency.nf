#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribor — translational_efficiency
// Integrate ribosome profiling region counts with paired RNA-Seq data to calculate and analyze translational efficiency.
// Input: HEK293_ingolia.ribo
// Container: quay.io/biocontainers/bioconductor-ribor:1.22.0--r45hdfd78af_0
// Requires: ribor
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract RNA-Seq CDS counts. 2. Extract Ribosome Profiling CDS region counts. 3. Filter out lowly expressed transcripts. 4. Calcula

nextflow.enable.dsl = 2

process BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ribor")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(ribor)
    
    # Define the input file path (must be in the working directory)
    input_file <- "HEK293_ingolia.ribo"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # Define the default renaming function as described in the ribor documentation
    rename_default <- function(names) {
      return(unlist(strsplit(names, split = "[|]"))[5])
    }
    
    # Initialize the Ribo object from the user-provided file
    original.ribo <- Ribo(input_file, rename = rename_default)
    
    # 1. Extract RNA-Seq CDS counts
    rnaseq_CDS <- get_rnaseq(ribo.object = original.ribo,
                             tidy        = TRUE,
                             alias       = TRUE,
                             region      = "CDS",
                             compact     = FALSE,
                             experiment  = "GSM1606108")
    
    # 2. Extract Ribosome Profiling CDS region counts
    rc_CDS <- get_region_counts(ribo.object    = original.ribo,
                                    tidy       = TRUE,
                                    alias      = TRUE,
                                    transcript = FALSE,
                                    region     = "CDS",
                                    compact    = FALSE,
                                    experiment = "GSM1606108")
    
    # Create directory for plots if it doesn't exist
    output_dir <- "output"
    if (!dir.exists(output_dir)) {
      dir.create(output_dir)
    }
    
    # Generate diagnostic plots before filtering
    pdf(file.path(output_dir, "translational_efficiency_plots.pdf"), width = 10, height = 8)
    par(mfrow = c(2, 2))
    
    # Plot 1: RNA-Seq Density
    plot(density(log2(rnaseq_CDS\$count + 1)), 
         xlab = "Log 2 of RNA-Seq Count (+1)", 
         main = "RNA-Seq Density (Pre-filtering)")
    
    # 3. Filter out lowly expressed transcripts
    filtered_transcripts <- which(rnaseq_CDS\$count > 2 & rc_CDS\$count > 2)
    rnaseq_CDS           <- rnaseq_CDS[filtered_transcripts, ]
    rc_CDS               <- rc_CDS[filtered_transcripts, ]
    
    # Plot 2: Scatter plot of Ribosome Profiling vs RNA-Seq
    plot(log2(rnaseq_CDS\$count), 
         log2(rc_CDS\$count), 
         xlab = "RNA-Seq (log2)", 
         ylab = "Ribosome Profiling (log2)", 
         main = "log2 CDS Read Counts (Filtered)", 
         pch = 19, 
         cex = 0.5,
         col = "darkblue")
    
    # 4. Calculate translational efficiency as the ratio of ribosome profiling to RNA-Seq counts
    te_CDS    <- rc_CDS\$count/rnaseq_CDS\$count
    
    # Plot 3: Density of Translational Efficiency
    plot(density(log2(te_CDS)), 
         xlab = "Log 2 of Translation Efficiency", 
         main = "Translational Efficiency Density",
         col = "red")
    abline(v = log2(0.25), col = "blue", lty = 2) # Threshold line at 0.25
    
    # Identify transcripts with high translational efficiency (> 0.25)
    high_te <- rc_CDS\$transcript[which(te_CDS > .25)]
    
    dev.off()
    
    # Prepare final data frame for export
    results_df <- data.frame(
      transcript = rc_CDS\$transcript,
      ribo_count = rc_CDS\$count,
      rnaseq_count = rnaseq_CDS\$count,
      translational_efficiency = te_CDS,
      high_te_status = te_CDS > 0.25
    )
    
    # Write outputs to files
    write.csv(results_df, file = file.path(output_dir, "cds_translational_efficiency_results.csv"), row.names = FALSE)
    
    high_te_df <- data.frame(transcript = high_te)
    write.csv(high_te_df, file = file.path(output_dir, "high_translational_efficiency_transcripts.csv"), row.names = FALSE)
    
    saveRDS(results_df, file = file.path(output_dir, "translational_efficiency_results.rds"))
    
    cat("Pipeline completed successfully.\n")
    cat("Outputs saved to the 'output' directory:\n")
    cat(" - translational_efficiency_plots.pdf\n")
    cat(" - cds_translational_efficiency_results.csv\n")
    cat(" - high_translational_efficiency_transcripts.csv\n")
    cat(" - translational_efficiency_results.rds\n")

    writeLines(c(
        '"BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY":',
        paste0('    ribor: ', as.character(packageVersion('ribor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_translational_efficiency.csv versions.yml
    """
}

workflow BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HEK293_ingolia.ribo ] ]

    main:
    BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY(ch_input)

    emit:
    tables   = BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY.out.tables
    plots    = BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY.out.plots
    objects  = BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY.out.objects
    versions = BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY.out.versions
}
