#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SubCellBarCode — exon_centric_classification
// Classify subcellular localization at the exon/peptide level using a pre-built gene-centric model and compare results to detect deviated localizations.
// Input: exon_abundance.tsv, gene_cls_model.rds, gene_cls_output.tsv
// Container: quay.io/biocontainers/bioconductor-subcellbarcode:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SubCellBarCode
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract trained models from the gene-centric classification
//  * 2. [Core Analysis] Predict probabilities for exon-centric data
//  * 3. [Core Analysis] Apply compartment thresholds
//  * 4. [Core Analysis] Apply neighborhood thresholds
//  * 5. [Core Analysis] Merge classifications
//  * 6. [Core Analysis] Compare gene-centric and exon-centric classifications to detect deviations

nextflow.enable.dsl = 2

process BIOC_SUBCELLBARCODE_EXON_CENTRIC_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("SubCellBarCode")
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
    
    # Load required library
    library(SubCellBarCode)
    
    # ----------------------------------------------------------------------
    # Stage 1: Read User Input Files
    # ----------------------------------------------------------------------
    # Read exon-centric quantification data frame
    # Expected format: row names are exon/peptide IDs, columns include Gene_Symbol, 
    # replicate fraction values (e.g., FS1.A.HCC827, FS1.B.HCC827...), and PeptideCount.
    hcc827exon <- read.delim(
      "exon_abundance.tsv", 
      header = TRUE, 
      sep = "\t", 
      row.names = 1, 
      stringsAsFactors = FALSE
    )
    
    # Read trained SVM model list from gene-centric workflow
    cls <- readRDS("gene_cls_model.rds")
    
    # Read gene-centric classification output
    # Expected format: row names are Gene Symbols, columns include NeighborhoodCls, CompartmentCls, etc.
    cls.df <- read.delim(
      "gene_cls_output.tsv", 
      header = TRUE, 
      sep = "\t", 
      row.names = 1, 
      stringsAsFactors = FALSE
    )
    
    # ----------------------------------------------------------------------
    # Stage 2: Extract Models and Compute Thresholds
    # ----------------------------------------------------------------------
    # Extract trained models from the gene-centric classification
    modelA <- cls[[1]]\$model
    modelB <- cls[[2]]\$model
    
    # Extract test predictions to compute thresholds
    test.A <- cls[[1]]\$svm.test.prob.out
    test.B <- cls[[2]]\$svm.test.prob.out
    
    # Compute compartment and neighborhood thresholds
    t.c.df <- computeThresholdCompartment(test.repA = test.A, test.repB = test.B)
    t.n.df <- computeThresholdNeighborhood(test.repA = test.A, test.repB = test.B)
    
    # ----------------------------------------------------------------------
    # Stage 3: Predict Probabilities for Exon-Centric Data
    # ----------------------------------------------------------------------
    exon.cls <- svmExternalData(df = hcc827exon, modelA = modelA, modelB = modelB)
    exon.A <- exon.cls[[1]]
    exon.B <- exon.cls[[2]]
    
    # ----------------------------------------------------------------------
    # Stage 4: Apply Thresholds and Merge Classifications
    # ----------------------------------------------------------------------
    # Apply compartment thresholds
    exon.comp.cls <- applyThresholdCompartment(
      all.repA = exon.A[, 2:17], 
      all.repB = exon.B[, 2:17],
      threshold.df = t.c.df
    )
    
    # Apply neighborhood thresholds
    exon.neigh.cls <- applyThresholdNeighborhood(
      all.repA = exon.A[, 2:17], 
      all.repB = exon.B[, 2:17], 
      threshold.df = t.n.df
    )
    
    # Merge classifications
    exon.cls.df <- mergeCls(
      compartmentCls = exon.comp.cls, 
      neighborhoodCls = exon.neigh.cls
    )
    
    # Align row order and append metadata
    exon.cls.df <- exon.cls.df[rownames(exon.A), ]
    exon.cls.df\$GeneSymbol <- exon.A\$Gene_Symbol
    exon.cls.df\$PeptideCount <- hcc827exon\$PeptideCount
    
    # ----------------------------------------------------------------------
    # Stage 5: Compare Gene-Centric and Exon-Centric Classifications
    # ----------------------------------------------------------------------
    comp.df <- compareCls(geneCls = cls.df, exonCls = exon.cls.df)
    
    # ----------------------------------------------------------------------
    # Stage 6: Write Outputs
    # ----------------------------------------------------------------------
    # Save the exon-centric classification results
    write.table(
      exon.cls.df, 
      file = "exon_classification_output.tsv", 
      sep = "\t", 
      quote = FALSE, 
      col.names = NA
    )
    
    # Save the comparison results (deviated localizations)
    write.table(
      comp.df, 
      file = "exon_gene_comparison.tsv", 
      sep = "\t", 
      quote = FALSE, 
      col.names = NA
    )
    
    # Save the full workspace/objects for downstream exploration
    saveRDS(exon.cls.df, file = "exon_cls_df.rds")
    saveRDS(comp.df, file = "comp_df.rds")

    writeLines(c(
        '"BIOC_SUBCELLBARCODE_EXON_CENTRIC_CLASSIFICATION":',
        paste0('    SubCellBarCode: ', as.character(packageVersion('SubCellBarCode')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_exon_centric_classification.csv versions.yml
    """
}

workflow BIOC_SUBCELLBARCODE_EXON_CENTRIC_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exon_abundance.tsv, gene_cls_model.rds, gene_cls_output.tsv ] ]

    main:
    BIOC_SUBCELLBARCODE_EXON_CENTRIC_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_SUBCELLBARCODE_EXON_CENTRIC_CLASSIFICATION.out.tables
    plots    = BIOC_SUBCELLBARCODE_EXON_CENTRIC_CLASSIFICATION.out.plots
    objects  = BIOC_SUBCELLBARCODE_EXON_CENTRIC_CLASSIFICATION.out.objects
    versions = BIOC_SUBCELLBARCODE_EXON_CENTRIC_CLASSIFICATION.out.versions
}
