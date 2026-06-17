#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DominoEffect — hotspot_step_by_step
// Run hotspot identification, functional annotation, and genomic position conversion as separate steps with custom parameters.
// Input: user_file_with_mutations.txt, user_ensembl_gene_list.txt, user_population_SNPs_with_frequency.txt
// Container: quay.io/biocontainers/bioconductor-dominoeffect:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DominoEffect
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input datasets
//  * 2. [Core Analysis] Identify hotspot mutations with custom statistical thresholds
//  * 3. [Core Analysis] Map identified hotspots to functional elements using UniProt/Swiss-Prot
//  * 4. [Core Analysis] Convert the hotspot genomic coordinates into a GPo object for downstream genomic analyses

nextflow.enable.dsl = 2

process BIOC_DOMINOEFFECT_HOTSPOT_STEP_BY_STEP {
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
    
    # Load the required package
    library(DominoEffect)
    
    # 1. Load the input datasets from the working directory
    mutation_dataset <- read.table("user_file_with_mutations.txt", header = TRUE, stringsAsFactors = FALSE)
    gene_data <- read.table("user_ensembl_gene_list.txt", header = TRUE, stringsAsFactors = FALSE)
    snp_data <- read.table("user_population_SNPs_with_frequency.txt", header = TRUE, stringsAsFactors = FALSE)
    
    # 2. Identify hotspot mutations with custom statistical thresholds
    hotspot_mutations <- identify_hotspots(
      mutation_dataset = mutation_dataset,
      gene_data = gene_data,
      snp_data = snp_data,
      min_n_muts = 5,
      MAF_thresh = 0.01,
      flanking_region = c(200, 300),
      poisson.thr = 0.01,
      percentage.thr = 0.15,
      ratio.thr = 45,
      approach = "percentage"
    )
    
    # Save the identified hotspots
    write.csv(hotspot_mutations, "hotspot_mutations.csv", row.names = FALSE)
    saveRDS(hotspot_mutations, "hotspot_mutations.rds")
    
    # 3. Map identified hotspots to functional elements using UniProt/Swiss-Prot
    # Wrapped in tryCatch to handle potential network or BioMart service interruptions robustly
    results_w_annotations <- NULL
    tryCatch({
      results_w_annotations <- map_to_func_elem(
        hotspot_mutations,
        write_to_file = "NO",
        ens_release = "73"
      )
      if (!is.null(results_w_annotations)) {
        write.csv(results_w_annotations, "results_w_annotations.csv", row.names = FALSE)
        saveRDS(results_w_annotations, "results_w_annotations.rds")
      }
    }, error = function(e) {
      message("Warning: map_to_func_elem failed (likely due to network or BioMart server issues): ", e\$message)
    })
    
    # 4. Convert the hotspot genomic coordinates into a GPo object for downstream genomic analyses
    hotspot_mutations.GPo <- GPo_of_hotspots(hotspot_mutations)
    
    # Save the GPo object
    if (!is.null(hotspot_mutations.GPo)) {
      saveRDS(hotspot_mutations.GPo, "hotspot_mutations_GPo.rds")
    }

    writeLines(c(
        '"BIOC_DOMINOEFFECT_HOTSPOT_STEP_BY_STEP":',
        paste0('    DominoEffect: ', as.character(packageVersion('DominoEffect')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hotspot_step_by_step.csv versions.yml
    """
}

workflow BIOC_DOMINOEFFECT_HOTSPOT_STEP_BY_STEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_file_with_mutations.txt, user_ensembl_gene_list.txt, user_population_SNPs_with_frequency.txt ] ]

    main:
    BIOC_DOMINOEFFECT_HOTSPOT_STEP_BY_STEP(ch_input)

    emit:
    tables   = BIOC_DOMINOEFFECT_HOTSPOT_STEP_BY_STEP.out.tables
    plots    = BIOC_DOMINOEFFECT_HOTSPOT_STEP_BY_STEP.out.plots
    objects  = BIOC_DOMINOEFFECT_HOTSPOT_STEP_BY_STEP.out.objects
    versions = BIOC_DOMINOEFFECT_HOTSPOT_STEP_BY_STEP.out.versions
}
