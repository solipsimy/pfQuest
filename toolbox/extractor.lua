#!/usr/bin/lua
-- depends on luasql

DEBUG, DLOOP = nil, -1
function __DEBUG_LOOP_LIMIT()
  if not DEBUG then return nil end

  if DLOOP == -1 then DLOOP = 5 end
  if DLOOP == 0 then
    DLOOP = -1
    return true
  end

  DLOOP = DLOOP -1
  return nil
end

-- map pngs with alpha channel generated with:
-- `convert $file  -transparent white -resize '100x100!' $file`

do -- server config
  cmangos = setmetatable({}, { __index = function(tab,key)
    local value = tostring(key)
    rawset(tab,key,value)
    return value
  end})

  vmangos = {
    ["cmangos"] = "vmangos",
    ["Id"] = "entry",
    ["Entry"] = "entry",
    ["Faction"] = "faction",
    ["Name"] = "name",
    ["MinLevel"] = "level_min",
    ["MaxLevel"] = "level_max",
    ["Rank"] = "rank",
    ["RequiresSpellFocus"] = "requiresSpellFocus",
    ["dbscripts_on_event"] = "event_scripts",
  }
end

local C = cmangos
local expansions = {
  "vanilla", "tbc"
}

local locales = {
  ["enUS"] = 0,
  ["koKR"] = 1,
  ["frFR"] = 2,
  ["deDE"] = 3,
  ["zhCN"] = 4,
  ["esES"] = 6,
  ["ruRU"] = 8,
}

do -- map lookup functions
  maps = {}
  package.path = './pngLua/?.lua;' .. package.path
  require("png")

  function isFile(name)
    if type(name)~="string" then return false end
    if not ( os.rename(name,name) and true or false ) then return false end
    local f = io.open(name)
    if not f then return false end
    f:close()
    return true
  end

  function isValidMap(map,x,y)
    -- load map if required
    if not maps[map] and isFile("maps/" .. map .. ".png") then
      maps[map] = pngImage("maps/" .. map .. ".png")
    end

    -- no mapfile means valid map
    if not maps[map] then return true end

    -- error handling
    if not maps[map].getPixel then return false end
    if x == 0 or y == 0 then return false end

    -- check pixel alpha
    local pixel = maps[map]:getPixel(x,y)
    if pixel and pixel.A and pixel.A > 0 then
      return true
    else
      return false
    end
  end
end

do -- helper functions
  function round(input, places)
    if not places then places = 0 end
    if type(input) == "number" and type(places) == "number" then
      local pow = 1
      for i = 1, places do pow = pow * 10 end
      return math.floor(input * pow + 0.5) / pow
    end
  end

  function sanitize(str)
    str = string.gsub(str, "\"", "\\\"")
    str = string.gsub(str, "\'", "\\\'")
    str = string.gsub(str, "\r", "")
    str = string.gsub(str, "\n", "")
    return str
  end

  -- http://lua-users.org/wiki/SortedIteration
  function __genOrderedIndex( t )
    local orderedIndex = {}
    for key in pairs(t) do
      table.insert( orderedIndex, key )
    end
    table.sort( orderedIndex )
    return orderedIndex
  end

  function orderedNext(t, state)
    local key = nil
    if state == nil then
      t.__orderedIndex = __genOrderedIndex( t )
      key = t.__orderedIndex[1]
    else
      for i = 1,#t.__orderedIndex do
        if t.__orderedIndex[i] == state then
          key = t.__orderedIndex[i+1]
        end
      end
    end

    if key then
      return key, t[key]
    end

    t.__orderedIndex = nil
    return
  end

  function opairs(t)
      return orderedNext, t, nil
  end
  --

  function tblsize(tbl)
    local count = 0
    for _ in pairs(tbl) do
      count = count + 1
    end
    return count
  end

  function smalltable(tbl)
    local size = tblsize(tbl)
    if size > 10 then return end
    if size < 1 then return end

    for i=1, size do
      if not tbl[i] then return end
      if type(tbl[i]) == "table" then return end
    end

    return true
  end

  function trealsize(tbl)
    local count = 0
    for _ in pairs(tbl) do
      count = count + 1
    end
    return count
  end

  function tablesubstract(new, base)
    local ret = {}

    if not base then
      ret = new
    elseif type(new) == "table" and type(base) == "table" then
      for k, v in pairs(new) do
        if base[k] and type(base[k]) == "table" and type(v) == "table"  then
          local result = tablesubstract(v, base[k])
          -- only write table if there is at least one change
          if trealsize(result) > 0 then ret[k] = result end
        elseif base[k] and type(base[k]) ~= "table" and type(v) ~= "table" then
          if base[k] ~= v then
            ret[k] = v
          end
        elseif not base[k] then
          ret[k] = v
        end
      end

      -- add delete entries for obsolete values
      for k, v in pairs(base) do
        if not new[k] then
          ret[k] = "_"
        end
      end
    else
      print("ERROR: non-table assigned to `tablesubstract`")
    end

    return ret
  end

  function serialize(file, name, tbl, spacing, flat)
    local closehandle = type(file) == "string"
    local file = type(file) == "string" and io.open(file, "w") or file
    local spacing = spacing or ""

    if tblsize(tbl) == 0 then
      file:write(spacing .. name .. " = {},\n")
    else
      file:write(spacing .. name .. " = {\n")

      for k, v in opairs(tbl) do
        local prefix = "["..k.."]"
        if type(k) == "string" then
          prefix = "[\""..k.."\"]"
        end

        if type(v) == "table" and flat then
          file:write("  "..spacing..prefix .. " = {},\n")
        elseif type(v) == "table" and smalltable(v) then
          local init
          local line = spacing.."  "..prefix.." = { "
          for _, v in pairs(v) do
            line = line .. (init and ", " or "") .. (type(v) == "string" and "\""..v.."\"" or v)
            if not init then
              init = true
            end
          end
          line = line .. " },\n"
          file:write(line)

        elseif type(v) == "table" then
          serialize(file, prefix, v, spacing .. "  ")
        elseif type(v) == "string" then
          file:write("  "..spacing..prefix .. " = " .. "\"" .. v .. "\",\n")
        elseif type(v) == "number" then
          file:write("  "..spacing..prefix .. " = " .. v .. ",\n")
        end
      end

      file:write(spacing.."}" .. (not closehandle and "," or "") .. "\n")
    end

    if closehandle then file:close() end
  end
end

local pfDB = {}

for _, expansion in pairs(expansions) do
  print("Extracting: " .. expansion)
  do -- database connection
    luasql = require("luasql.mysql").mysql()
    mysql = luasql:connect(C["cmangos"].."-"..expansion,"mangos","mangos","127.0.0.1")
  end

  do -- database query functions
    function GetCreatureCoords(id)
      local creature = {}
      local ret = {}

      local sql = [[
        SELECT * FROM creature LEFT JOIN pfquest.WorldMapArea_]]..expansion..[[
        ON ( pfquest.WorldMapArea_]]..expansion..[[.mapID = creature.map
          AND pfquest.WorldMapArea_]]..expansion..[[.x_min < creature.position_x
          AND pfquest.WorldMapArea_]]..expansion..[[.x_max > creature.position_x
          AND pfquest.WorldMapArea_]]..expansion..[[.y_min < creature.position_y
          AND pfquest.WorldMapArea_]]..expansion..[[.y_max > creature.position_y
          AND pfquest.WorldMapArea_]]..expansion..[[.areatableID > 0)
        WHERE creature.id = ]] .. id .. [[ ORDER BY areatableID, position_x, position_y, spawntimesecsmin ]]

      local query = mysql:execute(sql)
      while query:fetch(creature, "a") do
        local zone = creature.areatableID
        local x = creature.position_x
        local y = creature.position_y
        local x_max = creature.x_max
        local x_min = creature.x_min
        local y_max = creature.y_max
        local y_min = creature.y_min
        local px, py = 0, 0

        if x and y and x_min and y_min then
          px = round(100 - (y - y_min) / ((y_max - y_min)/100),1)
          py = round(100 - (x - x_min) / ((x_max - x_min)/100),1)
          if isValidMap(zone, round(px), round(py)) then
            local coord = { px, py, tonumber(zone), ( tonumber(creature.spawntimesecsmin) > 0 and tonumber(creature.spawntimesecsmin) or 0) }
            table.insert(ret, coord)
          end
        end
      end

      return ret
    end

    function GetGameObjectCoords(id)
      local gameobject = {}
      local ret = {}

      local sql = [[
        SELECT * FROM gameobject LEFT JOIN pfquest.WorldMapArea_]]..expansion..[[
        ON ( pfquest.WorldMapArea_]]..expansion..[[.mapID = gameobject.map
          AND pfquest.WorldMapArea_]]..expansion..[[.x_min < gameobject.position_x
          AND pfquest.WorldMapArea_]]..expansion..[[.x_max > gameobject.position_x
          AND pfquest.WorldMapArea_]]..expansion..[[.y_min < gameobject.position_y
          AND pfquest.WorldMapArea_]]..expansion..[[.y_max > gameobject.position_y
          AND pfquest.WorldMapArea_]]..expansion..[[.areatableID > 0)
        WHERE gameobject.id = ]] .. id .. [[ ORDER BY areatableID, position_x, position_y, spawntimesecsmin ]]

      local query = mysql:execute(sql)
      while query:fetch(gameobject, "a") do
        local zone   = gameobject.areatableID
        local x      = gameobject.position_x
        local y      = gameobject.position_y
        local x_max  = gameobject.x_max
        local x_min  = gameobject.x_min
        local y_max  = gameobject.y_max
        local y_min  = gameobject.y_min
        local px, py = 0, 0

        if x and y and x_min and y_min then
          px = round(100 - (y - y_min) / ((y_max - y_min)/100),1)
          py = round(100 - (x - x_min) / ((x_max - x_min)/100),1)
          if isValidMap(zone, round(px), round(py)) then
            local coord = { px, py, tonumber(zone), ( tonumber(gameobject.spawntimesecsmin) > 0 and tonumber(gameobject.spawntimesecsmin) or 0) }
            table.insert(ret, coord)
          end
        end
      end

      return ret
    end
  end

  local exp = expansion == "vanilla" and "" or "-"..expansion
  local data = "data".. exp

  do -- units
    print("- loading units...")

    pfDB["units"] = pfDB["units"] or {}
    pfDB["units"][data] = {}

    -- iterate over all creatures
    local creature_template = {}
    local query = mysql:execute('SELECT * FROM creature_template GROUP BY creature_template.entry ORDER BY creature_template.entry')
    while query:fetch(creature_template, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry   = tonumber(creature_template[C.Entry])
      local name    = creature_template[C.Name]
      local minlvl  = creature_template[C.MinLevel]
      local maxlvl  = creature_template[C.MaxLevel]
      local rnk     = creature_template[C.Rank]
      local lvl     = (minlvl == maxlvl) and minlvl or minlvl .. "-" .. maxlvl

      pfDB["units"][data][entry] = {}
      pfDB["units"][data][entry]["lvl"] = lvl
      if tonumber(rnk) > 0 then
        pfDB["units"][data][entry]["rnk"] = rnk
      end

      do -- detect faction
        local fac = ""
        local faction = {}
        local sql = [[
          SELECT A, H FROM creature_template, pfquest.FactionTemplate_]]..expansion..[[
          WHERE pfquest.FactionTemplate_]]..expansion..[[.factiontemplateID = creature_template.]] .. C.Faction .. [[
          AND creature_template.]] .. C.Entry .. [[ = ]] .. creature_template[C.Entry]

        local query = mysql:execute(sql)
        while query:fetch(faction, "a") do
          local A = faction.A
          local H = faction.H
          if A == "1" then fac = fac .. "A" end
          if H == "1" then fac = fac .. "H" end
        end

        if fac ~= "" then
          pfDB["units"][data][entry]["fac"] = fac
        end
      end

      do -- coordinates
        pfDB["units"][data][entry]["coords"] = {}

        for id, coords in pairs(GetCreatureCoords(entry)) do
          local x, y, zone, respawn = unpack(coords)
          table.insert(pfDB["units"][data][entry]["coords"], { x, y, zone, respawn })
        end

        -- search for summoned mobs
        local event_scripts = {}
        local query = mysql:execute('SELECT * FROM ' .. C.dbscripts_on_event .. ' WHERE ' .. C.dbscripts_on_event .. '.datalong = ' .. creature_template[C.Entry])
        while query:fetch(event_scripts, "a") do
          local script = event_scripts.datalong

          local spell_template = {}
          local query = mysql:execute('SELECT * FROM spell_template WHERE '..C.RequiresSpellFocus..' > 0 AND spell_template.effectMiscValue1 = ' .. event_scripts.id)
          while query:fetch(spell_template, "a") do
            local spellfocus = spell_template[C.RequiresSpellFocus]

            local gameobject_template = {}
            local query = mysql:execute('SELECT * FROM gameobject_template WHERE gameobject_template.type = 8 and gameobject_template.data0 = ' .. spellfocus)
            while query:fetch(gameobject_template, "a") do
              local object = gameobject_template.entry
              for id, coords in pairs(GetGameObjectCoords(object)) do
                local x, y, zone, respawn = unpack(coords)
                table.insert(pfDB["units"][data][entry]["coords"], { x, y, zone, respawn })
              end
            end
          end
        end
      end
    end
  end

  do -- objects
    print("- loading objects...")

    pfDB["objects"] = pfDB["objects"] or {}
    pfDB["objects"][data] = {}

    -- iterate over all objects
    local gameobject_template = {}
    local query = mysql:execute('SELECT * FROM gameobject_template GROUP BY gameobject_template.entry ORDER BY gameobject_template.entry ASC')
    while query:fetch(gameobject_template, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry  = tonumber(gameobject_template.entry)
      local name   = gameobject_template.name

      pfDB["objects"][data][entry] = {}

      do -- detect faction
        local fac = ""
        local faction = {}
        local sql = [[
          SELECT A FROM gameobject_template, pfquest.FactionTemplate_]]..expansion..[[
          WHERE pfquest.FactionTemplate_]]..expansion..[[.factiontemplateID = gameobject_template.faction
          AND gameobject_template.entry = ]] .. gameobject_template.entry

        local query = mysql:execute(sql)
        while query:fetch(faction, "a") do
          local A = faction.A
          if A == "1" then fac = fac .. "A" end
        end

        local faction = {}
        local sql = [[
          SELECT H FROM gameobject_template, pfquest.FactionTemplate_]]..expansion..[[
          WHERE pfquest.FactionTemplate_]]..expansion..[[.factiontemplateID = gameobject_template.faction
          AND gameobject_template.entry = ]] .. gameobject_template.entry

        local query = mysql:execute(sql)
        while query:fetch(faction, "a") do
          local H = faction.H
          if H == "1" then fac = fac .. "H" end
        end

        if fac ~= "" then
          pfDB["objects"][data][entry]["fac"] = fac
        end
      end

      do -- coordinates
        pfDB["objects"][data][entry]["coords"] = {}

        for id,coords in pairs(GetGameObjectCoords(entry)) do
          local x, y, zone, respawn = unpack(coords)
          table.insert(pfDB["objects"][data][entry]["coords"], { x, y, zone, respawn })
        end
      end
    end
  end

  do -- items
    print("- loading items...")

    pfDB["items"] = pfDB["items"] or {}
    pfDB["items"][data] = {}

    -- iterate over all items
    local item_template = {}
    local query = mysql:execute('SELECT entry, name FROM item_template GROUP BY item_template.entry ASC')
    while query:fetch(item_template, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry = tonumber(item_template.entry)
      local scans = { [0] = { entry, nil } }

      -- add items that contain the actual item to the itemlist
      local item_loot_item = {}
      local count = 0
      local query = mysql:execute('SELECT entry, ChanceOrQuestChance FROM item_loot_template WHERE item = ' .. item_template.entry .. ' ORDER BY entry')
      while query:fetch(item_loot_item, "a") do
        if math.abs(item_loot_item.ChanceOrQuestChance) > 0 then
          table.insert(scans, { tonumber(item_loot_item.entry), math.abs(item_loot_item.ChanceOrQuestChance) })
        end
      end

      -- recursively read U, O, V, R blocks of the item
      for id, item in pairs(scans) do
        local entry = tonumber(item[1])
        local chance = item[2] and item[2] / 100 or 1
        pfDB["items"][data][entry] = pfDB["items"][data][entry] or {}

        -- fill unit table
        local creature_loot_template = {}
        local query = mysql:execute('SELECT entry, ChanceOrQuestChance FROM creature_loot_template WHERE item = ' .. entry .. ' ORDER BY entry')
        while query:fetch(creature_loot_template, "a") do
          local chance = round(math.abs(creature_loot_template.ChanceOrQuestChance) * chance, 5)
          if chance > 0 then
            pfDB["items"][data][entry]["U"] = pfDB["items"][data][entry]["U"] or {}
            pfDB["items"][data][entry]["U"][tonumber(creature_loot_template.entry)] = chance
          end
        end

        -- fill object table
        local gameobject_loot_template = {}
        local query = mysql:execute([[
          SELECT gameobject_template.entry, gameobject_loot_template.ChanceOrQuestChance FROM gameobject_loot_template
          INNER JOIN gameobject_template ON gameobject_template.data1 = gameobject_loot_template.entry
          WHERE ( gameobject_template.type = 3 OR gameobject_template.type = 25 )
          AND gameobject_loot_template.item = ]] .. entry .. [[ ORDER BY gameobject_template.entry ]])
        while query:fetch(gameobject_loot_template, "a") do
          local chance = round(math.abs(gameobject_loot_template.ChanceOrQuestChance) * chance, 5)
          if chance > 0 then
            pfDB["items"][data][entry]["O"] = pfDB["items"][data][entry]["O"] or {}
            pfDB["items"][data][entry]["O"][tonumber(gameobject_loot_template.entry)] = chance
          end
        end

        -- fill reference table
        local reference_loot_template = {}
        local query = mysql:execute([[
          SELECT entry, ChanceOrQuestChance FROM reference_loot_template where reference_loot_template.item = ]] .. entry .. [[ GROUP BY entry
        ]])
        while query:fetch(reference_loot_template, "a") do
          pfDB["items"][data][entry]["R"] = pfDB["items"][data][entry]["R"] or {}
          pfDB["items"][data][entry]["R"][tonumber(reference_loot_template.entry)] = tonumber(reference_loot_template.ChanceOrQuestChance)
        end

        -- fill vendor table
        local npc_vendor = {}
        local query = mysql:execute('SELECT entry, maxcount FROM npc_vendor WHERE item = ' .. entry .. ' ORDER BY entry')
        while query:fetch(npc_vendor, "a") do
          pfDB["items"][data][entry]["V"] = pfDB["items"][data][entry]["V"] or {}
          pfDB["items"][data][entry]["V"][tonumber(npc_vendor.entry)] = tonumber(npc_vendor.maxcount)
        end

        -- handle vendor template tables
        local npc_vendor = {}
        local query = mysql:execute('SELECT creature_template.entry, maxcount FROM npc_vendor_template, creature_template WHERE item = ' .. entry .. ' and creature_template.VendorTemplateId = npc_vendor_template.entry ORDER BY creature_template.entry')
        while query:fetch(npc_vendor, "a") do
          pfDB["items"][data][entry]["V"] = pfDB["items"][data][entry]["V"] or {}
          pfDB["items"][data][entry]["V"][tonumber(npc_vendor.entry)] = tonumber(npc_vendor.maxcount)
        end
      end
    end
  end

  do -- refloot
    print("- loading refloot...")

    pfDB["refloot"] = pfDB["refloot"] or {}
    pfDB["refloot"][data] = {}

    -- iterate over all reference loots
    local reference_loot_template = {}
    local query = mysql:execute('SELECT entry, ChanceOrQuestChance FROM reference_loot_template GROUP BY entry')
    while query:fetch(reference_loot_template, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry = tonumber(reference_loot_template.entry)

      -- fill unit table
      local creature_loot_template = {}
      local count = 0
      local query = mysql:execute([[
        SELECT entry FROM creature_loot_template
        WHERE creature_loot_template.mincountOrRef < 0
        AND item = ]] .. entry .. [[ ORDER BY entry
      ]])
      while query:fetch(creature_loot_template, "a") do
        pfDB["refloot"][data][entry] = pfDB["refloot"][data][entry] or {}
        pfDB["refloot"][data][entry]["U"] = pfDB["refloot"][data][entry]["U"] or {}
        pfDB["refloot"][data][entry]["U"][tonumber(creature_loot_template.entry)] = 1
      end

      -- fill object table
      local gameobject_template = {}
      local count = 0
      local query = mysql:execute([[
        SELECT gameobject_template.entry FROM gameobject_template, gameobject_loot_template
        WHERE gameobject_template.data1 = gameobject_loot_template.entry
        AND gameobject_loot_template.mincountOrRef < 0
        AND gameobject_loot_template.item = ]] .. entry .. [[ ORDER BY gameobject_template.entry ;
      ]])
      while query:fetch(gameobject_template, "a") do
        pfDB["refloot"][data][entry] = pfDB["refloot"][data][entry] or {}
        pfDB["refloot"][data][entry]["O"] = pfDB["refloot"][data][entry]["O"] or {}
        pfDB["refloot"][data][entry]["O"][tonumber(gameobject_template.entry)] = 1
      end
    end
  end

  do -- quests
    print("- loading quests...")

    pfDB["quests"] = pfDB["quests"] or {}
    pfDB["quests"][data] = {}

    -- iterate over all quests
    local quest_template = {}
    local query = mysql:execute('SELECT * FROM quest_template GROUP BY quest_template.entry')
    while query:fetch(quest_template, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry = tonumber(quest_template.entry)
      local minlevel = tonumber(quest_template.MinLevel)
      local questlevel = tonumber(quest_template.QuestLevel)
      local class = tonumber(quest_template.RequiredClasses)
      local race = tonumber(quest_template.RequiredRaces)
      local skill = tonumber(quest_template.RequiredSkill)
      local pre = tonumber(quest_template.PrevQuestId)
      local chain = tonumber(quest_template.NextQuestInChain)

      pfDB["quests"][data][entry] = {}
      pfDB["quests"][data][entry]["min"] = minlevel ~= 0 and minlevel
      pfDB["quests"][data][entry]["skill"] = skill ~= 0 and skill
      pfDB["quests"][data][entry]["lvl"] = questlevel ~= 0 and questlevel
      pfDB["quests"][data][entry]["class"] = class ~= 0 and class
      pfDB["quests"][data][entry]["race"] = race ~= 0 and race
      pfDB["quests"][data][entry]["skill"] = skill ~= 0 and skill
      pfDB["quests"][data][entry]["pre"] = pre ~= 0 and pre
      pfDB["quests"][data][entry]["next"] = chain ~= 0 and chain

      -- quest objectives
      local units, objects, items = {}, {}, {}

      for i=1,4 do
        if quest_template["ReqCreatureOrGOId" .. i] and tonumber(quest_template["ReqCreatureOrGOId" .. i]) > 0 then
          units[quest_template["ReqCreatureOrGOId" .. i]] = true
        elseif quest_template["ReqCreatureOrGOId" .. i] and tonumber(quest_template["ReqCreatureOrGOId" .. i]) < 0 then
          objects[math.abs(tonumber(quest_template["ReqCreatureOrGOId" .. i]))] = true
        end
        if quest_template["ReqItemId" .. i] and tonumber(quest_template["ReqItemId" .. i]) > 0 then
          items[tonumber(quest_template["ReqItemId" .. i])] = true
        end
        if quest_template["ReqSourceId" .. i] and tonumber(quest_template["ReqSourceId" .. i]) > 0 then
          items[tonumber(quest_template["ReqSourceId" .. i])] = true
        end
        if quest_template["ReqSpellCast" .. i] and tonumber(quest_template["ReqSpellCast" .. i]) > 0 then
          local spell_template = {}
          local query = mysql:execute('SELECT * FROM spell_template WHERE spell_template.' .. C.Id .. ' = ' .. quest_template["ReqSpellCast" .. i])
          while query:fetch(spell_template, "a") do
            if spell_template[C.RequiresSpellFocus] ~= "0" then
              local gameobject_template = {}
              local query = mysql:execute('SELECT * FROM gameobject_template WHERE gameobject_template.type = 8 and gameobject_template.data0 = ' .. spell_template[C.RequiresSpellFocus])
              while query:fetch(gameobject_template, "a") do
                objects[tonumber(gameobject_template["entry"])] = true
              end
            end
          end
        end
      end

      -- scan required object/areas for usable quest items
      if quest_template["SrcItemId"] ~= "0" then
        local item_template = {}
        local query = mysql:execute('SELECT * FROM item_template WHERE item_template.entry = ' .. quest_template["SrcItemId"])
        while query:fetch(item_template, "a") do
          if item_template["spellid_1"] ~= "0" then
            local spell_template = {}
            local query = mysql:execute('SELECT * FROM spell_template WHERE spell_template.' .. C.Id .. ' = ' .. item_template["spellid_1"])
            while query:fetch(spell_template, "a") do
              if spell_template[C.RequiresSpellFocus] ~= "0" then
                local gameobject_template = {}
                local query = mysql:execute('SELECT * FROM gameobject_template WHERE gameobject_template.type = 8 and gameobject_template.data0 = ' .. spell_template[C.RequiresSpellFocus])
                while query:fetch(gameobject_template, "a") do
                  objects[tonumber(gameobject_template["entry"])] = true
                end
              end
            end
          end
        end
      end

      do -- write objectives
        if tblsize(units) > 0 or tblsize(objects) > 0 or tblsize(items) > 0 then
          pfDB["quests"][data][entry]["obj"] = pfDB["quests"][data][entry]["obj"] or {}

          for id in opairs(units) do
            pfDB["quests"][data][entry]["obj"]["U"] = pfDB["quests"][data][entry]["obj"]["U"] or {}
            table.insert(pfDB["quests"][data][entry]["obj"]["U"], tonumber(id))
          end

          for id in opairs(objects) do
            pfDB["quests"][data][entry]["obj"]["O"] = pfDB["quests"][data][entry]["obj"]["O"] or {}
            table.insert(pfDB["quests"][data][entry]["obj"]["O"], tonumber(id))
          end

          for id in opairs(items) do
            pfDB["quests"][data][entry]["obj"]["I"] = pfDB["quests"][data][entry]["obj"]["I"] or {}
            table.insert(pfDB["quests"][data][entry]["obj"]["I"], tonumber(id))
          end
        end
      end

      do -- quest starter
        local creature_questrelation = {}
        local sql = [[
          SELECT * FROM creature_questrelation WHERE creature_questrelation.quest = ]] .. quest_template.entry
        local query = mysql:execute(sql)
        while query:fetch(creature_questrelation, "a") do
          pfDB["quests"][data][entry]["start"] = pfDB["quests"][data][entry]["start"] or {}
          pfDB["quests"][data][entry]["start"]["U"] = pfDB["quests"][data][entry]["start"]["U"] or {}
          table.insert(pfDB["quests"][data][entry]["start"]["U"], tonumber(creature_questrelation.id))
        end

        local gameobject_questrelation = {}
        local sql = [[
          SELECT * FROM gameobject_questrelation WHERE gameobject_questrelation.quest = ]] .. quest_template.entry
        local query = mysql:execute(sql)
        while query:fetch(gameobject_questrelation, "a") do
          pfDB["quests"][data][entry]["start"] = pfDB["quests"][data][entry]["start"] or {}
          pfDB["quests"][data][entry]["start"]["O"] = pfDB["quests"][data][entry]["start"]["O"] or {}
          table.insert(pfDB["quests"][data][entry]["start"]["O"], tonumber(gameobject_questrelation.id))
        end
      end

      do -- quest ender
        local creature_involvedrelation = {}
        local sql = [[
          SELECT * FROM creature_involvedrelation WHERE creature_involvedrelation.quest = ]] .. quest_template.entry
        local query = mysql:execute(sql)
        while query:fetch(creature_involvedrelation, "a") do
          pfDB["quests"][data][entry]["end"] = pfDB["quests"][data][entry]["end"] or {}
          pfDB["quests"][data][entry]["end"]["U"] = pfDB["quests"][data][entry]["end"]["U"] or {}
          table.insert(pfDB["quests"][data][entry]["end"]["U"], tonumber(creature_involvedrelation.id))
        end

        local gameobject_involvedrelation = {}
        local first = true
        local sql = [[
          SELECT * FROM gameobject_involvedrelation WHERE gameobject_involvedrelation.quest = ]] .. quest_template.entry
        local query = mysql:execute(sql)
        while query:fetch(gameobject_involvedrelation, "a") do
          pfDB["quests"][data][entry]["end"] = pfDB["quests"][data][entry]["end"] or {}
          pfDB["quests"][data][entry]["end"]["O"] = pfDB["quests"][data][entry]["end"]["O"] or {}
          table.insert(pfDB["quests"][data][entry]["end"]["O"], tonumber(gameobject_involvedrelation.id))
        end
      end
    end
  end

  do -- minimap
    print("- loading minimap...")

    pfDB["minimap"..exp] = pfDB["minimap"..exp] or {}

    local minimap_size = {}
    local query = mysql:execute('SELECT * FROM pfquest.WorldMapArea_'..expansion..' ORDER BY areatableID ASC')
    while query:fetch(minimap_size, "a") do
      local mapID = minimap_size.mapID
      local areaID = minimap_size.areatableID
      local name = minimap_size.name
      local x_min = minimap_size.x_min
      local y_min = minimap_size.y_min
      local x_max = minimap_size.x_max
      local y_max = minimap_size.y_max

      local x = -1 * x_min + x_max
      local y = -1 * y_min + y_max

      pfDB["minimap"..exp][tonumber(areaID)] = { y, x }
    end
  end

  do -- meta
    print("- loading meta...")

    pfDB["meta"..exp] = pfDB["meta"..exp] or {
      ["mines"] = {},
      ["herbs"] = {},
      ["chests"] = {},
    }

    do -- gameobject relations
      local gameobject_template = {}
      local query = mysql:execute([[
        SELECT entry, data0, skill, locktype FROM `gameobject_template`, pfquest.Lock_]]..expansion..[[
        WHERE `type` = 3 AND `flags` = 0 AND `data1` > 0 and id = data0 GROUP BY `gameobject_template`.entry ORDER BY `gameobject_template`.entry ASC
      ]])

      while query:fetch(gameobject_template, "a") do
        local entry   = tonumber(gameobject_template.entry) * -1
        local locktype = tonumber(gameobject_template.locktype)
        local skill = tonumber(gameobject_template.skill)
        if locktype == 1 then
          pfDB["meta"..exp]["chests"][entry] = skill
        elseif locktype == 2 then
          pfDB["meta"..exp]["herbs"][entry] = skill
        elseif locktype == 3 then
          pfDB["meta"..exp]["mines"][entry] = skill
        end
      end
    end
  end

  print("- loading locales...")
  do -- unit locales
    -- load unit locales
    local units_loc = {}
    local locales_creature = {}
    local query = mysql:execute('SELECT * FROM creature_template LEFT JOIN locales_creature ON locales_creature.entry = creature_template.entry GROUP BY creature_template.entry ORDER BY creature_template.entry ASC')
    while query:fetch(locales_creature, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry = tonumber(locales_creature.entry)
      local name  = locales_creature[C.Name]

      if entry then
        for loc in pairs(locales) do
          local name_loc = locales_creature["name_loc" .. locales[loc]]
          if not name_loc or name_loc == "" then name_loc = name or "" end
          if name_loc and name_loc ~= "" then
            local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
            pfDB["units"][locale] = pfDB["units"][locale] or {}
            pfDB["units"][locale][entry] = sanitize(name_loc)
          end
        end
      end
    end
  end

  do -- objects locales
    local locales_gameobject = {}
    local query = mysql:execute('SELECT * FROM gameobject_template LEFT JOIN locales_gameobject ON locales_gameobject.entry = gameobject_template.entry GROUP BY gameobject_template.entry ORDER BY gameobject_template.entry ASC')
    while query:fetch(locales_gameobject, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry = tonumber(locales_gameobject.entry)
      local name  = locales_gameobject.name

      if entry then
        for loc in pairs(locales) do
          local name_loc = locales_gameobject["name_loc" .. locales[loc]]
          if not name_loc or name_loc == "" then name_loc = name or "" end
          if name_loc and name_loc ~= "" then
            local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
            pfDB["objects"][locale] = pfDB["objects"][locale] or {}
            pfDB["objects"][locale][entry] = sanitize(name_loc)
          end
        end
      end
    end
  end

  do -- items locales
    local items_loc = {}
    local locales_item = {}
    local query = mysql:execute('SELECT * FROM item_template LEFT JOIN locales_item ON locales_item.entry = item_template.entry GROUP BY item_template.entry ORDER BY item_template.entry ASC')
    while query:fetch(locales_item, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry = tonumber(locales_item.entry)
      local name  = locales_item.name

      if entry then
        for loc in pairs(locales) do
          local name_loc = locales_item["name_loc" .. locales[loc]]
          if not name_loc or name_loc == "" then name_loc = name or "" end
          if name_loc and name_loc ~= "" then
            local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
            pfDB["items"][locale] = pfDB["items"][locale] or {}
            pfDB["items"][locale][entry] = sanitize(name_loc)
          end
        end
      end
    end
  end

  do -- quests locales
    local locales_quest = {}
    local query = mysql:execute('SELECT * FROM quest_template LEFT JOIN locales_quest ON locales_quest.entry = quest_template.entry GROUP BY quest_template.entry ORDER BY quest_template.entry ASC')
    while query:fetch(locales_quest, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      for loc in pairs(locales) do
        local entry = tonumber(locales_quest.entry)

        if entry then
          local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
          pfDB["quests"][locale] = pfDB["quests"][locale] or {}

          local title_loc = locales_quest["Title_loc" .. locales[loc]]
          local details_loc = locales_quest["Details_loc" .. locales[loc]]
          local objectives_loc = locales_quest["Objectives_loc" .. locales[loc]]

          -- fallback to enUS titles
          if not title_loc or title_loc == "" then title_loc = locales_quest.Title or "" end
          if not details_loc or details_loc == "" then details_loc = locales_quest.Details or "" end
          if not objectives_loc or objectives_loc == "" then objectives_loc = locales_quest.Objectives or "" end

          pfDB["quests"][locale][entry] = {
            ["T"] = sanitize(title_loc),
            ["O"] = sanitize(objectives_loc),
            ["D"] = sanitize(details_loc)
          }
        end
      end
    end
  end

  do -- professions locales
    pfDB["professions"] = {}
    local locales_professions = {}
    local query = mysql:execute('SELECT * FROM pfquest.SkillLine_'..expansion..' ORDER BY id ASC')
    while query:fetch(locales_professions, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry = tonumber(locales_professions.id)

      if entry then
        for loc in pairs(locales) do
          local name = locales_professions["name_loc" .. locales[loc]]
          if name and name ~= "" then
            local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
            pfDB["professions"][locale] = pfDB["professions"][locale] or {}
            pfDB["professions"][locale][entry] = sanitize(name)
          end
        end
      end
    end
  end

  do -- zones locales
    pfDB["zones"] = {}

    local locales_zones = {}
    local query = mysql:execute('SELECT * FROM pfquest.AreaTable_'..expansion..' ORDER BY id ASC')
    while query:fetch(locales_zones, "a") do
      if __DEBUG_LOOP_LIMIT() then break end

      local entry = tonumber(locales_zones.id)

      if entry then
        for loc in pairs(locales) do
          local name = locales_zones["name_loc" .. locales[loc]]
          if name and name ~= "" then
            local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
            pfDB["zones"][locale] = pfDB["zones"][locale] or {}
            pfDB["zones"][locale][entry] = sanitize(name)
          end
        end
      end
    end
  end

  if expansion ~= "vanilla" then
    print("- compress DB")
    local prev_exp = expansion == "tbc" and "" or "-tbc"
    local prev_data = "data".. prev_exp

    pfDB["units"][data] = tablesubstract(pfDB["units"][data], pfDB["units"][prev_data])
    pfDB["objects"][data] = tablesubstract(pfDB["objects"][data], pfDB["objects"][prev_data])
    pfDB["items"][data] = tablesubstract(pfDB["items"][data], pfDB["items"][prev_data])
    pfDB["refloot"][data] = tablesubstract(pfDB["refloot"][data], pfDB["refloot"][prev_data])
    pfDB["quests"][data] = tablesubstract(pfDB["quests"][data], pfDB["quests"][prev_data])
    pfDB["minimap"..exp] = tablesubstract(pfDB["minimap"..exp], pfDB["minimap"..prev_exp])
    pfDB["meta"..exp] = tablesubstract(pfDB["meta"..exp], pfDB["meta"..prev_exp])


    for loc in pairs(locales) do
      local locale = loc .. exp
      local prev_locale = loc .. prev_exp

      os.execute("mkdir -p output/" .. loc)
      pfDB["units"][locale] = tablesubstract(pfDB["units"][locale], pfDB["units"][prev_locale])
      pfDB["objects"][locale] = tablesubstract(pfDB["objects"][locale], pfDB["objects"][prev_locale])
      pfDB["items"][locale] = tablesubstract(pfDB["items"][locale], pfDB["items"][prev_locale])
      pfDB["quests"][locale] = tablesubstract(pfDB["quests"][locale], pfDB["quests"][prev_locale])
      pfDB["professions"][locale] = tablesubstract(pfDB["professions"][locale], pfDB["professions"][prev_locale])
      pfDB["zones"][locale] = tablesubstract(pfDB["zones"][locale], pfDB["zones"][prev_locale])
    end
  end

  -- write down tables
  print("- writing database...")

  os.execute("mkdir -p output")
  serialize("output/init.lua", "pfDB", pfDB, nil, true)
  serialize(string.format("output/units%s.lua", exp), "pfDB[\"units\"][\""..data.."\"]", pfDB["units"][data])
  serialize(string.format("output/objects%s.lua", exp), "pfDB[\"objects\"][\""..data.."\"]", pfDB["objects"][data])
  serialize(string.format("output/items%s.lua", exp), "pfDB[\"items\"][\""..data.."\"]", pfDB["items"][data])
  serialize(string.format("output/refloot%s.lua", exp), "pfDB[\"refloot\"][\""..data.."\"]", pfDB["refloot"][data])
  serialize(string.format("output/quests%s.lua", exp), "pfDB[\"quests\"][\""..data.."\"]", pfDB["quests"][data])
  serialize(string.format("output/minimap%s.lua", exp), "pfDB[\"minimap"..exp.."\"]", pfDB["minimap"..exp])
  serialize(string.format("output/meta%s.lua", exp), "pfDB[\"meta"..exp.."\"]", pfDB["meta"..exp])

  for loc in pairs(locales) do
    local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )

    os.execute("mkdir -p output/" .. loc)
    serialize(string.format("output/%s/units%s.lua", loc, exp), "pfDB[\"units\"][\""..locale.."\"]", pfDB["units"][locale])
    serialize(string.format("output/%s/objects%s.lua", loc, exp), "pfDB[\"objects\"][\""..locale.."\"]", pfDB["objects"][locale])
    serialize(string.format("output/%s/items%s.lua", loc, exp), "pfDB[\"items\"][\""..locale.."\"]", pfDB["items"][locale])
    serialize(string.format("output/%s/quests%s.lua", loc, exp), "pfDB[\"quests\"][\""..locale.."\"]", pfDB["quests"][locale])
    serialize(string.format("output/%s/professions%s.lua", loc, exp), "pfDB[\"professions\"][\""..locale.."\"]", pfDB["professions"][locale])
    serialize(string.format("output/%s/zones%s.lua", loc, exp), "pfDB[\"zones\"][\""..locale.."\"]", pfDB["zones"][locale])
  end
end
