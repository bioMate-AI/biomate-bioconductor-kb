#!/bin/bash -ue
python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import digest_sequence

# Run the tool
try:
    result = digest_sequence(
    dna_sequence="GAATTCATCGATCGGAATTC",
    enzyme_names="EcoRI",
    is_circular=False
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("digest_sequence_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("digest_sequence_output.txt", "w") as f:
    f.write("Biomni: Digest Sequence Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("digest_sequence completed successfully")
PYEOF
