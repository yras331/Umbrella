---@diagnostic disable: undefined-global

local creep_agro = {}

local SCRIPT_TAG = "[Creep Agro]"

-- ── Menu ──────────────────────────────────────────────────────────────────
local menu_tab = Menu.Create("General", "My Scripts", "Creep Agro", "Agro")
local settings_group = menu_tab:Create("Settings")

local ui = {}
ui.enabled = settings_group:Switch("Enable", true)
ui.agro_key = settings_group:Bind("Agro Key", Enum.ButtonCode.BUTTON_CODE_INVALID)
ui.agro_cooldown = settings_group:Slider("Cooldown (ms)", 100, 1000, 300)
ui.debug_logs = settings_group:Switch("Debug Logs", false)

settings_group:Label("Hold or tap the agro key to A-click the nearest visible enemy hero.")
settings_group:Label("Triggers creep agro within 500 range, then moves you back to where you stood.")
settings_group:Label("Your anchor position is captured the moment you first press the key.")

Log.Write(SCRIPT_TAG .. " Loaded")

-- ── Helpers ───────────────────────────────────────────────────────────────

local function now_time()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
end

local function log_debug(msg)
	if not ui.debug_logs or not ui.debug_logs.Get or not ui.debug_logs:Get() then return end
	if Log and Log.Write then
		Log.Write(SCRIPT_TAG .. " " .. tostring(msg))
	else
		print(SCRIPT_TAG .. " " .. tostring(msg))
	end
end

local function is_bind_down(bind)
	if not bind or not bind.Get then return false end
	local key = bind:Get()
	if not key or key == Enum.ButtonCode.BUTTON_CODE_INVALID then return false end
	return Input.IsKeyDown(key)
end

local function get_local_info()
	local player = Players and Players.GetLocal and Players.GetLocal() or nil
	local hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
	if not player or not hero then return nil, nil end
	if not Entity.IsAlive(hero) then return nil, nil end
	return player, hero
end

-- ── State ─────────────────────────────────────────────────────────────────
local last_agro_t = -1000.0
local was_key_down = false
local last_target_index = -1
local anchor_pos = nil  -- captured position when key is first pressed

-- ── Core Logic ────────────────────────────────────────────────────────────

local function find_nearest_visible_enemy_hero(hero)
	if not hero then return nil end
	local my_team = Entity.GetTeamNum(hero)
	local hero_pos = Entity.GetAbsOrigin(hero)
	if not hero_pos or not my_team then return nil end

	-- Search globally (large radius) for visible enemy heroes
	local enemies = Heroes.InRadius(hero_pos, 30000, my_team, Enum.TeamType.TEAM_ENEMY, true, true)
	if not enemies or #enemies == 0 then
		log_debug("No visible enemy heroes found")
		return nil
	end

	local best = nil
	local best_dist = math.huge

	for _, enemy in ipairs(enemies) do
		if enemy and enemy ~= hero and Entity.IsAlive(enemy) then
			-- Skip illusions
			if NPC and NPC.IsIllusion then
				local ok, is_illu = pcall(NPC.IsIllusion, enemy)
				if ok and is_illu then
					goto continue
				end
			end
			-- Skip invulnerable
			if Entity.IsInvulnerable then
				local ok, inv = pcall(Entity.IsInvulnerable, enemy)
				if ok and inv then
					goto continue
				end
			end

			local enemy_pos = Entity.GetAbsOrigin(enemy)
			if enemy_pos then
				local dist = (hero_pos.x - enemy_pos.x) ^ 2 + (hero_pos.y - enemy_pos.y) ^ 2
				if dist < best_dist then
					best_dist = dist
					best = enemy
				end
			end
		end
		::continue::
	end

	return best
end

local function do_agro(player, hero)
	if not player or not hero then return false end

	local enemy = find_nearest_visible_enemy_hero(hero)
	if not enemy then return false end

	local enemy_index = Entity.GetIndex(enemy)

	-- Issue attack order on the enemy hero (this triggers creep agro)
	if Player and Player.AttackTarget then
		Player.AttackTarget(
			player,
			hero,
			enemy,
			false,  -- queue
			false,  -- push
			true,   -- execute_fast
			"creep_agro_attack",
			true    -- force_minimap
		)
	end

	-- Immediately issue stop so the hero doesn't walk toward the enemy
	if Player and Player.PrepareUnitOrders and Enum then
		Player.PrepareUnitOrders(
			player,
			Enum.UnitOrder.DOTA_UNIT_ORDER_STOP,
			nil,
			Vector(0, 0, 0),
			nil,
			Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY,
			hero,
			false,  -- queue
			false,  -- show_effects
			false,  -- callback
			true,   -- execute_fast
			"creep_agro_stop",
			true    -- force_minimap
		)
	end

	-- Move back to the anchor position (captured when key was first pressed)
	if anchor_pos and NPC and NPC.MoveTo then
		NPC.MoveTo(hero, anchor_pos, false, false, false, true, "creep_agro_return", true)
	end

	last_target_index = enemy_index
	log_debug("Agro -> enemy #" .. tostring(enemy_index) .. " | back to anchor")
	return true
end

-- ── Callbacks ─────────────────────────────────────────────────────────────

function creep_agro.OnUpdate()
	if not ui.enabled:Get() then
		was_key_down = false
		anchor_pos = nil
		return
	end

	local key_down = is_bind_down(ui.agro_key)

	if not key_down then
		-- Key released: clear anchor
		if was_key_down then
			anchor_pos = nil
			log_debug("Key released, anchor cleared")
		end
		was_key_down = false
		return
	end

	local player, hero = get_local_info()
	if not player or not hero then
		anchor_pos = nil
		return
	end

	-- Key just pressed: capture anchor position
	if not was_key_down then
		anchor_pos = Entity.GetAbsOrigin(hero)
		if anchor_pos then
			log_debug("Anchor set at " .. tostring(anchor_pos))
		end
	end
	was_key_down = true

	local t = now_time()
	local cd = (ui.agro_cooldown and ui.agro_cooldown.Get and ui.agro_cooldown:Get()) or 300
	local cooldown_sec = cd / 1000.0

	if (t - last_agro_t) < cooldown_sec then
		return
	end

	last_agro_t = t
	do_agro(player, hero)
end

return creep_agro
