#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scuttle — feature_qc_and_data_transformation
// Calculate feature-level QC metrics, compute size-factor adjusted average expression, resolve duplicate gene symbols, and format data into data.frames for downst
// Input: sce, sce.ens
// Container: quay.io/biocontainers/bioconductor-scuttle:1.20.0--r45ha27e39d_0
// R packages: SingleCellExperiment, BiocStyle, scran, scRNAseq, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scuttle
// QC: outlier detection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute feature-level QC metrics using perFeatureQCMetrics
//  * 2. [Core Analysis] Calculate size-factor adjusted average expression using calculateAverage
//  * 3. [Core Analysis] Resolve duplicate or missing gene symbols using uniquifyFeatureNames
//  * 4. [Core Analysis] Convert cell or feature data to data.frames using makePerCellDF and makePerFeatureDF

nextflow.enable.dsl = 2

process BIOC_SCUTTLE_FEATURE_QC_AND_DATA_TRANSFORMATION {
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
    .bm_deps <- c("SingleCellExperiment", "BiocStyle", "scran", "scRNAseq", "scuttle", "SummarizedExperiment")
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
        library(scuttle)
        library(SummarizedExperiment)
        
        # Read user input files from the working directory
        sce <- readRDS("sce.rds")
        sce.ens <- readRDS("sce.ens.rds")
        
        # 1. Compute feature-level QC metrics
        per.feat <- perFeatureQCMetrics(sce)
        summary(per.feat\$mean)
        summary(per.feat\$detected)
        
        # Save feature-level QC metrics
        write.csv(as.data.frame(per.feat), "per_feature_qc_metrics.csv", row.names=TRUE)
        
        # 2. Calculate size-factor adjusted average expression
        ave <- calculateAverage(sce)
        summary(ave)
        
        # Save average expression
        saveRDS(ave, "average_expression.rds")
        
        # 3. Resolve duplicate or missing gene symbols
        if ("originalName" %in% colnames(rowData(sce.ens))) {
            symbols <- rowData(sce.ens)\$originalName
        } else {
            symbols <- rownames(sce.ens)
        }
        
        rownames(sce.ens) <- uniquifyFeatureNames(
            rownames(sce.ens), symbols
        )
        
        # Save the updated SingleCellExperiment object
        saveRDS(sce.ens, "sce_ens_uniquified.rds")
        
        # 4. Convert cell or feature data to data.frames
        out <- makePerCellDF(sce, features=rownames(sce)[1], assay.type="counts")
        write.csv(out, "per_cell_df.csv", row.names=TRUE)
        
        out2 <- makePerFeatureDF(
            sce,
            cells=head(colnames(sce), 4),
            assay.type="counts"
        )
        write.csv(out2, "per_feature_df.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_SCUTTLE_FEATURE_QC_AND_DATA_TRANSFORMATION":',
        paste0('    scuttle: ', as.character(packageVersion('scuttle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_qc_and_data_transformation.csv versions.yml
    """
}

workflow BIOC_SCUTTLE_FEATURE_QC_AND_DATA_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, sce.ens ] ]

    main:
    BIOC_SCUTTLE_FEATURE_QC_AND_DATA_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_SCUTTLE_FEATURE_QC_AND_DATA_TRANSFORMATION.out.tables
    plots    = BIOC_SCUTTLE_FEATURE_QC_AND_DATA_TRANSFORMATION.out.plots
    objects  = BIOC_SCUTTLE_FEATURE_QC_AND_DATA_TRANSFORMATION.out.objects
    versions = BIOC_SCUTTLE_FEATURE_QC_AND_DATA_TRANSFORMATION.out.versions
}
