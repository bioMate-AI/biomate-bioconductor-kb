#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOstats — association_unsupported_organism
// Perform GO or KEGG enrichment analysis for an organism that does not have a pre-built Bioconductor annotation package.
// Input: custom_go_mappings.txt, custom_kegg_mappings.txt
// Container: quay.io/biocontainers/bioconductor-gostats:2.76.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, AnnotationForge, Category, GOstats, GSEABase
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] GO Enrichment Analysis
//  * 2. [Visualization & Output] KEGG Enrichment Analysis

nextflow.enable.dsl = 2

process BIOC_GOSTATS_ASSOCIATION_UNSUPPORTED_ORGANISM {
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
    .bm_deps <- c("GOstats", "GSEABase", "Category", "AnnotationDbi", "AnnotationForge")
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
        library(GOstats)
        library(GSEABase)
        library(Category)
        library(AnnotationDbi)
        library(AnnotationForge)
        
        # ==========================================
        # --- GO Enrichment Analysis ---
        # ==========================================
        
        # Read custom GO mappings from the working directory
        # Expected format: Tab-delimited file with GO ID, Evidence Code, and Gene ID
        frame <- read.table("custom_go_mappings.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        colnames(frame) <- c("go_id", "Evidence", "gene_id")
        
        # Recreate the documented data frame structure
        goframeData = data.frame(frame\$go_id, frame\$Evidence, frame\$gene_id)
        
        # Create GOFrame and GOAllFrame
        goFrame=GOFrame(goframeData,organism="Homo sapiens")
        goAllFrame=GOAllFrame(goFrame)
        
        # Generate GeneSetCollection
        gsc <- GeneSetCollection(goAllFrame, setType = GOCollection())
        
        # Define universe from the custom mappings
        universe = unique(as.character(goframeData[[3]]))
        
        # Define genes of interest as a subset of the universe (as per vignette)
        genes = head(universe, 500)
        
        # Set up GSEAGOHyperGParams
        params <- GSEAGOHyperGParams(name="My Custom GSEA based annot Params", geneSetCollection=gsc, geneIds = genes, universeGeneIds = universe, ontology = "MF", pvalueCutoff = 0.05, conditional = FALSE, testDirection = "over")
        
        # Run hypergeometric test
        Over <- hyperGTest(params)
        
        # Print summary to console
        print("GO Enrichment Summary:")
        print(head(summary(Over)))
        
        # Save GO results
        write.csv(summary(Over), "go_enrichment_results.csv", row.names = FALSE)
        saveRDS(Over, "go_enrichment_results.rds")
        
        
        # ==========================================
        # --- KEGG Enrichment Analysis ---
        # ==========================================
        
        # Read custom KEGG mappings from the working directory
        # Expected format: Tab-delimited file with KEGG Pathway ID and Gene ID
        frame <- read.table("custom_kegg_mappings.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        colnames(frame) <- c("path_id", "gene_id")
        
        # Recreate the documented data frame structure
        keggframeData = data.frame(frame\$path_id, frame\$gene_id)
        
        # Create KEGGFrame
        keggFrame=KEGGFrame(keggframeData,organism="Homo sapiens")
        
        # Generate GeneSetCollection
        gsc <- GeneSetCollection(keggFrame, setType = KEGGCollection())
        
        # Define universe from the custom mappings
        universe = unique(as.character(keggframeData[[2]]))
        
        # Set up GSEAKEGGHyperGParams
        kparams <- GSEAKEGGHyperGParams(name="My Custom GSEA based annot Params", geneSetCollection=gsc, geneIds = genes, universeGeneIds = universe, pvalueCutoff = 0.05, testDirection = "over")
        
        # Run hypergeometric test (correcting the vignette typo 'params' to 'kparams')
        kOver <- hyperGTest(kparams)
        
        # Print summary to console
        print("KEGG Enrichment Summary:")
        print(head(summary(kOver)))
        
        # Save KEGG results
        write.csv(summary(kOver), "kegg_enrichment_results.csv", row.names = FALSE)
        saveRDS(kOver, "kegg_enrichment_results.rds")

    writeLines(c(
        '"BIOC_GOSTATS_ASSOCIATION_UNSUPPORTED_ORGANISM":',
        paste0('    GOstats: ', as.character(packageVersion('GOstats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_association_unsupported_organism.csv versions.yml
    """
}

workflow BIOC_GOSTATS_ASSOCIATION_UNSUPPORTED_ORGANISM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ custom_go_mappings.txt, custom_kegg_mappings.txt ] ]

    main:
    BIOC_GOSTATS_ASSOCIATION_UNSUPPORTED_ORGANISM(ch_input)

    emit:
    tables   = BIOC_GOSTATS_ASSOCIATION_UNSUPPORTED_ORGANISM.out.tables
    plots    = BIOC_GOSTATS_ASSOCIATION_UNSUPPORTED_ORGANISM.out.plots
    objects  = BIOC_GOSTATS_ASSOCIATION_UNSUPPORTED_ORGANISM.out.objects
    versions = BIOC_GOSTATS_ASSOCIATION_UNSUPPORTED_ORGANISM.out.versions
}
