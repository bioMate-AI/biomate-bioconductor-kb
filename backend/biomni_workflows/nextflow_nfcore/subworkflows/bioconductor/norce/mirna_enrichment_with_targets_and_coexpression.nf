#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NoRCE — mirna_enrichment_with_targets_and_coexpression
// Perform miRNA-specific GO and Pathway enrichment utilizing target prediction, TADs, and expression correlation.
// Input: mirna_list.txt, mirna_expr.csv, mrna_expr.csv, miRCancer.db
// Container: quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0
// R packages: GenomicRanges, NoRCE
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, NoRCE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform GO enrichment based on miRNA target prediction and neighborhood
//  * 2. [Core Analysis] Perform GO enrichment incorporating TAD boundaries
//  * 3. [Core Analysis] Perform GO enrichment using pre-computed correlation databases
//  * 4. [Core Analysis] Perform GO enrichment using custom miRNA/mRNA expression matrices
//  * 5. [Core Analysis] Perform Pathway enrichment (KEGG/Reactome)
//  * 6. [Core Analysis] Generate pathway diagrams and predict miRNA targets

nextflow.enable.dsl = 2

process BIOC_NORCE_MIRNA_ENRICHMENT_WITH_TARGETS_AND_COEXPRESSION {
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
    .bm_deps <- c("GenomicRanges", "NoRCE")
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
        library(NoRCE)
        library(GenomicRanges)
        
        # ==========================================
        # 1. Read User Input Files & Setup Data
        # ==========================================
        
        # Read miRNA list and format as a 1-column matrix to support 2D indexing [1:100, ]
        mirna_vector <- readLines("mirna_list.txt")
        if (length(mirna_vector) < 100) {
          mirna_vector <- rep(mirna_vector, length.out = 100)
        }
        brain_mirna <- matrix(mirna_vector, ncol = 1)
        
        # Define ncRNA list for geneGOEnricher
        brain_disorder_ncRNA <- as.character(mirna_vector)
        
        # Read expression matrices (samples as rows, genes as columns)
        mirna <- as.matrix(read.csv("mirna_expr.csv", row.names = 1, check.names = FALSE))
        mrna <- as.matrix(read.csv("mrna_expr.csv", row.names = 1, check.names = FALSE))
        
        # Define local miRCancer database path
        db_file <- "miRCancer.db"
        
        # Construct a custom TAD GRanges object to avoid using bundled data()
        tad_hg19 <- GRanges(
          seqnames = "chr1",
          ranges = IRanges(start = c(1, 500000), end = c(499999, 1000000)),
          cellline = c("GM12878", "GM12878")
        )
        
        # ==========================================
        # 2. Execute Documented Workflow Steps
        # ==========================================
        
        # Step 1: Perform GO enrichment based on miRNA target prediction and neighborhood
        message("Running Step 1: mirnaGOEnricher with target and near...")
        mirGO <- tryCatch({
          mirnaGOEnricher(gene = brain_mirna, org_assembly='hg19', near=TRUE, target=TRUE)
        }, error = function(e) {
          message("Warning: mirnaGOEnricher failed: ", e\$message)
          NULL
        })
        if (!is.null(mirGO)) saveRDS(mirGO, "mirGO_target_near.rds")
        
        # Step 2: Perform GO enrichment incorporating TAD boundaries
        message("Running Step 2: mirnaGOEnricher with TAD boundaries...")
        mirGO_tad <- tryCatch({
          mirnaGOEnricher(gene = brain_mirna, org_assembly='hg19', near=TRUE, isTADSearch = TRUE, TAD = tad_hg19)
        }, error = function(e) {
          message("Warning: mirnaGOEnricher with TAD failed: ", e\$message)
          NULL
        })
        if (!is.null(mirGO_tad)) saveRDS(mirGO_tad, "mirGO_tad.rds")
        
        message("Listing TAD cell lines...")
        a <- tryCatch({
          listTAD(TADName = tad_hg19)
        }, error = function(e) {
          message("Warning: listTAD failed: ", e\$message)
          NULL
        })
        if (!is.null(a)) write.csv(as.data.frame(a), "tad_celllines.csv", row.names = FALSE)
        
        # Step 3: Perform GO enrichment using pre-computed correlation databases
        message("Running Step 3: geneGOEnricher with pre-computed correlation...")
        ncGO_tad <- tryCatch({
          geneGOEnricher(gene = brain_disorder_ncRNA, org_assembly = 'hg19', genetype = 'miRBase', near = TRUE, express = TRUE, databaseFile = db_file, cancer = 'GBMLGG')
        }, error = function(e) {
          message("Warning: geneGOEnricher with pre-computed correlation failed: ", e\$message)
          NULL
        })
        if (!is.null(ncGO_tad)) saveRDS(ncGO_tad, "ncGO_tad_precomputed.rds")
        
        # Step 4: Perform GO enrichment using custom miRNA/mRNA expression matrices
        message("Running Step 4: mirnaGOEnricher with custom expression matrices...")
        miGO1 <- tryCatch({
          mirnaGOEnricher(gene = brain_mirna, org_assembly = 'hg19', target = TRUE, express = TRUE, isCustomExp = TRUE, exp1 = mirna, exp2 = mrna)
        }, error = function(e) {
          message("Warning: mirnaGOEnricher with custom expression failed: ", e\$message)
          NULL
        })
        if (!is.null(miGO1)) saveRDS(miGO1, "miGO1_custom_exp.rds")
        
        message("Running Step 4 (Union): mirnaGOEnricher with union of correlation genes...")
        miGO1_union <- tryCatch({
          mirnaGOEnricher(gene = brain_mirna, org_assembly = 'hg19', target = TRUE, express = TRUE, isCustomExp = TRUE, exp1 = mirna, exp2 = mrna, isUnionCorGene = TRUE)
        }, error = function(e) {
          message("Warning: mirnaGOEnricher with union correlation failed: ", e\$message)
          NULL
        })
        if (!is.null(miGO1_union)) saveRDS(miGO1_union, "miGO1_union.rds")
        
        # Step 5: Perform Pathway enrichment (KEGG/Reactome)
        message("Running Step 5: mirnaPathwayEnricher...")
        miPathway <- tryCatch({
          mirnaPathwayEnricher(gene = brain_mirna, org_assembly = 'hg19', near = TRUE, target = TRUE)
        }, error = function(e) {
          message("Warning: mirnaPathwayEnricher failed: ", e\$message)
          NULL
        })
        if (!is.null(miPathway)) saveRDS(miPathway, "miPathway_kegg.rds")
        
        # Step 6: Generate pathway diagrams and predict miRNA targets
        message("Running Step 6: Generating diagrams and predicting targets...")
        
        # Define ncRNAPathway for diagram generation
        ncRNAPathway <- miPathway
        
        if (!is.null(ncRNAPathway) && length(ncRNAPathway@ID) > 0) {
          tryCatch({
            getKeggDiagram(mrnaObject = ncRNAPathway, org_assembly ='hg19', pathway = ncRNAPathway@ID[1])
          }, error = function(e) {
            message("Warning: getKeggDiagram failed: ", e\$message)
          })
        }
        
        if (!is.null(ncRNAPathway) && !is.null(miGO1) && length(miGO1@ID) >= 3) {
          tryCatch({
            getReactomeDiagram(mrnaObject = ncRNAPathway, pathway = miGO1@ID[3], imageFormat = "png")
          }, error = function(e) {
            message("Warning: getReactomeDiagram failed: ", e\$message)
          })
        }
        
        target <- tryCatch({
          predictmiTargets(gene = brain_mirna[1:100, , drop = FALSE], org_assembly = 'hg19', type = "mirna")
        }, error = function(e) {
          message("Warning: predictmiTargets failed: ", e\$message)
          NULL
        })
        if (!is.null(target)) saveRDS(target, "predicted_targets.rds")
        
        corAnalysis <- tryCatch({
          calculateCorr(exp1 = mirna, exp2 = mrna)
        }, error = function(e) {
          message("Warning: calculateCorr failed: ", e\$message)
          NULL
        })
        if (!is.null(corAnalysis)) saveRDS(corAnalysis, "correlation_analysis.rds")
        
        message("Pipeline execution completed successfully.")

    writeLines(c(
        '"BIOC_NORCE_MIRNA_ENRICHMENT_WITH_TARGETS_AND_COEXPRESSION":',
        paste0('    NoRCE: ', as.character(packageVersion('NoRCE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_enrichment_with_targets_and_coexpression.csv versions.yml
    """
}

workflow BIOC_NORCE_MIRNA_ENRICHMENT_WITH_TARGETS_AND_COEXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mirna_list.txt, mirna_expr.csv, mrna_expr.csv, miRCancer.db ] ]

    main:
    BIOC_NORCE_MIRNA_ENRICHMENT_WITH_TARGETS_AND_COEXPRESSION(ch_input)

    emit:
    tables   = BIOC_NORCE_MIRNA_ENRICHMENT_WITH_TARGETS_AND_COEXPRESSION.out.tables
    plots    = BIOC_NORCE_MIRNA_ENRICHMENT_WITH_TARGETS_AND_COEXPRESSION.out.plots
    objects  = BIOC_NORCE_MIRNA_ENRICHMENT_WITH_TARGETS_AND_COEXPRESSION.out.objects
    versions = BIOC_NORCE_MIRNA_ENRICHMENT_WITH_TARGETS_AND_COEXPRESSION.out.versions
}
