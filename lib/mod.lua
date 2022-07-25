local mod = require 'core/mods'
local lattice = require("lattice")
local er = require("er")
local deque = require('container/deque')

local number = require 'core/params/number'
local control = require 'core/params/control'
local taper = require 'core/params/taper'

local DIVISIONS = {1/16, 1/12, 1/8, 1/7, 1/6, 1/5, 1/4, 1/3, 1/2, 3/4, 1, 5/4, 6/4, 7/4, 2, 4, 8, 32, 64, 128}
local DIVISION_OPTS = {
    "1/16", "1/12", "1/8", "1/7", "1/6", "1/5", "1/4", "1/3", "1/2", "3/4", "4/4", "5/4", "6/4", "7/4", "2", "4", "8", "32", "64", "128"}

local N_RHYTHMS = 4
local N_LFOS = 4
local N_MULTS = 4
local N_SEQS = 4

local state = {
    registered_numbers = {},
    registered_binaries = {},
}

function monkeypatch()
    state.global_raw = false
    
    local core_write = params.write
    
    function params:write(filename, name)
        local old_global_raw = state.global_raw
        state.global_raw = true
        core_write(self, filename, name)
        state.global_raw = old_global_raw
    end

    function number:get(raw)
        if self.modulation == nil or raw == true or state.global_raw then
            return self.value
        end
        local val = self.value
        for _, v in pairs(self.modulation) do
            val = val + (v*self.range)
        end
        val = util.round(val, 1)
        if self.wrap then
            val = util.wrap(val, self.min, self.max)
        else
            val = util.clamp(val, self.min, self.max)
        end
        return val
    end

    function number:bang()
        self.action(self:get())
    end
    
    function number:delta(d)
        self:set(self:get(true) + d)
    end

    function taper:get_modulated_raw()
        if self.modulation == nil then
            return self.value
    else
        local val = self.value
        for _, v in pairs(self.modulation) do
            val = val + v
        end
        if controlspec.wrap then
            val = val % 1
        else
            val = util.clamp(val, 0, 1)
        end
        return val
    end
    end

    function taper:get(raw)
        if raw == true then
            return self:map_value(self.value)
        end
        return self:map_value(self:get_modulated_raw())
    end

    function control:get_modulated_raw()
        if self.modulation == nil then
            return self.raw
        else
            local val = self.raw
            for _, v in pairs(self.modulation) do
                val = val + v
            end
            if controlspec.wrap then
                val = val % 1
            else
                val = util.clamp(val, 0, 1)
            end
            return val
        end
    end

    function control:get(raw)
        if raw == true then
            return self:map_value(self.raw)
        end
        return self:map_value(self:get_modulated_raw())
    end
    state.monkeypatched = true
end -- monkeypatch

function params:get_raw(p)
    return self:lookup_param(p):get(true)
end

local n = function(i, s)
    return "tk_" .. i .. "_" ..s
end

local bang_all = function()
    if state ~= nil then
        for _, tier in ipairs(state.bangable) do
            for v, _ in pairs(tier) do
                params:lookup_param(v):bang()
                tier[v] = nil
            end
            -- second round to pick up things we missed the first
            for v, _ in pairs(tier) do
                params:lookup_param(v):bang()
                tier[v] = nil
            end
            if next(tier) ~= nil then
                print("Missing modulation; too much recursion")
            end
        end
        state.bangable = {{}, {}, {}, {}}
        state.bang_deferred = nil
    end
end

local defer_bang = function(param, tier)
    if tier == nil then tier = 3 end
    if state.bang_deferred == nil then
        clock.run(function()
            clock.sleep(0)
            bang_all()
        end)
    end
    state.bang_deferred = true
    state.bangable[tier][param] = true
end

state.defer_bang = defer_bang

local make_string_option_backup = function(id, options)
    local str_id = (id .. "_str")
    params:add_text(str_id)
    params:set_action(str_id, function(s)
        local k = tab.key(options, s)
        if k ~= nil then
            params:set(id, k, true)
        end
        params:lookup_param(id):bang()
    end)
    params:hide(str_id)
    defer_bang(str_id)
    return str_id
end

local make_seq = function(i, target_ids)
    params:add_group("sequence "..i, 9 + 16)
    params:add_number(n(i, "pos"), "position", 1, 16, 1, nil, true)
    params:add_binary(n(i, "seq_active"), "active", "toggle", 1)
    params:add_number(n(i, "seq_length"), "length", 1, 16, 4)
    params:add_control(n(i, "shred"), "shred", controlspec.new(0, 1, "lin", 0, 0))
    params:add_control(n(i, "zero"), "zero", controlspec.new(0, 1, "lin", 0, 0))
    params:add_trigger(n(i, "advance"), "advance")
    params:lookup_param(n(i, "advance")).priority = 1
    params:add_trigger(n(i, "reset"), "reset")
    params:lookup_param(n(i, "reset")).priority = 2
    params:add_control(n(i, "seq_depth"), "depth", controlspec.new(-1, 1, "lin", 0, 0))
    params:add_option(n(i, "seq_target"), "target", target_ids, 1)
    local str_backup = make_string_option_backup(n(i, "seq_target"), target_ids)
    defer_bang(n(i, "seq_length"))
    local target = nil
    local bang = function(p)
        -- print("bang", target)
        if target == nil then return end
        if params:get(n(i, "seq_active")) > 0 then
            local val = params:get(n(i, "seq_depth")) * params:get(n(i, "val_"..params:get(n(i, "pos"))))
            -- print("setting mod for ", target.id, val)
            target.modulation["seq_"..i] = val
        else
            -- print("setting nil for ", target.id)
            target.modulation["seq_"..i] = nil
        end
        defer_bang(target.id)
    end
    params:set_action(n(i, "advance"), function() 
        local pos = params:get_raw(n(i, "pos")) -- raw value
        if math.random() < params:get(n(i, "shred")) then
            -- randomize the old _modulated_ position
            params:set(n(i, "val_"..params:get(n(i, "pos"))), math.random())
        end
        if math.random() < params:get(n(i, "zero")) then
            -- zero the old _modulated_ position
            params:set(n(i, "val_"..params:get(n(i, "pos"))), 0)
        end
        -- set the new _raw_ position
        params:set(n(i, "pos"), util.wrap(pos + 1, 1, params:get(n(i, "seq_length"))))
        bang()
    end)
    params:set_action(n(i, "reset"), function()
        params:set(n(i, "pos"), 1)
        bang()
    end)
    params:set_action(n(i, "seq_target"), function(t)
        local str_id = target_ids[params:get(n(i, "seq_target"))]
        if target ~= nil and target.modulation ~= nil then
            print("removing modulation for ", target.id)
            target.modulation["seq_"..i] = nil
            defer_bang(target.id)
        end
        if params:get(n(i, "seq_target")) == 1 then
            target = nil
            params:set(str_backup, "", true)
        else
            params:set(str_backup, str_id, true)
            target = params:lookup_param(str_id)
            if target.modulation == nil then
                target.modulation = {}
            end
        end
        bang()
    end)

    for j=1,16,1 do
        params:add_control(n(i, "val_"..j), "value "..j, controlspec.new(0, 1, "lin", 0, 0))
    end
    params:set_action(n(i, "pos"), bang)
    params:set_action(n(i, "seq_active"), bang)
    params:set_action(n(i, "seq_length"), function(l)
        for j=1,16,1 do
            if j <= l then
                params:show(n(i, "val_"..j))
            else
                params:hide(n(i, "val_"..j))
            end
        end
        params:set(n(i, "pos"), util.wrap(params:get(n(i, "pos")), 1, params:get(n(i, "seq_length"))))
    end)
end

local make_mult = function(i, target_ids)
    params:add_group("mult "..i, 13)
    params:add_control(n(i, "value"), "value", controlspec.new(-1, 1, "lin", 0, 0))
    params:add_binary(n(i, "mult_active"), "active", "toggle", 1)
    local targets = {}
    local bang = function()
        for j=1,4,1 do
            if targets[j] ~= nil then
                if params:get(n(i, "mult_active")) > 0 then
                    targets[j].modulation["mult_"..i] = params:get(n(i, "mult_depth_"..j))*params:get(n(i, "value"))
                else
                    targets[j].modulation["mult_"..i] = nil
                end
                defer_bang(targets[j].id, targets[j].priority)
            end
        end
    end
    params:set_action(n(i, "value"), bang)
    defer_bang(n(i, "value"))
    params:set_action(n(i, "mult_active"), bang)
    for j=1,4,1 do
        params:add_control(n(i, "mult_depth_"..j), "depth "..j, controlspec.new(-1, 1, "lin", 0, 0))
        params:add_option(n(i, "mult_target_"..j), "target "..j, target_ids, 1)
        local str_backup = make_string_option_backup(n(i, "mult_target_"..j), target_ids)

        params:set_action(n(i, "mult_target_"..j), function(t)
            if targets[j] ~= nil and targets[j].modulation ~= nil then
                targets[j].modulation["mult_"..i] = nil
                defer_bang(targets[j].id, targets[j].priority)
            end
            if params:get(n(i, "mult_target_"..j)) == 1 then
                targets[j] = nil
                params:set(str_backup, "", true)
            else
                targets[j] = params:lookup_param(target_ids[params:get(n(i, "mult_target_"..j))])
                params:set(str_backup, targets[j].id, true)
            end
        end)
    end
end

local make_lfo = function(i, targets)
    params:add_group("lfo "..i, 8)
    params:add_binary(n(i, "clocked"), "clocked", "toggle", 0)
    defer_bang(n(i, "clocked"))
    params:add_option(n(i, "clocked_period"), "beats", DIVISION_OPTS, 7)
    params:add_control(n(i, "unclocked_period"), "seconds", controlspec.new(0.1, 300, "exp", 0, 1))
    params:set_action(n(i, "clocked"), function (c)
        if params:get(n(i, "clocked")) > 0 then
            params:show(n(i, "clocked_period"))
            params:hide(n(i, "unclocked_period"))
        else
            params:hide(n(i, "clocked_period"))
            params:show(n(i, "unclocked_period")) 
        end
        _menu.rebuild_params()
    end)
    params:add_binary(n(i, "lfo_bipolar"), "bipolar", "toggle", 0)
    params:add_option(n(i, "shape"), "shape", {"sine", "tri/ramp", "pulse", "random"}, 1)
    defer_bang(n(i, "shape"))
    params:set_action(n(i, "shape"), function (s)
        if s == 2 or s == 3 then
            params:show(n(i, "width"))
        else
            params:hide(n(i, "width"))
        end
        _menu.rebuild_params()
    end)
    params:add_control(n(i, "width"), "width", controlspec.new(0, 1, "lin", 0, 0.5))
    params:add_control(n(i, "depth"), "depth", controlspec.new(-1, 1, "lin", 0, 0))
    params:add_option(n(i, "lfo_target"), "target", targets, 1)
    local str_backup = make_string_option_backup(n(i, "lfo_target"), targets)

    local target = nil
    params:set_action(n(i, "lfo_target"), function(t)
        if target ~= nil and target.modulation ~= nil then
            print("removing modulation for ", target.id)
            target.modulation["lfo_"..i] = nil
            defer_bang(target.id, target.priority)
        end
        if params:get(n(i, "lfo_target")) == 1 then
            target = nil
            params:set(str_backup, "", true)
        else
            target = params:lookup_param(targets[params:get(n(i, "lfo_target"))])
            params:set(str_backup, target.id, true)
        end
    end)
    local last_phase = 0
    local rand_value = 0
    local tick = function()
        if target == nil then
            return
        end
        local t = clock.get_beats()
        local phase
        if params:get(n(i, "clocked")) > 0 then
            phase = t / DIVISIONS[params:get(n(i, "clocked_period"))]
        else
            phase = t * clock.get_beat_sec() / params:get(n(i, "unclocked_period"))
        end
        phase = phase % 1
        local shape = params:get(n(i, "shape"))
        local width = params:get(n(i, "width"))
        local value
        if shape == 1 then
            value = (math.sin(2*math.pi*phase) + 1)/2
        elseif shape == 2 then
            if phase < width then
                value = phase/width
            else
                value = 1 - (phase - width)/(1-width)
            end
        elseif shape == 3 then
            if phase < width then
                value = 1
            else
                value = 0
            end
        elseif shape == 4 then
            if phase < last_phase then
                rand_value = math.random()
            end
            value = rand_value
        end
        last_phase = phase
        if target.modulation == nil then target.modulation = {} end
        target.modulation["lfo_"..i] = params:get(n(i, "depth")) * (value - 0.5*params:get(n(i, "lfo_bipolar")))
        defer_bang(target.id, target.priority)
    end
    state.lfos[i] = state.lattice:new_pattern{
        enabled = true,
        division = 1/96,
        action = tick,
    }
end

local make_rhythm = function(i, targets)
    params:add_group("rhythm " .. i, 6 + #targets)
    params:add_binary(n(i, "rhythm_active"), "active", "toggle", 1)
    params:add_option(n(i, "div"), "division", DIVISION_OPTS, 7)
    params:set_action(n(i, "div"), function(d)
        state.rhythms[i]:set_division(DIVISIONS[d])
        -- This arcane machination is required to preserve appropriate swing and beats when changing divisions.
        local tick_length = state.rhythms[i].division * state.lattice.ppqn * state.lattice.meter
        local two_phase = (state.lattice.transport % (2*tick_length))/tick_length
        state.rhythms[i].phase = state.lattice.transport % tick_length
        state.rhythms[i].downbeat = (two_phase < 1)
    end)
    defer_bang(n(i, "div"))
    params:add_control(n(i, "swing"), "swing", controlspec.new(50, 90, "lin", 0, 50))
    params:set_action(n(i, "swing"), function(d)
        state.rhythms[i]:set_swing(d)
    end)
    defer_bang(n(i, "swing"))
    params:add_number(n(i, "rhythm_length"), "length", 1, 24, 8)
    params:add_control(n(i, "fill"), "fill", controlspec.new(0, 1, "lin", 0, 1))
    params:add_control(n(i, "offset"), "offset", controlspec.new(0, 1, "lin", 0, 0))
    defer_bang(n(i, "rhythm_length"))
    state.trigs[i] = {}
    local gen = function ()
        local l = params:get(n(i, "rhythm_length"))
        local k = util.round(params:get(n(i, "fill"))*l, 1)
        local w = util.round(params:get(n(i, "offset"))*l, 1)
        state.trigs[i] = er.gen(k, l, w)
    end
    params:set_action(n(i, "rhythm_length"), gen)
    params:set_action(n(i, "fill"), gen)
    params:set_action(n(i, "offset"), gen)
    gen()
    for _, v in ipairs(targets) do
        params:add_binary(n(i, "to_" .. v), "to ".. v, "toggle", 0)
    end
    local t = 1
    local tick = function ()
        if params:get(n(i, "rhythm_active")) == 0 then
            t = util.wrap(t + 1, 1, params:get(n(i, "rhythm_length")))
            return
        end
        for _, v in ipairs(targets) do
            if params:get(n(i, "to_"..v)) > 0 then
                local p = params:lookup_param(v)
                if p.t == params.tBINARY then
                    if state.trigs[i][t] then p:set(1) else p:set(0) end
                elseif p.t == params.tTRIGGER then
                    if state.trigs[i][t] then 
                        --params:lookup_param(p.id):bang()
                        defer_bang(p.id)
                    end
                end
            end
        end
        t = util.wrap(t + 1, 1, params:get(n(i, "rhythm_length")))
    end    
    state.rhythms[i] = state.lattice:new_pattern{
        enabled = true,
        division = DIVISIONS[params:get(n(i, "div"))],
        swing = params:get(n(i, "swing")),
        action = tick,
    }
end

local get_binaries = function() 
    ret = {table.unpack(state.registered_binaries)}

    for k,v in pairs(params.params) do
        if (v.t == params.tBINARY or v.t == params.tTRIGGER) and v.id ~= nil then
            if v.id:find("tk_%d+_to_") == nil and not tab.contains(state.registered_binaries, v.id) then
                table.insert(ret, v.id)
            end
        end
    end
    return ret
end

local get_numericals = function()
    ret = {"none"}
    for _, v in ipairs(state.registered_numbers) do
        table.insert(ret, v)
    end
    for k,v in pairs(params.params) do
        if (v.t == params.tCONTROL or v.t == params.tNUMBER or v.t == params.tTAPER) and v.id ~= nil then
            if not tab.contains(state.registered_numbers, v.id) then
                if v.id == "output_level" or v.id == "input_level" or v.id == "monitor_level" or v.id == "engine_level" or v.id == "softcut_level" or v.id == "tape_level" then
                    -- pass
                else
                    table.insert(ret, v.id)
                end
            end
        end
    end
    return ret
end

local pre_init = function()
    print("pre-init")
    local init1 = init
    state.lattice = lattice:new()
    state.rhythms = {}
    state.lfos = {}
    state.bangable = {{}, {}, {}, {}}
    state.trigs = {}
    -- cleaning up the registered numbers and booleans are handled in cleanup
    
    for i=1,N_RHYTHMS,1 do
        table.insert(state.registered_binaries, n(i, "rhythm_active"))
        table.insert(state.registered_numbers, n(i, "fill"))
        table.insert(state.registered_numbers, n(i, "offset"))
    end
    for i=1,N_SEQS,1 do
        table.insert(state.registered_binaries, n(i, "seq_active"))
        table.insert(state.registered_binaries, n(i, "advance"))
        table.insert(state.registered_binaries, n(i, "reset"))
        table.insert(state.registered_numbers, n(i, "shred"))
        table.insert(state.registered_numbers, n(i, "zero"))
    end
    for i=1,N_LFOS,1 do
        table.insert(state.registered_binaries, n(i, "lfo_active"))
    end
    init = function()
        print("about to init")
        init1()
        print("post init")
        local binaries = get_binaries()
        local numbers = get_numericals()
        for i=1,N_RHYTHMS,1 do
            make_rhythm(i, binaries)
        end
        for i=1,N_LFOS,1 do
            make_lfo(i, numbers)
        end
        for i=1,N_MULTS,1 do
            make_mult(i, numbers)
        end
        for i=1,N_SEQS,1 do
            make_seq(i, numbers)
        end
        -- after adding our params, we want to re-load default/existing values
        -- but, we don't want to re-bang script params, 
        -- or bang our params which have conflicting side-effects
        params:read(nil, true)
        bang_all()
        print("Starting")
        state.lattice:start()
    end
end


local post_cleanup = function()
    print("post cleanup")
    state.lattice:destroy()
    state.registered_numbers = {}
    state.registered_binaries = {}
end
mod.hook.register("system_post_startup", "toolkit post startup", monkeypatch)
mod.hook.register("script_pre_init", "toolkit pre init", pre_init)
mod.hook.register("script_post_cleanup", "toolkit post clean", post_cleanup)

return state
