#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: midasHLA — hla_allele_association
// Perform association analysis on classical HLA alleles, filter by Hardy-Weinberg Equilibrium, and run conditional testing to identify independent signals.
// Input: MiDAS_tut_pheno.txt, MiDAS_tut_HLA.txt
// Container: quay.io/biocontainers/bioconductor-midashla:1.18.0--r45hdfd78af_0
// R packages: midasHLA
// Bioconductor: 3.20 | R: 4.4
// Requires: midasHLA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read phenotype data using read.table
//  * 2. [Input & Preparation] Read HLA calls using readHlaCalls with a specified resolution
//  * 3. [Core Analysis] Combine genetic and phenotypic data using prepareMiDAS
//  * 4. [Core Analysis] Test for Hardy-Weinberg Equilibrium and filter alleles using HWETest
//  * 5. [Input & Preparation] Define a statistical model using the placeholder term
//  * 6. [Core Analysis] Run association analysis using runMiDAS
//  * 7. [Core Analysis] Run stepwise conditional association analysis by setting conditional = TRUE in runMiDAS

nextflow.enable.dsl = 2

process BIOC_MIDASHLA_HLA_ALLELE_ASSOCIATION {
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
    .bm_deps <- c("midasHLA")
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
    library(midasHLA)
    
    # 1. Read phenotype data
    dat_pheno <- read.table(file = "MiDAS_tut_pheno.txt", header = TRUE, stringsAsFactors = FALSE)
    
    # 2. Read HLA calls
    dat_HLA <- readHlaCalls(file = "MiDAS_tut_HLA.txt", resolution = 4)
    
    # 3. Combine genetic and phenotypic data
    HLA <- prepareMiDAS(hla_calls = dat_HLA, colData = dat_pheno, experiment = "hla_alleles")
    
    # 4. Test for Hardy-Weinberg Equilibrium and filter alleles
    HLA <- HWETest(object = HLA, experiment = "hla_alleles", HWE_cutoff = 0.05 / nrow(HLA[["hla_alleles"]]), as.MiDAS = TRUE)
    
    # 5. Define a statistical model using the placeholder term
    HLA_model <- glm(disease ~ term, data = HLA, family = binomial())
    
    # 6. Run association analysis
    HLA_results <- runMiDAS(object = HLA_model, experiment = "hla_alleles", inheritance_model = "dominant", lower_frequency_cutoff = 0.02, upper_frequency_cutoff = 0.98, correction = "bonferroni", exponentiate = TRUE)
    
    # 7. Run stepwise conditional association analysis
    HLA_results_cond <- runMiDAS(object = HLA_model, experiment = "hla_alleles", inheritance_model = "dominant", conditional = TRUE, lower_frequency_cutoff = 0.02, upper_frequency_cutoff = 0.98, correction = "bonferroni", exponentiate = TRUE)
    
    # Save outputs to the working directory
    write.csv(HLA_results, file = "HLA_results.csv", row.names = FALSE)
    write.csv(HLA_results_cond, file = "HLA_results_cond.csv", row.names = FALSE)
    saveRDS(HLA, file = "HLA_prepared_object.rds")

    writeLines(c(
        '"BIOC_MIDASHLA_HLA_ALLELE_ASSOCIATION":',
        paste0('    midasHLA: ', as.character(packageVersion('midasHLA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hla_allele_association.csv versions.yml
    """
}

workflow BIOC_MIDASHLA_HLA_ALLELE_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MiDAS_tut_pheno.txt, MiDAS_tut_HLA.txt ] ]

    main:
    BIOC_MIDASHLA_HLA_ALLELE_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_MIDASHLA_HLA_ALLELE_ASSOCIATION.out.tables
    plots    = BIOC_MIDASHLA_HLA_ALLELE_ASSOCIATION.out.plots
    objects  = BIOC_MIDASHLA_HLA_ALLELE_ASSOCIATION.out.objects
    versions = BIOC_MIDASHLA_HLA_ALLELE_ASSOCIATION.out.versions
}
