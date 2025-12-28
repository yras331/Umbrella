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
ui.combo_key = main_group:Bind("Combo Key", Enum.ButtonCode.KEY_SPACE)
ui.search_radius = main_group:Input("Target Search Radius", "300")

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

local function cast_fast(ability, spell, target)
	if not ability then return false end
	local hero = Heroes.GetLocal()
	if not hero then return false end
	if not Ability.IsReady(ability) then return false end
	local mana = NPC.GetMana(hero) or 0.0
	if not Ability.IsCastable(ability, mana) then return false end

	if spell.cast == "no_target" then
		Ability.CastNoTarget(ability, false, false, true)
		return true
	end
	if not target or not Entity.IsAlive(target) then return false end
	if spell.cast == "position" then
		Ability.CastPosition(ability, get_mystic_flare_cast_pos(hero, target, ability), false, false, true)
		return true
	end
	Ability.CastTarget(ability, target, false, false, true)
	return true
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

local function reset_combo()
	combo_running = false
	combo_target = nil
	combo_seq = {}
	combo_idx = 1
	next_cast_time = 0.0
end

local function start_combo(target)
	combo_running = true
	combo_target = target
	combo_seq = build_combo_sequence()
	combo_idx = 1
	next_cast_time = 0.0
end

local function step_combo()
	if not combo_running or not combo_target or not Entity.IsAlive(combo_target) then
		reset_combo()
		return false
	end
	local hero = Heroes.GetLocal()
	if not hero then
		reset_combo()
		return false
	end
	if combo_idx > #combo_seq then
		reset_combo()
		return false
	end

	local spell = combo_seq[combo_idx]
	local ability = get_spell(hero, spell)
	-- If missing or not castable now, skip instantly.
	if not ability then
		combo_idx = combo_idx + 1
		return false
	end
	if cast_fast(ability, spell, combo_target) then
		combo_idx = combo_idx + 1
		return true
	end
	combo_idx = combo_idx + 1
	return false
end

function combo.OnUpdate()
	if not ui.enabled:Get() then return end
	local key = ui.combo_key:Get()
	if key == Enum.ButtonCode.BUTTON_CODE_INVALID then return end

	local down = Input.IsKeyDown(key)
	if not down then
		if combo_running then reset_combo() end
		was_key_down = false
		return
	end

	-- lock once at start; reacquire only if target died
	if not combo_running or not combo_target or not Entity.IsAlive(combo_target) then
		local target = find_target_near_cursor()
		if target then
			start_combo(target)
		else
			return
		end
	end

	local t = now_time()
	if t < next_cast_time then return end

	-- Fast-skip non-castable steps, but enforce 0.05s between actual casts.
	for _ = 1, 32 do
		if not combo_running then break end
		if step_combo() then
			next_cast_time = t + CAST_GAP_SECONDS
			break
		end
	end

	was_key_down = true
end

return combo