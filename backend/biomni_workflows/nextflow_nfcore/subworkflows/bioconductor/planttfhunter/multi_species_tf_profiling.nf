#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: planttfhunter — multi_species_tf_profiling
// Count and compare transcription factor family abundances across multiple species.
// Input: species_proteomes_directory, species_metadata.csv
// Container: quay.io/biocontainers/bioconductor-planttfhunter:1.10.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-planttfhunter:1.10.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "SummarizedExperiment", "planttfhunter")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(planttfhunter)
    library(Biostrings)
    library(SummarizedExperiment)
    
    # Define input paths
    proteomes_dir <- "species_proteomes_directory"
    metadata_file <- "species_metadata.csv"
    
    # Check if inputs exist
    if (!dir.exists(proteomes_dir)) {
        stop(paste("Directory does not exist:", proteomes_dir))
    }
    if (!file.exists(metadata_file)) {
        stop(paste("Metadata file does not exist:", metadata_file))
    }
    
    # 1. Read multiple proteome FASTA files into a named list of AAStringSet objects
    fasta_files <- list.files(proteomes_dir, pattern = "\\.(fa|fasta|faa|pep)\$", full.names = TRUE, ignore.case = TRUE)
    if (length(fasta_files) == 0) {
        stop(paste("No FASTA files found in", proteomes_dir))
    }
    
    proteomes <- lapply(fasta_files, Biostrings::readAAStringSet)
    names(proteomes) <- tools::file_path_sans_ext(basename(fasta_files))
    
    # 2. Create a species metadata data frame with row names matching the list names
    species_metadata <- read.csv(metadata_file, row.names = 1, stringsAsFactors = FALSE)
    
    # Align proteomes and metadata to ensure exact match of names
    common_species <- intersect(names(proteomes), rownames(species_metadata))
    if (length(common_species) == 0) {
        stop("No matching species names found between proteome files and species_metadata.csv row names.")
    }
    proteomes <- proteomes[common_species]
    species_metadata <- species_metadata[common_species, , drop = FALSE]
    
    # 3. Run HMMER annotation and TF family counting across all proteomes
    if (!planttfhunter::hmmer_is_installed()) {
        stop("HMMER is not installed or not in the system PATH. planttfhunter requires HMMER to run.")
    }
    
    tf_counts <- get_tf_counts(proteomes, species_metadata)
    
    # 4. Extract the TF count matrix and metadata from the resulting SummarizedExperiment
    counts_matrix <- SummarizedExperiment::assay(tf_counts)
    metadata_extracted <- SummarizedExperiment::colData(tf_counts)
    
    # Write outputs
    write.csv(as.data.frame(counts_matrix), "tf_counts_matrix.csv", row.names = TRUE)
    write.csv(as.data.frame(metadata_extracted), "tf_counts_metadata.csv", row.names = TRUE)
    saveRDS(tf_counts, "tf_counts_se.rds")
    
    message("Workflow completed successfully. Outputs saved to 'tf_counts_matrix.csv', 'tf_counts_metadata.csv', and 'tf_counts_se.rds'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING":
        planttfhunter: \$(Rscript -e 'cat(as.character(packageVersion("planttfhunter")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_species_tf_profiling.csv versions.yml
    """
}

workflow BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ species_proteomes_directory, species_metadata.csv ] ]

    main:
    BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING(ch_input)

    emit:
    tables   = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING.out.tables
    plots    = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING.out.plots
    objects  = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING.out.objects
    versions = BIOC_PLANTTFHUNTER_MULTI_SPECIES_TF_PROFILING.out.versions
}
