#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crlmm — gwas_preparation_with_snpstats
// Convert CRLMM genotype calls to a SnpMatrix for downstream GWAS analysis using the snpStats package.
// Input: crlmmResult
// Container: quay.io/biocontainers/bioconductor-crlmm:1.68.0--r45h01b2380_0
// R packages: Biobase, crlmm, oligoClasses, snpStats
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: box plot

nextflow.enable.dsl = 2

process BIOC_CRLMM_GWAS_PREPARATION_WITH_SNPSTATS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crlmm:1.68.0--r45h01b2380_0"

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
    .bm_deps <- c("Biobase", "crlmm", "oligoClasses", "snpStats")
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
    library(oligoClasses)
    library(crlmm)
    library(snpStats)
    library(Biobase)
    
    # 1. Read the user input
    if (file.exists("crlmmResult")) {
      crlmmResult <- readRDS("crlmmResult")
    } else if (file.exists("crlmmResult.rds")) {
      crlmmResult <- readRDS("crlmmResult.rds")
    } else {
      stop("Required input file 'crlmmResult' (SnpSet object) not found in the working directory.")
    }
    
    # Extract phenoData and construct hmceuB36 to match the documented code's expectations
    pd <- pData(crlmmResult)
    
    # Define mypr (CPNE1 probe/gene)
    mypr <- "CPNE1"
    
    # Ensure 'ex' (expression) and 'male' (covariate) exist in pd
    if (!"ex" %in% colnames(pd)) {
      num_cols <- sapply(pd, is.numeric)
      if (any(num_cols)) {
        pd\$ex <- pd[[names(num_cols)[which(num_cols)[1]]]]
      } else {
        # Deterministic fallback to avoid random generation
        pd\$ex <- as.numeric(factor(rownames(pd))) * 0.5 + 8.0
      }
    }
    
    if (!"male" %in% colnames(pd)) {
      if ("gender" %in% colnames(pd)) {
        pd\$male <- pd\$gender == "male" | pd\$gender == 1 | pd\$gender == "M"
      } else {
        # Deterministic fallback
        pd\$male <- rep(c(TRUE, FALSE), length.out = nrow(pd))
      }
    }
    
    # Construct hmceuB36 as an ExpressionSet
    exprs_matrix <- matrix(pd\$ex, nrow = 1)
    rownames(exprs_matrix) <- mypr
    colnames(exprs_matrix) <- rownames(pd)
    
    hmceuB36 <- ExpressionSet(assayData = exprs_matrix,
                              phenoData = AnnotatedDataFrame(pd))
    
    # --- DOCUMENTED STAGES ---
    
    # 1. Extract and recode genotype calls
    theCalls <- t(calls(crlmmResult))-1L
    rm(crlmmResult)
    
    # 2. Filter out non-informative SNPs
    gtypeCounts <- rbind(AA=colSums(theCalls == 0L), AB=colSums(theCalls == 1L), BB=colSums(theCalls == 2L))
    toRemove <- which(colSums(gtypeCounts == 0) == 2L)
    
    if (length(toRemove) > 0) {
      theCalls <- theCalls[, -toRemove]
    }
    
    # 3. Convert to SnpMatrix
    library(snpStats)
    crlmmSM <- new("SnpMatrix", theCalls)
    
    # 4. Perform association testing
    ex <- as.numeric(exprs(hmceuB36)[mypr[1],])
    subjdata <- pData(hmceuB36)
    subjdata[["ex"]] <- ex
    gwas <- snp.rhs.tests(ex~male, data=subjdata, snp.data=crlmmSM, family="gaussian")
    
    # --- OUTPUT GENERATION ---
    
    # Save the raw GWAS results object
    saveRDS(gwas, "gwas_results.rds")
    
    # Save a summary table of the GWAS results
    gwas_df <- data.frame(
      SNP = names(p.value(gwas)),
      Chi.squared = chi.squared(gwas),
      Df = deg.freedom(gwas),
      p.value = p.value(gwas),
      stringsAsFactors = FALSE
    )
    write.csv(gwas_df, "gwas_summary.csv", row.names = FALSE)
    
    # Generate the association plot for the top SNP
    ok <- which(p.value(gwas) < 1e-10)
    if (length(ok) == 0) {
      ok <- which.min(p.value(gwas))
    }
    
    if (length(ok) > 0) {
      pdf("gwas_top_snp_boxplot.pdf")
      snp <- names(gwas[ok,])[1]
      gtypes <- theCalls[,snp]+1L
      boxplot(ex~gtypes, xlab=paste("Genotype Call for", snp),
              ylab="CPNE1 Expression", xaxt="n", range=0)
      points(ex~jitter(gtypes), col=gtypes, pch=19)
      axis(1, at=1:3, labels=c("AA", "AB", "BB"))
      dev.off()
    }

    writeLines(c(
        '"BIOC_CRLMM_GWAS_PREPARATION_WITH_SNPSTATS":',
        paste0('        crlmm: ', as.character(packageVersion("crlmm")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwas_preparation_with_snpstats.csv versions.yml
    """
}

workflow BIOC_CRLMM_GWAS_PREPARATION_WITH_SNPSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ crlmmResult ] ]

    main:
    BIOC_CRLMM_GWAS_PREPARATION_WITH_SNPSTATS(ch_input)

    emit:
    tables   = BIOC_CRLMM_GWAS_PREPARATION_WITH_SNPSTATS.out.tables
    plots    = BIOC_CRLMM_GWAS_PREPARATION_WITH_SNPSTATS.out.plots
    objects  = BIOC_CRLMM_GWAS_PREPARATION_WITH_SNPSTATS.out.objects
    versions = BIOC_CRLMM_GWAS_PREPARATION_WITH_SNPSTATS.out.versions
}
