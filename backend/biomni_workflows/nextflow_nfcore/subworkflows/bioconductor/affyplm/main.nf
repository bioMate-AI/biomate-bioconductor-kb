#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affyPLM — probe_level_modeling_and_qc
// Fit probe-level models to Affymetrix microarray data and perform comprehensive quality control diagnostics using spatial chip images, RLE, and NUSE.
// Input: Dilution
// Container: quay.io/biocontainers/bioconductor-affyplm:1.86.0--r45h01b2380_0
// R packages: affydata, affyPLM
// Bioconductor: 3.20 | R: 4.4
// Requires: affyPLM, affydata
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and update the AffyBatch object
//  * 2. [Core Analysis] Fit a standard or customized probe-level model (PLM)
//  * 3. [Core Analysis] Extract model coefficients and standard errors
//  * 4. [Core Analysis] Generate spatial pseudo-images of weights and residuals
//  * 5. [Core Analysis] Perform Relative Log Expression (RLE) and Normalized Unscaled Standard Error (NUSE) quality diagnostics

nextflow.enable.dsl = 2

process BIOC_AFFYPLM_PROBE_LEVEL_MODELING_AND_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("affydata", "affyPLM")
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
        library(affyPLM)
        library(affydata)
        
        # 1. Load package and update the AffyBatch object
        message("Reading input Dilution dataset from the working directory...")
        if (file.exists("Dilution.rds")) {
          Dilution <- readRDS("Dilution.rds")
        } else if (file.exists("Dilution.RData")) {
          # Load the RData file which is expected to contain the 'Dilution' object
          load("Dilution.RData")
        } else {
          stop("Error: Required input file 'Dilution.rds' or 'Dilution.RData' not found in the working directory.")
        }
        
        message("Updating the AffyBatch object...")
        Dilution = updateObject(Dilution)
        
        # 2. Fit standard probe-level model (PLM)
        message("Fitting standard PLM...")
        Pset <- fitPLM(Dilution)
        
        # Save the full standard PLM object for later QC diagnostics
        Pset_full <- Pset
        
        # 3. Extract model coefficients and standard errors
        message("Extracting coefficients and standard errors...")
        coef_std <- coefs(Pset)[1:5,]
        se_std <- se(Pset)[1:5,]
        
        write.csv(coef_std, "coefs_standard_top5.csv")
        write.csv(se_std, "se_standard_top5.csv")
        
        # Verify output parameters
        verify.output.param()
        
        # Fit PLM with no residuals and no weights
        message("Fitting PLM with residuals=FALSE and weights=FALSE...")
        Pset <- fitPLM(Dilution,output.param=list(residuals=FALSE,weights=FALSE))
        saveRDS(Pset, "Pset_no_residuals_no_weights.rds")
        
        # Fit PLM with no robustness (max.its=0)
        message("Fitting PLM with max.its=0...")
        Pset <- fitPLM(Dilution,model.param=list(max.its=0))
        saveRDS(Pset, "Pset_no_robustness.rds")
        
        # Fit customized models on a subset of 100 genes
        message("Fitting customized models on a subset of 100 genes...")
        
        Pset <- fitPLM(Dilution,  MM ~ -1 + samples + probes,subset = geneNames(Dilution)[1:100])
        write.csv(as.data.frame(t(coefs(Pset)[1,])), "coefs_model_MM_liver_scanner.csv")
        write.csv(as.data.frame(coefs.probe(Pset)[1]), "coefs_probe_model_MM_liver_scanner.csv")
        
        logliver <- log2(seq_len(length(sampleNames(Dilution))))
        Pset <- fitPLM(Dilution,model=PM~-1+probes+logliver+samples, variable.type=c(logliver="covariate"),subset = geneNames(Dilution)[1:100])
        write.csv(as.data.frame(t(coefs(Pset)[1,])), "coefs_model_PM_covariate.csv")
        
        Pset <- fitPLM(Dilution,  PM ~ MM + samples + probes,subset = geneNames(Dilution)[1:100])
        write.csv(as.data.frame(t(coefs(Pset)[1,])), "coefs_model_PM_MM_samples.csv")
        write.csv(as.data.frame(t(coefs.const(Pset)[1,])), "coefs_const_model_PM_MM_samples.csv")
        write.csv(as.data.frame(coefs.probe(Pset)[1]), "coefs_probe_model_PM_MM_samples.csv")
        
        Pset <- fitPLM(Dilution,  PMMM ~ samples + probe.type + probes,subset = geneNames(Dilution)[1:100])
        write.csv(as.data.frame(t(coefs(Pset)[1,])), "coefs_model_PMMM_liver_probetype.csv")
        write.csv(as.data.frame(t(coefs.const(Pset)[1,])), "coefs_const_model_PMMM_liver_probetype.csv")
        write.csv(as.data.frame(coefs.probe(Pset)[1]), "coefs_probe_model_PMMM_liver_probetype.csv")
        
        Pset <- fitPLM(Dilution,  PM ~ -1 + samples + samples:probes,subset = geneNames(Dilution)[1:100])
        write.csv(as.data.frame(coefs.probe(Pset)[1]), "coefs_probe_model_PM_liver_interaction.csv")
        
        Pset <- fitPLM(Dilution,   PMMM ~ -1 + samples + probe.type:probes,subset = geneNames(Dilution)[1:100])
        write.csv(as.data.frame(coefs.probe(Pset)[1]), "coefs_probe_model_PMMM_probetype_interaction.csv")
        
        Pset <- fitPLM(Dilution,   PMMM ~ -1 + samples + samples:probe.type:probes,subset = geneNames(Dilution)[1:100])
        write.csv(as.data.frame(coefs.probe(Pset)[1]), "coefs_probe_model_PMMM_liver_probetype_interaction.csv")
        
        Pset <- fitPLM(Dilution, model = PM ~ probes + samples,constraint.type=c(samples="contr.sum"),subset = geneNames(Dilution)[1:100])
        write.csv(as.data.frame(coefs.const(Pset)[1:2]), "coefs_const_model_PM_constraint.csv")
        write.csv(as.data.frame(coefs(Pset)[1:2,]), "coefs_model_PM_constraint.csv")
        
        # Restore the full standard PLM object for comprehensive QC diagnostics
        Pset <- Pset_full
        
        # 4. Generate spatial pseudo-images of weights and residuals
        # 5. Perform Relative Log Expression (RLE) and Normalized Unscaled Standard Error (NUSE) diagnostics
        message("Generating spatial chip images and performing QC diagnostics...")
        pdf("qc_diagnostic_plots.pdf", width = 8, height = 8)
        
        # Spatial images of weights
        image(Pset,which=1)
        image(Pset,which=1,col=gray(0:25/25),add.legend=TRUE)
        image(Pset,which=1,col=gray(25:0/25),add.legend=TRUE)
        
        # Spatial images of residuals
        image(Pset,which=1, type="resids")
        image(Pset,which=1, type="pos.resids")
        image(Pset,which=1, type="neg.resids")
        image(Pset,which=1, type="sign.resids")
        image(Pset,which=1,type="resids",col=pseudoPalette(low="darkgreen",high="magenta",mid="lightgrey"),add.legend=TRUE)
        image(Pset,which=1,type="pos.resids",col=pseudoPalette(low="yellow",high="darkblue"),add.legend=TRUE)
        
        # Relative Log Expression (RLE)
        RLE(Pset,main="RLE for Dilution dataset")
        rle_stats <- RLE(Pset,type="stats")
        write.csv(rle_stats, "rle_statistics.csv")
        
        # Normalized Unscaled Standard Error (NUSE)
        NUSE(Pset,main="NUSE for Dilution dataset")
        nuse_stats <- NUSE(Pset,type="stats")
        write.csv(nuse_stats, "nuse_statistics.csv")
        
        dev.off()
        
        # Save the final full PLMset object
        saveRDS(Pset_full, "Pset_full.rds")
        
        message("Pipeline completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_AFFYPLM_PROBE_LEVEL_MODELING_AND_QC":',
        paste0('    affyPLM: ', as.character(packageVersion('affyPLM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_probe_level_modeling_and_qc.csv versions.yml
    """
}

workflow BIOC_AFFYPLM_PROBE_LEVEL_MODELING_AND_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Dilution ] ]

    main:
    BIOC_AFFYPLM_PROBE_LEVEL_MODELING_AND_QC(ch_input)

    emit:
    tables   = BIOC_AFFYPLM_PROBE_LEVEL_MODELING_AND_QC.out.tables
    plots    = BIOC_AFFYPLM_PROBE_LEVEL_MODELING_AND_QC.out.plots
    objects  = BIOC_AFFYPLM_PROBE_LEVEL_MODELING_AND_QC.out.objects
    versions = BIOC_AFFYPLM_PROBE_LEVEL_MODELING_AND_QC.out.versions
}
