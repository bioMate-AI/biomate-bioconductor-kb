#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epidecoder — epigenetic_deg_integration
// Integrate genomic coordinates of epigenetic/epitranscriptomic modification events with differential gene expression data to analyze and plot the impact of modif
// Input: NOMO-1_ref_peaks.bed, FTOi.txt
// Container: quay.io/biocontainers/bioconductor-epidecoder:1.18.0--r45hdfd78af_0
// R packages: epidecodeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIDECODER_EPIGENETIC_DEG_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-epidecoder:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("epidecodeR")
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
    
    # 1. Load the epidecodeR package
    library(epidecodeR)
    
    # Define input file paths (must exist in the working directory)
    events_file <- "NOMO-1_ref_peaks.bed"
    deg_file <- "FTOi.txt"
    
    # Check if input files exist
    if (!file.exists(events_file)) {
      stop(paste("Required input file missing:", events_file))
    }
    if (!file.exists(deg_file)) {
      stop(paste("Required input file missing:", deg_file))
    }
    
    # 2. Define paths to the events BED file and the differential gene expression (DEG) file
    events <- events_file
    deg <- deg_file
    
    # 3. Run the epidecodeR function to map events to genes, group genes by modification degree, and perform statistical testing
    epiobj <- epidecodeR(events = events, deg = deg, pval = 0.05, param = 3, ints = c(2, 4))
    
    # Save the S4 object for reproducibility
    saveRDS(epiobj, file = "epiobj.rds")
    
    # 4. Generate cumulative distribution function (CDF) plots using makeplot
    pdf("cdf_plot.pdf", width = 7, height = 7)
    makeplot(epiobj, lim = c(-10, 10), title = "m6A mediated dysregulation after FTO inhibitor treatment", xlab = "log2FC")
    dev.off()
    
    # 5. Generate boxplots of log2FC distribution across groups using plot_test
    pdf("boxplot_test.pdf", width = 7, height = 7)
    plot_test(epiobj, title = "m6A mediated dysregulation after FTO inhibitor treatment", ylab = "log2FC")
    dev.off()
    
    # 6. Retrieve theoretical and empirical cumulative tables, group counts, and gene lists using helper functions
    theoretical_table <- get_theoretical_table(epiobj)
    empirical_table <- get_empirical_table(epiobj)
    grpcounts <- get_grpcounts(epiobj)
    grptables_list <- get_grptables(epiobj)
    
    # Print heads to stdout as in the documented code
    print("Head of theoretical table:")
    print(head(theoretical_table))
    
    print("Head of empirical table:")
    print(head(empirical_table))
    
    print("Group counts:")
    print(grpcounts)
    
    print("Head of group '0' table:")
    print(head(grptables_list\$'0'))
    
    print("Head of group '1' table:")
    print(head(grptables_list\$'1'))
    
    print("Head of group '2to4' table:")
    print(head(grptables_list\$'2to4'))
    
    print("Head of group '5+' table:")
    print(head(grptables_list\$'5+'))
    
    # Write results to output CSV files
    write.csv(theoretical_table, "theoretical_table.csv", row.names = FALSE)
    write.csv(empirical_table, "empirical_table.csv", row.names = FALSE)
    
    # Convert group counts to a data frame for clean CSV writing
    grpcounts_df <- data.frame(Group = names(grpcounts), Count = as.vector(grpcounts))
    write.csv(grpcounts_df, "group_counts.csv", row.names = FALSE)
    
    # Write individual group tables
    if (!is.null(grptables_list\$'0')) {
      write.csv(grptables_list\$'0', "grptable_group_0.csv", row.names = TRUE)
    }
    if (!is.null(grptables_list\$'1')) {
      write.csv(grptables_list\$'1', "grptable_group_1.csv", row.names = TRUE)
    }
    if (!is.null(grptables_list\$'2to4')) {
      write.csv(grptables_list\$'2to4', "grptable_group_2to4.csv", row.names = TRUE)
    }
    if (!is.null(grptables_list\$'5+')) {
      write.csv(grptables_list\$'5+', "grptable_group_5plus.csv", row.names = TRUE)
    }
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EPIDECODER_EPIGENETIC_DEG_INTEGRATION":
        epidecoder: \$(Rscript -e 'cat(as.character(packageVersion("epidecoder")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epigenetic_deg_integration.csv versions.yml
    """
}

workflow BIOC_EPIDECODER_EPIGENETIC_DEG_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ NOMO-1_ref_peaks.bed, FTOi.txt ] ]

    main:
    BIOC_EPIDECODER_EPIGENETIC_DEG_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_EPIDECODER_EPIGENETIC_DEG_INTEGRATION.out.tables
    plots    = BIOC_EPIDECODER_EPIGENETIC_DEG_INTEGRATION.out.plots
    objects  = BIOC_EPIDECODER_EPIGENETIC_DEG_INTEGRATION.out.objects
    versions = BIOC_EPIDECODER_EPIGENETIC_DEG_INTEGRATION.out.versions
}
