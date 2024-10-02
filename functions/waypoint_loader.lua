-- waypoint_loader.lua

local waypoint_loader = {}
local cached_waypoints = {}

-- Estrutura de dados melhorada para mapear zonas e arquivos de waypoints
waypoint_loader.zone_mappings = {
    ["Frac_Tundra_S"] = {id = 0xACE9B, regular = "menestad", maiden = "menestad_to_maiden"},
    ["Scos_Coast"] = {id = 0x27E01, regular = "marowen", maiden = "marowen_to_maiden"},
    ["Kehj_Oasis"] = {id = 0xDEAFC, regular = "ironwolfs", maiden = "ironwolfs_to_maiden"},
    ["Hawe_Verge"] = {id = 0x9346B, regular = "wejinhani", maiden = "wejinhani_to_maiden"},
    ["Step_South"] = {id = 0x462E2, regular = "jirandai", maiden = "jirandai_to_maiden"}
}

-- Função para carregar waypoints (mantida para compatibilidade)
function waypoint_loader.load_waypoints(file)
    if cached_waypoints[file] then
        return cached_waypoints[file]
    end
    local waypoints = require("waypoints." .. file)
    cached_waypoints[file] = waypoints
    return waypoints
end

-- Função para limpar o cache de waypoints
function waypoint_loader.clear_cached_waypoints()
    cached_waypoints = {}
    collectgarbage("collect")
end

-- Função para randomizar waypoints
function waypoint_loader.randomize_waypoint(waypoint, max_offset)
    max_offset = max_offset or 1.5 -- Valor padrão de 1.5 metros
    local random_x = math.random() * max_offset * 2 - max_offset
    local random_y = math.random() * max_offset * 2 - max_offset
    
    return vec3:new(
        waypoint:x() + random_x,
        waypoint:y() + random_y,
        waypoint:z()
    )
end

-- Função unificada para carregar waypoints e rotas da Maiden
function waypoint_loader.load_route(zone_name, is_maiden_route)
    local world_instance = world.get_current_world()
    if not world_instance then
        console.print("Error: Unable to get world instance")
        return nil, nil
    end

    local zone_name = zone_name or world_instance:get_current_zone_name()
    if not zone_name then
        console.print("Error: Unable to get zone name")
        return nil, nil
    end

    local zone_info = waypoint_loader.zone_mappings[zone_name]
    if not zone_info then
        console.print("No matching zone found for waypoints: " .. zone_name)
        return nil, nil
    end

    local file = is_maiden_route and zone_info.maiden or zone_info.regular
    local route_type = is_maiden_route and "Maiden" or "regular"
    
    console.print("Loading " .. route_type .. " waypoints for zone: " .. zone_name .. " from file: " .. file)
    
    local waypoints
    if cached_waypoints[file] then
        waypoints = cached_waypoints[file]
    else
        waypoints = require("waypoints." .. file)
        cached_waypoints[file] = waypoints
    end
    
    if type(waypoints) ~= "table" or #waypoints == 0 then
        console.print("Error: Waypoints are empty or not a valid table")
        return nil, nil
    end
    
    console.print("Loaded " .. #waypoints .. " waypoints")
    
    return waypoints, zone_info.id
end

-- Função para verificar e carregar waypoints (mantida para compatibilidade)
function waypoint_loader.check_and_load_waypoints()
    local world_instance = world.get_current_world()
    if not world_instance then
        console.print("Error: Unable to get world instance")
        return nil, nil
    end

    local zone_name = world_instance:get_current_zone_name()
    if not zone_name then
        console.print("Error: Unable to get zone name")
        return nil, nil
    end

    return waypoint_loader.load_route(zone_name, false)
end

-- Função para carregar rota da Maiden (mantida para compatibilidade)
function waypoint_loader.load_maiden_route(file)
    for zone_name, info in pairs(waypoint_loader.zone_mappings) do
        if info.regular == file then
            return waypoint_loader.load_route(zone_name, true)
        end
    end
    console.print("Error: Unable to find matching zone for file: " .. file)
    return nil, nil
end

return waypoint_loader