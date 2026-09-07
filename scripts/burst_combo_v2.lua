---@diagnostic disable: undefined-global

-- ============================================================================
-- Burst Combo v2 — Hold-key combo script using API v2.0
-- ============================================================================

local burst_combo_v2 = {}

-- ── Constants ──────────────────────────────────────────────────────────────
local CAST_GAP = 0.015
local MAX_STEPS = 8
local COOLDOWN_GRACE = 0.08
local COOLDOWN_EXTRA = 0.15
local TARGET_SEARCH_INTERVAL = 0.03
local MOVE_ORDER_INTERVAL = 0.20

-- ── Spell Definitions ──────────────────────────────────────────────────────
local SPELLS = {
	["Arcane Bolt"]      = { internal = "skywrath_mage_arcane_bolt",     kind = "ability",  cast = "target"   },
	["Concussive Shot"]  = { internal = "skywrath_mage_concussive_shot",  kind = "ability",  cast = "no_target" },
	["Ancient Seal"]     = { internal = "skywrath_mage_ancient_seal",     kind = "ability",  cast = "target"   },
	["Mystic Flare"]     = { internal = "skywrath_mage_mystic_flare",     kind = "ability",  cast = "position" },
	["Sheep Stick"]      = { internal = "item_sheepstick",                kind = "item",     cast = "target"   },
	["Rod of Atos"]      = { internal = "item_rod_of_atos",               kind = "item",     cast = "target",   aliases = {"item_gleipnir", "item_gungir"} },
	["Ethereal Blade"]   = { internal = "item_ethereal_blade",            kind = "item",     cast = "target"   },
	["Bloodthorn"]       = { internal = "item_bloodthorn",                kind = "item",     cast = "target"   },
	["Nullifier"]        = { internal = "item_nullifier",                 kind = "item",     cast = "target"   },
	["Dagon"]            = { internal = "item_dagon",                     kind = "item",     cast = "target",   dagon = true },
	["Eul's / Wind Waker"] = { internal = "item_cyclone",                 kind = "item",     cast = "target",   aliases = {"item_wind_waker"} },
}

local DEFAULT_ORDER = { "Arcane Bolt", "Concussive Shot", "Sheep Stick", "Ancient Seal", "Rod of Atos", "Ethereal Blade", "Dagon", "Mystic Flare" }

local ALL_ORDER_ITEMS = { "Concussive Shot", "Sheep Stick", "Rod of Atos", "Ancient Seal", "Ethereal Blade", "Bloodthorn", "Nullifier", "Arcane Bolt", "Dagon", "Mystic Flare" }

local LINKENS_BREAKERS = { "Sheep Stick", "Eul's / Wind Waker", "Rod of Atos", "Ancient Seal", "Ethereal Blade", "Bloodthorn", "Nullifier", "Arcane Bolt", "Dagon" }

-- ── Menu ───────────────────────────────────────────────────────────────────
local CONFIG_KEY = "burst_combo_v2"
local SCRIPT_TAG = "[Burst Combo v2]"

local menu_tab = Menu.Create("General", "My Scripts", "Burst Combo v2", "Combo")
local main_group = menu_tab:Create("Settings")
local order_group = menu_tab:Create("Combo Order")
local linkens_group = menu_tab:Create("Linken's Breaker")

local ui = {}
ui.enabled      = main_group:Switch("Enable Combo", true)
ui.debug        = main_group:Switch("Debug Logs", false)
ui.combo_key    = main_group:Bind("Combo Key", Enum.ButtonCode.KEY_SPACE)
ui.search_range = main_group:Slider("Search Range", 100, 2000, 300)
ui.wait_rod     = main_group:Switch("Wait Rod Root", false)
ui.wait_eblade  = main_group:Switch("Wait EBlade Modifier", false)
ui.sheep_first  = main_group:Switch("Force Sheep First", false)

Log.Write(SCRIPT_TAG .. " Loaded")

-- ── Helpers ────────────────────────────────────────────────────────────────
local function now()
	return GameRules.GetGameTime and GameRules.GetGameTime() or os.clock()
end

local function log(fmt, ...)
	if not ui.debug:Get() then return end
	local msg = string.format(fmt, ...)
	if Log and Log.Write then Log.Write(SCRIPT_TAG .. " " .. msg) else print(SCRIPT_TAG .. " " .. msg) end
end

local function dist2d(a, b)
	local dx = (a.x or 0) - (b.x or 0)
	local dy = (a.y or 0) - (b.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

-- ── MultiSelect Builders (API v2.0: keyed tables) ──────────────────────────
local function spell_icon_path(name_id)
	local s = SPELLS[name_id]
	if not s then return "" end
	local short = s.internal:gsub("^item_", "")
	if s.kind == "ability" then
		return "panorama/images/spellicons/" .. s.internal .. "_png.vtex_c"
	end
	return "panorama/images/items/" .. short .. "_png.vtex_c"
end

local function build_multiselect(order_list, enabled_set, fallback)
	local items, seen = {}, {}
	local function push(id)
		if seen[id] then return end
		seen[id] = true
		items[#items + 1] = { nameId = id, imagePath = spell_icon_path(id), isEnabled = enabled_set[id] == true }
	end
	for _, id in ipairs(order_list or {}) do push(id) end
	for _, id in ipairs(fallback) do push(id) end
	return items
end

-- ── Read enabled names from MultiSelect (API v2.0: no :List(), use static list) ──
local function read_multiselect_enabled(widget, id_list)
	local enabled = {}
	if not widget or not widget.Get then return enabled end
	for _, id in ipairs(id_list) do
		local ok, on = pcall(widget.Get, widget, id)
		if ok and on then enabled[#enabled + 1] = id end
	end
	return enabled
end

-- ── Combo Order UI ─────────────────────────────────────────────────────────
local combo_order_ids = nil
do
	local items = build_multiselect(DEFAULT_ORDER, {}, ALL_ORDER_ITEMS)
	local ms = order_group:MultiSelect("Drag Order", items, true)
	if ms and ms.DragAllowed then pcall(ms.DragAllowed, ms, true) end
	combo_order_ids = read_multiselect_enabled(ms, ALL_ORDER_ITEMS)
	if #combo_order_ids == 0 then combo_order_ids = DEFAULT_ORDER end
end

-- ── Linken's Breaker UI ────────────────────────────────────────────────────
local linkens_break_ids = nil
do
	local items = build_multiselect(LINKENS_BREAKERS, {}, LINKENS_BREAKERS)
	local ms = linkens_group:MultiSelect("Breaker Priority", items, true)
	if ms and ms.DragAllowed then pcall(ms.DragAllowed, ms, true) end
	linkens_break_ids = read_multiselect_enabled(ms, LINKENS_BREAKERS)
	if #linkens_break_ids == 0 then linkens_break_ids = LINKENS_BREAKERS end
end

-- ── Spell Resolution ───────────────────────────────────────────────────────
local function resolve_spell(hero, spell_def)
	if spell_def.kind == "ability" then
		return NPC.GetAbility(hero, spell_def.internal)
	end
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(hero, i)
		if item then
			local nm = Ability.GetName(item)
			if nm == spell_def.internal then return item end
			if spell_def.aliases then
				for _, alias in ipairs(spell_def.aliases) do
					if nm == alias then return item end
				end
			end
			if spell_def.dagon and nm and nm:find("^item_dagon") then return item end
		end
	end
	return nil
end

-- ── API v2.0 Cast Helpers ──────────────────────────────────────────────────
local function get_cast_range(hero, ability)
	local r = Ability.GetCastRange and Ability.GetCastRange(ability) or 0
	if r <= 0 and Ability.GetSpecialValueFor then
		local ok, v = pcall(Ability.GetSpecialValueFor, ability, "cast_range", -1)
		if ok and type(v) == "number" and v > 0 then r = v
		else
			ok, v = pcall(Ability.GetSpecialValueFor, ability, "range", -1)
			if ok and type(v) == "number" and v > 0 then r = v end
		end
	end
	return r + (NPC.GetCastRangeBonus and NPC.GetCastRangeBonus(hero) or 0)
end

local function get_cast_point(ability)
	local cp = Ability.GetCastPoint and pcall(Ability.GetCastPoint, ability) and select(2, pcall(Ability.GetCastPoint, ability)) or 0.10
	if type(cp) ~= "number" then cp = 0.10 end
	return math.max(0.05, math.min(0.60, cp))
end

local function cooldown_left(ability)
	return Ability.GetCooldown and pcall(Ability.GetCooldown, ability) and select(2, pcall(Ability.GetCooldown, ability)) or nil
end

local function cooldown_started(ability)
	if not Ability.IsReady(ability) then return true end
	local cd = cooldown_left(ability)
	return cd and cd > 0
end

-- ── API v2.0 Target Search ─────────────────────────────────────────────────
local function find_target_near_cursor(hero)
	local cursor = Input.GetWorldCursorPos()
	local team = Entity.GetTeamNum(hero)
	local range = ui.search_range:Get()
	local enemies = Heroes.InRadius(cursor, range, team, Enum.TeamType.TEAM_ENEMY, true, true)
	if not enemies or #enemies == 0 then return nil end

	local best, best_d = nil, range
	for _, e in ipairs(enemies) do
		if e and e ~= hero and Entity.IsAlive(e) and not Entity.IsInvulnerable(e) then
			if not (NPC.IsDebuffImmune and NPC.IsDebuffImmune(e)) then
				local d = cursor:Distance(Entity.GetAbsOrigin(e))
				if d < best_d then best, best_d = e, d end
			end
		end
	end
	return best
end

-- ── API v2.0 Drawing (Render v2: Vec2-based) ───────────────────────────────
local LOCK_COLOR = Color(0, 255, 120, 220)
local function draw_line(hero, target)
	if not hero or not target then return end
	local hp = Entity.GetAbsOrigin(hero)
	local tp = Entity.GetAbsOrigin(target)
	hp = Vector(hp.x, hp.y, (hp.z or 0) + 80)
	tp = Vector(tp.x, tp.y, (tp.z or 0) + 80)
	local a, a_vis = Render.WorldToScreen(hp) -- Vec2, bool
	local b, b_vis = Render.WorldToScreen(tp)
	if a_vis and b_vis then
		Render.Line(a, b, LOCK_COLOR, 2.0) -- Vec2, Vec2, Color, thickness
	end
end

-- ── Cast Logic ─────────────────────────────────────────────────────────────
local function do_cast(hero, ability, spell_def, target)
	if not ability or not Ability.IsReady(ability) then return false, "not_ready" end
	local mana = NPC.GetMana(hero) or 0
	if not Ability.IsCastable(ability, mana) then return false, "not_castable" end

	local range = get_cast_range(hero, ability)
	if spell_def.internal == "item_rod_of_atos" and range <= 0 then range = 1100 end

	if spell_def.cast == "no_target" then
		Ability.CastNoTarget(ability, false, false, false)
		return true, "cast"
	end
	if not target or not Entity.IsAlive(target) then return false, "no_target" end

	if spell_def.cast == "position" then
		local pos = Entity.GetAbsOrigin(target)
		Ability.CastPosition(ability, pos, false, false, false)
		return true, "cast"
	end

	if range > 0 and not NPC.IsEntityInRange(hero, target, range) then return false, "out_of_range" end
	Ability.CastTarget(ability, target, false, false, false)
	return true, "cast"
end

-- ── Linken's Check ─────────────────────────────────────────────────────────
local function has_linkens(target)
	if not target or not NPC then return false end
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(target, i)
		if item then
			local ok, nm = pcall(Ability.GetName, item)
			if ok and nm == "item_sphere" and Ability.IsReady(item) then return true end
		end
	end
	return NPC.HasModifier and (NPC.HasModifier(target, "modifier_item_sphere_target") or NPC.HasModifier(target, "modifier_item_sphere_target_buff"))
end

-- ── Combo State Machine ────────────────────────────────────────────────────
local combo_running, combo_target, combo_idx = false, nil, 1
local next_cast_t, was_key_down = 0, false
local last_search_t, last_move_t = -1000, -1000
local pending_cooldown = nil  -- {idx, name, next_try_t}
local linkens_broken = false

local function reset_combo()
	combo_running, combo_target, combo_idx = false, nil, 1
	next_cast_t, pending_cooldown, linkens_broken = 0, nil, false
end

local function move_to(hero, target)
	local t = now()
	if t - last_move_t < MOVE_ORDER_INTERVAL then return end
	last_move_t = t
	NPC.MoveTo(hero, Entity.GetAbsOrigin(target), false, false, false, true, "burst_v2_move", true)
end

-- ── Main Step ──────────────────────────────────────────────────────────────
local function step_combo()
	local hero = Heroes.GetLocal()
	if not hero or not combo_running or not combo_target or not Entity.IsAlive(combo_target) then
		reset_combo(); return
	end

	-- Build sequence from enabled order
	local seq = {}
	for _, name_id in ipairs(combo_order_ids) do
		local s = SPELLS[name_id]
		if s then seq[#seq + 1] = s end
		if #seq >= MAX_STEPS then break end
	end
	if #seq == 0 then return end

	if combo_idx < 1 or combo_idx > #seq then combo_idx = 1 end

	-- Linken's breaker
	if has_linkens(combo_target) and not linkens_broken then
		for _, name_id in ipairs(linkens_break_ids) do
			local sd = SPELLS[name_id]
			if sd and sd.cast == "target" then
				local ab = resolve_spell(hero, sd)
				if ab and Ability.IsReady(ab) then
					local ok, reason = do_cast(hero, ab, sd, combo_target)
					if ok then
						if not cooldown_started(ab) then
							pending_cooldown = { idx = 0, name = sd.internal, next_try_t = now() + get_cast_point(ab) + COOLDOWN_EXTRA }
						else
							linkens_broken = true
						end
						return
					end
					if reason == "out_of_range" then move_to(hero, combo_target); return end
				end
			end
		end
		return
	end

	-- Pending cooldown check
	if pending_cooldown then
		local pc = pending_cooldown
		if pc.idx == combo_idx then
			local sd = seq[combo_idx]
			local ab = sd and resolve_spell(hero, sd)
			if ab and cooldown_started(ab) then
				pending_cooldown = nil
				combo_idx = combo_idx + 1
				if combo_idx > #seq then combo_idx = 1 end
				return
			end
			if now() < (pc.next_try_t or 0) then return end
			pending_cooldown = nil
		else
			pending_cooldown = nil
		end
	end

	local t = now()
	if t < next_cast_t then return end

	local spell = seq[combo_idx]
	if not spell then combo_idx = combo_idx + 1; return end

	local ability = resolve_spell(hero, spell)
	if not ability then
		combo_idx = combo_idx + 1
		if combo_idx > #seq then combo_idx = 1 end
		return
	end

	local ok, reason = do_cast(hero, ability, spell, combo_target)
	if ok then
		if not cooldown_started(ability) then
			pending_cooldown = {
				idx = combo_idx,
				name = spell.internal,
				next_try_t = t + math.max(COOLDOWN_GRACE, get_cast_point(ability) + COOLDOWN_EXTRA),
			}
		else
			combo_idx = combo_idx + 1
			if combo_idx > #seq then combo_idx = 1 end
		end
		next_cast_t = t + CAST_GAP
	elseif reason == "out_of_range" then
		move_to(hero, combo_target)
	elseif reason == "not_ready" then
		combo_idx = combo_idx + 1
		if combo_idx > #seq then combo_idx = 1 end
	end
end

-- ── Callbacks ──────────────────────────────────────────────────────────────
function burst_combo_v2.OnUpdate()
	if not ui.enabled:Get() then return end

	local key = ui.combo_key:Get()
	if key == Enum.ButtonCode.BUTTON_CODE_INVALID then return end

	if not Input.IsKeyDown(key) then
		if was_key_down and combo_running then reset_combo() end
		was_key_down = false
		return
	end
	was_key_down = true

	local hero = Heroes.GetLocal()
	if not hero then return end

	local t = now()

	-- Find target
	if not combo_running or not combo_target or not Entity.IsAlive(combo_target) then
		if t - last_search_t >= TARGET_SEARCH_INTERVAL then
			last_search_t = t
			local target = find_target_near_cursor(hero)
			if target then
				combo_running = true
				combo_target = target
				combo_idx = 1
				next_cast_t = 0
				pending_cooldown = nil
				linkens_broken = false
				log("Combo started on target")
			end
		end
	end

	if combo_running then step_combo() end
end

function burst_combo_v2.OnDraw()
	if not ui.enabled:Get() then return end
	local key = ui.combo_key:Get()
	if key == Enum.ButtonCode.BUTTON_CODE_INVALID then return end
	if not Input.IsKeyDown(key) then return end
	local hero = Heroes.GetLocal()
	if hero and combo_target and Entity.IsAlive(combo_target) then
		draw_line(hero, combo_target)
	end
end

return burst_combo_v2
