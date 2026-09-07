---@diagnostic disable: undefined-global

local zeus_nimbus_blink_spam = {}

local menu_tab = Menu.Create("General", "Scripts", "Zeus Nimbus Blink Spam", "ZeusNimbusBlinkSpam")
local main_group = menu_tab:Create("Settings")

local ui = {}
ui.enabled = main_group:Switch("Enabled", true)
ui.use_nimbus = main_group:Switch("Use Nimbus", true)
ui.use_thunder = main_group:Switch("Use Thundergod's Wrath", true)
ui.use_arcane_blink = main_group:Switch("Use Arcane Blink", true)
ui.prefer_lowest_hp = main_group:Switch("Prefer Lowest HP Target", true)
ui.search_radius = main_group:Slider("Search Radius", 1000, 20000, 12000)
ui.blink_min_distance = main_group:Slider("Blink Min Distance", 200, 1800, 650)
ui.blink_end_distance = main_group:Slider("Blink End Distance", 0, 450, 175)
ui.action_gap_ms = main_group:Slider("Action Gap (ms)", 50, 600, 140)
ui.debug_logs = main_group:Switch("Debug Logs", false)
main_group:Label("While enabled, Zeus auto-casts on the best valid enemy hero.")
main_group:Label("Arcane Blink only engages when Nimbus is ready.")

local SCRIPT_TAG = "[Zeus Nimbus Blink Spam]"
local ZEUS_NAMES = {
	["npc_dota_hero_zuus"] = true,
	["npc_dota_hero_zeus"] = true,
}

local SPELLS = {
	nimbus = { name = "zuus_cloud", cast = "position" },
	thunder = { name = "zuus_thundergods_wrath", cast = "no_target" },
	arcane_blink = { name = "item_arcane_blink", cast = "position" },
}

local next_action_t = 0.0

local function now_time()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
end

local function log_debug(msg)
	if not ui.debug_logs:Get() then return end
	if Log and Log.Write then
		Log.Write(SCRIPT_TAG .. " " .. tostring(msg))
	else
		print(SCRIPT_TAG .. " " .. tostring(msg))
	end
end

local function distance2d(a, b)
	if not a or not b then return 999999.0 end
	local dx = (a.x or 0.0) - (b.x or 0.0)
	local dy = (a.y or 0.0) - (b.y or 0.0)
	return math.sqrt(dx * dx + dy * dy)
end

local function get_unit_name(unit)
	if not unit then return nil end
	if NPC and NPC.GetUnitName then
		local ok, name = pcall(NPC.GetUnitName, unit)
		if ok and type(name) == "string" then return name end
	end
	if Entity and Entity.GetUnitName then
		local ok, name = pcall(Entity.GetUnitName, unit)
		if ok and type(name) == "string" then return name end
	end
	return nil
end

local function is_zeus(hero)
	if not hero then return false end
	local name = get_unit_name(hero)
	if name and ZEUS_NAMES[name] then
		return true
	end
	return NPC and NPC.GetAbility and NPC.GetAbility(hero, "zuus_arc_lightning") ~= nil
end

local function is_backpack_index(i)
	return type(i) == "number" and i >= 6 and i <= 8
end

local function get_ability_name(ability)
	if not ability or not Ability or not Ability.GetName then return nil end
	local ok, name = pcall(Ability.GetName, ability)
	if ok and type(name) == "string" then
		return name
	end
	return nil
end

local function spell_name_matches(expected_name, item_name)
	return expected_name ~= nil and item_name ~= nil and expected_name == item_name
end

local function get_spell(owner, spell)
	if not owner or not spell or not NPC then return nil, "missing" end
	if spell.name:sub(1, 5) ~= "item_" then
		return NPC.GetAbility(owner, spell.name), "ability"
	end

	local found_in_backpack = false
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(owner, i)
		if item then
			local item_name = get_ability_name(item)
			if spell_name_matches(spell.name, item_name) then
				if is_backpack_index(i) then
					found_in_backpack = true
				else
					return item, "inventory"
				end
			end
		end
	end

	if found_in_backpack then
		return nil, "backpack"
	end
	return nil, "missing"
end

local function get_cast_point_seconds(ability)
	if not ability or not Ability or not Ability.GetCastPoint then return 0.10 end
	local ok, cp = pcall(Ability.GetCastPoint, ability)
	if ok and type(cp) == "number" then
		if cp < 0.05 then cp = 0.05 end
		if cp > 0.60 then cp = 0.60 end
		return cp
	end
	return 0.10
end

local function read_special_value(ability, key)
	if not ability or not key or not Ability then return nil end
	if Ability.GetSpecialValueFor then
		local ok, value = pcall(Ability.GetSpecialValueFor, ability, key, -1)
		if ok and type(value) == "number" and value > 0.0 then return value end
		ok, value = pcall(Ability.GetSpecialValueFor, ability, key)
		if ok and type(value) == "number" and value > 0.0 then return value end
	end
	if Ability.GetLevelSpecialValueFor then
		local ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, key, -1)
		if ok and type(value) == "number" and value > 0.0 then return value end
		ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, key)
		if ok and type(value) == "number" and value > 0.0 then return value end
	end
	return nil
end

local function get_cast_range(hero, ability, spell)
	if not ability then return 0.0 end

	local cast_range = 0.0
	if Ability and Ability.GetCastRange then
		local ok, value = pcall(Ability.GetCastRange, ability)
		if ok and type(value) == "number" then
			cast_range = value
		end
	end

	if cast_range <= 0.0 then
		cast_range = read_special_value(ability, "cast_range")
			or read_special_value(ability, "range")
			or read_special_value(ability, "AbilityCastRange")
			or read_special_value(ability, "blink_range")
			or 0.0
	end

	if NPC and NPC.GetCastRangeBonus and hero and cast_range > 0.0 and spell and spell.cast ~= "position" then
		cast_range = cast_range + (NPC.GetCastRangeBonus(hero) or 0.0)
	end

	return cast_range
end

local function is_spell_ready_and_castable(hero, ability)
	if not hero or not ability or not Ability or not Ability.IsReady or not Ability.IsCastable then return false end
	if not Ability.IsReady(ability) then return false end
	local mana = (NPC and NPC.GetMana and NPC.GetMana(hero)) or 0.0
	return Ability.IsCastable(ability, mana)
end

local function target_is_invalid(target)
	if not target or not Entity or not Entity.IsAlive or not Entity.IsAlive(target) then
		return true
	end
	if Entity.IsInvulnerable then
		local ok, inv = pcall(Entity.IsInvulnerable, target)
		if ok and inv then return true end
	end
	if NPC and NPC.IsMagicImmune then
		local ok, immune = pcall(NPC.IsMagicImmune, target)
		if ok and immune then return true end
	end
	if NPC and NPC.IsDebuffImmune then
		local ok, immune = pcall(NPC.IsDebuffImmune, target)
		if ok and immune then return true end
	end
	return false
end

local function can_select_enemy(hero, enemy)
	if not hero or not enemy or enemy == hero then return false end
	if not Entity or not Entity.IsAlive or not Entity.IsAlive(enemy) then return false end
	if Entity.GetTeamNum(enemy) == Entity.GetTeamNum(hero) then return false end
	if NPC and NPC.IsIllusion then
		local ok, illusion = pcall(NPC.IsIllusion, enemy)
		if ok and illusion then return false end
	end
	return not target_is_invalid(enemy)
end

local function get_unit_health(unit)
	if not unit then return nil end
	if NPC and NPC.GetHealth then
		local ok, hp = pcall(NPC.GetHealth, unit)
		if ok and type(hp) == "number" then return hp end
	end
	if Entity and Entity.GetHealth then
		local ok, hp = pcall(Entity.GetHealth, unit)
		if ok and type(hp) == "number" then return hp end
	end
	return nil
end

local function find_best_enemy(hero, radius)
	if not hero or not Heroes or not Heroes.InRadius or not Entity or not Entity.GetAbsOrigin then return nil end

	local hero_pos = Entity.GetAbsOrigin(hero)
	if not hero_pos then return nil end

	local my_team = Entity.GetTeamNum(hero)
	local enemies = Heroes.InRadius(hero_pos, radius, my_team, Enum.TeamType.TEAM_ENEMY, true, true)
	if not enemies or #enemies == 0 then return nil end

	local prefer_lowest_hp = ui.prefer_lowest_hp:Get()
	local best_enemy = nil
	local best_hp = 999999.0
	local best_dist = 999999.0

	for _, enemy in ipairs(enemies) do
		if can_select_enemy(hero, enemy) then
			local enemy_pos = Entity.GetAbsOrigin(enemy)
			local dist = distance2d(hero_pos, enemy_pos)
			local hp = get_unit_health(enemy)
			if type(hp) ~= "number" then hp = 999999.0 end

			local better = false
			if prefer_lowest_hp then
				better = (hp < best_hp) or (hp == best_hp and dist < best_dist)
			else
				better = dist < best_dist
			end

			if better then
				best_enemy = enemy
				best_hp = hp
				best_dist = dist
			end
		end
	end

	return best_enemy
end

local function get_blink_position(hero_pos, target_pos, blink_range, stop_distance)
	if not hero_pos or not target_pos then return nil end

	local dx = (target_pos.x or 0.0) - (hero_pos.x or 0.0)
	local dy = (target_pos.y or 0.0) - (hero_pos.y or 0.0)
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist < 1.0 then
		return nil
	end

	local dir_x = dx / dist
	local dir_y = dy / dist
	local desired_step = math.max(0.0, dist - stop_distance)
	if blink_range > 0.0 then
		desired_step = math.min(desired_step, blink_range)
	end

	return Vector(
		(hero_pos.x or 0.0) + dir_x * desired_step,
		(hero_pos.y or 0.0) + dir_y * desired_step,
		target_pos.z or hero_pos.z or 0.0
	)
end

local function schedule_next_action(ability)
	local gap = (ui.action_gap_ms:Get() or 140) / 1000.0
	local cast_point = get_cast_point_seconds(ability)
	next_action_t = now_time() + math.max(gap, cast_point + 0.08)
end

local function try_cast_position(hero, ability, spell, pos)
	if not hero or not ability or not spell or not pos then return false, "missing" end
	if not is_spell_ready_and_castable(hero, ability) then return false, "not_ready" end

	local cast_range = get_cast_range(hero, ability, spell)
	if cast_range > 0.0 and NPC and NPC.IsPositionInRange and not NPC.IsPositionInRange(hero, pos, cast_range) then
		return false, "out_of_range"
	end

	if not Ability or not Ability.CastPosition then return false, "api_unavailable" end
	Ability.CastPosition(ability, pos, false, false, false)
	schedule_next_action(ability)
	return true, "cast"
end

local function try_cast_no_target(hero, ability)
	if not hero or not ability then return false, "missing" end
	if not is_spell_ready_and_castable(hero, ability) then return false, "not_ready" end
	if not Ability or not Ability.CastNoTarget then return false, "api_unavailable" end
	Ability.CastNoTarget(ability, false, false, false)
	schedule_next_action(ability)
	return true, "cast"
end

local function try_use_arcane_blink(hero, target, nimbus)
	if not ui.use_arcane_blink:Get() or not ui.use_nimbus:Get() then return false end
	if not hero or not target or not nimbus then return false end
	if not is_spell_ready_and_castable(hero, nimbus) then return false end

	local blink = get_spell(hero, SPELLS.arcane_blink)
	if not blink or not is_spell_ready_and_castable(hero, blink) then return false end

	local hero_pos = Entity.GetAbsOrigin(hero)
	local target_pos = Entity.GetAbsOrigin(target)
	if not hero_pos or not target_pos then return false end

	local dist = distance2d(hero_pos, target_pos)
	local min_dist = ui.blink_min_distance:Get() or 650
	if dist < min_dist then return false end

	local blink_range = get_cast_range(hero, blink, SPELLS.arcane_blink)
	if blink_range <= 0.0 then
		blink_range = 1400.0
	end
	if dist > (blink_range + 50.0) then return false end

	local stop_distance = ui.blink_end_distance:Get() or 175
	local blink_pos = get_blink_position(hero_pos, target_pos, blink_range, stop_distance)
	if not blink_pos then return false end

	local ok_cast, reason = try_cast_position(hero, blink, SPELLS.arcane_blink, blink_pos)
	if ok_cast then
		log_debug("Arcane Blink cast")
		return true
	end

	if reason ~= "not_ready" then
		log_debug("Arcane Blink skipped: " .. tostring(reason))
	end
	return false
end

local function try_use_nimbus(hero, target)
	if not ui.use_nimbus:Get() or not hero or not target then return false end

	local nimbus = get_spell(hero, SPELLS.nimbus)
	if not nimbus then return false end

	local target_pos = Entity.GetAbsOrigin(target)
	if not target_pos then return false end

	local ok_cast, reason = try_cast_position(hero, nimbus, SPELLS.nimbus, target_pos)
	if ok_cast then
		log_debug("Nimbus cast")
		return true
	end

	if reason ~= "not_ready" and reason ~= "out_of_range" then
		log_debug("Nimbus skipped: " .. tostring(reason))
	end
	return false
end

local function try_use_thunder(hero)
	if not ui.use_thunder:Get() or not hero then return false end

	local thunder = get_spell(hero, SPELLS.thunder)
	if not thunder then return false end

	local ok_cast, reason = try_cast_no_target(hero, thunder)
	if ok_cast then
		log_debug("Thundergod's Wrath cast")
		return true
	end

	if reason ~= "not_ready" then
		log_debug("Thundergod's Wrath skipped: " .. tostring(reason))
	end
	return false
end

local function reset_runtime_state()
	next_action_t = 0.0
end

function zeus_nimbus_blink_spam.OnGameStart()
	reset_runtime_state()
end

function zeus_nimbus_blink_spam.OnGameEnd()
	reset_runtime_state()
end

function zeus_nimbus_blink_spam.OnUpdate()
	if not ui.enabled:Get() then return end
	if now_time() < next_action_t then return end

	local hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
	if not hero or not Entity or not Entity.IsAlive or not Entity.IsAlive(hero) then return end
	if not is_zeus(hero) then return end

	local radius = ui.search_radius:Get() or 12000
	local target = find_best_enemy(hero, radius)
	if not target then return end

	local nimbus = get_spell(hero, SPELLS.nimbus)
	if try_use_arcane_blink(hero, target, nimbus) then
		return
	end

	if try_use_nimbus(hero, target) then
		return
	end

	try_use_thunder(hero)
end

return zeus_nimbus_blink_spam
