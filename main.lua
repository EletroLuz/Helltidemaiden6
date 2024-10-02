-- Import modules
local menu = require("menu")
menu.plugin_enabled:set(false)
local menu_renderer = require("graphics.menu_renderer")
local revive = require("data.revive")
local explorer = require("data.explorer")
local automindcage = require("data.automindcage")
local actors = require("data.actors")
local waypoint_loader = require("functions.waypoint_loader")
local interactive_patterns = require("enums.interactive_patterns")
local Movement = require("functions.movement")
local ChestsInteractor = require("functions.chests_interactor")
local teleport = require("data.teleport")
local GameStateChecker = require("functions.game_state_checker")
local maidenmain = require("data.maidenmain")
maidenmain.init()

-- Initialize variables
local plugin_enabled = false
local doorsEnabled = false
local loopEnabled = false
local revive_enabled = false
local profane_mindcage_enabled = false
local profane_mindcage_count = 0
local graphics_enabled = false
local was_in_helltide = false
local last_cleanup_time = get_time_since_inject()
local cleanup_interval = 300 -- 5 minutos
local maidenmain_enabled = false

local function periodic_cleanup()
    local current_time = get_time_since_inject()
    if current_time - last_cleanup_time > cleanup_interval then
        collectgarbage("collect")
        ChestsInteractor.clearInteractedObjects()
        waypoint_loader.clear_cached_waypoints()
        last_cleanup_time = current_time
        console.print("Periodic cleanup performed")
    end
end

-- Function to update menu states
local function update_menu_states()
    local new_plugin_enabled = menu.plugin_enabled:get()
    local new_maidenmain_enabled = maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:get()

    -- Garantir que apenas um plugin esteja ativo
    if new_plugin_enabled and new_maidenmain_enabled then
        if plugin_enabled then
            new_maidenmain_enabled = false
            maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:set(false)
            console.print("Maidenmain plugin disabled due to conflict with main plugin")
        else
            new_plugin_enabled = false
            menu.plugin_enabled:set(false)
            console.print("Main plugin disabled due to conflict with Maidenmain plugin")
        end
    end

    -- Atualizar plugin principal
    if new_plugin_enabled ~= plugin_enabled then
        plugin_enabled = new_plugin_enabled
        console.print("Movement Plugin " .. (plugin_enabled and "enabled" or "disabled"))
        if plugin_enabled then
            local waypoints, _ = waypoint_loader.load_route(nil, false)
            if waypoints then
                local randomized_waypoints = {}
                for _, wp in ipairs(waypoints) do
                    table.insert(randomized_waypoints, waypoint_loader.randomize_waypoint(wp))
                end
                Movement.set_waypoints(randomized_waypoints)
                Movement.set_moving(true)
            end
        else
            Movement.save_last_index()
            Movement.set_moving(false)
        end
    end

    -- Atualizar Maidenmain
    if new_maidenmain_enabled ~= maidenmain_enabled then
        maidenmain_enabled = new_maidenmain_enabled
        console.print("Maidenmain Plugin " .. (maidenmain_enabled and "enabled" or "disabled"))
        if maidenmain_enabled then
            local waypoints, _ = waypoint_loader.load_route(nil, true)
            if waypoints then
                local randomized_waypoints = {}
                for _, wp in ipairs(waypoints) do
                    table.insert(randomized_waypoints, waypoint_loader.randomize_waypoint(wp))
                end
                Movement.set_waypoints(randomized_waypoints)
                Movement.set_moving(true)
            end
            -- Desabilitar o loop quando Maidenmain está ativo
            loopEnabled = false
            menu.loop_enabled:set(false)
        else
            Movement.save_last_index()
            Movement.set_moving(false)
        end
    end

    -- Atualizar outras configurações apenas se o plugin principal estiver ativo e Maidenmain não estiver
    if plugin_enabled and not maidenmain_enabled then
        doorsEnabled = menu.main_openDoors_enabled:get()
        loopEnabled = menu.loop_enabled:get()
    else
        doorsEnabled = false
        loopEnabled = false
    end

    revive_enabled = menu.revive_enabled:get()
    profane_mindcage_enabled = menu.profane_mindcage_toggle:get()
    profane_mindcage_count = menu.profane_mindcage_slider:get()

    -- Update maidenmain menu states
    maidenmain.update_menu_states()
end

-- Main update function
on_update(function()
    update_menu_states()

    local teleport_info = teleport.get_teleport_info()
    if teleport_info.cooldown > 0 then
        console.print("Teleport on cooldown. " .. teleport_info.cooldown .. " seconds remaining.")
        return
    end

    if plugin_enabled or maidenmain_enabled then
        periodic_cleanup()
        
        local game_state = GameStateChecker.check_game_state()

        if game_state == "loading_or_limbo" then
            console.print("Loading or in Limbo. Pausing operations.")
            return
        end

        if game_state == "no_player" then
            console.print("No player detected. Waiting for player.")
            return
        end

        local local_player = get_local_player()
        local world_instance = world.get_current_world()
        
        if game_state == "helltide" then
            if not was_in_helltide then
                console.print("Entered Helltide. Initializing Helltide operations.")
                was_in_helltide = true
                Movement.reset(maidenmain_enabled)
                local waypoints, _ = waypoint_loader.load_route(nil, maidenmain_enabled)
                if waypoints then
                    local randomized_waypoints = {}
                    for _, wp in ipairs(waypoints) do
                        table.insert(randomized_waypoints, waypoint_loader.randomize_waypoint(wp))
                    end
                    Movement.set_waypoints(randomized_waypoints)
                    Movement.set_moving(true)
                end
                ChestsInteractor.clearInteractedObjects()
                ChestsInteractor.clearBlacklist()
            end
            
            if profane_mindcage_enabled then
                automindcage.update()
            end

            -- Só interage com baús se o plugin Maiden não estiver ativo
            if not maidenmain_enabled then
                ChestsInteractor.interactWithObjects(doorsEnabled, interactive_patterns)
            end

            Movement.pulse(plugin_enabled or maidenmain_enabled, loopEnabled, teleport, maidenmain_enabled)
            if revive_enabled then
                revive.check_and_revive()
            end
            actors.update()

            -- Update maidenmain apenas se estiver ativo
            if maidenmain_enabled then
                local current_position = local_player:get_position()
                maidenmain.update(menu, current_position, ChestsInteractor, Movement, maidenmain.menu_elements.main_helltide_maiden_auto_plugin_explorer_circle_radius:get())
            end

            -- Verificar se a rota da Maiden foi concluída
            if maidenmain_enabled and Movement.is_idle() then
                explorer.disable()
            end
        else
            if was_in_helltide then
                console.print("Helltide ended. Performing cleanup.")
                Movement.reset(false)
                ChestsInteractor.clearInteractedObjects()
                ChestsInteractor.clearBlacklist()
                was_in_helltide = false
                teleport.reset()
                if maidenmain_enabled then
                    maidenmain.clearBlacklist()
                    maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:set(false)
                    maidenmain_enabled = false
                    console.print("Maiden plugin disabled after Helltide ended.")
                end
                explorer.disable()
            end

            -- Sempre tenta teleportar quando não está em Helltide
            console.print("Not in the Helltide zone. Attempting to teleport...")
            local teleport_result = teleport.tp_to_next(ChestsInteractor, Movement)
            if teleport_result then
                console.print("Teleported successfully. Loading new waypoints...")
                local waypoints, _ = waypoint_loader.load_route(nil, false)
                if waypoints then
                    local randomized_waypoints = {}
                    for _, wp in ipairs(waypoints) do
                        table.insert(randomized_waypoints, waypoint_loader.randomize_waypoint(wp))
                    end
                    Movement.set_waypoints(randomized_waypoints)
                    Movement.set_moving(true)
                end
            else
                local teleport_info = teleport.get_teleport_info()
                console.print("Teleport not successful. Current state: " .. teleport_info.state)
                console.print("Attempts: " .. teleport_info.attempts .. "/" .. teleport_info.max_attempts)
                if teleport_info.cooldown > 0 then
                    console.print("Cooldown: " .. teleport_info.cooldown .. " seconds remaining")
                end
            end
        end
    end
end)

-- Render menu function
on_render_menu(function()
    menu_renderer.render_menu(plugin_enabled, doorsEnabled, loopEnabled, revive_enabled, profane_mindcage_enabled, profane_mindcage_count)
end)

-- Render function for maidenmain
on_render(function()
    if maidenmain_enabled then
        maidenmain.render()
    end
end)

console.print(">>Helltide Chests Farmer Eletroluz V1.5 with Maidenmain integration<<")