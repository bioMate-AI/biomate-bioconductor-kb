#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Heatplus — double_annotated_heatmap
// Generate a highly customized heatmap with both column (sample) and row (feature) annotations.
// Input: exprs_matrix.csv, sample_metadata.csv, feature_metadata.csv
// Container: quay.io/biocontainers/bioconductor-heatplus:3.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Heatplus
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare sample and feature annotation data frames by
//  * 2. [Visualization & Output] Generate double-annotated heatmap using annHeatmap2 and
//  * 3. [Visualization & Output] Generate double-annotated heatmap with custom label rows
//  * 4. [Visualization & Output] Generate double-annotated heatmap excluding reference
//  * 5. [Visualization & Output] Convert annotation data using convAnnData for manual

nextflow.enable.dsl = 2

process BIOC_HEATPLUS_DOUBLE_ANNOTATED_HEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("Biobase", "Heatplus")
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
        library(Biobase)
        library(Heatplus)
        
        # --- Prepare sample and feature annotation data frames by ---
        exprs_mat = as.matrix(read.csv("exprs_matrix.csv", row.names=1))
        sample_meta = read.csv("sample_metadata.csv", row.names=1)
        feature_meta = read.csv("feature_metadata.csv", row.names=1)
        
        # Align samples and features to ensure consistency
        common_samples = intersect(colnames(exprs_mat), rownames(sample_meta))
        exprs_mat = exprs_mat[, common_samples, drop=FALSE]
        sample_meta = sample_meta[common_samples, , drop=FALSE]
        
        common_features = intersect(rownames(exprs_mat), rownames(feature_meta))
        exprs_mat = exprs_mat[common_features, , drop=FALSE]
        feature_meta = feature_meta[common_features, , drop=FALSE]
        
        # Construct ExpressionSet to match the documented code's use of exprs() and pData()
        pheno_data = new("AnnotatedDataFrame", data=sample_meta)
        exdat2 = new("ExpressionSet", exprs=exprs_mat, phenoData=pheno_data)
        annFeatures = feature_meta
        
        # Open PDF device to save the heatmaps
        pdf("double_annotated_heatmaps.pdf", width=12, height=12)
        
        # --- Generate double-annotated heatmap using annHeatmap2 and ---
        ann4 = annHeatmap2(exprs(exdat2), ann=list(Col=list(data=pData(exdat2)), Row=list(data=annFeatures)))
        plot(ann4)
        saveRDS(ann4, "ann4.rds")
        
        # --- Generate double-annotated heatmap with custom label rows ---
        ann4a = annHeatmap2(exprs(exdat2), ann=list(Col=list(data=pData(exdat2)), Row=list(data=annFeatures)), labels=list(Row=list(nrow=7), Col=list(nrow=2)))
        plot(ann4a)
        saveRDS(ann4a, "ann4a.rds")
        
        # --- Generate double-annotated heatmap excluding reference ---
        ann4b = annHeatmap2(exprs(exdat2), ann=list( inclRef=FALSE, Col=list(data=pData(exdat2)), Row=list(data=annFeatures)   ), labels=list(Row=list(nrow=7), Col=list(nrow=2)))
        plot(ann4b, widths=c(2,5,1), heights=c(2,5,1))
        saveRDS(ann4b, "ann4b.rds")
        
        # --- Convert annotation data using convAnnData for manual ---
        tryCatch({
            ann1 = convAnnData(pData(exdat2), inclRef=FALSE)
            ann2 = convAnnData(annFeatures, inclRef=FALSE)
            ann4c = annHeatmap2(exprs(exdat2), ann=list(asIs=TRUE, Col=list(data=ann1), Row=list(data=ann2)), labels=list(Row=list(nrow=7), Col=list(nrow=2)))
            plot(ann4c)
            saveRDS(ann4c, "ann4c.rds")
        }, error = function(e) {
            message("Skipping the manual convAnnData step (ann4c) due to column mismatch or data structure: ", e\$message)
        })
        
        # Close PDF device
        dev.off()

    writeLines(c(
        '"BIOC_HEATPLUS_DOUBLE_ANNOTATED_HEATMAP":',
        paste0('    Heatplus: ', as.character(packageVersion('Heatplus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_double_annotated_heatmap.csv versions.yml
    """
}

workflow BIOC_HEATPLUS_DOUBLE_ANNOTATED_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs_matrix.csv, sample_metadata.csv, feature_metadata.csv ] ]

    main:
    BIOC_HEATPLUS_DOUBLE_ANNOTATED_HEATMAP(ch_input)

    emit:
    tables   = BIOC_HEATPLUS_DOUBLE_ANNOTATED_HEATMAP.out.tables
    plots    = BIOC_HEATPLUS_DOUBLE_ANNOTATED_HEATMAP.out.plots
    objects  = BIOC_HEATPLUS_DOUBLE_ANNOTATED_HEATMAP.out.objects
    versions = BIOC_HEATPLUS_DOUBLE_ANNOTATED_HEATMAP.out.versions
}
