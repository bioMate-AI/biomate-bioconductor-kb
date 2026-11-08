"""Load BioMate text weights, including the text backbone of Qwen3.5."""
def load_text_model(path, **kwargs):
    from transformers import AutoConfig, AutoModelForCausalLM, Qwen3_5ForCausalLM
    config = AutoConfig.from_pretrained(path)
    if config.model_type == "qwen3_5":
        model, info = Qwen3_5ForCausalLM.from_pretrained(
            path, config=config.text_config,
            key_mapping={r"^model\.language_model\.": "model."},
            output_loading_info=True, **kwargs)
    else:
        model, info = AutoModelForCausalLM.from_pretrained(path, output_loading_info=True, **kwargs)
    if info.get("missing_keys") or info.get("mismatched_keys") or info.get("error_msgs"):
        raise RuntimeError(f"Incomplete model load: {info}")
    unexpected = [key for key in info.get("unexpected_keys", [])
                  if not key.startswith(("model.visual.", "mtp."))]
    if unexpected:
        raise RuntimeError(f"Unexpected non-vision weights: {unexpected[:10]}")
    return model
