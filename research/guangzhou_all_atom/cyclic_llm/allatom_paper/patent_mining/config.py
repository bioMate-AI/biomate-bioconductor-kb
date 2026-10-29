"""K4 patent mining configuration. Frozen by docs/20261031_ALLATOM_PATENT_PREREG.md (committed before any extraction)."""
# CPC codes VERIFIED against the USPTO CPC scheme page (cpc-C07K.html, opened 2026-10-29): cyclic peptide groups.
CPC_VERIFIED = ["C07K7/50", "C07K7/52", "C07K7/54", "C07K7/56", "C07K7/58", "C07K7/60", "C07K7/62", "C07K7/64", "C07K7/645", "C07K7/66"]
# Query hints only (title NOT confirmed from the opened page): used as a hint, never as a verified filter.
CPC_HINTS_UNVERIFIED = ["A61K38/12"]
SURECHEMBL_BASE = "https://ftp.ebi.ac.uk/pub/databases/chembl/SureChEMBL/bulk_data/2026-05-15"
SURECHEMBL_FILES = ["compounds.parquet", "patent_compound_map.parquet", "patents.parquet", "fields.parquet"]
BINDINGDB_PATENT_TSV = "https://www.bindingdb.org/rwd/bind/downloads/BindingDB_Patents_202610_tsv.zip"
GP_URL = "https://patents.google.com/patent/{pn}/en"      # robots.txt: Allow /patent/ (checked 2026-10-29)
GP_DELAY_S = 2.5                                         # polite fixed delay between requests
GP_UA = "BioMate-research-knowledge-extraction/1.0 (academic literature mining; contact via repository owner)"
YEAR_MIN = 2000
PILOT_N = 200
PILOT_TOP, PILOT_RANDOM = 120, 80          # top by macrocyclic-peptide compound count + random from the next tier
MODEL = "Qwen/Qwen3-8B"                    # same open-weight model as K2
# peptide-macrocycle compound filter (RDKit on EC2): ring >= 12 atoms and >= 3 amide bonds in/attached to the ring system
MIN_RING, MIN_AMIDES = 12, 3
MW_MIN, MW_MAX = 500.0, 2600.0
