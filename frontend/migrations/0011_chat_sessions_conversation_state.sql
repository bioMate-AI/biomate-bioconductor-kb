-- Add per-chat-session conversation state JSONB to chat_sessions
--
-- The conversationStateManager previously persisted state into the LTM-tier
-- `sessions` table (UUID primary key), but the frontend uses TEXT IDs of the
-- form `chat-<ts>-<rand>` for chat session_ids. Every load/save attempted on
-- a TEXT chat ID hit `invalid input syntax for type uuid` on PostgreSQL and
-- silently degraded to empty state, breaking cross-turn conversation context.
--
-- Fix: store conversation_state alongside the chat session it belongs to.

ALTER TABLE chat_sessions
  ADD COLUMN IF NOT EXISTS conversation_state JSONB;
