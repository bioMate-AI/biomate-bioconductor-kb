-- Per-user LLM provider API keys (encrypted at rest).
-- Allows users to supply their own Anthropic / future-provider keys
-- so their chats consume their own quota instead of BioMate's shared key.
-- Column stores AES-256-GCM ciphertext; server never returns the plaintext.
-- Schema: { anthropic?: string }  (extensible for OpenAI, Gemini, etc.)

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS llm_api_keys JSONB DEFAULT NULL;
