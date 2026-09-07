---@diagnostic disable: undefined-global

local auto_manta_dodge = {}

local SCRIPT_TAG = "[Auto Manta Dodge]"
local SCAN_INTERVAL = 0.40
local ITEM_SLOT_MAX = 20

local THREATS = {
{ id = "abaddon_death_coil", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "alchemist_unstable_concoction_throw", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "ancient_apparition_chilling_touch", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "ancient_apparition_cold_feet", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "antimage_mana_void", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "arc_warden_flux", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "axe_battle_hunger", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "axe_culling_blade", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bane_brain_sap", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bane_enfeeble", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bane_fiends_grip", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bane_nightmare", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "batrider_flaming_lasso", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "beastmaster_primal_roar", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bloodseeker_rupture", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bounty_hunter_jinada", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bounty_hunter_shuriken_toss", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bounty_hunter_track", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "bristleback_viscous_nasal_goo", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "broodmother_spawn_spiderlings", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "centaur_double_edge", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "chaos_knight_chaos_bolt", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "chaos_knight_reality_rift", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "chen_penitence", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "clinkz_searing_arrows", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "crystal_maiden_frostbite", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "dark_seer_ion_shell", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "dark_willow_cursed_crown", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "dazzle_poison_touch", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "death_prophet_carrion_swarm", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "death_prophet_spirit_siphon", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "disruptor_glimpse", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "disruptor_thunder_strike", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "doom_bringer_devour", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "doom_bringer_doom", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "doom_bringer_infernal_blade", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "dragon_knight_breathe_fire", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "dragon_knight_dragon_tail", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "drow_ranger_frost_arrows", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "earth_spirit_boulder_smash", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "earth_spirit_petrify", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "enchantress_enchant", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "enchantress_impetus", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "enchantress_little_friends", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "enigma_malefice", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "furion_sprout", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "furion_wrath_of_nature", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "grimstroke_dark_portrait", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "grimstroke_ink_creature", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "grimstroke_soul_chain", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "gyrocopter_homing_missile", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "hoodwink_acorn_shot", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "hoodwink_hunters_boomerang", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "huskar_burning_spear", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "huskar_life_break", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "invoker_cold_snap", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "item_abyssal_blade", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_bfury", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_bloodthorn", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_book_of_shadows", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_bullwhip", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_clumsy_net", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_crippling_crossbow", kind = "item", order_fallback = false, allow_no_target = false },
    { id = "item_cyclone", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_dagon", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_dagon_2", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_dagon_3", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_dagon_4", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_dagon_5", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_diffusal_blade", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_disperser", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_ethereal_blade", kind = "item", order_fallback = false, allow_no_target = false },
    { id = "item_force_boots", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_force_staff", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_hand_of_midas", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_harpoon", kind = "item", order_fallback = false, allow_no_target = false },
    { id = "item_heavens_halberd", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_heavy_blade", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_helm_of_the_dominator", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_helm_of_the_overlord", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_horizon", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_hurricane_pike", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_iron_talon", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_lunar_crest", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_manacles_of_power", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_medallion_of_courage", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_muertas_gun", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_nullifier", kind = "item", order_fallback = false, allow_no_target = false },
    { id = "item_orchid", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_paintball", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_psychic_headband", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_pyrrhic_cloak", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_quelling_blade", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_rod_of_atos", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_sheepstick", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_spirit_vessel", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_tango", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_tango_single", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_urn_of_shadows", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_warhammer", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "item_wind_waker", kind = "item", order_fallback = true, allow_no_target = false },
    { id = "jakiro_dual_breath", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "jakiro_liquid_fire", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "jakiro_liquid_ice", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "juggernaut_omni_slash", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "juggernaut_swift_slash", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "kez_grappling_claw", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "kez_kazurai_katana", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "kez_talon_toss", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "kunkka_tidebringer", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "kunkka_x_marks_the_spot", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "largo_catchy_lick", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "legion_commander_duel", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "leshrac_lightning_storm", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "lich_chain_frost", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "lich_frost_nova", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "lich_sinister_gaze", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "life_stealer_infest", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "life_stealer_open_wounds", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "lina_dragon_slave", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "lina_laguna_blade", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "lion_finger_of_death", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "lion_impale", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "lion_mana_drain", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "lion_voodoo", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "luna_lucent_beam", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "magnataur_reverse_polarity", kind = "ability", order_fallback = true, allow_no_target = true },
    { id = "magnataur_shockwave", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "marci_grapple", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "medusa_mystic_snake", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "meepo_megameepo_fling", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "monkey_king_tree_dance", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "morphling_adaptive_strike_agi", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "morphling_replicate", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "muerta_dead_shot", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "naga_siren_ensnare", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "necrolyte_death_seeker", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "necrolyte_reapers_scythe", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "night_stalker_void", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "nyx_assassin_jolt", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "obsidian_destroyer_arcane_orb", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "obsidian_destroyer_astral_imprisonment", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "ogre_magi_fireblast", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "ogre_magi_ignite", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "ogre_magi_unrefined_fireblast", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "omniknight_hammer_of_purity", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "oracle_fates_edict", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "oracle_fortunes_end", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "oracle_purifying_flames", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "phantom_assassin_phantom_strike", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "phantom_assassin_stifling_dagger", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "phantom_lancer_spirit_lance", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "primal_beast_pulverize", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "pudge_dismember", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "pugna_decrepify", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "pugna_life_drain", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "queenofpain_shadow_strike", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "razor_static_link", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "riki_blink_strike", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "rubick_fade_bolt", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "rubick_spell_steal", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "rubick_telekinesis", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "shadow_demon_demonic_purge", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "shadow_demon_disruption", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "shadow_demon_disseminate", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "shadow_shaman_ether_shock", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "shadow_shaman_shackles", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "shadow_shaman_voodoo", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "silencer_glaives_of_wisdom", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "silencer_last_word", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "skeleton_king_hellfire_blast", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "skywrath_mage_ancient_seal", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "skywrath_mage_arcane_bolt", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "slardar_amplify_damage", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "slark_saltwater_shiv", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "snapfire_gobble_up", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "sniper_assassinate", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "spectre_shadow_step", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "spectre_spectral_dagger", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "spirit_breaker_charge_of_darkness", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "spirit_breaker_nether_strike", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "spirit_breaker_planar_pocket", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "storm_spirit_electric_vortex", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "sven_storm_bolt", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "terrorblade_sunder", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "tidehunter_dead_in_the_water", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "tidehunter_gush", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "tinker_laser", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "tinker_warp_grenade", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "tiny_toss", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "tiny_toss_tree", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "tiny_tree_grab", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "treant_leech_seed", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "troll_warlord_whirling_axes_ranged", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "tusk_snowball", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "tusk_walrus_kick", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "tusk_walrus_punch", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "undying_soul_rip", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "vengefulspirit_magic_missile", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "vengefulspirit_nether_swap", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "venomancer_noxious_plague", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "viper_poison_attack", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "viper_viper_strike", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "visage_grave_chill", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "visage_soul_assumption", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "warlock_fatal_bonds", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "warlock_shadow_word", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "weaver_geminate_attack", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "windrunner_focusfire", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "windrunner_shackleshot", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "winter_wyvern_splinter_blast", kind = "ability", order_fallback = false, allow_no_target = false },
    { id = "winter_wyvern_winters_curse", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "witch_doctor_paralyzing_cask", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "zuus_arc_lightning", kind = "ability", order_fallback = true, allow_no_target = false },
    { id = "zuus_lightning_bolt", kind = "ability", order_fallback = true, allow_no_target = false },
}

local THREAT_BY_ID = {}
local ALL_THREAT_IDS = {}
local ALL_SPELL_IDS = {}
local ALL_ITEM_IDS = {}
local NO_TARGET_EXTRA_IDS = {}

for _, meta in ipairs(THREATS) do
    THREAT_BY_ID[meta.id] = meta
    ALL_THREAT_IDS[#ALL_THREAT_IDS + 1] = meta.id
    if meta.kind == "item" then
        ALL_ITEM_IDS[#ALL_ITEM_IDS + 1] = meta.id
    else
        ALL_SPELL_IDS[#ALL_SPELL_IDS + 1] = meta.id
        if meta.allow_no_target then
            NO_TARGET_EXTRA_IDS[#NO_TARGET_EXTRA_IDS + 1] = meta.id
        end
    end
end

table.sort(ALL_THREAT_IDS)
table.sort(ALL_SPELL_IDS)
table.sort(ALL_ITEM_IDS)

local menu_tab = Menu.Create("General", "Scripts", "Auto Manta Dodge", "AutoMantaDodge")
local settings_group = menu_tab:Create("Settings")
local current_group = menu_tab:Create("Current Game")
local all_group = menu_tab:Create("Show All")

local ui = {}
ui.enabled = settings_group:Switch("Enabled", true)
ui.debug_logs = settings_group:Switch("Debug Logs", false)
ui.use_projectiles = settings_group:Switch("Projectile Timing", true)
ui.use_order_fallback = settings_group:Switch("Order Precast Timing", true)
ui.use_no_target_extras = settings_group:Switch("No-Target Extras (RP)", true)
ui.projectile_prehit_ms = settings_group:Slider("Projectile Pre-Hit (ms)", 0, 120, 12)
ui.activation_offset_ms = settings_group:Slider("Activation Offset (ms)", 0, 120, 0)
ui.no_target_buffer = settings_group:Slider("No-Target Range Buffer", 0, 250, 80)
ui.max_queue_age_ms = settings_group:Slider("Queue Max Age (ms)", 100, 3000, 900)

current_group:Label("Enemy spells/items are auto-detected. Enabled entries are used in Current Game mode.")
all_group:Label("Show all hero spell + item icons, including inactive entries from this match.")
ui.show_all_mode = all_group:Switch("Show All Mode", false)

local current_spell_enabled_set = {}
local current_item_enabled_set = {}
local show_all_enabled_set = {}

local current_detected_spell_set = {}
local current_detected_item_set = {}

local ui_current_spells = nil
local ui_current_items = nil
local ui_show_all = nil

local pending_dodges = {}
local seen_projectiles = {}
local pending_order_dodges = {}
local enemy_no_target_ready = {}
local last_manta_cast_t = -1000.0
local last_scan_t = -1000.0

local function log_debug(msg)
    if not ui.debug_logs:Get() then return end
    if Log and Log.Write then
        Log.Write(SCRIPT_TAG .. " " .. tostring(msg))
    else
        print(SCRIPT_TAG .. " " .. tostring(msg))
    end
end

local function now_time()
    if GameRules and GameRules.GetGameTime then
        return GameRules.GetGameTime()
    end
    return os.clock()
end

local function distance2d(a, b)
    if not a or not b then return 0.0 end
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    return math.sqrt(dx * dx + dy * dy)
end

local function get_entity_index(ent)
    if not ent or not Entity or not Entity.GetIndex then return -1 end
    return Entity.GetIndex(ent)
end

local function is_same_entity(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local ai = get_entity_index(a)
    local bi = get_entity_index(b)
    if ai ~= -1 and bi ~= -1 then
        return ai == bi
    end
    return false
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
    for _, v in ipairs(list) do
        if v ~= nil then set[v] = true end
    end
    return set
end

local function set_to_list(set, fallback_order)
    local out = {}
    if type(fallback_order) == "table" then
        for _, id in ipairs(fallback_order) do
            if set[id] then
                out[#out + 1] = id
            end
        end
        return out
    end
    for id, on in pairs(set or {}) do
        if on then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

local function build_detected_first_order(all_ids, detected_set)
    local out = {}
    local seen = {}
    for _, id in ipairs(all_ids or {}) do
        if detected_set and detected_set[id] then
            out[#out + 1] = id
            seen[id] = true
        end
    end
    for _, id in ipairs(all_ids or {}) do
        if not seen[id] then
            out[#out + 1] = id
        end
    end
    return out
end

local function resolve_multiselect_image_path(id)
    local meta = THREAT_BY_ID[id]
    if not meta then return "" end
    if meta.kind == "item" then
        local short = tostring(id):gsub("^item_", "")
        return "panorama/images/items/" .. short .. "_png.vtex_c"
    end
    return "panorama/images/spellicons/" .. tostring(id) .. "_png.vtex_c"
end

local function build_multiselect_items(id_order, enabled_set)
    local items = {}
    local seen = {}
    for _, id in ipairs(id_order or {}) do
        if THREAT_BY_ID[id] and not seen[id] then
            seen[id] = true
            items[#items + 1] = { id, resolve_multiselect_image_path(id), enabled_set[id] == true }
        end
    end
    return items
end

local function read_multiselect_enabled(control)
    local enabled = {}
    local order = {}
    if not control or not control.List or not control.Get then
        return enabled, order
    end
    local ok_list, ids = pcall(control.List, control)
    if not ok_list or type(ids) ~= "table" then
        return enabled, order
    end
    for _, id in ipairs(ids) do
        order[#order + 1] = id
        local ok_get, is_on = pcall(control.Get, control, id)
        if ok_get and is_on then
            enabled[id] = true
        end
    end
    return enabled, order
end

local function try_set_multiselect_value(control, id, value)
    if not control or not control.Set then return false end
    local ok = pcall(control.Set, control, id, value)
    return ok
end

local function set_visible(control, value)
    if not control or not control.Visible then return end
    pcall(control.Visible, control, value)
end

local function refresh_section_visibility()
    local show_all = ui.show_all_mode and ui.show_all_mode.Get and ui.show_all_mode:Get() or false
    set_visible(ui_current_spells, not show_all)
    set_visible(ui_current_items, not show_all)
    set_visible(ui_show_all, show_all)
end

local function get_threat_set_for_mode()
    if ui.show_all_mode and ui.show_all_mode.Get and ui.show_all_mode:Get() then
        return show_all_enabled_set
    end
    local combined = {}
    for id, on in pairs(current_spell_enabled_set) do
        if on and current_detected_spell_set[id] then
            combined[id] = true
        end
    end
    for id, on in pairs(current_item_enabled_set) do
        if on and current_detected_item_set[id] then
            combined[id] = true
        end
    end
    return combined
end

local function is_threat_enabled(id)
    local set = get_threat_set_for_mode()
    return set[id] == true
end

local function get_cast_point_seconds(ability)
    if not ability or not Ability or not Ability.GetCastPoint then return 0.10 end
    local ok, cp = pcall(Ability.GetCastPoint, ability)
    if ok and type(cp) == "number" then
        if cp < 0.0 then cp = 0.0 end
        if cp > 1.2 then cp = 1.2 end
        return cp
    end
    return 0.10
end

local function read_special_number(ability, key)
    if not ability or not key or not Ability then return nil end
    if Ability.GetSpecialValueFor then
        local ok, val = pcall(Ability.GetSpecialValueFor, ability, key, -1)
        if ok and type(val) == "number" then return val end
        ok, val = pcall(Ability.GetSpecialValueFor, ability, key)
        if ok and type(val) == "number" then return val end
    end
    if Ability.GetLevelSpecialValueFor then
        local ok, val = pcall(Ability.GetLevelSpecialValueFor, ability, key, -1)
        if ok and type(val) == "number" then return val end
        ok, val = pcall(Ability.GetLevelSpecialValueFor, ability, key)
        if ok and type(val) == "number" then return val end
    end
    return nil
end

local function get_no_target_radius(ability_name, ability)
    if ability_name == "magnataur_reverse_polarity" then
        local r = read_special_number(ability, "pull_radius") or read_special_number(ability, "radius")
        if type(r) == "number" and r > 0 then return r end
        return 410.0
    end
    return nil
end

local function ability_has_projectile_speed(ability)
    if not ability then return false end
    local v1 = read_special_number(ability, "projectile_speed")
    if type(v1) == "number" and v1 > 0 then return true end
    local v2 = read_special_number(ability, "projectile_speed_tooltip")
    if type(v2) == "number" and v2 > 0 then return true end
    local v3 = read_special_number(ability, "arrow_speed")
    if type(v3) == "number" and v3 > 0 then return true end
    return false
end

local function no_target_can_hit_hero(caster, hero, ability_name, ability)
    local r = get_no_target_radius(ability_name, ability)
    if not r then return false end
    local caster_pos = Entity.GetAbsOrigin(caster)
    local hero_pos = Entity.GetAbsOrigin(hero)
    if not caster_pos or not hero_pos then return false end
    local buffer = ui.no_target_buffer and ui.no_target_buffer.Get and ui.no_target_buffer:Get() or 80
    return distance2d(caster_pos, hero_pos) <= (r + buffer)
end

local function find_manta(hero)
    if not hero or not NPC or not NPC.GetItemByIndex or not Ability or not Ability.GetName then return nil end
    for i = 0, ITEM_SLOT_MAX do
        local item = NPC.GetItemByIndex(hero, i)
        if item then
            local ok_name, name = pcall(Ability.GetName, item)
            if ok_name and name == "item_manta" then
                return item
            end
        end
    end
    return nil
end

local function normalize_impact_time(value, t_now)
    if type(value) ~= "number" or value <= 0.0 then return nil end
    -- Some builds provide absolute game-time, others may provide remaining time.
    if value < 15.0 and t_now > 15.0 then
        return t_now + value
    end
    if value < (t_now - 0.5) then
        return t_now + value
    end
    return value
end

local function try_cast_manta(hero)
    local t = now_time()
    if (t - last_manta_cast_t) < 0.08 then
        return false, "throttled"
    end

    local manta = find_manta(hero)
    if not manta then
        return false, "no_manta"
    end

    if not Ability or not Ability.IsReady or not Ability.IsCastable or not Ability.CastNoTarget then
        return false, "api_unavailable"
    end

    local mana = (NPC and NPC.GetMana and NPC.GetMana(hero)) or 0.0
    if not Ability.IsReady(manta) then
        return false, "not_ready"
    end
    if not Ability.IsCastable(manta, mana) then
        return false, "not_castable"
    end

    Ability.CastNoTarget(manta, false, false, false)
    last_manta_cast_t = t
    return true, "cast"
end

local function push_pending_dodge(exec_t, expire_t, ability_name, source, reason)
    local t = now_time()
    if type(exec_t) ~= "number" then return end
    if exec_t < t then exec_t = t end

    local max_age = (ui.max_queue_age_ms and ui.max_queue_age_ms.Get and ui.max_queue_age_ms:Get() or 900) / 1000.0
    if type(expire_t) ~= "number" then
        expire_t = exec_t + max_age
    end

    local source_idx = get_entity_index(source)
    for _, p in ipairs(pending_dodges) do
        if p.ability_name == ability_name and p.source_idx == source_idx and math.abs((p.exec_t or 0) - exec_t) <= 0.07 then
            if exec_t < p.exec_t then p.exec_t = exec_t end
            if expire_t > p.expire_t then p.expire_t = expire_t end
            return
        end
    end

    pending_dodges[#pending_dodges + 1] = {
        exec_t = exec_t,
        expire_t = expire_t,
        ability_name = ability_name,
        source_idx = source_idx,
        reason = reason,
    }

    log_debug(string.format("queue %s (%s) in %.3fs", tostring(ability_name), tostring(reason), math.max(0.0, exec_t - t)))
end

local function push_pending_order_dodge(caster, hero, ability, ability_name, mode)
    local t = now_time()
    local source_idx = get_entity_index(caster)
    if source_idx == -1 then return end

    for _, c in ipairs(pending_order_dodges) do
        if c.source_idx == source_idx and c.ability_name == ability_name and (t - c.created_t) <= 0.12 then
            return
        end
    end

    local cast_point = get_cast_point_seconds(ability)
    local offset = (ui.activation_offset_ms and ui.activation_offset_ms.Get and ui.activation_offset_ms:Get() or 0) / 1000.0
    if offset < 0.0 then offset = 0.0 end
    if offset > cast_point then offset = cast_point end
    local exec_t = t + cast_point - offset
    if exec_t < t then exec_t = t end
    local expire_t = t + cast_point + 0.25

    pending_order_dodges[#pending_order_dodges + 1] = {
        created_t = t,
        exec_t = exec_t,
        expire_t = expire_t,
        ability_name = ability_name,
        expected_target_idx = (mode == "order_target") and get_entity_index(hero) or -1,
        source = caster,
        source_idx = source_idx,
        mode = mode,
    }

    log_debug(string.format("queue %s (precast_%s) in %.3fs", tostring(ability_name), tostring(mode), math.max(0.0, exec_t - t)))
end

local function cancel_pending_order_dodges_for_caster(caster, incoming_ability_name, incoming_target)
    local source_idx = get_entity_index(caster)
    if source_idx == -1 then return end
    local incoming_target_idx = get_entity_index(incoming_target)

    local i = 1
    while i <= #pending_order_dodges do
        local p = pending_order_dodges[i]
        if p.source_idx == source_idx then
            local keep = false
            if incoming_ability_name ~= nil and incoming_ability_name == p.ability_name then
                if p.expected_target_idx == -1 or p.expected_target_idx == incoming_target_idx then
                    keep = true
                end
            end
            if not keep then
                log_debug(string.format("cancel precast %s (incoming=%s)", tostring(p.ability_name), tostring(incoming_ability_name)))
                table.remove(pending_order_dodges, i)
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

local function process_pending_order_dodges()
    local t = now_time()
    local i = 1
    while i <= #pending_order_dodges do
        local p = pending_order_dodges[i]
        if t > (p.expire_t or t) then
            table.remove(pending_order_dodges, i)
        else
            if t >= (p.exec_t or t) then
                push_pending_dodge(t, t + 0.35, p.ability_name, p.source, "precast_" .. tostring(p.mode))
                table.remove(pending_order_dodges, i)
            else
                i = i + 1
            end
        end
    end
end

local function reset_runtime_state()
    pending_dodges = {}
    seen_projectiles = {}
    pending_order_dodges = {}
    enemy_no_target_ready = {}
    current_detected_spell_set = {}
    current_detected_item_set = {}
    last_scan_t = -1000.0
end

local function scan_enemy_threats(hero)
    local t = now_time()
    if (t - last_scan_t) < SCAN_INTERVAL then
        return
    end
    last_scan_t = t

    local my_pos = Entity.GetAbsOrigin(hero)
    local my_team = Entity.GetTeamNum(hero)
    local enemies = Heroes.InRadius(my_pos, 12000, my_team, Enum.TeamType.TEAM_ENEMY)

    local detected_spells = {}
    local detected_items = {}

    for _, enemy in ipairs(enemies) do
        if not NPC.IsIllusion(enemy) then
            for _, ability_name in ipairs(ALL_SPELL_IDS) do
                if NPC.GetAbility(enemy, ability_name) ~= nil then
                    detected_spells[ability_name] = true
                end
            end

            for slot = 0, ITEM_SLOT_MAX do
                local item = NPC.GetItemByIndex(enemy, slot)
                if item and Ability and Ability.GetName then
                    local ok_name, item_name = pcall(Ability.GetName, item)
                    if ok_name then
                        local meta = THREAT_BY_ID[item_name]
                        if meta and meta.kind == "item" then
                            detected_items[item_name] = true
                            try_set_multiselect_value(ui_current_items, item_name, true)
                        end
                    end
                end
            end
        end
    end

    current_detected_spell_set = detected_spells
    current_detected_item_set = detected_items

    if ui_current_spells then
        for _, id in ipairs(ALL_SPELL_IDS) do
            if detected_spells[id] then
                try_set_multiselect_value(ui_current_spells, id, true)
            end
        end
    end
end

local function create_ui_controls()
    local hero = Heroes.GetLocal()
    if hero and Entity.IsAlive(hero) then
        scan_enemy_threats(hero)
    end

    local spell_order = nil
    if next(current_detected_spell_set) ~= nil then
        spell_order = set_to_list(current_detected_spell_set, ALL_SPELL_IDS)
    else
        spell_order = ALL_SPELL_IDS
    end

    local item_order = build_detected_first_order(ALL_ITEM_IDS, current_detected_item_set)
    local item_enabled = nil
    if next(current_detected_item_set) ~= nil then
        item_enabled = current_detected_item_set
    else
        item_enabled = list_to_set(item_order)
    end

    local spell_items = build_multiselect_items(spell_order, list_to_set(spell_order))
    local item_items = build_multiselect_items(item_order, item_enabled)
    local all_items = build_multiselect_items(ALL_THREAT_IDS, list_to_set(ALL_THREAT_IDS))

    ui_current_spells = current_group:MultiSelect("Enemy Spells", spell_items, true)
    if ui_current_spells and ui_current_spells.DragAllowed then
        pcall(ui_current_spells.DragAllowed, ui_current_spells, true)
    end

    ui_current_items = current_group:MultiSelect("Enemy Items", item_items, true)
    if ui_current_items and ui_current_items.DragAllowed then
        pcall(ui_current_items.DragAllowed, ui_current_items, true)
    end

    ui_show_all = all_group:MultiSelect("All Threat Icons", all_items, true)
    if ui_show_all and ui_show_all.DragAllowed then
        pcall(ui_show_all.DragAllowed, ui_show_all, true)
    end

    local function read_current_spells()
        current_spell_enabled_set = read_multiselect_enabled(ui_current_spells)
    end
    local function read_current_items()
        current_item_enabled_set = read_multiselect_enabled(ui_current_items)
    end
    local function read_show_all()
        show_all_enabled_set = read_multiselect_enabled(ui_show_all)
    end

    read_current_spells()
    read_current_items()
    read_show_all()

    if ui_current_spells and ui_current_spells.SetCallback then
        ui_current_spells:SetCallback(function()
            read_current_spells()
        end, true)
    end
    if ui_current_items and ui_current_items.SetCallback then
        ui_current_items:SetCallback(function()
            read_current_items()
        end, true)
    end
    if ui_show_all and ui_show_all.SetCallback then
        ui_show_all:SetCallback(function()
            read_show_all()
        end, true)
    end

    if ui.show_all_mode and ui.show_all_mode.SetCallback then
        ui.show_all_mode:SetCallback(function()
            refresh_section_visibility()
        end, true)
    end

    refresh_section_visibility()
end

create_ui_controls()

function auto_manta_dodge.OnGameStart()
    reset_runtime_state()
end

function auto_manta_dodge.OnGameEnd()
    reset_runtime_state()
end

function auto_manta_dodge.OnProjectile(data)
    if not ui.enabled:Get() or not ui.use_projectiles:Get() then return end
    if not data or data.isAttack then return end

    local hero = Heroes.GetLocal()
    if not hero or not Entity.IsAlive(hero) then return end
    if not is_same_entity(data.target, hero) then return end
    if not data.ability or not Ability or not Ability.GetName then return end

    local ok_name, ability_name = pcall(Ability.GetName, data.ability)
    if not ok_name or type(ability_name) ~= "string" then return end

    local meta = THREAT_BY_ID[ability_name]
    if not meta then return end

    if meta.kind == "ability" then current_detected_spell_set[ability_name] = true end
    if meta.kind == "item" then current_detected_item_set[ability_name] = true end

    if not is_threat_enabled(ability_name) then return end

    if data.handle and seen_projectiles[data.handle] then
        return
    end
    if data.handle then
        seen_projectiles[data.handle] = now_time()
    end

    local t = now_time()
    local hit_t_api = normalize_impact_time(data.maxImpactTime, t)
    local hit_t_calc = nil
    local speed = (type(data.moveSpeed) == "number") and data.moveSpeed or 0.0
    local src = data.source and Entity.GetAbsOrigin(data.source) or nil
    local dst = Entity.GetAbsOrigin(hero)
    if src and dst and speed > 0.0 then
        hit_t_calc = t + (distance2d(src, dst) / speed)
    end

    local hit_t = nil
    if hit_t_api and hit_t_calc then
        -- Prefer the later estimate so we don't fire early.
        hit_t = math.max(hit_t_api, hit_t_calc)
    elseif hit_t_api then
        hit_t = hit_t_api
    elseif hit_t_calc then
        hit_t = hit_t_calc
    else
        hit_t = t + 0.10
    end

    local pre_hit = (ui.projectile_prehit_ms and ui.projectile_prehit_ms.Get and ui.projectile_prehit_ms:Get() or 12) / 1000.0
    if pre_hit < 0.0 then pre_hit = 0.0 end
    local exec_t = hit_t - pre_hit
    if exec_t < t then exec_t = t end

    push_pending_dodge(exec_t, hit_t + 0.35, ability_name, data.source, "projectile")
end

function auto_manta_dodge.OnPrepareUnitOrders(data)
    if not ui.enabled:Get() then return end
    if not data or not data.npc then return end

    local hero = Heroes.GetLocal()
    if not hero or not Entity.IsAlive(hero) then return end

    local caster = data.npc
    if not Entity.IsAlive(caster) then return end
    if Entity.IsSameTeam and Entity.IsSameTeam(caster, hero) then return end

    local ability_name = nil
    if data.ability and Ability and Ability.GetName then
        local ok_name, n = pcall(Ability.GetName, data.ability)
        if ok_name and type(n) == "string" then
            ability_name = n
        end
    end

    cancel_pending_order_dodges_for_caster(caster, ability_name, data.target)
    if not ability_name then return end

    local meta = THREAT_BY_ID[ability_name]
    if not meta then return end

    if meta.kind == "ability" then current_detected_spell_set[ability_name] = true end
    if meta.kind == "item" then current_detected_item_set[ability_name] = true end

    local has_projectile_speed = ability_has_projectile_speed(data.ability)
    if has_projectile_speed then
        -- Projectile-speed spells/items must use OnProjectile completion timing only.
        return
    end

    local targeted_hero = is_same_entity(data.target, hero)

    if targeted_hero and ui.use_order_fallback:Get() and meta.order_fallback and is_threat_enabled(ability_name) then
        push_pending_order_dodge(caster, hero, data.ability, ability_name, "order_target")
        return
    end

    if ui.use_no_target_extras:Get() and meta.allow_no_target and is_threat_enabled(ability_name) then
        if no_target_can_hit_hero(caster, hero, ability_name, data.ability) then
            push_pending_order_dodge(caster, hero, data.ability, ability_name, "order_no_target")
        end
    end
end

local function poll_no_target_extras(hero)
    if not ui.use_no_target_extras:Get() then return end
    if #NO_TARGET_EXTRA_IDS == 0 then return end

    local my_pos = Entity.GetAbsOrigin(hero)
    local my_team = Entity.GetTeamNum(hero)
    local enemies = Heroes.InRadius(my_pos, 12000, my_team, Enum.TeamType.TEAM_ENEMY)

    for _, enemy in ipairs(enemies) do
        if not NPC.IsIllusion(enemy) then
            local enemy_idx = get_entity_index(enemy)
            if enemy_idx ~= -1 then
                local st = enemy_no_target_ready[enemy_idx]
                if not st then
                    st = {}
                    enemy_no_target_ready[enemy_idx] = st
                end

                for _, ability_name in ipairs(NO_TARGET_EXTRA_IDS) do
                    local meta = THREAT_BY_ID[ability_name]
                    if meta then
                        local ability = NPC.GetAbility(enemy, ability_name)
                        local ready = false
                        if ability and Ability and Ability.IsReady then
                            ready = Ability.IsReady(ability) == true
                            current_detected_spell_set[ability_name] = true
                        end

                        local was_ready = st[ability_name]
                        if was_ready == true and ready == false and is_threat_enabled(ability_name) then
                            if no_target_can_hit_hero(enemy, hero, ability_name, ability) then
                                local t = now_time()
                                push_pending_dodge(t, t + 0.35, ability_name, enemy, "cooldown_no_target")
                            end
                        end

                        st[ability_name] = ready
                    end
                end
            end
        end
    end
end

local function cleanup_projectile_cache(t)
    for handle, seen_t in pairs(seen_projectiles) do
        if (t - seen_t) > 8.0 then
            seen_projectiles[handle] = nil
        end
    end
end

local function cleanup_pending_dodges(t)
    local i = 1
    while i <= #pending_dodges do
        local p = pending_dodges[i]
        if t > (p.expire_t or t) then
            table.remove(pending_dodges, i)
        else
            i = i + 1
        end
    end
end

function auto_manta_dodge.OnUpdate()
    if not ui.enabled:Get() then return end

    local hero = Heroes.GetLocal()
    if not hero or not Entity.IsAlive(hero) then return end

    local t = now_time()

    scan_enemy_threats(hero)
    process_pending_order_dodges()
    poll_no_target_extras(hero)
    cleanup_projectile_cache(t)
    cleanup_pending_dodges(t)

    local due_idx = nil
    local due_t = 1e9
    for idx, p in ipairs(pending_dodges) do
        if p.exec_t and p.exec_t <= t and p.exec_t < due_t then
            due_idx = idx
            due_t = p.exec_t
        end
    end

    if not due_idx then return end

    local due = pending_dodges[due_idx]
    local ok_cast, reason = try_cast_manta(hero)
    if ok_cast then
        log_debug(string.format("cast manta vs %s (%s)", tostring(due.ability_name), tostring(due.reason)))
        pending_dodges = {}
        pending_order_dodges = {}
    else
        if reason == "no_manta" then
            pending_dodges = {}
            pending_order_dodges = {}
        end
    end
end

return auto_manta_dodge
