#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clstutils — reference_set_creation
// Identify mislabeled outlier sequences in a reference set and select a maximally diverse subset of representative sequences.
// Input: seqs, seqdat
// Container: quay.io/biocontainers/bioconductor-clstutils:1.58.0--r45hdfd78af_0
// R packages: ape, clst, clstutils
// Bioconductor: 3.20 | R: 4.4
// Requires: ape, clst, clstutils
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate DNA pairwise distances using ape::dist.dna
//  * 2. [Core Analysis] Identify outlier sequences using findOutliers
//  * 3. [Visualization & Output] Visualize outliers on a tree using prettyTree
//  * 4. [Core Analysis] Select a diverse subset of sequences using maxDists while excluding outliers

nextflow.enable.dsl = 2

process BIOC_CLSTUTILS_REFERENCE_SET_CREATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ape", "clst", "clstutils")
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
    library(ape)
    library(clst)
    library(clstutils)
    
    # 1. Read user input files from the working directory
    seqs <- readRDS("seqs.rds")
    seqdat <- readRDS("seqdat.rds")
    
    # Identify the taxon of interest dynamically.
    # Default to 'Enterococcus faecium' if present, otherwise use the most abundant taxon.
    if ("Enterococcus faecium" %in% seqdat\$tax_name) {
      taxon_name <- "Enterococcus faecium"
    } else if ("tax_name" %in% colnames(seqdat)) {
      taxon_name <- names(sort(table(seqdat\$tax_name), decreasing = TRUE))[1]
    } else {
      seqdat\$tax_name <- "Unknown Taxon"
      taxon_name <- "Unknown Taxon"
    }
    
    Efaecium <- which(seqdat\$tax_name == taxon_name)
    
    # Ensure necessary columns exist in seqdat to prevent runtime crashes on custom data
    if (!"isType" %in% colnames(seqdat)) {
      seqdat\$isType <- FALSE
      # Mark at least one sequence as type strain to ensure which(isType) is not empty
      seqdat\$isType[Efaecium[1]] <- TRUE
    }
    
    if (!"accession" %in% colnames(seqdat)) {
      seqdat\$accession <- rownames(seqdat)
      if (is.null(seqdat\$accession)) {
        seqdat\$accession <- as.character(1:nrow(seqdat))
      }
    }
    
    # 2. Calculate DNA pairwise distances using ape::dist.dna
    dmat <- ape::dist.dna(seqs[Efaecium,], pairwise.deletion=TRUE, as.matrix=TRUE, model='raw')
    
    # 3. Identify outlier sequences using findOutliers
    outliers <- clstutils::findOutliers(dmat, cutoff=0.015)
    
    # Add outlier status to seqdat for downstream steps
    seqdat\$outlier <- FALSE
    seqdat\$outlier[Efaecium] <- outliers
    
    # 4. Visualize outliers on a tree using prettyTree
    pdf("outliers_tree.pdf", width=10, height=8)
    with(seqdat[Efaecium,], {
      prettyTree(nj(dmat), groups=ifelse(outliers,'outlier','non-outlier'),
                 X=outliers, labels=ifelse(isType,gettextf('type strain (%s)', accession),NA))
    })
    dev.off()
    
    # 5. Select a diverse subset of sequences using maxDists while excluding outliers, and visualize
    pdf("selected_diverse_subset_tree.pdf", width=10, height=8)
    with(seqdat[Efaecium,], {
      selected <- clstutils::maxDists(dmat, idx=which(isType),
                                      N=10, exclude=outlier, include.center=TRUE)
      prettyTree(nj(dmat), groups=ifelse(outlier,'outlier','non-outlier'),
                 X=outlier,
                 O=selected, fill=selected,
                 labels=ifelse(isType,gettextf('type strain (%s)', accession),NA))
      
      # Export selected indices to the parent environment for saving
      selected_indices <<- selected
    })
    dev.off()
    
    # Save meaningful results to files
    seqdat\$selected <- FALSE
    seqdat\$selected[rownames(seqdat) %in% selected_indices] <- TRUE
    
    write.csv(seqdat[Efaecium, ], "taxon_analysis_results.csv", row.names=FALSE)
    saveRDS(selected_indices, "selected_indices.rds")

    writeLines(c(
        '"BIOC_CLSTUTILS_REFERENCE_SET_CREATION":',
        paste0('    clstutils: ', as.character(packageVersion('clstutils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_set_creation.csv versions.yml
    """
}

workflow BIOC_CLSTUTILS_REFERENCE_SET_CREATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seqs, seqdat ] ]

    main:
    BIOC_CLSTUTILS_REFERENCE_SET_CREATION(ch_input)

    emit:
    tables   = BIOC_CLSTUTILS_REFERENCE_SET_CREATION.out.tables
    plots    = BIOC_CLSTUTILS_REFERENCE_SET_CREATION.out.plots
    objects  = BIOC_CLSTUTILS_REFERENCE_SET_CREATION.out.objects
    versions = BIOC_CLSTUTILS_REFERENCE_SET_CREATION.out.versions
}
