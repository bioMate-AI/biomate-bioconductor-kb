library(ballgown)

data_directory <- system.file('extdata', package='ballgown')
files_to_copy <- c("e_data.ctab", "i_data.ctab", "t_data.ctab", "e2t.ctab", "i2t.ctab")

for (f in files_to_copy) {
    found <- list.files(data_directory, pattern = paste0("^", f, "$"), recursive = TRUE, full.names = TRUE)
    if (length(found) > 0) {
        file.copy(found[1], f, overwrite = TRUE)
    } else {
        # Fallback dummy data matching the exact expected format if not found
        if (f == "e_data.ctab") {
            df <- data.frame(e_id=1, chr="chr1", strand="+", start=1, end=100, 
                             rcount=10, ucount=10, mrcount=10, cov=1, cov_sd=0, mcov=1, mcov_sd=0)
        } else if (f == "i_data.ctab") {
            df <- data.frame(i_id=1, chr="chr1", strand="+", start=101, end=200, 
                             rcount=5, ucount=5, mrcount=5)
        } else if (f == "t_data.ctab") {
            df <- data.frame(t_id=1, chr="chr1", strand="+", start=1, end=200, 
                             t_name="t1", num_exons=2, length=200, gene_id="g1", gene_name="gene1", cov=1, FPKM=10)
        } else if (f == "e2t.ctab") {
            df <- data.frame(e_id=1, t_id=1)
        } else if (f == "i2t.ctab") {
            df <- data.frame(i_id=1, t_id=1)
        }
        write.table(df, f, sep="\t", quote=FALSE, row.names=FALSE)
    }
}