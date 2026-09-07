---@diagnostic disable: undefined-global

local no_new_player = {}

local SCRIPT_TAG = "[No New Player]"

-- ── Menu ──────────────────────────────────────────────────────────────────
local menu_tab = Menu.Create("General", "Scripts", "No New Player", "Settings")
local settings_group = menu_tab:Create("Settings")

local ui = {}
ui.enabled = settings_group:Switch("Enable", true)

settings_group:Label("While enabled, continuously sets dota_new_player to false.")
settings_group:Label("This disables the \"New Player\" mode in Dota 2.")

Log.Write(SCRIPT_TAG .. " Loaded")

-- ── State ─────────────────────────────────────────────────────────────────
local last_execute_t = -9999.0
local EXECUTE_INTERVAL = 2.0  -- seconds between re-applying the command

local function now_time()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
end

-- ── Callbacks ─────────────────────────────────────────────────────────────

--- Called every frame (in-game + menus). Re-applies the convar periodically.
function no_new_player.OnFrame()
	if not ui.enabled:Get() then
		return
	end

	local t = now_time()
	if (t - last_execute_t) < EXECUTE_INTERVAL then
		return
	end
	last_execute_t = t

	if Engine and Engine.ExecuteCommand then
		Engine.ExecuteCommand("dota_new_player false")
	end
end

return no_new_player
