---@diagnostic disable: undefined-global

local smoke_detector = {}

-- Create menu
local menu_tab = Menu.Create("General", "Scripts", "Smoke Detector", "Detector")
local main_group = menu_tab:Create("Settings")

local ui = {}
ui.enabled = main_group:Switch("Enabled", true)

ui.minimap_duration = main_group:Slider("Minimap Duration (s)", 1, 60, 20)
ui.minimap_alpha = main_group:Slider("Minimap Translucency", 0, 255, 120)
ui.center_duration = main_group:Slider("Center Alert Duration (s)", 1, 5, 1)
ui.center_alpha = main_group:Slider("Center Alert Translucency", 0, 255, 200)

local SCRIPT_TAG = "[Smoke Detector]"
Log.Write(SCRIPT_TAG .. " Loaded")

-- Settings
local SMOKE_LINGER_TIME = 20.0  -- seconds to show smoke indicator (menu overrides)
local CENTER_ICON_DURATION = 1.0  -- seconds to show center screen icon (menu overrides)
local CENTER_ICON_FADE_TIME = 0.3  -- seconds for fade out animation

-- Smoke tracking
local smoke_uses = {}  -- {pos = Vector, time = number, team = number}

-- Particle tracking (best chance to detect out-of-vision if replicated)
local tracked_particles = {} -- [index] = {fullName, name, created_t, entity, team, triggered, last_pos_by_cp = {}}
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

local function try_add_smoke_marker(pos, team, source)
	if not pos then
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

	Log.Write("[Smoke Detector] SMOKE DETECTED (" .. tostring(source or "?") .. ") at " .. tostring(pos))
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
			-- MiniMap.DrawCircle(pos, r, g, b, a, size)
			if MiniMap and MiniMap.DrawCircle then
				-- Layer a few circles to make the ring visually thicker.
				-- Double size (default was ~800).
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

		-- If Render v2 isn't available, skip center alert silently.
	end
end
function smoke_detector.OnDraw()
	if not ui.enabled:Get() then
		return
	end
	
	draw_minimap_circles()
	draw_center_screen_icon()
end

-- Particle-based detection
function smoke_detector.OnParticleCreate(data)
	if not ui.enabled:Get() then
		return
	end
	if not data or not data.index then
		return
	end

	if is_smoke_particle_name(data.fullName, data.name) then
		local team = nil
		local ent = data.entity
		if ent and Entity and Entity.GetTeamNum then
			team = Entity.GetTeamNum(ent)
		end

		tracked_particles[data.index] = {
			fullName = data.fullName,
			name = data.name,
			created_t = now_time(),
			entity = ent,
			team = team,
			triggered = false,
			last_pos_by_cp = {},
		}

		Log.Write("[Smoke Detector] Particle created (candidate): index=" .. tostring(data.index) .. " name=" .. tostring(data.name) .. " full=" .. tostring(data.fullName))
	end
end

function smoke_detector.OnParticleUpdate(data)
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
		local pos = p.last_pos_by_cp[0] or p.last_pos_by_cp[1] or p.last_pos_by_cp[2] or data.position
		if not pos and p.entity then
			pos = Entity.GetAbsOrigin(p.entity)
		end
		if pos then
			p.triggered = true
			try_add_smoke_marker(pos, p.team, "particle:" .. tostring(p.name or p.fullName))
		end
	end
end

function smoke_detector.OnParticleDestroy(data)
	if not data or data.index == nil then
		return
	end
	tracked_particles[data.index] = nil
end

return smoke_detector
