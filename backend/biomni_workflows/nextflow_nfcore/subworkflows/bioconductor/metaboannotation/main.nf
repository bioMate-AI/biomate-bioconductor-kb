#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnnotation — match_values
// Match experimental LC-MS features (m/z and retention times) from data.frames, SummarizedExperiment, or QFeatures objects against a reference database of exact m
// Input: ms1_features.txt, LipidMaps_CompDB.txt
// Container: quay.io/biocontainers/bioconductor-metaboannotation:1.14.0--r45hdfd78af_0
// R packages: AnnotationHub, MetaboAnnotation, microbenchmark, QFeatures, Spectra, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnnotation, QFeatures, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load query and target datasets
//  * 2. [Input & Preparation] Define matching parameters using Mass2MzParam or Mass2MzRtParam
//  * 3. [Core Analysis] Perform matching using matchValues()
//  * 4. [Core Analysis] Inspect and extract matches using matchedData(), whichQuery(), and whichTarget()

nextflow.enable.dsl = 2

process BIOC_METABOANNOTATION_MATCH_VALUES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("AnnotationHub", "MetaboAnnotation", "microbenchmark", "QFeatures", "Spectra", "SummarizedExperiment")
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
    library(MetaboAnnotation)
    library(SummarizedExperiment)
    library(QFeatures)
    
    # 1. Load query and target datasets from the working directory
    ms1_features <- read.table("ms1_features.txt", header = TRUE, sep = "\t")
    target_df <- read.table("LipidMaps_CompDB.txt", header = TRUE, sep = "\t")
    
    # Determine subset size safely (up to 100 rows as in the documented code)
    n_limit <- min(100, nrow(ms1_features))
    ms1_subset <- ms1_features[1:n_limit, ]
    
    # 2. Define matching parameters using Mass2MzParam and perform matching
    parm <- Mass2MzParam(adducts = c("[M+H]+", "[M+Na]+"), tolerance = 0.005, ppm = 0)
    matched_features <- matchValues(ms1_subset, target_df, parm)
    
    # Inspect and extract matches (reproducing documented calls)
    head(query(matched_features))
    head(target(matched_features))
    whichQuery(matched_features)
    whichTarget(matched_features)
    colnames(matched_features)
    m_data1 <- matchedData(matched_features)
    matched_features\$target_name
    
    # Save first stage results
    write.csv(as.data.frame(m_data1), "matched_features_mz.csv", row.names = FALSE)
    
    # 3. Matching of m/z and retention time values
    set.seed(123)
    target_df\$rtime <- sample(ms1_subset\$rtime, nrow(target_df), replace = TRUE) + 2
    
    parm_rt <- Mass2MzRtParam(adducts = c("[M+H]+", "[M+Na]+"), tolerance = 0.005, ppm = 0, toleranceRt = 10)
    matched_features_rt <- matchValues(ms1_subset, target_df, param = parm_rt, rtColname = "rtime")
    
    m_data2 <- matchedData(matched_features_rt)[whichQuery(matched_features_rt), ]
    
    # Save second stage results
    write.csv(as.data.frame(m_data2), "matched_features_mz_rt.csv", row.names = FALSE)
    
    # 4. Matching of SummarizedExperiment objects
    se <- SummarizedExperiment(
      assays = matrix(rnorm(nrow(ms1_features) * 4), ncol = 4, dimnames = list(NULL, c("A", "B", "C", "D"))),
      rowData = ms1_features
    )
    
    parm_se <- Mass2MzParam(adducts = c("[M+H]+", "[M+Na]+"), tolerance = 0.005, ppm = 0)
    matched_features_se <- matchValues(se, target_df, param = parm_se)
    
    colnames(matched_features_se)
    m_data_se <- matchedData(matched_features_se)
    
    matched_sub <- matched_features_se[whichQuery(matched_features_se)]
    MetaboAnnotation::query(matched_sub)
    
    # Save SummarizedExperiment matching results
    write.csv(as.data.frame(m_data_se), "matched_se_data.csv", row.names = FALSE)
    saveRDS(matched_features_se, "matched_se.rds")
    
    # 5. Matching of QFeatures objects
    qf <- QFeatures(list(features = se))
    matched_qf <- matchValues(qf, target_df, param = parm_se, queryAssay = "features")
    
    colnames(matched_qf)
    m_data_qf <- matchedData(matched_qf)
    
    # Save QFeatures matching results
    write.csv(as.data.frame(m_data_qf), "matched_qf_data.csv", row.names = FALSE)
    saveRDS(matched_qf, "matched_qf.rds")

    writeLines(c(
        '"BIOC_METABOANNOTATION_MATCH_VALUES":',
        paste0('    MetaboAnnotation: ', as.character(packageVersion('MetaboAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_match_values.csv versions.yml
    """
}

workflow BIOC_METABOANNOTATION_MATCH_VALUES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ms1_features.txt, LipidMaps_CompDB.txt ] ]

    main:
    BIOC_METABOANNOTATION_MATCH_VALUES(ch_input)

    emit:
    tables   = BIOC_METABOANNOTATION_MATCH_VALUES.out.tables
    plots    = BIOC_METABOANNOTATION_MATCH_VALUES.out.plots
    objects  = BIOC_METABOANNOTATION_MATCH_VALUES.out.objects
    versions = BIOC_METABOANNOTATION_MATCH_VALUES.out.versions
}
