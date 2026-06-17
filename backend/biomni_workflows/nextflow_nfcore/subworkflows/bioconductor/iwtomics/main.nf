#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IWTomics — interval_wise_testing
// Import genomic regions and feature measurements, optionally smooth the data, perform interval-wise permutation testing, and visualize the results.
// Input: datasets.txt, features_datasetsTable.txt, BED or text files
// Container: quay.io/biocontainers/bioconductor-iwtomics:1.34.1--r45hdfd78af_0
// R packages: IWTomics
// Bioconductor: 3.20 | R: 4.4
// Requires: IWTomics
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import and align genomic regions and feature measurements using IWTomicsData
//  * 2. [Core Analysis] (Optional) Smooth curves or change resolution using smooth
//  * 3. [Visualization & Output] Visualize raw feature measurements using plot
//  * 4. [Core Analysis] Perform Interval-Wise Testing using IWTomicsTest
//  * 5. [Core Analysis] Extract adjusted p-values using adjusted_pval
//  * 6. [Visualization & Output] Visualize test results using plotTest and plotSummary

nextflow.enable.dsl = 2

process BIOC_IWTOMICS_INTERVAL_WISE_TESTING {
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
    .bm_deps <- c("IWTomics")
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
                
    library(IWTomics)
    
    # 1. Import and align genomic regions and feature measurements
    datasets <- read.table("datasets.txt", sep="\t", header=TRUE, stringsAsFactors=FALSE)
    features_datasetsTable <- read.table("features_datasetsTable.txt", sep="\t", header=TRUE, stringsAsFactors=FALSE)
    features_datasetsBED <- features_datasetsTable
    
    feature_cols <- 3:ncol(features_datasetsTable)
    
    regionsFeatures=IWTomicsData(datasets\$regionFile,
        features_datasetsTable[, feature_cols, drop=FALSE],alignment='center',
        id_regions=datasets\$id,name_regions=datasets\$name,
        id_features=features_datasetsBED\$id,
        name_features=features_datasetsBED\$name,
        path='.')
    
    saveRDS(regionsFeatures, "regionsFeatures.rds")
    
    # 2. Smooth curves or change resolution
    regionsFeatures_smooth=smooth(regionsFeatures,type='locpoly')
    saveRDS(regionsFeatures_smooth, "regionsFeatures_smooth.rds")
    
    # 3. Visualize raw feature measurements
    pdf("plot_pairs.pdf")
    plot(regionsFeatures,type='pairs')
    dev.off()
    
    feature_ids <- features_datasetsBED\$id
    feat1 <- feature_ids[1]
    feat2 <- feature_ids[min(2, length(feature_ids))]
    
    pdf("plot_curves.pdf")
    plot(regionsFeatures,type='curves',
         N_regions=lengthRegions(regionsFeatures),
         id_features_subset=feat1,cex.main=2,cex.axis=1.2,cex.lab=1.2)
    dev.off()
    
    pdf("plot_boxplot.pdf")
    plot(regionsFeatures,type='boxplot',
         id_features_subset=feat2,cex.main=2,cex.axis=1.2,cex.lab=1.2)
    dev.off()
    
    # 4. Perform Interval-Wise Testing
    set.seed(123) # Set seed for reproducibility of permutation test
    
    region_ids <- datasets\$id
    id_reg1 <- region_ids[-length(region_ids)]
    id_reg2 <- rep(region_ids[length(region_ids)], length(id_reg1))
    
    result2_mean=IWTomicsTest(regionsFeatures,
                              id_region1=id_reg1,
                              id_region2=id_reg2)
    saveRDS(result2_mean, "result2_mean.rds")
    
    # 5. Extract adjusted p-values
    adj_pvals <- adjusted_pval(result2_mean)
    saveRDS(adj_pvals, "adjusted_pvals.rds")
    
    df_list <- list()
    for (test_name in names(adj_pvals)) {
      for (feat_name in names(adj_pvals[[test_name]])) {
        p_vec <- adj_pvals[[test_name]][[feat_name]]
        df_list[[paste(test_name, feat_name, sep="_")]] <- data.frame(
          Test = test_name,
          Feature = feat_name,
          Window = seq_along(p_vec),
          Adjusted_pValue = p_vec
        )
      }
    }
    if (length(df_list) > 0) {
      df_pvals <- do.call(rbind, df_list)
      write.csv(df_pvals, "adjusted_pvals.csv", row.names = FALSE)
    }
    
    # 6. Visualize test results
    pdf("plot_test.pdf")
    plotTest(result2_mean,alpha=0.05,id_features_subset=feat1)
    dev.off()
    
    pdf("plot_summary.pdf")
    plotSummary(result2_mean,alpha=0.05,groupby='feature',align_lab='Center')
    dev.off()

    writeLines(c(
        '"BIOC_IWTOMICS_INTERVAL_WISE_TESTING":',
        paste0('    IWTomics: ', as.character(packageVersion('IWTomics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interval_wise_testing.csv versions.yml
    """
}

workflow BIOC_IWTOMICS_INTERVAL_WISE_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ datasets.txt, features_datasetsTable.txt, BED or text files ] ]

    main:
    BIOC_IWTOMICS_INTERVAL_WISE_TESTING(ch_input)

    emit:
    tables   = BIOC_IWTOMICS_INTERVAL_WISE_TESTING.out.tables
    plots    = BIOC_IWTOMICS_INTERVAL_WISE_TESTING.out.plots
    objects  = BIOC_IWTOMICS_INTERVAL_WISE_TESTING.out.objects
    versions = BIOC_IWTOMICS_INTERVAL_WISE_TESTING.out.versions
}
