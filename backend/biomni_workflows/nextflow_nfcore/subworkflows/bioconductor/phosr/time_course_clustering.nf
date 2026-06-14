#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhosR — time_course_clustering
// Cluster time-course phosphoproteomic data to identify temporal profiles and enriched kinases/pathways.
// Input: time_course_quantification.csv
// Container: quay.io/biocontainers/bioconductor-phosr:1.20.0--r45hdfd78af_0
// R packages: ClueR, PhosR, annotate, org.Mm.eg.db, reactome.db
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHOSR_TIME_COURSE_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phosr:1.20.0--r45hdfd78af_0"

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
    .bm_deps <- c("ClueR", "PhosR", "annotate", "org.Mm.eg.db", "reactome.db", "SummarizedExperiment")
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
    
    # Load required libra    library(SummarizedExperiment)
ries
    library(PhosR)
    library(reactome.db)
    library(org.Mm.eg.db)
    library(annotate)
    library(ClueR)
    
    # --- Read user input ---
    if (!file.exists("time_course_quantification.csv")) {
      stop("Required input file 'time_course_quantification.csv' not found in the working directory.")
    }
    
    df <- read.csv("time_course_quantification.csv", row.names = 1, check.names = FALSE)
    ppe <- PhosphoExperiment(assays = list(Quantification = as.matrix(df)))
    
    # --- Extract grouping information ---
    grps <- sapply(strsplit(colnames(ppe), "_"), 
                function(x)x[3])
    
    # --- Filter and average replicates using matANOVA and ---
    sites.p <- matANOVA(SummarizedExperiment::assay(ppe, "Quantification"), 
                        grps)
    ppm <- meanAbundance(SummarizedExperiment::assay(ppe, "Quantification"), grps)
    sel <- which((sites.p < 0.05) & (rowSums(abs(ppm) > 1) != 0))
    ppm_filtered <- ppm[sel,]
    
    # Write filtered and averaged replicates
    write.csv(ppm_filtered, "ppm_filtered.csv", row.names = TRUE)
    
    # --- Collapse to gene level using phosCollapse ---
    ppm_gene <- phosCollapse(ppm_filtered, 
                gsub(";.+", "", rownames(ppm_filtered)), 
                    stat = apply(abs(ppm_filtered), 1, max), by = "max")
    
    # Write gene-level collapsed matrix
    write.csv(ppm_gene, "ppm_gene.csv", row.names = TRUE)
    
    # --- Prepare the Reactome annotation (mouse pathways, ---
    pathways = as.list(reactomePATHID2EXTID)
    pathways = pathways[which(grepl("R-MMU", names(pathways), ignore.case = TRUE))]
    pathways = lapply(pathways, function(path) {
        gene_name = unname(getSYMBOL(path, data = "org.Mm.eg"))
        toupper(unique(gene_name))
    })
    
    # --- Run clustering evaluation using runClue ---
    RNGkind("L'Ecuyer-CMRG")
    set.seed(123)
    c1 <- runClue(ppm_gene, annotation=pathways, 
                kRange = seq(2,10), rep = 5, effectiveSize = c(5, 100), 
                pvalueCutoff = 0.05, alpha = 0.5)
    
    saveRDS(c1, "clue_results.rds")
    
    # --- Identify optimal clusters and find enriched ---
    pdf("optimal_clusters.pdf", width = 10, height = 8)
    best <- clustOptimal(c1, rep=5, mfrow=c(2, 3), visualize = TRUE)
    dev.off()
    
    saveRDS(best, "best_clustering.rds")
    
    # Save enriched list if available
    if (!is.null(best\$enrichList)) {
      saveRDS(best\$enrichList, "enriched_pathways.rds")
    }
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_PHOSR_TIME_COURSE_CLUSTERING":',
        paste0('        PhosR: ', as.character(packageVersion("PhosR")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_course_clustering.csv versions.yml
    """
}

workflow BIOC_PHOSR_TIME_COURSE_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ time_course_quantification.csv ] ]

    main:
    BIOC_PHOSR_TIME_COURSE_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_PHOSR_TIME_COURSE_CLUSTERING.out.tables
    plots    = BIOC_PHOSR_TIME_COURSE_CLUSTERING.out.plots
    objects  = BIOC_PHOSR_TIME_COURSE_CLUSTERING.out.objects
    versions = BIOC_PHOSR_TIME_COURSE_CLUSTERING.out.versions
}
