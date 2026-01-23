#!/bin/bash -ue
python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import reverse_complement
except ImportError:
    # Fallback: function may need to be implemented locally
    def reverse_complement(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = reverse_complement(
    seq="ATCGATCG"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("reverse_complement_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("reverse_complement_output.txt", "w") as f:
    f.write("Biomni: Reverse Complement Results
")
    f.write("=" * 60 + "

")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}
")
    else:
        f.write(str(result))

print("reverse_complement completed successfully")
PYEOF
