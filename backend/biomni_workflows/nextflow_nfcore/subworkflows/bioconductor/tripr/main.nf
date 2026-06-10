#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tripr — tripr_analysis_pipeline
// Run the complete TRIP analysis pipeline on IMGT/HighV-Quest output files to perform preselection, selection, and clonotype/repertoire computation.
// Input: 1_Summary.txt, 2_IMGT-gapped-nt-sequences.txt, 4_IMGT-gapped-AA-sequences.txt, 6_Junction.txt
// Container: quay.io/biocontainers/bioconductor-tripr:1.16.0--r45hdfd78af_0
// R packages: BiocStyle, fs, refmanager, tripr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRIPR_TRIPR_ANALYSIS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tripr:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("BiocStyle", "fs", "refmanager", "tripr")
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
    library(tripr)
    library(fs)
    library(tools)
    
    # 1. Define input and output paths using fs and tools packages
    # tripr expects each sample to have its own folder inside a root directory.
    # We create a temporary root directory and a sample subdirectory to structure the user's files.
    root_dir <- fs::path(getwd(), "tripr_input")
    sample_dir <- fs::path(root_dir, "sample1")
    
    if (!fs::dir_exists(sample_dir)) {
      fs::dir_create(sample_dir, recurse = TRUE)
    }
    
    # User input files expected in the working directory
    user_files <- c(
      "1_Summary.txt",
      "2_IMGT-gapped-nt-sequences.txt",
      "4_IMGT-gapped-AA-sequences.txt",
      "6_Junction.txt"
    )
    
    # Copy the user-provided files from the working directory to the sample directory
    for (f in user_files) {
      src_file <- fs::path(getwd(), f)
      if (!fs::file_exists(src_file)) {
        stop(paste("Required input file missing from working directory:", f))
      }
      fs::file_copy(src_file, fs::path(sample_dir, f), overwrite = TRUE)
    }
    
    datapath <- root_dir
    output_path <- fs::path(tools::R_user_dir("tripr", which = "cache"))
    
    if (!fs::dir_exists(output_path)) {
      fs::dir_create(output_path, recurse = TRUE)
    }
    
    # 2. Set pipeline parameters including cell type, throughput, preselection/selection filters, and clonotype definition
    cell <- "Bcell"
    preselection <- "1,2,3,4C:W"
    selection <- "5"
    filelist <- c(
      "1_Summary.txt",
      "2_IMGT-gapped-nt-sequences.txt",
      "4_IMGT-gapped-AA-sequences.txt",
      "6_Junction.txt"
    )
    throughput <- "High Throughput"
    identity_range <- "88:100"
    pipeline <- "1"
    select_clonotype <- "V Gene + CDR3 Amino Acids"
    
    # 3. Execute the complete analysis pipeline using run_TRIP()
    run_TRIP(
      datapath = datapath,
      output_path = output_path,
      filelist = filelist,
      cell = cell,
      throughput = throughput,
      preselection = preselection,
      selection = selection,
      identity_range = identity_range,
      pipeline = pipeline,
      select_clonotype = select_clonotype
    )
    
    # 4. Write named output files for the meaningful results
    # Locate the generated outputs in the output_path and copy them to a structured directory in the working directory
    output_dest_dir <- fs::path(getwd(), "pipeline_results")
    if (fs::dir_exists(output_dest_dir)) {
      fs::dir_delete(output_dest_dir)
    }
    fs::dir_create(output_dest_dir, recurse = TRUE)
    
    generated_files <- list.files(output_path, recursive = TRUE, full.names = TRUE)
    for (f in generated_files) {
      rel_path <- fs::path_rel(f, start = output_path)
      dest_file <- fs::path(output_dest_dir, rel_path)
      fs::dir_create(fs::path_dir(dest_file), recurse = TRUE)
      fs::file_copy(f, dest_file, overwrite = TRUE)
    }
    
    # Clean up the temporary input directory
    if (fs::dir_exists(root_dir)) {
      fs::dir_delete(root_dir)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TRIPR_TRIPR_ANALYSIS_PIPELINE":
        tripr: \$(Rscript -e 'cat(as.character(packageVersion("tripr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tripr_analysis_pipeline.csv versions.yml
    """
}

workflow BIOC_TRIPR_TRIPR_ANALYSIS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 1_Summary.txt, 2_IMGT-gapped-nt-sequences.txt, 4_IMGT-gapped-AA-sequences.txt, 6_Junction.txt ] ]

    main:
    BIOC_TRIPR_TRIPR_ANALYSIS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_TRIPR_TRIPR_ANALYSIS_PIPELINE.out.tables
    plots    = BIOC_TRIPR_TRIPR_ANALYSIS_PIPELINE.out.plots
    objects  = BIOC_TRIPR_TRIPR_ANALYSIS_PIPELINE.out.objects
    versions = BIOC_TRIPR_TRIPR_ANALYSIS_PIPELINE.out.versions
}
