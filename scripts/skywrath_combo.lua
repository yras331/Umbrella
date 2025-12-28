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

local available_spells = {
	{nameId = "Concussive Shot", imagePath = "", isEnabled = true},
	{nameId = "Sheep Stick", imagePath = "", isEnabled = true},
	{nameId = "Rod of Atos", imagePath = "", isEnabled = true},
	{nameId = "Ancient Seal", imagePath = "", isEnabled = true},
	{nameId = "Ethereal Blade", imagePath = "", isEnabled = true},
	{nameId = "Arcane Bolt", imagePath = "", isEnabled = true},
	{nameId = "Dagon", imagePath = "", isEnabled = true},
	{nameId = "Mystic Flare", imagePath = "", isEnabled = true},
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

ui.combo_order = order_group:MultiSelect("Combo Order (Drag to Reorder)", available_spells, true)
ui.combo_order:DragAllowed(true)
if ui.combo_order and ui.combo_order.Set then
	ui.combo_order:Set(DEFAULT_ORDER)
end

local function normalize_list(v)
	if type(v) == "table" then return v end
	return {}
end

local function get_order_list()
	local list = normalize_list(ui.combo_order:List())
	if #list == 0 then return DEFAULT_ORDER end
	return list
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

local function step_combo()
	if not combo_running or not combo_target or not Entity.IsAlive(combo_target) then
		reset_combo()
		return STEP_BLOCKED
	end

	-- If we previously issued a cast, wait until it actually goes on cooldown before advancing.
	if pending_ability then
		local t = now_time()
		if pending_is_confirmed() then
			log_debug("Confirmed cooldown for step " .. tostring(pending_step) .. ": " .. tostring(pending_name))
			pending_ability = nil
			pending_step = 0
			pending_name = nil
			pending_start_t = 0.0
			combo_idx = combo_idx + 1
			return STEP_SKIPPED -- advance without consuming a cast slot this frame
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
	if combo_idx > #combo_seq then
		reset_combo()
		return STEP_BLOCKED
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

	local spell = combo_seq[combo_idx]
	local ability = get_spell(hero, spell)
	-- If missing or not castable now, skip instantly.
	if not ability then
		log_debug("Skip step " .. tostring(combo_idx) .. ": missing " .. tostring(spell.name))
		combo_idx = combo_idx + 1
		return STEP_SKIPPED
	end
	local ok, reason = cast_fast(ability, spell, combo_target)
	if ok then
		log_debug("Cast step " .. tostring(combo_idx) .. ": " .. tostring(spell.name) .. " (waiting cooldown)")
		pending_ability = ability
		pending_step = combo_idx
		pending_name = spell.name
		pending_start_t = now_time()
		return STEP_CAST
	end
	if reason == "out_of_range" then
		issue_move_to_target(hero, combo_target)
	end

	local t = now_time()
	-- Rate-limit repeated fail logs for the same step+reason.
	if ui.debug_logs:Get() then
		local step = combo_idx
		if reason ~= last_fail_reason or step ~= last_fail_step or (t - last_fail_log_t) >= FAIL_LOG_COOLDOWN then
			last_fail_reason = reason
			last_fail_step = step
			last_fail_log_t = t
			log_debug(
				"Fail step " .. tostring(step) .. ": " .. tostring(spell.name) .. " => " .. tostring(reason)
			)
		end
	end

	-- Don't advance unless the cast actually goes off.
	return STEP_BLOCKED
end

function combo.OnUpdate()
	if not ui.enabled:Get() then return end
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

return combo