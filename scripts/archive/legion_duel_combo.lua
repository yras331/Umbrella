---@diagnostic disable: undefined-global

local legion_duel_combo = {}

local ui
local compute_required_combo_range
local can_select_target_for_combo

local SCRIPT_TAG = "[Legion Duel Combo]"
local ORDER_UI_CONFIG_NAME = "legion_duel_combo"
local LOCK_LINE_COLOR_READY = Color(80, 255, 110, 230)
local LOCK_LINE_COLOR_CHASE = Color(255, 70, 70, 230)
local LOCK_LINE_THICKNESS = 4.0

local CAST_GAP_SECONDS = 0.015
local COOLDOWN_CONFIRM_GRACE = 0.08
local COOLDOWN_CONFIRM_EXTRA = 0.15
local TARGET_SEARCH_COOLDOWN = 0.03
local MOVE_ORDER_COOLDOWN = 0.08
local GROUND_MOVE_MIN_DIST = 50.0
local BLINK_RANGE_BUFFER = 25.0

local combo_running = false
local waiting_release = false
local was_key_down = false
local combo_target = nil
local combo_allow_blink = true
local next_action_time = 0.0
local last_target_search_t = -1000.0
local last_move_order_t = -1000.0
local last_ground_pos = nil
local pending_confirm = nil
local step_done = {}

local pre_duel_enabled_names = nil
local linkens_break_enabled_names = nil

local PRE_DUEL_ITEMS = {
	"Bloodthorn",
	"Orchid",
	"Nullifier",
	"Sheep Stick",
	"Abyssal Blade",
	"Heaven's Halberd",
	"Rod of Atos",
	"Diffusal / Disperser",
	"Dagon",
	"Harpoon",
}

local DEFAULT_PRE_DUEL_ENABLED = {
	"Bloodthorn",
	"Orchid",
	"Nullifier",
	"Sheep Stick",
	"Abyssal Blade",
	"Heaven's Halberd",
}

local LINKENS_BREAK_ITEMS = {
	"Bloodthorn",
	"Orchid",
	"Nullifier",
	"Sheep Stick",
	"Rod of Atos",
	"Abyssal Blade",
	"Heaven's Halberd",
	"Diffusal / Disperser",
	"Dagon",
	"Harpoon",
}

local DEFAULT_LINKENS_BREAK_ENABLED = {
	"Bloodthorn",
	"Orchid",
	"Nullifier",
	"Sheep Stick",
	"Rod of Atos",
	"Abyssal Blade",
	"Heaven's Halberd",
	"Diffusal / Disperser",
	"Harpoon",
}

local spell_map = {
	["Bloodthorn"] = { name = "item_bloodthorn", kind = "item", cast = "target" },
	["Orchid"] = { name = "item_orchid", kind = "item", cast = "target" },
	["Nullifier"] = { name = "item_nullifier", kind = "item", cast = "target" },
	["Sheep Stick"] = { name = "item_sheepstick", kind = "item", cast = "target" },
	["Abyssal Blade"] = { name = "item_abyssal_blade", kind = "item", cast = "target" },
	["Heaven's Halberd"] = { name = "item_heavens_halberd", kind = "item", cast = "target" },
	["Rod of Atos"] = {
		name = "item_rod_of_atos",
		kind = "item",
		cast = "target",
		aliases = { "item_gleipnir", "item_gungir" },
	},
	["Diffusal / Disperser"] = {
		name = "item_diffusal_blade",
		kind = "item",
		cast = "target",
		aliases = { "item_disperser" },
	},
	["Dagon"] = { name = "item_dagon", kind = "item", cast = "target", dagon = true },
	["Harpoon"] = { name = "item_harpoon", kind = "item", cast = "target" },
	["Blade Mail"] = { name = "item_blade_mail", kind = "item", cast = "no_target" },
	["Duel"] = { name = "legion_commander_duel", kind = "ability", cast = "target" },
	["Blink"] = {
		name = "item_blink",
		kind = "item",
		cast = "position",
		aliases = { "item_overwhelming_blink", "item_swift_blink", "item_arcane_blink" },
	},
}

local LINKENS_READY_MODIFIERS = {
	"modifier_item_sphere_target",
	"modifier_item_sphere_target_buff",
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

local function split_csv(s)
	if type(s) ~= "string" or s == "" then return {} end
	local out = {}
	for token in string.gmatch(s, "[^,]+") do
		token = tostring(token):gsub("^%s+", ""):gsub("%s+$", "")
		if token ~= "" then
			out[#out + 1] = token
		end
	end
	return out
end

local function list_to_set(list)
	local set = {}
	if type(list) ~= "table" then return set end
	for _, value in ipairs(list) do
		if value ~= nil then
			set[value] = true
		end
	end
	return set
end

local function resolve_multiselect_image_path(name_id)
	local meta = spell_map[name_id]
	if not meta or not meta.name then return "" end
	if meta.kind == "item" then
		local item_short = tostring(meta.name):gsub("^item_", "")
		return "panorama/images/items/" .. item_short .. "_png.vtex_c"
	end
	return "panorama/images/spellicons/" .. tostring(meta.name) .. "_png.vtex_c"
end

local function build_multiselect_items(order_list, enabled_set, fallback_items)
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
	for _, name_id in ipairs(fallback_items) do
		push(name_id)
	end
	return items
end

local function distance2d(a, b)
	if not a or not b then return 99999.0 end
	local dx = (a.x or 0.0) - (b.x or 0.0)
	local dy = (a.y or 0.0) - (b.y or 0.0)
	return math.sqrt(dx * dx + dy * dy)
end

local function get_local_player()
	if Players and Players.GetLocal then
		return Players.GetLocal()
	end
	return nil
end

local function is_bind_down(bind)
	if not bind or not bind.Get then return false end
	local key = bind:Get()
	if not key or key == Enum.ButtonCode.BUTTON_CODE_INVALID then return false end
	return Input.IsKeyDown(key)
end

local function stop_hero_orders()
	local player = get_local_player()
	local hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
	if not player or not hero then return end
	if not Player or not Player.PrepareUnitOrders or not Enum or not Enum.UnitOrder or not Enum.PlayerOrderIssuer then
		return
	end
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
		"legion_duel_combo_stop",
		true
	)
end

local function draw_lock_line(hero, target, color)
	if not ui or not ui.draw_lock_line or not ui.draw_lock_line.Get or not ui.draw_lock_line:Get() then return end
	if not hero or not target or not Render or not Render.WorldToScreen or not Render.Line then return end
	local hero_pos = Entity.GetAbsOrigin(hero)
	local target_pos = Entity.GetAbsOrigin(target)
	if not hero_pos or not target_pos then return end
	hero_pos = Vector(hero_pos.x, hero_pos.y, (hero_pos.z or 0.0) + 80.0)
	target_pos = Vector(target_pos.x, target_pos.y, (target_pos.z or 0.0) + 80.0)
	local a, a_vis = Render.WorldToScreen(hero_pos)
	local b, b_vis = Render.WorldToScreen(target_pos)
	if not a_vis or not b_vis then return end
	Render.Line(a, b, color or LOCK_LINE_COLOR_CHASE, LOCK_LINE_THICKNESS)
end

local function draw_world_circle(pos, radius, color, thickness, steps)
	if not pos or not radius or radius <= 0.0 then return end
	if not Render or not Render.WorldToScreen or not Render.Line then return end
	local points = {}
	steps = steps or 36
	thickness = thickness or 1.0
	color = color or Color(255, 255, 255, 200)
	local z = pos.z or 0.0
	for i = 1, steps do
		local angle = (i / steps) * 2.0 * math.pi
		local x = pos.x + radius * math.cos(angle)
		local y = pos.y + radius * math.sin(angle)
		local screen_pos, on_screen = Render.WorldToScreen(Vector(x, y, z))
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

local function band_int(a, b)
	if type(a) ~= "number" or type(b) ~= "number" then return 0 end
	if bit and bit.band then return bit.band(a, b) end
	if bit32 and bit32.band then return bit32.band(a, b) end
	a = math.floor(a)
	b = math.floor(b)
	local res = 0
	local bitval = 1
	while a > 0 and b > 0 do
		local abit = a % 2
		local bbit = b % 2
		if abit == 1 and bbit == 1 then
			res = res + bitval
		end
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

local function get_ability_behavior(ability)
	if not ability or not Ability or not Ability.GetBehavior then return nil end
	local ok, behavior = pcall(Ability.GetBehavior, ability, true)
	if ok and type(behavior) == "number" then return behavior end
	ok, behavior = pcall(Ability.GetBehavior, ability)
	if ok and type(behavior) == "number" then return behavior end
	return nil
end

local function ability_has_unit_target_behavior(ability)
	local behavior = get_ability_behavior(ability)
	if behavior == nil or not Enum or not Enum.AbilityBehavior then return true end
	return has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_UNIT_TARGET)
		or has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_OPTIONAL_UNIT_TARGET)
end

local function ability_is_point_only(ability)
	local behavior = get_ability_behavior(ability)
	if behavior == nil or not Enum or not Enum.AbilityBehavior then return false end
	local is_point = has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_POINT)
		or has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_OPTIONAL_POINT)
		or has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_LAST_RESORT_POINT)
	local is_unit = has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_UNIT_TARGET)
		or has_behavior_flag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_OPTIONAL_UNIT_TARGET)
	return is_point and (not is_unit)
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

local function read_special_value(ability, key)
	if not ability or not key or not Ability then return nil end
	if Ability.GetSpecialValueFor then
		local ok, value = pcall(Ability.GetSpecialValueFor, ability, key, -1)
		if ok and type(value) == "number" and value > 0 then return value end
		ok, value = pcall(Ability.GetSpecialValueFor, ability, key)
		if ok and type(value) == "number" and value > 0 then return value end
	end
	if Ability.GetLevelSpecialValueFor then
		local ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, key, -1)
		if ok and type(value) == "number" and value > 0 then return value end
		ok, value = pcall(Ability.GetLevelSpecialValueFor, ability, key)
		if ok and type(value) == "number" and value > 0 then return value end
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
	if cast_range <= 0.0 and spell and spell.name == "legion_commander_duel" then
		cast_range = 200.0
	end
	if cast_range <= 0.0 and spell and spell.name == "item_blink" then
		cast_range = 1200.0
	end
	if NPC and NPC.GetCastRangeBonus and hero and cast_range > 0.0 and spell and spell.cast ~= "position" then
		cast_range = cast_range + (NPC.GetCastRangeBonus(hero) or 0.0)
	end
	return cast_range
end

local function is_backpack_index(i)
	return type(i) == "number" and i >= 6 and i <= 8
end

local function spell_name_matches(spell, item_name)
	if not spell or not item_name then return false end
	if item_name == spell.name then return true end
	if spell.dagon and type(item_name) == "string" and item_name:find("^item_dagon") then
		return true
	end
	if type(spell.aliases) == "table" then
		for _, alias in ipairs(spell.aliases) do
			if alias == item_name then return true end
		end
	end
	return false
end

local function get_spell(owner, spell)
	if not owner or not spell or not NPC then return nil, "missing" end
	if spell.kind == "ability" then
		return NPC.GetAbility(owner, spell.name), "ability"
	end
	local found_in_backpack = false
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(owner, i)
		if item then
			local item_name = Ability and Ability.GetName and Ability.GetName(item) or nil
			if spell_name_matches(spell, item_name) then
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

local function target_has_enrage(target)
	if not target or not NPC or not NPC.HasModifier then return false end
	return NPC.HasModifier(target, "modifier_ursa_enrage")
end

local function target_is_forbidden(target)
	if not target or not Entity or not Entity.IsAlive or not Entity.IsAlive(target) then return true end
	if Entity.IsInvulnerable then
		local ok, invulnerable = pcall(Entity.IsInvulnerable, target)
		if ok and invulnerable then return true end
	end
	if target_has_enrage(target) then return true end
	return false
end

local function target_blocks_optional_target_items(target)
	if not target or not NPC then return false end
	if NPC.IsDebuffImmune then
		local ok, immune = pcall(NPC.IsDebuffImmune, target)
		if ok and immune then return true end
	end
	if NPC.IsMagicImmune then
		local ok, immune = pcall(NPC.IsMagicImmune, target)
		if ok and immune then return true end
	end
	return false
end

local function target_has_linkens(target)
	if not target or not NPC then return false end
	if NPC.GetItemByIndex and Ability and Ability.GetName then
		for i = 0, 20 do
			local item = NPC.GetItemByIndex(target, i)
			if item then
				local ok_name, item_name = pcall(Ability.GetName, item)
				if ok_name and item_name == "item_sphere" then
					if Ability.IsReady then
						local ok_ready, ready = pcall(Ability.IsReady, item)
						if ok_ready then return ready == true end
					end
					local cooldown = get_cooldown_remaining_seconds(item)
					return (cooldown == nil) or (cooldown <= 0.0)
				end
			end
		end
	end
	if NPC.HasModifier then
		for _, modifier_name in ipairs(LINKENS_READY_MODIFIERS) do
			if NPC.HasModifier(target, modifier_name) then return true end
		end
	end
	return false
end

local function get_enabled_names_from_multiselect(multiselect, cache)
	if type(cache) == "table" and #cache > 0 then
		return cache
	end
	if not multiselect or not multiselect.List or not multiselect.Get then
		return {}
	end
	local ok_list, ids = pcall(multiselect.List, multiselect)
	if not ok_list or type(ids) ~= "table" then return {} end
	local enabled = {}
	for _, id in ipairs(ids) do
		local ok_get, is_on = pcall(multiselect.Get, multiselect, id)
		if ok_get and is_on then
			enabled[#enabled + 1] = id
		end
	end
	return enabled
end

local function get_pre_duel_order()
	return get_enabled_names_from_multiselect(ui and ui.pre_duel_order, pre_duel_enabled_names)
end

local function get_linkens_break_order()
	return get_enabled_names_from_multiselect(ui and ui.linkens_breaker, linkens_break_enabled_names)
end

local function reset_combo(keep_waiting_release)
	combo_running = false
	if not keep_waiting_release then
		waiting_release = false
		combo_target = nil
	end
	combo_allow_blink = true
	next_action_time = 0.0
	pending_confirm = nil
	step_done = {}
	last_ground_pos = nil
end

local function start_combo(target, allow_blink)
	combo_target = target
	combo_running = true
	waiting_release = false
	combo_allow_blink = (allow_blink ~= false)
	next_action_time = 0.0
	pending_confirm = nil
	step_done = {}
	log_debug("Start combo")
end

local function issue_move_to_target(hero, target)
	if not hero or not target or not NPC or not NPC.MoveTo then return end
	local t = now_time()
	if (t - last_move_order_t) < MOVE_ORDER_COOLDOWN then return end
	last_move_order_t = t
	NPC.MoveTo(hero, Entity.GetAbsOrigin(target), false, false, false, true, "legion_duel_combo_move", true)
end

local function issue_move_to_ground(hero, pos)
	if not hero or not pos or not NPC or not NPC.MoveTo then return end
	local t = now_time()
	if (t - last_move_order_t) < MOVE_ORDER_COOLDOWN then return end
	if last_ground_pos and last_ground_pos.Distance and last_ground_pos:Distance(pos) < GROUND_MOVE_MIN_DIST then
		return
	end
	last_move_order_t = t
	last_ground_pos = pos
	NPC.MoveTo(hero, pos, false, false, false, true, "legion_duel_combo_ground", true)
end

local function find_target_near_cursor()
	local hero = Heroes and Heroes.GetLocal and Heroes.GetLocal() or nil
	if not hero then return nil end
	local cursor = Input and Input.GetWorldCursorPos and Input.GetWorldCursorPos() or nil
	if not cursor then return nil end
	local my_team = Entity.GetTeamNum(hero)
	local radius = tonumber(ui.mouse_target_radius and ui.mouse_target_radius.Get and ui.mouse_target_radius:Get()) or 325
	if radius < 50 then radius = 50 end
	if radius > 2000 then radius = 2000 end
	local enemies = Heroes.InRadius(cursor, radius, my_team, Enum.TeamType.TEAM_ENEMY, true, true)
	if not enemies or #enemies == 0 then return nil end
	local best = nil
	local best_dist = radius
	for _, enemy in ipairs(enemies) do
		if enemy and enemy ~= hero and Entity.IsAlive(enemy) and Entity.GetTeamNum(enemy) ~= my_team then
			local is_illusion = false
			if NPC and NPC.IsIllusion then
				local ok_illusion, value = pcall(NPC.IsIllusion, enemy)
				if ok_illusion and value then
					is_illusion = true
				end
			end
			if not is_illusion and not target_is_forbidden(enemy) and can_select_target_for_combo and can_select_target_for_combo(hero, enemy, cursor) then
				local dist = cursor:Distance(Entity.GetAbsOrigin(enemy))
				if dist < best_dist then
					best_dist = dist
					best = enemy
				end
			end
		end
	end
	return best
end

local function get_target_facing_dir(target)
	if not target or not Entity or not Entity.GetRotation then return nil end
	local ok, rotation = pcall(Entity.GetRotation, target)
	if not ok or not rotation or not rotation.GetForward then return nil end
	local forward = rotation:GetForward()
	if not forward or not forward.Length2D then return nil end
	local len = forward:Length2D()
	if not len or len < 0.001 then return nil end
	return forward:Normalized()
end

local function get_blink_position(hero_pos, target, target_pos, desired_range)
	if not hero_pos or not target_pos then return nil end
	local facing = get_target_facing_dir(target)
	local offset = tonumber(ui and ui.blink_forward_offset and ui.blink_forward_offset.Get and ui.blink_forward_offset:Get()) or 0.0
	if offset < 0.0 then offset = 0.0 end
	if desired_range > 0.0 then
		offset = math.min(offset, math.max(0.0, desired_range - BLINK_RANGE_BUFFER))
	end
	if not facing then
		return Vector(target_pos.x, target_pos.y, target_pos.z)
	end
	return Vector(
		target_pos.x + facing.x * offset,
		target_pos.y + facing.y * offset,
		target_pos.z
	)
end

local function cast_fast(hero, ability, spell, target_or_pos)
	if not hero or not ability or not spell then return false, "missing" end
	if not Ability or not Ability.IsReady or not Ability.IsCastable then return false, "api_unavailable" end
	if not Ability.IsReady(ability) then return false, "not_ready" end
	local mana = (NPC and NPC.GetMana and NPC.GetMana(hero)) or 0.0
	if not Ability.IsCastable(ability, mana) then return false, "not_castable" end
	if spell.cast == "no_target" then
		if not Ability.CastNoTarget then return false, "api_unavailable" end
		Ability.CastNoTarget(ability, false, false, false)
		return true, "cast"
	end

	local cast_range = get_cast_range(hero, ability, spell)

	if spell.cast == "position" then
		if not target_or_pos then return false, "no_position" end
		if cast_range > 0.0 and NPC and NPC.IsPositionInRange and not NPC.IsPositionInRange(hero, target_or_pos, cast_range) then
			return false, "out_of_range"
		end
		if not Ability.CastPosition then return false, "api_unavailable" end
		Ability.CastPosition(ability, target_or_pos, false, false, false)
		return true, "cast"
	end

	local target = target_or_pos
	if not target or not Entity or not Entity.IsAlive or not Entity.IsAlive(target) then return false, "invalid_target" end

	if ability_is_point_only(ability) then
		local pos = Entity.GetAbsOrigin(target)
		if cast_range > 0.0 and NPC and NPC.IsPositionInRange and not NPC.IsPositionInRange(hero, pos, cast_range) then
			return false, "out_of_range"
		end
		if not Ability.CastPosition then return false, "api_unavailable" end
		Ability.CastPosition(ability, pos, false, false, false)
		return true, "cast"
	end

	if cast_range > 0.0 and NPC and NPC.IsEntityInRange and not NPC.IsEntityInRange(hero, target, cast_range) then
		return false, "out_of_range"
	end
	if not Ability.CastTarget then return false, "api_unavailable" end
	Ability.CastTarget(ability, target, false, false, false)
	return true, "cast"
end

local function is_spell_ready_and_castable(hero, ability)
	if not hero or not ability or not Ability or not Ability.IsReady or not Ability.IsCastable then return false end
	if not Ability.IsReady(ability) then return false end
	local mana = (NPC and NPC.GetMana and NPC.GetMana(hero)) or 0.0
	return Ability.IsCastable(ability, mana)
end

local function is_spell_in_cast_range(hero, target, ability, spell)
	if not hero or not target or not ability or not spell then return false end
	if spell.cast == "no_target" then return true end
	local cast_range = get_cast_range(hero, ability, spell)
	if cast_range <= 0.0 then return true end

	if spell.cast == "position" or ability_is_point_only(ability) then
		local pos = Entity and Entity.GetAbsOrigin and Entity.GetAbsOrigin(target) or nil
		if not pos then return false end
		if NPC and NPC.IsPositionInRange then
			return NPC.IsPositionInRange(hero, pos, cast_range)
		end
		local hero_pos = Entity and Entity.GetAbsOrigin and Entity.GetAbsOrigin(hero) or nil
		return hero_pos and distance2d(hero_pos, pos) <= cast_range
	end

	if NPC and NPC.IsEntityInRange then
		return NPC.IsEntityInRange(hero, target, cast_range)
	end
	local hero_pos = Entity and Entity.GetAbsOrigin and Entity.GetAbsOrigin(hero) or nil
	local target_pos = Entity and Entity.GetAbsOrigin and Entity.GetAbsOrigin(target) or nil
	return hero_pos and target_pos and distance2d(hero_pos, target_pos) <= cast_range
end

local function get_ready_linkens_breaker_max_range(hero, target)
	if not hero or not target then return nil end
	if target_blocks_optional_target_items(target) then return nil end
	local max_range = nil
	for _, name_id in ipairs(get_linkens_break_order()) do
		local spell = spell_map[name_id]
		if spell then
			local ability = get_spell(hero, spell)
			if ability and is_spell_ready_and_castable(hero, ability) and ability_has_unit_target_behavior(ability) then
				local cast_range = get_cast_range(hero, ability, spell)
				if cast_range <= 0.0 then
					max_range = max_range or 0.0
				elseif not max_range or cast_range > max_range then
					max_range = cast_range
				end
			end
		end
	end
	return max_range
end

local function get_ready_pre_duel_max_range(hero, target, ignore_step_state)
	if not hero or not target or target_blocks_optional_target_items(target) then return nil end
	local max_range = nil
	for _, name_id in ipairs(get_pre_duel_order()) do
		if ignore_step_state or not step_done[name_id] then
			local spell = spell_map[name_id]
			local ability = spell and get_spell(hero, spell) or nil
			if ability and is_spell_ready_and_castable(hero, ability) and spell.cast ~= "no_target" then
				local cast_range = get_cast_range(hero, ability, spell)
				if cast_range <= 0.0 then
					max_range = max_range or 0.0
				elseif not max_range or cast_range > max_range then
					max_range = cast_range
				end
			end
		end
	end
	return max_range
end

local function pick_linkens_breaker(hero, target, require_in_range)
	if not hero or not target then return nil end
	if target_blocks_optional_target_items(target) then
		return nil
	end
	for _, name_id in ipairs(get_linkens_break_order()) do
		local spell = spell_map[name_id]
		if spell then
			local ability = get_spell(hero, spell)
			if ability and is_spell_ready_and_castable(hero, ability) and ability_has_unit_target_behavior(ability) then
				local step = {
					key = "linkens",
					label = name_id,
					spell = spell,
					ability = ability,
					category = "linkens",
				}
				if (not require_in_range) or is_spell_in_cast_range(hero, target, ability, spell) then
					return step
				end
			end
		end
	end
	return nil
end

local function get_next_pre_duel_step(hero, target, require_in_range)
	if not hero then return nil end
	for _, name_id in ipairs(get_pre_duel_order()) do
		if not step_done[name_id] then
			local spell = spell_map[name_id]
			if not spell or target_blocks_optional_target_items(target) then
				step_done[name_id] = true
			else
				local ability = get_spell(hero, spell)
				if not ability or not is_spell_ready_and_castable(hero, ability) then
					step_done[name_id] = true
				else
					local step = {
						key = name_id,
						label = name_id,
						spell = spell,
						ability = ability,
						category = "pre_duel",
					}
					if (not require_in_range) or is_spell_in_cast_range(hero, target, ability, spell) then
						return step
					end
				end
			end
		end
	end
	return nil
end

local function get_blade_mail_step(hero)
	if not ui or not ui.use_blade_mail or not ui.use_blade_mail.Get or not ui.use_blade_mail:Get() then
		step_done["Blade Mail"] = true
		return nil
	end
	if step_done["Blade Mail"] then return nil end
	local spell = spell_map["Blade Mail"]
	local ability = get_spell(hero, spell)
	if not ability or not is_spell_ready_and_castable(hero, ability) then
		step_done["Blade Mail"] = true
		return nil
	end
	return {
		key = "Blade Mail",
		label = "Blade Mail",
		spell = spell,
		ability = ability,
		category = "blade_mail",
	}
end

local function get_duel_step(hero)
	if not hero then return nil, "no_hero" end
	local spell = spell_map["Duel"]
	local ability = get_spell(hero, spell)
	if not ability then return nil, "missing" end
	if not is_spell_ready_and_castable(hero, ability) then return nil, "duel_unavailable" end
	return {
		key = "Duel",
		label = "Duel",
		spell = spell,
		ability = ability,
		category = "duel",
	}, nil
end

compute_required_combo_range = function(hero, target, ignore_step_state)
	local duel_step, duel_reason = get_duel_step(hero)
	if not duel_step then
		return nil, duel_reason or "duel_unavailable"
	end

	if target_has_linkens(target) then
		local breaker_range = get_ready_linkens_breaker_max_range(hero, target)
		if breaker_range == nil then
			return nil, "need_linkens_breaker"
		end
		return breaker_range, nil
	end

	local pre_duel_range = get_ready_pre_duel_max_range(hero, target, ignore_step_state)
	if pre_duel_range ~= nil then
		return pre_duel_range, nil
	end

	local required_range = get_cast_range(hero, duel_step.ability, duel_step.spell)
	return required_range or 0.0, nil
end

can_select_target_for_combo = function(hero, target, cursor_pos)
	if not hero or not target then return false end
	if target_is_forbidden(target) then return false end
	local required_range, reason = compute_required_combo_range(hero, target, true)
	if not required_range then
		log_debug("Skip target: " .. tostring(reason))
		return false
	end
	return true
end

local function combo_ready_now(hero, target, allow_blink)
	if not hero or not target then return false, nil, "invalid" end
	local required_range, reason = compute_required_combo_range(hero, target)
	if not required_range then
		return false, nil, reason or "unavailable"
	end
	local hero_pos = Entity.GetAbsOrigin(hero)
	local target_pos = Entity.GetAbsOrigin(target)
	if not hero_pos or not target_pos then
		return false, required_range, "no_position"
	end
	if distance2d(hero_pos, target_pos) <= required_range then
		return true, required_range, "direct"
	end
	if allow_blink and ui and ui.use_blink and ui.use_blink.Get and ui.use_blink:Get() then
		local blink_spell = spell_map["Blink"]
		local blink = get_spell(hero, blink_spell)
		if blink and is_spell_ready_and_castable(hero, blink) then
			local blink_pos = get_blink_position(hero_pos, target, target_pos, required_range)
			local blink_range = get_cast_range(hero, blink, blink_spell)
			if blink_range <= 0.0 then blink_range = 1200.0 end
			if blink_pos
				and distance2d(hero_pos, blink_pos) <= blink_range
				and distance2d(blink_pos, target_pos) <= required_range then
				return true, required_range, "blink"
			end
		end
	end
	return false, required_range, "walk"
end

local function attempt_gap_close(hero, target, required_range, allow_blink)
	if not hero or not target then return false end
	if not NPC or not NPC.IsEntityInRange then return false end
	if required_range <= 0.0 then required_range = 200.0 end
	if NPC.IsEntityInRange(hero, target, required_range) then
		return false
	end

	if allow_blink and ui and ui.use_blink and ui.use_blink.Get and ui.use_blink:Get() then
		local blink_spell = spell_map["Blink"]
		local blink = get_spell(hero, blink_spell)
		if blink and is_spell_ready_and_castable(hero, blink) then
			local hero_pos = Entity.GetAbsOrigin(hero)
			local target_pos = Entity.GetAbsOrigin(target)
			local blink_range = get_cast_range(hero, blink, blink_spell)
			if blink_range <= 0.0 then blink_range = 1200.0 end
			if distance2d(hero_pos, target_pos) > required_range then
				local blink_pos = get_blink_position(hero_pos, target, target_pos, required_range)
				if blink_pos
					and distance2d(hero_pos, blink_pos) <= blink_range
					and distance2d(blink_pos, target_pos) <= required_range then
					local ok_cast, reason = cast_fast(hero, blink, blink_spell, blink_pos)
					if ok_cast then
						local cast_point = get_cast_point_seconds(blink)
						next_action_time = now_time() + math.max(CAST_GAP_SECONDS, cast_point + 0.03)
						log_debug("Blink in")
						return true
					end
					log_debug("Blink failed: " .. tostring(reason))
				end
			end
		end
	end

	issue_move_to_target(hero, target)
	return true
end

local function commit_step(step)
	if not step then return end
	if step.category == "pre_duel" or step.category == "blade_mail" then
		step_done[step.key] = true
		return
	end
	if step.category == "duel" then
		step_done[step.key] = true
		combo_running = false
		waiting_release = true
		log_debug("Duel cast confirmed")
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

local function get_next_combo_step(hero, target)
	if target_has_linkens(target) then
		local breaker = pick_linkens_breaker(hero, target, true)
		if breaker then
			return breaker, nil
		end
		return nil, "need_linkens_breaker"
	end

	local pre_duel_step = get_next_pre_duel_step(hero, target, true)
	if pre_duel_step then
		return pre_duel_step, nil
	end

	local blade_mail_step = get_blade_mail_step(hero)
	if blade_mail_step then
		return blade_mail_step, nil
	end

	local duel_step, duel_reason = get_duel_step(hero)
	if duel_step then
		return duel_step, nil
	end

	return nil, duel_reason or "duel_unavailable"
end

local menu_tab = Menu.Create("General", "My Scripts", "Legion Duel Combo", "Combo")
local settings_group = menu_tab:Create("Settings")
local pre_duel_group = menu_tab:Create("Pre-Duel Items")
local linkens_group = menu_tab:Create("Linken's Breaker")

ui = {}
ui.enabled = settings_group:Switch("Enable Combo", true)
ui.combo_key = settings_group:Bind("Combo Key", Enum.ButtonCode.KEY_SPACE)
ui.invis_combo_key = settings_group:Bind("Invis Walk Combo Key", Enum.ButtonCode.BUTTON_CODE_INVALID)
ui.use_blink = settings_group:Switch("Blink Combo", true)
ui.blink_forward_offset = settings_group:Slider("Blink Forward Offset", 0, 250, 0)
ui.mouse_target_radius = settings_group:Slider("Mouse Target Radius", 50, 1200, 325)
ui.use_blade_mail = settings_group:Switch("Use Blade Mail Before Duel", true)
ui.draw_lock_line = settings_group:Switch("Draw Lock Line", true)
ui.debug_logs = settings_group:Switch("Debug Logs", false)

settings_group:Label("Hold the combo key near an enemy hero to combo the closest target to your cursor.")
settings_group:Label("Invis Walk Combo Key disables blink and walks in for the combo instead.")
settings_group:Label("Will never Duel Ursa while Enrage is active.")
settings_group:Label("Blink lands on the target's facing line. Offset 0 means blink right on top of them.")
settings_group:Label("Mouse Target Radius is both the targeting AOE and the on-screen mouse circle.")

pre_duel_group:Label("Drag to reorder. Toggle entries to enable or disable optional casts before Duel.")
do
	local saved_order = ""
	local saved_enabled = ""
	if Config and Config.ReadString then
		saved_order = Config.ReadString(ORDER_UI_CONFIG_NAME, "pre_duel_drag_order", "")
		saved_enabled = Config.ReadString(ORDER_UI_CONFIG_NAME, "pre_duel_drag_enabled", "")
	end

	local order_list = split_csv(saved_order)
	if #order_list == 0 then
		order_list = PRE_DUEL_ITEMS
	end

	local enabled_list = split_csv(saved_enabled)
	if #enabled_list == 0 then
		enabled_list = DEFAULT_PRE_DUEL_ENABLED
	end

	local items = build_multiselect_items(order_list, list_to_set(enabled_list), PRE_DUEL_ITEMS)
	ui.pre_duel_order = pre_duel_group:MultiSelect("Priority", items, true)
	if ui.pre_duel_order and ui.pre_duel_order.DragAllowed then
		pcall(ui.pre_duel_order.DragAllowed, ui.pre_duel_order, true)
	end

	local function read_pre_duel(save_to_config)
		if not ui.pre_duel_order or not ui.pre_duel_order.List or not ui.pre_duel_order.Get then return end
		local ok_list, ids = pcall(ui.pre_duel_order.List, ui.pre_duel_order)
		if not ok_list or type(ids) ~= "table" then return end
		local enabled = {}
		for _, id in ipairs(ids) do
			local ok_get, is_on = pcall(ui.pre_duel_order.Get, ui.pre_duel_order, id)
			if ok_get and is_on then
				enabled[#enabled + 1] = id
			end
		end
		pre_duel_enabled_names = enabled
		if save_to_config and Config and Config.WriteString then
			Config.WriteString(ORDER_UI_CONFIG_NAME, "pre_duel_drag_order", table.concat(ids, ","))
			Config.WriteString(ORDER_UI_CONFIG_NAME, "pre_duel_drag_enabled", table.concat(enabled, ","))
		end
	end

	read_pre_duel(true)
	if ui.pre_duel_order and ui.pre_duel_order.SetCallback then
		ui.pre_duel_order:SetCallback(function()
			read_pre_duel(true)
		end, true)
	end
end

linkens_group:Label("Drag to reorder. If Linken's is active, the first ready direct-target breaker is used.")
do
	local saved_order = ""
	local saved_enabled = ""
	if Config and Config.ReadString then
		saved_order = Config.ReadString(ORDER_UI_CONFIG_NAME, "linkens_drag_order", "")
		saved_enabled = Config.ReadString(ORDER_UI_CONFIG_NAME, "linkens_drag_enabled", "")
	end

	local order_list = split_csv(saved_order)
	if #order_list == 0 then
		order_list = LINKENS_BREAK_ITEMS
	end

	local enabled_list = split_csv(saved_enabled)
	if #enabled_list == 0 then
		enabled_list = DEFAULT_LINKENS_BREAK_ENABLED
	end

	local items = build_multiselect_items(order_list, list_to_set(enabled_list), LINKENS_BREAK_ITEMS)
	ui.linkens_breaker = linkens_group:MultiSelect("Priority", items, true)
	if ui.linkens_breaker and ui.linkens_breaker.DragAllowed then
		pcall(ui.linkens_breaker.DragAllowed, ui.linkens_breaker, true)
	end

	local function read_linkens(save_to_config)
		if not ui.linkens_breaker or not ui.linkens_breaker.List or not ui.linkens_breaker.Get then return end
		local ok_list, ids = pcall(ui.linkens_breaker.List, ui.linkens_breaker)
		if not ok_list or type(ids) ~= "table" then return end
		local enabled = {}
		for _, id in ipairs(ids) do
			local ok_get, is_on = pcall(ui.linkens_breaker.Get, ui.linkens_breaker, id)
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

	read_linkens(true)
	if ui.linkens_breaker and ui.linkens_breaker.SetCallback then
		ui.linkens_breaker:SetCallback(function()
			read_linkens(true)
		end, true)
	end
end

function legion_duel_combo.OnUpdate()
	if not ui.enabled:Get() then return end

	local normal_down = is_bind_down(ui.combo_key)
	local invis_down = is_bind_down(ui.invis_combo_key)
	local down = normal_down or invis_down
	local allow_blink = normal_down and not invis_down
	if not down then
		if combo_running then
			stop_hero_orders()
		end
		reset_combo(false)
		was_key_down = false
		return
	end

	local hero = Heroes.GetLocal()
	if not hero or not Entity.IsAlive(hero) then return end
	combo_allow_blink = allow_blink

	if NPC and NPC.HasModifier and NPC.HasModifier(hero, "modifier_legion_commander_duel") then
		waiting_release = true
		combo_running = false
		was_key_down = true
		return
	end

	if waiting_release then
		was_key_down = true
		return
	end

	local t = now_time()

	if pending_confirm and handle_pending_confirmation(hero) then
		was_key_down = true
		return
	end

	if (not combo_running) or (not combo_target) or (not Entity.IsAlive(combo_target)) then
		if combo_running then
			reset_combo(false)
		end
		local target = nil
		if (t - last_target_search_t) >= TARGET_SEARCH_COOLDOWN then
			last_target_search_t = t
			target = find_target_near_cursor()
		end
		if target then
			start_combo(target, allow_blink)
		else
			issue_move_to_ground(hero, Input.GetWorldCursorPos())
			was_key_down = true
			return
		end
	end

	if not combo_target or not Entity.IsAlive(combo_target) then
		reset_combo(false)
		was_key_down = true
		return
	end

	if target_is_forbidden(combo_target) then
		log_debug("Target became forbidden")
		stop_hero_orders()
		reset_combo(false)
		was_key_down = true
		return
	end

	if t < next_action_time then
		was_key_down = true
		return
	end

	local required_range, range_reason = compute_required_combo_range(hero, combo_target)
	if not required_range then
		log_debug("Combo blocked: " .. tostring(range_reason))
		was_key_down = true
		return
	end

	if attempt_gap_close(hero, combo_target, required_range, combo_allow_blink) then
		was_key_down = true
		return
	end

	local step, step_reason = get_next_combo_step(hero, combo_target)
	if not step then
		log_debug("No step available: " .. tostring(step_reason))
		was_key_down = true
		return
	end

	local cast_target = combo_target
	if step.spell.cast == "position" then
		cast_target = Entity.GetAbsOrigin(combo_target)
	end

	local ok_cast, reason = cast_fast(hero, step.ability, step.spell, cast_target)
	if ok_cast then
		local cast_point = get_cast_point_seconds(step.ability)
		next_action_time = t + math.max(CAST_GAP_SECONDS, cast_point)
		if is_cooldown_started(step.ability) then
			commit_step(step)
		else
			set_pending_confirmation(step, step.ability)
		end
		log_debug("Cast " .. tostring(step.label))
	else
		if reason == "out_of_range" then
			local step_range = get_cast_range(hero, step.ability, step.spell)
			attempt_gap_close(hero, combo_target, step_range, combo_allow_blink)
		elseif step.category == "pre_duel" or step.category == "blade_mail" then
			step_done[step.key] = true
		else
			log_debug("Step blocked: " .. tostring(step.label) .. " => " .. tostring(reason))
		end
	end

	was_key_down = true
end

function legion_duel_combo.OnDraw()
	if not ui.enabled:Get() then return end
	local normal_down = is_bind_down(ui.combo_key)
	local invis_down = is_bind_down(ui.invis_combo_key)
	local down = normal_down or invis_down
	local allow_blink = normal_down and not invis_down
	if not down then return end
	local hero = Heroes.GetLocal()
	if not hero then return end

	local cursor = Input.GetWorldCursorPos and Input.GetWorldCursorPos() or nil
	local mouse_radius = tonumber(ui.mouse_target_radius and ui.mouse_target_radius.Get and ui.mouse_target_radius:Get()) or 325
	if cursor and mouse_radius and mouse_radius > 0.0 then
		draw_world_circle(cursor, mouse_radius, Color(255, 210, 90, 220), 1.5, 36)
	end

	if allow_blink and ui.use_blink and ui.use_blink.Get and ui.use_blink:Get() then
		local blink_spell = spell_map["Blink"]
		local blink = get_spell(hero, blink_spell)
		if blink then
			local hero_pos = Entity.GetAbsOrigin(hero)
			local blink_range = get_cast_range(hero, blink, blink_spell)
			if blink_range <= 0.0 then blink_range = 1200.0 end
			if hero_pos and blink_range > 0.0 then
				draw_world_circle(hero_pos, blink_range, Color(90, 180, 255, 220), 1.5, 40)
			end
		end
	end

	if combo_target and Entity.IsAlive(combo_target) then
		local ready_now = combo_ready_now(hero, combo_target, combo_allow_blink)
		draw_lock_line(hero, combo_target, ready_now and LOCK_LINE_COLOR_READY or LOCK_LINE_COLOR_CHASE)
	end
end

return legion_duel_combo
