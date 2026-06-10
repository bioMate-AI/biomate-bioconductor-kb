#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tanggle — split_networks
// Visualize unrooted, undirected split networks (such as consensus networks or neighbor-nets) from Nexus files.
// Input: woodmouse.nxs
// Container: quay.io/biocontainers/bioconductor-tanggle:1.16.0--r45hdfd78af_0
// R packages: ggplot2, ggtree, phangorn, tanggle
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TANGGLE_SPLIT_NETWORKS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tanggle:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "ggtree", "phangorn", "tanggle")
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
    library(tanggle)
    library(phangorn)
    library(ggtree)
    library(ggplot2)
    
    # 1. Read the split network Nexus file from the working directory
    input_file <- "woodmouse.nxs"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    Nnet <- phangorn::read.nexus.networx(input_file)
    
    # 2. Generate the base split network plot using ggsplitnet and add tip labels
    p1 <- ggsplitnet(Nnet) + geom_tiplab2()
    
    # 3. Adjust x and y axis limits to ensure labels are fully visible
    p2 <- p1 + xlim(-0.019, .003) + ylim(-.01, .012)
    
    # 4. Rename tip labels and customize tip/node aesthetics
    Nnet\$translate\$label <- seq_along(Nnet\$tip.label)
    
    p3 <- ggsplitnet(Nnet) + geom_tiplab2(col = "blue", font = 4, hjust = -0.15) + 
        geom_nodepoint(col = "green", size = 0.25)
    
    p4 <- ggsplitnet(Nnet) + geom_point(aes(shape = isTip, color = isTip), size = 2)
    
    # Save the generated plots to a multi-page PDF file
    pdf("split_networks_visualization.pdf", width = 10, height = 8)
    print(p1)
    print(p2)
    print(p3)
    print(p4)
    dev.off()
    
    # Save the processed network object
    saveRDS(Nnet, "processed_split_network.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TANGGLE_SPLIT_NETWORKS":
        tanggle: \$(Rscript -e 'cat(as.character(packageVersion("tanggle")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_split_networks.csv versions.yml
    """
}

workflow BIOC_TANGGLE_SPLIT_NETWORKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ woodmouse.nxs ] ]

    main:
    BIOC_TANGGLE_SPLIT_NETWORKS(ch_input)

    emit:
    tables   = BIOC_TANGGLE_SPLIT_NETWORKS.out.tables
    plots    = BIOC_TANGGLE_SPLIT_NETWORKS.out.plots
    objects  = BIOC_TANGGLE_SPLIT_NETWORKS.out.objects
    versions = BIOC_TANGGLE_SPLIT_NETWORKS.out.versions
}
