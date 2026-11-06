"""Download the PeptideCLM-2 DATA files (config, tokenizer, weights; never the repo's .py) at a pinned commit and verify sha256.
usage: python3 fetch_weights.py small|base [DEST]   (DEST default: $PCLM2_DIR or ~/.cache/ihlm_backbone/pclm2). No code from the repo is downloaded or run."""
import os, sys, hashlib, urllib.request
PIN = {"small": ("7fe899df4d9753224aefa955ed0cf859d181e693", "713fb214c51d42bd038b4dd71928ea5f5e0c3c2cf58be1fce8345cc395ef5f4a"),
       "base": ("d4e8bafa378b8670d178029d6f97af5a5ee209fc", "2ee9244b84ff636080bbb7ef874d4a2d5159f70a8518f67a5065ff13fcab54e3")}
FILES = ["config.json", "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json", "model.safetensors"]   # NOT ChemPepMTR.py / config.py / __init__.py

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()

def fetch(size, dest=None):
    dest = dest or os.environ.get("PCLM2_DIR") or os.path.expanduser("~/.cache/ihlm_backbone/pclm2"); d = os.path.join(dest, size); os.makedirs(d, exist_ok=True)
    commit, wsha = PIN[size]
    for f in FILES:
        p = os.path.join(d, f)
        if not os.path.exists(p): urllib.request.urlretrieve(f"https://huggingface.co/aaronfeller/peptideclm-2-mlm-{size}/resolve/{commit}/{f}", p)
    got = sha256(os.path.join(d, "model.safetensors"))
    if got != wsha: raise RuntimeError(f"weights sha256 mismatch for {size}: {got} != {wsha}")
    return d

if __name__ == "__main__":
    print(fetch(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None))
