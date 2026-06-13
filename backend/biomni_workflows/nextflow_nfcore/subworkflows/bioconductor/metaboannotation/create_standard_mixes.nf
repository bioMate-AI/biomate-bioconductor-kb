#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnnotation — create_standard_mixes
// Group standard compounds into mixes such that compounds in the same mix have a minimum m/z difference to avoid overlapping signals during LC-MS runs.
// Input: Standard_list_example.txt
// Container: quay.io/biocontainers/bioconductor-metaboannotation:1.14.0--r45hdfd78af_0
// R packages: MetaboAnnotation, MetaboCoreUtils
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnnotation, MetaboCoreUtils
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load standard compound list
//  * 2. [Core Analysis] Calculate exact masses and theoretical m/z values for desired adducts
//  * 3. [Core Analysis] Group compounds into mixes using createStandardMixes()
//  * 4. [Visualization & Output] Export designed mixes to a text file

nextflow.enable.dsl = 2

process BIOC_METABOANNOTATION_CREATE_STANDARD_MIXES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("MetaboAnnotation", "MetaboCoreUtils")
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
        library(MetaboAnnotation)
        library(MetaboCoreUtils)
        
        # 1. Load standard compound list from the working directory
        # The pipeline reads EXACTLY "Standard_list_example.txt" from the working directory
        standard <- read.table("Standard_list_example.txt", header = TRUE, sep = "\t", quote = "")
        
        # 2. Calculate exact masses and theoretical m/z values for desired adducts
        standard\$mass <- calculateMass(standard\$formula)
        standard_charged <- mass2mz(standard\$mass, adduct = c("[M+H]+", "[M+Na]+"))
        rownames(standard_charged) <- standard[ , 1]
        
        if (!is.matrix(standard_charged)) {
            standard_charged <- as.matrix(standard_charged, drop = FALSE)
        }
        
        # 3. Group compounds into mixes using createStandardMixes()
        # Run without randomization on a subset
        group_no_randomization <- createStandardMixes(head(standard_charged, 20))
        print("Table of groups (no randomization, subset 1:20):")
        print(table(group_no_randomization\$group))
        
        # Run without randomization on the full set
        group_no_randomization <- createStandardMixes(standard_charged)
        print("Table of groups (no randomization, full set):")
        print(table(group_no_randomization\$group))
        
        # Run with iterative randomization
        group_with_ramdomization <- createStandardMixes(standard_charged, iterativeRandomization = TRUE)
        print("Table of groups (with randomization, default constraints):")
        print(table(group_with_ramdomization\$group))
        
        # Run with iterative randomization and custom constraints
        set.seed(123)
        group_with_ramdomization <- createStandardMixes(
            standard_charged, 
            max_nstd = 15, 
            min_nstd = 10, 
            min_diff = 2, 
            iterativeRandomization = TRUE
        )
        print("Table of groups (with randomization, custom constraints):")
        print(table(group_with_ramdomization\$group))
        
        # 4. Export designed mixes to a text file
        write.table(group_with_ramdomization, file = "standard_mixes.txt", sep = "\t", quote = FALSE)

    writeLines(c(
        '"BIOC_METABOANNOTATION_CREATE_STANDARD_MIXES":',
        paste0('    MetaboAnnotation: ', as.character(packageVersion('MetaboAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_standard_mixes.csv versions.yml
    """
}

workflow BIOC_METABOANNOTATION_CREATE_STANDARD_MIXES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Standard_list_example.txt ] ]

    main:
    BIOC_METABOANNOTATION_CREATE_STANDARD_MIXES(ch_input)

    emit:
    tables   = BIOC_METABOANNOTATION_CREATE_STANDARD_MIXES.out.tables
    plots    = BIOC_METABOANNOTATION_CREATE_STANDARD_MIXES.out.plots
    objects  = BIOC_METABOANNOTATION_CREATE_STANDARD_MIXES.out.objects
    versions = BIOC_METABOANNOTATION_CREATE_STANDARD_MIXES.out.versions
}
