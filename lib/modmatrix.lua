local ModMatrix = {
    tBINARY = 1,
    tUNIPOLAR = 2,
    tBIPOLAR = 3,
    matrix = {}, -- modulation -> param -> depth
    bangers = {{}, {}, {}, {}},
    sources_list = {}, -- List of mod sources
    sources_indexes = {}, -- mod sources by index
}

function ModMatrix:bang_all()
    for tn, tier in ipairs(self.bangers) do
        local done = false
        for round=1,3,1 do
            for v, _ in pairs(tier) do
                params:lookup_param(v):bang()
                tier[v] = nil
            end
            if next(tier) == nil then
                done = true
                break
            end
        end
        if not done then
            print("Missing modulation; too much recursion", tn)
            tab.print(tier)
            self.bangers[tn] = {}
        end
    end
    self.bang_deferred = nil
end

function ModMatrix:defer_bang(param_id, tier)
    if tier == nil then tier = 3 end
    if self.bang_deferred == nil then
        clock.run(function()
            clock.sleep(0)
            self:bang_all()
        end)
    end
    self.bang_deferred = true
    self.bangers[tier][param_id] = true
end

function ModMatrix:lookup_source(id)
    if type(id) == "string" and self.sources_indexes[id] then
        return self.sources_list[self.sources_indexes[id]]
    elseif self.sources_list[id] then
        return self.sources_list[id]
    else
        error("invalid mod matrix index: "..id)
    end
end

function ModMatrix:add(source)
    table.insert(self.sources_list, source)
    self.sources_indexes[source.id] = #self.sources_list
end

function ModMatrix:add_binary(id, name)
    self:add{
        t = self.tBINARY,
        name = name,
        id = id,
    }
end

function ModMatrix:add_unipolar(id, name)
    self:add{
        t = self.tUNIPOLAR,
        name = name,
        id = id,
    }
end

function ModMatrix:add_bipolar(id, name)
    self:add{
        t = self.tBIPOLAR,
        name = name,
        id =id,
    }
end

function ModMatrix:get(id)
    return self:lookup_source(id).value
end

local nilmul = function(depth, modulation)
    if modulation == nil then return nil end
    return depth*modulation
end

function ModMatrix:set_depth(param_id, modulation_id, depth)
    if type(modulation_id) == "number" then
        modulation_id = self.sources_list[modulation_id].id
    end
    local p = params:lookup_param(param_id)
    if depth == nil or depth == 0 then
        if self.matrix[modulation_id] ~= nil then
            self.matrix[modulation_id][p.id] = nil        
            if next(self.matrix[modulation_id]) == nil then
                self.matrix[modulation_id] = nil
            end
        end
    else
        if self.matrix[modulation_id] == nil then
            self.matrix[modulation_id] = {}
        end
        self.matrix[modulation_id][p.id] = depth
        if p.modulation == nil then p.modulation = {} end
        p.modulation[modulation_id] = nilmul(self:get(modulation_id))
        if p.t ~= params.tTRIGGER then
            self:defer_bang(p.id, p.priority)
        end
    end
end

function ModMatrix:get_depth(param_id, modulation_id)
    if type(modulation_id) == "number" then
        modulation_id = self.sources_list[modulation_id].id
    end
    if type(param_id) == "number" then
        param_id = params:lookup_param(param_id).id
    end
    if self.matrix[modulation_id] == nil then return nil end
    return self.matrix[modulation_id][param_id]
end

function ModMatrix:set(modulation_id, value)
    local source = self:lookup_source(modulation_id)
    source.value = value
    if self.matrix[source.id] == nil then self.matrix[source.id] = {} end
    local targets = self.matrix[source.id]
    for param_id, depth in pairs(targets) do
        local p = param:lookup_param(param_id)
        p.modulation[source.id] = nilmul(depth, value)
        if p.t ~= params.tTRIGGER then
            params:defer_bang(p.id, p.priority)
        elseif value > 0 then
            params:defer_bang(p.id, p.priority)
        end
    end
end

function ModMatrix:clear()
    self.matrix = {}
    self.bangers = {{}, {}, {}, {}}
    self.sources_list = {}
    self.sources_indexes = {}
end

return ModMatrix