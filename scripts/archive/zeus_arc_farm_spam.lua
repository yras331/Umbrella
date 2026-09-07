---@diagnostic disable: undefined-global

local zeus_arc_farm_spam = {}

local menu_tab = Menu.Create("General", "Scripts", "Zeus Arc Farm Spam", "ArcFarm")
local main_group = menu_tab:Create("Settings")

local ui = {}
ui.enabled = main_group:Switch("Enabled", true)
ui.use_toggle_mode = main_group:Switch("Use Toggle Key Mode", false)
ui.hold_key = main_group:Bind("Hold Key", Enum.ButtonCode.KEY_F)
ui.toggle_key = main_group:Bind("Toggle Key", Enum.ButtonCode.KEY_G)
ui.attack_orders = main_group:Switch("Send Right Click Orders", true)
ui.attack_only_in_range = main_group:Switch("Attack Only In Range (No Walk)", true)
ui.attack_rate_ms = main_group:Slider("Attack Order Rate (ms)", 30, 300, 90)
ui.debug_logs = main_group:Switch("Debug Logs", false)
main_group:Label("Target range is Arc Lightning cast range + bonuses.")

local SCRIPT_TAG = "[Zeus Arc Farm Spam]"
local ARC_LIGHTNING_NAME = "zuus_arc_lightning"
local ORDER_TAG = "zeus_arc_farm_attack"

local ARC_ORDER_GAP = 0.06
local last_arc_order_t = -1000.0
local last_attack_order_t = -1000.0
local toggle_active = false
local toggle_key_was_down = false

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

local function get_entity_index(ent)
	if not ent or not Entity or not Entity.GetIndex then return -1 end
	local ok, idx = pcall(Entity.GetIndex, ent)
	if ok and type(idx) == "number" then return idx end
	return -1
end

local function is_same_team(a, b)
	if not a or not b then return false end
	if Entity and Entity.IsSameTeam then
		local ok, same = pcall(Entity.IsSameTeam, a, b)
		if ok then return same == true end
	end
	if Entity and Entity.GetTeamNum then
		local ok_a, ta = pcall(Entity.GetTeamNum, a)
		local ok_b, tb = pcall(Entity.GetTeamNum, b)
		if ok_a and ok_b and type(ta) == "number" and type(tb) == "number" then
			return ta == tb
		end
	end
	return false
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
	if name == "npc_dota_hero_zuus" or name == "npc_dota_hero_zeus" then
		return true
	end
	if NPC and NPC.GetAbility then
		return NPC.GetAbility(hero, ARC_LIGHTNING_NAME) ~= nil
	end
	return false
end

local function append_unique_units(out, seen, units)
	if type(units) ~= "table" then return end
	for _, unit in ipairs(units) do
		if unit then
			local idx = get_entity_index(unit)
			if idx ~= -1 and not seen[idx] then
				seen[idx] = true
				out[#out + 1] = unit
			end
		end
	end
end

local function gather_units_in_radius(pos, radius, my_team)
	local out = {}
	local seen = {}
	if not pos or not Enum or not Enum.TeamType then return out end

	if NPCs and NPCs.InRadius then
		local team_type_names = {
			"TEAM_ENEMY",
			"TEAM_BOTH",
			"TEAM_NEUTRAL",
			"TEAM_ALL",
		}
		for _, name in ipairs(team_type_names) do
			local tt = Enum.TeamType[name]
			if tt ~= nil then
				local ok, units = pcall(NPCs.InRadius, pos, radius, my_team, tt)
				if ok then append_unique_units(out, seen, units) end
				local ok6, units6 = pcall(NPCs.InRadius, pos, radius, my_team, tt, true, true)
				if ok6 then append_unique_units(out, seen, units6) end
			end
		end
	end

	-- Fallback scan to ensure neutrals are included even if team-type filters miss them.
	if NPCs and NPCs.GetAll then
		local ok_all, all_units = pcall(NPCs.GetAll)
		if ok_all and type(all_units) == "table" then
			for _, unit in ipairs(all_units) do
				if unit then
					local idx = get_entity_index(unit)
					if idx ~= -1 and not seen[idx] and Entity and Entity.IsAlive and Entity.IsAlive(unit) then
						local upos = Entity.GetAbsOrigin(unit)
						if distance2d(pos, upos) <= radius then
							seen[idx] = true
							out[#out + 1] = unit
						end
					end
				end
			end
		end
	end

	return out
end

local function is_creep(unit)
	if not unit then return false end
	if NPC then
		if NPC.IsHero then
			local ok, v = pcall(NPC.IsHero, unit)
			if ok and v then return false end
		end
		if NPC.IsRoshan then
			local ok, v = pcall(NPC.IsRoshan, unit)
			if ok and v then return false end
		end
		if NPC.IsLaneCreep then
			local ok, v = pcall(NPC.IsLaneCreep, unit)
			if ok and v then return true end
		end
		if NPC.IsNeutral then
			local ok, v = pcall(NPC.IsNeutral, unit)
			if ok and v then return true end
		end
		if NPC.IsCreep then
			local ok, v = pcall(NPC.IsCreep, unit)
			if ok and v then return true end
		end
	end

	local name = get_unit_name(unit)
	if type(name) == "string" then
		if string.find(name, "npc_dota_creep", 1, true) ~= nil then return true end
		if string.find(name, "npc_dota_neutral", 1, true) ~= nil then return true end
	end

	return false
end

local function is_valid_creep_target(hero, unit)
	if not hero or not unit then return false end
	if not Entity or not Entity.IsAlive then return false end
	if not Entity.IsAlive(unit) then return false end
	if is_same_team(hero, unit) then return false end
	if Entity.IsInvulnerable then
		local ok, inv = pcall(Entity.IsInvulnerable, unit)
		if ok and inv then return false end
	end
	return is_creep(unit)
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

local function find_lowest_hp_creep(hero, radius)
	if not hero or not Entity or not Entity.GetAbsOrigin then return nil, nil end

	local my_pos = Entity.GetAbsOrigin(hero)
	if not my_pos then return nil, nil end

	local my_team = (Entity.GetTeamNum and Entity.GetTeamNum(hero)) or nil
	local units = gather_units_in_radius(my_pos, radius, my_team)

	local best_unit = nil
	local best_hp = 999999.0
	local best_dist = 999999.0

	for _, unit in ipairs(units) do
		if is_valid_creep_target(hero, unit) then
			local pos = Entity.GetAbsOrigin(unit)
			local dist = distance2d(my_pos, pos)
			local hp = get_unit_health(unit)
			if type(hp) ~= "number" then hp = 999999.0 end

			if (hp < best_hp) or (hp == best_hp and dist < best_dist) then
				best_hp = hp
				best_dist = dist
				best_unit = unit
			end
		end
	end

	return best_unit, best_dist
end

local function get_arc_lightning(hero)
	if not hero or not NPC or not NPC.GetAbility then return nil end
	return NPC.GetAbility(hero, ARC_LIGHTNING_NAME)
end

local function get_effective_cast_range(hero, ability)
	if not ability or not Ability or not Ability.GetCastRange then return 0.0 end
	local ok, range = pcall(Ability.GetCastRange, ability)
	if not ok or type(range) ~= "number" then range = 0.0 end
	if range < 0.0 then range = 0.0 end
	if NPC and NPC.GetCastRangeBonus then
		local ok_bonus, bonus = pcall(NPC.GetCastRangeBonus, hero)
		if ok_bonus and type(bonus) == "number" then
			range = range + bonus
		end
	end
	return range
end

local function get_hull_radius(unit)
	if not unit then return 0.0 end
	if NPC and NPC.GetHullRadius then
		local ok, r = pcall(NPC.GetHullRadius, unit)
		if ok and type(r) == "number" and r > 0.0 then return r end
	end
	if Entity and Entity.GetHullRadius then
		local ok, r = pcall(Entity.GetHullRadius, unit)
		if ok and type(r) == "number" and r > 0.0 then return r end
	end
	return 0.0
end

local function get_effective_attack_range(hero)
	if not hero then return 380.0 end

	if NPC and NPC.GetTrueAttackRange then
		local ok, r = pcall(NPC.GetTrueAttackRange, hero)
		if ok and type(r) == "number" and r > 0.0 then return r end
	end

	local range = nil
	if NPC and NPC.GetAttackRange then
		local ok, r = pcall(NPC.GetAttackRange, hero)
		if ok and type(r) == "number" and r > 0.0 then range = r end
	end
	if (not range or range <= 0.0) and Entity and Entity.GetAttackRange then
		local ok, r = pcall(Entity.GetAttackRange, hero)
		if ok and type(r) == "number" and r > 0.0 then range = r end
	end
	if not range or range <= 0.0 then
		range = 380.0 -- Zeus base fallback
	end

	return range
end

local function is_in_attack_range(hero, target, center_dist)
	if not hero or not target then return false end
	local attack_range = get_effective_attack_range(hero)
	local target_hull = get_hull_radius(target)
	local hero_hull = get_hull_radius(hero)
	-- Small buffer to avoid jitter from frame-to-frame range checks.
	local threshold = attack_range + target_hull + hero_hull + 20.0
	return (center_dist or 999999.0) <= threshold
end

local function try_cast_arc_lightning(hero, target, distance_to_target)
	if not hero or not target then return false, "invalid" end
	if not Ability or not Ability.IsReady or not Ability.CastTarget then return false, "api_missing" end

	local arc = get_arc_lightning(hero)
	if not arc then return false, "no_arc_lightning" end

	if not Ability.IsReady(arc) then return false, "not_ready" end
	if Ability.IsCastable and NPC and NPC.GetMana then
		local mana = NPC.GetMana(hero) or 0.0
		if not Ability.IsCastable(arc, mana) then
			return false, "not_castable"
		end
	end

	local range = get_effective_cast_range(hero, arc)
	if range > 0.0 and distance_to_target and distance_to_target > (range + 25.0) then
		return false, "out_of_range"
	end

	Ability.CastTarget(arc, target, false, false, false)
	return true, "cast"
end

local function issue_attack_target_order(hero, target)
	if not hero or not target then return false end

	if NPC and NPC.AttackTarget then
		local ok = pcall(NPC.AttackTarget, hero, target, false)
		if ok then return true end
	end

	if not Players or not Players.GetLocal then return false end
	local player = Players.GetLocal()
	if not player then return false end

	if not Player or not Player.PrepareUnitOrders then return false end
	if not Enum or not Enum.UnitOrder or not Enum.PlayerOrderIssuer then return false end
	if not Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET then return false end
	if not Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY then return false end

	Player.PrepareUnitOrders(
		player,
		Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET,
		target,
		Vector(0, 0, 0),
		nil,
		Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY,
		hero,
		false,
		false,
		false,
		true,
		ORDER_TAG,
		true
	)
	return true
end

local function reset_runtime_state()
	last_arc_order_t = -1000.0
	last_attack_order_t = -1000.0
	toggle_active = false
	toggle_key_was_down = false
end

local function is_activation_pressed()
	local hold_key = ui.hold_key:Get()
	local hold_down = (hold_key ~= Enum.ButtonCode.BUTTON_CODE_INVALID) and Input.IsKeyDown(hold_key) or false

	if not ui.use_toggle_mode:Get() then
		toggle_key_was_down = false
		return hold_down
	end

	local key = ui.toggle_key:Get()
	if key == Enum.ButtonCode.BUTTON_CODE_INVALID then
		toggle_key_was_down = false
		return hold_down
	end

	local down = Input.IsKeyDown(key)
	if down and not toggle_key_was_down then
		toggle_active = not toggle_active
		log_debug("Toggle mode state: " .. tostring(toggle_active))
	end
	toggle_key_was_down = down
	return toggle_active or hold_down
end

function zeus_arc_farm_spam.OnGameStart()
	reset_runtime_state()
end

function zeus_arc_farm_spam.OnGameEnd()
	reset_runtime_state()
end

function zeus_arc_farm_spam.OnUpdate()
	if not ui.enabled:Get() then return end

	if not is_activation_pressed() then return end

	local hero = Heroes.GetLocal()
	if not hero or not Entity.IsAlive(hero) then return end
	if not is_zeus(hero) then return end

	local arc = get_arc_lightning(hero)
	if not arc then return end
	local radius = get_effective_cast_range(hero, arc)
	if radius <= 0.0 then return end

	local target, dist = find_lowest_hp_creep(hero, radius)
	if not target then return end

	local t = now_time()

	if (t - last_arc_order_t) >= ARC_ORDER_GAP then
		local ok_cast, reason = try_cast_arc_lightning(hero, target, dist)
		if ok_cast then
			last_arc_order_t = t
		else
			if reason ~= "not_ready" and reason ~= "out_of_range" then
				log_debug("Arc Lightning skipped: " .. tostring(reason))
			end
		end
	end

	if ui.attack_orders:Get() then
		local attack_gap = (ui.attack_rate_ms:Get() or 90) / 1000.0
		if (t - last_attack_order_t) >= attack_gap then
			local can_issue = true
			if ui.attack_only_in_range and ui.attack_only_in_range.Get and ui.attack_only_in_range:Get() then
				can_issue = is_in_attack_range(hero, target, dist)
			end
			if can_issue and issue_attack_target_order(hero, target) then
				last_attack_order_t = t
			elseif not can_issue then
				log_debug("Attack skipped: out_of_range_no_walk")
			end
		end
	end
end

return zeus_arc_farm_spam
