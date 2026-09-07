---@diagnostic disable: undefined-global
-- ============================================================================
-- Umbrella Framework v1.0 — Core Library for MCP API V2.0 Lua Scripts
-- ============================================================================
-- Drop this file in scripts/lib/ and dofile() it from your scripts:
--   local U = dofile("scripts/lib/umbrella.lua")
-- ============================================================================

local Umbrella = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

Umbrella.COOLDOWN_CONFIRM_GRACE = 0.08
Umbrella.COOLDOWN_CONFIRM_EXTRA = 0.15
Umbrella.ITEM_SLOT_MAX = 20
Umbrella.BACKPACK_START = 6
Umbrella.BACKPACK_END = 8

-- ═══════════════════════════════════════════════════════════════════════════
-- TIME HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Get current game time (fallback to os.clock if API unavailable).
function Umbrella.now()
  if GameRules and GameRules.GetGameTime then
    local ok, t = pcall(GameRules.GetGameTime)
    if ok and type(t) == "number" then return t end
  end
  return os.clock()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LOGGING
-- ═══════════════════════════════════════════════════════════════════════════

--- Log a message with a script tag prefix.
--- @param tag string  e.g. "[My Script]"
--- @param msg any     message to log
function Umbrella.log(tag, msg)
  local text = tag .. " " .. tostring(msg)
  if Log and Log.Write then
    Log.Write(text)
  else
    print(text)
  end
end

--- Create a debug-logger closure that respects a UI switch.
--- @param tag string        script tag
--- @param getEnabled function  returns boolean
--- @return function  log_debug(msg)
function Umbrella.makeDebugLogger(tag, getEnabled)
  return function(msg)
    if getEnabled and getEnabled() then
      Umbrella.log(tag, msg)
    end
  end
end

--- Log info unconditionally (always prints).
--- @param tag string
--- @param msg any
function Umbrella.logInfo(tag, msg)
  local text = tag .. " " .. tostring(msg)
  if Log and Log.Write then Log.Write(text) else print(text) end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SAFE API CALLS
-- ═══════════════════════════════════════════════════════════════════════════

--- Safe pcall wrapper. Returns nil on error.
--- @param fn function
--- @param ... any
--- @return any
function Umbrella.safeCall(fn, ...)
  local ok, result = pcall(fn, ...)
  if ok then return result end
  return nil
end

--- Safe method call on an object.
--- @param obj table
--- @param method string
--- @param ... any
--- @return any
function Umbrella.safeMethod(obj, method, ...)
  if not obj or type(obj[method]) ~= "function" then return nil end
  local ok, result = pcall(obj[method], obj, ...)
  if ok then return result end
  return nil
end

--- Safe index-based item retrieval.
function Umbrella.getItemByIndex(npc, index)
  if not npc or not NPC or not NPC.GetItemByIndex then return nil end
  return Umbrella.safeCall(NPC.GetItemByIndex, npc, index)
end

--- Safe ability retrieval.
function Umbrella.getAbility(npc, name)
  if not npc or not NPC or not NPC.GetAbility then return nil end
  return Umbrella.safeCall(NPC.GetAbility, npc, name)
end

--- Safe ability name getter.
function Umbrella.getAbilityName(ability)
  if not ability or not Ability or not Ability.GetName then return nil end
  return Umbrella.safeCall(Ability.GetName, ability)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MATH / DISTANCE
-- ═══════════════════════════════════════════════════════════════════════════

--- 2D distance between two position vectors.
function Umbrella.distance(a, b)
  if not a or not b then return 999999.0 end
  local dx = (a.x or 0.0) - (b.x or 0.0)
  local dy = (a.y or 0.0) - (b.y or 0.0)
  return math.sqrt(dx * dx + dy * dy)
end

--- Clamp a number between lo and hi.
function Umbrella.clamp(v, lo, hi, fallback)
  if type(v) ~= "number" then return fallback or lo end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ENTITY HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Get entity index (safe).
function Umbrella.entityIndex(ent)
  if not ent or not Entity or not Entity.GetIndex then return -1 end
  local idx = Umbrella.safeCall(Entity.GetIndex, ent)
  if type(idx) == "number" then return idx end
  return -1
end

--- Compare two entities by index.
function Umbrella.entityEqual(a, b)
  if not a or not b then return false end
  if a == b then return true end
  return Umbrella.entityIndex(a) == Umbrella.entityIndex(b)
end

--- Check if entity is alive.
function Umbrella.isAlive(ent)
  if not ent or not Entity or not Entity.IsAlive then return false end
  local ok, alive = pcall(Entity.IsAlive, ent)
  return ok and alive == true
end

--- Check if entity is invulnerable.
function Umbrella.isInvulnerable(ent)
  if not ent or not Entity or not Entity.IsInvulnerable then return false end
  local ok, inv = pcall(Entity.IsInvulnerable, ent)
  return ok and inv == true
end

--- Check if two entities are on the same team.
function Umbrella.isSameTeam(a, b)
  if not a or not b then return false end
  if Entity and Entity.IsSameTeam then
    local ok, same = pcall(Entity.IsSameTeam, a, b)
    if ok then return same == true end
  end
  if Entity and Entity.GetTeamNum then
    local ta = Umbrella.safeCall(Entity.GetTeamNum, a)
    local tb = Umbrella.safeCall(Entity.GetTeamNum, b)
    if type(ta) == "number" and type(tb) == "number" then return ta == tb end
  end
  return false
end

--- Get team number.
function Umbrella.getTeamNum(ent)
  if not ent or not Entity or not Entity.GetTeamNum then return nil end
  return Umbrella.safeCall(Entity.GetTeamNum, ent)
end

--- Get entity position.
function Umbrella.getPos(ent)
  if not ent or not Entity or not Entity.GetAbsOrigin then return nil end
  return Umbrella.safeCall(Entity.GetAbsOrigin, ent)
end

--- Get unit name (safe).
function Umbrella.getUnitName(unit)
  if not unit then return nil end
  if NPC and NPC.GetUnitName then
    local n = Umbrella.safeCall(NPC.GetUnitName, unit)
    if n then return n end
  end
  if Entity and Entity.GetUnitName then
    return Umbrella.safeCall(Entity.GetUnitName, unit)
  end
  return nil
end

--- Check if unit is an illusion.
function Umbrella.isIllusion(unit)
  if not unit or not NPC then return false end
  if NPC.IsIllusion then
    local ok, v = pcall(NPC.IsIllusion, unit)
    if ok then return v == true end
  end
  return false
end

--- Check if unit is a hero.
function Umbrella.isHero(unit)
  if not unit or not NPC then return false end
  if NPC.IsHero then
    local ok, v = pcall(NPC.IsHero, unit)
    if ok then return v == true end
  end
  local name = Umbrella.getUnitName(unit)
  return type(name) == "string" and string.find(name, "npc_dota_hero_", 1, true) ~= nil
end

--- Check if unit is a creep.
function Umbrella.isCreep(unit)
  if not unit then return false end
  if NPC then
    if NPC.IsCreep then
      local ok, v = pcall(NPC.IsCreep, unit)
      if ok and v then return true end
    end
    if NPC.IsLaneCreep then
      local ok, v = pcall(NPC.IsLaneCreep, unit)
      if ok and v then return true end
    end
    if NPC.IsNeutral then
      local ok, v = pcall(NPC.IsNeutral, unit)
      if ok and v then return true end
    end
  end
  local name = Umbrella.getUnitName(unit)
  if type(name) == "string" then
    if string.find(name, "npc_dota_creep", 1, true) then return true end
    if string.find(name, "npc_dota_neutral", 1, true) then return true end
  end
  return false
end

--- Check debuff immune.
function Umbrella.isDebuffImmune(unit)
  if not unit or not NPC or not NPC.IsDebuffImmune then return false end
  local ok, v = pcall(NPC.IsDebuffImmune, unit)
  return ok and v == true
end

--- Check magic immune.
function Umbrella.isMagicImmune(unit)
  if not unit or not NPC or not NPC.IsMagicImmune then return false end
  local ok, v = pcall(NPC.IsMagicImmune, unit)
  return ok and v == true
end

--- Check if target is blocked (dead, invulnerable, debuff/magic immune, etc.)
--- @return boolean blocked, string|nil reason
function Umbrella.isTargetBlocked(target, opts)
  opts = opts or {}
  if not Umbrella.isAlive(target) then return true, "dead" end
  if Umbrella.isInvulnerable(target) then return true, "invulnerable" end
  if Umbrella.isDebuffImmune(target) then return true, "debuff_immune" end
  if Umbrella.isMagicImmune(target) then return true, "magic_immune" end

  if NPC and NPC.HasModifier then
    if Umbrella.safeCall(NPC.HasModifier, target, "modifier_antimage_counterspell")
      or Umbrella.safeCall(NPC.HasModifier, target, "modifier_antimage_counterspell_active") then
      return true, "antimage_counterspell"
    end
    if not opts.ignore_lotus then
      if Umbrella.safeCall(NPC.HasModifier, target, "modifier_item_lotus_orb_active") then
        return true, "lotus_active"
      end
    end
  end
  return false, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ABILITY/ITEM HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Safe cast point retrieval (clamped to reasonable range).
--- @param ability table
--- @param min_cp number  minimum clamp (default 0.05)
--- @param max_cp number  maximum clamp (default 0.60)
function Umbrella.getCastPoint(ability, min_cp, max_cp)
  if not ability or not Ability or not Ability.GetCastPoint then return 0.10 end
  local cp = Umbrella.safeCall(Ability.GetCastPoint, ability)
  if type(cp) ~= "number" then return 0.10 end
  min_cp = min_cp or 0.05
  max_cp = max_cp or 0.60
  if cp < min_cp then cp = min_cp end
  if cp > max_cp then cp = max_cp end
  return cp
end

--- Safe ability special value reader.
function Umbrella.getSpecialValue(ability, key)
  if not ability or not key or not Ability then return nil end
  if Ability.GetSpecialValueFor then
    local v = Umbrella.safeCall(Ability.GetSpecialValueFor, ability, key)
    if type(v) == "number" then return v end
  end
  if Ability.GetLevelSpecialValueFor then
    local v = Umbrella.safeCall(Ability.GetLevelSpecialValueFor, ability, key)
    if type(v) == "number" then return v end
  end
  return nil
end

--- Get cooldown remaining.
function Umbrella.getCooldownRemaining(ability)
  if not ability or not Ability or not Ability.GetCooldown then return nil end
  return Umbrella.safeCall(Ability.GetCooldown, ability)
end

--- Check if ability has entered cooldown (started casting, ignoring silence/stun).
function Umbrella.isCooldownStarted(ability)
  if not ability then return false end
  -- Check cooldown directly first (most reliable signal)
  local cd = Umbrella.getCooldownRemaining(ability)
  if type(cd) == "number" and cd > 0.0 then return true end
  -- IsReady can return false for reasons OTHER than cooldown (silence, stun, no mana).
  -- Only treat IsReady=false as "cooldown started" if cooldown API is unavailable.
  if not (Ability and Ability.GetCooldown) and Ability and Ability.IsReady then
    if not Umbrella.safeCall(Ability.IsReady, ability) then return true end
  end
  return false
end

--- Check if ability/item is ready and castable.
--- @param ability table
--- @param mana number|nil  current mana (fetched automatically if nil)
function Umbrella.isReady(ability, mana)
  if not ability then return false end
  if Ability and Ability.IsReady then
    if not Umbrella.safeCall(Ability.IsReady, ability) then return false end
  end
  if Ability and Ability.IsCastable then
    if mana == nil and NPC and NPC.GetMana then
      local hero = Heroes.GetLocal()
      if hero then mana = Umbrella.safeCall(NPC.GetMana, hero) or 0.0 end
    end
    if mana ~= nil and not Umbrella.safeCall(Ability.IsCastable, ability, mana) then
      return false
    end
  end
  return true
end

--- Get cast range with bonuses.
function Umbrella.getCastRange(hero, ability)
  if not ability or not Ability then return 0.0 end
  local range = 0.0
  if Ability.GetCastRange then
    range = Umbrella.safeCall(Ability.GetCastRange, ability) or 0.0
  end
  if range <= 0.0 and Ability.GetLevelSpecialValueFor then
    range = Umbrella.safeCall(Ability.GetLevelSpecialValueFor, ability, "cast_range") or 0.0
  end
  if range > 0.0 and NPC and NPC.GetCastRangeBonus and hero then
    local bonus = Umbrella.safeCall(NPC.GetCastRangeBonus, hero)
    if type(bonus) == "number" then range = range + bonus end
  end
  if range < 0.0 then range = 0.0 end
  return range
end

--- Get attack range.
function Umbrella.getAttackRange(hero)
  if not hero then return 380.0 end
  if NPC and NPC.GetTrueAttackRange then
    local r = Umbrella.safeCall(NPC.GetTrueAttackRange, hero)
    if type(r) == "number" and r > 0.0 then return r end
  end
  local range = nil
  if NPC and NPC.GetAttackRange then
    range = Umbrella.safeCall(NPC.GetAttackRange, hero)
  end
  if (not range or range <= 0.0) and Entity and Entity.GetAttackRange then
    range = Umbrella.safeCall(Entity.GetAttackRange, hero)
  end
  return (type(range) == "number" and range > 0.0) and range or 380.0
end

--- Get hull radius.
function Umbrella.getHullRadius(unit)
  if not unit then return 0.0 end
  if NPC and NPC.GetHullRadius then
    local r = Umbrella.safeCall(NPC.GetHullRadius, unit)
    if type(r) == "number" and r > 0.0 then return r end
  end
  if Entity and Entity.GetHullRadius then
    local r = Umbrella.safeCall(Entity.GetHullRadius, unit)
    if type(r) == "number" and r > 0.0 then return r end
  end
  return 0.0
end

--- Get AOE increase percentage.
function Umbrella.getAoeIncrease(hero)
  local v = nil
  if NPC and NPC.GetAOEIncrease then v = Umbrella.safeCall(NPC.GetAOEIncrease, hero) end
  if v == nil and NPC and NPC.GetAoEIncrease then v = Umbrella.safeCall(NPC.GetAoEIncrease, hero) end
  if type(v) ~= "number" then return 0.0 end
  if v > 1.0 then return v / 100.0 end
  if v < 0.0 then v = 0.0 end
  return v
end

--- Check if hero has Aghanim's Scepter (item + modifier).
function Umbrella.hasAghs(hero)
  if not hero then return false end
  if NPC and NPC.GetItemByIndex then
    for i = 0, Umbrella.ITEM_SLOT_MAX do
      local item = Umbrella.getItemByIndex(hero, i)
      if item then
        local nm = Umbrella.getAbilityName(item)
        if nm == "item_ultimate_scepter" or nm == "item_ultimate_scepter_2" or nm == "item_ultimate_scepter_roshan" then
          return true
        end
      end
    end
  end
  if NPC and NPC.HasModifier then
    if Umbrella.safeCall(NPC.HasModifier, hero, "modifier_item_ultimate_scepter") then return true end
    if Umbrella.safeCall(NPC.HasModifier, hero, "modifier_item_ultimate_scepter_consumed") then return true end
    if Umbrella.safeCall(NPC.HasModifier, hero, "modifier_item_ultimate_scepter_2") then return true end
    if Umbrella.safeCall(NPC.HasModifier, hero, "modifier_alchemist_aghanims_scepter") then return true end
    if Umbrella.safeCall(NPC.HasModifier, hero, "modifier_alchemist_aghanims_scepter_buff") then return true end
    if Umbrella.safeCall(NPC.HasModifier, hero, "modifier_item_ultimate_scepter_consumed_alchemist") then return true end
  end
  return false
end

--- Check if hero has learned a talent/facette ability.
function Umbrella.hasLearnedAbility(hero, abilityName)
  if not hero or not abilityName then return false end
  local talent = Umbrella.getAbility(hero, abilityName)
  if not talent then return false end
  if Ability and Ability.GetLevel then
    local level = Umbrella.safeCall(Ability.GetLevel, talent)
    return type(level) == "number" and level > 0
  end
  return false
end

--- Get unit health (safe).
function Umbrella.getHealth(unit)
  if not unit then return nil end
  if NPC and NPC.GetHealth then
    local hp = Umbrella.safeCall(NPC.GetHealth, unit)
    if type(hp) == "number" then return hp end
  end
  if Entity and Entity.GetHealth then
    return Umbrella.safeCall(Entity.GetHealth, unit)
  end
  return nil
end

--- Get unit mana (safe).
function Umbrella.getMana(unit)
  if not unit then return nil end
  if NPC and NPC.GetMana then
    return Umbrella.safeCall(NPC.GetMana, unit)
  end
  return nil
end

--- Find an item on a hero by name (checks all slots, returns first match).
--- @param hero table
--- @param itemName string  e.g. "item_manta"
--- @return table|nil
function Umbrella.findItem(hero, itemName)
  if not hero or not itemName then return nil end
  for i = 0, Umbrella.ITEM_SLOT_MAX do
    local item = Umbrella.getItemByIndex(hero, i)
    if item then
      local nm = Umbrella.getAbilityName(item)
      if nm == itemName then return item end
    end
  end
  return nil
end

--- Find an item where the name starts with a prefix (for dagon variants).
function Umbrella.findItemPrefix(hero, prefix)
  if not hero or not prefix then return nil end
  for i = 0, Umbrella.ITEM_SLOT_MAX do
    local item = Umbrella.getItemByIndex(hero, i)
    if item then
      local nm = Umbrella.getAbilityName(item)
      if nm and string.find(nm, prefix, 1, true) == 1 then return item end
    end
  end
  return nil
end

--- Resolve a spell meta entry to an actual ability/item handle.
--- @param hero table
--- @param spellMeta {name:string, kind:string, aliases?:table, dagon?:boolean}
--- @return table|nil, string  (handle, location: "ability"|"inventory"|"backpack"|"missing")
function Umbrella.resolveSpell(hero, spellMeta)
  if not hero or not spellMeta then return nil, "invalid" end
  if spellMeta.kind == "ability" then
    return Umbrella.getAbility(hero, spellMeta.name), "ability"
  end
  if not NPC or not NPC.GetItemByIndex then return nil, "api_missing" end
  local foundBackpack = false
  for i = 0, Umbrella.ITEM_SLOT_MAX do
    local item = Umbrella.getItemByIndex(hero, i)
    if item then
      local nm = Umbrella.getAbilityName(item)
      local inBackpack = i >= Umbrella.BACKPACK_START and i <= Umbrella.BACKPACK_END
      if nm == spellMeta.name then
        if inBackpack then foundBackpack = true else return item, "inventory" end
      end
      -- Check aliases
      if spellMeta.aliases and type(spellMeta.aliases) == "table" then
        for _, alias in ipairs(spellMeta.aliases) do
          if nm == alias then
            if inBackpack then foundBackpack = true else return item, "inventory" end
          end
        end
      end
      -- Dagon variants
      if spellMeta.dagon and nm and string.find(nm, "^item_dagon") then
        if inBackpack then foundBackpack = true else return item, "inventory" end
      end
    end
  end
  if foundBackpack then return nil, "backpack" end
  return nil, "missing"
end

--- Check if target has Linken's Sphere active.
function Umbrella.hasLinkens(target)
  if not target then return false end
  local sphere = Umbrella.findItem(target, "item_sphere")
  if sphere then
    -- Prefer IsReady for accuracy (accounts for silence/stun blocking active use)
    if Ability and Ability.IsReady then
      local ready = Umbrella.safeCall(Ability.IsReady, sphere)
      if ready == true then return true end
    end
    -- Fallback to cooldown check if IsReady unavailable
    if Ability and not Ability.IsReady and Ability.GetCooldown then
      local cd = Umbrella.getCooldownRemaining(sphere)
      if type(cd) == "number" and cd <= 0.0 then return true end
    end
  end
  if NPC and NPC.HasModifier then
    if Umbrella.safeCall(NPC.HasModifier, target, "modifier_item_sphere_target") then return true end
    if Umbrella.safeCall(NPC.HasModifier, target, "modifier_item_sphere_target_buff") then return true end
  end
  return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PROJECTILE HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if an ability has projectile speed (indicating projectile-based delivery).
function Umbrella.hasProjectileSpeed(ability)
  if not ability then return false end
  local speed = Umbrella.getSpecialValue(ability, "projectile_speed")
  if type(speed) == "number" and speed > 0 then return true end
  speed = Umbrella.getSpecialValue(ability, "projectile_speed_tooltip")
  if type(speed) == "number" and speed > 0 then return true end
  speed = Umbrella.getSpecialValue(ability, "arrow_speed")
  if type(speed) == "number" and speed > 0 then return true end
  return false
end

--- Normalize impact time (handle absolute vs relative timing).
function Umbrella.normalizeImpactTime(value, tNow)
  if type(value) ~= "number" or value <= 0.0 then return nil end
  if value < 15.0 and tNow > 15.0 then return tNow + value end
  if value < (tNow - 0.5) then return tNow + value end
  return value
end

--- Compute projectile travel time.
function Umbrella.projectileTravelTime(sourcePos, targetPos, speed)
  if not sourcePos or not targetPos or not speed or speed <= 0 then return 0.0 end
  return Umbrella.distance(sourcePos, targetPos) / speed
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COLLECTION HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Split a CSV string.
function Umbrella.splitCSV(s)
  if type(s) ~= "string" or s == "" then return {} end
  local out = {}
  for token in string.gmatch(s, "[^,]+") do
    token = tostring(token):gsub("^%s+", ""):gsub("%s+$", "")
    if token ~= "" then out[#out + 1] = token end
  end
  return out
end

--- Convert a list to a set (lookup table).
function Umbrella.listToSet(list)
  local set = {}
  if type(list) ~= "table" then return set end
  for _, v in ipairs(list) do
    if v ~= nil then set[v] = true end
  end
  return set
end

--- Convert a set to an ordered list (optionally respecting fallback_order).
function Umbrella.setToList(set, fallbackOrder)
  local out = {}
  if type(set) ~= "table" then return out end
  if type(fallbackOrder) == "table" then
    for _, id in ipairs(fallbackOrder) do
      if set[id] then out[#out + 1] = id end
    end
    return out
  end
  for id, on in pairs(set) do
    if on then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

--- Append to list if not already present.
function Umbrella.appendUnique(list, value)
  if type(list) ~= "table" or value == nil then return end
  for _, existing in ipairs(list) do
    if existing == value then return end
  end
  list[#list + 1] = value
end

--- Filter a list to only values present in an allowed set.
function Umbrella.filterList(list, allowedSet)
  local out = {}
  if type(list) ~= "table" or type(allowedSet) ~= "table" then return out end
  for _, v in ipairs(list) do
    if allowedSet[v] then Umbrella.appendUnique(out, v) end
  end
  return out
end

--- Build order list with detected items first, then remaining.
function Umbrella.detectedFirstOrder(allIds, detectedSet)
  local out = {}
  local seen = {}
  for _, id in ipairs(allIds or {}) do
    if detectedSet and detectedSet[id] then
      out[#out + 1] = id
      seen[id] = true
    end
  end
  for _, id in ipairs(allIds or {}) do
    if not seen[id] then out[#out + 1] = id end
  end
  return out
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ICON PATH RESOLUTION
-- ═══════════════════════════════════════════════════════════════════════════

--- Resolve item icon panorama path.
function Umbrella.itemIconPath(itemName)
  local short = tostring(itemName):gsub("^item_", "")
  return "panorama/images/items/" .. short .. "_png.vtex_c"
end

--- Resolve ability icon panorama path.
function Umbrella.abilityIconPath(abilityName)
  return "panorama/images/spellicons/" .. tostring(abilityName) .. "_png.vtex_c"
end

--- Resolve icon path from a spell meta entry.
function Umbrella.spellIconPath(spellMeta)
  if not spellMeta or not spellMeta.name then return "" end
  if spellMeta.kind == "item" then
    return Umbrella.itemIconPath(spellMeta.name)
  end
  return Umbrella.abilityIconPath(spellMeta.name)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MULTISELECT UI HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Build MultiSelect items array.
--- @param orderList table  ordered list of nameIds
--- @param enabledSet table  set of enabled nameIds
--- @param fallbackItems table  items to include even if not in orderList
--- @param iconFn function(nameId) -> string  icon path resolver
--- @return table  {{nameId, imagePath, isEnabled}, ...}
function Umbrella.buildMultiSelectItems(orderList, enabledSet, fallbackItems, iconFn)
  local items = {}
  local seen = {}
  iconFn = iconFn or function(id) return "" end
  local function push(nameId)
    if not nameId or seen[nameId] then return end
    seen[nameId] = true
    items[#items + 1] = { nameId, iconFn(nameId), enabledSet[nameId] == true }
  end
  if type(orderList) == "table" then
    for _, id in ipairs(orderList) do push(id) end
  end
  if type(fallbackItems) == "table" then
    for _, id in ipairs(fallbackItems) do push(id) end
  end
  return items
end

--- Read enabled set from a MultiSelect control.
--- @param control table  MultiSelect widget
--- @return table enabledSet, table orderedIds
function Umbrella.readMultiSelect(control)
  local enabled = {}
  local order = {}
  if not control or not control.List or not control.Get then return enabled, order end
  local ok, ids = pcall(control.List, control)
  if not ok or type(ids) ~= "table" then return enabled, order end
  for _, id in ipairs(ids) do
    order[#order + 1] = id
    local okGet, isOn = pcall(control.Get, control, id)
    if okGet and isOn then enabled[id] = true end
  end
  return enabled, order
end

--- Set a MultiSelect item value.
function Umbrella.setMultiSelect(control, id, value)
  if not control or not control.Set then return false end
  local ok = pcall(control.Set, control, id, value)
  return ok
end

--- Setup a persistent MultiSelect with Config save/load.
--- @param group table        menu group
--- @param label string       UI label
--- @param configName string  Config section name
--- @param key string         Config key
--- @param defaultOrder table default ordered list
--- @param defaultEnabled table  default enabled list
--- @param allItems table     full items list (for fallback)
--- @param iconFn function    icon path resolver
--- @return table {multiselect, getEnabled, getOrder, save}
function Umbrella.setupPersistentMultiSelect(group, label, configName, key, defaultOrder, defaultEnabled, allItems, iconFn)
  local savedOrder = {}
  local savedEnabled = {}
  if Config and Config.ReadString then
    local rawOrder = Config.ReadString(configName, key .. "_order", "")
    local rawEnabled = Config.ReadString(configName, key .. "_enabled", "")
    savedOrder = Umbrella.splitCSV(rawOrder)
    savedEnabled = Umbrella.splitCSV(rawEnabled)
  end
  if #savedOrder == 0 then savedOrder = defaultOrder end
  if #savedEnabled == 0 then savedEnabled = defaultEnabled end

  local enabledSet = Umbrella.listToSet(savedEnabled)
  local items = Umbrella.buildMultiSelectItems(savedOrder, enabledSet, allItems, iconFn)

  local multiselect = group:MultiSelect(label, items, true)
  if multiselect and multiselect.DragAllowed then
    pcall(multiselect.DragAllowed, multiselect, true)
  end

  local cache = {}

  local function read(saveToConfig)
    if not multiselect or not multiselect.List or not multiselect.Get then return {} end
    local ok, ids = pcall(multiselect.List, multiselect)
    if not ok or type(ids) ~= "table" then return {} end
    local enabled = {}
    for _, id in ipairs(ids) do
      local okGet, isOn = pcall(multiselect.Get, multiselect, id)
      if okGet and isOn then enabled[#enabled + 1] = id end
    end
    cache = enabled
    if saveToConfig and Config and Config.WriteString then
      Config.WriteString(configName, key .. "_order", table.concat(ids, ","))
      Config.WriteString(configName, key .. "_enabled", table.concat(enabled, ","))
    end
    return enabled
  end

  if multiselect and multiselect.SetCallback then
    multiselect:SetCallback(function() read(true) end, true)
  end

  -- Prime cache
  read(false)

  return {
    multiselect = multiselect,
    getEnabled = function() return cache end,
    getOrder = function()
      if not multiselect or not multiselect.List then return {} end
      local ok, ids = pcall(multiselect.List, multiselect)
      if ok and type(ids) == "table" then return ids end
      return {}
    end,
    save = function() read(true) end,
  }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- WIDGET SHORTCUTS
-- ═══════════════════════════════════════════════════════════════════════════

--- Create a menu tab with a standard "Settings" group.
--- @param menuPath string  e.g. "General"
--- @param tabPath string   e.g. "Scripts"
--- @param tabName string   display name
--- @param tabId string     internal id
--- @return table tab, table settingsGroup
function Umbrella.createSettingsTab(menuPath, tabPath, tabName, tabId)
  local tab = Menu.Create(menuPath, tabPath, tabName, tabId)
  local group = tab:Create("Settings")
  return tab, group
end

--- Create a switch with debug logger.
--- @param group table
--- @param label string
--- @param defaultValue boolean
--- @return table switch, function isEnabled
function Umbrella.createSwitch(group, label, defaultValue)
  local sw = group:Switch(label, defaultValue ~= false)
  return sw, function() return sw:Get() == true end
end

--- Create a slider.
function Umbrella.createSlider(group, label, minVal, maxVal, defaultVal)
  return group:Slider(label, minVal or 0, maxVal or 100, defaultVal or 50)
end

--- Create a key bind.
function Umbrella.createBind(group, label, defaultKey)
  return group:Bind(label, defaultKey or Enum.ButtonCode.KEY_NONE)
end

--- Widget visibility helper.
function Umbrella.setVisible(control, visible)
  if not control or not control.Visible then return end
  pcall(control.Visible, control, visible)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CASTING HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Cast a no-target ability/item.
--- @return boolean success, string reason
function Umbrella.castNoTarget(ability)
  if not Ability or not Ability.CastNoTarget then return false, "api_missing" end
  if not Umbrella.isReady(ability) then return false, "not_ready" end
  local ok = pcall(Ability.CastNoTarget, ability, false, false, false)
  if ok then return true, "cast" end
  return false, "cast_failed"
end

--- Cast a target ability/item.
--- @return boolean success, string reason
function Umbrella.castTarget(ability, target)
  if not Ability or not Ability.CastTarget then return false, "api_missing" end
  if not Umbrella.isReady(ability) then return false, "not_ready" end
  local ok = pcall(Ability.CastTarget, ability, target, false, false, false)
  if ok then return true, "cast" end
  return false, "cast_failed"
end

--- Cast a position ability.
function Umbrella.castPosition(ability, pos)
  if not Ability or not Ability.CastPosition then return false, "api_missing" end
  if not Umbrella.isReady(ability) then return false, "not_ready" end
  local ok = pcall(Ability.CastPosition, ability, pos, false, false, false)
  if ok then return true, "cast" end
  return false, "cast_failed"
end

--- Issue an attack order.
--- @return boolean success
function Umbrella.attackTarget(hero, target)
  if not hero or not target then return false end
  if NPC and NPC.AttackTarget then
    local ok = pcall(NPC.AttackTarget, hero, target, false)
    if ok then return true end
  end
  if not Players or not Players.GetLocal then return false end
  local player = Umbrella.safeCall(Players.GetLocal)
  if not player then return false end
  if not Player or not Player.PrepareUnitOrders then return false end
  if not Enum or not Enum.UnitOrder or not Enum.PlayerOrderIssuer then return false end
  local ok = pcall(Player.PrepareUnitOrders,
    player,
    Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET,
    target,
    Vector(0, 0, 0),
    nil,
    Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY,
    hero, false, false, false, true, "umbrella_attack", true)
  return ok == true
end

--- Issue a stop order.
function Umbrella.stopHero(hero)
  if not hero then return false end
  if not Players or not Players.GetLocal then return false end
  local player = Umbrella.safeCall(Players.GetLocal)
  if not player then return false end
  if not Player or not Player.PrepareUnitOrders then return false end
  if not Enum or not Enum.UnitOrder or not Enum.PlayerOrderIssuer then return false end
  local ok = pcall(Player.PrepareUnitOrders,
    player,
    Enum.UnitOrder.DOTA_UNIT_ORDER_STOP,
    nil, Vector(0, 0, 0), nil,
    Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY,
    hero, false, false, false, true, "umbrella_stop", true)
  return ok == true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ENEMY SCANNING
-- ═══════════════════════════════════════════════════════════════════════════

--- Get all enemy heroes within radius.
function Umbrella.getEnemyHeroes(hero, radius)
  if not hero then return {} end
  local pos = Umbrella.getPos(hero)
  if not pos then return {} end
  local team = Umbrella.getTeamNum(hero)
  if not team or not Enum or not Enum.TeamType then return {} end
  if not Heroes or not Heroes.InRadius then return {} end
  return Umbrella.safeCall(Heroes.InRadius, pos, radius or 12000, team, Enum.TeamType.TEAM_ENEMY) or {}
end

--- Scan enemies within range and return sets of detected spell/item ids.
--- @param hero table
--- @param threatAbilities table  list of ability name strings to scan for
--- @param threatItems table|nil  list of item name strings to scan for
--- @return table, table  detectedSpells {[name]=true}, detectedItems {[name]=true}
function Umbrella.scanThreats(hero, threatAbilities, threatItems)
  local detectedSpells = {}
  local detectedItems = {}
  local enemies = Umbrella.getEnemyHeroes(hero, 12000)
  for _, enemy in ipairs(enemies or {}) do
    if not Umbrella.isIllusion(enemy) then
      if threatAbilities then
        for _, abilityName in ipairs(threatAbilities) do
          if Umbrella.getAbility(enemy, abilityName) then
            detectedSpells[abilityName] = true
          end
        end
      end
      if threatItems and NPC and NPC.GetItemByIndex then
        for slot = 0, Umbrella.ITEM_SLOT_MAX do
          local item = Umbrella.getItemByIndex(enemy, slot)
          if item then
            local nm = Umbrella.getAbilityName(item)
            if nm and threatItems[nm] then
              detectedItems[nm] = true
            end
          end
        end
      end
    end
  end
  return detectedSpells, detectedItems
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DRAWING HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Draw a world-space circle.
function Umbrella.drawWorldCircle(pos, radius, color, thickness, steps)
  if not pos or not radius or radius <= 0.0 then return end
  if not Render or not Render.WorldToScreen or not Render.Line then return end
  color = color or Color(255, 50, 50, 200)
  thickness = thickness or 1.0
  steps = steps or 32
  local points = {}
  for i = 1, steps do
    local angle = (i / steps) * 2.0 * math.pi
    local x = pos.x + radius * math.cos(angle)
    local y = pos.y + radius * math.sin(angle)
    local screenPos, onScreen = Render.WorldToScreen(Vector(x, y, (pos.z or 0.0)))
    if onScreen then points[#points + 1] = screenPos end
  end
  for i = 1, #points do
    local a = points[i]
    local b = points[(i % #points) + 1]
    Render.Line(a, b, color, thickness)
  end
end

--- Draw a line between two entities (in world space) on screen.
function Umbrella.drawLockLine(hero, target, color, thickness)
  if not hero or not target then return end
  if not Render or not Render.WorldToScreen or not Render.Line then return end
  local heroPos = Umbrella.getPos(hero)
  local targetPos = Umbrella.getPos(target)
  if not heroPos or not targetPos then return end
  heroPos = Vector(heroPos.x, heroPos.y, (heroPos.z or 0.0) + 80.0)
  targetPos = Vector(targetPos.x, targetPos.y, (targetPos.z or 0.0) + 80.0)
  local a, aVis = Render.WorldToScreen(heroPos)
  local b, bVis = Render.WorldToScreen(targetPos)
  if not aVis or not bVis then return end
  Render.Line(a, b, color or Color(0, 255, 120, 220), thickness or 2.0)
end

--- Draw a minimap circle.
function Umbrella.drawMinimapCircle(pos, color, size)
  if not pos or not MiniMap or not MiniMap.DrawCircle then return end
  color = color or Color(128, 0, 128, 200)
  size = size or 1600
  MiniMap.DrawCircle(pos, color.r or 128, color.g or 0, color.b or 128, color.a or 200, size)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SCRIPT BOILERPLATE
-- ═══════════════════════════════════════════════════════════════════════════

--- Create a script table with automatic callback registration.
--- Usage:
---   local script = U.createScript("MyScript")
---   function script.OnUpdate() ... end
---   return script
---
--- @param name string  optional script name (for debugging)
--- @return table
function Umbrella.createScript(name)
  return {}
end

return Umbrella
