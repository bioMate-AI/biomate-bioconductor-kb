#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: synextend — ortholog_prediction_and_clustering
// Predict orthologous gene pairs from genomic sequences and GFF annotations, cluster them into single-linkage groups, and extract their sequences.
// Input: Endosymbionts_v05a.sqlite, GCF_023585825.1_ASM2358582v1_genomic.gff.gz
// Container: quay.io/biocontainers/bioconductor-synextend:1.22.0--r45h63f16b7_0
// R packages: SynExtend
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNEXTEND_ORTHOLOG_PREDICTION_AND_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-synextend:1.22.0--r45h63f16b7_0"

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
    .bm_deps <- c("SynExtend")
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
    library(SynExtend)
    
    # Define input file paths from the working directory
    DBPATH <- "Endosymbionts_v05a.sqlite"
    GFF_PATH <- "GCF_023585825.1_ASM2358582v1_genomic.gff.gz"
    
    # 1. Build synteny map using FindSynteny
    message("Building synteny map...")
    Syn <- FindSynteny(dbFile = DBPATH)
    
    # Print synteny object summary
    print(Syn)
    
    # Save synteny plot to PDF
    pdf("synteny_pairs_plot.pdf", width = 8, height = 8)
    pairs(Syn)
    dev.off()
    
    # Save synteny object to RDS
    saveRDS(Syn, "synteny_map.rds")
    
    # Print head of synteny map matrices
    print(head(Syn[[1, 2]]))
    print(head(Syn[[2, 1]]))
    
    # 2. Parse GFF annotations into a usable data frame using gffToDataFrame
    message("Parsing GFF annotations...")
    GC <- gffToDataFrame(GFF = GFF_PATH,
                         Verbose = TRUE)
    
    # Save parsed GFF to CSV
    write.csv(as.data.frame(GC), "parsed_gff.csv", row.names = FALSE)
    
    # Reconcile GeneCalls names with the Synteny object
    # GeneCalls must be a named list matching dimnames(Syn)[[1]] exactly
    genome_names <- dimnames(Syn)[[1]]
    GeneCalls <- vector("list", length = length(genome_names))
    names(GeneCalls) <- genome_names
    for (name in genome_names) {
      GeneCalls[[name]] <- GC
    }
    
    print(head(GeneCalls[[1]]))
    
    # 3. Find nucleotide overlaps between synteny maps and gene calls using NucleotideOverlap
    message("Finding nucleotide overlaps...")
    Links <- NucleotideOverlap(SyntenyObject = Syn,
                               GeneCalls = GeneCalls,
                               Verbose = TRUE)
    
    class(Links)
    print(Links)
    saveRDS(Links, "synteny_links.rds")
    
    # 4. Summarize linked pairs using PairSummaries
    message("Summarizing linked pairs...")
    LinkedPairs1 <- PairSummaries(SyntenyLinks = Links,
                                  DBPATH = DBPATH,
                                  PIDs = FALSE,
                                  Verbose = TRUE)
    
    print(head(LinkedPairs1))
    write.csv(LinkedPairs1, "linked_pairs_summary.csv", row.names = FALSE)
    
    # 5. Cluster predicted pairs using DisjointSet
    message("Clustering predicted pairs...")
    SingleLinkageClusters <- DisjointSet(Pairs = LinkedPairs1,
                                         Verbose = TRUE)
    
    saveRDS(SingleLinkageClusters, "single_linkage_clusters.rds")
    
    # 6. Extract clustered sequences using ExtractBy
    message("Extracting clustered sequences...")
    # Extract the first 10 clusters (or fewer if there are less than 10)
    num_clusters <- min(10, length(SingleLinkageClusters))
    Sets <- ExtractBy(x = LinkedPairs1,
                      y = DBPATH,
                      z = SingleLinkageClusters[1:num_clusters],
                      Verbose = TRUE)
    
    print(head(Sets))
    saveRDS(Sets, "extracted_cluster_sequences.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SYNEXTEND_ORTHOLOG_PREDICTION_AND_CLUSTERING":',
        paste0('        synextend: ', as.character(packageVersion("synextend")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ortholog_prediction_and_clustering.csv versions.yml
    """
}

workflow BIOC_SYNEXTEND_ORTHOLOG_PREDICTION_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Endosymbionts_v05a.sqlite, GCF_023585825.1_ASM2358582v1_genomic.gff.gz ] ]

    main:
    BIOC_SYNEXTEND_ORTHOLOG_PREDICTION_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SYNEXTEND_ORTHOLOG_PREDICTION_AND_CLUSTERING.out.tables
    plots    = BIOC_SYNEXTEND_ORTHOLOG_PREDICTION_AND_CLUSTERING.out.plots
    objects  = BIOC_SYNEXTEND_ORTHOLOG_PREDICTION_AND_CLUSTERING.out.objects
    versions = BIOC_SYNEXTEND_ORTHOLOG_PREDICTION_AND_CLUSTERING.out.versions
}
