local _, Hooter = ...

-- Chat event → SendChatMessage chatType mapping
-- Used by Response.lua (direct sends) and Coordination.lua (coordinated sends)
Hooter.EVENT_TO_CHAT = {
    CHAT_MSG_PARTY         = "PARTY",
    CHAT_MSG_PARTY_LEADER  = "PARTY",
    CHAT_MSG_RAID          = "RAID",
    CHAT_MSG_RAID_LEADER   = "RAID",
    CHAT_MSG_GUILD         = "GUILD",
    CHAT_MSG_WHISPER       = "WHISPER",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
}

-- Chat events to scan for triggers
-- Used by Scanner.lua (event registration) and ChatLinks.lua (chat filters)
Hooter.CHAT_EVENTS = {
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_INSTANCE_CHAT",
}

-- Sharing protocol constants
Hooter.SHARE = {
    TTL             = 300,  -- seconds before cached share data expires
    PENDING_TIMEOUT = 30,   -- seconds before incomplete chunks are discarded
    MAX_CACHE       = 10,   -- maximum number of cached share entries
    CHUNK_DATA_SIZE = 235,  -- bytes of payload per addon message chunk
    MAX_CHUNKS      = 50,   -- sanity cap on total chunk count per share
}

-- Coordination protocol constants
Hooter.COORD = {
    JOIN_WINDOW   = 0.4,  -- seconds to collect JOIN messages before resolving
    CLEANUP_DELAY = 10,   -- seconds after which stale coordination state is purged
}

-- Guard for the 12.0+ secret values system.
--
-- While chat messaging lockdown is active (a Mythic+ run, a PvP match, or an
-- instance encounter in progress) the game hands CHAT_MSG_* payloads to Lua as
-- secret values.  Tainted code -- which means all addon code -- may store, pass
-- and concatenate secrets, but indexing, comparing or measuring them raises an
-- immediate Lua error, so even `message:find(...)` blows up.
--
-- Addons also cannot send chat or addon comms during lockdown, so there is
-- nothing useful Hooter could do with a restricted payload anyway: every
-- handler that receives chat data bails out early.
local issecretvalue = issecretvalue or function() return false end

function Hooter:IsChatRestricted(...)
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return true
    end
    -- Belt and braces, in case payloads are ever marked secret outside lockdown
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

-- Random delay within configured range (used by both direct and coordinated sends)
function Hooter:CalculateDelay()
    local min = self.db.settings.minDelay
    local max = self.db.settings.maxDelay
    return min + (math.random() * (max - min))
end
