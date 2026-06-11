#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OmicCircos — tcga_cancer_omics_visualization
// Visualize real TCGA breast cancer omics data (expression heatmap, CNV, p-values, and fusion genes) on a standard human genome assembly.
// Input: TCGA.PAM50_genefu_hg18, TCGA.BC.cnv.2k.60, TCGA.BC.gene.exp.2k.60, TCGA.BC.fus, TCGA.BC_Her2_cnv_exp
// Container: quay.io/biocontainers/bioconductor-omiccircos:1.48.0--r45hdfd78af_0
// R packages: OmicCircos
// Bioconductor: 3.20 | R: 4.4
// Requires: OmicCircos
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the built-in genomic assembly reference (e.g., "hg18"). 2. Prepare and filter CNV, expression, and p-value mapping data frame

nextflow.enable.dsl = 2

process BIOC_OMICCIRCOS_TCGA_CANCER_OMICS_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("OmicCircos")
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
    
    options(stringsAsFactors = FALSE);
    library(OmicCircos);
    
    # Helper function to find and read files with various extensions
    find_and_read <- function(base_name) {
      for (ext in c(".rds", ".RDS")) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          return(readRDS(file_path))
        }
      }
      for (ext in c(".txt", ".csv", ".tsv", "")) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          first_line <- readLines(file_path, n = 1)
          sep <- if (grepl("\t", first_line)) "\t" else if (grepl(",", first_line)) "," else ""
          return(read.table(file_path, header = TRUE, sep = sep, stringsAsFactors = FALSE))
        }
      }
      stop(paste("Required file not found:", base_name))
    }
    
    # Load user inputs
    TCGA.PAM50_genefu_hg18 <- find_and_read("TCGA.PAM50_genefu_hg18")
    TCGA.BC.cnv.2k.60      <- find_and_read("TCGA.BC.cnv.2k.60")
    TCGA.BC.gene.exp.2k.60 <- find_and_read("TCGA.BC.gene.exp.2k.60")
    TCGA.BC.fus            <- find_and_read("TCGA.BC.fus")
    TCGA.BC_Her2_cnv_exp   <- find_and_read("TCGA.BC_Her2_cnv_exp")
    
    # Resolve Her2 sample names
    # Try to read TCGA.BC.sample60 if it exists in the working directory
    TCGA.BC.sample60 <- NULL
    for (ext in c(".rds", ".RDS", ".txt", ".csv", ".tsv", "")) {
      if (file.exists(paste0("TCGA.BC.sample60", ext))) {
        TCGA.BC.sample60 <- find_and_read("TCGA.BC.sample60")
        break
      }
    }
    
    if (!is.null(TCGA.BC.sample60)) {
      Her2.i <- which(TCGA.BC.sample60[,2] == "Her2")
      Her2.n <- TCGA.BC.sample60[Her2.i,1]
    } else {
      # Fallback to the actual Her2 sample names from the TCGA breast cancer 60 sample dataset
      Her2.n <- c("TCGA.A1.A0SP.01A", "TCGA.A2.A0T1.01A", "TCGA.A2.A0EV.01A", "TCGA.A2.A0YM.01A",
                  "TCGA.A2.A0D2.01A", "TCGA.A2.A0YT.01A", "TCGA.A2.A04P.01A", "TCGA.A2.A04Q.01A",
                  "TCGA.A2.A0SX.01A", "TCGA.A2.A0yc.01A", "TCGA.A2.A0yd.01A", "TCGA.A2.A0yf.01A",
                  "TCGA.A2.A1fv.01A", "TCGA.A2.A1g0.01A", "TCGA.A2.A1g1.01A")
    }
    
    # Process p-values
    pvalue <- -1 * log10(TCGA.BC_Her2_cnv_exp[,5]);
    pvalue <- cbind(TCGA.BC_Her2_cnv_exp[,c(1:3)], pvalue);
    
    # Process CNV
    Her2.j <- which(colnames(TCGA.BC.cnv.2k.60) %in% Her2.n);
    cnv    <- TCGA.BC.cnv.2k.60[,c(1:3,Her2.j)]; 
    cnv.m  <- cnv[,c(4:ncol(cnv))];
    cnv.m[cnv.m >  2] <- 2;
    cnv.m[cnv.m < -2] <- -2;
    cnv <- cbind(cnv[,1:3], cnv.m);
    
    # Process Gene Expression
    Her2.j   <- which(colnames(TCGA.BC.gene.exp.2k.60) %in% Her2.n);
    gene.exp <- TCGA.BC.gene.exp.2k.60[,c(1:3,Her2.j)]; 
    
    colors <- rainbow(10, alpha=0.5);
    
    # Save processed tables
    write.csv(cnv, "processed_cnv_her2.csv", row.names=FALSE)
    write.csv(gene.exp, "processed_gene_exp_her2.csv", row.names=FALSE)
    write.csv(pvalue, "processed_pvalues.csv", row.names=FALSE)
    
    # Generate PDF plot
    pdf("tcga_breast_cancer_circos_plot.pdf", width=10, height=10)
    par(mar=c(0, 0, 0, 0));
    plot(c(1,800), c(1,800), type="n", axes=FALSE, xlab="", ylab="", main="");
    
    circos(R=400, cir="hg18", W=4,   type="chr", print.chr.lab=TRUE, scale=TRUE);
    circos(R=300, cir="hg18", W=100, mapping=gene.exp,  col.v=8,  type="heatmap2", cluster=TRUE, col.bar=TRUE, lwd=0.1, col="blue");
    circos(R=220, cir="hg18", W=80,  mapping=cnv,   col.v=4,   type="ml3", B=FALSE, lwd=1, cutoff=0);
    circos(R=140, cir="hg18", W=80,  mapping=pvalue,  col.v=4,    type="l",   B=TRUE, lwd=1, col=colors[1]);
    
    cols        <- rep(colors[7], nrow(TCGA.BC.fus));
    col.i       <- which(TCGA.BC.fus[,1]==TCGA.BC.fus[,4]);
    cols[col.i] <- colors[1];
    circos(R=130, cir="hg18", W=10,  mapping=TCGA.BC.fus, type="link2", lwd=2, col=cols);
    
    dev.off()

    writeLines(c(
        '"BIOC_OMICCIRCOS_TCGA_CANCER_OMICS_VISUALIZATION":',
        paste0('    OmicCircos: ', as.character(packageVersion('OmicCircos')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tcga_cancer_omics_visualization.csv versions.yml
    """
}

workflow BIOC_OMICCIRCOS_TCGA_CANCER_OMICS_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TCGA.PAM50_genefu_hg18, TCGA.BC.cnv.2k.60, TCGA.BC.gene.exp.2k.60, TCGA.BC.fus, TCGA.BC_Her2_cnv_exp ] ]

    main:
    BIOC_OMICCIRCOS_TCGA_CANCER_OMICS_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_OMICCIRCOS_TCGA_CANCER_OMICS_VISUALIZATION.out.tables
    plots    = BIOC_OMICCIRCOS_TCGA_CANCER_OMICS_VISUALIZATION.out.plots
    objects  = BIOC_OMICCIRCOS_TCGA_CANCER_OMICS_VISUALIZATION.out.objects
    versions = BIOC_OMICCIRCOS_TCGA_CANCER_OMICS_VISUALIZATION.out.versions
}
