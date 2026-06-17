#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Pirat — imputation_with_extensions
// Impute proteomics data using extensions (2-peptide rule, sample-wise correlations, or transcriptomic integration) to handle singleton peptide groups.
// Input: subropers
// Container: quay.io/biocontainers/bioconductor-pirat:1.4.4--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Pirat
// QC: low-count filtering, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the dataset
//  * 2. [Core Analysis] Run imputation with the 2-peptide rule extension using pipeline_llkimpute
//  * 3. [Core Analysis] Run imputation with sample-wise correlations extension using my_pipeline_llkimpute
//  * 4. [Core Analysis] Run imputation with transcriptomic integration extension using my_pipeline_llkimpute with paired or condition-masked samples

nextflow.enable.dsl = 2

process BIOC_PIRAT_IMPUTATION_WITH_EXTENSIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("Pirat")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
        library(Pirat)
        library(utils)
        
        # Set seed for reproducibility as recommended in the vignette
        set.seed(12345)
        
        # 1. Load the dataset from the working directory
        # The pipeline expects 'subropers.rds' containing the list with peptides_ab, adj, rnas_ab, and adj_rna_pg
        if (!file.exists("subropers.rds")) {
          stop("Error: 'subropers.rds' not found in the working directory.")
        }
        subropers <- readRDS("subropers.rds")
        
        # 2. Run imputation with the 2-peptide rule extension using pipeline_llkimpute
        message("Running imputation with extension '2' (2-peptide rule)...")
        imp.res.2 <- pipeline_llkimpute(subropers, extension = "2")
        
        mask.sing.pg <- colSums(subropers\$adj) == 1
        mask.sing.pep <- rowSums(subropers\$adj[, mask.sing.pg, drop = FALSE]) >= 1
        imputed_sing_2 <- imp.res.2\$data.imputed[, mask.sing.pep, drop = FALSE]
        
        # Save results for extension '2'
        saveRDS(imp.res.2, "imp_res_ext2.rds")
        write.csv(as.data.frame(imp.res.2\$data.imputed), "imputed_data_ext2.csv", row.names = TRUE)
        write.csv(as.data.frame(imputed_sing_2), "imputed_singletons_ext2.csv", row.names = TRUE)
        
        
        # 3. Run imputation with sample-wise correlations extension using my_pipeline_llkimpute
        message("Running imputation with extension 'S' (sample-wise correlations)...")
        imp.res.S <- my_pipeline_llkimpute(subropers, extension = "S")
        
        mask.sing.pg <- colSums(subropers\$adj) == 1
        mask.sing.pep <- rowSums(subropers\$adj[, mask.sing.pg, drop = FALSE]) >= 1
        imputed_sing_S <- imp.res.S\$data.imputed[, mask.sing.pep, drop = FALSE]
        
        # Save results for extension 'S'
        saveRDS(imp.res.S, "imp_res_extS.rds")
        write.csv(as.data.frame(imp.res.S\$data.imputed), "imputed_data_extS.csv", row.names = TRUE)
        write.csv(as.data.frame(imputed_sing_S), "imputed_singletons_extS.csv", row.names = TRUE)
        
        
        # 4. Run imputation with transcriptomic integration extension using my_pipeline_llkimpute (paired samples)
        message("Running imputation with extension 'T' (transcriptomic integration - paired)...")
        imp.res.T.paired <- my_pipeline_llkimpute(subropers,
            extension = "T",
            rna.cond.mask = seq(nrow(subropers\$peptides_ab)),
            pep.cond.mask = seq(nrow(subropers\$peptides_ab)),
            max.pg.size.pirat.t = 1)
        
        mask.sing.pg <- colSums(subropers\$adj) == 1
        mask.sing.pep <- rowSums(subropers\$adj[, mask.sing.pg, drop = FALSE]) >= 1
        imputed_sing_T_paired <- imp.res.T.paired\$data.imputed[, mask.sing.pep, drop = FALSE]
        
        # Save results for extension 'T' (paired)
        saveRDS(imp.res.T.paired, "imp_res_extT_paired.rds")
        write.csv(as.data.frame(imp.res.T.paired\$data.imputed), "imputed_data_extT_paired.csv", row.names = TRUE)
        write.csv(as.data.frame(imputed_sing_T_paired), "imputed_singletons_extT_paired.csv", row.names = TRUE)
        
        
        # 5. Run imputation with transcriptomic integration extension using my_pipeline_llkimpute (condition-masked samples)
        message("Running imputation with extension 'T' (transcriptomic integration - condition-masked)...")
        n_samples <- nrow(subropers\$peptides_ab)
        cond_mask <- rep(seq_len(ceiling(n_samples / 3)), each = 3)[seq_len(n_samples)]
        imp.res.T.cond <- my_pipeline_llkimpute(subropers,
                                     extension = "T",
                                     rna.cond.mask = cond_mask,
                                     pep.cond.mask = cond_mask,
                                     max.pg.size.pirat.t = 1)
        
        mask.sing.pg <- colSums(subropers\$adj) == 1
        mask.sing.pep <- rowSums(subropers\$adj[, mask.sing.pg, drop = FALSE]) >= 1
        imputed_sing_T_cond <- imp.res.T.cond\$data.imputed[, mask.sing.pep, drop = FALSE]
        
        # Save results for extension 'T' (condition-masked)
        saveRDS(imp.res.T.cond, "imp_res_extT_cond.rds")
        write.csv(as.data.frame(imp.res.T.cond\$data.imputed), "imputed_data_extT_cond.csv", row.names = TRUE)
        write.csv(as.data.frame(imputed_sing_T_cond), "imputed_singletons_extT_cond.csv", row.names = TRUE)
        
        message("Pirat imputation pipeline completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_PIRAT_IMPUTATION_WITH_EXTENSIONS":',
        paste0('    Pirat: ', as.character(packageVersion('Pirat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_imputation_with_extensions.csv versions.yml
    """
}

workflow BIOC_PIRAT_IMPUTATION_WITH_EXTENSIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ subropers ] ]

    main:
    BIOC_PIRAT_IMPUTATION_WITH_EXTENSIONS(ch_input)

    emit:
    tables   = BIOC_PIRAT_IMPUTATION_WITH_EXTENSIONS.out.tables
    plots    = BIOC_PIRAT_IMPUTATION_WITH_EXTENSIONS.out.plots
    objects  = BIOC_PIRAT_IMPUTATION_WITH_EXTENSIONS.out.objects
    versions = BIOC_PIRAT_IMPUTATION_WITH_EXTENSIONS.out.versions
}
