#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: magar — meth_qtl_from_plink
// Import pre-processed PLINK genotyping files and RnBeads methylation objects, call methQTLs, and perform downstream visualization and enrichment.
// Input: plink_data, rnb_set_dir, sample_annotation.csv
// Container: quay.io/biocontainers/bioconductor-magar:1.18.0--r45hdfd78af_0
// R packages: RnBeads, MAGAR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAGAR_METH_QTL_FROM_PLINK {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-magar:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("RnBeads", "MAGAR")
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
    suppressPackageStartupMessages(library(RnBeads))
    suppressPackageStartupMessages(library(MAGAR))
    
    # 1. Configure RnBeads options
    # Set options directly in RnBeads and serialize to XML to avoid system.file
    rnb.options(identifiers.column="geo_accession",
        import.idat.platform="probes450")
    xml.fi <- file.path(getwd(),"rnbeads_options.xml")
    cat(rnb.options2xml(),file=xml.fi)
    qtlSetOption(rnbeads.options = xml.fi)
    
    # 2. Import PLINK and RnBeads data using doImport
    geno.dir <- "plink_data"
    plink.dir <- geno.dir # Define plink.dir to match the vignette's list structure
    rnb.set <- load.rnb.set("rnb_set_dir")
    s.anno <- "sample_annotation.csv"
    data.loc <- list(idat.dir=rnb.set,geno.dir=plink.dir)
    
    qtlSetOption(geno.data.type="plink",
        meth.data.type="rnb.set")
    
    meth.qtl <- doImport(data.location=data.loc,
        s.anno=s.anno,
        s.id.col="SampleID",
        out.folder=getwd())
    
    # 3. Call methQTLs using doMethQTL
    # Use the imported meth.qtl object instead of the package's bundled demo data
    imp.data <- meth.qtl
    qtlSetOption(standard.deviation.gauss=100,
        cluster.cor.threshold=0.75)
    meth.qtl.res <- doMethQTL(imp.data,default.options=FALSE,p.val.cutoff=0.05)
    
    # Save the main methQTLResult object
    saveRDS(meth.qtl.res, file="meth_qtl_result.rds")
    
    # 4. Extract results and annotations using getResult and getAnno
    result.table <- getResult(meth.qtl.res)
    write.csv(result.table, "meth_qtl_results.csv", row.names=FALSE)
    
    anno.meth <- getAnno(meth.qtl.res,"meth")
    write.csv(anno.meth, "meth_annotations.csv", row.names=FALSE)
    
    anno.geno <- getAnno(meth.qtl.res,"geno")
    write.csv(anno.geno, "geno_annotations.csv", row.names=FALSE)
    
    # Print heads to stdout for logging
    print("Head of Result Table:")
    print(head(result.table))
    print("Head of Methylation Annotation:")
    print(head(anno.meth))
    print("Head of Genotype Annotation:")
    print(head(anno.geno))
    
    # 5. Visualize interactions using qtlPlotSNPCpGInteraction and qtlDistanceScatterplot
    result.table <- result.table[order(result.table\$P.value,decreasing=FALSE),]
    
    pdf("meth_qtl_plots.pdf", width=10, height=8)
    
    # Plot SNP-CpG interaction for the top association if results are not empty
    if (nrow(result.table) > 0) {
        tryCatch({
            p1 <- qtlPlotSNPCpGInteraction(imp.data, result.table\$CpG[1], result.table\$SNP[1])
            print(p1)
        }, error = function(e) {
            message("Could not generate SNP-CpG interaction plot: ", e\$message)
        })
    } else {
        message("No significant methQTLs found to plot interaction.")
    }
    
    # Plot distance scatterplot
    tryCatch({
        p2 <- qtlDistanceScatterplot(meth.qtl.res)
        print(p2)
    }, error = function(e) {
        message("Could not generate distance scatterplot: ", e\$message)
    })
    
    dev.off()
    
    # 6. Perform base substitution enrichment using qtlBaseSubstitutionEnrichment
    tryCatch({
        res <- qtlBaseSubstitutionEnrichment(meth.qtl.res)
        write.csv(res, "base_substitution_enrichment.csv", row.names=FALSE)
        print("Base Substitution Enrichment Results:")
        print(head(res))
    }, error = function(e) {
        message("Could not perform base substitution enrichment: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MAGAR_METH_QTL_FROM_PLINK":
        magar: \$(Rscript -e 'cat(as.character(packageVersion("magar")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meth_qtl_from_plink.csv versions.yml
    """
}

workflow BIOC_MAGAR_METH_QTL_FROM_PLINK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ plink_data, rnb_set_dir, sample_annotation.csv ] ]

    main:
    BIOC_MAGAR_METH_QTL_FROM_PLINK(ch_input)

    emit:
    tables   = BIOC_MAGAR_METH_QTL_FROM_PLINK.out.tables
    plots    = BIOC_MAGAR_METH_QTL_FROM_PLINK.out.plots
    objects  = BIOC_MAGAR_METH_QTL_FROM_PLINK.out.objects
    versions = BIOC_MAGAR_METH_QTL_FROM_PLINK.out.versions
}
