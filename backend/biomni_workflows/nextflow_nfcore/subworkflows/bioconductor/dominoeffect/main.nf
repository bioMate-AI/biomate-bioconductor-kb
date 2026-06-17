#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DominoEffect — hotspot_pipeline_wrapper
// Run the complete hotspot identification and functional annotation pipeline in a single step using the wrapper function.
// Input: user_file_with_mutations.txt, user_ensembl_gene_list.txt, user_population_SNPs_with_frequency.txt
// Container: quay.io/biocontainers/bioconductor-dominoeffect:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DominoEffect
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input datasets
//  * 2. [Core Analysis] Run the DominoEffect wrapper function to identify and annotate hotspots

nextflow.enable.dsl = 2

process BIOC_DOMINOEFFECT_HOTSPOT_PIPELINE_WRAPPER {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("DominoEffect")
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
    
    # Stage 1: Load the package and input datasets
    library(DominoEffect)
    
    # Read the user-provided input files
    TestData <- read.table("user_file_with_mutations.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    DominoData <- read.table("user_ensembl_gene_list.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    SnpData <- read.table("user_population_SNPs_with_frequency.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Stage 2: Run the DominoEffect wrapper function to identify and annotate hotspots
    hotspot_mutations <- DominoEffect(mutation_dataset = TestData, gene_data = DominoData, snp_data = SnpData)
    
    # Save the results to output files
    write.table(hotspot_mutations, "Protein_hotspot_residues.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    saveRDS(hotspot_mutations, "hotspot_mutations.rds")
    
    # Optional: Convert results into GPo object and save if successful
    tryCatch({
      hotspot_mutations.GPo <- GPo_of_hotspots(hotspot_mutations)
      saveRDS(hotspot_mutations.GPo, "hotspot_mutations_GPo.rds")
    }, error = function(e) {
      message("GPo conversion skipped or failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_DOMINOEFFECT_HOTSPOT_PIPELINE_WRAPPER":',
        paste0('    DominoEffect: ', as.character(packageVersion('DominoEffect')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hotspot_pipeline_wrapper.csv versions.yml
    """
}

workflow BIOC_DOMINOEFFECT_HOTSPOT_PIPELINE_WRAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_file_with_mutations.txt, user_ensembl_gene_list.txt, user_population_SNPs_with_frequency.txt ] ]

    main:
    BIOC_DOMINOEFFECT_HOTSPOT_PIPELINE_WRAPPER(ch_input)

    emit:
    tables   = BIOC_DOMINOEFFECT_HOTSPOT_PIPELINE_WRAPPER.out.tables
    plots    = BIOC_DOMINOEFFECT_HOTSPOT_PIPELINE_WRAPPER.out.plots
    objects  = BIOC_DOMINOEFFECT_HOTSPOT_PIPELINE_WRAPPER.out.objects
    versions = BIOC_DOMINOEFFECT_HOTSPOT_PIPELINE_WRAPPER.out.versions
}
