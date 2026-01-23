#!/usr/bin/env python3
"""Reduce text tokens for LLM context."""
import sys
import json

def reduce_tokens(text, max_tokens=4000, method="truncate"):
    """Reduce text to fit token limit.
    Args: text: input text, max_tokens: limit, method: truncate/summarize
    """
    # Rough estimate: 4 chars per token
    max_chars = max_tokens * 4
    if len(text) <= max_chars:
        return {"text": text, "reduced": False, "original_length": len(text)}
    
    if method == "truncate":
        reduced = text[:max_chars] + "..."
    else:
        reduced = text[:max_chars] + "..."
    
    return {"text": reduced, "reduced": True, "original_length": len(text), "new_length": len(reduced)}

def main():
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                try:
                    val = int(val)
                except ValueError:
                    pass
                args[key] = val
                i += 2
            else:
                i += 1
        else:
            i += 1
    output_path = args.pop('output', '/dev/stdout')
    result = reduce_tokens(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
