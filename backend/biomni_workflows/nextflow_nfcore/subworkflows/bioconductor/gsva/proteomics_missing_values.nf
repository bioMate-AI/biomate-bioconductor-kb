#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSVA — proteomics_missing_values
// Calculate GSVA or ssGSEA enrichment scores on proteomics data containing missing values (NAs) without imputation.
// Input: proteomics_expression.csv, pathways.gmt
// Container: quay.io/biocontainers/bioconductor-gsva:2.4.4--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, GSVA, SummarizedExperiment, org.Hs.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read gene sets from GMT file using readGMT()
//  * 2. [Core Analysis] Map gene identifiers using gsvaAnnotation()
//  * 3. [Input & Preparation] Build parameter object using gsvaParam() or ssgseaParam() with use="na.rm"
//  * 4. [Core Analysis] Run GSVA or ssGSEA using gsva()

nextflow.enable.dsl = 2

process BIOC_GSVA_PROTEOMICS_MISSING_VALUES {
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
    .bm_deps <- c("GSVA", "GSEABase", "org.Hs.eg.db", "SummarizedExperiment")
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
              library(SummarizedExperiment)
          library(GSVA)
            library(GSEABase)
            library(org.Hs.eg.db)
            
            # 1. Read gene sets from GMT file
            # The documented code uses readGMT(URL). We adapt this to read the local "pathways.gmt" file.
            c7.genesets <- readGMT("pathways.gmt")
            
            # To faithfully reproduce the documented code's variable names, we assign c7.genesets to c7.genesets.filt
            c7.genesets.filt <- c7.genesets
            
            # 2. Read the proteomics expression matrix containing NA values
            # The documented code uses logCPMsWithNAs. We construct this from "proteomics_expression.csv".
            expr_data <- read.csv("proteomics_expression.csv", row.names = 1, check.names = FALSE)
            logCPMsWithNAs <- as.matrix(expr_data)
            
            # Convert to SummarizedExperiment for automatic identifier mapping
            se <- SummarizedExperiment(assays = list(exprs = logCPMsWithNAs))
            
            # Map gene identifiers using gsvaAnnotation
            gsvaAnnotation(se) <- SymbolIdentifier("org.Hs.eg.db")
            
            # 3. Build parameter object and run GSVA with na.use="na.rm"
            gsvapar <- gsvaParam(se, c7.genesets.filt, minSize=5, na.use="na.rm")
            es_gsva_narm <- gsva(gsvapar)
            
            # 4. Build parameter object and run ssGSEA with na.use="na.rm"
            ssgseapar <- ssgseaParam(se, c7.genesets.filt, minSize=5, na.use="na.rm")
            es_ssgsea_narm <- gsva(ssgseapar)
            
            # Write outputs to the working directory
            write.csv(assay(es_gsva_narm), "es_gsva_narm.csv", row.names = TRUE)
            write.csv(assay(es_ssgsea_narm), "es_ssgsea_narm.csv", row.names = TRUE)
            
            saveRDS(es_gsva_narm, "es_gsva_narm.rds")
            saveRDS(es_ssgsea_narm, "es_ssgsea_narm.rds")

    writeLines(c(
        '"BIOC_GSVA_PROTEOMICS_MISSING_VALUES":',
        paste0('    GSVA: ', as.character(packageVersion('GSVA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteomics_missing_values.csv versions.yml
    """
}

workflow BIOC_GSVA_PROTEOMICS_MISSING_VALUES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteomics_expression.csv, pathways.gmt ] ]

    main:
    BIOC_GSVA_PROTEOMICS_MISSING_VALUES(ch_input)

    emit:
    tables   = BIOC_GSVA_PROTEOMICS_MISSING_VALUES.out.tables
    plots    = BIOC_GSVA_PROTEOMICS_MISSING_VALUES.out.plots
    objects  = BIOC_GSVA_PROTEOMICS_MISSING_VALUES.out.objects
    versions = BIOC_GSVA_PROTEOMICS_MISSING_VALUES.out.versions
}
