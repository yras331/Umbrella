---@diagnostic disable: undefined-global

local blink_breaker = {}

local ORDER_UI_CONFIG_NAME = "blink_breaker_v2"
local SCRIPT_TAG = "[Blink Breaker]"

local ui
local priority_enabled_names = nil
local linkens_break_enabled_names = nil

local pending_targets = {} -- [handle] = { enemy = Entity, t = number, blink_like = bool, reason = string }
local recent_target_cast_t = {} -- [handle] = number
local pending_linkens_followup = nil -- { handle = number, enemy = Entity, breaker_ability = Ability, breaker_name_id = string, next_try_t = number, expire_t = number }

local COOLDOWN_CONFIRM_GRACE = 0.08
local COOLDOWN_CONFIRM_EXTRA = 0.15
local GLOBAL_CAST_COOLDOWN = 0.10
local TARGET_CAST_COOLDOWN = 0.60
local QUEUE_LIFETIME = 0.50
local FOLLOWUP_LIFETIME = 0.75

local last_cast_t = -1000.0

local BLINK_LIKE_ABILITIES = {
	["item_blink"] = true,
	["item_overwhelming_blink"] = true,
	["item_swift_blink"] = true,
	["item_arcane_blink"] = true,
	["item_super_blink"] = true,
	["antimage_blink"] = true,
	["queenofpain_blink"] = true,
	["faceless_void_time_walk"] = true,
	["void_spirit_astral_step"] = true,
}

local spell_map = {
	["Orchid"] = { name = "item_orchid", kind = "item" },
	["Bloodthorn"] = { name = "item_bloodthorn", kind = "item" },
	["Eul's Scepter"] = { name = "item_cyclone", kind = "item", aliases = { "item_wind_waker" } },
	["Lion Hex"] = { name = "lion_voodoo", kind = "ability" },
	["Lion Mana Drain"] = { name = "lion_mana_drain", kind = "ability" },
	["Sinister Gaze"] = { name = "lich_sinister_gaze", kind = "ability" },
	["Shaman Hex"] = { name = "shadow_shaman_voodoo", kind = "ability" },
	["Zeus Arc Lightning"] = { name = "zuus_arc_lightning", kind = "ability" },
	["Scythe of Vyse"] = { name = "item_sheepstick", kind = "item" },
	["Ancient Seal"] = { name = "skywrath_mage_ancient_seal", kind = "ability" },
	["Rod of Atos"] = { name = "item_rod_of_atos", kind = "item", aliases = { "item_gleipnir", "item_gungir" } },
	["Heaven's Halberd"] = { name = "item_heavens_halberd", kind = "item" },
	["Diffusal / Disperser"] = { name = "item_diffusal_blade", kind = "item", aliases = { "item_disperser" } },
	["Dagon"] = { name = "item_dagon", kind = "item", dagon = true },
	["Harpoon"] = { name = "item_harpoon", kind = "item" },
	["Force Staff / Hurricane Pike"] = {
		name = "item_force_staff",
		kind = "item",
		aliases = { "item_hurricane_pike", "item_force_boots" },
	},
}

local PRIORITY_ITEMS = {
	"Scythe of Vyse",
	"Orchid",
	"Bloodthorn",
	"Eul's Scepter",
	"Lion Hex",
	"Sinister Gaze",
	"Shaman Hex",
	"Ancient Seal",
	"Rod of Atos",
	"Harpoon",
}

local LINKENS_BREAK_ITEMS = {
	"Orchid",
	"Bloodthorn",
	"Eul's Scepter",
	"Lion Hex",
	"Lion Mana Drain",
	"Shaman Hex",
	"Zeus Arc Lightning",
	"Scythe of Vyse",
	"Ancient Seal",
	"Rod of Atos",
	"Heaven's Halberd",
	"Diffusal / Disperser",
	"Dagon",
	"Force Staff / Hurricane Pike",
	"Harpoon",
}

local DEFAULT_LINKENS_BREAK_ENABLED = {
	"Orchid",
	"Bloodthorn",
	"Eul's Scepter",
	"Lion Hex",
	"Lion Mana Drain",
	"Shaman Hex",
	"Zeus Arc Lightning",
	"Scythe of Vyse",
	"Ancient Seal",
	"Rod of Atos",
	"Heaven's Halberd",
	"Diffusal / Disperser",
	"Dagon",
	"Force Staff / Hurricane Pike",
	"Harpoon",
}

local function now_time()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
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

local function get_aoe_increase_pct(hero)
	local v = nil
	if NPC and NPC.GetAOEIncrease then v = NPC.GetAOEIncrease(hero) end
	if v == nil and NPC and NPC.GetAoEIncrease then v = NPC.GetAoEIncrease(hero) end
	if type(v) ~= "number" then return 0.0 end
	if v > 1.0 then return v / 100.0 end
	if v < 0.0 then v = 0.0 end
	return v
end

local function hero_has_learned_ability(hero, ability_name)
	if not hero or not ability_name or not NPC then return false end
	local talent = NPC.GetAbility(hero, ability_name)
	if not talent then return false end
	if Ability and Ability.GetLevel then
		local ok_level, level = pcall(Ability.GetLevel, talent)
		if ok_level and type(level) == "number" then
			return level > 0
		end
	end
	return false
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

local function split_csv(s)
	if type(s) ~= "string" or s == "" then return {} end
	local out = {}
	for segment in string.gmatch(s, "[^,]+") do
		local cleaned = tostring(segment):gsub("^%s+", ""):gsub("%s+$", "")
		if cleaned ~= "" then
			out[#out + 1] = cleaned
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

local function append_unique(list, value)
	if type(list) ~= "table" or value == nil then return end
	for _, existing in ipairs(list) do
		if existing == value then
			return
		end
	end
	list[#list + 1] = value
end

local function filter_list_to_allowed(list, allowed_set)
	local filtered = {}
	if type(list) ~= "table" or type(allowed_set) ~= "table" then return filtered end
	for _, value in ipairs(list) do
		if allowed_set[value] then
			append_unique(filtered, value)
		end
	end
	return filtered
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

local function spell_meta_matches_name(meta, actual_name)
	if not meta or not actual_name then return false end
	if meta.name == actual_name then return true end
	if meta.dagon and type(actual_name) == "string" and actual_name:find("^item_dagon") then
		return true
	end
	if type(meta.aliases) == "table" then
		for _, alias in ipairs(meta.aliases) do
			if alias == actual_name then return true end
		end
	end
	return false
end

local function resolve_meta_ability_or_item(hero, meta)
	if not hero or not meta or not NPC then return nil end
	if meta.kind == "ability" then
		return NPC.GetAbility(hero, meta.name)
	end
	if not NPC.GetItemByIndex or not Ability or not Ability.GetName then return nil end
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(hero, i)
		if item then
			local ok_name, name = pcall(Ability.GetName, item)
			if ok_name and spell_meta_matches_name(meta, name) then
				return item
			end
		end
	end
	return nil
end

local function read_enabled_names(multiselect, cache)
	if type(cache) == "table" and #cache > 0 then return cache end
	if not multiselect or not multiselect.List or not multiselect.Get then return {} end
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

local function get_priority_ids()
	return read_enabled_names(ui and ui.priority, priority_enabled_names)
end

local function get_linkens_breaker_ids()
	return read_enabled_names(ui and ui.linkens_breaker, linkens_break_enabled_names)
end

local function merge_spell_id_lists(...)
	local merged = {}
	for i = 1, select("#", ...) do
		local list = select(i, ...)
		if type(list) == "table" then
			for _, name_id in ipairs(list) do
				append_unique(merged, name_id)
			end
		end
	end
	return merged
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
		end
	end
	if cast_range > 0.0 and NPC and NPC.GetCastRangeBonus then
		cast_range = cast_range + (NPC.GetCastRangeBonus(hero) or 0.0)
	end
	return cast_range
end

local function get_spell_aoe_radius(hero, ability, name_id)
	if not hero or not ability or not name_id then return 0.0 end

	if name_id == "Sinister Gaze" then
		if not has_agh_effect(hero) then return 0.0 end
		local radius = get_special_value(ability, "aoe_scepter")
		if type(radius) ~= "number" or radius <= 0.0 then
			radius = 400.0
		end
		return radius * (1.0 + get_aoe_increase_pct(hero))
	end

	if name_id == "Lion Hex" then
		local radius = get_special_value(ability, "radius")
		if (type(radius) ~= "number" or radius <= 0.0) and hero_has_learned_ability(hero, "special_bonus_unique_lion_4") then
			radius = 250.0
		end
		if type(radius) ~= "number" or radius <= 0.0 then
			return 0.0
		end
		return radius * (1.0 + get_aoe_increase_pct(hero))
	end

	return 0.0
end

local function spell_uses_ground_target_when_aoe(hero, ability, name_id)
	if not hero or not ability or not name_id then return false end
	if name_id ~= "Sinister Gaze" and name_id ~= "Lion Hex" then
		return false
	end
	return get_spell_aoe_radius(hero, ability, name_id) > 0.0
end

local function apply_cast_result_to_targets(hero, primary_target, cast_name_id, ability, cast_t)
	if not hero or not primary_target or not cast_name_id then return end

	local primary_handle = Entity.GetIndex(primary_target)
	if primary_handle then
		pending_targets[primary_handle] = nil
		recent_target_cast_t[primary_handle] = cast_t
	end

	local aoe_radius = get_spell_aoe_radius(hero, ability, cast_name_id)
	if aoe_radius <= 0.0 then return end
	if not Heroes or not Heroes.InRadius or not Entity or not Entity.GetAbsOrigin then return end

	local center = Entity.GetAbsOrigin(primary_target)
	local my_team = Entity.GetTeamNum(hero)
	local enemies = Heroes.InRadius(center, aoe_radius, my_team, Enum.TeamType.TEAM_ENEMY, true, true)
	for _, enemy in ipairs(enemies or {}) do
		if enemy and Entity.IsAlive(enemy) and not NPC.IsIllusion(enemy) then
			local immune = false
			if Entity.IsInvulnerable then
				local ok_inv, inv = pcall(Entity.IsInvulnerable, enemy)
				if ok_inv and inv then immune = true end
			end
			if not immune and NPC and NPC.IsDebuffImmune then
				local ok_di, debuff_immune = pcall(NPC.IsDebuffImmune, enemy)
				if ok_di and debuff_immune then immune = true end
			end
			if not immune and NPC and NPC.IsMagicImmune then
				local ok_mi, magic_immune = pcall(NPC.IsMagicImmune, enemy)
				if ok_mi and magic_immune then immune = true end
			end
			local handle = (not immune) and Entity.GetIndex(enemy) or nil
			if handle ~= nil then
				pending_targets[handle] = nil
				recent_target_cast_t[handle] = cast_t
			end
		end
	end
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

local function target_is_blocked(target)
	if not target or not Entity or not Entity.IsAlive or not Entity.IsAlive(target) then
		return true, "dead"
	end
	if Entity.IsInvulnerable then
		local ok, invulnerable = pcall(Entity.IsInvulnerable, target)
		if ok and invulnerable then return true, "invulnerable" end
	end
	if NPC and NPC.HasModifier then
		if NPC.HasModifier(target, "modifier_antimage_counterspell") or NPC.HasModifier(target, "modifier_antimage_counterspell_active") then
			return true, "antimage_counterspell"
		end
		if NPC.HasModifier(target, "modifier_item_lotus_orb_active")
			and not (ui.ignore_lotus_active and ui.ignore_lotus_active.Get and ui.ignore_lotus_active:Get()) then
			return true, "lotus_active"
		end
	end
	if NPC and NPC.IsDebuffImmune then
		local ok, immune = pcall(NPC.IsDebuffImmune, target)
		if ok and immune then return true, "debuff_immune" end
	end
	if NPC and NPC.IsMagicImmune then
		local ok, immune = pcall(NPC.IsMagicImmune, target)
		if ok and immune then return true, "magic_immune" end
	end
	return false, nil
end

local function queue_target(enemy, blink_like, reason)
	if not enemy or not Entity or not Entity.IsAlive or not Entity.IsAlive(enemy) then return end
	local blocked, block_reason = target_is_blocked(enemy)
	if blocked then
		log_debug("Skip queue: " .. tostring(block_reason))
		return
	end
	local handle = Entity.GetIndex(enemy)
	if not handle then return end
	local t = now_time()
	local recent_t = recent_target_cast_t[handle] or -1000.0
	if (t - recent_t) < TARGET_CAST_COOLDOWN then return end
	local current = pending_targets[handle]
	if current then
		current.enemy = enemy
		current.t = t
		current.blink_like = current.blink_like or (blink_like == true)
		current.reason = reason or current.reason
	else
		pending_targets[handle] = {
			enemy = enemy,
			t = t,
			blink_like = blink_like == true,
			reason = reason or "queued",
		}
	end
end

local function choose_spell_ids_for_target(target)
	if target_has_linkens(target) then
		return get_linkens_breaker_ids(), true
	end
	return get_priority_ids(), false
end

local function cast_from_spell_ids(hero, target, spell_ids, opts)
	opts = opts or {}
	local blocked, block_reason = target_is_blocked(target)
	if blocked then return false, "blocked_" .. tostring(block_reason) end
	if not spell_ids or #spell_ids == 0 then
		return false, "no_spells"
	end

	local had_matching_spell = false
	local had_owned_spell = false
	local had_ready_spell = false
	for _, name_id in ipairs(spell_ids) do
		local meta = spell_map[name_id]
		if meta and meta.name then
			local ability = resolve_meta_ability_or_item(hero, meta)
			if ability and Ability and Ability.IsReady and Ability.IsCastable then
				local bypasses_linkens = spell_uses_ground_target_when_aoe(hero, ability, name_id)
				if (not opts.bypass_linkens_only) or bypasses_linkens then
					had_matching_spell = true
				had_owned_spell = true
				local mana = (NPC and NPC.GetMana and NPC.GetMana(hero)) or 0.0
				if Ability.IsReady(ability) and Ability.IsCastable(ability, mana) then
					had_ready_spell = true
					local range = get_effective_cast_range(hero, ability)
					local target_pos = Entity.GetAbsOrigin(target)
					local dist = distance2d(Entity.GetAbsOrigin(hero), target_pos)
					if range <= 0.0 or dist <= range then
						if bypasses_linkens and Ability.CastPosition and target_pos then
							Ability.CastPosition(ability, target_pos, false, false, false)
							return true, name_id, ability, meta
						end
						if Ability.CastTarget then
							Ability.CastTarget(ability, target, false, false, false)
							return true, name_id, ability, meta
						end
						return false, "api_unavailable"
					end
				end
			end
			end
		end
	end

	if opts.bypass_linkens_only and not had_matching_spell then
		return false, "no_bypass_spell"
	end
	if not had_owned_spell then
		return false, "no_owned_spell"
	end
	if not had_ready_spell then
		return false, "no_ready_spell"
	end
	return false, "out_of_range"
end

local function cast_one_on_target(hero, target)
	if target_has_linkens(target) then
		local bypass_ids = merge_spell_id_lists(get_priority_ids(), get_linkens_breaker_ids())
		local ok_bypass, bypass_name_or_reason, bypass_ability, bypass_meta = cast_from_spell_ids(hero, target, bypass_ids, { bypass_linkens_only = true })
		if ok_bypass then
			return true, bypass_name_or_reason, {
				using_linkens = false,
				name_id = bypass_name_or_reason,
				ability = bypass_ability,
				meta = bypass_meta,
			}
		end

		local breaker_ids = get_linkens_breaker_ids()
		local ok_cast, cast_name_or_reason, ability, meta = cast_from_spell_ids(hero, target, breaker_ids)
		if not ok_cast then
			if cast_name_or_reason and tostring(cast_name_or_reason):sub(1, 8) == "blocked_" then
				return false, cast_name_or_reason
			end
			if cast_name_or_reason == "no_spells" or cast_name_or_reason == "no_owned_spell" then
				return false, "no_linkens_breaker_owned"
			end
			return false, "waiting_linkens_breaker"
		end

		return true, "linkens_" .. tostring(cast_name_or_reason), {
			using_linkens = true,
			name_id = cast_name_or_reason,
			ability = ability,
			meta = meta,
		}
	end

	local spell_ids = get_priority_ids()
	if not spell_ids or #spell_ids == 0 then
		return false, "no_spells"
	end

	local ok_cast, cast_name_or_reason, ability, meta = cast_from_spell_ids(hero, target, spell_ids)
	if not ok_cast then
		return false, cast_name_or_reason
	end

	return true, cast_name_or_reason, {
		using_linkens = false,
		name_id = cast_name_or_reason,
		ability = ability,
		meta = meta,
	}
end

local function start_linkens_followup(handle, enemy, breaker_name_id, breaker_ability)
	if not handle or not enemy or not breaker_ability then return end
	local t = now_time()
	local retry_delay = math.max(COOLDOWN_CONFIRM_GRACE, get_cast_point_seconds(breaker_ability) + COOLDOWN_CONFIRM_EXTRA)
	pending_linkens_followup = {
		handle = handle,
		enemy = enemy,
		breaker_name_id = breaker_name_id,
		breaker_ability = breaker_ability,
		next_try_t = t + retry_delay,
		expire_t = t + math.max(FOLLOWUP_LIFETIME, retry_delay + 0.30),
	}
	log_debug("Queued rapid follow-up after Linken's breaker: " .. tostring(breaker_name_id))
end

local function clear_linkens_followup()
	pending_linkens_followup = nil
end

local function process_linkens_followup(hero)
	local state = pending_linkens_followup
	if not state then return false end

	local t = now_time()
	if t > (state.expire_t or t) then
		clear_linkens_followup()
		return false
	end

	local handle = state.handle
	local enemy = state.enemy
	if not enemy or not Entity or not Entity.IsAlive or not Entity.IsAlive(enemy) then
		pending_targets[handle] = nil
		clear_linkens_followup()
		return false
	end

	local blocked, block_reason = target_is_blocked(enemy)
	if blocked then
		log_debug("Cancel Linken's follow-up: " .. tostring(block_reason))
		pending_targets[handle] = nil
		recent_target_cast_t[handle] = t
		clear_linkens_followup()
		return false
	end

	local breaker_ability = state.breaker_ability
	if not breaker_ability then
		clear_linkens_followup()
		return false
	end

	if not is_cooldown_started(breaker_ability) then
		if t < (state.next_try_t or t) then
			return true
		end
		log_debug("Linken's breaker cooldown did not confirm in time, retrying normal flow")
		clear_linkens_followup()
		return false
	end

	if target_has_linkens(enemy) then
		log_debug("Linken's still active after breaker, keeping target in normal queue")
		clear_linkens_followup()
		return false
	end

	local ok_cast, cast_name_or_reason, ability = cast_from_spell_ids(hero, enemy, get_priority_ids())
	log_debug(string.format("Rapid follow-up target=%s ok=%s reason=%s", tostring(handle), tostring(ok_cast), tostring(cast_name_or_reason)))
	clear_linkens_followup()
	if ok_cast then
		apply_cast_result_to_targets(hero, enemy, cast_name_or_reason, ability, t)
		last_cast_t = t
		return true
	end
	pending_targets[handle] = nil
	recent_target_cast_t[handle] = t

	return false
end

local function collect_candidates(hero, radius)
	local out = {}
	local t = now_time()

	for handle, entry in pairs(pending_targets) do
		local enemy = entry and entry.enemy or nil
		if not enemy or not Entity or not Entity.IsAlive or not Entity.IsAlive(enemy) then
			pending_targets[handle] = nil
		elseif (t - (entry.t or 0.0)) > QUEUE_LIFETIME then
			pending_targets[handle] = nil
		else
			local blocked = target_is_blocked(enemy)
			if blocked then
				pending_targets[handle] = nil
			else
				out[#out + 1] = {
					handle = handle,
					enemy = enemy,
					dist = distance2d(Entity.GetAbsOrigin(hero), Entity.GetAbsOrigin(enemy)),
					t = entry.t or 0.0,
				}
			end
		end
	end

	if ui.include_non_blink_targets and ui.include_non_blink_targets.Get and ui.include_non_blink_targets:Get() then
		local hero_pos = Entity.GetAbsOrigin(hero)
		local my_team = Entity.GetTeamNum(hero)
		local enemies = Heroes.InRadius(hero_pos, radius, my_team, Enum.TeamType.TEAM_ENEMY, true, true)
		for _, enemy in ipairs(enemies or {}) do
			if enemy and Entity.IsAlive(enemy) and not NPC.IsIllusion(enemy) then
				local handle = Entity.GetIndex(enemy)
				local recent_t = recent_target_cast_t[handle] or -1000.0
				if (t - recent_t) >= TARGET_CAST_COOLDOWN then
					local blocked = target_is_blocked(enemy)
					if not blocked then
						local already_added = false
						for _, existing in ipairs(out) do
							if existing.handle == handle then
								already_added = true
								break
							end
						end
						if not already_added then
							out[#out + 1] = {
								handle = handle,
								enemy = enemy,
								dist = distance2d(hero_pos, Entity.GetAbsOrigin(enemy)),
								t = t,
							}
						end
					end
				end
			end
		end
	end

	table.sort(out, function(a, b)
		if a.t == b.t then
			return a.dist < b.dist
		end
		return a.t < b.t
	end)

	return out
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
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		Render.Line(a, b, color, thickness)
	end
end

local menu_tab = Menu.Create("General", "My Scripts", "Blink Breaker", "BlinkBreaker")
local main_group = menu_tab:Create("Settings")
local order_group = menu_tab:Create("Priority")
local linkens_group = menu_tab:Create("Linken's Breaker")

ui = {}
ui.enabled = main_group:Switch("Enabled", true)
ui.debug_logs = main_group:Switch("Debug Logs", false)
ui.radius = main_group:Slider("Trigger Radius", 200, 1400, 450)
ui.draw_radius = main_group:Switch("Draw Radius", true)
ui.include_non_blink_targets = main_group:Switch("Include Non-Blink Targets", false)
ui.ignore_lotus_active = main_group:Switch("Ignore Lotus Orb Active", false)

order_group:Label("Drag to reorder. Toggle entries to enable or disable the main reaction spell list.")
do
	local saved_order = Config and Config.ReadString and Config.ReadString(ORDER_UI_CONFIG_NAME, "priority_drag_order", "") or ""
	local saved_enabled = Config and Config.ReadString and Config.ReadString(ORDER_UI_CONFIG_NAME, "priority_drag_enabled", "") or ""
	local order_list = split_csv(saved_order)
	local enabled_list = split_csv(saved_enabled)
	if #order_list == 0 then order_list = PRIORITY_ITEMS end
	if #enabled_list == 0 then enabled_list = PRIORITY_ITEMS end
	ui.priority = order_group:MultiSelect("Priority Order", build_multiselect_items(order_list, list_to_set(enabled_list), PRIORITY_ITEMS), true)
	if ui.priority and ui.priority.DragAllowed then
		pcall(ui.priority.DragAllowed, ui.priority, true)
	end
	local function read_priority(save_to_config)
		if not ui.priority or not ui.priority.List or not ui.priority.Get then return end
		local ok_list, ids = pcall(ui.priority.List, ui.priority)
		if not ok_list or type(ids) ~= "table" then return end
		local enabled = {}
		for _, id in ipairs(ids) do
			local ok_get, is_on = pcall(ui.priority.Get, ui.priority, id)
			if ok_get and is_on then enabled[#enabled + 1] = id end
		end
		priority_enabled_names = enabled
		if save_to_config and Config and Config.WriteString then
			Config.WriteString(ORDER_UI_CONFIG_NAME, "priority_drag_order", table.concat(ids, ","))
			Config.WriteString(ORDER_UI_CONFIG_NAME, "priority_drag_enabled", table.concat(enabled, ","))
		end
	end
	read_priority(false)
	if ui.priority and ui.priority.SetCallback then
		ui.priority:SetCallback(function()
			read_priority(true)
		end, true)
	end
end

linkens_group:Label("Drag to reorder. Toggle entries to enable or disable Linken's breakers.")
do
	local saved_order = Config and Config.ReadString and Config.ReadString(ORDER_UI_CONFIG_NAME, "linkens_drag_order", "") or ""
	local saved_enabled = Config and Config.ReadString and Config.ReadString(ORDER_UI_CONFIG_NAME, "linkens_drag_enabled", "") or ""
	local allowed_set = list_to_set(LINKENS_BREAK_ITEMS)
	local order_list = filter_list_to_allowed(split_csv(saved_order), allowed_set)
	local enabled_list = filter_list_to_allowed(split_csv(saved_enabled), allowed_set)
	local saved_order_set = list_to_set(order_list)
	local fallback_items = LINKENS_BREAK_ITEMS
	if #order_list > 0 and not saved_order_set["Zeus Arc Lightning"] then
		append_unique(enabled_list, "Zeus Arc Lightning")
	end
	if #order_list == 0 then order_list = fallback_items end
	if #enabled_list == 0 then enabled_list = DEFAULT_LINKENS_BREAK_ENABLED end
	ui.linkens_breaker = linkens_group:MultiSelect("Breaker Priority", build_multiselect_items(order_list, list_to_set(enabled_list), fallback_items), true)
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
			if ok_get and is_on then enabled[#enabled + 1] = id end
		end
		linkens_break_enabled_names = enabled
		if save_to_config and Config and Config.WriteString then
			Config.WriteString(ORDER_UI_CONFIG_NAME, "linkens_drag_order", table.concat(ids, ","))
			Config.WriteString(ORDER_UI_CONFIG_NAME, "linkens_drag_enabled", table.concat(enabled, ","))
		end
	end
	read_linkens(false)
	if ui.linkens_breaker and ui.linkens_breaker.SetCallback then
		ui.linkens_breaker:SetCallback(function()
			read_linkens(true)
		end, true)
	end
end

function blink_breaker.OnPrepareUnitOrders(data)
	if not ui.enabled:Get() then return end
	if not data or not data.npc or not data.ability then return end

	local hero = Heroes.GetLocal()
	if not hero or not Entity.IsAlive(hero) then return end

	local caster = data.npc
	if not caster or not Entity.IsAlive(caster) or NPC.IsIllusion(caster) then return end
	if Entity.IsSameTeam and Entity.IsSameTeam(caster, hero) then return end

	local ok_name, ability_name = pcall(Ability.GetName, data.ability)
	if not ok_name or type(ability_name) ~= "string" or not BLINK_LIKE_ABILITIES[ability_name] then
		return
	end

	local landing_pos = nil
	if data.position then
		landing_pos = data.position
	elseif data.target and Entity and Entity.GetAbsOrigin then
		landing_pos = Entity.GetAbsOrigin(data.target)
	end
	if not landing_pos then return end

	local hero_pos = Entity.GetAbsOrigin(hero)
	local radius = ui.radius and ui.radius.Get and ui.radius:Get() or 450
	local dist = distance2d(hero_pos, landing_pos)
	if dist <= radius then
		log_debug(string.format("Queued blink target %s via %s dist=%.1f", tostring(Entity.GetIndex(caster)), ability_name, dist))
		queue_target(caster, true, ability_name)
	end
end

function blink_breaker.OnUpdate()
	if not ui.enabled:Get() then return end

	local hero = Heroes.GetLocal()
	if not hero or not Entity.IsAlive(hero) then return end

	local t = now_time()
	if (t - last_cast_t) < GLOBAL_CAST_COOLDOWN then return end

	if process_linkens_followup(hero) then
		return
	end

	local radius = ui.radius and ui.radius.Get and ui.radius:Get() or 450
	local candidates = collect_candidates(hero, radius)
	for _, candidate in ipairs(candidates) do
		local handle = candidate.handle
		local enemy = candidate.enemy
		local ok_cast, reason, cast_info = cast_one_on_target(hero, enemy)
		log_debug(string.format("Try target=%s ok=%s reason=%s", tostring(handle), tostring(ok_cast), tostring(reason)))
		if ok_cast then
			last_cast_t = t
			if cast_info and cast_info.using_linkens and cast_info.ability then
				start_linkens_followup(handle, enemy, cast_info.name_id, cast_info.ability)
			else
				apply_cast_result_to_targets(hero, enemy, cast_info and cast_info.name_id or reason, cast_info and cast_info.ability or nil, t)
			end
			break
		end
		if reason == "blocked_dead"
			or reason == "blocked_invulnerable"
			or reason == "blocked_lotus_active"
			or reason == "blocked_antimage_counterspell"
			or reason == "blocked_debuff_immune"
			or reason == "blocked_magic_immune" then
			pending_targets[handle] = nil
		end
	end
end

function blink_breaker.OnGameStart()
	pending_targets = {}
	recent_target_cast_t = {}
	pending_linkens_followup = nil
	last_cast_t = -1000.0
end

function blink_breaker.OnGameEnd()
	pending_targets = {}
	recent_target_cast_t = {}
	pending_linkens_followup = nil
	last_cast_t = -1000.0
end

function blink_breaker.OnDraw()
	if not ui.enabled:Get() or not ui.draw_radius:Get() then return end
	local hero = Heroes.GetLocal()
	if not hero then return end
	local pos = Entity.GetAbsOrigin(hero)
	if not pos then return end
	local radius = ui.radius and ui.radius.Get and ui.radius:Get() or 450
	if radius <= 0.0 then return end
	draw_world_circle(pos, radius, Color(255, 50, 50, 200), 1.0, 32)
end

return blink_breaker
