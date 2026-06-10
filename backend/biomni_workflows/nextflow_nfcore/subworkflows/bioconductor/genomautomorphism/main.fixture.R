library(Biostrings)
library(GenomAutomorphism)

data(covid_aln, package = "GenomAutomorphism")

saveRDS(covid_aln, "covid_aln.rds")
saveRDS(covid_aln, "covid_aln")
Biostrings::write.XStringSet(as(covid_aln, "DNAStringSet"), "covid_aln.fasta")
Biostrings::write.XStringSet(as(covid_aln, "DNAStringSet"), "covid_aln.fa")