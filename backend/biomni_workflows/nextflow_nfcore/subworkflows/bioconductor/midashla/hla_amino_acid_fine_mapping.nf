#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: midasHLA — hla_amino_acid_fine_mapping
// Fine-map HLA associations to the amino acid level by inferring residues, running omnibus tests, and mapping residues back to alleles.
// Input: MiDAS_tut_pheno.txt, MiDAS_tut_HLA.txt
// Container: quay.io/biocontainers/bioconductor-midashla:1.18.0--r45hdfd78af_0
// R packages: midasHLA
// Bioconductor: 3.20 | R: 4.4
// Requires: midasHLA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Combine HLA and phenotypic data using prepareMiDAS with experiment = "hla_aa"
//  * 2. [Input & Preparation] Define a statistical model using the placeholder term
//  * 3. [Core Analysis] Run a likelihood ratio (omnibus) test using runMiDAS
//  * 4. [Core Analysis] Investigate effect estimates for a specific amino acid position using runMiDAS with omnibus_groups_filter
//  * 5. [Core Analysis] Map amino acid residues back to HLA alleles using getAllelesForAA

nextflow.enable.dsl = 2

process BIOC_MIDASHLA_HLA_AMINO_ACID_FINE_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    
    # 1. Read the user input files from the working directory
    dat_pheno <- read.table(
      file = "MiDAS_tut_pheno.txt",
      header = TRUE,
      stringsAsFactors = FALSE
    )
    
    dat_HLA <- readHlaCalls(
      file = "MiDAS_tut_HLA.txt",
      resolution = 4
    )
    
    # 2. Combine HLA and phenotypic data using prepareMiDAS with experiment = "hla_aa"
    HLA_AA <- prepareMiDAS(
      hla_calls = dat_HLA,
      colData = dat_pheno,
      experiment = "hla_aa"
    )
    
    # 3. Define a statistical model using the placeholder 'term'
    HLA_AA_model <- glm(
      disease ~ term,
      data = HLA_AA,
      family = binomial()
    )
    
    # 4. Run a likelihood ratio (omnibus) test using runMiDAS
    HLA_AA_omnibus_results <- runMiDAS(
      HLA_AA_model,
      experiment = "hla_aa",
      inheritance_model = "dominant",
      conditional = FALSE,
      omnibus = TRUE,
      lower_frequency_cutoff = 0.02,
      upper_frequency_cutoff = 0.98,
      correction = "bonferroni"
    )
    
    # 5. Investigate effect estimates for a specific amino acid position (DQB1_9)
    HLA_AA_DQB1_9_results <- runMiDAS(
      HLA_AA_model,
      experiment = "hla_aa",
      inheritance_model = "dominant",
      omnibus_groups_filter = "DQB1_9",
      lower_frequency_cutoff = 0.02,
      upper_frequency_cutoff = 0.98,
      correction = "bonferroni",
      exponentiate = TRUE
    )
    
    # 6. Map amino acid residues back to HLA alleles
    HLA_AA_DQB1_9_alleles <- getAllelesForAA(
      HLA_AA,
      "DQB1_9"
    )
    
    # 7. Write outputs to files
    write.csv(
      HLA_AA_omnibus_results,
      file = "HLA_AA_omnibus_results.csv",
      row.names = FALSE
    )
    
    write.csv(
      HLA_AA_DQB1_9_results,
      file = "HLA_AA_DQB1_9_results.csv",
      row.names = FALSE
    )
    
    if (is.data.frame(HLA_AA_DQB1_9_alleles) || is.matrix(HLA_AA_DQB1_9_alleles)) {
      write.csv(
        as.data.frame(HLA_AA_DQB1_9_alleles),
        file = "HLA_AA_DQB1_9_alleles.csv",
        row.names = TRUE
      )
    } else {
      saveRDS(
        HLA_AA_DQB1_9_alleles,
        file = "HLA_AA_DQB1_9_alleles.rds"
      )
    }
    
    saveRDS(
      HLA_AA,
      file = "HLA_AA_prepared_object.rds"
    )

    writeLines(c(
        '"BIOC_MIDASHLA_HLA_AMINO_ACID_FINE_MAPPING":',
        paste0('    midasHLA: ', as.character(packageVersion('midasHLA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hla_amino_acid_fine_mapping.csv versions.yml
    """
}

workflow BIOC_MIDASHLA_HLA_AMINO_ACID_FINE_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MiDAS_tut_pheno.txt, MiDAS_tut_HLA.txt ] ]

    main:
    BIOC_MIDASHLA_HLA_AMINO_ACID_FINE_MAPPING(ch_input)

    emit:
    tables   = BIOC_MIDASHLA_HLA_AMINO_ACID_FINE_MAPPING.out.tables
    plots    = BIOC_MIDASHLA_HLA_AMINO_ACID_FINE_MAPPING.out.plots
    objects  = BIOC_MIDASHLA_HLA_AMINO_ACID_FINE_MAPPING.out.objects
    versions = BIOC_MIDASHLA_HLA_AMINO_ACID_FINE_MAPPING.out.versions
}
