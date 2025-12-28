---@diagnostic disable: undefined-global

local combo = {}

-- Minimal, maximum-speed Skywrath Mage hold-key combo.
-- No logging, no confirmation waits, no retries, no persistence, no drawing.

local CAST_GAP_SECONDS = 0.05

local function now_time()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
end

local DEFAULT_ORDER = {
	"Concussive Shot",
	"Sheep Stick",
	"Rod of Atos",
	"Ancient Seal",
	"Ethereal Blade",
	"Arcane Bolt",
	"Dagon",
	"Mystic Flare",
}

local ORDER_ITEMS = {
	"Concussive Shot",
	"Sheep Stick",
	"Rod of Atos",
	"Ancient Seal",
	"Ethereal Blade",
	"Arcane Bolt",
	"Dagon",
	"Mystic Flare",
}

local LINKENS_BREAKER_ITEMS = {
	"None",
	"Concussive Shot",
	"Sheep Stick",
	"Rod of Atos",
	"Ancient Seal",
	"Ethereal Blade",
	"Arcane Bolt",
	"Dagon",
	"Mystic Flare",
}

local available_spells = {
	{nameId = "Concussive Shot", imagePath = "images/MenuIcons/target.png", isEnabled = true},
	{nameId = "Sheep Stick", imagePath = "images/MenuIcons/staff_stick.png", isEnabled = true},
	{nameId = "Rod of Atos", imagePath = "images/MenuIcons/Dota/gungir.png", isEnabled = true},
	{nameId = "Ancient Seal", imagePath = "images/MenuIcons/silent.png", isEnabled = true},
	{nameId = "Ethereal Blade", imagePath = "images/MenuIcons/Dota/ethereal_blade.png", isEnabled = true},
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
	["Dagon"] = {name = "item_dagon", kind = "item", cast = "target"}, -- matches dagon_2..5 too
	["Mystic Flare"] = {name = "skywrath_mage_mystic_flare", kind = "ability", cast = "position"},
}

local menu_tab = Menu.Create("General", "Scripts", "Skywrath Combo", "Combo")
local main_group = menu_tab:Create("Settings")
local order_group = menu_tab:Create("Combo Order")

local ui = {}
ui.enabled = main_group:Switch("Enable Combo", true)
ui.debug_logs = main_group:Switch("Debug Logs", false)
ui.combo_key = main_group:Bind("Combo Key", Enum.ButtonCode.KEY_SPACE)
ui.search_radius = main_group:Input("Target Search Radius", "300")

local SCRIPT_TAG = "[Skywrath Combo]"
local function log_debug(msg)
	if not ui.debug_logs:Get() then return end
	if Log and Log.Write then
		Log.Write(SCRIPT_TAG .. " " .. msg)
	else
		print(SCRIPT_TAG .. " " .. msg)
	end
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

local flare_minus_labels, flare_minus_values = {}, {}
for i = 0, 200 do
	flare_minus_values[#flare_minus_values + 1] = i
	flare_minus_labels[#flare_minus_labels + 1] = tostring(i)
end
ui.flare_offset_minus = main_group:Combo("Mystic Flare Offset Minus", flare_minus_labels, 10)

ui.linkens_breaker = main_group:Combo("Linken's Breaker", LINKENS_BREAKER_ITEMS, 0)
if ui.linkens_breaker and ui.linkens_breaker.Image then
	pcall(ui.linkens_breaker.Image, ui.linkens_breaker, ICON_BY_NAME["None"] or "")
end

-- Fallback ordering UI: per-step dropdowns (always renders on all builds).
ui.order_steps = {}
for i = 1, #ORDER_ITEMS do
	ui.order_steps[i] = order_group:Combo("Step " .. tostring(i), ORDER_ITEMS, i - 1)
	if ui.order_steps[i] and ui.order_steps[i].Image then
		pcall(ui.order_steps[i].Image, ui.order_steps[i], ICON_BY_NAME[ORDER_ITEMS[i]] or "")
	end
end

local last_icon_update_t = 0.0
local function update_step_icons()
	local t = now_time()
	if (t - last_icon_update_t) < 0.20 then return end
	last_icon_update_t = t
	if ui.linkens_breaker and ui.linkens_breaker.Get and ui.linkens_breaker.Image then
		local idx = ui.linkens_breaker:Get()
		local name = LINKENS_BREAKER_ITEMS[(idx or 0) + 1]
		pcall(ui.linkens_breaker.Image, ui.linkens_breaker, ICON_BY_NAME[name] or "")
	end
	for i = 1, #ui.order_steps do
		local w = ui.order_steps[i]
		if w and w.Get and w.Image then
			local idx = w:Get()
			local name = ORDER_ITEMS[(idx or 0) + 1]
			pcall(w.Image, w, ICON_BY_NAME[name] or "")
		end
	end
end

local function normalize_list(v)
	if type(v) == "table" then return v end
	return {}
end

local function get_order_list()
	if ui.order_steps and #ui.order_steps > 0 then
		local list = {}
		for i = 1, #ui.order_steps do
			local w = ui.order_steps[i]
			if w and w.Get then
				local idx = w:Get()
				local name = ORDER_ITEMS[(idx or 0) + 1]
				if name then list[#list + 1] = name end
			end
		end
		if #list > 0 then return list end
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
			if spell.name == "item_dagon" and nm and nm:find("^item_dagon") then return item end
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

local function get_scaled_offset_minus(hero, ability)
	local idx = ui.flare_offset_minus:Get()
	local user_minus = flare_minus_values[idx + 1] or 10
	local base_radius = 170
	if has_agh_effect(hero) then
		local scepter = get_special_value(ability, "scepter_radius")
		if scepter and scepter > 0 then base_radius = scepter end
	end
	local actual = get_mystic_flare_radius(hero, ability)
	if base_radius > 0 then
		return user_minus * (actual / base_radius)
	end
	return user_minus
end

local function get_mystic_flare_cast_pos(hero, target, ability)
	local target_pos = Entity.GetAbsOrigin(target)
	if not has_agh_effect(hero) then return target_pos end
	local r = get_mystic_flare_radius(hero, ability)
	local offset = (r / 2.0) - get_scaled_offset_minus(hero, ability)
	if offset < 0.0 then offset = 0.0 end
	local hero_pos = Entity.GetAbsOrigin(hero)
	local dir = Vector(hero_pos.x - target_pos.x, hero_pos.y - target_pos.y, 0.0)
	local len = dir:Length2D()
	if not len or len < 0.001 then return target_pos end
	dir = dir:Normalized()
	return Vector(target_pos.x + dir.x * offset, target_pos.y + dir.y * offset, target_pos.z)
end

local function get_cast_range(hero, ability)
	if not ability or not hero then return 0.0 end
	local cast_range = 0.0
	if Ability and Ability.GetCastRange then
		cast_range = Ability.GetCastRange(ability) or 0.0
	end
	if NPC and NPC.GetCastRangeBonus then
		cast_range = cast_range + (NPC.GetCastRangeBonus(hero) or 0.0)
	end
	return cast_range
end

local function cast_fast(ability, spell, target)
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

	if spell.cast == "no_target" then
		Ability.CastNoTarget(ability, false, false, true)
		return true, "cast"
	end
	if not target then return false, "no_target" end
	if not Entity.IsAlive(target) then return false, "target_dead" end
	if spell.cast == "position" then
		local pos = get_mystic_flare_cast_pos(hero, target, ability)
		if NPC and NPC.IsPositionInRange and cast_range > 0.0 then
			if not NPC.IsPositionInRange(hero, pos, cast_range) then return false, "out_of_range" end
		end
		Ability.CastPosition(ability, pos, false, false, true)
		return true, "cast"
	end
	if NPC and NPC.IsEntityInRange and cast_range > 0.0 then
		if not NPC.IsEntityInRange(hero, target, cast_range) then return false, "out_of_range" end
	end
	Ability.CastTarget(ability, target, false, false, true)
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
			local pos = Entity.GetAbsOrigin(enemy)
			local dist = cursor:Distance(pos)
			if dist < best_dist then
				best_dist = dist
				best = enemy
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

local linkens_prefix_done = false

local last_fail_reason = nil
local last_fail_step = nil
local last_fail_log_t = 0.0
local FAIL_LOG_COOLDOWN = 0.25

local STEP_CAST = 1
local STEP_SKIPPED = 2
local STEP_BLOCKED = 3

local pending_ability = nil
local pending_step = 0
local pending_name = nil
local pending_start_t = 0.0
local PENDING_TIMEOUT = 0.35

local desired_min_range = 0.0
local last_move_order_t = 0.0
local MOVE_ORDER_COOLDOWN = 0.20

local moving_to_target = false
local last_ground_pos = nil
local GROUND_MOVE_MIN_DIST = 80.0

local function reset_combo()
	combo_running = false
	combo_target = nil
	combo_seq = {}
	combo_idx = 1
	next_cast_time = 0.0
	linkens_prefix_done = false
	pending_ability = nil
	pending_step = 0
	pending_name = nil
	pending_start_t = 0.0
	desired_min_range = 0.0
	last_move_order_t = 0.0
	moving_to_target = false
	last_ground_pos = nil
	last_fail_reason = nil
	last_fail_step = nil
	last_fail_log_t = 0.0
end

local function start_combo(target)
	combo_running = true
	combo_target = target
	combo_seq = build_combo_sequence()
	combo_idx = 1
	next_cast_time = 0.0
	linkens_prefix_done = false
	pending_ability = nil
	pending_step = 0
	pending_name = nil
	pending_start_t = 0.0
	desired_min_range = 0.0
	last_move_order_t = 0.0
	moving_to_target = false
	last_ground_pos = nil
	last_fail_reason = nil
	last_fail_step = nil
	last_fail_log_t = 0.0
	log_debug("Start combo. Steps=" .. tostring(#combo_seq))
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

local function pending_is_confirmed()
	if not pending_ability then return false end
	-- If the ability is no longer ready OR has any cooldown remaining, the cast registered.
	if Ability and Ability.IsReady and not Ability.IsReady(pending_ability) then
		return true
	end
	if Ability and Ability.GetCooldown then
		local cd = Ability.GetCooldown(pending_ability) or 0.0
		if cd > 0.0 then return true end
	end
	-- Charges-based items may not immediately show cooldown in some edge cases.
	if Ability and Ability.SecondsSinceLastUse then
		local s = Ability.SecondsSinceLastUse(pending_ability)
		if type(s) == "number" and s >= 0.0 then return true end
	end
	return false
end

local LINKENS_MODIFIERS = {
	"modifier_item_sphere",
	"modifier_item_sphere_target",
	"modifier_item_sphere_buff",
	"modifier_item_sphere_target_buff",
}

local LINKENS_BREAK_GRACE_SECONDS = 0.60
local last_linkens_break_t = -1000.0

local function target_has_linkens(target)
	if not target or not NPC or not NPC.HasModifier then return false end
	for _, m in ipairs(LINKENS_MODIFIERS) do
		if NPC.HasModifier(target, m) then return true end
	end
	return false
end

local function get_linkens_breaker_spell()
	if not ui.linkens_breaker then return nil end
	local idx = ui.linkens_breaker:Get()
	local name_id = LINKENS_BREAKER_ITEMS[(idx or 0) + 1]
	if not name_id or name_id == "None" then return nil end
	return spell_map[name_id]
end

local function step_combo()
	if not combo_running or not combo_target or not Entity.IsAlive(combo_target) then
		reset_combo()
		return STEP_BLOCKED
	end

	-- If we previously issued a cast, wait until it actually goes on cooldown before attempting anything else.
	if pending_ability then
		local t = now_time()
		if pending_is_confirmed() then
			log_debug("Confirmed cooldown for step " .. tostring(pending_step) .. ": " .. tostring(pending_name))
			if pending_step == 0 then
				last_linkens_break_t = t
				linkens_prefix_done = true
			end
			pending_ability = nil
			pending_step = 0
			pending_name = nil
			pending_start_t = 0.0
			return STEP_SKIPPED -- clear pending; allow searching next frame
		end
		if (t - pending_start_t) >= PENDING_TIMEOUT then
			log_debug("No cooldown detected for step " .. tostring(pending_step) .. ": " .. tostring(pending_name) .. " (retry)")
			pending_ability = nil
			pending_step = 0
			pending_name = nil
			pending_start_t = 0.0
		else
			-- Still waiting.
			return STEP_BLOCKED
		end
	end
	local hero = Heroes.GetLocal()
	if not hero then
		reset_combo()
		return STEP_BLOCKED
	end
	if not combo_seq or #combo_seq == 0 then
		return STEP_BLOCKED
	end
	if combo_idx < 1 or combo_idx > #combo_seq then
		combo_idx = 1
	end
	local function advance_idx()
		combo_idx = combo_idx + 1
		if combo_idx > #combo_seq then combo_idx = 1 end
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

	-- Linken's Sphere handling: if target has Linken's active, override combo to use a chosen breaker first.
	local breaker = get_linkens_breaker_spell()
	local has_linkens = target_has_linkens(combo_target)
	if has_linkens and (now_time() - last_linkens_break_t) <= LINKENS_BREAK_GRACE_SECONDS then
		has_linkens = false
	end
	local enforce_breaker = (not linkens_prefix_done) and has_linkens and (breaker ~= nil)
	if enforce_breaker then
		local ability = get_spell(hero, breaker)
		if not ability then
			log_debug("Linken's breaker missing: " .. tostring(breaker and breaker.name))
			return STEP_BLOCKED
		end
		local ok, reason = cast_fast(ability, breaker, combo_target)
		if ok then
			log_debug("Cast Linken's breaker: " .. tostring(breaker and breaker.name) .. " (waiting cooldown)")
			pending_ability = ability
			pending_step = 0
			pending_name = breaker and breaker.name
			pending_start_t = now_time()
			combo_idx = 1
			return STEP_CAST
		end
		if reason == "out_of_range" then
			issue_move_to_target(hero, combo_target)
			return STEP_BLOCKED
		end
		-- Don't cast anything else while Linken's is up; wait for breaker to be ready/castable.
		return STEP_BLOCKED
	end

	local i = combo_idx
	local spell = combo_seq[i]
	local ability = get_spell(hero, spell)
	if not ability then
		-- Missing items/spells are skipped.
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

	local ok, reason = cast_fast(ability, spell, combo_target)
	if ok then
		log_debug("Cast step " .. tostring(i) .. ": " .. tostring(spell.name) .. " (waiting cooldown)")
		pending_ability = ability
		pending_step = i
		pending_name = spell.name
		pending_start_t = now_time()
		advance_idx()
		return STEP_CAST
	end

	-- Cooldown = skip and continue sequentially.
	if reason == "not_ready" then
		if ui.debug_logs:Get() then
			local t = now_time()
			if reason ~= last_fail_reason or last_fail_step ~= i or (t - last_fail_log_t) >= FAIL_LOG_COOLDOWN then
				last_fail_reason = reason
				last_fail_step = i
				last_fail_log_t = t
				log_debug("Skip step " .. tostring(i) .. ": " .. tostring(spell.name) .. " => not_ready")
			end
		end
		advance_idx()
		return STEP_SKIPPED
	end

	-- Out of range = move and block.
	if reason == "out_of_range" then
		issue_move_to_target(hero, combo_target)
		return STEP_BLOCKED
	end

	-- Other failures (mana/silence/etc) block.
	if ui.debug_logs:Get() then
		local t = now_time()
		if reason ~= last_fail_reason or last_fail_step ~= i or (t - last_fail_log_t) >= FAIL_LOG_COOLDOWN then
			last_fail_reason = reason
			last_fail_step = i
			last_fail_log_t = t
			log_debug("Fail step " .. tostring(i) .. ": " .. tostring(spell.name) .. " => " .. tostring(reason))
		end
	end
	return STEP_BLOCKED
end

function combo.OnUpdate()
	if not ui.enabled:Get() then return end
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
		if combo_running then
			reset_combo()
		end
		local target = find_target_near_cursor()
		if target then
			start_combo(target)
		else
			issue_move_to_ground(hero, Input.GetWorldCursorPos())
			was_key_down = true
			return
		end
	end

	local t = now_time()
	if t < next_cast_time then return end

	-- Enforce 0.05s between actual casts; fast-skip missing items/spells.
	for _ = 1, 32 do
		if not combo_running then break end
		local r = step_combo()
		if r == STEP_CAST then
			next_cast_time = t + CAST_GAP_SECONDS
			break
		end
		if r == STEP_SKIPPED then
			-- keep skipping in the same frame
		else
			break
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