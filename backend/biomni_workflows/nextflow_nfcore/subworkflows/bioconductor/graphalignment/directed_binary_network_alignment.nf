#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GraphAlignment — directed_binary_network_alignment
// Align two directed binary networks using node similarity and link similarity.
// Input: ex$a, ex$b, ex$r
// Container: quay.io/biocontainers/bioconductor-graphalignment:1.74.0--r45h01b2380_0
// R packages: GraphAlignment
// Bioconductor: 3.20 | R: 4.4
// Requires: GraphAlignment
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate example directed data and binarize matrices
//  * 2. [Core Analysis] Generate initial alignment
//  * 3. [Input & Preparation] Define link and node lookup bins
//  * 4. [Core Analysis] Compute link parameters with clamping disabled
//  * 5. [Core Analysis] Align networks with directed mode enabled

nextflow.enable.dsl = 2

process BIOC_GRAPHALIGNMENT_DIRECTED_BINARY_NETWORK_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GraphAlignment")
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
        
        # Load required library
        library(GraphAlignment)
        
        # 1. Read user input files from the working directory
        a <- as.matrix(read.csv("ex_a.csv", header = FALSE))
        b <- as.matrix(read.csv("ex_b.csv", header = FALSE))
        r <- as.matrix(read.csv("ex_r.csv", header = FALSE))
        ex <- list(a = a, b = b, r = r)
        
        # Binarize matrices
        a[a > .5] = 1; a[a <= .5] = 0
        b[b > .5] = 1; b[b <= .5] = 0
        
        # 2. Generate initial alignment
        pinitial <- InitialAlignment(psize = nrow(a) + nrow(b), r = ex\$r, mode = "reciprocal")
        
        # 3. Define link and node lookup bins
        lookupLink <- c(-.5, .5, 1.5)
        
        # 4. Compute link parameters with clamping disabled
        linkParams <- ComputeLinkParameters(a, b, pinitial, lookupLink, clamp = FALSE)
        
        lookupNode <- c(-.5, .5, 1.5)
        nsS0 <- c(.025, -.025)
        nsS1 <- c(-.025, 4)
        
        # 5. Align networks with directed mode enabled
        al <- AlignNetworks(A = a, B = b, R = ex\$r, P = pinitial,
            linkScore = linkParams\$ls,
            selfLinkScore = linkParams\$lsSelf,
            nodeScore1 = nsS1, nodeScore0 = nsS0,
            lookupLink = lookupLink, lookupNode = lookupNode,
            bStart = .1, bEnd = 100,
            maxNumSteps = 500, clamp = FALSE, directed = TRUE)
        
        # Write meaningful results to output files
        # 1. Alignment Vector
        write.csv(data.frame(Node_A = 1:length(al), Aligned_Node_B = al), "alignment.csv", row.names = FALSE)
        
        # 2. Aligned Pairs
        ap <- AlignedPairs(a, b, al)
        write.csv(ap, "aligned_pairs.csv", row.names = FALSE)
        
        # 3. Compute Scores
        scores <- ComputeScores(A = a, B = b, R = ex\$r, P = al,
                                linkScore = linkParams\$ls,
                                selfLinkScore = linkParams\$lsSelf,
                                nodeScore1 = nsS1, nodeScore0 = nsS0,
                                lookupLink = lookupLink, lookupNode = lookupNode,
                                symmetric = FALSE, clamp = FALSE)
        write.csv(data.frame(LinkScore = scores\$sl, NodeScore = scores\$sn), "scores.csv", row.names = FALSE)
        
        # 4. Analyze Alignment
        analysis <- AnalyzeAlignment(A = a, B = b, R = ex\$r, P = al, lookupNode = lookupNode, epsilon = 0.5)
        write.csv(data.frame(na = analysis\$na, nb = analysis\$nb, nc = analysis\$nc), "alignment_analysis.csv", row.names = FALSE)
        
        # 5. Visualization Plot
        pdf("alignment_plot.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        image(a, main = "Network A Adjacency")
        image(b, main = "Network B Adjacency")
        dev.off()

    writeLines(c(
        '"BIOC_GRAPHALIGNMENT_DIRECTED_BINARY_NETWORK_ALIGNMENT":',
        paste0('    GraphAlignment: ', as.character(packageVersion('GraphAlignment')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_directed_binary_network_alignment.csv versions.yml
    """
}

workflow BIOC_GRAPHALIGNMENT_DIRECTED_BINARY_NETWORK_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ex$a, ex$b, ex$r ] ]

    main:
    BIOC_GRAPHALIGNMENT_DIRECTED_BINARY_NETWORK_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_GRAPHALIGNMENT_DIRECTED_BINARY_NETWORK_ALIGNMENT.out.tables
    plots    = BIOC_GRAPHALIGNMENT_DIRECTED_BINARY_NETWORK_ALIGNMENT.out.plots
    objects  = BIOC_GRAPHALIGNMENT_DIRECTED_BINARY_NETWORK_ALIGNMENT.out.objects
    versions = BIOC_GRAPHALIGNMENT_DIRECTED_BINARY_NETWORK_ALIGNMENT.out.versions
}
