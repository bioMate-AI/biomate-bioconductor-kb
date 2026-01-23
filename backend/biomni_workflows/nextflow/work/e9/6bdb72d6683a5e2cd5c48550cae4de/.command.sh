#!/bin/bash -ue
python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import annotate_plasmid

# Run the tool
try:
    result = annotate_plasmid(
    sequence="ATGAAACGCATTAGCACCACCATTACCACCACCATCACCATTACCACAGGTAACGGTGCGGGCTGA",
    is_circular=False
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("annotate_plasmid_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("annotate_plasmid_output.txt", "w") as f:
    f.write("Biomni: Annotate Plasmid Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("annotate_plasmid completed successfully")
PYEOF
