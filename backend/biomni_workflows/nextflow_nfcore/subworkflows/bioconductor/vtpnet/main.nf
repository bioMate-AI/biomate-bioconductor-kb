#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vtpnet — vtp_network_construction
// Intersect GWAS variants with transcription factor binding sites and filter by disease map to identify phenotype-TF links.
// Input: gwas_variants.GRanges, tf_binding_sites.GRanges, disease_map.RData
// Container: quay.io/biocontainers/bioconductor-vtpnet:0.50.0--r45hdfd78af_0
// R packages: GenomicRanges, doParallel, foreach, graph, gwascat, MotifDb, Rgraphviz, vtpnet
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-vtpnet:0.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "doParallel", "foreach", "graph", "gwascat", "MotifDb", "Rgraphviz", "vtpnet")
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
    library(vtpnet)
    library(GenomicRanges)
    library(gwascat)
    
    # 1. Load GWAS variants and TF binding sites from user input files
    # Read the GRanges objects
    maurGWAS <- readRDS("gwas_variants.GRanges")
    pax4 <- readRDS("tf_binding_sites.GRanges")
    
    # Since the user provides a single TF binding sites file, we use it for the comparisons
    pax4_85 <- pax4
    pax4_75 <- pax4
    
    # Load the disease map from the RData file
    env <- new.env()
    load("disease_map.RData", envir = env)
    loaded_names <- ls(env)
    if ("cancerMap" %in% loaded_names) {
      cancerMap <- env\$cancerMap
    } else if (length(loaded_names) > 0) {
      cancerMap <- env[[loaded_names[1]]]
    } else {
      stop("The disease_map.RData file is empty or could not be loaded properly.")
    }
    
    # 2. Find overlaps between GWAS variants and TF binding sites using overlapsAny
    vp_pax4_85 = maurGWAS[ overlapsAny(maurGWAS, pax4_85) ]
    length(vp_pax4_85)
    
    vp_pax4_75 = maurGWAS[ overlapsAny(maurGWAS, pax4_75) ]
    length(vp_pax4_75)
    
    # 3. Filter the GWAS variants by a disease map using filterGWASbyMap
    gwrngs19 <- maurGWAS
    cangw = filterGWASbyMap( gwrngs19, cancerMap )
    
    # 4. Identify specific hits using getOneHits
    hits = getOneHits( pax4, cangw, "fimo" )
    
    # Save the results to output files
    saveRDS(hits, "one_hits.rds")
    write.csv(as.data.frame(hits), "one_hits.csv", row.names = FALSE)
    
    saveRDS(vp_pax4_75, "vp_pax4_75_overlaps.rds")
    write.csv(as.data.frame(vp_pax4_75), "vp_pax4_75_overlaps.csv", row.names = FALSE)
    
    # Generate a summary plot of the hits
    pdf("hits_summary.pdf")
    if (length(hits) > 0) {
      # Plot distribution of hits across chromosomes
      chrom_counts <- table(as.character(seqnames(hits)))
      barplot(chrom_counts, 
              main = "Number of Hits by Chromosome", 
              xlab = "Chromosome", 
              ylab = "Hit Count", 
              col = "skyblue", 
              las = 2)
    } else {
      plot.new()
      text(0.5, 0.5, "No hits identified to plot.", cex = 1.2)
    }
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION":
        vtpnet: \$(Rscript -e 'cat(as.character(packageVersion("vtpnet")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vtp_network_construction.csv versions.yml
    """
}

workflow BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gwas_variants.GRanges, tf_binding_sites.GRanges, disease_map.RData ] ]

    main:
    BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION.out.tables
    plots    = BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION.out.plots
    objects  = BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION.out.objects
    versions = BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION.out.versions
}
