---@diagnostic disable: undefined-global
-- Copy of smoke_detector.lua: only triggers when ENEMY uses smoke (not your team).
-- Uses API: Players.GetLocal(), Entity.IsSameTeam(entity1, entity2).

local smoke_detector_enemy_only = {}

-- Create menu
local menu_tab = Menu.Create("General", "Scripts", "Smoke Detector (Enemy Only)", "Detector")
local main_group = menu_tab:Create("Settings")

local ui = {}
ui.enabled = main_group:Switch("Enabled", true)
ui.debug_log = main_group:Switch("Debug (log entity/team per particle)", false)

ui.minimap_duration = main_group:Slider("Minimap Duration (s)", 1, 60, 20)
ui.minimap_alpha = main_group:Slider("Minimap Translucency", 0, 255, 120)
ui.center_duration = main_group:Slider("Center Alert Duration (s)", 1, 5, 1)
ui.center_alpha = main_group:Slider("Center Alert Translucency", 0, 255, 200)

local SCRIPT_TAG = "[Smoke Detector Enemy Only]"
Log.Write(SCRIPT_TAG .. " Loaded")

-- Settings
local SMOKE_LINGER_TIME = 20.0  -- seconds to show smoke indicator (menu overrides)
local CENTER_ICON_DURATION = 1.0  -- seconds to show center screen icon (menu overrides)
local CENTER_ICON_FADE_TIME = 0.3  -- seconds for fade out animation

-- Smoke tracking
local smoke_uses = {}  -- {pos = Vector, time = number, team = number}

-- Particle tracking (best chance to detect out-of-vision if replicated)
-- Store entity_id so we can resolve entity via Entity.Get(entity_id) when data.entity is nil (API: OnParticleCreate has entity_id).
local tracked_particles = {} -- [index] = {fullName, name, created_t, entity, entity_id, team, triggered, last_pos_by_cp = {}}
local last_smoke_added_t = -1000.0

-- Only trigger on the exact smoke particle we saw in logs.
local SMOKE_PARTICLE_FULLNAME = "particles/items2_fx/smoke_of_deceit.vpcf"
local SMOKE_PARTICLE_NAME = "smoke_of_deceit"

-- UI assets (lazy-loaded)
local SMOKE_ICON_PATH = "images/MenuIcons/Dota/smoke.png"
local smoke_icon_handle = nil
local smoke_icon_load_failed = false

-- Colors
local PURPLE_COLOR = Color(128, 0, 128, 200)  -- Purple for circle
local ICON_COLOR_START = Color(255, 255, 255, 255)  -- White, full opacity
local ICON_COLOR_END = Color(255, 255, 255, 0)  -- White, transparent

local function now_time()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
end

local function get_minimap_linger_time()
	if ui.minimap_duration and ui.minimap_duration.Get then
		return tonumber(ui.minimap_duration:Get()) or SMOKE_LINGER_TIME
	end
	return SMOKE_LINGER_TIME
end

local function get_minimap_alpha()
	if ui.minimap_alpha and ui.minimap_alpha.Get then
		local a = tonumber(ui.minimap_alpha:Get()) or 120
		return math.max(0, math.min(255, a))
	end
	return 120
end

local function get_center_duration()
	if ui.center_duration and ui.center_duration.Get then
		return tonumber(ui.center_duration:Get()) or CENTER_ICON_DURATION
	end
	return CENTER_ICON_DURATION
end

local function get_center_max_alpha()
	if ui.center_alpha and ui.center_alpha.Get then
		local a = tonumber(ui.center_alpha:Get()) or 200
		return math.max(0, math.min(255, a))
	end
	return 200
end

local function normalize_str(s)
	if not s then
		return ""
	end
	return string.lower(tostring(s))
end

local function is_smoke_particle_name(particle_full_name, particle_name)
	local full_name = normalize_str(particle_full_name)
	local short_name = normalize_str(particle_name)
	return (full_name == SMOKE_PARTICLE_FULLNAME) or (short_name == SMOKE_PARTICLE_NAME)
end

-- Get local player or hero entity for team comparison (API: Players.GetLocal, Heroes.GetLocal).
local function get_local_entity()
	if Players and Players.GetLocal then
		local p = Players.GetLocal()
		if p then return p end
	end
	if Heroes and Heroes.GetLocal then
		local h = Heroes.GetLocal()
		if h then return h end
	end
	return nil
end

-- Get local team number (Entity.GetTeamNum). Returns nil if unknown.
local function get_local_team_num()
	local local_ent = get_local_entity()
	if not local_ent or not Entity or not Entity.GetTeamNum then
		return nil
	end
	return Entity.GetTeamNum(local_ent)
end

-- Returns true if the smoke should be shown (only when enemy team used it).
-- smoke_entity = entity that created the particle (unit that used smoke); can be nil.
-- smoke_team_num = optional Enum.TeamNum from particle (Entity.GetTeamNum on particle entity).
-- Uses multiple fallbacks so enemy smoke still triggers when entity is nil or team comes from particle only.
local function is_enemy_smoke(smoke_entity, smoke_team_num)
	local local_ent = get_local_entity()
	local local_team = get_local_team_num()

	-- Fallback 1: No local reference (menus / not in game) -> don't show
	if not local_ent and local_team == nil then
		return false
	end

	-- Fallback 2: We have numeric team from particle and local team -> compare numbers (Enum.TeamNum).
	-- Catches enemy smoke when particle only gives team, not entity.
	if smoke_team_num ~= nil and local_team ~= nil and Entity then
		local team_smoke = smoke_team_num
		if team_smoke ~= local_team then
			-- TEAM_NONE / invalid: don't treat as enemy
			if Enum and Enum.TeamNum then
				local tn = Enum.TeamNum
				if (team_smoke == tn.TEAM_RADIANT or team_smoke == tn.TEAM_DIRE)
					and (local_team == tn.TEAM_RADIANT or local_team == tn.TEAM_DIRE) then
					return true
				end
			else
				-- No enum: assume different numbers = enemy
				return true
			end
		else
			-- Same team number = ally, never show
			return false
		end
	end

	-- Primary: entity present -> use Entity.IsSameTeam(smoke_entity, local_ent).
	if smoke_entity and local_ent and Entity and Entity.IsSameTeam then
		local same = Entity.IsSameTeam(smoke_entity, local_ent)
		if same then return false end
		return true
	end

	-- Fallback 3: entity present but IsSameTeam missing -> use GetTeamNum on both.
	if smoke_entity and local_ent and Entity and Entity.GetTeamNum then
		local st = Entity.GetTeamNum(smoke_entity)
		local lt = Entity.GetTeamNum(local_ent)
		if st ~= nil and lt ~= nil and st ~= lt then
			if Enum and Enum.TeamNum then
				local tn = Enum.TeamNum
				if (st == tn.TEAM_RADIANT or st == tn.TEAM_DIRE) and (lt == tn.TEAM_RADIANT or lt == tn.TEAM_DIRE) then
					return true
				end
			else
				return true
			end
		elseif st ~= nil and lt ~= nil and st == lt then
			return false
		end
	end

	-- Fallback 4: particle entity might be item/child -> check RecursiveGetOwner (root = hero/player).
	if smoke_entity and local_ent and Entity then
		local owner = nil
		if Entity.RecursiveGetOwner then
			owner = Entity.RecursiveGetOwner(smoke_entity)
		elseif Entity.GetOwner then
			owner = Entity.GetOwner(smoke_entity)
		end
		if owner then
			if Entity.IsSameTeam and Entity.IsSameTeam(owner, local_ent) then
				return false
			end
			if Entity.GetTeamNum then
				local ot = Entity.GetTeamNum(owner)
				local lt = Entity.GetTeamNum(local_ent)
				if ot ~= nil and lt ~= nil and ot ~= lt then
					if Enum and Enum.TeamNum then
						local tn = Enum.TeamNum
						if (ot == tn.TEAM_RADIANT or ot == tn.TEAM_DIRE) and (lt == tn.TEAM_RADIANT or lt == tn.TEAM_DIRE) then
							return true
						end
					else
						return true
					end
				elseif ot ~= nil and lt ~= nil and ot == lt then
					return false
				end
			end
		end
	end

	-- No entity and no conclusive team comparison above -> don't show.
	-- (Ally smoke often has nil particle entity; showing here caused ally smoke to trigger.)
	if not smoke_entity then
		return false
	end

	return false
end

local function try_add_smoke_marker(pos, team, source, smoke_entity)
	if not pos then
		return
	end

	-- Only show when enemy used smoke (pass numeric team for fallbacks when entity is nil)
	if not is_enemy_smoke(smoke_entity, team) then
		return
	end

	local t = now_time()
	-- De-dupe bursts (smoke can create multiple particles/updates)
	if (t - last_smoke_added_t) < 0.5 then
		return
	end
	last_smoke_added_t = t

	table.insert(smoke_uses, {
		pos = pos,
		time = t,
		team = team or -1,
		detected = true,
		source = source or "unknown",
	})

	Log.Write(SCRIPT_TAG .. " SMOKE DETECTED (enemy) (" .. tostring(source or "?") .. ") at " .. tostring(pos))
end

local function draw_minimap_circles()
	local t = now_time()
	local linger = get_minimap_linger_time()
	local alpha = get_minimap_alpha()

	-- Remove old smoke uses
	local i = 1
	while i <= #smoke_uses do
		if (t - smoke_uses[i].time) > linger then
			table.remove(smoke_uses, i)
		else
			i = i + 1
		end
	end

	-- Draw circles on minimap for active smoke uses
	for idx, smoke_data in ipairs(smoke_uses) do
		local age = t - smoke_data.time
		if age <= linger then
			-- Draw purple circle on minimap
			if MiniMap and MiniMap.DrawCircle then
				MiniMap.DrawCircle(smoke_data.pos, 128, 0, 128, alpha, 1520)
				MiniMap.DrawCircle(smoke_data.pos, 128, 0, 128, alpha, 1600)
				MiniMap.DrawCircle(smoke_data.pos, 128, 0, 128, alpha, 1680)
			end
		end
	end
end

local function draw_center_screen_icon()
	local t = now_time()
	local duration = get_center_duration()
	local max_alpha = get_center_max_alpha()
	local fade_time = math.min(CENTER_ICON_FADE_TIME, duration)

	-- Find the most recent smoke use
	local most_recent = nil
	for _, smoke_data in ipairs(smoke_uses) do
		local age = t - smoke_data.time
		if age <= duration then
			if not most_recent or smoke_data.time > most_recent.time then
				most_recent = smoke_data
			end
		end
	end

	if most_recent then
		local age = t - most_recent.time

		-- Calculate alpha based on age (fade out in last portion)
		local alpha = max_alpha
		if fade_time > 0 and age > (duration - fade_time) then
			local fade_progress = (age - (duration - fade_time)) / fade_time
			alpha = math.floor(max_alpha * (1.0 - fade_progress))
		end

		-- Prefer Render v2 (present in your build; Renderer.GetScreenSize appears missing)
		if Render and Render.ScreenSize and Render.ImageCentered and Render.LoadImage then
			local ss = Render.ScreenSize()
			if ss and ss.x and ss.y then
				local center = Vec2(ss.x / 2.0, ss.y / 2.0)
				local icon_size = Vec2(300.0, 300.0)
				local a = math.max(0, math.min(255, alpha))
				local global_alpha = a / 255.0
				Render.SetGlobalAlpha(global_alpha)

				-- Always draw a purple backdrop so the alert is visible on any background.
				local backdrop_a = math.floor((180 * a) / 255)
				local outline_a = math.floor((220 * a) / 255)
				Render.FilledCircle(center, 155.0, Color(128, 0, 128, backdrop_a))
				Render.Circle(center, 155.0, Color(255, 255, 255, outline_a), 3.0)

				if not smoke_icon_handle and not smoke_icon_load_failed then
					local ok, handle = pcall(Render.LoadImage, SMOKE_ICON_PATH)
					if ok and handle then
						smoke_icon_handle = handle
					else
						smoke_icon_load_failed = true
					end
				end

				if smoke_icon_handle then
					Render.ImageCentered(smoke_icon_handle, center, icon_size, Color(255, 255, 255, 255))
				else
					-- Fallback: draw a big purple filled circle if image couldn't be loaded
					Render.FilledCircle(center, 140.0, Color(128, 0, 128, 255))
					Render.Circle(center, 140.0, Color(255, 255, 255, 255), 3.0)
				end

				Render.ResetGlobalAlpha()
				return
			end
		end
	end
end

function smoke_detector_enemy_only.OnDraw()
	if not ui.enabled:Get() then
		return
	end

	draw_minimap_circles()
	draw_center_screen_icon()
end

-- Particle-based detection
function smoke_detector_enemy_only.OnParticleCreate(data)
	if not ui.enabled:Get() then
		return
	end
	if not data or not data.index then
		return
	end

	if is_smoke_particle_name(data.fullName, data.name) then
		local team = nil
		local ent = data.entity
		-- API: OnParticleCreate can have entity nil but entity_id (integer) set; resolve via Entity.Get(entity_id).
		if not ent and data.entity_id and Entity and Entity.Get then
			ent = Entity.Get(data.entity_id)
		end
		if ent and Entity and Entity.GetTeamNum then
			team = Entity.GetTeamNum(ent)
		end

		tracked_particles[data.index] = {
			fullName = data.fullName,
			name = data.name,
			created_t = now_time(),
			entity = ent,
			entity_id = data.entity_id,
			team = team,
			triggered = false,
			last_pos_by_cp = {},
		}
		if ui.debug_log and ui.debug_log.Get and ui.debug_log:Get() then
			Log.Write(SCRIPT_TAG .. " create index=" .. tostring(data.index)
				.. " entity_id=" .. tostring(data.entity_id)
				.. " entity=" .. (ent and "yes" or "nil")
				.. " team=" .. tostring(team))
		end
	end
end

function smoke_detector_enemy_only.OnParticleUpdate(data)
	if not ui.enabled:Get() then
		return
	end
	if not data or data.index == nil then
		return
	end

	local p = tracked_particles[data.index]
	if not p then
		return
	end

	local cp = data.controlPoint or -1
	if data.position then
		p.last_pos_by_cp[cp] = data.position
	end

	-- Many world particles report their world origin on CP0; if not, we'll take first available.
	if not p.triggered then
		-- Resolve entity once more from entity_id if still nil (can become valid after a tick).
		if not p.entity and p.entity_id and Entity and Entity.Get then
			p.entity = Entity.Get(p.entity_id)
			if p.entity and Entity.GetTeamNum then
				p.team = Entity.GetTeamNum(p.entity)
			end
		end
		local pos = p.last_pos_by_cp[0] or p.last_pos_by_cp[1] or p.last_pos_by_cp[2] or data.position
		if not pos and p.entity then
			pos = Entity.GetAbsOrigin(p.entity)
		end
		if pos then
			p.triggered = true
			if ui.debug_log and ui.debug_log.Get and ui.debug_log:Get() then
				Log.Write(SCRIPT_TAG .. " trigger index=" .. tostring(data.index)
					.. " entity=" .. (p.entity and "yes" or "nil")
					.. " team=" .. tostring(p.team)
					.. " local_team=" .. tostring(get_local_team_num()))
			end
			try_add_smoke_marker(pos, p.team, "particle:" .. tostring(p.name or p.fullName), p.entity)
		end
	end
end

-- API: OnParticleUpdateEntity fires when particle has entity attachment; use it to get entity when Create had nil.
function smoke_detector_enemy_only.OnParticleUpdateEntity(data)
	if not ui.enabled:Get() or not data or data.index == nil then
		return
	end
	local p = tracked_particles[data.index]
	if not p or p.triggered then
		return
	end
	if data.entity then
		p.entity = data.entity
		if Entity and Entity.GetTeamNum then
			p.team = Entity.GetTeamNum(data.entity)
		end
	end
	-- Also store position from this update if present
	if data.position then
		local cp = data.controlPoint or 0
		p.last_pos_by_cp[cp] = data.position
	end
end

function smoke_detector_enemy_only.OnParticleDestroy(data)
	if not data or data.index == nil then
		return
	end
	tracked_particles[data.index] = nil
end

return smoke_detector_enemy_only
