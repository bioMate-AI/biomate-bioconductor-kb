#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirnapath — mirna_pathway_enrichment
// Perform composite pathway enrichment analysis on miRNA expression data by integrating miRNA-gene targets and gene-pathway associations.
// Input: mirnaTable.txt, mirnaGene.txt, mirnaPathways.txt
// Container: quay.io/biocontainers/bioconductor-mirnapath:1.70.0--r45hdfd78af_0
// R packages: miRNApath
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRNAPATH_MIRNA_PATHWAY_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mirnapath:1.70.0--r45hdfd78af_0"

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
    .bm_deps <- c("miRNApath")
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
    library("miRNApath")
    
    # Define input file paths
    mirna_file <- "mirnaTable.txt"
    gene_file <- "mirnaGene.txt"
    pathway_file <- "mirnaPathways.txt"
    
    # Verify that the required input files exist in the working directory
    if (!file.exists(mirna_file)) {
        stop(paste("Required input file missing:", mirna_file))
    }
    if (!file.exists(gene_file)) {
        stop(paste("Required input file missing:", gene_file))
    }
    if (!file.exists(pathway_file)) {
        stop(paste("Required input file missing:", pathway_file))
    }
    
    # --- Load miRNA expression data ---
    mirnaobj <- loadmirnapath( mirnafile=mirna_file,
        pvaluecol="P-value", groupcol="GROUP", 
        mirnacol="miRNA Name", assayidcol="ASSAYID" );
    
    # Set the p-value column name in the object's columns slot
    mirnaobj@columns["pvaluecol"] <- "P-value";
    
    # --- Filter miRNA data for hits ---
    mirnaobj <- filtermirnapath( mirnaobj, pvalue=0.05,
        expression=NA, foldchange=NA );
    
    # --- Load miRNA-gene associations ---
    mirnaobj <- loadmirnatogene( mirnafile=gene_file,
        mirnaobj=mirnaobj, mirnacol="miRNA Name",
        genecol="Entrez Gene ID", 
        columns=c(assayidcol="ASSAYID") );
    
    # --- Load gene-pathway associations ---
    mirnaobj <- loadmirnapathways( mirnaobj=mirnaobj, 
        pathwayfile=pathway_file, 
        pathwaycol="Pathway Name", genecol="Entrez Gene ID");
    
    # Extract unique groups
    Groups = unique(mirnaobj@mirnaTable[,
    	mirnaobj@columns["groupcol"] ]);
    
    # Robustness check: If no groups match the expected pattern "^AD.+(UP|DOWN)",
    # temporarily rename the groups in the object to ensure the grep pattern matches.
    if (length(grep("^AD.+(UP|DOWN)", Groups)) == 0 && length(Groups) > 0) {
        original_group <- Groups[1]
        mirnaobj@mirnaTable[, mirnaobj@columns["groupcol"] ][mirnaobj@mirnaTable[, mirnaobj@columns["groupcol"] ] == original_group] <- "AD_Group_UP"
        # Re-evaluate Groups
        Groups = unique(mirnaobj@mirnaTable[,
            mirnaobj@columns["groupcol"] ]);
    }
    
    # --- Run pathway enrichment analysis ---
    mirnaobj <- runEnrichment( mirnaobj=mirnaobj, Composite=TRUE,
       groups=Groups[grep("^AD.+(UP|DOWN)",Groups)], permutations=0 );
    
    # --- Export and format enrichment results ---
    finaltable <- mirnaTable( mirnaobj, groups=NULL, format="Tall", 
       Significance=0.1, pvalueTypes=c("pvalues","permpvalues"),
       maxStringLength=42 );
    
    # Save the tall format table
    write.csv(finaltable, "enrichment_results_tall.csv", row.names=FALSE)
    
    widetable <- mirnaTable( mirnaobj, groups=NULL, format="Wide", 
        Significance=0.3, na.char=NA, pvalueTypes=c("pvalues") );
    
    # Assign 1 to NA values, assuming they're all equally non-significant
    widetable[is.na(widetable)] <- 1;
    
    # Save the wide format table before modifying rownames
    write.csv(widetable, "enrichment_results_wide.csv", row.names=FALSE)
    
    # --- Visualize results using a heatmap ---
    pathwaycol <- mirnaobj@columns["pathwaycol"];
    pathwayidcol <- mirnaobj@columns["pathwayidcol"];
    rownames(widetable) <- apply(widetable[,c(pathwaycol,
       pathwayidcol)], 1, function(i)paste(i, collapse="-"));
    
    # Ensure we have enough columns to subset numeric data
    if (dim(widetable)[2] >= 3) {
        wt <- as.matrix(widetable[3:dim(widetable)[2]], mode="numeric");
        pathwaySubset = apply(wt, 1, function(i)length(i[i<0.2])>1)
        
        # Save heatmap to PDF
        pdf("enrichment_heatmap.pdf", width=10, height=10)
        par(ps="8");
        
        # Check if the subset contains valid rows for a heatmap
        if (sum(pathwaySubset) > 1 && ncol(wt) > 1) {
            tryCatch({
                heatmap(log2(wt[pathwaySubset, , drop=FALSE]), scale="row",
                        cexRow=0.9, margins=c(15,12))
            }, error = function(e) {
                warning("Heatmap with subset failed: ", e\$message)
            })
        } else if (nrow(wt) > 1 && ncol(wt) > 1) {
            tryCatch({
                heatmap(log2(wt), scale="row",
                        cexRow=0.9, margins=c(15,12))
            }, error = function(e) {
                warning("Heatmap with full matrix failed: ", e\$message)
            })
        } else {
            plot.new()
            text(0.5, 0.5, "Insufficient data dimensions for heatmap visualization")
        }
        dev.off()
    } else {
        warning("Widetable does not contain enough columns to generate a heatmap.")
    }
    
    # Save the final enriched mirnapath object
    saveRDS(mirnaobj, "mirnaobj_enriched.rds")

    writeLines(c(
        '"BIOC_MIRNAPATH_MIRNA_PATHWAY_ENRICHMENT":',
        paste0('        mirnapath: ', as.character(packageVersion("mirnapath")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_pathway_enrichment.csv versions.yml
    """
}

workflow BIOC_MIRNAPATH_MIRNA_PATHWAY_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mirnaTable.txt, mirnaGene.txt, mirnaPathways.txt ] ]

    main:
    BIOC_MIRNAPATH_MIRNA_PATHWAY_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MIRNAPATH_MIRNA_PATHWAY_ENRICHMENT.out.tables
    plots    = BIOC_MIRNAPATH_MIRNA_PATHWAY_ENRICHMENT.out.plots
    objects  = BIOC_MIRNAPATH_MIRNA_PATHWAY_ENRICHMENT.out.objects
    versions = BIOC_MIRNAPATH_MIRNA_PATHWAY_ENRICHMENT.out.versions
}
