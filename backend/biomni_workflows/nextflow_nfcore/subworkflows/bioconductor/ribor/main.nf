#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribor — ribo_qc_and_quantification
// Load a .ribo file, perform quality control checks (read length distribution and metagene analysis), and extract region-specific counts.
// Input: HEK293_ingolia.ribo
// Container: quay.io/biocontainers/bioconductor-ribor:1.22.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOR_RIBO_QC_AND_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribor:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("devtools", "ribor")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(ribor)
    
    # Define input file path
    file.path <- "HEK293_ingolia.ribo"
    
    # Check if the required input file exists in the working directory
    if (!file.exists(file.path)) {
      stop(paste("Required input file '", file.path, "' not found in the working directory.", sep = ""))
    }
    
    # 1. Initialize the Ribo object
    original.ribo <- Ribo(file.path, rename = rename_default)
    print(original.ribo)
    
    # Open PDF device to save all plots
    pdf("ribo_qc_plots.pdf", width = 8, height = 6)
    
    # 2. Plot and retrieve read length distribution
    plot_length_distribution(x           = original.ribo,
                             region      = "CDS",
                             range.lower = 28,
                             range.upper = 32,
                             fraction    = TRUE)
    
    plot_length_distribution(x           = original.ribo,
                             region      = "CDS",
                             range.lower = 28,
                             range.upper = 32,
                             fraction    = FALSE)
    
    rc <- get_length_distribution(ribo.object      = original.ribo,
                                  region      = "CDS",
                                  range.lower = 28,
                                  range.upper = 32)
    write.csv(as.data.frame(rc), "length_distribution.csv", row.names = FALSE)
    
    # 3. Perform metagene analysis around start/stop sites
    metagene_radius <- get_info(original.ribo)\$attributes\$metagene_radius
    message(paste("Metagene radius:", metagene_radius))
    
    plot_metagene(original.ribo,
                  site        = "start",
                  experiment  = c("GSM1606107"),
                  range.lower = 28,
                  range.upper = 32)
    
    plot_metagene(original.ribo,
                  site        = "stop",
                  normalize   = TRUE,
                  title       = "Stop Site Coverage",
                  range.lower = 28,
                  range.upper = 32)
    
    meta.start <- get_metagene(ribo.object = original.ribo, 
                               site        = "start",
                               range.lower = 28,
                               range.upper = 32,
                               length      = TRUE,
                               transcript  = TRUE)
    write.csv(as.data.frame(meta.start), "meta_start.csv", row.names = FALSE)
    
    tidy.meta.start <- get_tidy_metagene(ribo.object = original.ribo,
                                         site        = "start",
                                         range.lower = 28,
                                         range.upper = 32,
                                         length      = TRUE)
    write.csv(as.data.frame(tidy.meta.start), "tidy_meta_start.csv", row.names = FALSE)
    
    plot_metagene(tidy.meta.start, normalize = TRUE)
    
    # 4. Quantify and plot region counts
    plot_region_counts(x           = original.ribo,
                       range.lower = 28,
                       range.upper = 32)
    
    rc_cds <- get_region_counts(original.ribo,
                                range.lower = 28,
                                range.upper = 32,
                                length      = TRUE,
                                transcript  = TRUE,
                                region      = c("CDS"))
    write.csv(as.data.frame(rc_cds), "region_counts_cds.csv", row.names = FALSE)
    
    rc_non_tidy <- get_region_counts(original.ribo,
                                     range.lower = 28,
                                     range.upper = 32,
                                     tidy        = FALSE)
    write.csv(as.data.frame(rc_non_tidy), "region_counts_non_tidy.csv", row.names = FALSE)
    
    # Close PDF device
    dev.off()
    
    # 5. Retrieve region coordinates and lengths using alias
    alias.ribo <- Ribo(file.path, rename = rename_default)
    
    region_coord <- get_internal_region_coordinates(ribo.object = alias.ribo, alias = TRUE)
    write.csv(as.data.frame(region_coord), "internal_region_coordinates.csv", row.names = FALSE)
    
    region_lengths <- get_internal_region_lengths(ribo.object = alias.ribo, alias = TRUE)
    write.csv(as.data.frame(region_lengths), "internal_region_lengths.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to 'ribo_qc_plots.pdf', 'length_distribution.csv', 'meta_start.csv', 'tidy_meta_start.csv', 'region_counts_cds.csv', 'region_counts_non_tidy.csv', 'internal_region_coordinates.csv', and 'internal_region_lengths.csv'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RIBOR_RIBO_QC_AND_QUANTIFICATION":
        ribor: \$(Rscript -e 'cat(as.character(packageVersion("ribor")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ribo_qc_and_quantification.csv versions.yml
    """
}

workflow BIOC_RIBOR_RIBO_QC_AND_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HEK293_ingolia.ribo ] ]

    main:
    BIOC_RIBOR_RIBO_QC_AND_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_RIBOR_RIBO_QC_AND_QUANTIFICATION.out.tables
    plots    = BIOC_RIBOR_RIBO_QC_AND_QUANTIFICATION.out.plots
    objects  = BIOC_RIBOR_RIBO_QC_AND_QUANTIFICATION.out.objects
    versions = BIOC_RIBOR_RIBO_QC_AND_QUANTIFICATION.out.versions
}
