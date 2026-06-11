#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OLIN — statistical_bias_assessment
// Statistically assess and detect intensity-dependent, spatial, pin-dependent, and plate-dependent biases in microarray data using ANOVA and permutation tests.
// Input: microarray_data.RData
// Container: quay.io/biocontainers/bioconductor-olin:1.88.0--r45hdfd78af_0
// R packages: OLIN, marray
// Bioconductor: 3.20 | R: 4.4
// Requires: OLIN, marray
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate neighborhood correlation on intensity and spatial scales
//  * 2. [Core Analysis] Perform ANOVA to test for intensity-dependent bias
//  * 3. [Core Analysis] Perform ANOVA to test for spatial block-wise bias
//  * 4. [Core Analysis] Perform ANOVA to test for pin- and plate-dependent biases
//  * 5. [Visualization & Output] Run permutation tests to calculate False Discovery Rates (FDR) for intensity and spatial biases and plot the significant biased re

nextflow.enable.dsl = 2

process BIOC_OLIN_STATISTICAL_BIAS_ASSESSMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("OLIN", "marray")
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
        
    library(OLIN)
    library(marray)
    
    # -----------------------------------------------------------------------------
    # 1. Load User Input and Pre-process
    # -----------------------------------------------------------------------------
    if (!file.exists("microarray_data.RData")) {
      stop("Error: Required input file 'microarray_data.RData' not found in the working directory.")
    }
    
    load("microarray_data.RData")
    
    # Identify the marrayRaw or marrayNorm object in the loaded environment
    objs <- ls()
    marray_idx <- which(sapply(objs, function(x) inherits(get(x), c("marrayRaw", "marrayNorm"))))
    if (length(marray_idx) == 0) {
      stop("Error: No marrayRaw or marrayNorm object found in 'microarray_data.RData'.")
    }
    sw_name <- objs[marray_idx[1]]
    sw <- get(sw_name)
    message("Loaded object '", sw_name, "' as 'sw'.")
    
    # Ensure layout slots are populated to prevent downstream failures
    if (length(maNgc(sw)) == 0 || is.na(maNgc(sw))) maNgc(sw) <- 4
    if (length(maNgr(sw)) == 0 || is.na(maNgr(sw))) maNgr(sw) <- 4
    if (length(maNsc(sw)) == 0 || is.na(maNsc(sw))) maNsc(sw) <- 10
    if (length(maNsr(sw)) == 0 || is.na(maNsr(sw))) maNsr(sw) <- 10
    
    # Ensure sw.olin exists; if not, generate it using olin()
    if (!exists("sw.olin")) {
      message("sw.olin not found. Generating sw.olin using olin()...")
      sw.olin <- olin(sw[,1], X=NA, Y=NA)
    }
    
    # Open PDF device to capture all generated plots
    pdf("statistical_bias_assessment_plots.pdf", width = 8, height = 8)
    
    # -----------------------------------------------------------------------------
    # 2. Calculate Neighborhood Correlation on Intensity and Spatial Scales
    # -----------------------------------------------------------------------------
    A <- maA(sw[,1])
    M <- maM(sw[,1])
    Mav <- ma.vector(A,M,av="median",delta=50)
    cor_int <- cor(Mav,M,use="pairwise.complete.obs")
    
    MM <-  v2m(maM(sw)[,1],Ngc=maNgc(sw),Ngr=maNgr(sw),Nsc=maNsc(sw),Nsr=maNsr(sw),visu=FALSE)
    MMav <- ma.matrix(MM,av="median",delta= 2,edgeNA=FALSE)
    Mav <- m2v(MMav,Ngc=maNgc(sw),Ngr=maNgr(sw),Nsc=maNsc(sw),Nsr=maNsr(sw),visu=FALSE)
    cor_spat <- cor(Mav,M,use="pairwise.complete.obs")
    
    # Save correlation results
    cor_df <- data.frame(
      Scale = c("Intensity", "Spatial"),
      Correlation = c(cor_int[1,1], cor_spat[1,1])
    )
    write.csv(cor_df, "neighborhood_correlations.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # 3. Perform ANOVA to Test for Intensity, Pin, and Plate Biases
    # -----------------------------------------------------------------------------
    sink("anova_results.txt")
    cat("=== ANOVA INTENSITY-DEPENDENT BIAS ===\n")
    print(anovaint(sw,index=1,N=10))
    cat("\n")
    
    cat("=== ANOVA PIN-DEPENDENT BIAS ===\n")
    print(anovapin(sw.olin,index=1))
    cat("\n")
    
    cat("=== ANOVA PLATE-DEPENDENT BIAS ===\n")
    print(anovaplate(sw.olin,index=1))
    sink()
    
    # -----------------------------------------------------------------------------
    # 4. Perform ANOVA to Test for Spatial Block-wise Bias
    # -----------------------------------------------------------------------------
    s <-  anovaspatial(sw,index=1,xN=8,yN=8,visu=TRUE)
    
    # -----------------------------------------------------------------------------
    # 5. Run Permutation Tests for FDR and Plot Significant Biased Regions
    # -----------------------------------------------------------------------------
    FDR_int <- fdr.int(maA(sw)[,1],maM(sw)[,1],delta=50,N=10,av="median")
    sigint.plot(maA(sw)[,1],maM(sw)[,1],FDR_int\$FDRp,FDR_int\$FDRn,c(-5,-5))
    
    M <- v2m(maM(sw)[,1],Ngc=maNgc(sw),Ngr=maNgr(sw),
                    Nsc=maNsc(sw),Nsr=maNsr(sw),main="MXY plot of SW-array 1")
    FDR_spat <- fdr.spatial(M,delta=2,N=10,av="median",edgeNA=TRUE)
    sigxy.plot(FDR_spat\$FDRp,FDR_spat\$FDRn,color.lim=c(-5,5),main="FDR")
    
    dev.off()
    
    # Save FDR objects for downstream analysis
    saveRDS(FDR_int, "fdr_intensity.rds")
    saveRDS(FDR_spat, "fdr_spatial.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_OLIN_STATISTICAL_BIAS_ASSESSMENT":',
        paste0('    OLIN: ', as.character(packageVersion('OLIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_statistical_bias_assessment.csv versions.yml
    """
}

workflow BIOC_OLIN_STATISTICAL_BIAS_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ microarray_data.RData ] ]

    main:
    BIOC_OLIN_STATISTICAL_BIAS_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_OLIN_STATISTICAL_BIAS_ASSESSMENT.out.tables
    plots    = BIOC_OLIN_STATISTICAL_BIAS_ASSESSMENT.out.plots
    objects  = BIOC_OLIN_STATISTICAL_BIAS_ASSESSMENT.out.objects
    versions = BIOC_OLIN_STATISTICAL_BIAS_ASSESSMENT.out.versions
}
