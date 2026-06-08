#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSVA — proteomics_missing_values
// Calculate GSVA or ssGSEA enrichment scores on proteomics data containing missing values (NAs) without imputation.
// Input: proteomics_expression.csv, pathways.gmt
// Container: quay.io/biocontainers/bioconductor-gsva:2.4.4--r45h01b2380_0
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
            
            # Load required libraries
            library(GSVA)
            library(GSEABase)
            library(org.Hs.eg.db)
            library(SummarizedExperiment)
            
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
