#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Category — chrom_band_hypergeometric_test
// Perform standard and conditional hypergeometric testing for over-representation of chromosome bands in a list of selected genes.
// Input: bcrAblOrNeg.RData
// Container: quay.io/biocontainers/bioconductor-category:2.76.0--r45hdfd78af_0
// Requires: Biobase, Category, annotate, genefilter, hgu95av2.db, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Filter the ExpressionSet and define the gene universe and selected gene list
//  * 2. [Input & Preparation] Create a ChrMapHyperGParams parameter object
//  * 3. [Core Analysis] Run the hypergeometric test using hyperGTest
//  * 4. [Visualization & Output] Summarize results using summary

nextflow.enable.dsl = 2

process BIOC_CATEGORY_CHROM_BAND_HYPERGEOMETRIC_TEST {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    library(Biobase)
    library(annotate)
    library(hgu95av2.db)
    library(genefilter)
    library(limma)
    library(Category)
    
    # 1. Load the input data
    # The pipeline expects 'bcrAblOrNeg.RData' in the working directory,
    # which contains the ExpressionSet object 'bcrAblOrNeg'.
    load("bcrAblOrNeg.RData")
    
    # Ensure the annotation is set correctly (typically "hgu95av2" for this dataset)
    if (annotation(bcrAblOrNeg) == "") {
      annotation(bcrAblOrNeg) <- "hgu95av2"
    }
    
    # Ensure mol.biol is a factor
    bcrAblOrNeg\$mol.biol <- factor(bcrAblOrNeg\$mol.biol)
    
    # Retrieve annotation maps
    annType <- c("db", "env")
    entrezMap <- getAnnMap("ENTREZID", annotation(bcrAblOrNeg),
                           type=annType, load=TRUE)
    symbolMap <- getAnnMap("SYMBOL", annotation(bcrAblOrNeg),
                           type=annType, load=TRUE)
    bandMap <- getAnnMap("MAP", annotation(bcrAblOrNeg),
                         type=annType, load=TRUE)
    
    # 2. Filter the ExpressionSet and define the gene universe and selected gene list
    filterAns <- nsFilter(bcrAblOrNeg,
                          require.entrez = TRUE, 
                          remove.dupEntrez = TRUE, 
                          var.func = IQR, var.cutoff = 0.5)
    nsFiltered <- filterAns\$eset
    
    hasSYM <- sapply(mget(featureNames(nsFiltered), symbolMap, ifnotfound=NA),
                     function(x) length(x) > 0 && !is.na(x[1]))
    hasMAP <- sapply(mget(featureNames(nsFiltered), bandMap, ifnotfound=NA),
                     function(x) length(x) > 0 && !is.na(x[1]))
    nsFiltered <- nsFiltered[hasSYM & hasMAP, ]
    
    affyUniverse <- featureNames(nsFiltered)
    entrezUniverse <- unlist(mget(affyUniverse, entrezMap))
    names(affyUniverse) <- entrezUniverse
    
    # Check for duplicate Entrez IDs in the universe
    if (any(duplicated(entrezUniverse))) {
      stop("error in gene universe: can't have duplicate Entrez Gene Ids")
    }
    
    # Fit linear model to find differentially expressed genes
    design <- model.matrix(~ 0 + nsFiltered\$mol.biol)
    colnames(design) <- c("BCR/ABL", "NEG")
    contr <- c(1, -1)
    fm1 <- lmFit(nsFiltered, design)
    fm2 <- contrasts.fit(fm1, contr)
    fm3 <- eBayes(fm2)
    ttestLimma <- topTable(fm3, number = nrow(fm3), adjust.method = "none")
    ttestLimma <- ttestLimma[featureNames(nsFiltered), ]
    
    # Select genes based on p-value cutoff
    ttestCutoff <- 0.01
    smPV  <- ttestLimma\$P.Value < ttestCutoff
    pvalFiltered <- nsFiltered[smPV, ]
    selectedEntrezIds <- unlist(mget(featureNames(pvalFiltered), entrezMap))
    
    # 3. Create ChrMapHyperGParams parameter objects
    params <- new("ChrMapHyperGParams",
                  conditional=FALSE,
                  testDirection="over",
                  universeGeneIds=entrezUniverse,
                  geneIds=selectedEntrezIds,
                  annotation="hgu95av2",
                  pvalueCutoff=0.05)
    
    paramsCond <- params
    paramsCond@conditional <- TRUE
    
    # 4. Run the hypergeometric tests
    hgans <- hyperGTest(params)
    hgansCond <- hyperGTest(paramsCond)
    
    # 5. Summarize results
    sumUn <- summary(hgans, categorySize=1)
    sumCond <- summary(hgansCond, categorySize=1)
    
    # Helper function to sort chromosome bands in natural order
    chrSortOrder <- function(df) {
        if (nrow(df) == 0) return(df)
        chrs <- sub("([^pq]+).*\$", "\\1", rownames(df))
        xyIdx <- chrs %in% c("X", "Y")
        xydf <- NULL
        if (any(xyIdx)) {
            chrs <- chrs[!xyIdx]
            xydf <- df[xyIdx, ]
            df <- df[!xyIdx, ]
        }
        ord <- order(as.integer(chrs), rownames(df))
        df <- df[ord, ]
        if (!is.null(xydf))
          df <- rbind(df, xydf)
        df
    }
    
    # Sort the summary tables
    sumUnSorted <- chrSortOrder(sumUn)
    sumCondSorted <- chrSortOrder(sumCond)
    
    # 6. Write outputs to files
    write.csv(sumUnSorted, "chrom_band_hyperg_unconditional_results.csv", row.names=TRUE)
    write.csv(sumCondSorted, "chrom_band_hyperg_conditional_results.csv", row.names=TRUE)
    
    saveRDS(hgans, "hgans_unconditional.rds")
    saveRDS(hgansCond, "hgans_conditional.rds")
    
    cat("Workflow completed successfully. Outputs written to CSV and RDS files.\n")

    writeLines(c(
        '"BIOC_CATEGORY_CHROM_BAND_HYPERGEOMETRIC_TEST":',
        paste0('    Category: ', as.character(packageVersion('Category')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chrom_band_hypergeometric_test.csv versions.yml
    """
}

workflow BIOC_CATEGORY_CHROM_BAND_HYPERGEOMETRIC_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bcrAblOrNeg.RData ] ]

    main:
    BIOC_CATEGORY_CHROM_BAND_HYPERGEOMETRIC_TEST(ch_input)

    emit:
    tables   = BIOC_CATEGORY_CHROM_BAND_HYPERGEOMETRIC_TEST.out.tables
    plots    = BIOC_CATEGORY_CHROM_BAND_HYPERGEOMETRIC_TEST.out.plots
    objects  = BIOC_CATEGORY_CHROM_BAND_HYPERGEOMETRIC_TEST.out.objects
    versions = BIOC_CATEGORY_CHROM_BAND_HYPERGEOMETRIC_TEST.out.versions
}
