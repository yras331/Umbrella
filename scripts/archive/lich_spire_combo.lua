---@diagnostic disable: undefined-global

local lich_spire_combo = {}

local SCRIPT_TAG = "[Lich Spire Combo]"
local LOCK_LINE_COLOR_READY = Color(80, 255, 110, 230)
local LOCK_LINE_COLOR_CHASE = Color(255, 70, 70, 230)
local LOCK_LINE_THICKNESS = 4.0
local CAST_GAP_SECONDS = 0.015
local COOLDOWN_CONFIRM_GRACE = 0.08
local COOLDOWN_CONFIRM_EXTRA = 0.15
local MOVE_ORDER_COOLDOWN = 0.08
local GROUND_MOVE_MIN_DIST = 50.0
local SPIRE_SEARCH_RADIUS = 350.0

local ui

local combo_running = false
local waiting_release = false
local was_key_down = false
local combo_mode = nil -- "shard" | "scepter"
local combo_target = nil
local combo_anchor_pos = nil
local next_action_time = 0.0
local last_move_order_t = -1000.0
local last_ground_pos = nil
local pending_confirm = nil
local step_done = {}
local last_spire_hint_pos = nil
local last_spire_hint_t = -1000.0
local last_cluster = nil
local gaze_channel_confirmed = false
local locked_cluster_center = nil

local spell_map = {
	["Frost Blast"] = { name = "lich_frost_nova", kind = "ability", cast = "target" },
	["Frost Shield"] = { name = "lich_frost_shield", kind = "ability", cast = "target" },
	["Sinister Gaze"] = { name = "lich_sinister_gaze", kind = "ability", cast = "target" },
	["Ice Spire"] = { name = "lich_ice_spire", kind = "ability", cast = "position" },
	["Chain Frost"] = { name = "lich_chain_frost", kind = "ability", cast = "target" },
}

local function now_time()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
end

local function log_debug(msg)
	if not ui or not ui.debug_logs or not ui.debug_logs.Get or not ui.debug_logs:Get() then return end
	if Log and Log.Write then
		Log.Write(SCRIPT_TAG .. " " .. tostring(msg))
	else
		print(SCRIPT_TAG .. " " .. tostring(msg))
	end
end

local function distance2d(a, b)
	if not a or not b then return 99999.0 end
	local dx = (a.x or 0.0) - (b.x or 0.0)
	local dy = (a.y or 0.0) - (b.y or 0.0)
	return math.sqrt(dx * dx + dy * dy)
end

local function copy_vector(pos)
	if not pos then return nil end
	return Vector(pos.x or 0.0, pos.y or 0.0, pos.z or 0.0)
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

local function is_lich(hero)
	if not hero then return false end
	local name = get_unit_name(hero)
	if name == "npc_dota_hero_lich" then
		return true
	end
	return NPC and NPC.GetAbility and NPC.GetAbility(hero, "lich_frost_nova") ~= nil
end

local function get_spell(hero, spell)
	if not hero or not spell or not NPC then return nil end
	if spell.kind == "ability" then
		return NPC.GetAbility(hero, spell.name)
	end
	return nil
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

local function get_cooldown_remaining_seconds(ability)
	if not ability or not Ability or not Ability.GetCooldown then return nil end
	local ok, cd = pcall(Ability.GetCooldown, ability)
	if ok and type(cd) == "number" then
		return cd
	end
	return nil
end

local function is_cooldown_started(ability)
	if not ability or not Ability or not Ability.IsReady then return false end
	if not Ability.IsReady(ability) then
		return true
	end
	local cd = get_cooldown_remaining_seconds(ability)
	return (cd ~= nil) and (cd > 0.0)
end

local function get_special_value(ability, key)
	if not ability or not key or not Ability then return 0 end
	if Ability.GetSpecialValueFor then
		local ok, value = pcall(Ability.GetSpecialValueFor, ability, key, -1)
		if ok and type(value) == "number" then return value end
		ok, value = pcall(Ability.GetSpecialValueFor, ability, key)
		if ok and type(value) == "number" then return value end
	end
	if Ability.GetLevelSpecialValueFor then
		local ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, key, -1)
		if ok and type(value) == "number" then return value end
		ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, key)
		if ok and type(value) == "number" then return value end
	end
	return 0
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

local function has_agh_effect(hero)
	if not hero or not NPC or not Ability or not Ability.GetName then return false end
	if NPC.GetItemByIndex then
		for i = 0, 20 do
			local item = NPC.GetItemByIndex(hero, i)
			if item then
				local ok_n, nm = pcall(Ability.GetName, item)
				if ok_n and (nm == "item_ultimate_scepter" or nm == "item_ultimate_scepter_2" or nm == "item_ultimate_scepter_roshan") then
					return true
				end
			end
		end
	end
	if NPC.HasModifier then
		if NPC.HasModifier(hero, "modifier_item_ultimate_scepter") then return true end
		if NPC.HasModifier(hero, "modifier_item_ultimate_scepter_consumed") then return true end
		if NPC.HasModifier(hero, "modifier_item_ultimate_scepter_2") then return true end
		if NPC.HasModifier(hero, "modifier_alchemist_aghanims_scepter") then return true end
		if NPC.HasModifier(hero, "modifier_alchemist_aghanims_scepter_buff") then return true end
		if NPC.HasModifier(hero, "modifier_item_ultimate_scepter_consumed_alchemist") then return true end
	end
	return false
end

local function has_shard_effect(hero)
	local spire = get_spell(hero, spell_map["Ice Spire"])
	if spire and Ability and Ability.GetLevel then
		local ok_level, level = pcall(Ability.GetLevel, spire)
		if ok_level and type(level) == "number" and level > 0 then
			return true
		end
	end
	if NPC and NPC.GetItemByIndex and Ability and Ability.GetName then
		for i = 0, 20 do
			local item = NPC.GetItemByIndex(hero, i)
			if item then
				local ok_name, name = pcall(Ability.GetName, item)
				if ok_name and (name == "item_aghanims_shard" or name == "item_aghanims_shard_roshan") then
					return true
				end
			end
		end
	end
	return false
end

local function sinister_gaze_is_ground_aoe(hero)
	return has_agh_effect(hero)
end

local function get_sinister_gaze_radius(hero, ability)
	if not hero or not ability then return 0.0 end
	if not sinister_gaze_is_ground_aoe(hero) then return 0.0 end
	local radius = get_special_value(ability, "aoe_scepter")
	if type(radius) ~= "number" or radius <= 0.0 then
		radius = 400.0
	end
	return radius * (1.0 + get_aoe_increase_pct(hero))
end

local function get_effective_cast_range(hero, ability)
	if not hero or not ability then return 0.0 end
	local cast_range = 0.0
	if Ability and Ability.GetCastRange then
		local ok, value = pcall(Ability.GetCastRange, ability)
		if ok and type(value) == "number" then
			cast_range = value
		end
	end
	if cast_range <= 0.0 and Ability and Ability.GetLevelSpecialValueFor then
		local ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, "cast_range", -1)
		if ok and type(value) == "number" and value > 0 then
			cast_range = value
		else
			ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, "AbilityCastRange", -1)
			if ok and type(value) == "number" and value > 0 then
				cast_range = value
			end
		end
	end
	if cast_range > 0.0 and NPC and NPC.GetCastRangeBonus then
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

local function target_has_linkens(target)
	if not target or not NPC then return false end
	if NPC.GetItemByIndex and Ability and Ability.GetName then
		for i = 0, 20 do
			local item = NPC.GetItemByIndex(target, i)
			if item then
				local ok_name, name = pcall(Ability.GetName, item)
				if ok_name and name == "item_sphere" then
					if Ability.IsReady then
						local ok_ready, ready = pcall(Ability.IsReady, item)
						if ok_ready then return ready == true end
					end
					if Ability.GetCooldown then
						local ok_cd, cd = pcall(Ability.GetCooldown, item)
						if ok_cd and type(cd) == "number" then return cd <= 0.0 end
					end
					return true
				end
			end
		end
	end
	if NPC.HasModifier then
		if NPC.HasModifier(target, "modifier_item_sphere_target") then return true end
		if NPC.HasModifier(target, "modifier_item_sphere_target_buff") then return true end
	end
	return false
end

local function target_is_invalid(target)
	if not target or not Entity or not Entity.IsAlive or not Entity.IsAlive(target) then
		return true
	end
	if Entity.IsInvulnerable then
		local ok, inv = pcall(Entity.IsInvulnerable, target)
		if ok and inv then return true end
	end
	if NPC and NPC.IsDebuffImmune then
		local ok, immune = pcall(NPC.IsDebuffImmune, target)
		if ok and immune then return true end
	end
	if NPC and NPC.IsMagicImmune then
		local ok, immune = pcall(NPC.IsMagicImmune, target)
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

local function draw_line_between_positions(a_pos, b_pos, color, thickness)
	if not a_pos or not b_pos or not Render or not Render.WorldToScreen or not Render.Line then return end
	local a, a_ok = Render.WorldToScreen(a_pos)
	local b, b_ok = Render.WorldToScreen(b_pos)
	if not a_ok or not b_ok then return end
	Render.Line(a, b, color, thickness or 1.0)
end

local function draw_lock_line(hero, target, color)
	if not ui or not ui.draw_lock_line or not ui.draw_lock_line.Get or not ui.draw_lock_line:Get() then return end
	if not hero or not target or not Entity or not Entity.IsAlive then return end
	if not Entity.IsAlive(hero) or not Entity.IsAlive(target) then return end
	draw_line_between_positions(
		Entity.GetAbsOrigin(hero),
		Entity.GetAbsOrigin(target),
		color or LOCK_LINE_COLOR_CHASE,
		LOCK_LINE_THICKNESS
	)
end

local function draw_world_circle(pos, radius, color, thickness, steps)
	if not pos or not radius or radius <= 0.0 then return end
	if not Render or not Render.WorldToScreen or not Render.Line then return end
	local points = {}
	color = color or Color(255, 50, 50, 200)
	thickness = thickness or 1.0
	steps = steps or 32
	for i = 1, steps do
		local angle = (i / steps) * 2.0 * math.pi
		local x = pos.x + radius * math.cos(angle)
		local y = pos.y + radius * math.sin(angle)
		local screen_pos, on_screen = Render.WorldToScreen(Vector(x, y, pos.z))
		if on_screen then
			points[#points + 1] = screen_pos
		end
	end
	if #points < 2 then return end
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		Render.Line(a, b, color, thickness)
	end
end

local function append_unique_units(out, seen, units)
	if type(units) ~= "table" then return end
	for _, unit in ipairs(units) do
		if unit then
			local idx = Entity and Entity.GetIndex and Entity.GetIndex(unit) or nil
			if idx and not seen[idx] then
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
			"TEAM_FRIEND",
			"TEAM_BOTH",
			"TEAM_ALL",
		}
		for _, name in ipairs(team_type_names) do
			local tt = Enum.TeamType[name]
			if tt ~= nil then
				local ok, units = pcall(NPCs.InRadius, pos, radius, my_team, tt)
				if ok then append_unique_units(out, seen, units) end
				local ok2, units2 = pcall(NPCs.InRadius, pos, radius, my_team, tt, true, true)
				if ok2 then append_unique_units(out, seen, units2) end
			end
		end
	end

	if #out == 0 and NPCs and NPCs.GetAll then
		local ok_all, all_units = pcall(NPCs.GetAll)
		if ok_all and type(all_units) == "table" then
			for _, unit in ipairs(all_units) do
				if unit and Entity and Entity.IsAlive and Entity.IsAlive(unit) then
					local upos = Entity.GetAbsOrigin(unit)
					if distance2d(pos, upos) <= radius then
						local idx = Entity.GetIndex and Entity.GetIndex(unit) or nil
						if idx and not seen[idx] then
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

local function unit_owned_by(unit, owner)
	if not unit or not owner or not Entity then return false end
	local owned = nil
	if Entity.RecursiveGetOwner then
		local ok, value = pcall(Entity.RecursiveGetOwner, unit)
		if ok and value then owned = value end
	end
	if not owned and Entity.GetOwner then
		local ok, value = pcall(Entity.GetOwner, unit)
		if ok and value then owned = value end
	end
	if not owned then return false end
	if owned == owner then return true end
	if Entity.GetIndex and Entity.GetIndex(owned) == Entity.GetIndex(owner) then return true end
	return false
end

local function find_owned_ice_spire(hero, near_pos, search_radius)
	if not hero or not near_pos or not Entity then return nil end
	local my_team = Entity.GetTeamNum(hero)
	local best = nil
	local best_dist = search_radius or SPIRE_SEARCH_RADIUS
	local units = gather_units_in_radius(near_pos, search_radius or SPIRE_SEARCH_RADIUS, my_team)
	for _, unit in ipairs(units) do
		if unit and Entity.IsAlive(unit) and Entity.GetTeamNum(unit) == my_team then
			local name = get_unit_name(unit)
			if name == "npc_dota_lich_ice_spire" then
				local owned = unit_owned_by(unit, hero)
				if owned or best == nil then
					local dist = distance2d(near_pos, Entity.GetAbsOrigin(unit))
					if dist <= best_dist then
						best_dist = dist
						best = unit
					end
				end
			end
		end
	end
	if best then return best end
	if distance2d(Entity.GetAbsOrigin(hero), near_pos) > SPIRE_SEARCH_RADIUS then
		return find_owned_ice_spire(hero, Entity.GetAbsOrigin(hero), 900.0)
	end
	return nil
end

local function get_mouse_target_radius()
	local radius = tonumber(ui and ui.mouse_target_radius and ui.mouse_target_radius.Get and ui.mouse_target_radius:Get()) or 325
	if radius < 50 then radius = 50 end
	if radius > 2000 then radius = 2000 end
	return radius
end

local function collect_enemy_entries(hero, anchor_pos, radius)
	local entries = {}
	if not hero or not anchor_pos or not Heroes or not Heroes.InRadius then return entries end
	local my_team = Entity.GetTeamNum(hero)
	local enemies = Heroes.InRadius(anchor_pos, radius, my_team, Enum.TeamType.TEAM_ENEMY, true, true)
	for _, enemy in ipairs(enemies or {}) do
		if can_select_enemy(hero, enemy) then
			entries[#entries + 1] = {
				enemy = enemy,
				pos = Entity.GetAbsOrigin(enemy),
			}
		end
	end
	table.sort(entries, function(a, b)
		return distance2d(anchor_pos, a.pos) < distance2d(anchor_pos, b.pos)
	end)
	return entries
end

local function pick_primary_entry(entries, anchor_pos)
	local best = nil
	local best_dist = 99999.0
	for _, entry in ipairs(entries or {}) do
		local dist = distance2d(anchor_pos, entry.pos)
		if dist < best_dist then
			best_dist = dist
			best = entry
		end
	end
	return best
end

local function average_entry_positions(entries)
	if type(entries) ~= "table" or #entries == 0 then return nil end
	local sx, sy, sz = 0.0, 0.0, 0.0
	for _, entry in ipairs(entries) do
		local pos = entry.pos
		if pos then
			sx = sx + (pos.x or 0.0)
			sy = sy + (pos.y or 0.0)
			sz = sz + (pos.z or 0.0)
		end
	end
	local count = #entries
	return Vector(sx / count, sy / count, sz / count)
end

local function collect_cluster_hits(center, entries, radius)
	local hits = {}
	for _, entry in ipairs(entries or {}) do
		if distance2d(center, entry.pos) <= (radius + 0.5) then
			hits[#hits + 1] = entry
		end
	end
	return hits
end

local function choose_better_cluster(current, candidate)
	if not candidate then return current end
	if not current then return candidate end
	if candidate.count ~= current.count then
		return (candidate.count > current.count) and candidate or current
	end
	if math.abs(candidate.cursor_dist - current.cursor_dist) > 0.5 then
		return (candidate.cursor_dist < current.cursor_dist) and candidate or current
	end
	if math.abs(candidate.hero_dist - current.hero_dist) > 0.5 then
		return (candidate.hero_dist < current.hero_dist) and candidate or current
	end
	return current
end

local function evaluate_cluster_candidate(hero, anchor_pos, entries, radius, center)
	if not hero or not center then return nil end
	local hero_pos = Entity.GetAbsOrigin(hero)
	local best = nil

	local function try_center(pos)
		local hits = collect_cluster_hits(pos, entries, radius)
		if #hits == 0 then return end
		local primary = pick_primary_entry(hits, anchor_pos)
		if not primary or not primary.enemy then return end
		local candidate = {
			center = copy_vector(pos),
			entries = hits,
			primary = primary.enemy,
			count = #hits,
			cursor_dist = distance2d(anchor_pos, pos),
			hero_dist = distance2d(hero_pos, pos),
		}
		best = choose_better_cluster(best, candidate)
	end

	try_center(center)
	local refined = average_entry_positions(collect_cluster_hits(center, entries, radius))
	if refined then
		try_center(refined)
	end

	return best
end

local function choose_best_cluster(hero, anchor_pos, entries, radius)
	if not hero or not anchor_pos or type(entries) ~= "table" or #entries == 0 then return nil end
	local best = nil
	local candidates = {}

	local function push_candidate(pos)
		if not pos then return end
		candidates[#candidates + 1] = copy_vector(pos)
	end

	for _, entry in ipairs(entries) do
		push_candidate(entry.pos)
	end
	for i = 1, #entries do
		for j = i + 1, #entries do
			local a = entries[i].pos
			local b = entries[j].pos
			if distance2d(a, b) <= (radius * 2.0 + 1.0) then
				push_candidate(Vector((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5))
			end
		end
	end
	push_candidate(average_entry_positions(entries))
	push_candidate(anchor_pos)

	for _, candidate in ipairs(candidates) do
		best = choose_better_cluster(best, evaluate_cluster_candidate(hero, anchor_pos, entries, radius, candidate))
	end

	return best
end

local function is_bind_down(bind)
	return bind and bind.IsDown and bind:IsDown()
end

local function reset_combo(keep_waiting_release)
	combo_running = false
	if not keep_waiting_release then
		waiting_release = false
		combo_target = nil
		combo_mode = nil
		combo_anchor_pos = nil
		last_cluster = nil
		locked_cluster_center = nil
	end
	next_action_time = 0.0
	pending_confirm = nil
	step_done = {}
	last_ground_pos = nil
	last_spire_hint_pos = nil
	last_spire_hint_t = -1000.0
	gaze_channel_confirmed = false
end

local function start_combo(target, mode, anchor_pos, cluster)
	combo_target = target
	combo_mode = mode
	combo_anchor_pos = copy_vector(anchor_pos)
	combo_running = true
	waiting_release = false
	next_action_time = 0.0
	pending_confirm = nil
	step_done = {}
	last_ground_pos = nil
	last_spire_hint_pos = nil
	last_spire_hint_t = -1000.0
	last_cluster = cluster
	gaze_channel_confirmed = false
	locked_cluster_center = nil
	log_debug("Start combo mode=" .. tostring(mode))
end

local function issue_move_to_target(hero, target)
	if not hero or not target or not NPC or not NPC.MoveTo then return end
	local t = now_time()
	if (t - last_move_order_t) < MOVE_ORDER_COOLDOWN then return end
	last_move_order_t = t
	NPC.MoveTo(hero, Entity.GetAbsOrigin(target), false, false, false, true, "lich_spire_combo_move_target", true)
end

local function issue_move_to_ground(hero, pos)
	if not hero or not pos or not NPC or not NPC.MoveTo then return end
	local t = now_time()
	if (t - last_move_order_t) < MOVE_ORDER_COOLDOWN then return end
	if last_ground_pos and distance2d(last_ground_pos, pos) < GROUND_MOVE_MIN_DIST then
		return
	end
	last_move_order_t = t
	last_ground_pos = copy_vector(pos)
	NPC.MoveTo(hero, pos, false, false, false, true, "lich_spire_combo_move_ground", true)
end

local function get_combo_mode(hero)
	if not has_shard_effect(hero) then return nil end
	if has_agh_effect(hero) then return "scepter" end
	return "shard"
end

local function find_target_near_cursor(hero, cursor)
	if not hero or not cursor then return nil end
	local entries = collect_enemy_entries(hero, cursor, get_mouse_target_radius())
	local primary = pick_primary_entry(entries, cursor)
	return primary and primary.enemy or nil
end

local function find_initial_combo_selection(hero, mode, cursor)
	if not hero or not mode or not cursor then return nil, nil end
	if mode == "scepter" then
		local gaze = get_spell(hero, spell_map["Sinister Gaze"])
		local gaze_radius = get_sinister_gaze_radius(hero, gaze)
		if gaze_radius <= 0.0 then gaze_radius = 400.0 end
		local entries = collect_enemy_entries(hero, cursor, get_mouse_target_radius())
		local cluster = choose_best_cluster(hero, cursor, entries, gaze_radius)
		if cluster then
			return cluster.primary, cluster
		end
		return nil, nil
	end
	return find_target_near_cursor(hero, cursor), nil
end

local function get_step_key(name)
	return tostring(combo_mode or "combo") .. ":" .. tostring(name)
end

local function mark_step_done(name)
	step_done[get_step_key(name)] = true
end

local function is_step_done(name)
	return step_done[get_step_key(name)] == true
end

local function commit_step(step)
	if not step then return end
	step_done[step.key] = true
	if step.name == "Ice Spire" and step.cast_pos then
		last_spire_hint_pos = copy_vector(step.cast_pos)
		last_spire_hint_t = now_time()
	end
	if combo_mode == "scepter" and step.name == "Sinister Gaze" then
		gaze_channel_confirmed = true
		locked_cluster_center = step.cast_pos and copy_vector(step.cast_pos) or locked_cluster_center
	end
end

local function set_pending_confirmation(step, ability)
	local cast_point = get_cast_point_seconds(ability)
	local retry_delay = math.max(COOLDOWN_CONFIRM_GRACE, cast_point + COOLDOWN_CONFIRM_EXTRA)
	pending_confirm = {
		step = step,
		next_try_t = now_time() + retry_delay,
	}
end

local function handle_pending_confirmation(hero)
	if not pending_confirm then return false end
	local step = pending_confirm.step
	if not step then
		pending_confirm = nil
		return false
	end
	local ability = get_spell(hero, step.spell)
	if ability and is_cooldown_started(ability) then
		commit_step(step)
		pending_confirm = nil
		return true
	end
	if now_time() < (pending_confirm.next_try_t or 0.0) then
		return true
	end
	pending_confirm = nil
	return false
end

local function get_shard_spire_cast_pos(hero, target)
	if not hero or not target then return nil end
	local hero_pos = Entity.GetAbsOrigin(hero)
	local target_pos = Entity.GetAbsOrigin(target)
	if not hero_pos or not target_pos then return nil end
	local offset = tonumber(ui and ui.ice_spire_offset and ui.ice_spire_offset.Get and ui.ice_spire_offset:Get()) or 90.0
	if offset < 0.0 then offset = 0.0 end
	local dx = hero_pos.x - target_pos.x
	local dy = hero_pos.y - target_pos.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1.0 then
		return copy_vector(target_pos)
	end
	local nx = dx / len
	local ny = dy / len
	return Vector(target_pos.x + nx * offset, target_pos.y + ny * offset, target_pos.z)
end

local function build_combo_context(hero)
	if not hero or not combo_mode then return nil end
	local ctx = {
		mode = combo_mode,
		anchor_pos = combo_anchor_pos and copy_vector(combo_anchor_pos) or (Input and Input.GetWorldCursorPos and Input.GetWorldCursorPos() or nil),
		target = combo_target,
		cluster = nil,
		entries = {},
		spire = nil,
		spire_pos = nil,
		gaze_radius = 0.0,
	}
	if not ctx.anchor_pos then return ctx end

	ctx.entries = collect_enemy_entries(hero, ctx.anchor_pos, get_mouse_target_radius())

	if combo_mode == "scepter" then
		local gaze = get_spell(hero, spell_map["Sinister Gaze"])
		ctx.gaze_radius = get_sinister_gaze_radius(hero, gaze)
		if ctx.gaze_radius <= 0.0 then ctx.gaze_radius = 400.0 end
		if gaze_channel_confirmed and locked_cluster_center then
			local locked_hits = collect_cluster_hits(locked_cluster_center, ctx.entries, ctx.gaze_radius)
			local primary = pick_primary_entry(locked_hits, ctx.anchor_pos)
			ctx.cluster = {
				center = copy_vector(locked_cluster_center),
				entries = locked_hits,
				primary = primary and primary.enemy or combo_target,
				count = #locked_hits,
				cursor_dist = distance2d(ctx.anchor_pos, locked_cluster_center),
				hero_dist = distance2d(Entity.GetAbsOrigin(hero), locked_cluster_center),
			}
		else
			ctx.cluster = choose_best_cluster(hero, ctx.anchor_pos, ctx.entries, ctx.gaze_radius)
		end
		if ctx.cluster and ctx.cluster.primary then
			combo_target = ctx.cluster.primary
			ctx.target = combo_target
		end
		ctx.spire_pos = ctx.cluster and copy_vector(ctx.cluster.center) or (ctx.target and Entity.GetAbsOrigin(ctx.target) or ctx.anchor_pos)
	else
		ctx.spire_pos = ctx.target and get_shard_spire_cast_pos(hero, ctx.target) or nil
	end

	local spire_search_pos = last_spire_hint_pos or ctx.spire_pos or (ctx.target and Entity.GetAbsOrigin(ctx.target) or nil)
	if spire_search_pos then
		ctx.spire = find_owned_ice_spire(hero, spire_search_pos, SPIRE_SEARCH_RADIUS)
	end

	last_cluster = ctx.cluster
	return ctx
end

local function pick_chain_frost_target_for_cluster(cluster, spire)
	if not cluster then return spire end
	local ref_pos = spire and Entity.GetAbsOrigin(spire) or cluster.center
	local best_enemy = nil
	local best_dist = 99999.0
	for _, entry in ipairs(cluster.entries or {}) do
		if entry.enemy and not target_is_invalid(entry.enemy) and not target_has_linkens(entry.enemy) then
			local dist = distance2d(ref_pos, entry.pos)
			if dist < best_dist then
				best_dist = dist
				best_enemy = entry.enemy
			end
		end
	end
	return best_enemy or spire
end

local function pick_lowest_hp_enemy_without_linkens(entries)
	local best = nil
	local best_hp = 999999.0
	for _, entry in ipairs(entries or {}) do
		local enemy = entry.enemy
		if enemy and not target_is_invalid(enemy) and not target_has_linkens(enemy) then
			local hp = get_unit_health(enemy) or 999999.0
			if hp < best_hp then
				best_hp = hp
				best = enemy
			end
		end
	end
	return best
end

local function make_step(name, label, spell, ability, cast_mode, cast_target, cast_pos)
	return {
		key = get_step_key(name),
		name = name,
		label = label,
		spell = spell,
		ability = ability,
		cast_mode = cast_mode,
		cast_target = cast_target,
		cast_pos = cast_pos,
	}
end

local function get_shard_combo_step(hero, ctx)
	if not hero or not ctx or not ctx.target then return nil, "no_target" end

	if not is_step_done("Ice Spire") then
		local spell = spell_map["Ice Spire"]
		local ability = get_spell(hero, spell)
		if not ability or not is_spell_ready_and_castable(hero, ability) then
			mark_step_done("Ice Spire")
		else
			local pos = ctx.spire_pos or get_shard_spire_cast_pos(hero, ctx.target)
			if pos then
				return make_step("Ice Spire", "Ice Spire", spell, ability, "position", nil, pos), nil
			end
		end
	end

	if not is_step_done("Chain Frost") then
		local spell = spell_map["Chain Frost"]
		local ability = get_spell(hero, spell)
		if not ability or not is_spell_ready_and_castable(hero, ability) then
			mark_step_done("Chain Frost")
		else
			if target_has_linkens(ctx.target) then
				if ctx.spire then
					return make_step("Chain Frost", "Chain Frost", spell, ability, "target", ctx.spire, nil), nil
				end
				return nil, "need_spire_entity"
			end
			return make_step("Chain Frost", "Chain Frost", spell, ability, "target", ctx.target, nil), nil
		end
	end

	if not is_step_done("Frost Shield") then
		if not (ui and ui.use_frost_shield and ui.use_frost_shield.Get and ui.use_frost_shield:Get()) then
			mark_step_done("Frost Shield")
		else
			local spell = spell_map["Frost Shield"]
			local ability = get_spell(hero, spell)
			if not ability or not is_spell_ready_and_castable(hero, ability) then
				mark_step_done("Frost Shield")
			elseif ctx.spire then
				return make_step("Frost Shield", "Frost Shield", spell, ability, "target", ctx.spire, nil), nil
			else
				return nil, "need_spire_entity"
			end
		end
	end

	if not is_step_done("Frost Blast") then
		local spell = spell_map["Frost Blast"]
		local ability = get_spell(hero, spell)
		if not ability or not is_spell_ready_and_castable(hero, ability) then
			mark_step_done("Frost Blast")
		elseif target_has_linkens(ctx.target) then
			return nil, "wait_linkens_removed"
		else
			return make_step("Frost Blast", "Frost Blast", spell, ability, "target", ctx.target, nil), nil
		end
	end

	if not is_step_done("Sinister Gaze") then
		local spell = spell_map["Sinister Gaze"]
		local ability = get_spell(hero, spell)
		if not ability or not is_spell_ready_and_castable(hero, ability) then
			mark_step_done("Sinister Gaze")
		elseif target_has_linkens(ctx.target) then
			return nil, "wait_linkens_removed"
		else
			return make_step("Sinister Gaze", "Sinister Gaze", spell, ability, "target", ctx.target, nil), nil
		end
	end

	return nil, "complete"
end

local function get_scepter_combo_step(hero, ctx)
	if not hero or not ctx or not ctx.cluster or not ctx.cluster.center then return nil, "no_cluster" end

	if not is_step_done("Sinister Gaze") then
		local spell = spell_map["Sinister Gaze"]
		local ability = get_spell(hero, spell)
		if not ability or not is_spell_ready_and_castable(hero, ability) then
			mark_step_done("Sinister Gaze")
		else
			return make_step("Sinister Gaze", "Sinister Gaze", spell, ability, "position", nil, ctx.cluster.center), nil
		end
	end

	if not is_step_done("Ice Spire") then
		local spell = spell_map["Ice Spire"]
		local ability = get_spell(hero, spell)
		if not ability or not is_spell_ready_and_castable(hero, ability) then
			mark_step_done("Ice Spire")
		else
			return make_step("Ice Spire", "Ice Spire", spell, ability, "position", nil, ctx.cluster.center), nil
		end
	end

	if not is_step_done("Chain Frost") then
		local spell = spell_map["Chain Frost"]
		local ability = get_spell(hero, spell)
		if not ability or not is_spell_ready_and_castable(hero, ability) then
			mark_step_done("Chain Frost")
		else
			local target = pick_chain_frost_target_for_cluster(ctx.cluster, ctx.spire)
			if target then
				return make_step("Chain Frost", "Chain Frost", spell, ability, "target", target, nil), nil
			end
			if ctx.spire then
				return nil, "need_spire_entity"
			end
			mark_step_done("Chain Frost")
		end
	end

	if not is_step_done("Frost Blast") then
		local spell = spell_map["Frost Blast"]
		local ability = get_spell(hero, spell)
		if not ability or not is_spell_ready_and_castable(hero, ability) then
			mark_step_done("Frost Blast")
		else
			local target = pick_lowest_hp_enemy_without_linkens(ctx.cluster.entries)
			if target then
				return make_step("Frost Blast", "Frost Blast", spell, ability, "target", target, nil), nil
			end
			mark_step_done("Frost Blast")
		end
	end

	if not is_step_done("Frost Shield") then
		if not (ui and ui.use_frost_shield and ui.use_frost_shield.Get and ui.use_frost_shield:Get()) then
			mark_step_done("Frost Shield")
		else
			local spell = spell_map["Frost Shield"]
			local ability = get_spell(hero, spell)
			if not ability or not is_spell_ready_and_castable(hero, ability) then
				mark_step_done("Frost Shield")
			elseif ctx.spire then
				return make_step("Frost Shield", "Frost Shield", spell, ability, "target", ctx.spire, nil), nil
			else
				return nil, "need_spire_entity"
			end
		end
	end

	return nil, "complete"
end

local function get_next_combo_step(hero, ctx)
	if combo_mode == "scepter" then
		return get_scepter_combo_step(hero, ctx)
	end
	return get_shard_combo_step(hero, ctx)
end

local function is_step_in_range(hero, step)
	if not hero or not step or not step.ability then return false end
	local range = get_effective_cast_range(hero, step.ability)
	if range <= 0.0 then return true end
	local hero_pos = Entity.GetAbsOrigin(hero)
	if step.cast_mode == "position" then
		return distance2d(hero_pos, step.cast_pos) <= range
	end
	if step.cast_target and Entity and Entity.IsAlive and Entity.IsAlive(step.cast_target) then
		return distance2d(hero_pos, Entity.GetAbsOrigin(step.cast_target)) <= range
	end
	return false
end

local function move_for_step(hero, step, ctx)
	if not hero or not step then return end
	if step.cast_mode == "position" and step.cast_pos then
		issue_move_to_ground(hero, step.cast_pos)
		return
	end
	if step.cast_target then
		issue_move_to_target(hero, step.cast_target)
		return
	end
	if ctx and ctx.target then
		issue_move_to_target(hero, ctx.target)
	end
end

local function cast_step(hero, step)
	if not hero or not step or not step.ability then return false, "missing" end
	if not Ability or not Ability.IsReady or not Ability.IsCastable then return false, "api_unavailable" end
	if not Ability.IsReady(step.ability) then return false, "not_ready" end
	local mana = (NPC and NPC.GetMana and NPC.GetMana(hero)) or 0.0
	if not Ability.IsCastable(step.ability, mana) then return false, "not_castable" end
	if not is_step_in_range(hero, step) then
		return false, "out_of_range"
	end
	if step.cast_mode == "position" then
		if not Ability.CastPosition or not step.cast_pos then return false, "api_unavailable" end
		Ability.CastPosition(step.ability, step.cast_pos, false, false, false)
		return true, "cast"
	end
	if not step.cast_target or not Entity or not Entity.IsAlive or not Entity.IsAlive(step.cast_target) then
		return false, "invalid_target"
	end
	if not Ability.CastTarget then return false, "api_unavailable" end
	Ability.CastTarget(step.ability, step.cast_target, false, false, false)
	return true, "cast"
end

local function collect_scepter_range_requirements(hero, ctx)
	local reqs = {}
	if not hero or not ctx or not ctx.cluster then return reqs end

	local function push_pos(ability, pos)
		if ability and is_spell_ready_and_castable(hero, ability) and pos then
			reqs[#reqs + 1] = { kind = "position", ability = ability, pos = pos }
		end
	end

	local function push_target(ability, target)
		if ability and is_spell_ready_and_castable(hero, ability) and target then
			reqs[#reqs + 1] = { kind = "target", ability = ability, target = target }
		end
	end

	if not is_step_done("Sinister Gaze") then
		push_pos(get_spell(hero, spell_map["Sinister Gaze"]), ctx.cluster.center)
	end
	if not is_step_done("Ice Spire") then
		push_pos(get_spell(hero, spell_map["Ice Spire"]), ctx.cluster.center)
	end
	if not is_step_done("Chain Frost") then
		local cf = get_spell(hero, spell_map["Chain Frost"])
		local target = pick_chain_frost_target_for_cluster(ctx.cluster, ctx.spire)
		if target and get_unit_name(target) == "npc_dota_lich_ice_spire" then
			push_pos(cf, Entity.GetAbsOrigin(target))
		elseif target then
			push_target(cf, target)
		else
			push_pos(cf, ctx.cluster.center)
		end
	end
	if not is_step_done("Frost Blast") then
		push_target(get_spell(hero, spell_map["Frost Blast"]), pick_lowest_hp_enemy_without_linkens(ctx.cluster.entries))
	end
	if not is_step_done("Frost Shield") and ui and ui.use_frost_shield and ui.use_frost_shield.Get and ui.use_frost_shield:Get() then
		push_pos(get_spell(hero, spell_map["Frost Shield"]), ctx.cluster.center)
	end

	return reqs
end

local function scepter_combo_ready_now(hero, ctx)
	local reqs = collect_scepter_range_requirements(hero, ctx)
	local hero_pos = Entity.GetAbsOrigin(hero)
	for _, req in ipairs(reqs) do
		local range = get_effective_cast_range(hero, req.ability)
		if range > 0.0 then
			if req.kind == "position" then
				if distance2d(hero_pos, req.pos) > range then
					return false
				end
			elseif req.target and Entity and Entity.IsAlive and Entity.IsAlive(req.target) then
				if distance2d(hero_pos, Entity.GetAbsOrigin(req.target)) > range then
					return false
				end
			end
		end
	end
	return true
end

local function combo_ready_now(hero, ctx)
	if not hero or not ctx then return false end
	if combo_mode == "scepter" and not is_step_done("Sinister Gaze") then
		return scepter_combo_ready_now(hero, ctx)
	end
	local step = select(1, get_next_combo_step(hero, ctx))
	return step ~= nil and is_step_in_range(hero, step)
end

local menu_tab = Menu.Create("General", "My Scripts", "Lich Spire Combo", "LichSpireCombo")
local settings_group = menu_tab:Create("Settings")

ui = {}
ui.enabled = settings_group:Switch("Enable Combo", true)
ui.combo_key = settings_group:Bind("Combo Key", Enum.ButtonCode.KEY_SPACE)
ui.mouse_target_radius = settings_group:Slider("Mouse Target Radius", 50, 1200, 325)
ui.ice_spire_offset = settings_group:Slider("Shard Spire Offset", 0, 250, 90)
ui.use_frost_shield = settings_group:Switch("Use Frost Shield On Spire", true)
ui.draw_mouse_radius = settings_group:Switch("Draw Mouse Radius", true)
ui.draw_lock_line = settings_group:Switch("Draw Lock Line", true)
ui.draw_calc_geometry = settings_group:Switch("Draw Calculated AOE", true)
ui.debug_logs = settings_group:Switch("Debug Logs", false)

settings_group:Label("Hold the combo key near enemies to lock the closest Lich combo target to your mouse area.")
settings_group:Label("With Shard+Scepter, the script locks the area and finds the best Sinister Gaze center.")
settings_group:Label("Shard Spire Offset places Ice Spire next to the target toward Lich in shard-only mode.")

function lich_spire_combo.OnUpdate()
	if not ui.enabled:Get() then return end

	local hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
	if not hero or not Entity or not Entity.IsAlive or not Entity.IsAlive(hero) or not is_lich(hero) then
		reset_combo(false)
		was_key_down = false
		return
	end

	local down = is_bind_down(ui.combo_key)
	if not down then
		if was_key_down then
			reset_combo(false)
		end
		was_key_down = false
		return
	end

	local available_mode = get_combo_mode(hero)
	if not available_mode then
		was_key_down = true
		return
	end

	if waiting_release then
		was_key_down = true
		return
	end

	if not combo_running then
		local cursor = Input and Input.GetWorldCursorPos and Input.GetWorldCursorPos() or nil
		local target, cluster = find_initial_combo_selection(hero, available_mode, cursor)
		if not target then
			was_key_down = true
			return
		end
		start_combo(target, available_mode, cursor, cluster)
	end

	if not combo_target or not Entity.IsAlive(combo_target) then
		reset_combo(false)
		was_key_down = true
		return
	end

	if target_is_invalid(combo_target) then
		log_debug("Target became invalid")
		reset_combo(false)
		was_key_down = true
		return
	end

	local t = now_time()
	if t < next_action_time then
		was_key_down = true
		return
	end

	local ctx = build_combo_context(hero)
	if not ctx then
		was_key_down = true
		return
	end

	if combo_mode == "scepter" then
		if not ctx.cluster or not ctx.target then
			reset_combo(false)
			was_key_down = true
			return
		end
		combo_target = ctx.target
	end

	if pending_confirm and handle_pending_confirmation(hero) then
		was_key_down = true
		return
	end

	if combo_mode == "scepter" and not is_step_done("Sinister Gaze") and not scepter_combo_ready_now(hero, ctx) then
		issue_move_to_ground(hero, ctx.cluster and ctx.cluster.center or Entity.GetAbsOrigin(combo_target))
		was_key_down = true
		return
	end

	local step, reason = get_next_combo_step(hero, ctx)
	if not step then
		if reason == "complete" then
			combo_running = false
			waiting_release = true
			log_debug("Combo complete")
		end
		was_key_down = true
		return
	end

	local ok_cast, cast_reason = cast_step(hero, step)
	if ok_cast then
		if step.name == "Ice Spire" and step.cast_pos then
			last_spire_hint_pos = copy_vector(step.cast_pos)
			last_spire_hint_t = t
		end
		local cast_point = get_cast_point_seconds(step.ability)
		next_action_time = t + math.max(CAST_GAP_SECONDS, cast_point)
		if is_cooldown_started(step.ability) or step.name == "Ice Spire" or (combo_mode == "scepter" and step.name == "Sinister Gaze") then
			commit_step(step)
		else
			set_pending_confirmation(step, step.ability)
		end
		log_debug("Cast " .. tostring(step.label))
	else
		if cast_reason == "out_of_range" then
			if gaze_channel_confirmed then
				step_done[step.key] = true
				log_debug("Skip " .. tostring(step.label) .. " (out of range during gaze)")
			else
				move_for_step(hero, step, ctx)
			end
		elseif cast_reason == "invalid_target" then
			step_done[step.key] = true
		else
			log_debug("Step blocked: " .. tostring(step.label) .. " => " .. tostring(cast_reason))
		end
	end

	was_key_down = true
end

function lich_spire_combo.OnDraw()
	if not ui.enabled:Get() then return end
	local hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
	if not hero or not is_lich(hero) then return end

	local down = is_bind_down(ui.combo_key)
	if not down then return end

	local draw_anchor = combo_running and combo_anchor_pos or (Input and Input.GetWorldCursorPos and Input.GetWorldCursorPos() or nil)
	if draw_anchor and ui.draw_mouse_radius and ui.draw_mouse_radius.Get and ui.draw_mouse_radius:Get() then
		draw_world_circle(draw_anchor, get_mouse_target_radius(), Color(255, 210, 90, 220), 1.5, 36)
	end

	local draw_cluster = last_cluster
	if not draw_cluster and not combo_running then
		local mode = get_combo_mode(hero)
		if mode == "scepter" and draw_anchor then
			local gaze = get_spell(hero, spell_map["Sinister Gaze"])
			local gaze_radius = get_sinister_gaze_radius(hero, gaze)
			if gaze_radius <= 0.0 then gaze_radius = 400.0 end
			draw_cluster = choose_best_cluster(hero, draw_anchor, collect_enemy_entries(hero, draw_anchor, get_mouse_target_radius()), gaze_radius)
		end
	end

	if ui.draw_calc_geometry and ui.draw_calc_geometry.Get and ui.draw_calc_geometry:Get() then
		if draw_cluster and draw_cluster.center then
			local gaze = get_spell(hero, spell_map["Sinister Gaze"])
			local radius = get_sinister_gaze_radius(hero, gaze)
			if radius <= 0.0 then radius = 400.0 end
			draw_world_circle(draw_cluster.center, radius, Color(90, 180, 255, 220), 1.5, 40)
			draw_world_circle(draw_cluster.center, 45.0, Color(140, 220, 255, 220), 1.0, 24)
			for _, entry in ipairs(draw_cluster.entries or {}) do
				draw_line_between_positions(draw_cluster.center, entry.pos, Color(120, 220, 255, 140), 1.0)
			end
		elseif combo_running and combo_mode == "shard" and combo_target and Entity.IsAlive(combo_target) then
			local spire_pos = get_shard_spire_cast_pos(hero, combo_target)
			if spire_pos then
				draw_world_circle(spire_pos, 70.0, Color(90, 180, 255, 220), 1.5, 28)
			end
		end
	end

	if combo_target and Entity.IsAlive(combo_target) then
		local ctx = build_combo_context(hero)
		local ready = combo_ready_now(hero, ctx)
		draw_lock_line(hero, combo_target, ready and LOCK_LINE_COLOR_READY or LOCK_LINE_COLOR_CHASE)
	end
end

return lich_spire_combo
