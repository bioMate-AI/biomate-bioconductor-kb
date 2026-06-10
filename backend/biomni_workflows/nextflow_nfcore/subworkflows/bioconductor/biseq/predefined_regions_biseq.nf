#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BiSeq — predefined_regions_biseq
// Test predefined genomic regions (e.g., promoters) for differential methylation using the BiSeq regression framework.
// Input: rrbs, promoters
// Container: quay.io/biocontainers/bioconductor-biseq:1.50.0--r45hdfd78af_0
// R packages: BiSeq, GenomicRanges
// Bioconductor: 3.20 | R: 4.4
// Requires: BiSeq, GenomicRanges
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter raw data by overlaps with predefined regions
//  * 2. [Core Analysis] Assign region identifiers to the cluster.id metadata column

nextflow.enable.dsl = 2

process BIOC_BISEQ_PREDEFINED_REGIONS_BISEQ {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("BiSeq", "GenomicRanges")
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
    library(BiSeq)
    library(GenomicRanges)
    
    # 1. Read the declared user input files from the working directory
    # We expect 'rrbs.rds' (BSraw object) and 'promoters.rds' (GRanges object)
    rrbs <- readRDS("rrbs.rds")
    promoters <- readRDS("promoters.rds")
    
    # 2. Filter raw data by overlaps with predefined regions (Documented Stage 1)
    rrbs.red <- subsetByOverlaps(rrbs, promoters)
    
    # 3. Assign region identifiers to the cluster.id metadata column (Documented Stage 2)
    ov <- findOverlaps(rrbs.red, promoters)
    rowRanges(rrbs.red)\$cluster.id[queryHits(ov)] <- paste0("region_", subjectHits(ov))
    
    # Save the filtered raw object
    saveRDS(rrbs.red, "rrbs_red.rds")
    
    # 4. Proceed with the BiSeq regression framework on the predefined regions
    # Limit coverage to reduce bias from unusually high-coverage sites
    ind.cov <- totalReads(rrbs.red) > 0
    if (sum(ind.cov) > 0) {
      quant <- quantile(totalReads(rrbs.red)[ind.cov], 0.9)
      rrbs.red.lim <- limitCov(rrbs.red, maxCov = quant)
    } else {
      rrbs.red.lim <- rrbs.red
    }
    
    # Smooth the methylation levels within the predefined regions
    predictedMeth <- predictMeth(object = rrbs.red.lim)
    saveRDS(predictedMeth, "predicted_meth.rds")
    
    # Perform beta regression to test for group effect
    # We assume the colData of rrbs contains a 'group' variable
    betaResults <- betaRegression(formula = ~group,
                                  link = "probit",
                                  object = predictedMeth,
                                  type = "BR")
    
    # Save the regression results
    saveRDS(betaResults, "beta_results.rds")
    write.csv(betaResults, "beta_results.csv", row.names = TRUE)
    
    # 5. Attempt cluster/region-wise testing using the spatial correlation framework
    tryCatch({
      # Create a null model for variogram estimation by alternating groups
      predictedMethNull <- predictedMeth
      colData(predictedMethNull)\$group.null <- rep(c(1, 2), length.out = ncol(predictedMethNull))
      
      betaResultsNull <- betaRegression(formula = ~group.null,
                                        link = "probit",
                                        object = predictedMethNull,
                                        type = "BR")
      
      # Estimate and smooth the variogram
      vario <- makeVariogram(betaResultsNull)
      vario.sm <- smoothVariogram(vario, sill = 0.9)
      
      # Replace the null p-values with the actual test p-values
      vario.aux <- makeVariogram(betaResults, make.variogram = FALSE)
      vario.sm\$pValsList <- vario.aux\$pValsList
      
      # Estimate local correlation and test the predefined regions (clusters)
      locCor <- estLocCor(vario.sm)
      clusters.rej <- testClusters(locCor, FDR.cluster = 0.1)
      
      # Save the testing results
      saveRDS(clusters.rej, "rejected_regions.rds")
      if (!is.null(clusters.rej\$clusters.reject)) {
        write.csv(as.data.frame(clusters.rej\$clusters.reject), "rejected_regions.csv", row.names = FALSE)
      }
    }, error = function(e) {
      message("Optional spatial correlation testing step skipped or failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_BISEQ_PREDEFINED_REGIONS_BISEQ":',
        paste0('    BiSeq: ', as.character(packageVersion('BiSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predefined_regions_biseq.csv versions.yml
    """
}

workflow BIOC_BISEQ_PREDEFINED_REGIONS_BISEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rrbs, promoters ] ]

    main:
    BIOC_BISEQ_PREDEFINED_REGIONS_BISEQ(ch_input)

    emit:
    tables   = BIOC_BISEQ_PREDEFINED_REGIONS_BISEQ.out.tables
    plots    = BIOC_BISEQ_PREDEFINED_REGIONS_BISEQ.out.plots
    objects  = BIOC_BISEQ_PREDEFINED_REGIONS_BISEQ.out.objects
    versions = BIOC_BISEQ_PREDEFINED_REGIONS_BISEQ.out.versions
}
