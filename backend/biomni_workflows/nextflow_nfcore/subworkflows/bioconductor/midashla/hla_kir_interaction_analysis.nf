#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: midasHLA — hla_kir_interaction_analysis
// Analyze associations with Natural Killer (NK) cell ligands and KIR gene presence/absence, including HLA-KIR interactions.
// Input: MiDAS_tut_pheno.txt, MiDAS_tut_HLA.txt, MiDAS_tut_KIR.txt
// Container: quay.io/biocontainers/bioconductor-midashla:1.18.0--r45hdfd78af_0
// R packages: midasHLA
// Bioconductor: 3.20 | R: 4.4
// Requires: midasHLA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Combine HLA and phenotypic data using prepareMiDAS with experiment = c("hla_alleles", "hla_NK_ligands")
//  * 2. [Input & Preparation] Define a statistical model and run association analysis on NK ligands using runMiDAS
//  * 3. [Input & Preparation] Import KIR calls using readKirCalls

nextflow.enable.dsl = 2

process BIOC_MIDASHLA_HLA_KIR_INTERACTION_ANALYSIS {
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
    
    # Load required library
    library(midasHLA)
    
    # 1. Import the phenotypic data and HLA calls from the working directory
    dat_pheno <- read.table(
      file = "MiDAS_tut_pheno.txt",
      header = TRUE,
      stringsAsFactors = FALSE
    )
    
    dat_HLA <- readHlaCalls(
      file = "MiDAS_tut_HLA.txt",
      resolution = 4
    )
    
    # 2. Combine HLA and phenotypic data using prepareMiDAS
    NKlig <- prepareMiDAS(
      hla_calls = dat_HLA,
      colData = dat_pheno,
      experiment = c("hla_alleles", "hla_NK_ligands")
    )
    
    # 3. Define a statistical model and run association analysis on NK ligands
    NKlig_model <- glm(disease ~ term, data = NKlig, family = binomial())
    
    NKlig_results <- runMiDAS(
      NKlig_model,
      experiment = "hla_NK_ligands",
      inheritance_model = "dominant",
      correction = "bonferroni",
      exponentiate = TRUE
    )
    
    # 4. Import KIR calls from the working directory
    dat_KIR <- readKirCalls(
      file = "MiDAS_tut_KIR.txt"
    )
    
    # 5. Write outputs to the working directory
    write.csv(NKlig_results, "NKlig_results.csv", row.names = FALSE)
    saveRDS(NKlig, "NKlig_object.rds")
    saveRDS(dat_KIR, "dat_KIR.rds")

    writeLines(c(
        '"BIOC_MIDASHLA_HLA_KIR_INTERACTION_ANALYSIS":',
        paste0('    midasHLA: ', as.character(packageVersion('midasHLA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hla_kir_interaction_analysis.csv versions.yml
    """
}

workflow BIOC_MIDASHLA_HLA_KIR_INTERACTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MiDAS_tut_pheno.txt, MiDAS_tut_HLA.txt, MiDAS_tut_KIR.txt ] ]

    main:
    BIOC_MIDASHLA_HLA_KIR_INTERACTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MIDASHLA_HLA_KIR_INTERACTION_ANALYSIS.out.tables
    plots    = BIOC_MIDASHLA_HLA_KIR_INTERACTION_ANALYSIS.out.plots
    objects  = BIOC_MIDASHLA_HLA_KIR_INTERACTION_ANALYSIS.out.objects
    versions = BIOC_MIDASHLA_HLA_KIR_INTERACTION_ANALYSIS.out.versions
}
