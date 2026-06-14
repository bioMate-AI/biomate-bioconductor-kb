#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clstutils — reference_set_curation
// Identify taxonomic outliers and select a maximally diverse subset of reference sequences.
// Input: seqs, seqdat
// Container: quay.io/biocontainers/bioconductor-clstutils:1.58.0--r45hdfd78af_0
// R packages: ape, clst, clstutils
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: phylogenetic tree

nextflow.enable.dsl = 2

process BIOC_CLSTUTILS_REFERENCE_SET_CURATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-clstutils:1.58.0--r45hdfd78af_0"

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
    
    # -----------------------------------------------------------------------------
    # --- Read User Input Files ---
    # -----------------------------------------------------------------------------
    # The pipeline reads exactly these files from the working directory:
    # - seqs.rds: DNAbin object representing a multiple sequence alignment
    # - seqdat.rds: data.frame containing taxonomic assignments of the sequences
    seqs <- readRDS("seqs.rds")
    seqdat <- readRDS("seqdat.rds")
    
    # -----------------------------------------------------------------------------
    # --- Calculate pairwise DNA distances using ape::dist.dna ---
    # -----------------------------------------------------------------------------
    # Prepare taxonomic groupings
    seqdat\$i <- 1:nrow(seqdat)
    taxa <- split(seqdat, seqdat\$tax_name)
    
    # Identify the target taxon. We default to 'Enterococcus faecium' as in the
    # documented code, but fallback to the first available taxon if not present.
    target_taxon <- "Enterococcus faecium"
    if (!(target_taxon %in% names(taxa))) {
      target_taxon <- names(taxa)[1]
    }
    Efaecium <- taxa[[target_taxon]]\$i
    
    # Calculate distance matrix
    dmat <- ape::dist.dna(seqs[Efaecium,], pairwise.deletion=TRUE, as.matrix=TRUE, model='raw')
    
    # Save distance matrix to disk
    saveRDS(dmat, "distance_matrix.rds")
    
    # -----------------------------------------------------------------------------
    # --- Identify outlier sequences using findOutliers ---
    # -----------------------------------------------------------------------------
    outliers <- clstutils::findOutliers(dmat, cutoff=0.015)
    
    # Populate the outlier status back into seqdat for downstream steps
    seqdat\$outlier <- FALSE
    seqdat\$outlier[Efaecium] <- outliers
    
    # Save outlier detection results
    outliers_df <- data.frame(
      seqname = rownames(dmat),
      outlier = outliers
    )
    write.csv(outliers_df, "outliers.csv", row.names=FALSE)
    
    # -----------------------------------------------------------------------------
    # --- Visualize outliers on a phylogenetic tree using prettyTree ---
    # -----------------------------------------------------------------------------
    pdf("outliers_tree.pdf", width=10, height=10)
    with(seqdat[Efaecium,], {
      prettyTree(nj(dmat), groups=ifelse(outliers,'outlier','non-outlier'),
                 X=outliers, labels=ifelse(isType,gettextf('type strain (%s)', accession),NA))
    })
    dev.off()
    
    # -----------------------------------------------------------------------------
    # --- Select a diverse subset of sequences using maxDists ---
    # -----------------------------------------------------------------------------
    # We will capture the selected indices to write them to a file
    selected_indices <- NULL
    
    pdf("selected_subset_tree.pdf", width=10, height=10)
    with(seqdat[Efaecium,], {
      selected <- clstutils::maxDists(dmat, idx=which(isType),
                                      N=10, exclude=outlier, include.center=TRUE)
      
      # ---------------------------------------------------------------------------
      # --- Visualize the selected subset on the tree using prettyTree ---
      # ---------------------------------------------------------------------------
      prettyTree(nj(dmat), groups=ifelse(outlier,'outlier','non-outlier'),
                 X=outlier,
                 O=selected, fill=selected,
                 labels=ifelse(isType,gettextf('type strain (%s)', accession),NA))
      
      selected_indices <<- selected
    })
    dev.off()
    
    # Save selected subset results
    selected_df <- data.frame(
      index = selected_indices,
      seqname = rownames(dmat)[selected_indices]
    )
    write.csv(selected_df, "selected_sequences.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_CLSTUTILS_REFERENCE_SET_CURATION":',
        paste0('        clstutils: ', as.character(packageVersion("clstutils")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_set_curation.csv versions.yml
    """
}

workflow BIOC_CLSTUTILS_REFERENCE_SET_CURATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seqs, seqdat ] ]

    main:
    BIOC_CLSTUTILS_REFERENCE_SET_CURATION(ch_input)

    emit:
    tables   = BIOC_CLSTUTILS_REFERENCE_SET_CURATION.out.tables
    plots    = BIOC_CLSTUTILS_REFERENCE_SET_CURATION.out.plots
    objects  = BIOC_CLSTUTILS_REFERENCE_SET_CURATION.out.objects
    versions = BIOC_CLSTUTILS_REFERENCE_SET_CURATION.out.versions
}
