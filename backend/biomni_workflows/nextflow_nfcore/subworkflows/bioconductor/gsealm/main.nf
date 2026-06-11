#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSEAlm — gsea_linear_modeling_and_diagnostics
// Fit gene-specific linear models with multiple covariates, extract and aggregate residuals over gene sets for diagnostic plotting, and perform permutation-based 
// Input: workingEset, AmatChr3
// Container: quay.io/biocontainers/bioconductor-gsealm:1.70.0--r45hdfd78af_0
// R packages: Biobase, ALL, annotate, GOstats, GSEAlm, RColorBrewer, Rgraphviz
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEAlm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Fit gene-specific linear models using lmPerGene. 2. Extract Studentized residuals using getResidPerGene. 3. Plot residuals grouped

nextflow.enable.dsl = 2

process BIOC_GSEALM_GSEA_LINEAR_MODELING_AND_DIAGNOSTICS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "ALL", "annotate", "GOstats", "GSEAlm", "RColorBrewer", "Rgraphviz")
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
        library(GSEAlm)
        library(Biobase)
        
        # Read user input files from the working directory
        if (!file.exists("workingEset.rds") || !file.exists("AmatChr3.rds")) {
          stop("Required input files 'workingEset.rds' and/or 'AmatChr3.rds' not found in the working directory.")
        }
        
        workingEset <- readRDS("workingEset.rds")
        AmatChr3 <- readRDS("AmatChr3.rds")
        
        # Determine ChrLeaves and LeafGenes programmatically from AmatChr3
        bands <- rownames(AmatChr3)
        is_leaf <- sapply(bands, function(b) {
          children <- bands[startsWith(bands, b) & bands != b]
          if (length(children) == 0) return(TRUE)
          if (grepl("^\\\\d+\$", b)) {
            has_real_child <- any(grepl(paste0("^", b, "[pq]"), children))
            return(!has_real_child)
          }
          return(FALSE)
        })
        ChrLeaves <- bands[is_leaf]
        LeafGenes <- which(colSums(AmatChr3[ChrLeaves, , drop = FALSE]) > 0)
        
        nperm <- 125
        
        # Dynamically determine phenotype columns
        pheno_cols <- varLabels(workingEset)
        primary_pheno <- pheno_cols[1]
        
        workingEset[[primary_pheno]] <- as.factor(workingEset[[primary_pheno]])
        form_pheno <- as.formula(paste("~", sprintf("`%s`", primary_pheno)))
        
        # 1. Fit gene-specific linear models using lmPerGene
        lmPhen <- lmPerGene(workingEset, form_pheno)
        
        # 2. Extract Studentized residuals using getResidPerGene
        lmPhenRes <- getResidPerGene(lmPhen)
        
        # 3. Plot residuals grouped by sample and phenotype using resplot
        pdf("resplot.pdf", width = 10, height = 8)
        resplot(resmat=exprs(lmPhenRes),fac=workingEset[[primary_pheno]],cex.main=.7,cex.axis=.6,horiz=TRUE,lims=c(-5,5),xname="",col=5,cex=.3)
        dev.off()
        
        # 4. Aggregate residuals over gene sets using GSNormalize
        stdrAchr=GSNormalize(exprs(lmPhenRes),AmatChr3)
        form_expand <- as.formula(paste("~", paste(sprintf("`%s`", pheno_cols), collapse="+")))
        lmExpand <- lmPerGene(workingEset, form_expand)
        lmExpandRes <- getResidPerGene(lmExpand,type="extStudent")
        GSresidExpand=GSNormalize(exprs(lmExpandRes),AmatChr3)
        
        # 5. Perform permutation-based GSEA using gsealmPerm
        pvalsExpand=gsealmPerm(workingEset[LeafGenes,], form_expand, AmatChr3[ChrLeaves,LeafGenes],nperm=nperm,removeShift=TRUE)
        
        # 6. Calculate Cook's Distance per gene using CooksDPerGene and aggregate over gene sets using GSNormalize
        cookie1=CooksDPerGene(lmPhen)
        BandCooks1=GSNormalize(cookie1,AmatChr3,fun2=identity)
        
        # Save meaningful results to the working directory
        saveRDS(lmPhenRes, "lmPhenRes.rds")
        saveRDS(lmExpandRes, "lmExpandRes.rds")
        write.csv(as.data.frame(stdrAchr), "stdrAchr.csv", row.names = TRUE)
        write.csv(as.data.frame(GSresidExpand), "GSresidExpand.csv", row.names = TRUE)
        write.csv(as.data.frame(pvalsExpand), "pvalsExpand.csv", row.names = TRUE)
        write.csv(as.data.frame(BandCooks1), "BandCooks1.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_GSEALM_GSEA_LINEAR_MODELING_AND_DIAGNOSTICS":',
        paste0('    GSEAlm: ', as.character(packageVersion('GSEAlm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsea_linear_modeling_and_diagnostics.csv versions.yml
    """
}

workflow BIOC_GSEALM_GSEA_LINEAR_MODELING_AND_DIAGNOSTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ workingEset, AmatChr3 ] ]

    main:
    BIOC_GSEALM_GSEA_LINEAR_MODELING_AND_DIAGNOSTICS(ch_input)

    emit:
    tables   = BIOC_GSEALM_GSEA_LINEAR_MODELING_AND_DIAGNOSTICS.out.tables
    plots    = BIOC_GSEALM_GSEA_LINEAR_MODELING_AND_DIAGNOSTICS.out.plots
    objects  = BIOC_GSEALM_GSEA_LINEAR_MODELING_AND_DIAGNOSTICS.out.objects
    versions = BIOC_GSEALM_GSEA_LINEAR_MODELING_AND_DIAGNOSTICS.out.versions
}
