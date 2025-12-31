---@diagnostic disable: undefined-global

local combo = {}

-- Forward-declare UI table so helper functions can reference it.
local ui

-- Forward-declare functions that are referenced before their definition.
local cast_fast
local target_has_rod_root

-- Minimal, maximum-speed Skywrath Mage hold-key combo.
-- No logging, no confirmation waits, no retries, no persistence, no drawing.

local CAST_GAP_SECONDS = 0.015
local MAX_STEPS = 8

-- When we issue a cast order, cooldown might not be reflected until the next update.
-- To avoid false-positives (order sent but ability didn't actually cast), only advance
-- once we observe the ability go on cooldown (IsReady() becomes false).
-- NOTE: If this is too small, repeatedly re-issuing the same cast order can restart
-- the cast point and prevent the cast from ever completing (common with items).
local COOLDOWN_CONFIRM_GRACE = 0.08
local COOLDOWN_CONFIRM_EXTRA = 0.15

local function get_cast_point_seconds(ability)
	if not ability or not Ability or not Ability.GetCastPoint then return 0.10 end
	local ok, cp = pcall(Ability.GetCastPoint, ability)
	if ok and type(cp) == "number" then
		-- Clamp to a sane range; some items/APIs return 0 or garbage.
		if cp < 0.05 then cp = 0.05 end
		if cp > 0.60 then cp = 0.60 end
		return cp
	end
	return 0.10
end

local function get_cooldown_remaining_seconds(ability)
	if not ability or not Ability or not Ability.GetCooldown then return nil end
	local ok, cd = pcall(Ability.GetCooldown, ability)
	if ok and type(cd) == "number" then return cd end
	return nil
end

local function is_cooldown_started(ability)
	if not ability or not Ability or not Ability.IsReady then return false end
	if not Ability.IsReady(ability) then return true end
	local cd = get_cooldown_remaining_seconds(ability)
	return (cd ~= nil) and (cd > 0.0)
end

-- Debug timing/event capture (only used when Debug Logs is enabled)
local combo_start_t = 0.0
local combo_last_cast_t = 0.0
local combo_event_seq = 0
local combo_events = nil -- { {t=, dt=, kind=, step=, name=, reason=} ... }
local MAX_COMBO_EVENTS = 40

-- Per-step debug trace (only used when Debug Logs is enabled)
local step_trace = nil
local last_success_cast_t = 0.0

-- Cooldown-confirmation state for the current step.
-- {idx=number, name=string, next_try_t=number}
local pending_cooldown_confirm = nil

local TARGET_SEARCH_COOLDOWN = 0.03
local last_target_search_t = -1000.0

local perf_last_report_t = 0.0
local perf_updates = 0
local perf_cpu_total = 0.0
local perf_cpu_max = 0.0
local perf_find_total = 0.0
local perf_step_total = 0.0

-- Target movement cache (for Aghanim's Mystic Flare offset direction)
local target_motion = {} -- [entity] = {pos=Vector, t=number, dir=Vector|nil, speed=number}

-- Rod impact prediction (used to aim Mystic Flare where the target will be when Rod hits).
-- NOTE: Must be declared before get_mystic_flare_cast_pos()/cast_fast() so it isn't treated as a nil global.
local rod_predict = nil -- {target=Entity, cast_t=number, hit_t=number, impact_pos=Vector, move_dir=Vector|nil}
local ROD_PREDICTION_GRACE = 0.50

local function now_time()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
end

local function clamp_number(v, lo, hi, fallback)
	if type(v) ~= "number" then return fallback end
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function get_target_facing_dir(target)
	if not target or not Entity or not Entity.GetRotation then return nil end
	local ok, ang = pcall(Entity.GetRotation, target)
	if not ok or not ang or not ang.GetForward then return nil end
	local forward = ang:GetForward()
	if not forward or not forward.Length2D then return nil end
	local len = forward:Length2D()
	if not len or len < 0.001 then return nil end
	return forward:Normalized()
end

local function distance2d(a, b)
	if not a or not b then return 0.0 end
	local dx = (a.x or 0.0) - (b.x or 0.0)
	local dy = (a.y or 0.0) - (b.y or 0.0)
	return math.sqrt(dx * dx + dy * dy)
end

local function fmt_vec2(v)
	if not v then return "(nil)" end
	return string.format("(%.1f,%.1f,%.1f)", tonumber(v.x) or 0.0, tonumber(v.y) or 0.0, tonumber(v.z) or 0.0)
end

local function update_target_motion(target, t)
	if not target or not t then return end
	local pos = Entity.GetAbsOrigin(target)
	if not pos then return end
	local m = target_motion[target]
	if not m then
		target_motion[target] = {pos = pos, t = t, dir = nil, speed = 0.0}
		return
	end
	local dt = t - (m.t or t)
	if dt <= 0.001 then
		m.pos = pos
		m.t = t
		return
	end
	local delta = Vector(pos.x - (m.pos.x or pos.x), pos.y - (m.pos.y or pos.y), 0.0)
	local len = delta:Length2D()
	local speed = 0.0
	if len and len > 0.0 then
		speed = len / dt
	end
	-- Always store raw speed; only store a direction if it's meaningful.
	m.speed = speed
	if speed >= 30.0 then
		m.dir = delta:Normalized()
	else
		m.dir = nil
	end
	m.pos = pos
	m.t = t
end

local function get_target_move_dir(target)
	if not target_motion or not target then return nil end
	local m = target_motion[target]
	if not m or not m.t then return nil end
	local age = now_time() - (m.t or now_time())
	if not age or age > 0.50 then return nil end
	return m.dir
end

local function get_target_move_speed(target)
	if not target_motion or not target then return 0.0 end
	local m = target_motion[target]
	if not m or not m.t then return 0.0 end
	local age = now_time() - (m.t or now_time())
	if not age or age > 0.50 then return 0.0 end
	if type(m.speed) ~= "number" then return 0.0 end
	return m.speed
end

local function get_rod_projectile_speed(rod_ability)
	local function read_sv(key)
		if not rod_ability then return nil end
		if Ability and Ability.GetSpecialValueFor then
			local ok, val = pcall(Ability.GetSpecialValueFor, rod_ability, key, -1)
			if ok and type(val) == "number" then return val end
			ok, val = pcall(Ability.GetSpecialValueFor, rod_ability, key)
			if ok and type(val) == "number" then return val end
		end
		if Ability and Ability.GetLevelSpecialValueFor then
			local ok, val = pcall(Ability.GetLevelSpecialValueFor, rod_ability, key, -1)
			if ok and type(val) == "number" then return val end
			ok, val = pcall(Ability.GetLevelSpecialValueFor, rod_ability, key)
			if ok and type(val) == "number" then return val end
		end
		return nil
	end

	local speed = read_sv("projectile_speed")
	if not speed or speed <= 0 then
		speed = read_sv("projectile_speed_tooltip")
	end
	if not speed or speed <= 0 then
		speed = 1500.0
	end
	return speed
end

local function compute_rod_travel_time(hero_pos, target_pos, rod_speed)
	local dist = distance2d(hero_pos, target_pos)
	if not rod_speed or rod_speed <= 0.0 then return 0.0 end
	return dist / rod_speed
end

local function compute_predicted_pos_at_time(target_pos, move_dir, move_speed, dt)
	if not target_pos then return nil end
	if not move_dir or not move_speed or move_speed <= 0.0 or not dt or dt <= 0.0 then
		return target_pos
	end
	local lead_dist = move_speed * dt
	return Vector(target_pos.x + move_dir.x * lead_dist, target_pos.y + move_dir.y * lead_dist, target_pos.z)
end

local DEFAULT_ORDER = {
	"Arcane Bolt",
	"Concussive Shot",
	"Sheep Stick",
	"Ancient Seal",
	"Rod of Atos",
	"Ethereal Blade",
	"Dagon",
	"Mystic Flare",
}

local ORDER_ITEMS = {
	"Concussive Shot",
	"Sheep Stick",
	"Rod of Atos",
	"Ancient Seal",
	"Ethereal Blade",
	"Bloodthorn",
	"Nullifier",
	"Arcane Bolt",
	"Dagon",
	"Mystic Flare",
}

local ORDER_INDEX = {}
for i, name in ipairs(ORDER_ITEMS) do
	ORDER_INDEX[name] = i - 1 -- Combo() defaults are 0-based
end

local LINKENS_BREAKER_ITEMS = {
	"None",
	"Concussive Shot",
	"Sheep Stick",
	"Rod of Atos",
	"Ancient Seal",
	"Ethereal Blade",
	"Bloodthorn",
	"Nullifier",
	"Arcane Bolt",
	"Dagon",
	"Mystic Flare",
}

-- Linken's breaker priority list (only include direct target casts).
local LINKENS_BREAK_ORDER_ITEMS = {
	"Sheep Stick",
	"Rod of Atos",
	"Ancient Seal",
	"Ethereal Blade",
	"Bloodthorn",
	"Nullifier",
	"Arcane Bolt",
	"Dagon",
}

local available_spells = {
	{nameId = "Concussive Shot", imagePath = "images/MenuIcons/target.png", isEnabled = true},
	{nameId = "Sheep Stick", imagePath = "images/MenuIcons/staff_stick.png", isEnabled = true},
	{nameId = "Rod of Atos", imagePath = "images/MenuIcons/Dota/gungir.png", isEnabled = true},
	{nameId = "Ancient Seal", imagePath = "images/MenuIcons/silent.png", isEnabled = true},
	{nameId = "Ethereal Blade", imagePath = "images/MenuIcons/Dota/ethereal_blade.png", isEnabled = true},
	{nameId = "Bloodthorn", imagePath = "images/MenuIcons/Dota/bloodstone.png", isEnabled = true},
	{nameId = "Nullifier", imagePath = "images/MenuIcons/Dota/spell_book.png", isEnabled = true},
	{nameId = "Arcane Bolt", imagePath = "images/MenuIcons/magic_ball.png", isEnabled = true},
	{nameId = "Dagon", imagePath = "images/MenuIcons/Dota/dagon.png", isEnabled = true},
	{nameId = "Mystic Flare", imagePath = "images/MenuIcons/explosion.png", isEnabled = true},
}

local ICON_BY_NAME = {
	["Concussive Shot"] = "images/MenuIcons/target.png",
	["Sheep Stick"] = "images/MenuIcons/staff_stick.png",
	["Rod of Atos"] = "images/MenuIcons/Dota/gungir.png",
	["Ancient Seal"] = "images/MenuIcons/silent.png",
	["Ethereal Blade"] = "images/MenuIcons/Dota/ethereal_blade.png",
	["Bloodthorn"] = "images/MenuIcons/Dota/bloodstone.png",
	["Nullifier"] = "images/MenuIcons/Dota/spell_book.png",
	["Arcane Bolt"] = "images/MenuIcons/magic_ball.png",
	["Dagon"] = "images/MenuIcons/Dota/dagon.png",
	["Mystic Flare"] = "images/MenuIcons/explosion.png",
	["None"] = "images/MenuIcons/cancel_smth.png",
}

local spell_map = {
	["Rod of Atos"] = {name = "item_rod_of_atos", kind = "item", cast = "target"},
	["Ancient Seal"] = {name = "skywrath_mage_ancient_seal", kind = "ability", cast = "target"},
	["Concussive Shot"] = {name = "skywrath_mage_concussive_shot", kind = "ability", cast = "no_target"},
	["Arcane Bolt"] = {name = "skywrath_mage_arcane_bolt", kind = "ability", cast = "target"},
	["Sheep Stick"] = {name = "item_sheepstick", kind = "item", cast = "target"},
	["Ethereal Blade"] = {name = "item_ethereal_blade", kind = "item", cast = "target"},
	["Bloodthorn"] = {name = "item_bloodthorn", kind = "item", cast = "target"},
	["Nullifier"] = {name = "item_nullifier", kind = "item", cast = "target"},
	["Dagon"] = {name = "item_dagon", kind = "item", cast = "target"}, -- matches dagon_2..5 too
	["Mystic Flare"] = {name = "skywrath_mage_mystic_flare", kind = "ability", cast = "position"},
}

-- Combo Order UI: draggable icon list (this drives the actual combo order).
local ORDER_UI_CONFIG_NAME = "skywrath_combo"
local combo_order_enabled_names = nil -- cached {"Arcane Bolt", ...} in chosen order

local linkens_break_enabled_names = nil -- cached {"Dagon", ...} in chosen priority order

local function split_csv(s)
	if type(s) ~= "string" or s == "" then return {} end
	local out = {}
	for token in string.gmatch(s, "[^,]+") do
		token = tostring(token):gsub("^%s+", ""):gsub("%s+$", "")
		if token ~= "" then out[#out + 1] = token end
	end
	return out
end

local function list_to_set(list)
	local set = {}
	if type(list) ~= "table" then return set end
	for _, v in ipairs(list) do
		if v ~= nil then set[v] = true end
	end
	return set
end

local function resolve_multiselect_image_path(name_id)
	-- MultiSelect imagePath works reliably with Panorama vtex_c assets.
	local meta = spell_map[name_id]
	if meta and meta.name then
		if meta.kind == "item" then
			local item_short = tostring(meta.name):gsub("^item_", "")
			return "panorama/images/items/" .. item_short .. "_png.vtex_c"
		elseif meta.kind == "ability" then
			return "panorama/images/spellicons/" .. tostring(meta.name) .. "_png.vtex_c"
		end
	end
	-- Fallback: custom local images (may not render in all widget contexts).
	return ICON_BY_NAME[name_id] or ""
end

local function build_order_multiselect_items(order_list, enabled_set)
	local items = {}
	local seen = {}
	local function push(name_id)
		if not name_id or seen[name_id] then return end
		seen[name_id] = true
		-- API docs show MultiSelect items as tuple arrays: {nameId, imagePath, isEnabled}
		items[#items + 1] = { name_id, resolve_multiselect_image_path(name_id), enabled_set[name_id] == true }
	end
	if type(order_list) == "table" then
		for _, name_id in ipairs(order_list) do
			push(name_id)
		end
	end
	for _, name_id in ipairs(ORDER_ITEMS) do
		push(name_id)
	end
	return items
end

local function build_linkens_break_multiselect_items(order_list, enabled_set)
	local items = {}
	local seen = {}
	local function push(name_id)
		if not name_id or seen[name_id] then return end
		seen[name_id] = true
		items[#items + 1] = { name_id, resolve_multiselect_image_path(name_id), enabled_set[name_id] == true }
	end
	if type(order_list) == "table" then
		for _, name_id in ipairs(order_list) do
			push(name_id)
		end
	end
	for _, name_id in ipairs(LINKENS_BREAK_ORDER_ITEMS) do
		push(name_id)
	end
	return items
end

local menu_tab = Menu.Create("General", "Scripts", "Skywrath Combo", "Combo")
local main_group = menu_tab:Create("Settings")
local order_group = menu_tab:Create("Combo Order")
local linkens_group = menu_tab:Create("Linken's Breaker")

ui = {}
ui.enabled = main_group:Switch("Enable Combo", true)
ui.debug_logs = main_group:Switch("Debug Logs", false)
ui.combo_key = main_group:Bind("Combo Key", Enum.ButtonCode.KEY_SPACE)
ui.search_radius = main_group:Input("Target Search Radius", "300")

ui.wait_rod_modifier = main_group:Switch("Wait Rod Root (Modifier)", false)

ui.wait_eblade_modifier = main_group:Switch("Wait Ethereal Blade (Modifier)", false)

ui.force_sheep_first = main_group:Switch("Force Sheep First", false)

order_group:Label("Drag to reorder. Toggle entries to enable/disable. Combo uses the first " .. tostring(MAX_STEPS) .. " enabled entries.")

-- Mystic Flare offset is hard-coded for fastest consistent combos:
-- - Rod (or no Rod): 175
-- - Gungir: 250

local SCRIPT_TAG = "[Skywrath Combo]"
local function log_debug(msg)
	if not ui.debug_logs:Get() then return end
	if Log and Log.Write then
		Log.Write(SCRIPT_TAG .. " " .. msg)
	else
		print(SCRIPT_TAG .. " " .. msg)
	end
end

local function dbg_add_event(kind, step, name, reason)
	if not ui or not ui.debug_logs or not ui.debug_logs.Get or not ui.debug_logs:Get() then return end
	local t = now_time()
	if combo_start_t <= 0.0 then combo_start_t = t end
	combo_event_seq = (combo_event_seq or 0) + 1
	local dt_cast = 0.0
	if combo_last_cast_t and combo_last_cast_t > 0.0 then
		dt_cast = t - combo_last_cast_t
	end
	if not combo_events then combo_events = {} end
	combo_events[#combo_events + 1] = {
		seq = combo_event_seq,
		t = t,
		dt = dt_cast,
		from_start = t - (combo_start_t or t),
		kind = kind,
		step = step,
		name = name,
		reason = reason,
	}
	if #combo_events > MAX_COMBO_EVENTS then
		table.remove(combo_events, 1)
	end
end

local function dbg_log_cast(kind, step, name, reason)
	if not ui or not ui.debug_logs or not ui.debug_logs.Get or not ui.debug_logs:Get() then return end
	local t = now_time()
	if combo_start_t <= 0.0 then combo_start_t = t end
	local dt_cast = 0.0
	if combo_last_cast_t and combo_last_cast_t > 0.0 then
		dt_cast = t - combo_last_cast_t
	end
	local from_start = t - (combo_start_t or t)
	log_debug(string.format("[CAST] t=%.3f +%.3f since_start=%.3f step=%s %s%s",
		t,
		dt_cast,
		from_start,
		tostring(step),
		tostring(name),
		reason and (" reason=" .. tostring(reason)) or ""
	))
	if kind == "SUCCESS" then
		combo_last_cast_t = t
	end
	dbg_add_event(kind, step, name, reason)
end

local function trace_inc(map, key)
	if not map then return end
	key = key or "(nil)"
	map[key] = (map[key] or 0) + 1
end

local function trace_get_step(i, spell)
	if not ui or not ui.debug_logs or not ui.debug_logs.Get or not ui.debug_logs:Get() then return nil end
	if not step_trace then step_trace = {} end
	local st = step_trace[i]
	if not st then
		st = {
			step = i,
			name = spell and spell.name or "(nil)",
			entered_t = now_time(),
			first_attempt_t = nil,
			last_attempt_t = nil,
			success_t = nil,
			attempts = 0,
			skips = 0,
			blocks = {},
			fails = {},
		}
		step_trace[i] = st
	end
	if spell and spell.name then st.name = spell.name end
	return st
end

local function trace_step_attempt(i, spell)
	local st = trace_get_step(i, spell)
	if not st then return end
	local t = now_time()
	st.attempts = (st.attempts or 0) + 1
	st.last_attempt_t = t
	if not st.first_attempt_t then st.first_attempt_t = t end
end

local function trace_step_block(i, spell, reason)
	local st = trace_get_step(i, spell)
	if not st then return end
	trace_inc(st.blocks, reason or "block")
end

local function trace_step_fail(i, spell, reason)
	local st = trace_get_step(i, spell)
	if not st then return end
	trace_inc(st.fails, reason or "fail")
end

local function trace_step_skip(i, spell, reason)
	local st = trace_get_step(i, spell)
	if not st then return end
	st.skips = (st.skips or 0) + 1
	trace_inc(st.fails, reason or "skip")
end

local function trace_step_success(i, spell)
	local st = trace_get_step(i, spell)
	if not st then return end
	local t = now_time()
	st.success_t = t
	local dt_enter = st.entered_t and (t - st.entered_t) or 0.0
	local dt_first_attempt = st.first_attempt_t and (t - st.first_attempt_t) or 0.0
	local dt_prev_ok = (last_success_cast_t and last_success_cast_t > 0.0) and (t - last_success_cast_t) or 0.0
	last_success_cast_t = t
	log_debug(string.format("[STEP OK] step=%d %s attempts=%d dt_enter=%.3f dt_first_attempt=%.3f dt_prev_ok=%.3f",
		tostring(i),
		tostring(spell and spell.name),
		tonumber(st.attempts) or 0,
		dt_enter,
		dt_first_attempt,
		dt_prev_ok
	))
end

local function log_info(msg)
	if Log and Log.Write then
		Log.Write(SCRIPT_TAG .. " " .. msg)
	else
		print(SCRIPT_TAG .. " " .. msg)
	end
end

local LOCK_LINE_COLOR = Color(0, 255, 120, 220)
local LOCK_LINE_THICKNESS = 2.0

local function draw_lock_line(hero, target)
	if not hero or not target then return end
	if not Render or not Render.WorldToScreen or not Render.Line then return end
	local hero_pos = Entity.GetAbsOrigin(hero)
	local target_pos = Entity.GetAbsOrigin(target)
	-- lift endpoints slightly so the line doesn't end at feet
	hero_pos = Vector(hero_pos.x, hero_pos.y, (hero_pos.z or 0.0) + 80.0)
	target_pos = Vector(target_pos.x, target_pos.y, (target_pos.z or 0.0) + 80.0)

	local a, a_vis = Render.WorldToScreen(hero_pos)
	local b, b_vis = Render.WorldToScreen(target_pos)
	if not a_vis or not b_vis then return end
	Render.Line(a, b, LOCK_LINE_COLOR, LOCK_LINE_THICKNESS)
end

local function get_local_player()
	if Players and Players.GetLocal then return Players.GetLocal() end
	return nil
end

local function stop_hero_orders()
	local player = get_local_player()
	local hero = Heroes.GetLocal()
	if not player or not hero then return end
	if Player and Player.PrepareUnitOrders and Enum and Enum.UnitOrder and Enum.PlayerOrderIssuer then
		Player.PrepareUnitOrders(
			player,
			Enum.UnitOrder.DOTA_UNIT_ORDER_STOP,
			nil,
			Vector(0, 0, 0),
			nil,
			Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY,
			hero,
			false,
			false,
			false,
			true,
			"skywrath_combo_stop",
			true
		)
	end
end

-- (Removed) Old Aghanim's overlap-tuning UI: "Mystic Flare Offset Minus".

-- Linken's Breaker Priority (drag reorder).
ui.linkens_breaker = {}
do
	local saved_order = ""
	local saved_enabled = ""
	if Config and Config.ReadString then
		saved_order = Config.ReadString(ORDER_UI_CONFIG_NAME, "linkens_drag_order", "")
		saved_enabled = Config.ReadString(ORDER_UI_CONFIG_NAME, "linkens_drag_enabled", "")
	end

	local saved_order_list = split_csv(saved_order)
	if #saved_order_list == 0 then
		saved_order_list = LINKENS_BREAK_ORDER_ITEMS
	end

	local enabled_default = split_csv(saved_enabled)
	if #enabled_default == 0 then
		enabled_default = LINKENS_BREAK_ORDER_ITEMS
	end
	local enabled_set = list_to_set(enabled_default)

	linkens_group:Label("Drag to reorder. Toggle entries to enable/disable. First available breaker is used.")
	local items = build_linkens_break_multiselect_items(saved_order_list, enabled_set)
	ui.linkens_breaker.multiselect = linkens_group:MultiSelect("Breaker Priority", items, true)
	if ui.linkens_breaker.multiselect and ui.linkens_breaker.multiselect.DragAllowed then
		pcall(ui.linkens_breaker.multiselect.DragAllowed, ui.linkens_breaker.multiselect, true)
	end

	local function read_linkens_breaker(save_to_config)
		if not ui.linkens_breaker.multiselect or not ui.linkens_breaker.multiselect.List or not ui.linkens_breaker.multiselect.Get then
			return
		end
		local ok_list, ids = pcall(ui.linkens_breaker.multiselect.List, ui.linkens_breaker.multiselect)
		if not ok_list or type(ids) ~= "table" then return end
		local enabled = {}
		for _, id in ipairs(ids) do
			local ok_get, is_on = pcall(ui.linkens_breaker.multiselect.Get, ui.linkens_breaker.multiselect, id)
			if ok_get and is_on then
				enabled[#enabled + 1] = id
			end
		end
		linkens_break_enabled_names = enabled
		if save_to_config and Config and Config.WriteString then
			Config.WriteString(ORDER_UI_CONFIG_NAME, "linkens_drag_order", table.concat(ids, ","))
			Config.WriteString(ORDER_UI_CONFIG_NAME, "linkens_drag_enabled", table.concat(enabled, ","))
		end
	end

	read_linkens_breaker(true)
	if ui.linkens_breaker.multiselect and ui.linkens_breaker.multiselect.SetCallback then
		ui.linkens_breaker.multiselect:SetCallback(function()
			read_linkens_breaker(true)
		end, true)
	end
end

-- Fallback ordering UI: per-step dropdowns (always renders on all builds).
ui.combo_order = {}
do
	local saved_order = ""
	local saved_enabled = ""
	if Config and Config.ReadString then
		saved_order = Config.ReadString(ORDER_UI_CONFIG_NAME, "combo_drag_order", "")
		saved_enabled = Config.ReadString(ORDER_UI_CONFIG_NAME, "combo_drag_enabled", "")
	end

	local saved_order_list = split_csv(saved_order)
	if #saved_order_list == 0 then
		saved_order_list = DEFAULT_ORDER
	end

	local enabled_default = split_csv(saved_enabled)
	if #enabled_default == 0 then
		enabled_default = DEFAULT_ORDER
	end
	local enabled_set = list_to_set(enabled_default)

	local items = build_order_multiselect_items(saved_order_list, enabled_set)
	ui.combo_order.multiselect = order_group:MultiSelect("Drag Order", items, true)
	if ui.combo_order.multiselect and ui.combo_order.multiselect.DragAllowed then
		pcall(ui.combo_order.multiselect.DragAllowed, ui.combo_order.multiselect, true)
	end

	local function read_combo_order(save_to_config)
		if not ui.combo_order.multiselect or not ui.combo_order.multiselect.List or not ui.combo_order.multiselect.Get then
			return
		end
		local ok_list, ids = pcall(ui.combo_order.multiselect.List, ui.combo_order.multiselect)
		if not ok_list or type(ids) ~= "table" then return end
		local enabled = {}
		for _, id in ipairs(ids) do
			local ok_get, is_on = pcall(ui.combo_order.multiselect.Get, ui.combo_order.multiselect, id)
			if ok_get and is_on then
				enabled[#enabled + 1] = id
			end
		end
		combo_order_enabled_names = enabled
		if save_to_config and Config and Config.WriteString then
			Config.WriteString(ORDER_UI_CONFIG_NAME, "combo_drag_order", table.concat(ids, ","))
			Config.WriteString(ORDER_UI_CONFIG_NAME, "combo_drag_enabled", table.concat(enabled, ","))
		end
	end

	-- Prime cache and persist any normalization.
	read_combo_order(true)

	if ui.combo_order.multiselect and ui.combo_order.multiselect.SetCallback then
		ui.combo_order.multiselect:SetCallback(function()
			read_combo_order(true)
		end, true)
	end
end

local last_icon_update_t = 0.0
local function update_step_icons()
	local t = now_time()
	if (t - last_icon_update_t) < 0.20 then return end
	last_icon_update_t = t
end

local function normalize_list(v)
	if type(v) == "table" then return v end
	return {}
end

local function get_order_list()
	-- Preferred: draggable MultiSelect order.
	if combo_order_enabled_names and #combo_order_enabled_names > 0 then
		local out = {}
		for i = 1, math.min(#combo_order_enabled_names, MAX_STEPS) do
			out[#out + 1] = combo_order_enabled_names[i]
		end
		if #out > 0 then return out end
	end
	return DEFAULT_ORDER
end

local function build_combo_sequence()
	local seq = {}
	for _, name_id in ipairs(get_order_list()) do
		local s = spell_map[name_id]
		if s then seq[#seq + 1] = s end
	end
	return seq
end

local function get_spell(owner, spell)
	if spell.kind == "ability" then
		return NPC.GetAbility(owner, spell.name)
	end
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(owner, i)
		if item then
			local nm = Ability.GetName(item)
			if nm == spell.name then return item end
			-- Treat Rod of Atos and its common upgraded variants as the same step.
			-- Some Umbrella builds/logs refer to Gleipnir as "gungir".
			if spell.name == "item_rod_of_atos" and (nm == "item_gleipnir" or nm == "item_gungir") then
				return item
			end
			if spell.name == "item_dagon" and nm and nm:find("^item_dagon") then return item end
		end
	end
	return nil
end

local function hero_has_item_name(hero, item_name)
	if not hero or not item_name or not NPC or not NPC.GetItemByIndex or not Ability or not Ability.GetName then return false end
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(hero, i)
		if item then
			local ok_n, nm = pcall(Ability.GetName, item)
			if ok_n and nm == item_name then return true end
		end
	end
	return false
end

local function find_seq_index_by_name(seq, name)
	if not seq or not name then return nil end
	for idx, s in ipairs(seq) do
		if s and s.name == name then
			return idx
		end
	end
	return nil
end

local CONTROL_CHAIN = {
	spell_map["Sheep Stick"],
	spell_map["Rod of Atos"],
	spell_map["Ancient Seal"],
	spell_map["Ethereal Blade"],
}

local CONTROL_CHAIN_NAMES = {
	"item_sheepstick",
	"item_rod_of_atos",
	"skywrath_mage_ancient_seal",
	"item_ethereal_blade",
}

local function run_control_chain_prefix(hero, target, should_log)
	if control_chain_complete then return nil end
	if not control_chain_done then control_chain_done = {} end

	for k = 1, #CONTROL_CHAIN do
		local sp = CONTROL_CHAIN[k]
		local sp_name = CONTROL_CHAIN_NAMES[k]
		if sp and sp_name and (not control_chain_done[sp_name]) then
			local a = get_spell(hero, sp)
			if not a then
				-- Not owned -> treat as done for this combo.
				control_chain_done[sp_name] = true
			else
				-- Try to cast ASAP; no debuff/modifier checks here.
				if should_log then
					log_debug(string.format("[CTRL] Attempting %d/%d: %s", k, #CONTROL_CHAIN, sp_name))
				end
				dbg_log_cast("ATTEMPT", "CTRL", sp_name, nil)
				local ok, reason = cast_fast(a, sp, target)
				if ok then
					control_chain_done[sp_name] = true
					local seq_idx = find_seq_index_by_name(combo_seq, sp_name)
					if seq_idx and seq_idx > (control_chain_last_seq_idx or 0) then
						control_chain_last_seq_idx = seq_idx
					end
					dbg_log_cast("SUCCESS", "CTRL", sp_name, nil)
					return STEP_CAST
				end
				-- If not ready/castable, skip it (keep combo fast) and move on.
				if reason == "not_ready" or reason == "not_castable" or reason == "missing" then
					control_chain_done[sp_name] = true
					dbg_log_cast("SKIP", "CTRL", sp_name, reason)
					-- Continue in the same frame to the next control spell.
				else
					-- out_of_range / other blocks: stop and retry.
					dbg_log_cast("BLOCK", "CTRL", sp_name, reason)
					return STEP_BLOCKED
				end
			end
		end
	end

	-- All control spells are done (cast or skipped). Mark complete and resume after the last present one.
	control_chain_complete = true
	if control_chain_last_seq_idx and control_chain_last_seq_idx > 0 then
		combo_idx = control_chain_last_seq_idx + 1
		if combo_seq and combo_idx > #combo_seq then combo_idx = 1 end
		if should_log then
			log_debug(string.format("[CTRL] Complete. Resume idx=%d", combo_idx))
		end
	end
	return nil
end

local function has_agh_effect(hero)
	if not hero then return false end
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(hero, i)
		if item then
			local nm = Ability.GetName(item)
			if nm == "item_ultimate_scepter" or nm == "item_ultimate_scepter_2" or nm == "item_ultimate_scepter_roshan" then
				return true
			end
		end
	end
	if NPC.HasModifier then
		if NPC.HasModifier(hero, "modifier_item_ultimate_scepter") then return true end
		if NPC.HasModifier(hero, "modifier_item_ultimate_scepter_consumed") then return true end
		if NPC.HasModifier(hero, "modifier_item_ultimate_scepter_2") then return true end
	end
	return false
end

local function get_aoe_increase_pct(hero)
	local v = nil
	if NPC and NPC.GetAOEIncrease then v = NPC.GetAOEIncrease(hero) end
	if v == nil and NPC and NPC.GetAoEIncrease then v = NPC.GetAoEIncrease(hero) end
	if type(v) ~= "number" then return 0.0 end
	if v > 1.0 then return v / 100.0 end
	if v < 0.0 then v = 0.0 end
	return v
end

local function get_special_value(ability, key)
	if not ability then return 0 end
	if Ability and Ability.GetSpecialValueFor then
		local ok, val = pcall(Ability.GetSpecialValueFor, ability, key, -1)
		if ok and type(val) == "number" then return val end
		ok, val = pcall(Ability.GetSpecialValueFor, ability, key)
		if ok and type(val) == "number" then return val end
	end
	if Ability and Ability.GetLevelSpecialValueFor then
		local ok, val = pcall(Ability.GetLevelSpecialValueFor, ability, key, -1)
		if ok and type(val) == "number" then return val end
		ok, val = pcall(Ability.GetLevelSpecialValueFor, ability, key)
		if ok and type(val) == "number" then return val end
	end
	return 0
end

local function get_mystic_flare_radius(hero, ability)
	local base = get_special_value(ability, "radius")
	if has_agh_effect(hero) then
		local scepter = get_special_value(ability, "scepter_radius")
		if scepter and scepter > 0 then base = scepter end
	end
	if not base or base <= 0 then base = 170 end
	return base * (1.0 + get_aoe_increase_pct(hero))
end

local function get_mystic_flare_cast_pos(hero, target, ability)
	local t_now = now_time()
	local target_pos = Entity.GetAbsOrigin(target)
	local _ = t_now
	local dbg = {
		t_now = t_now,
		target_pos = target_pos,
		has_agh = has_agh_effect(hero),
	}

	if not dbg.has_agh then
		dbg.cast_pos = target_pos
		dbg.mode = "no_agh"
		return target_pos, dbg
	end
	local r = get_mystic_flare_radius(hero, ability)
	dbg.r = r

	-- Prefer Rod impact prediction when available: if Rod is in the sequence, the target will be rooted there.
	local pred_pos = target_pos
	local used_rod_predict = false
	local rooted_now = target_has_rod_root(target)
	dbg.rod_rooted = rooted_now

	-- If we are explicitly waiting for the Rod root modifier, prefer the CURRENT position once rooted.
	-- This avoids using an older predicted impact position and guarantees we cast from the latest snapshot.
	if rooted_now and ui and ui.wait_rod_modifier and ui.wait_rod_modifier.Get and ui.wait_rod_modifier:Get() then
		pred_pos = target_pos
		used_rod_predict = false
		dbg.used_latest_root_pos = true
	end
	if rod_predict and rod_predict.target == target and rod_predict.impact_pos and rod_predict.hit_t then
		local dt_to_hit = (rod_predict.hit_t or t_now) - t_now
		-- Use prediction shortly before impact and a bit after (grace), since timing can drift.
		if dt_to_hit >= -ROD_PREDICTION_GRACE and dt_to_hit <= 1.50 then
			-- Recompute impact position live using the *current* movement sample.
			-- This handles last-second jukes/turns better than freezing a single prediction at Rod cast time.
			local live_dt = dt_to_hit
			if live_dt < 0.0 then live_dt = 0.0 end
			local live_dir = get_target_move_dir(target)
			local live_speed = get_target_move_speed(target)
			local live_impact = compute_predicted_pos_at_time(target_pos, live_dir, live_speed, live_dt)
			-- If we're waiting on the root modifier, do not override the "latest rooted position" behavior.
			if not (rooted_now and ui and ui.wait_rod_modifier and ui.wait_rod_modifier.Get and ui.wait_rod_modifier:Get()) then
				pred_pos = live_impact or rod_predict.impact_pos
				used_rod_predict = true
			end
			dbg.rod_dt = dt_to_hit
			dbg.rod_impact_frozen = rod_predict.impact_pos
			dbg.rod_impact_live = pred_pos
		end
	end

	-- Movement lead (when not relying on Rod prediction): lead to where the target will be when flare starts dealing damage.
	local move_dir = get_target_move_dir(target)
	local move_speed = get_target_move_speed(target)
	local move_age = nil
	local m = target_motion and target_motion[target] or nil
	if m and m.t then
		move_age = t_now - (m.t or t_now)
	end
	local cast_point = 0.10
	if Ability and Ability.GetCastPoint then
		local ok, cp = pcall(Ability.GetCastPoint, ability)
		if ok and type(cp) == "number" then cast_point = cp end
	end
	-- Tuned for reliability vs moving targets (accounts for castpoint + input/latency + flare onset).
	local EXTRA_EFFECT_TIME = 0.55
	local LEAD_TIME = cast_point + EXTRA_EFFECT_TIME
	local MAX_LEAD_DIST = 450.0
	local lead_dist = 0.0
	if (not used_rod_predict) and move_dir and move_speed and move_speed > 30.0 then
		lead_dist = move_speed * LEAD_TIME
		lead_dist = clamp_number(lead_dist, 0.0, MAX_LEAD_DIST, 0.0)
		pred_pos = Vector(target_pos.x + move_dir.x * lead_dist, target_pos.y + move_dir.y * lead_dist, target_pos.z)
	end
	dbg.pred_pos = pred_pos
	dbg.move_speed = move_speed
	dbg.move_age = move_age
	dbg.lead_dist = lead_dist
	dbg.lead_time = LEAD_TIME
	dbg.max_lead = MAX_LEAD_DIST
	dbg.used_rod_predict = used_rod_predict

	-- Offset direction: "in front" of the unit.
	-- Prefer facing direction; fall back to movement direction if facing is unavailable.
	local dir = nil
	local dir_src = nil
	dir = get_target_facing_dir(target)
	dir_src = "facing"
	if not dir then
		dir = move_dir
		dir_src = "move"
	end
	if not dir then
		local m2 = target_motion and target_motion[target] or nil
		if m2 and m2.dir then
			dir = m2.dir
			dir_src = "motion"
		end
	end
	if not dir then
		-- Last resort: use away-from-hero direction (NOT toward hero).
		local hero_pos = Entity.GetAbsOrigin(hero)
		dir = Vector(target_pos.x - hero_pos.x, target_pos.y - hero_pos.y, 0.0)
		local len = dir:Length2D()
		if not len or len < 0.001 then
			dbg.cast_pos = target_pos
			dbg.mode = "agh_no_dir"
			return target_pos, dbg
		end
		dir = dir:Normalized()
		dir_src = "away_from_hero"
	end
	dbg.dir = dir
	dbg.dir_src = dir_src

	-- User-selected distance from the enemy center.
	local FLARE_OFFSET_DEFAULT = 175.0
	local FLARE_OFFSET_GUNGIR = 250.0
	local offset_units = FLARE_OFFSET_DEFAULT
	if hero_has_item_name(hero, "item_gungir") or hero_has_item_name(hero, "item_gleipnir") then
		offset_units = FLARE_OFFSET_GUNGIR
	end
	dbg.offset_units = offset_units

	-- Final placement: cast in front of the (predicted) target position by offset_units.
	local cast_pos = Vector(pred_pos.x + dir.x * offset_units, pred_pos.y + dir.y * offset_units, pred_pos.z)
	dbg.cast_pos = cast_pos
	dbg.mode = "agh_offset_units"
	return cast_pos, dbg
end

local function get_cast_range(hero, ability)
	if not ability or not hero then return 0.0 end
	local cast_range = 0.0
	if Ability and Ability.GetCastRange then
		cast_range = Ability.GetCastRange(ability) or 0.0
	end
	-- Some items/abilities can report 0 here; try reading KV special values as a fallback.
	-- This helps with items like Gleipnir/Gungir being treated as 0-range and "casting" out of range.
	if (not cast_range or cast_range <= 0.0) and Ability and Ability.GetLevelSpecialValueFor then
		local ok_sv, sv = pcall(Ability.GetLevelSpecialValueFor, ability, "cast_range", -1)
		if ok_sv and type(sv) == "number" and sv > 0 then
			cast_range = sv
		else
			ok_sv, sv = pcall(Ability.GetLevelSpecialValueFor, ability, "range", -1)
			if ok_sv and type(sv) == "number" and sv > 0 then
				cast_range = sv
			end
		end
	end
	if NPC and NPC.GetCastRangeBonus then
		cast_range = cast_range + (NPC.GetCastRangeBonus(hero) or 0.0)
	end
	return cast_range
end

-- One-time trace logs per combo run (gated by Debug Logs).
-- Must be declared before cast_fast() to avoid accidental global/upvalue mismatch.
local flare_trace_logged = false
local combo_end_logged = false
local trace_version_logged = false

local inventory_dump_logged = false

local function dump_inventory_once(hero)
	if inventory_dump_logged then return end
	if not ui or not ui.debug_logs or not ui.debug_logs.Get or not ui.debug_logs:Get() then return end
	if not hero or not NPC or not NPC.GetItemByIndex or not Ability or not Ability.GetName then return end
	inventory_dump_logged = true
	local parts = {}
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(hero, i)
		if item then
			local ok_n, nm = pcall(Ability.GetName, item)
			if ok_n and type(nm) == "string" and nm ~= "" then
				parts[#parts + 1] = string.format("%d:%s", i, nm)
			else
				parts[#parts + 1] = string.format("%d:(unknown)", i)
			end
		end
	end
	log_debug("[INV] " .. (#parts > 0 and table.concat(parts, " | ") or "(no items found)"))
end

local function band_int(a, b)
	if type(a) ~= "number" or type(b) ~= "number" then return 0 end
	if bit and bit.band then return bit.band(a, b) end
	if bit32 and bit32.band then return bit32.band(a, b) end
	-- Fallback bitwise AND for integer-like numbers.
	a = math.floor(a)
	b = math.floor(b)
	local res = 0
	local bitval = 1
	while a > 0 and b > 0 do
		local abit = a % 2
		local bbit = b % 2
		if abit == 1 and bbit == 1 then res = res + bitval end
		a = math.floor(a / 2)
		b = math.floor(b / 2)
		bitval = bitval * 2
	end
	return res
end

local function has_behavior_flag(behavior, flag)
	if type(behavior) ~= "number" or type(flag) ~= "number" then return false end
	return band_int(behavior, flag) ~= 0
end

cast_fast = function(ability, spell, target)
	if not ability then return false, "missing" end
	local hero = Heroes.GetLocal()
	if not hero then return false, "no_local_hero" end
	if not Ability.IsReady(ability) then return false, "not_ready" end
	local mana = NPC.GetMana(hero) or 0.0
	if not Ability.IsCastable(ability, mana) then
		return false, "not_castable" -- usually mana/silence/mute
	end

	-- Prevent advancing the combo from queued move-casts.
	-- Only cast when the target/position is actually in cast range.
	local cast_range = get_cast_range(hero, ability)
	-- Hard fallback for Rod of Atos and its variants: some APIs return 0 cast range for items.
	-- If we don't enforce range here, we'll issue casts from too far away and then wait forever for cooldown.
	if (not cast_range or cast_range <= 0.0) and spell and spell.name == "item_rod_of_atos" then
		cast_range = 1100.0
		if NPC and NPC.GetCastRangeBonus then
			cast_range = cast_range + (NPC.GetCastRangeBonus(hero) or 0.0)
		end
	end

	if spell.cast == "no_target" then
		Ability.CastNoTarget(ability, false, false, false)
		return true, "cast"
	end
	if not target then return false, "no_target" end
	if not Entity.IsAlive(target) then return false, "target_dead" end
	if spell.cast == "position" then
		local pos, flare_dbg = get_mystic_flare_cast_pos(hero, target, ability)
		if NPC and NPC.IsPositionInRange and cast_range > 0.0 then
			if not NPC.IsPositionInRange(hero, pos, cast_range) then return false, "out_of_range" end
		end
		if ui and ui.debug_logs and ui.debug_logs.Get and ui.debug_logs:Get() and (not flare_trace_logged) and spell and spell.name == "skywrath_mage_mystic_flare" then
			flare_trace_logged = true
			local hero_pos = Entity.GetAbsOrigin(hero)
			local target_pos = (flare_dbg and flare_dbg.target_pos) or Entity.GetAbsOrigin(target)
			local r = (flare_dbg and flare_dbg.r) or get_mystic_flare_radius(hero, ability)
			local dir = flare_dbg and flare_dbg.dir or nil
			local offset_units = flare_dbg and flare_dbg.offset_units or nil
			log_debug("[FLARE TRACE] ---")
			log_debug(string.format("[FLARE TRACE] target_alive=%s", tostring(Entity.IsAlive(target))))
			log_debug(string.format("[FLARE TRACE] hero_pos=%s target_pos=%s cast_pos=%s", fmt_vec2(hero_pos), fmt_vec2(target_pos), fmt_vec2(pos)))
			if flare_dbg and flare_dbg.pred_pos then
				local frozen = flare_dbg.rod_impact_frozen
				local live = flare_dbg.rod_impact_live
				log_debug(string.format("[FLARE TRACE] pred_pos=%s lead_dist=%.1f lead_time=%.2f max_lead=%.0f move_speed=%.1f move_age=%.3f rod=%s rod_dt=%.3f rod_frozen=%s rod_live=%s", fmt_vec2(flare_dbg.pred_pos), tonumber(flare_dbg.lead_dist) or 0.0, tonumber(flare_dbg.lead_time) or 0.0, tonumber(flare_dbg.max_lead) or 0.0, tonumber(flare_dbg.move_speed) or 0.0, tonumber(flare_dbg.move_age) or -1.0, tostring(flare_dbg.used_rod_predict), tonumber(flare_dbg.rod_dt) or -999.0, fmt_vec2(frozen), fmt_vec2(live)))
			end
			log_debug(string.format("[FLARE TRACE] mode=%s agh=%s r=%.1f dir_src=%s dir=%s", tostring(flare_dbg and flare_dbg.mode), tostring(flare_dbg and flare_dbg.has_agh), tonumber(r) or 0.0, tostring(flare_dbg and flare_dbg.dir_src), fmt_vec2(dir)))
			log_debug(string.format("[FLARE TRACE] offset_units=%.1f", tonumber(offset_units) or 0.0))

			-- Overlap checks (two hypotheses) using radius r.
			-- H1: centers at target_pos and cast_pos (what our code intends).
			local h1_c1 = target_pos
			local h1_c2 = pos
			local h1_mid = Vector((h1_c1.x + h1_c2.x) / 2.0, (h1_c1.y + h1_c2.y) / 2.0, target_pos.z)
			local h1_d1 = distance2d(target_pos, h1_c1)
			local h1_d2 = distance2d(target_pos, h1_c2)
			log_debug(string.format("[FLARE TRACE] H1 centers: c1=%s c2=%s mid=%s d_to_c1=%.1f d_to_c2=%.1f in_both=%s", fmt_vec2(h1_c1), fmt_vec2(h1_c2), fmt_vec2(h1_mid), h1_d1, h1_d2, tostring((h1_d1 <= r) and (h1_d2 <= r))))

			-- H2: symmetric centers around cast_pos by +/- r/2 along dir.
			if dir and dir.x and dir.y then
				local sep = r / 2.0
				local h2_c1 = Vector(pos.x + dir.x * sep, pos.y + dir.y * sep, pos.z)
				local h2_c2 = Vector(pos.x - dir.x * sep, pos.y - dir.y * sep, pos.z)
				local h2_mid = Vector((h2_c1.x + h2_c2.x) / 2.0, (h2_c1.y + h2_c2.y) / 2.0, pos.z)
				local h2_d1 = distance2d(target_pos, h2_c1)
				local h2_d2 = distance2d(target_pos, h2_c2)
				log_debug(string.format("[FLARE TRACE] H2 centers: c1=%s c2=%s mid=%s d_to_c1=%.1f d_to_c2=%.1f in_both=%s", fmt_vec2(h2_c1), fmt_vec2(h2_c2), fmt_vec2(h2_mid), h2_d1, h2_d2, tostring((h2_d1 <= r) and (h2_d2 <= r))))
				if flare_dbg and flare_dbg.pred_pos then
					local pred = flare_dbg.pred_pos
					local ph2_d1 = distance2d(pred, h2_c1)
					local ph2_d2 = distance2d(pred, h2_c2)
					log_debug(string.format("[FLARE TRACE] H2@pred: pred=%s d_to_c1=%.1f d_to_c2=%.1f in_both=%s", fmt_vec2(pred), ph2_d1, ph2_d2, tostring((ph2_d1 <= r) and (ph2_d2 <= r))))
				end
			end

			-- Rod prediction context (if available).
			if rod_predict and rod_predict.target == target then
				local t_now = now_time()
				local age = t_now - (rod_predict.cast_t or t_now)
				local time_to_hit = (rod_predict.hit_t or t_now) - t_now
				log_debug(string.format("[FLARE TRACE] rod_predict: age=%.2f time_to_hit=%.2f impact_pos=%s", age, time_to_hit, fmt_vec2(rod_predict.impact_pos)))
			end
		end
		Ability.CastPosition(ability, pos, false, false, false)
		return true, "cast"
	end

	-- Auto-select target vs position cast based on ability behavior.
	-- Some custom item variants (e.g. item_gungir) can be point-target even when we conceptually treat them like Rod.
	local behavior = nil
	if Ability and Ability.GetBehavior then
		local ok_b, b = pcall(Ability.GetBehavior, ability, true)
		if ok_b and type(b) == "number" then behavior = b end
		if behavior == nil then
			ok_b, b = pcall(Ability.GetBehavior, ability)
			if ok_b and type(b) == "number" then behavior = b end
		end
	end

	local is_point_only = false
	if behavior ~= nil and Enum and Enum.AbilityBehavior then
		local is_point = has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_POINT)
			or has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_OPTIONAL_POINT)
			or has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_LAST_RESORT_POINT)
		local is_unit = has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_UNIT_TARGET)
			or has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_OPTIONAL_UNIT_TARGET)
		is_point_only = is_point and (not is_unit)
	end

	if ui and ui.debug_logs and ui.debug_logs.Get and ui.debug_logs:Get() and spell and spell.name == "item_rod_of_atos" then
		local resolved_name = "(unknown)"
		if Ability and Ability.GetName then
			local ok_n, nm = pcall(Ability.GetName, ability)
			if ok_n and type(nm) == "string" and nm ~= "" then resolved_name = nm end
		end
		log_debug(string.format("[ROD] resolved=%s behavior=%s point_only=%s", tostring(resolved_name), tostring(behavior), tostring(is_point_only)))
	end

	if is_point_only then
		local pos = Entity.GetAbsOrigin(target)
		if NPC and NPC.IsPositionInRange and cast_range > 0.0 then
			if not NPC.IsPositionInRange(hero, pos, cast_range) then return false, "out_of_range" end
		end
		Ability.CastPosition(ability, pos, false, false, false)
		return true, "cast"
	end

	if NPC and NPC.IsEntityInRange and cast_range > 0.0 then
		if not NPC.IsEntityInRange(hero, target, cast_range) then return false, "out_of_range" end
	end
	Ability.CastTarget(ability, target, false, false, false)
	return true, "cast"
end

local function find_target_near_cursor()
	local hero = Heroes.GetLocal()
	if not hero then return nil end
	local cursor = Input.GetWorldCursorPos()
	local my_team = Entity.GetTeamNum(hero)
	local radius = tonumber(ui.search_radius:Get()) or 300
	if radius < 50 then radius = 50 end
	if radius > 2000 then radius = 2000 end
	local enemies = Heroes.InRadius(cursor, radius, my_team, Enum.TeamType.TEAM_ENEMY, true, true)
	if not enemies or #enemies == 0 then return nil end
	local best, best_dist = nil, radius
	for _, enemy in pairs(enemies) do
		if enemy and Entity.IsAlive(enemy) and enemy ~= hero and Entity.GetTeamNum(enemy) ~= my_team then
			-- Skip targets with reflect/immune buffs we don't want to engage.
			local forbidden = (target_is_forbidden ~= nil) and target_is_forbidden(enemy) or false
			if not forbidden then
				local pos = Entity.GetAbsOrigin(enemy)
				local dist = cursor:Distance(pos)
				if dist < best_dist then
					best_dist = dist
					best = enemy
				end
			end
		end
	end
	return best
end

local was_key_down = false
local combo_running = false
local combo_target = nil
local combo_seq = {}
local combo_idx = 1
local next_cast_time = 0.0
local combo_cycle_logged = false  -- Only log one complete cycle

-- Optional per-cast override (used for Rod travel-time gating).
local next_cast_time_override = nil

-- Safety: if we are waiting on Rod's root modifier but it never appears (Linken's/spell block/dispel/name mismatch),
-- retry Rod a limited number of times rather than stalling forever at Mystic Flare.
local rod_modifier_wait_retry_count = 0
local rod_modifier_wait_last_retry_t = -1000.0
local rod_modifier_wait_giveup_logged = false

-- When enabled, block further steps until Ethereal Blade debuff modifier is visible on the target.
local eblade_modifier_waiting = false
local eblade_modifier_wait_cast_t = 0.0

-- Optional per-combo gate: when enabled, Sheep Stick must be cast before other steps.
local force_sheep_done = false

-- Control-chain prefix: Sheep -> Rod -> Ancient Seal -> EBlade.
-- Goal: fire these ASAP (in order) when available, then continue into damage.
local control_chain_done = nil -- { [spell_name]=true }
local control_chain_complete = false
local control_chain_last_seq_idx = 0

-- Rod impact prediction declared near the top (required for correct Lua scoping).

local linkens_prefix_done = false

local last_fail_reason = nil
local last_fail_step = nil
local last_fail_log_t = 0.0
local FAIL_LOG_COOLDOWN = 0.25

local STEP_CAST = 1
local STEP_SKIPPED = 2
local STEP_BLOCKED = 3

local desired_min_range = 0.0
local last_move_order_t = 0.0
local MOVE_ORDER_COOLDOWN = 0.20

local moving_to_target = false
local last_ground_pos = nil
local GROUND_MOVE_MIN_DIST = 80.0

local function reset_combo()
	if ui and ui.debug_logs and ui.debug_logs.Get and ui.debug_logs:Get() then
		-- Per-step timing summary (helps diagnose delays between successful casts).
		if step_trace then
			log_debug("[STEP SUMMARY] ---")
			local n = (combo_seq and #combo_seq) or 0
			if n <= 0 then n = MAX_STEPS end
			for idx = 1, n do
				local st = step_trace[idx]
				if st then
					local entered = st.entered_t
					local first_a = st.first_attempt_t
					local succ = st.success_t
					local dt_enter = (entered and succ) and (succ - entered) or -1.0
					local dt_attempt = (first_a and succ) and (succ - first_a) or -1.0
					local status = succ and "OK" or "NO_CAST"
					log_debug(string.format("[STEP SUMMARY] step=%d %s status=%s attempts=%d skips=%d dt_enter=%.3f dt_attempt=%.3f",
						tonumber(st.step) or idx,
						tostring(st.name),
						status,
						tostring(st.attempts or 0),
						tostring(st.skips or 0),
						dt_enter,
						dt_attempt
					))
					if st.blocks then
						for reason, cnt in pairs(st.blocks) do
							log_debug(string.format("[STEP SUMMARY]   block %s x%d", tostring(reason), tonumber(cnt) or 0))
						end
					end
					if st.fails then
						for reason, cnt in pairs(st.fails) do
							log_debug(string.format("[STEP SUMMARY]   fail %s x%d", tostring(reason), tonumber(cnt) or 0))
						end
					end
				end
			end
		end

		-- Print an end-of-combo summary with timing between successful casts.
		if combo_events and #combo_events > 0 then
			log_debug(string.format("[SUMMARY] events=%d (showing last %d)", combo_event_seq or #combo_events, #combo_events))
			for _, e in ipairs(combo_events) do
				log_debug(string.format("[SUMMARY] #%d t=%.3f +%.3f start=%.3f %s step=%s %s%s",
					tostring(e.seq),
					tostring(e.t),
					tostring(e.dt),
					tostring(e.from_start),
					tostring(e.kind),
					tostring(e.step),
					tostring(e.name),
					e.reason and (" reason=" .. tostring(e.reason)) or ""
				))
			end
		end
	end
	if ui and ui.debug_logs and ui.debug_logs.Get and ui.debug_logs:Get() and combo_running and (not combo_end_logged) then
		local alive = (combo_target ~= nil) and Entity and Entity.IsAlive and Entity.IsAlive(combo_target) or false
		log_debug(string.format("[COMBO END] reset_combo alive=%s", tostring(alive)))
		combo_end_logged = true
	end
	combo_running = false
	combo_target = nil
	combo_seq = {}
	combo_idx = 1
	next_cast_time = 0.0
	next_cast_time_override = nil
	rod_modifier_wait_retry_count = 0
	rod_modifier_wait_last_retry_t = -1000.0
	rod_modifier_wait_giveup_logged = false
	eblade_modifier_waiting = false
	eblade_modifier_wait_cast_t = 0.0
	force_sheep_done = false
	control_chain_done = nil
	control_chain_complete = false
	control_chain_last_seq_idx = 0
	rod_predict = nil
	linkens_prefix_done = false
	desired_min_range = 0.0
	last_move_order_t = 0.0
	moving_to_target = false
	last_ground_pos = nil
	last_fail_reason = nil
	last_fail_step = nil
	last_fail_log_t = 0.0
	combo_cycle_logged = false
	flare_trace_logged = false
	combo_end_logged = false
	trace_version_logged = false
	combo_start_t = 0.0
	combo_last_cast_t = 0.0
	combo_event_seq = 0
	combo_events = nil
	step_trace = nil
	last_success_cast_t = 0.0
	pending_cooldown_confirm = nil
	pending_linkens_break_confirm = nil
	inventory_dump_logged = false
end

local function start_combo(target)
	combo_start_t = now_time()
	combo_last_cast_t = 0.0
	combo_event_seq = 0
	combo_events = {}
	step_trace = {}
	last_success_cast_t = 0.0
	pending_cooldown_confirm = nil
	pending_linkens_break_confirm = nil
	inventory_dump_logged = false
	combo_running = true
	combo_target = target
	combo_seq = build_combo_sequence()
	combo_idx = 1
	next_cast_time = 0.0
	next_cast_time_override = nil
	rod_modifier_wait_retry_count = 0
	rod_modifier_wait_last_retry_t = -1000.0
	rod_modifier_wait_giveup_logged = false
	eblade_modifier_waiting = false
	eblade_modifier_wait_cast_t = 0.0
	force_sheep_done = false
	control_chain_done = {}
	control_chain_complete = false
	control_chain_last_seq_idx = 0
	rod_predict = nil
	linkens_prefix_done = false
	desired_min_range = 0.0
	last_move_order_t = 0.0
	moving_to_target = false
	last_ground_pos = nil
	last_fail_reason = nil
	last_fail_step = nil
	last_fail_log_t = 0.0
	combo_cycle_logged = false
	flare_trace_logged = false
	combo_end_logged = false
	if ui and ui.debug_logs and ui.debug_logs.Get and ui.debug_logs:Get() and (not trace_version_logged) then
		trace_version_logged = true
		log_debug("[TRACE VERSION] flare_trace_v3")
	end
	if ui and ui.debug_logs and ui.debug_logs.Get and ui.debug_logs:Get() then
		local names = {}
		for i, s in ipairs(combo_seq or {}) do
			names[#names + 1] = string.format("%d:%s", i, tostring(s and s.name))
		end
		log_debug("Combo order: " .. table.concat(names, " -> "))
		dbg_add_event("START", "-", "combo", "")
	end
	log_debug("Start combo. Steps=" .. tostring(#combo_seq))
	-- Debug helper: print inventory item internal names once per combo, so we can see what Gleipnir/Gungir is called.
	dump_inventory_once(Heroes.GetLocal())
end

local function compute_min_required_range(hero)
	if not hero or not combo_seq then return 0.0 end
	local min_r = nil
	for _, spell in ipairs(combo_seq) do
		if spell and spell.cast ~= "no_target" then
			local a = get_spell(hero, spell)
			if a then
				local r = get_cast_range(hero, a)
				if r and r > 0.0 then
					if not min_r or r < min_r then min_r = r end
				end
			end
		end
	end
	return min_r or 0.0
end

local function issue_move_to_target(hero, target)
	if not hero or not target then return end
	local t = now_time()
	if (t - last_move_order_t) < MOVE_ORDER_COOLDOWN then return end
	last_move_order_t = t
	moving_to_target = true
	if NPC and NPC.MoveTo then
		NPC.MoveTo(hero, Entity.GetAbsOrigin(target), false, false, false, true, "skywrath_combo_move", true)
	end
	log_debug("Move toward target")
end

local function issue_move_to_ground(hero, pos)
	if not hero or not pos then return end
	local t = now_time()
	if (t - last_move_order_t) < MOVE_ORDER_COOLDOWN then return end
	if last_ground_pos and last_ground_pos.Distance then
		if last_ground_pos:Distance(pos) < GROUND_MOVE_MIN_DIST then
			return
		end
	end
	last_move_order_t = t
	last_ground_pos = pos
	moving_to_target = false
	if NPC and NPC.MoveTo then
		NPC.MoveTo(hero, pos, false, false, false, true, "skywrath_combo_ground", true)
	end
	log_debug("Move to cursor")
end

local LINKENS_MODIFIERS = {
	"modifier_item_sphere",
	"modifier_item_sphere_target",
	"modifier_item_sphere_buff",
	"modifier_item_sphere_target_buff",
}

-- If any of these are active, we refuse to target the enemy at all.
-- Goal: never cast into reflect/dark pact/enrage/counterspell/debuff immunity.
local FORBIDDEN_TARGET_MODIFIERS = {
	-- Reflect / spell return
	"modifier_item_lotus_orb_active",
	-- Ursa
	"modifier_ursa_enrage",
	-- Slark
	"modifier_slark_dark_pact",
	"modifier_slark_dark_pact_pulses",
	-- Anti-Mage
	"modifier_antimage_counterspell",
	"modifier_antimage_counterspell_active",
	-- Common spell/debuff immunity sources (fallbacks if API checks are unavailable)
	"modifier_black_king_bar_immune",
	"modifier_item_black_king_bar_immune",
	"modifier_item_minotaur_horn",
	"modifier_life_stealer_rage",
	"modifier_juggernaut_blade_fury",
}

target_is_forbidden = function(target)
	if not target or not Entity or not Entity.IsAlive or not Entity.IsAlive(target) then return true end
	-- Prefer broad API state checks when available.
	if NPC then
		if NPC.IsDebuffImmune then
			local ok, v = pcall(NPC.IsDebuffImmune, target)
			if ok and v then return true end
		end
		if NPC.IsMagicImmune then
			local ok, v = pcall(NPC.IsMagicImmune, target)
			if ok and v then return true end
		end
	end
	if Entity and Entity.IsInvulnerable then
		local ok, v = pcall(Entity.IsInvulnerable, target)
		if ok and v then return true end
	end
	if NPC and NPC.HasModifier then
		for _, m in ipairs(FORBIDDEN_TARGET_MODIFIERS) do
			if NPC.HasModifier(target, m) then return true end
		end
	end
	return false
end

local LINKENS_BREAK_GRACE_SECONDS = 0.60
local last_linkens_break_t = -1000.0

-- When we issue the Linken's breaker cast, wait until its cooldown actually starts
-- before allowing the rest of the combo to proceed.
local pending_linkens_break_confirm = nil

local function target_has_linkens(target)
	if not target or not NPC then return false end

	-- Best-effort: Linken's can leave a passive modifier even while the spell block is on cooldown.
	-- Prefer checking the actual item's cooldown when possible.
	if NPC.GetItemByIndex and Ability and Ability.GetName then
		for i = 0, 20 do
			local item = NPC.GetItemByIndex(target, i)
			if item then
				local ok_n, nm = pcall(Ability.GetName, item)
				if ok_n and nm == "item_sphere" then
					-- If the item is ready (cooldown 0), the shield is considered active/available.
					if Ability.IsReady then
						local ok_r, ready = pcall(Ability.IsReady, item)
						if ok_r then return ready == true end
					end
					local cd = get_cooldown_remaining_seconds(item)
					return (cd == nil) or (cd <= 0.0)
				end
			end
		end
	end

	-- Fallback: if we can't read item cooldown (e.g. Linken's buff from ally), rely on modifiers.
	-- Note: we intentionally do NOT treat the generic passive "modifier_item_sphere" alone as proof of readiness.
	if NPC.HasModifier then
		if NPC.HasModifier(target, "modifier_item_sphere_target") then return true end
		if NPC.HasModifier(target, "modifier_item_sphere_target_buff") then return true end
	end
	return false
end

local EBLADE_MODIFIERS = {
	-- Most common (applied to the target when projectile hits)
	"modifier_item_ethereal_blade_ethereal",
	"modifier_item_ethereal_blade_slow",
	-- Extra fallbacks across patches/variants
	"modifier_item_ethereal_blade_slow_debuff",
	"modifier_ethereal_blade_ethereal",
}

local function target_has_eblade_debuff(target)
	if not target or not NPC or not NPC.HasModifier then return false end
	for _, m in ipairs(EBLADE_MODIFIERS) do
		if NPC.HasModifier(target, m) then return true end
	end
	return false
end

local function is_damage_spell(spell)
	if not spell or not spell.name then return false end
	local n = spell.name
	return n == "skywrath_mage_concussive_shot"
		or n == "skywrath_mage_arcane_bolt"
		or n == "item_dagon"
		or n == "skywrath_mage_mystic_flare"
end

local ROD_ROOT_MODIFIERS = {
	"modifier_rod_of_atos_debuff",
	"modifier_item_rod_of_atos_debuff",
	"modifier_rod_of_atos",
	"modifier_item_rod_of_atos",
	-- Some clients/variants use non-item-prefixed names
	"modifier_gungnir_debuff",
	"modifier_gungnir_root",
	"modifier_gleipnir_root",
	"modifier_item_gungir_debuff",
	"modifier_item_gungir_root",
	"modifier_item_gleipnir_root",
	"modifier_item_rod_of_atos_root",
}

local function get_rod_root_modifier_name(target)
	if not target or not NPC or not NPC.HasModifier then return nil end
	for _, m in ipairs(ROD_ROOT_MODIFIERS) do
		if NPC.HasModifier(target, m) then return m end
	end
	return nil
end

local function get_target_modifier_names(target, max_items)
	if not target or not NPC or not NPC.GetModifiers or not Modifier or not Modifier.GetName then return nil end
	local ok, mods = pcall(NPC.GetModifiers, target)
	if not ok or type(mods) ~= "table" then return nil end
	local limit = tonumber(max_items) or 14
	if limit < 1 then limit = 1 end
	local names = {}
	for i = 1, math.min(#mods, limit) do
		local mod = mods[i]
		if mod then
			local okn, nm = pcall(Modifier.GetName, mod)
			if okn and type(nm) == "string" and nm ~= "" then
				names[#names + 1] = nm
			end
		end
	end
	return names
end

target_has_rod_root = function(target)
	if not target or not NPC or not NPC.HasModifier then return false end
	for _, m in ipairs(ROD_ROOT_MODIFIERS) do
		if NPC.HasModifier(target, m) then return true end
	end
	return false
end

local function get_linkens_breaker_priority_ids()
	if linkens_break_enabled_names and #linkens_break_enabled_names > 0 then
		return linkens_break_enabled_names
	end
	return LINKENS_BREAK_ORDER_ITEMS
end

local function step_combo()
	-- After first complete cycle (idx wrapped back to 1), stop detailed logging
	if combo_idx == 1 and combo_cycle_logged then
		-- Silent mode after first cycle - still execute, but don't log every step
		if ui.debug_logs:Get() then
			log_debug("[STEP] Cycling (silent mode)")
		end
	end
	
	local should_log = ui.debug_logs:Get() and not combo_cycle_logged
	
	if should_log then
		log_debug(string.format("[STEP] Enter: idx=%d", combo_idx))
	end
	
	if not combo_running or not combo_target or not Entity.IsAlive(combo_target) then
		if should_log then
			log_debug("[STEP] Exit: BLOCKED (no target/not running)")
		end
		dbg_add_event("END", tostring(combo_idx), "no_target_or_dead", "")
		reset_combo()
		return STEP_BLOCKED
	end

	-- Abort if target becomes unsafe (Lotus/Enrage/Dark Pact/Counterspell/Immunity).
	if target_is_forbidden and target_is_forbidden(combo_target) then
		if should_log then
			log_debug("[STEP] Exit: BLOCKED (target forbidden/immune)")
		end
		dbg_add_event("END", tostring(combo_idx), "target_forbidden", "")
		reset_combo()
		return STEP_BLOCKED
	end

	local hero = Heroes.GetLocal()
	if not hero then
		if should_log then
			log_debug("[STEP] Exit: BLOCKED (no hero)")
		end
		reset_combo()
		return STEP_BLOCKED
	end
	if not combo_seq or #combo_seq == 0 then
		if should_log then
			log_debug("[STEP] Exit: BLOCKED (empty seq)")
		end
		return STEP_BLOCKED
	end
	if combo_idx < 1 or combo_idx > #combo_seq then
		if should_log then
			log_debug(string.format("[STEP] Reset idx from %d to 1", combo_idx))
		end
		combo_idx = 1
	end

	-- Optional: after casting Ethereal Blade, don't continue until the debuff is on the enemy.
	if ui.wait_eblade_modifier and ui.wait_eblade_modifier.Get and ui.wait_eblade_modifier:Get() and eblade_modifier_waiting then
		if target_has_eblade_debuff(combo_target) then
			eblade_modifier_waiting = false
			eblade_modifier_wait_cast_t = 0.0
		else
			local cur_spell = combo_seq[combo_idx]
			-- Allow us to keep attempting EBlade itself; block everything else.
			if not cur_spell or cur_spell.name ~= "item_ethereal_blade" then
				local t_now = now_time()
				next_cast_time = t_now + CAST_GAP_SECONDS
				if should_log then
					local dt = 0.0
					if eblade_modifier_wait_cast_t and eblade_modifier_wait_cast_t > 0.0 then
						dt = t_now - eblade_modifier_wait_cast_t
					end
					log_debug(string.format("[STEP] Waiting Ethereal Blade modifier on target (%.2fs)", dt))
				end
				dbg_add_event("BLOCK", combo_idx, cur_spell and cur_spell.name, "wait_eblade_modifier")
				trace_step_block(combo_idx, cur_spell, "wait_eblade_modifier")
				return STEP_BLOCKED
			end
		end
	end
	local function advance_idx()
		local old_idx = combo_idx
		combo_idx = combo_idx + 1
		if combo_idx > #combo_seq then 
			combo_idx = 1
			combo_cycle_logged = true  -- Mark first cycle complete
		end
		if should_log then
			log_debug(string.format("[STEP] advance_idx: %d -> %d", old_idx, combo_idx))
		end
	end

	-- Before starting the combo (and while running), ensure we're in range for the *shortest* range step.
	if desired_min_range <= 0.0 then
		desired_min_range = compute_min_required_range(hero)
		if desired_min_range > 0.0 then
			log_debug("Min cast range required: " .. tostring(math.floor(desired_min_range)))
		end
	end
	if desired_min_range > 0.0 and NPC and NPC.IsEntityInRange then
		if not NPC.IsEntityInRange(hero, combo_target, desired_min_range) then
			issue_move_to_target(hero, combo_target)
			return STEP_BLOCKED
		end
		-- We are now in range; stop any previous move-to-target order so we don't keep walking.
		if moving_to_target then
			stop_hero_orders()
			moving_to_target = false
		end
	end

	-- Linken's Sphere handling: if target has Linken's active, use breaker priority list first.
	local has_linkens = target_has_linkens(combo_target)
	-- If Linken's is NOT currently active (on cooldown / already broken), do normal combo.
	if not has_linkens then
		pending_linkens_break_confirm = nil
	else
		local need_break = (pending_linkens_break_confirm ~= nil) or (not linkens_prefix_done)
		if need_break then
			local breaker_ids = get_linkens_breaker_priority_ids()
			if not breaker_ids or #breaker_ids == 0 then
				if ui.debug_logs:Get() then
					log_debug("Linken's is active but breaker list is empty")
				end
				return STEP_BLOCKED
			end

		-- If we already issued the breaker cast, wait for cooldown to actually start.
		if pending_linkens_break_confirm and pending_linkens_break_confirm.name then
			local pending_spell = { name = pending_linkens_break_confirm.name, kind = "item", cast = "target" }
			-- Map back to spell_map entry when possible (better for item/ability resolution).
			for k, v in pairs(spell_map) do
				if v and v.name == pending_linkens_break_confirm.name then
					pending_spell = v
					break
				end
			end
			local ability = get_spell(hero, pending_spell)
			if not ability then
				pending_linkens_break_confirm = nil
				return STEP_BLOCKED
			end
			local t_now = now_time()
			if is_cooldown_started(ability) then
				pending_linkens_break_confirm = nil
				last_linkens_break_t = t_now
				linkens_prefix_done = true
				combo_idx = 1
				if ui.debug_logs:Get() then
					log_debug("Linken's breaker cooldown confirmed: " .. tostring(pending_spell and pending_spell.name))
				end
				return STEP_CAST
			end
			if t_now < (pending_linkens_break_confirm.next_try_t or t_now) then
				next_cast_time = t_now + CAST_GAP_SECONDS
				return STEP_BLOCKED
			end
			-- Cooldown still hasn't started; allow retrying.
			pending_linkens_break_confirm = nil
		end

			-- Pick first available breaker we own/can cast; otherwise fall back to next.
			local mana = (NPC and NPC.GetMana and NPC.GetMana(hero)) or 0.0
			for _, name_id in ipairs(breaker_ids) do
				local breaker_spell = spell_map[name_id]
				if breaker_spell and breaker_spell.cast == "target" then
					local ability = get_spell(hero, breaker_spell)
					if ability then
						-- If not ready/castable, try the next breaker in the hierarchy.
						if (Ability and Ability.IsReady and Ability.IsReady(ability)) and (Ability and Ability.IsCastable and Ability.IsCastable(ability, mana)) then
							local ok, reason = cast_fast(ability, breaker_spell, combo_target)
							if ok then
								local t_now = now_time()
								if ui.debug_logs:Get() then
									log_debug("Cast Linken's breaker (waiting cooldown): " .. tostring(breaker_spell and breaker_spell.name))
								end
								-- Do not continue until cooldown starts.
								if not is_cooldown_started(ability) then
									local cp = get_cast_point_seconds(ability)
									local retry_delay = math.max(COOLDOWN_CONFIRM_GRACE, (cp + COOLDOWN_CONFIRM_EXTRA))
									pending_linkens_break_confirm = {
										name = breaker_spell and breaker_spell.name,
										next_try_t = t_now + retry_delay,
									}
									next_cast_time = t_now + CAST_GAP_SECONDS
									return STEP_BLOCKED
								end
								-- Cooldown is already visible.
								pending_linkens_break_confirm = nil
								last_linkens_break_t = t_now
								linkens_prefix_done = true
								combo_idx = 1
								return STEP_CAST
							end
							if reason == "out_of_range" then
								issue_move_to_target(hero, combo_target)
								return STEP_BLOCKED
							end
							-- Other failure: try next breaker.
						end
					end
				end
			end

			-- If Linken's is up but we have no usable breaker right now, do not proceed.
			return STEP_BLOCKED
		end
	end

	-- Optional: force Sheep Stick first (after Linken's is handled).
	if ui.force_sheep_first and ui.force_sheep_first.Get and ui.force_sheep_first:Get() and (not force_sheep_done) then
		local sheep_spell = spell_map["Sheep Stick"]
		local sheep_ability = sheep_spell and get_spell(hero, sheep_spell) or nil
		if not sheep_spell or not sheep_ability then
			-- If we don't have Sheep Stick, don't block the combo.
			force_sheep_done = true
		else
			local ok, reason = cast_fast(sheep_ability, sheep_spell, combo_target)
			if ok then
				force_sheep_done = true
				return STEP_CAST
			end
			if reason == "out_of_range" then
				issue_move_to_target(hero, combo_target)
				return STEP_BLOCKED
			end
			-- Keep trying until it casts; do not proceed to other steps.
			return STEP_BLOCKED
		end
	end

	-- Enforced control-chain prefix (always): Sheep -> Rod -> Ancient Seal -> EBlade.
	-- IMPORTANT: do not issue other control casts while we're waiting to confirm a cast via cooldown;
	-- repeatedly sending new orders during cast point can prevent cooldown from ever starting.
	if not pending_cooldown_confirm then
		local ctrl_r = run_control_chain_prefix(hero, combo_target, should_log)
		if ctrl_r == STEP_CAST or ctrl_r == STEP_BLOCKED then
			return ctrl_r
		end
	end

	local i = combo_idx
	local spell = combo_seq[i]
	trace_get_step(i, spell)
	local ability = get_spell(hero, spell)
	local resolved_name = nil
	if ability and Ability and Ability.GetName then
		local ok_n, nm = pcall(Ability.GetName, ability)
		if ok_n and type(nm) == "string" then resolved_name = nm end
	end
	if not ability then
		-- Missing items/spells are skipped.
		trace_step_skip(i, spell, "missing")
		if ui.debug_logs:Get() then
			local t = now_time()
			if last_fail_reason ~= "missing" or last_fail_step ~= i or (t - last_fail_log_t) >= FAIL_LOG_COOLDOWN then
				last_fail_reason = "missing"
				last_fail_step = i
				last_fail_log_t = t
				log_debug("Skip step " .. tostring(i) .. ": missing " .. tostring(spell.name))
			end
		end
		advance_idx()
		return STEP_SKIPPED
	end

	-- If we previously issued this step, wait for cooldown to actually start.
	-- Do this BEFORE logging an attempt, otherwise logs/attempt counters look like we're re-casting every frame.
	if pending_cooldown_confirm and pending_cooldown_confirm.idx == i and pending_cooldown_confirm.name == (spell and spell.name) then
		local t_now = now_time()
		local confirmed = is_cooldown_started(ability)
		-- For Rod/Gleipnir/Gungir: some builds don't reliably expose cooldown start.
		-- As a fallback, accept the cast once the root modifier is actually visible on the target.
		if (not confirmed) and spell and spell.name == "item_rod_of_atos" and combo_target and target_has_rod_root then
			if target_has_rod_root(combo_target) then
				confirmed = true
			end
		end
		if confirmed then
			pending_cooldown_confirm = nil
			if should_log then
				log_debug("[STEP] Cooldown confirmed step " .. tostring(i) .. ": " .. tostring(spell.name))
			end
			dbg_log_cast("SUCCESS", i, spell and spell.name, nil)
			trace_step_success(i, spell)

			-- Store Rod impact prediction for Mystic Flare targeting (independent of the wait slider).
			if spell and spell.name == "item_rod_of_atos" then
				local cast_t = t_now
				local hero_pos = Entity.GetAbsOrigin(hero)
				local target_pos = Entity.GetAbsOrigin(combo_target)
				local rod_speed = get_rod_projectile_speed(ability)
				local travel_time = compute_rod_travel_time(hero_pos, target_pos, rod_speed)
				local hit_t = cast_t + travel_time
				local move_dir = get_target_move_dir(combo_target)
				local move_speed = get_target_move_speed(combo_target)
				local impact_pos = compute_predicted_pos_at_time(target_pos, move_dir, move_speed, travel_time)
				rod_predict = {
					target = combo_target,
					cast_t = cast_t,
					hit_t = hit_t,
					impact_pos = impact_pos,
					move_dir = move_dir,
				}
			end

			-- If enabled: after casting Ethereal Blade, block further steps until its modifier is visible on the target.
			if ui.wait_eblade_modifier and ui.wait_eblade_modifier.Get and ui.wait_eblade_modifier:Get() then
				if spell and spell.name == "item_ethereal_blade" then
					eblade_modifier_waiting = true
					eblade_modifier_wait_cast_t = t_now
				end
			end

			advance_idx()
			if should_log then
				log_debug(string.format("[STEP] Exit: STEP_CAST (step %d done, now idx=%d)", i, combo_idx))
			end
			return STEP_CAST
		end
		if t_now < (pending_cooldown_confirm.next_try_t or t_now) then
			next_cast_time = t_now + CAST_GAP_SECONDS
			dbg_add_event("BLOCK", i, spell and spell.name, "wait_cooldown_start")
			trace_step_block(i, spell, "wait_cooldown_start")
			return STEP_BLOCKED
		end
		-- Cooldown still hasn't started; allow retrying the cast.
		pending_cooldown_confirm = nil
	end

	if should_log then
		if spell and spell.name == "item_rod_of_atos" and resolved_name and resolved_name ~= "item_rod_of_atos" then
			log_debug(string.format("[STEP] Attempting cast: step %d %s (resolved=%s)", i, tostring(spell.name), tostring(resolved_name)))
		else
			log_debug(string.format("[STEP] Attempting cast: step %d %s", i, tostring(spell.name)))
		end
	end
	trace_step_attempt(i, spell)
	dbg_log_cast("ATTEMPT", i, spell and spell.name, nil)

	-- Optional: wait until Rod is actually applied (modifier check) BEFORE casting Mystic Flare.
	-- This is the most reliable option vs moving targets: it guarantees the target is rooted when Flare starts.
	if ui.wait_rod_modifier and ui.wait_rod_modifier.Get and ui.wait_rod_modifier:Get() then
		if spell and spell.name == "skywrath_mage_mystic_flare" and rod_predict and rod_predict.target == combo_target then
			local rod_root_mod = get_rod_root_modifier_name(combo_target)
			if not rod_root_mod then
				local t_now = now_time()
				local hit_t = rod_predict.hit_t or t_now
				local dt_after_hit = t_now - hit_t
				local dt_to_hit = hit_t - t_now
				local dt_since_cast = t_now - (rod_predict.cast_t or t_now)

				-- Debug: log rod-root waiting details at a low rate (avoid spam).
				if ui.debug_logs:Get() then
					rod_wait_last_log_t = rod_wait_last_log_t or -1000.0
					rod_wait_last_dump_t = rod_wait_last_dump_t or -1000.0
					if (t_now - rod_wait_last_log_t) >= 0.15 then
						rod_wait_last_log_t = t_now
						log_debug(string.format("[ROD WAIT] rooted=false dt_to_hit=%.3f dt_after_hit=%.3f since_cast=%.3f", tonumber(dt_to_hit) or -999.0, tonumber(dt_after_hit) or -999.0, tonumber(dt_since_cast) or -999.0))
					end
					-- If we're past expected hit time and still not detecting a root modifier, dump current modifiers.
					if dt_after_hit > 0.10 and (t_now - rod_wait_last_dump_t) >= 0.35 then
						rod_wait_last_dump_t = t_now
						local names = get_target_modifier_names(combo_target, 18)
						if names and #names > 0 then
							log_debug("[ROD WAIT] target modifiers: " .. table.concat(names, " | "))
						else
							log_debug("[ROD WAIT] target modifiers: (none/unknown)")
						end
					end
				end

				-- If Rod should have already landed but we still can't see a root modifier, assume it was blocked/cleansed
				-- and retry the Rod step a couple times instead of stalling at Mystic Flare forever.
				if dt_after_hit > 0.35 then
					if rod_modifier_wait_retry_count < 2 and (t_now - rod_modifier_wait_last_retry_t) > 0.20 then
						rod_modifier_wait_retry_count = rod_modifier_wait_retry_count + 1
						rod_modifier_wait_last_retry_t = t_now
						rod_modifier_wait_giveup_logged = false

						local rod_step = nil
						for idx, s in ipairs(combo_seq) do
							if s and s.name == "item_rod_of_atos" then
								rod_step = idx
								break
							end
						end
						if rod_step and rod_step ~= combo_idx then
							rod_predict = nil
							combo_idx = rod_step
							next_cast_time = t_now + CAST_GAP_SECONDS
							if should_log then
								log_debug(string.format("[STEP] Rod root not detected (%.2fs after expected hit) -> retrying Rod (attempt %d)", dt_after_hit, rod_modifier_wait_retry_count))
							end
							return STEP_BLOCKED
						end
					end

					-- Give up waiting (rare edge cases) so the combo doesn't appear "stuck".
					if not rod_modifier_wait_giveup_logged then
						rod_modifier_wait_giveup_logged = true
						if ui.debug_logs:Get() then
							log_debug(string.format("[STEP] Rod root modifier not detected after expected hit (%.2fs). Proceeding without modifier gate.", dt_after_hit))
						end
					end
					rod_predict = nil
					-- Fall through; allow Mystic Flare to cast this tick.
				else
					-- Keep trying frequently; don't advance the combo until Rod lands.
					next_cast_time = t_now + CAST_GAP_SECONDS
					if should_log then
						log_debug("[STEP] Waiting Rod root modifier before Mystic Flare")
					end
					dbg_add_event("BLOCK", i, spell and spell.name, "wait_rod_root")
					trace_step_block(i, spell, "wait_rod_root")
					return STEP_BLOCKED
				end
			else
				-- Rod root is present. Also require the target to have settled (not moving) before casting Flare.
				-- This ensures we take the latest rooted position and cast with the configured offset.
				local t_now = now_time()
				local m = target_motion and target_motion[combo_target] or nil
				local age = (m and m.t) and (t_now - (m.t or t_now)) or 999.0
				local speed = get_target_move_speed(combo_target)
				local MOVING_EPS = 20.0
				local MAX_AGE = 0.20
				local hit_t = rod_predict and rod_predict.hit_t or t_now
				local dt_after_hit = t_now - (hit_t or t_now)
				-- If motion sampling is stale, wait briefly for a fresh sample.
				-- If we have been rooted for a while, don't over-block due to cache oddities.
				if ui.debug_logs:Get() then
					rod_wait_last_root_log_t = rod_wait_last_root_log_t or -1000.0
					if (t_now - rod_wait_last_root_log_t) >= 0.15 then
						rod_wait_last_root_log_t = t_now
						log_debug(string.format("[ROD WAIT] rooted=true mod=%s dt_after_hit=%.3f speed=%.1f age=%.3f", tostring(rod_root_mod), tonumber(dt_after_hit) or -999.0, tonumber(speed) or -1.0, tonumber(age) or -1.0))
					end
				end
				if dt_after_hit <= 0.60 then
					if age > MAX_AGE or (speed and speed > MOVING_EPS) then
						next_cast_time = t_now + CAST_GAP_SECONDS
						if should_log then
							log_debug(string.format("[STEP] Waiting target settle before Mystic Flare (speed=%.1f age=%.3f)", tonumber(speed) or -1.0, tonumber(age) or -1.0))
						end
						dbg_add_event("BLOCK", i, spell and spell.name, "wait_target_settle")
						trace_step_block(i, spell, "wait_target_settle")
						return STEP_BLOCKED
					end
				end
			end
		end
	end

	-- Optional reliability gate (moving targets): when modifier-wait is enabled,
	-- delay Mystic Flare to line up with Rod landing.
	local use_rod_timing_gate = false
	if ui.wait_rod_modifier and ui.wait_rod_modifier.Get and ui.wait_rod_modifier:Get() then
		use_rod_timing_gate = true
	end
	if use_rod_timing_gate and spell and spell.name == "skywrath_mage_mystic_flare" and rod_predict and rod_predict.target == combo_target and rod_predict.hit_t then
		local t_now = now_time()
		local dt_to_hit = (rod_predict.hit_t or t_now) - t_now
		local move_speed = get_target_move_speed(combo_target)
		-- Only gate when the target is actually moving and Rod is expected to hit soon.
		if move_speed and move_speed > 30.0 and dt_to_hit > 0.0 and dt_to_hit <= 1.50 then
			local cast_point = 0.10
			if Ability and Ability.GetCastPoint then
				local ok_cp, cp = pcall(Ability.GetCastPoint, ability)
				if ok_cp and type(cp) == "number" then cast_point = cp end
			end
			-- Cast after Rod hit so the target is already rooted when flare starts ticking.
			local POST_HIT_DELAY = 0.03
			local desired_cast_t = (rod_predict.hit_t or t_now) + POST_HIT_DELAY - cast_point
			if t_now < desired_cast_t then
				next_cast_time = desired_cast_t
				return STEP_BLOCKED
			end
		end
	end

	local ok, reason = cast_fast(ability, spell, combo_target)
	if ok then
		-- If cooldown didn't start yet, keep this step active and retry shortly.
		if not is_cooldown_started(ability) then
			local t_now = now_time()
			local cp = get_cast_point_seconds(ability)
			local retry_delay = math.max(COOLDOWN_CONFIRM_GRACE, (cp + COOLDOWN_CONFIRM_EXTRA))
			-- For Rod/Gleipnir/Gungir, allow time for the projectile to land and the root modifier to appear.
			if spell and spell.name == "item_rod_of_atos" and combo_target and Entity and Entity.GetAbsOrigin then
				local hero_pos = Entity.GetAbsOrigin(hero)
				local target_pos = Entity.GetAbsOrigin(combo_target)
				if hero_pos and target_pos then
					local speed = get_rod_projectile_speed(ability)
					local travel_time = compute_rod_travel_time(hero_pos, target_pos, speed)
					-- Small buffer after hit for modifier to register.
					retry_delay = math.max(retry_delay, (travel_time or 0.0) + 0.15)
				end
			end
			pending_cooldown_confirm = {
				idx = i,
				name = spell and spell.name,
				next_try_t = t_now + retry_delay,
			}
			next_cast_time = t_now + CAST_GAP_SECONDS
			dbg_add_event("BLOCK", i, spell and spell.name, "wait_cooldown_start")
			trace_step_block(i, spell, "wait_cooldown_start")
			return STEP_BLOCKED
		end

		-- Cooldown is already visible; treat as a confirmed cast.
		if should_log then
			log_debug("[STEP] Cast SUCCESS step " .. tostring(i) .. ": " .. tostring(spell.name))
		end
		dbg_log_cast("SUCCESS", i, spell and spell.name, nil)
		trace_step_success(i, spell)

		-- Store Rod impact prediction for Mystic Flare targeting (independent of the wait slider).
		if spell and spell.name == "item_rod_of_atos" then
			local cast_t = now_time()
			local hero_pos = Entity.GetAbsOrigin(hero)
			local target_pos = Entity.GetAbsOrigin(combo_target)
			local rod_speed = get_rod_projectile_speed(ability)
			local travel_time = compute_rod_travel_time(hero_pos, target_pos, rod_speed)
			local hit_t = cast_t + travel_time
			local move_dir = get_target_move_dir(combo_target)
			local move_speed = get_target_move_speed(combo_target)
			local impact_pos = compute_predicted_pos_at_time(target_pos, move_dir, move_speed, travel_time)
			rod_predict = {
				target = combo_target,
				cast_t = cast_t,
				hit_t = hit_t,
				impact_pos = impact_pos,
				move_dir = move_dir,
			}
		end

		-- If enabled: after casting Ethereal Blade, block further steps until its modifier is visible on the target.
		if ui.wait_eblade_modifier and ui.wait_eblade_modifier.Get and ui.wait_eblade_modifier:Get() then
			if spell and spell.name == "item_ethereal_blade" then
				eblade_modifier_waiting = true
				eblade_modifier_wait_cast_t = now_time()
			end
		end

		advance_idx()
		if should_log then
			log_debug(string.format("[STEP] Exit: STEP_CAST (step %d done, now idx=%d)", i, combo_idx))
		end
		return STEP_CAST
	end
	if should_log then
		log_debug(string.format("[STEP] Cast FAILED step %d %s: %s", i, tostring(spell.name), tostring(reason)))
	end
	dbg_log_cast("FAILED", i, spell and spell.name, reason)

	-- Cooldown = skip and continue sequentially.
	if reason == "not_ready" then
		trace_step_skip(i, spell, "not_ready")
		if ui.debug_logs:Get() and should_log then
			local t = now_time()
			if reason ~= last_fail_reason or last_fail_step ~= i or (t - last_fail_log_t) >= FAIL_LOG_COOLDOWN then
				last_fail_reason = reason
				last_fail_step = i
				last_fail_log_t = t
				log_debug("Skip step " .. tostring(i) .. ": " .. tostring(spell.name) .. " => not_ready")
			end
		end
		advance_idx()
		dbg_add_event("SKIP", i, spell and spell.name, "not_ready")
		if should_log then
			log_debug(string.format("[STEP] Exit: STEP_SKIPPED (not_ready, now idx=%d)", combo_idx))
		end
		return STEP_SKIPPED
	end

	-- Out of range = move and block.
	if reason == "out_of_range" then
		trace_step_fail(i, spell, "out_of_range")
		if should_log then
			log_debug(string.format("[STEP] Exit: STEP_BLOCKED (out_of_range step %d)", i))
		end
		issue_move_to_target(hero, combo_target)
		dbg_add_event("BLOCK", i, spell and spell.name, "out_of_range")
		return STEP_BLOCKED
	end

	-- Other failures (mana/silence/etc) block.
	trace_step_fail(i, spell, reason or "fail")
	if ui.debug_logs:Get() and should_log then
		local t = now_time()
		if reason ~= last_fail_reason or last_fail_step ~= i or (t - last_fail_log_t) >= FAIL_LOG_COOLDOWN then
			last_fail_reason = reason
			last_fail_step = i
			last_fail_log_t = t
			log_debug("Fail step " .. tostring(i) .. ": " .. tostring(spell.name) .. " => " .. tostring(reason))
		end
	end
	if should_log then
		log_debug(string.format("[STEP] Exit: STEP_BLOCKED (%s step %d)", tostring(reason), i))
	end
	return STEP_BLOCKED
end

function combo.OnUpdate()
	if not ui.enabled:Get() then return end

	local t = now_time()
	local cpu_start = nil
	local find_cpu_start = nil
	local step_cpu_start = nil
	if ui.debug_logs:Get() then
		cpu_start = os.clock()
	end

	update_step_icons()
	local key = ui.combo_key:Get()
	if key == Enum.ButtonCode.BUTTON_CODE_INVALID then return end

	local down = Input.IsKeyDown(key)
	if not down then
		if combo_running then
			stop_hero_orders()
			reset_combo()
		end
		if was_key_down then log_debug("Key released") end
		was_key_down = false
		return
	end
	if not was_key_down then
		log_debug("Key down")
	end

	local hero = Heroes.GetLocal()
	if not hero then return end

	-- If we don't have a valid target, keep moving to cursor (ground click) until one is found.
	if (not combo_running) or (not combo_target) or (not Entity.IsAlive(combo_target)) then
		if combo_running and ui.debug_logs:Get() and (not combo_end_logged) then
			local alive = (combo_target ~= nil) and Entity and Entity.IsAlive and Entity.IsAlive(combo_target) or false
			log_debug(string.format("[COMBO END] no_target_or_dead alive=%s", tostring(alive)))
			combo_end_logged = true
		end
		if combo_running then
			reset_combo()
		end
		local target = nil
		if (t - last_target_search_t) >= TARGET_SEARCH_COOLDOWN then
			last_target_search_t = t
			if ui.debug_logs:Get() then find_cpu_start = os.clock() end
			target = find_target_near_cursor()
			if ui.debug_logs:Get() and find_cpu_start then
				perf_find_total = perf_find_total + (os.clock() - find_cpu_start)
			end
		end
		if target then
			-- Do not start combos on forbidden/immune targets.
			if target_is_forbidden and target_is_forbidden(target) then
				if ui.debug_logs:Get() then
					log_debug("Found target but skipped (forbidden/immune)")
				end
			else
				start_combo(target)
			end
		else
			issue_move_to_ground(hero, Input.GetWorldCursorPos())
			if ui.debug_logs:Get() and cpu_start then
				perf_updates = perf_updates + 1
				local cpu_dt = os.clock() - cpu_start
				perf_cpu_total = perf_cpu_total + cpu_dt
				if cpu_dt > perf_cpu_max then perf_cpu_max = cpu_dt end
				if (t - perf_last_report_t) >= 1.0 then
					local span = math.max(0.001, (t - perf_last_report_t))
					local ups = perf_updates / span
					local avg_ms = (perf_cpu_total / math.max(1, perf_updates)) * 1000.0
					local max_ms = perf_cpu_max * 1000.0
					local find_ms = (perf_find_total / math.max(1, perf_updates)) * 1000.0
					local step_ms = (perf_step_total / math.max(1, perf_updates)) * 1000.0
					log_debug(string.format("Perf: upd/s=%.1f cpu_avg=%.2fms cpu_max=%.2fms find_avg=%.2fms step_avg=%.2fms", ups, avg_ms, max_ms, find_ms, step_ms))
					perf_last_report_t = t
					perf_updates = 0
					perf_cpu_total = 0.0
					perf_cpu_max = 0.0
					perf_find_total = 0.0
					perf_step_total = 0.0
				end
			end
			was_key_down = true
			return
		end
	end

	-- Track target movement direction (used for Aghanim's Mystic Flare offset placement).
	if combo_target and Entity.IsAlive(combo_target) then
		update_target_motion(combo_target, t)
	end

	-- Enforce 0.015s between actual casts; fast-skip missing items/spells.
	local max_iters = 12
	if combo_seq and #combo_seq > 0 then
		max_iters = math.min(32, #combo_seq + 4)
	end
	
	local should_log_loop = ui.debug_logs:Get() and not combo_cycle_logged
	
	if should_log_loop then
		log_debug(string.format("[LOOP] Enter step loop: t=%.3f next_cast_time=%.3f idx=%d", t, next_cast_time, combo_idx))
	end
	local loop_iter = 0
	for _ = 1, max_iters do
		loop_iter = loop_iter + 1
		if not combo_running then
			if should_log_loop then
				log_debug("[LOOP] Break: combo not running")
			end
			break
		end
		if t < next_cast_time then
			if should_log_loop then
				log_debug(string.format("[LOOP] Break: cast gap block (t=%.3f < next=%.3f, delta=%.3f)", t, next_cast_time, next_cast_time - t))
			end
			break
		end
		if should_log_loop then
			log_debug(string.format("[LOOP] Iter %d: calling step_combo idx=%d", loop_iter, combo_idx))
		end
		if ui.debug_logs:Get() then step_cpu_start = os.clock() end
		local r = step_combo()
		if ui.debug_logs:Get() and step_cpu_start then
			perf_step_total = perf_step_total + (os.clock() - step_cpu_start)
		end
		if should_log_loop then
			log_debug(string.format("[LOOP] Iter %d: step_combo returned %d", loop_iter, r))
		end
		if r == STEP_CAST then
			if next_cast_time_override and next_cast_time_override > (t + CAST_GAP_SECONDS) then
				next_cast_time = next_cast_time_override
			else
				next_cast_time = t + CAST_GAP_SECONDS
			end
			next_cast_time_override = nil
			if should_log_loop then
				log_debug(string.format("[LOOP] STEP_CAST: set next_cast_time=%.3f (t + %.3f)", next_cast_time, CAST_GAP_SECONDS))
			end
			break
		end
		if r == STEP_SKIPPED then
			if should_log_loop then
				log_debug("[LOOP] STEP_SKIPPED: continue")
			end
			-- keep skipping in the same frame
		else
			if should_log_loop then
				log_debug(string.format("[LOOP] Break: return code %d", r))
			end
			break
		end
	end
	if should_log_loop then
		log_debug(string.format("[LOOP] Exit step loop after %d iterations", loop_iter))
	end

	if ui.debug_logs:Get() and cpu_start then
		perf_updates = perf_updates + 1
		local cpu_dt = os.clock() - cpu_start
		perf_cpu_total = perf_cpu_total + cpu_dt
		if cpu_dt > perf_cpu_max then perf_cpu_max = cpu_dt end
		if (t - perf_last_report_t) >= 1.0 then
			local span = math.max(0.001, (t - perf_last_report_t))
			local ups = perf_updates / span
			local avg_ms = (perf_cpu_total / math.max(1, perf_updates)) * 1000.0
			local max_ms = perf_cpu_max * 1000.0
			local find_ms = (perf_find_total / math.max(1, perf_updates)) * 1000.0
			local step_ms = (perf_step_total / math.max(1, perf_updates)) * 1000.0
			log_debug(string.format("Perf: upd/s=%.1f cpu_avg=%.2fms cpu_max=%.2fms find_avg=%.2fms step_avg=%.2fms", ups, avg_ms, max_ms, find_ms, step_ms))
			perf_last_report_t = t
			perf_updates = 0
			perf_cpu_total = 0.0
			perf_cpu_max = 0.0
			perf_find_total = 0.0
			perf_step_total = 0.0
		end
	end

	was_key_down = true
end

function combo.OnDraw()
	if not ui.enabled:Get() then return end
	local key = ui.combo_key:Get()
	if key == Enum.ButtonCode.BUTTON_CODE_INVALID then return end
	if not Input.IsKeyDown(key) then return end

	local hero = Heroes.GetLocal()
	if not hero then return end
	if combo_target and Entity.IsAlive(combo_target) then
		draw_lock_line(hero, combo_target)
	end
end

return combo