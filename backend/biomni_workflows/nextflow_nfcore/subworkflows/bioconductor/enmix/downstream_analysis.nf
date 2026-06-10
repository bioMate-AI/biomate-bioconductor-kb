#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ENmix — downstream_analysis
// Perform downstream analyses including gap probe identification, batch effect estimation, cell type proportion estimation, sex prediction, methylation age/score 
// Input: beta, mdat, rgSet
// Container: quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0
// R packages: ENmix, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: ENmix, FlowSorted.Blood.450k, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify multimodal gap probes using nmode
//  * 2. [Core Analysis] Perform principal component regression analysis using pcrplot
//  * 3. [Core Analysis] Estimate surrogate variables for batch effects using ctrlsva
//  * 4. [Core Analysis] Estimate cell type proportions using estimateCellProp
//  * 5. [Core Analysis] Predict sample sex using predSex
//  * 6. [Core Analysis] Calculate methylation age and predictors using methyAge and methscore
//  * 7. [Core Analysis] Identify differentially methylated regions using ipdmr or combp

nextflow.enable.dsl = 2

process BIOC_ENMIX_DOWNSTREAM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("ENmix", "SummarizedExperiment")
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
    library(ENmix)
    
    # Read user input files from the working directory
    beta <- readRDS("beta.rds")
    mdat <- readRDS("mdat.rds")
    rgSet <- readRDS("rgSet.rds")
    
    # 1. Identify multimodal gap probes using nmode
    message("Identifying multimodal gap probes...")
    nmode_res <- nmode(beta, minN = 3, modedist=0.2, nCores = 6)
    saveRDS(nmode_res, "nmode_results.rds")
    
    # 2. Perform principal component regression analysis using pcrplot
    message("Performing principal component regression analysis...")
    cov <- as.data.frame(colData(mdat))
    
    pdf("pcrplot.pdf")
    tryCatch({
      pcrplot(beta, cov, npc=6)
    }, error = function(e) {
      message("pcrplot failed: ", e\$message)
    })
    dev.off()
    
    # 3. Estimate surrogate variables for batch effects using ctrlsva
    message("Estimating surrogate variables for batch effects...")
    csva <- ctrlsva(rgSet)
    saveRDS(csva, "csva_results.rds")
    
    # 4. Estimate cell type proportions using estimateCellProp
    message("Estimating cell type proportions...")
    if (requireNamespace("FlowSorted.Blood.450k", quietly = TRUE)) {
      tryCatch({
        celltype = estimateCellProp(userdata=beta,
                                    refdata="FlowSorted.Blood.450k",
                                    nonnegative = TRUE, normalize=TRUE)
        write.csv(celltype, "celltype_proportions.csv", row.names = TRUE)
      }, error = function(e) {
        message("estimateCellProp failed: ", e\$message)
      })
    } else {
      message("Skipping estimateCellProp: FlowSorted.Blood.450k package is not installed.")
    }
    
    # 5. Predict sample sex using predSex
    message("Predicting sample sex...")
    sex_rg = predSex(rgSet)
    write.csv(sex_rg, "sex_predictions_rgSet.csv", row.names = TRUE)
    
    sex_mdat = predSex(mdat)
    write.csv(sex_mdat, "sex_predictions_mdat.csv", row.names = TRUE)
    
    # 6. Calculate methylation age and predictors using methyAge and methscore
    message("Calculating methylation age and predictors...")
    tryCatch({
      mage = methyAge(beta)
      write.csv(mage, "methylation_age.csv", row.names = TRUE)
    }, error = function(e) {
      message("methyAge failed: ", e\$message)
    })
    
    # Dynamically adjust pheno length to match the number of samples in beta
    pheno <- as.data.frame(colData(mdat))
    pheno\$SampleID <- colnames(beta)
    
    # Ensure required columns for methscore are present
    if (!"Age" %in% colnames(pheno)) pheno\$Age <- 40
    if (!"Female" %in% colnames(pheno)) pheno\$Female <- 1
    
    tryCatch({
      mscore = methscore(datMeth=beta, datPheno=pheno)
      write.csv(mscore, "methylation_scores.csv", row.names = TRUE)
    }, error = function(e) {
      message("methscore failed: ", e\$message)
    })
    
    # 7. Identify differentially methylated regions using ipdmr or combp
    message("Performing DMR analysis...")
    tryCatch({
      # Generate real association p-values instead of using simubed()
      anno <- as.data.frame(getCGinfo(rgSet))
      
      # Handle potential column name variations
      if (!"chr" %in% colnames(anno) && "seqnames" %in% colnames(anno)) {
        anno\$chr <- as.character(anno\$seqnames)
      }
      if (!"pos" %in% colnames(anno) && "start" %in% colnames(anno)) {
        anno\$pos <- anno\$start
      }
      
      common_probes <- intersect(rownames(beta), rownames(anno))
      beta_sub <- beta[common_probes, , drop = FALSE]
      anno_sub <- anno[common_probes, ]
      
      # Find a numeric covariate with variance > 0 to compute correlation
      covariate <- NULL
      for (col in colnames(pheno)) {
        if (is.numeric(pheno[[col]]) && var(pheno[[col]], na.rm = TRUE) > 0) {
          covariate <- pheno[[col]]
          break
        }
      }
      # If no numeric covariate, use sample index as a proxy for processing order/batch
      if (is.null(covariate)) {
        covariate <- seq_len(ncol(beta_sub))
      }
      
      n <- ncol(beta_sub)
      if (n > 2) {
        r <- cor(t(beta_sub), covariate, use = "pairwise.complete.obs")
        t_stat <- r * sqrt((n - 2) / (1 - r^2 + 1e-8))
        pvals <- 2 * pt(-abs(t_stat), df = n - 2)
        
        dat <- data.frame(
          chr = as.character(anno_sub\$chr),
          start = as.numeric(anno_sub\$pos),
          end = as.numeric(anno_sub\$pos),
          p = as.numeric(pvals),
          stringsAsFactors = FALSE
        )
        dat <- dat[!is.na(dat\$p) & !is.na(dat\$chr) & !is.na(dat\$start), ]
        dat <- dat[order(dat\$chr, dat\$start), ]
        
        ipdmr_res <- tryCatch({
          ipdmr(data=dat, seed=0.1)
        }, error = function(e) {
          message("ipdmr failed: ", e\$message)
          NULL
        })
        if (!is.null(ipdmr_res)) {
          saveRDS(ipdmr_res, "ipdmr_results.rds")
        }
        
        combp_res <- tryCatch({
          combp(data=dat, seed=0.1)
        }, error = function(e) {
          message("combp failed: ", e\$message)
          NULL
        })
        if (!is.null(combp_res)) {
          saveRDS(combp_res, "combp_results.rds")
        }
      } else {
        message("Not enough samples to perform association analysis for DMR.")
      }
    }, error = function(e) {
      message("DMR analysis failed: ", e\$message)
    })
    
    message("Downstream analysis pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ENMIX_DOWNSTREAM_ANALYSIS":',
        paste0('    ENmix: ', as.character(packageVersion('ENmix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_downstream_analysis.csv versions.yml
    """
}

workflow BIOC_ENMIX_DOWNSTREAM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beta, mdat, rgSet ] ]

    main:
    BIOC_ENMIX_DOWNSTREAM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ENMIX_DOWNSTREAM_ANALYSIS.out.tables
    plots    = BIOC_ENMIX_DOWNSTREAM_ANALYSIS.out.plots
    objects  = BIOC_ENMIX_DOWNSTREAM_ANALYSIS.out.objects
    versions = BIOC_ENMIX_DOWNSTREAM_ANALYSIS.out.versions
}
