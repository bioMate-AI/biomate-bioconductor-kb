#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DaMiRseq — standard_pipeline_and_classification
// Perform raw count normalization, sample filtering, surrogate variable adjustment, feature selection, and ensemble learning classification.
// Input: count_data.txt, covariate_data.txt
// Container: quay.io/biocontainers/bioconductor-damirseq:2.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DaMiRseq, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import data and create a SummarizedExperiment object
//  * 2. [Core Analysis] Filter and normalize counts
//  * 3. [Core Analysis] Filter out low-correlation samples
//  * 4. [Core Analysis] Identify and adjust for surrogate variables
//  * 5. [Core Analysis] Transpose and perform feature selection and reduction
//  * 6. [Core Analysis] Sort and select the best predictors
//  * 7. [Core Analysis] Train and evaluate an ensemble classifier

nextflow.enable.dsl = 2

process BIOC_DAMIRSEQ_STANDARD_PIPELINE_AND_CLASSIFICATION {
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
    .bm_deps <- c("DaMiRseq", "SummarizedExperiment")
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
        library(DaMiRseq)
        library(SummarizedExperiment)
        
        # 1. Import data and create a SummarizedExperiment object
        count_data <- read.delim("count_data.txt", header = TRUE, row.names = 1)
        covariate_data <- read.delim("covariate_data.txt", header = TRUE, row.names = 1, stringsAsFactors = TRUE)
        SE <- DaMiR.makeSE(count_data, covariate_data)
        
        # 2. Filter and normalize counts
        data_norm <- DaMiR.normalization(SE, minCounts=10, fSample=0.7, hyper = "yes", th.cv=3)
        
        # 3. Filter out low-correlation samples
        data_filt <- DaMiR.sampleFilt(data_norm, th.corr=0.9)
        
        # 4. Identify and adjust for surrogate variables
        sv <- DaMiR.SV(data_filt)
        data_adjust<-DaMiR.SVadjust(data_filt, sv, n.sv=ncol(sv))
        
        # Open PDF device to save all diagnostic and results plots
        pdf("DaMiRseq_pipeline_plots.pdf", width = 10, height = 8)
        
        DaMiR.Allplot(data_adjust, colData(data_adjust))
        
        # 5. Transpose and perform feature selection and reduction
        set.seed(12345)
        data_clean<-DaMiR.transpose(assay(data_adjust))
        df<-colData(data_adjust)
        data_reduced <- DaMiR.FSelect(data_clean, df, th.corr=0.4)
        data_reduced <- DaMiR.FReduct(data_reduced\$data)
        
        DaMiR.MDSplot(data_reduced, df)
        
        # 6. Sort and select the best predictors
        df.importance <- DaMiR.FSort(data_reduced, df)
        selected_features <- DaMiR.FBest(data_reduced, ranking=df.importance, n.pred = 5)
        
        DaMiR.Clustplot(selected_features\$data, df)
        
        # Close the PDF device
        dev.off()
        
        # 7. Train and evaluate an ensemble classifier
        Classification_res <- DaMiR.EnsembleLearning(selected_features\$data, classes=df\$class, fSample.tr = 0.5, fSample.tr.w = 0.5, iter = 30)
        
        # Save meaningful results to files
        write.csv(df.importance, "feature_importance.csv", row.names = TRUE)
        write.csv(selected_features\$data, "selected_features_data.csv", row.names = TRUE)
        saveRDS(Classification_res, "classification_results.rds")
        saveRDS(data_adjust, "normalized_adjusted_SE.rds")

    writeLines(c(
        '"BIOC_DAMIRSEQ_STANDARD_PIPELINE_AND_CLASSIFICATION":',
        paste0('    DaMiRseq: ', as.character(packageVersion('DaMiRseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_pipeline_and_classification.csv versions.yml
    """
}

workflow BIOC_DAMIRSEQ_STANDARD_PIPELINE_AND_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_data.txt, covariate_data.txt ] ]

    main:
    BIOC_DAMIRSEQ_STANDARD_PIPELINE_AND_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_DAMIRSEQ_STANDARD_PIPELINE_AND_CLASSIFICATION.out.tables
    plots    = BIOC_DAMIRSEQ_STANDARD_PIPELINE_AND_CLASSIFICATION.out.plots
    objects  = BIOC_DAMIRSEQ_STANDARD_PIPELINE_AND_CLASSIFICATION.out.objects
    versions = BIOC_DAMIRSEQ_STANDARD_PIPELINE_AND_CLASSIFICATION.out.versions
}
