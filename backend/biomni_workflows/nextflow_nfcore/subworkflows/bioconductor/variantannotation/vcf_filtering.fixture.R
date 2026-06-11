# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("VariantAnnotation", "Rsamtools")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(VariantAnnotation)
library(Rsamtools)

# Generate a minimal VCF file matching the vignette's structure but for chromosome 7
vcf_text <- c(
  "##fileformat=VCFv4.1",
  "##INFO=<ID=LDAF,Number=1,Type=Float,Description=\"MLE Allele Frequency Accounting for LD\">",
  "##INFO=<ID=AVGPOST,Number=1,Type=Float,Description=\"Average posterior probability from MaCH/Thunder\">",
  "##INFO=<ID=RSQ,Number=1,Type=Float,Description=\"Genotype imputation quality from MaCH/Thunder\">",
  "##INFO=<ID=ERATE,Number=1,Type=Float,Description=\"Per-marker Mutation rate from MaCH/Thunder\">",
  "##INFO=<ID=THETA,Number=1,Type=Float,Description=\"Per-marker Transition rate from MaCH/Thunder\">",
  "##INFO=<ID=VT,Number=1,Type=String,Description=\"indicates what type of variant the line represents\">",
  "##INFO=<ID=SNPSOURCE,Number=.,Type=String,Description=\"indicates if a snp was called when analysing the low coverage or exome alignment data\">",
  "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">",
  "##FORMAT=<ID=DS,Number=1,Type=Float,Description=\"Genotype dosage from MaCH/Thunder\">",
  "##FORMAT=<ID=GL,Number=G,Type=Float,Description=\"Genotype Likelihoods\">",
  "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tHG00096\tHG00097\tHG00099\tHG00100\tHG00101",
  "7\t50300078\trs7410291\tA\tG\t100\tPASS\tLDAF=0.3431;AVGPOST=0.9890;RSQ=0.9856;ERATE=0.002;THETA=0.0005;VT=SNP\tGT:DS:GL\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5\t0|1:1:-5,-0.01,-5\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5",
  "7\t50300086\trs147922003\tC\tT\t100\tPASS\tLDAF=0.0091;AVGPOST=0.9963;RSQ=0.8398;ERATE=0.0005;THETA=0.0011;VT=SNP\tGT:DS:GL\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5",
  "7\t50300101\trs114143073\tG\tA\t100\tPASS\tLDAF=0.0098;AVGPOST=0.9891;RSQ=0.5919;ERATE=0.0007;THETA=0.0008;VT=SNP\tGT:DS:GL\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5\t0|0:0:-0.01,-0.5,-5"
)

# Write the raw VCF text to disk
writeLines(vcf_text, "chr7-sub.vcf")

# Compress with bgzip to create the required .vcf.gz file
bgzip("chr7-sub.vcf", "chr7-sub.vcf.gz", overwrite = TRUE)

# Create the Tabix index (.tbi) file
indexTabix("chr7-sub.vcf.gz", format = "vcf")

# Clean up the uncompressed intermediate file
unlink("chr7-sub.vcf")