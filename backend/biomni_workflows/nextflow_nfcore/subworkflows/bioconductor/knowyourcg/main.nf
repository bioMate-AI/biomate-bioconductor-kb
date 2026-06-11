#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowyourcg — array_discrete_enrichment
// Test a discrete set of CpG probe IDs (e.g., from Illumina arrays) for enrichment against categorical database sets using Fisher's exact test and visualize the r
// Input: query
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: ggplot2, ggrepel, gprofiler2, knitr, knowYourCG, sesame, sesameData, SummarizedExperiment
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_ARRAY_DISCRETE_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0"

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
    .bm_deps <- c("ggplot2", "ggrepel", "gprofiler2", "knitr", "knowYourCG", "sesame", "sesameData", "SummarizedExperiment")
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
    library(knowYourCG)
    library(sesameData)
    library(SummarizedExperiment)
    library(sesame)
    library(ggrepel)
    library(ggplot2)
    
    # 1. Cache required database sets
    sesameDataCache(data_titles = c(
      "genomeInfo.hg38",
      "genomeInfo.mm10",
      "KYCG.MM285.tissueSignature.20211211",
      "MM285.tissueSignature",
      "MM285.address",
      "probeIDSignature",
      "KYCG.MM285.designGroup.20210210",
      "KYCG.MM285.chromHMM.20210210",
      "KYCG.MM285.TFBSconsensus.20220116",
      "KYCG.MM285.HMconsensus.20220116",
      "KYCG.MM285.chromosome.mm10.20210630"
    ))
    sesameDataCache("MM285.tissueSignature")
    kycgDataCache()
    
    # 2. Retrieve query CpG list from user input file
    if (file.exists("query")) {
      query <- tryCatch({
        readRDS("query")
      }, error = function(e) {
        readLines("query")
      })
    } else {
      stop("Required input file 'query' not found in the working directory.")
    }
    
    # Ensure query is a character vector of probe IDs
    query <- as.character(query)
    
    # 3. Run enrichment testing using testEnrichment()
    # Test 1: Enrichment against specified databases (using MM285 platform)
    dbs <- c(
      "KYCG.MM285.chromHMM.20210210",
      "KYCG.HM450.TFBSconsensus.20211013",
      "KYCG.MM285.HMconsensus.20220116",
      "KYCG.MM285.tissueSignature.20211211",
      "KYCG.MM285.chromosome.mm10.20210630",
      "KYCG.MM285.designGroup.20210210"
    )
    
    results_pgc <- testEnrichment(query, databases = dbs, platform = "MM285")
    write.csv(results_pgc, "results_pgc.csv", row.names = FALSE)
    saveRDS(results_pgc, "results_pgc.rds")
    
    # Test 2: Enrichment against TFBS database (one-sided)
    results <- testEnrichment(query, "TFBS")
    write.csv(results, "results_tfbs.csv", row.names = FALSE)
    saveRDS(results, "results_tfbs.rds")
    
    # Test 3: Enrichment against TFBS database (two-sided)
    results_2tailed <- testEnrichment(query, "TFBS", alternative = "two.sided")
    write.csv(results_2tailed, "results_tfbs_2tailed.csv", row.names = FALSE)
    saveRDS(results_2tailed, "results_tfbs_2tailed.rds")
    
    # 4. Visualize results
    # Plot 1: Dot Plot
    pdf("KYCG_plotDot.pdf", width = 8, height = 6)
    p_dot <- KYCG_plotDot(results)
    print(p_dot)
    dev.off()
    
    # Plot 2: Volcano Plot
    pdf("KYCG_plotVolcano.pdf", width = 8, height = 6)
    p_volcano <- KYCG_plotVolcano(results_2tailed)
    print(p_volcano)
    dev.off()
    
    # Plot 3: Manhattan Plot (using external EWAS summary p-values as documented)
    tryCatch({
      smry_pvals <- readRDS(url(paste0(
        "https://zenodo.org/records/",
        "18176501/files/20220413_testManhattan.rds"
      )))
      
      pdf("KYCG_plotManhattan.pdf", width = 10, height = 6)
      p_manhattan <- KYCG_plotManhattan(
        -log10(smry_pvals),
        platform = "HM450",
        title = "Differentially Methylated CpGs - EWAS Aging",
        col = c("navy", "skyblue"),
        ylabel = bquote(-log[10](P ~ value)),
        label_min = 30
      ) + theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1))
      print(p_manhattan)
      dev.off()
    }, error = function(e) {
      warning("Failed to download or plot Manhattan data from Zenodo: ", e\$message)
    })

    writeLines(c(
        '"BIOC_KNOWYOURCG_ARRAY_DISCRETE_ENRICHMENT":',
        paste0('        knowyourcg: ', as.character(packageVersion("knowyourcg")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_array_discrete_enrichment.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_ARRAY_DISCRETE_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query ] ]

    main:
    BIOC_KNOWYOURCG_ARRAY_DISCRETE_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_ARRAY_DISCRETE_ENRICHMENT.out.tables
    plots    = BIOC_KNOWYOURCG_ARRAY_DISCRETE_ENRICHMENT.out.plots
    objects  = BIOC_KNOWYOURCG_ARRAY_DISCRETE_ENRICHMENT.out.objects
    versions = BIOC_KNOWYOURCG_ARRAY_DISCRETE_ENRICHMENT.out.versions
}
