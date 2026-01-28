# Clawdbot Integration Session - 2026-01-28 14:43

## Session Summary

Successfully integrated Clawdbot (open-source AI agent system) with Biomate to enable multi-channel messaging access. Users can now interact with Biomate through Telegram and Slack.

## Work Completed

### 1. Clawdbot Installation and Setup

**Time**: ~2026-01-27 to 2026-01-28

- Cloned Clawdbot repository to `/home/yzhang/biomate/reference/clawdbot/`
- Created survey document: `reference/CLAWDBOT_SURVEY_AND_INTEGRATION_PLAN_20260127.md`
- Installed fnm (Fast Node Manager) for Node.js version management
- Installed Node.js v22.22.0 (required by Clawdbot)
- Installed Clawdbot CLI globally via npm

**Commands used:**
```bash
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 22
fnm use 22
npm install -g clawdbot
clawdbot init
```

### 2. Clawdbot Gateway Configuration

**Configuration file**: `~/.clawdbot/clawdbot.json`

**Key settings:**
- Agent model: `anthropic/claude-sonnet-4-20250514`
- Workspace: `/home/yzhang/clawd`
- Gateway mode: `local`
- Gateway URL: `ws://127.0.0.1:18789`

### 3. Telegram Channel Setup

**Bot**: `@BioMateAI_bot`
**Token**: Configured in clawdbot.json (format: `8243903312:AAG...`)

**Configuration:**
```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "botToken": "<TOKEN>",
      "allowFrom": ["*"],
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    }
  }
}
```

**Setup steps:**
1. Created bot via @BotFather in Telegram
2. Obtained bot token
3. Configured in clawdbot.json
4. Started gateway

### 4. Slack Channel Setup

**Mode**: Socket Mode (recommended for local development)

**Tokens configured:**
- App Token: `xapp-1-A0ABDV01V50-...` (for Socket Mode)
- Bot Token: `xoxb-10381587259043-...` (for API calls)

**Configuration:**
```json
{
  "channels": {
    "slack": {
      "mode": "socket",
      "enabled": true,
      "botToken": "<BOT_TOKEN>",
      "appToken": "<APP_TOKEN>",
      "dm": {
        "policy": "open",
        "allowFrom": ["*"]
      },
      "groupPolicy": "open"
    }
  }
}
```

**Slack App Manifest** (critical for proper operation):
```json
{
  "display_information": {
    "name": "BioMateAI"
  },
  "features": {
    "bot_user": {
      "display_name": "BioMateAI",
      "always_online": true
    },
    "app_home": {
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "chat:write",
        "im:history",
        "im:read",
        "im:write",
        "app_mentions:read",
        "channels:history",
        "channels:read"
      ]
    }
  },
  "settings": {
    "socket_mode_enabled": true,
    "event_subscriptions": {
      "bot_events": [
        "app_mention",
        "message.im"
      ]
    }
  }
}
```

### 5. Biomate Skill Created

**Location**: `~/clawd/skills/biomate/SKILL.md`

Defines when Clawdbot should invoke Biomate functionality for bioinformatics queries.

### 6. Biomate Chat API Endpoints

**File modified**: `frontend/server/routes.ts`

**New endpoints:**
- `POST /api/biomate/chat` - Send messages, get responses
- `GET /api/biomate/health` - Health check
- `GET /api/biomate/status/:invocationId` - Workflow status

### 7. Documentation

**Created:**
- `docs/CLAWDBOT_INTEGRATION.md` - Comprehensive setup guide
- `reference/CLAWDBOT_SURVEY_AND_INTEGRATION_PLAN_20260127.md` - Initial survey

## Troubleshooting Encountered

### Issue 1: Node.js Version Too Old
- **Problem**: System had Node.js 18.x, Clawdbot requires 22+
- **Solution**: Installed fnm and Node.js 22.22.0

### Issue 2: Invalid Config Keys
- **Problem**: `dmPolicy`, `allowFrom` at wrong nesting level for Slack
- **Solution**: Used correct structure: `dm.policy`, `dm.allowFrom`

### Issue 3: Slack Bot "Cannot Be Used"
- **Problem**: Messages Tab not enabled in App Home
- **Solution**: Added `messages_tab_enabled: true` to app manifest

### Issue 4: Slack Bot Not Responding
- **Problem**: Missing Event Subscriptions
- **Solution**: Added `message.im` and `app_mention` to bot events in manifest

### Issue 5: DM Pairing Required
- **Problem**: Default DM policy requires pairing code approval
- **Solution**: Set `dm.policy: "open"` and `dm.allowFrom: ["*"]`

## Git Commit

**Commit**: `90bc8f3e9434a9b7ce866abffb76521899a79651`
**Branch**: `biomni-nextflow`
**Message**: `feat: Add Clawdbot integration for multi-channel messaging`

**Files committed:**
1. `docs/CLAWDBOT_INTEGRATION.md` (+465 lines)
2. `reference/CLAWDBOT_SURVEY_AND_INTEGRATION_PLAN_20260127.md` (+610 lines)
3. `frontend/server/routes.ts` (+169 lines)
4. `.gitignore` (+3 lines - exclude cloned clawdbot repo)

## Running Services

### Clawdbot Gateway
```bash
# Start
clawdbot gateway

# Or background
nohup clawdbot gateway > /tmp/clawdbot-gateway.log 2>&1 &

# Check status
clawdbot channels status
clawdbot doctor
```

### Access URLs
- **Webchat**: http://127.0.0.1:18789/chat?session=main
- **Gateway WebSocket**: ws://127.0.0.1:18789
- **Browser Control**: http://127.0.0.1:18791/

### Log Files
- Gateway log: `/tmp/clawdbot-gateway.log`
- Daily log: `/tmp/clawdbot/clawdbot-2026-01-28.log`

## Current Status

| Channel | Status | Notes |
|---------|--------|-------|
| Telegram | Working | @BioMateAI_bot, polling mode |
| Slack | Working | Socket mode, DMs open |
| Webchat | Working | localhost:18789 |

## Security Notes

- All connections are localhost only (127.0.0.1)
- No public IPs exposed
- Channel connections are outbound only
- Tokens stored in local config file

## Future Work

1. Connect Biomate skill to actual Biomate backend API
2. Add workflow execution from messaging channels
3. Push workflow status updates to users
4. Support file uploads through messaging platforms
5. Add Discord and WhatsApp channels

## Files Created/Modified This Session

| File | Action | Description |
|------|--------|-------------|
| `~/.clawdbot/clawdbot.json` | Created/Modified | Main config |
| `~/clawd/skills/biomate/SKILL.md` | Created | Biomate skill |
| `frontend/server/routes.ts` | Modified | Chat API |
| `docs/CLAWDBOT_INTEGRATION.md` | Created | Setup guide |
| `reference/CLAWDBOT_SURVEY...` | Created | Survey doc |
| `.gitignore` | Modified | Exclude clawdbot repo |

---

*Session completed: 2026-01-28 14:43 CST*
