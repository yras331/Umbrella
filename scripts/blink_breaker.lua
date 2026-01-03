---@diagnostic disable: undefined-global

local blink_breaker = {}

-- Create Menu
local menu_tab = Menu.Create("General", "Scripts", "Blink Breaker", "BlinkBreaker")
local main_group = menu_tab:Create("Settings")
local order_group = menu_tab:Create("Priority")

local ui = {}
ui.enabled = main_group:Switch("Enabled", true)
ui.debug_logs = main_group:Switch("Debug Logs", false)
ui.override_max_range = main_group:Switch("Override To Max Cast Range Spell/Item", false)
if ui.override_max_range and ui.override_max_range.ToolTip then
	ui.override_max_range:ToolTip("Will skip out-of-range entries and use the highest-priority enabled spell/item that is currently in cast range (based on the Priority list)")
end
ui.radius = main_group:Slider("Trigger Radius", 200, 1200, 400)
ui.draw_radius = main_group:Switch("Draw Radius", true)
ui.stop_after_cast = main_group:Switch("Stop After First Cast", true)

local SCRIPT_TAG = "[Blink Breaker]"
local function log_debug(msg)
	if not ui or not ui.debug_logs or not ui.debug_logs.Get or not ui.debug_logs:Get() then return end
	if Log and Log.Write then
		Log.Write(SCRIPT_TAG .. " " .. tostring(msg))
	else
		print(SCRIPT_TAG .. " " .. tostring(msg))
	end
end

local function update_radius_visibility()
	if not ui or not ui.radius or not ui.override_max_range or not ui.radius.Visible then return end
	local use_override = ui.override_max_range and ui.override_max_range.Get and ui.override_max_range:Get() or false
	ui.radius:Visible(not use_override)
end

update_radius_visibility()
if ui.override_max_range and ui.override_max_range.SetCallback then
	ui.override_max_range:SetCallback(function()
		update_radius_visibility()
	end, true)
end

-- Priority UI (drag + toggle) like Skywrath Combo.
local ORDER_UI_CONFIG_NAME = "blink_breaker"
local priority_enabled_names = nil -- cached {"Orchid", ...} in chosen order

local ORDER_ITEMS = {
	"Orchid",
	"Bloodthorn",
	"Eul's Scepter",
	"Lion Hex",
	"Shaman Hex",
	"Scythe of Vyse",
	"Ancient Seal",
}

local spell_map = {
	["Orchid"] = { name = "item_orchid", kind = "item" },
	["Bloodthorn"] = { name = "item_bloodthorn", kind = "item" },
	["Eul's Scepter"] = { name = "item_cyclone", kind = "item" },
	["Lion Hex"] = { name = "lion_voodoo", kind = "ability" },
	["Shaman Hex"] = { name = "shadow_shaman_voodoo", kind = "ability" },
	["Scythe of Vyse"] = { name = "item_sheepstick", kind = "item" },
	["Ancient Seal"] = { name = "skywrath_mage_ancient_seal", kind = "ability" },
}

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
	local meta = spell_map[name_id]
	if meta and meta.name then
		if meta.kind == "item" then
			local item_short = tostring(meta.name):gsub("^item_", "")
			return "panorama/images/items/" .. item_short .. "_png.vtex_c"
		elseif meta.kind == "ability" then
			return "panorama/images/spellicons/" .. tostring(meta.name) .. "_png.vtex_c"
		end
	end
	return ""
end

local function build_order_multiselect_items(order_list, enabled_set)
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
	for _, name_id in ipairs(ORDER_ITEMS) do
		push(name_id)
	end
	return items
end

order_group:Label("Drag to reorder. Toggle entries to enable/disable. Uses first enabled entry that is ready.")

do
	local saved_order = ""
	local saved_enabled = ""
	if Config and Config.ReadString then
		saved_order = Config.ReadString(ORDER_UI_CONFIG_NAME, "priority_drag_order", "")
		saved_enabled = Config.ReadString(ORDER_UI_CONFIG_NAME, "priority_drag_enabled", "")
	end

	local saved_order_list = split_csv(saved_order)
	if #saved_order_list == 0 then
		saved_order_list = ORDER_ITEMS
	end

	local enabled_default = split_csv(saved_enabled)
	if #enabled_default == 0 then
		enabled_default = ORDER_ITEMS
	end
	local enabled_set = list_to_set(enabled_default)

	local items = build_order_multiselect_items(saved_order_list, enabled_set)
	ui.priority = order_group:MultiSelect("Priority Order", items, true)
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
			if ok_get and is_on then
				enabled[#enabled + 1] = id
			end
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

-- State
local enemy_state = {} -- [handle] = {pos=Vector, visible=bool, t=number}
local last_cast_t = 0.0
local CAST_COOLDOWN = 0.1 -- Prevent spamming multiple spells in same frame if "Stop After First" is off

local now_time -- forward declaration (used by debug helpers)

local enemy_log_state = {} -- [handle] = { t = number }
local function dbg_enemy_throttled(handle, interval, msg)
	if not ui or not ui.debug_logs or not ui.debug_logs.Get or not ui.debug_logs:Get() then return end
	interval = interval or 0.25
	local t = (type(now_time) == "function" and now_time()) or os.clock()
	local st = enemy_log_state[handle]
	if st and st.t and (t - st.t) < interval then return end
	enemy_log_state[handle] = { t = t }
	log_debug(msg)
end

local function distance2d(a, b)
	if not a or not b then return 99999 end
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end


now_time = function()
	if GameRules and GameRules.GetGameTime then
		return GameRules.GetGameTime()
	end
	return os.clock()
end

local function has_modifier_name_substring(npc, needle)
	if not npc or not needle or needle == "" then return false end
	if not NPC or not NPC.GetModifiers or not Modifier or not Modifier.GetName then return false end
	local ok_mods, mods = pcall(NPC.GetModifiers, npc)
	if not ok_mods or type(mods) ~= "table" then return false end
	needle = tostring(needle)
	for _, mod in ipairs(mods) do
		local ok_name, name = pcall(Modifier.GetName, mod)
		if ok_name and type(name) == "string" and string.find(name, needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function enemy_has_ability(enemy, ability_name)
	if not enemy or not ability_name or not NPC or not NPC.GetAbility then return false end
	return NPC.GetAbility(enemy, ability_name) ~= nil
end

local function get_enabled_priority_ids()
	local enabled = priority_enabled_names
	if type(enabled) ~= "table" or #enabled == 0 then
		-- Best-effort fallback to read directly from UI.
		if not ui.priority or not ui.priority.List or not ui.priority.Get then return {} end
		local ok, ids = pcall(ui.priority.List, ui.priority)
		if not ok or type(ids) ~= "table" then return {} end
		enabled = {}
		for _, id in ipairs(ids) do
			local ok_get, is_on = pcall(ui.priority.Get, ui.priority, id)
			if ok_get and is_on then enabled[#enabled + 1] = id end
		end
	end
	return enabled
end

local function resolve_ability_or_item(hero, spell_name)
	if not hero or not spell_name or not NPC then return nil end
	local ability = NPC.GetAbility(hero, spell_name)
	if ability then return ability end
	if not NPC.GetItemByIndex or not Ability or not Ability.GetName then return nil end
	for i = 0, 20 do
		local item = NPC.GetItemByIndex(hero, i)
		if item then
			local ok_n, nm = pcall(Ability.GetName, item)
			if ok_n and nm == spell_name then
				return item
			end
		end
	end
	return nil
end

local function get_effective_cast_range(hero, ability)
	if not ability or not Ability or not Ability.GetCastRange then return 0.0 end
	local ok, r = pcall(Ability.GetCastRange, ability)
	if not ok or type(r) ~= "number" then r = 0.0 end
	if r < 0.0 then r = 0.0 end
	local bonus = (NPC and NPC.GetCastRangeBonus and hero) and (NPC.GetCastRangeBonus(hero) or 0.0) or 0.0
	return r + bonus
end

local function get_trigger_radius(hero)
	local use_override = ui.override_max_range and ui.override_max_range.Get and ui.override_max_range:Get() or false
	if not use_override then
		return ui.radius and ui.radius.Get and ui.radius:Get() or 400
	end
	-- Override mode: ignore the slider. Use max cast range among enabled + owned entries.
	local best = 0.0
	if not hero then return best end
	for _, name_id in ipairs(get_enabled_priority_ids()) do
		local meta = spell_map[name_id]
		if meta and meta.name then
			local ability = resolve_ability_or_item(hero, meta.name)
			if ability then
				local r = get_effective_cast_range(hero, ability)
				if r > best then best = r end
			end
		end
	end
	return best
end

local function get_ordered_spells()
	-- Prefer cached enabled list (updated by UI callback).
	local enabled = priority_enabled_names
	if type(enabled) ~= "table" or #enabled == 0 then
		-- Best-effort fallback to read directly from UI.
		if not ui.priority or not ui.priority.List or not ui.priority.Get then return {} end
		local ok, ids = pcall(ui.priority.List, ui.priority)
		if not ok or type(ids) ~= "table" then return {} end
		enabled = {}
		for _, id in ipairs(ids) do
			local ok_get, is_on = pcall(ui.priority.Get, ui.priority, id)
			if ok_get and is_on then enabled[#enabled + 1] = id end
		end
	end
	local out = {}
	for _, name_id in ipairs(enabled) do
		local meta = spell_map[name_id]
		if meta and meta.name then
			out[#out + 1] = meta.name
		end
	end
	return out
end

local function cast_spell(hero, target, spell_name)
	local ability = NPC.GetAbility(hero, spell_name)
	if not ability then
		-- Check items
		for i = 0, 5 do
			local item = NPC.GetItemByIndex(hero, i)
			if item and Ability.GetName(item) == spell_name then
				ability = item
				break
			end
		end
	end

	if not ability then return false, "not_found" end
	local mana = (NPC and NPC.GetMana and NPC.GetMana(hero)) or 0.0
	if not Ability.IsCastable(ability, mana) then return false, "not_castable" end
	if not Ability.IsReady(ability) then return false, "not_ready" end
	
	-- Range check (optional, but good practice, though we only trigger if close)
	-- Some spells might have short range (e.g. Hex is usually 500-800, Radius might be 1200)
	-- If radius > cast range, we should probably not cast or walk? 
	-- User said "instantly cast". Walking takes time. 
	-- If out of range, we skip.
	local range = Ability.GetCastRange(ability)
	if range and range > 0 then
		local dist = distance2d(Entity.GetAbsOrigin(hero), Entity.GetAbsOrigin(target))
		local bonus = (NPC and NPC.GetCastRangeBonus and NPC.GetCastRangeBonus(hero)) or 0.0
		if dist > (range + bonus) then
			return false, string.format("out_of_range dist=%.1f range=%.1f bonus=%.1f", dist, range, bonus)
		end
	end

	Ability.CastTarget(ability, target, false, false, false)
	return true, "cast"
end

function blink_breaker.OnUpdate()
	if not ui.enabled:Get() then return end
	local hero = Heroes.GetLocal()
	if not hero or not Entity.IsAlive(hero) then return end

	local t = now_time()
	local my_pos = Entity.GetAbsOrigin(hero)
	local radius = get_trigger_radius(hero)
	local my_team = Entity.GetTeamNum(hero)
	local enemies = Heroes.InRadius(my_pos, 2500, my_team, Enum.TeamType.TEAM_ENEMY)

	for _, enemy in ipairs(enemies) do
		if Entity.IsAlive(enemy) and not NPC.IsIllusion(enemy) then
			local handle = Entity.GetIndex(enemy)
			local pos = Entity.GetAbsOrigin(enemy)
			local visible = not Entity.IsDormant(enemy) -- IsDormant usually means FOW
			-- Better visibility check:
			-- Entity.IsDormant is true if entity is not updated (in fog).
			
			local prev = enemy_state[handle]
			local triggered = false
			local trigger_reason = nil

				if visible and radius and radius > 0.0 then
				local dist = distance2d(my_pos, pos)
				local is_void_trace = enemy_has_ability(enemy, "faceless_void_time_walk")
				local is_phoenix_trace = enemy_has_ability(enemy, "phoenix_icarus_dive")
				if (is_void_trace or is_phoenix_trace) and dist <= (radius + 250) then
					local prev_dist_dbg = prev and prev.pos and distance2d(my_pos, prev.pos) or -1
					local delta_dbg = prev and prev.pos and distance2d(pos, prev.pos) or -1
					local dt_dbg = prev and prev.t and (t - prev.t) or -1
					local speed_dbg = -1
					if dt_dbg and dt_dbg > 0 and delta_dbg and delta_dbg >= 0 then speed_dbg = delta_dbg / dt_dbg end
					local doing_tw = is_void_trace and has_modifier_name_substring(enemy, "time_walk")
					local doing_dive = is_phoenix_trace and has_modifier_name_substring(enemy, "icarus_dive")
					local prev_gap_dbg = prev and prev.gapclose_active == true
					local prev_dash_dbg = prev and prev.fast_dash_active == true
					local prev_in_dbg = prev and prev.in_radius == true
					dbg_enemy_throttled(handle, 0.20, string.format(
						"[GAP TRACE] handle=%s vis=%s dist=%.1f rad=%.1f prev_vis=%s prev_in=%s prev_gap=%s prev_dash=%s prev_dist=%.1f delta=%.1f dt=%.3f speed=%.1f tw_mod=%s dive_mod=%s",
						tostring(handle), tostring(visible), dist, radius, tostring(prev and prev.visible), tostring(prev_in_dbg), tostring(prev_gap_dbg), tostring(prev_dash_dbg), prev_dist_dbg, delta_dbg, dt_dbg, speed_dbg, tostring(doing_tw), tostring(doing_dive)
					))
				end
				
				if dist <= radius then
					if not prev then
						-- First time seeing them, and they are close.
						-- Could be game start, or appeared from fog.
						-- If game time is > 0 and we just saw them close, trigger.
						triggered = true
						trigger_reason = "first_seen_close"
					elseif not prev.visible then
						-- Was not visible, now visible and close.
						-- Blinked out of fog or invis.
						triggered = true
						trigger_reason = "became_visible_close"
					else
						-- Was visible. Check displacement.
						local prev_dist = distance2d(my_pos, prev.pos)
						local delta = distance2d(pos, prev.pos)
						local dt = (prev.t and (t - prev.t)) or 0.0
						if dt <= 0.0 then dt = 0.03 end
						local speed = delta / dt

						-- Explicit gap-closers: Time Walk / Icarus Dive.
						-- We detect these while the enemy is visible using their movement modifiers
						-- (substring match). To avoid spamming while the modifier persists, we only
						-- trigger on the "start" edge (wasn't active last tick).
						local is_void = enemy_has_ability(enemy, "faceless_void_time_walk")
						local is_phoenix = enemy_has_ability(enemy, "phoenix_icarus_dive")
						local doing_time_walk = is_void and has_modifier_name_substring(enemy, "time_walk")
						local doing_icarus_dive = is_phoenix and has_modifier_name_substring(enemy, "icarus_dive")
						local gapclose_active = (doing_time_walk or doing_icarus_dive) == true
						local gapclose_started = gapclose_active and (prev.gapclose_active ~= true)

						-- Heuristic fallback for ultra-fast movement (covers cases where modifier name
						-- doesn't match exactly). Keep conservative to reduce false positives.
						local fast_dash = (dt <= 0.25) and (delta >= 220) and (speed >= 900)
						local dash_started = fast_dash and (prev.fast_dash_active ~= true)

						-- If they were outside radius (with buffer) and now inside
						-- OR they moved a large distance instantly (blink)
						if (delta > 300) then
							triggered = true
							trigger_reason = "big_delta"
						elseif (prev_dist > radius + 100) then
							triggered = true
							trigger_reason = "outside_to_inside"
						else
							-- Trigger if a gap-close starts while they're already within radius too.
							if gapclose_started or dash_started then
								triggered = true
								trigger_reason = gapclose_started and "gapclose_started" or "fast_dash_started"
							else
								-- If Time Walk / Dive started outside our radius, we can miss the "start" edge.
								-- Trigger when they cross into radius while the gap-close is active (even if
								-- they were only slightly outside the edge last tick).
								if gapclose_active and (prev_dist > radius) then
									triggered = true
									trigger_reason = "entered_radius_gapclose"
								else
									-- Also trigger on a significant in-radius jump while the gap-close is active,
									-- even if the modifier started earlier.
									local prev_in_radius = prev and prev.in_radius == true
									local last_gap_t = prev and prev.last_gap_trigger_t or 0.0
									local since_last_gap = t - (last_gap_t or 0.0)
									local closing = (prev_dist - dist)
									if gapclose_active and prev_in_radius and since_last_gap >= 0.5 then
										if (delta >= 80) or (speed >= 700) or (closing >= 60) then
											triggered = true
											trigger_reason = "gapclose_inside_move"
										end
									end
								end
							end
						end
					end
				end
			end

			-- Update state
			local gapclose_active_now = false
			local fast_dash_active_now = false
			local in_radius_now = false
			local last_gap_trigger_t_now = prev and prev.last_gap_trigger_t or 0.0
			if visible and prev and prev.pos and prev.t then
				-- Recompute the current gap-close flags to store.
				local is_void = enemy_has_ability(enemy, "faceless_void_time_walk")
				local is_phoenix = enemy_has_ability(enemy, "phoenix_icarus_dive")
				gapclose_active_now = ((is_void and has_modifier_name_substring(enemy, "time_walk"))
					or (is_phoenix and has_modifier_name_substring(enemy, "icarus_dive"))) == true
				local delta = distance2d(pos, prev.pos)
				local dt = (t - prev.t)
				if dt <= 0.0 then dt = 0.03 end
				local speed = delta / dt
				fast_dash_active_now = (dt <= 0.25) and (delta >= 220) and (speed >= 900)
			end
			if radius and radius > 0.0 then
				in_radius_now = distance2d(my_pos, pos) <= radius
			end
			if triggered and (trigger_reason == "gapclose_started" or trigger_reason == "entered_radius_gapclose" or trigger_reason == "gapclose_inside_move" or trigger_reason == "fast_dash_started") then
				last_gap_trigger_t_now = t
			end
			enemy_state[handle] = {
				pos = pos,
				visible = visible,
				t = t,
				gapclose_active = gapclose_active_now,
				fast_dash_active = fast_dash_active_now,
				in_radius = in_radius_now,
				last_gap_trigger_t = last_gap_trigger_t_now,
			}

			if triggered then
				log_debug(string.format(
					"[TRIGGER] handle=%s reason=%s vis=%s dist=%.1f rad=%.1f gapclose_now=%s dash_now=%s",
					tostring(handle), tostring(trigger_reason), tostring(visible), distance2d(my_pos, pos), radius, tostring(gapclose_active_now), tostring(fast_dash_active_now)
				))
				-- Check for magic immunity / invulnerability
				local magic_immune = (NPC and NPC.IsMagicImmune) and NPC.IsMagicImmune(enemy) or false
				local invuln = (Entity and Entity.IsInvulnerable) and Entity.IsInvulnerable(enemy) or false
				if magic_immune or invuln then
					log_debug(string.format("[BLOCK] handle=%s magic_immune=%s invuln=%s", tostring(handle), tostring(magic_immune), tostring(invuln)))
				end
				if not magic_immune and not invuln then
					local use_max_range = ui.override_max_range and ui.override_max_range.Get and ui.override_max_range:Get() or false
					if use_max_range then
						-- "In-range override": still respects priority order, but skips spells/items
						-- that are out of cast range, so we always cast the highest-priority option
						-- that is actually in range right now.
						local dist = distance2d(my_pos, pos)
						local chosen = nil
						for _, name_id in ipairs(get_enabled_priority_ids()) do
							local meta = spell_map[name_id]
							if meta and meta.name then
								local ability = resolve_ability_or_item(hero, meta.name)
								if ability and Ability and Ability.IsReady and Ability.IsCastable and NPC and NPC.GetMana then
									local mana = NPC.GetMana(hero) or 0.0
									if Ability.IsReady(ability) and Ability.IsCastable(ability, mana) then
										local r = get_effective_cast_range(hero, ability)
										if r <= 0.0 or dist <= r then
											chosen = meta.name
											log_debug(string.format("[SELECT] mode=override pick=%s dist=%.1f range=%.1f", tostring(chosen), dist, r))
											break
										else
											log_debug(string.format("[SELECT] skip=%s reason=out_of_range dist=%.1f range=%.1f", tostring(meta.name), dist, r))
										end
									else
										log_debug(string.format("[SELECT] skip=%s reason=not_ready_or_not_castable", tostring(meta.name)))
									end
								else
									log_debug(string.format("[SELECT] skip=%s reason=not_owned", tostring(meta.name)))
								end
							end
						end
						if not chosen then
							log_debug("[CAST] mode=override result=no_spell_selected")
						else
							local ok_cast, reason = cast_spell(hero, enemy, chosen)
							log_debug(string.format("[CAST] mode=override spell=%s ok=%s reason=%s", tostring(chosen), tostring(ok_cast), tostring(reason)))
							if ok_cast then
								last_cast_t = t
							end
						end
					else
						local spell_list = get_ordered_spells()
						log_debug(string.format("[CAST] mode=normal candidates=%s", tostring(#spell_list)))
						for _, spell_id in ipairs(spell_list) do
							local ok_cast, reason = cast_spell(hero, enemy, spell_id)
							log_debug(string.format("[CAST] try=%s ok=%s reason=%s", tostring(spell_id), tostring(ok_cast), tostring(reason)))
							if ok_cast then
								last_cast_t = t
								if ui.stop_after_cast:Get() then break end
							end
						end
					end
				end
			end
		end
	end
end

function blink_breaker.OnDraw()
	if not ui.enabled:Get() or not ui.draw_radius:Get() then return end
	local hero = Heroes.GetLocal()
	if not hero then return end
	
	local radius = get_trigger_radius(hero)
	if not radius or radius <= 0.0 then return end
	local pos = Entity.GetAbsOrigin(hero)
	if not pos then return end
	if Render and Render.WorldToScreen and Render.Line then
		local points = {}
		local steps = 32
		for i = 1, steps do
			local angle = (i / steps) * 2 * math.pi
			local x = pos.x + radius * math.cos(angle)
			local y = pos.y + radius * math.sin(angle)
			local z = pos.z
			local p_screen, on_screen = Render.WorldToScreen(Vector(x, y, z))
			if on_screen then
				points[#points + 1] = p_screen
			end
		end
		
		if #points >= 2 then
			for i = 1, #points do
				local p1 = points[i]
				local p2 = points[(i % #points) + 1]
				Render.Line(p1, p2, Color(255, 50, 50, 200), 1)
			end
		end
	end
end

return blink_breaker
