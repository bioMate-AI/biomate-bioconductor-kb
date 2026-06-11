library(DECIPHER)
library(RSQLite)

# 1. Prepare the GenBank file (gb)
gb_source <- system.file("extdata", "Bacteria_175seqs.gen", package="DECIPHER")
file.copy(gb_source, "gb", overwrite = TRUE)

# 2. Prepare the SQLite database (dbConn)
dbConn <- "dbConn"
if (file.exists(dbConn)) {
    file.remove(dbConn)
}

# Import sequences into the database
Seqs2DB("gb", "GenBank", dbConn, "Bacteria")

# Add taxonomic ranks and tiles to the database as per the vignette
IdentifyByRank(dbConn, level=Inf, add2tbl=TRUE)
TileSeqs(dbConn, add2tbl="Tiles")