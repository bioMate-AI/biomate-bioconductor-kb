#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: synapsis — meiotic_foci_quantification
// Crop raw meiotic immunofluorescence images, filter for pachytene-stage cells, and count coincident foci on the synaptonemal complex.
// Input: foci_channel.tif, sc_channel.tif
// Container: quay.io/biocontainers/bioconductor-synapsis:1.16.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNAPSIS_MEIOTIC_FOCI_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-synapsis:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("devtools", "ebimage", "synapsis")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Check for required input files in the working directory
    input_foci <- "foci_channel.tif"
    input_sc <- "sc_channel.tif"
    
    if (!file.exists(input_foci)) {
      stop(paste("Required input file missing:", input_foci))
    }
    if (!file.exists(input_sc)) {
      stop(paste("Required input file missing:", input_sc))
    }
    
    # Load required libraries
    library(synapsis)
    
    # Set up a dedicated directory for the synapsis run
    # Synapsis identifies channel pairs using file name patterns.
    # By default, it looks for "-MLH3" for the foci channel and "-SYCP3" for the SC channel,
    # and expects a genotype indicator like "++" in the filename.
    path <- "synapsis_analysis_dir"
    if (!dir.exists(path)) {
      dir.create(path)
    }
    
    # Copy user input files to the analysis directory with expected naming conventions
    file.copy(input_foci, file.path(path, "sample++-MLH3.tif"), overwrite = TRUE)
    file.copy(input_sc, file.path(path, "sample++-SYCP3.tif"), overwrite = TRUE)
    
    # 1. Crop individual cells from raw images using auto_crop_fast
    auto_crop_fast(
      path, 
      annotation = "on", 
      max_cell_area = 30000, 
      min_cell_area = 7000, 
      file_ext = "tif", 
      crowded_cells = TRUE
    )
    
    # 2. Identify pachytene-stage cells using get_pachytene
    SYCP3_stats <- get_pachytene(
      path, 
      ecc_thresh = 0.8, 
      area_thresh = 0.04, 
      annotation = "on", 
      file_ext = "tif"
    )
    
    # 3. Count coincident foci on the synaptonemal complex using count_foci
    foci_counts <- count_foci(
      path, 
      offset_factor = 8, 
      brush_size = 3, 
      offset_px = 0.6, 
      brush_sigma = 3, 
      annotation = "on", 
      stage = "pachytene", 
      file_ext = "tif", 
      watershed_stop = "on",  
      crowded_foci = FALSE, 
      C1 = 0.03, 
      disc_size_foci = 9
    )
    
    # Print the results to the console
    print(foci_counts)
    
    # Save the meaningful results to output files
    write.csv(SYCP3_stats, "SYCP3_stats.csv", row.names = FALSE)
    write.csv(foci_counts, "foci_counts.csv", row.names = FALSE)
    saveRDS(foci_counts, "foci_counts.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SYNAPSIS_MEIOTIC_FOCI_QUANTIFICATION":
        synapsis: \$(Rscript -e 'cat(as.character(packageVersion("synapsis")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meiotic_foci_quantification.csv versions.yml
    """
}

workflow BIOC_SYNAPSIS_MEIOTIC_FOCI_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ foci_channel.tif, sc_channel.tif ] ]

    main:
    BIOC_SYNAPSIS_MEIOTIC_FOCI_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_SYNAPSIS_MEIOTIC_FOCI_QUANTIFICATION.out.tables
    plots    = BIOC_SYNAPSIS_MEIOTIC_FOCI_QUANTIFICATION.out.plots
    objects  = BIOC_SYNAPSIS_MEIOTIC_FOCI_QUANTIFICATION.out.objects
    versions = BIOC_SYNAPSIS_MEIOTIC_FOCI_QUANTIFICATION.out.versions
}
