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

function number:get()
    if self.modulation == nil then
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

function taper:get()
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

function control:get()
  return self:map_value(self:get_modulated_raw())
end

local state

local n = function(i, s)
    return "tk_" .. i .. "_" ..s
end

local bang_all = function()
    if state ~= nil then
        for v, _ in pairs(state.bangable) do
            params:lookup_param(v):bang()
        end
        state.bangable = {}
    end
end

local defer_bang = function(param)
    if next(state.bangable) == nil then
        clock.run(function()
            clock.sleep(0)
            bang_all()
        end)
    end
    state.bangable[param] = true
end

local make_lfo = function(i, targets)
    params:add_group("lfo "..i, 8)
    params:add_binary(n(i, "clocked"), "clocked", "toggle", 0)
    state.bangable[n(i, "clocked")] = true
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
    params:add_control(n(i, "depth"), "depth", controlspec.new(0, 1, "lin", 0, 0))
    params:add_binary(n(i, "lfo_bipolar"), "bipolar", "toggle", 0)
    params:add_option(n(i, "shape"), "shape", {"sine", "tri/ramp", "pulse", "random"}, 1)
    state.bangable[n(i, "shape")] = true
    params:set_action(n(i, "shape"), function (s)
        if s == 2 or s == 3 then
            params:show(n(i, "width"))
        else
            params:hide(n(i, "width"))
        end
        _menu.rebuild_params()
    end)
    params:add_control(n(i, "width"), "width", controlspec.new(0, 1, "lin", 0, 0.5))
    params:add_option(n(i, "lfo_target"), "target", targets, 1)
    state.bangable[n(i, "lfo_target")] = true
    local target = nil
    params:set_action(n(i, "lfo_target"), function(t)
        if target ~= nil and target.modulation ~= nil then
            print("removing modulation for ", target.id)
            target.modulation["lfo_"..i] = nil
            defer_bang(target.id)
        end
        if params:get(n(i, "lfo_target")) == 1 then
            target = nil
        else
            target = params:lookup_param(targets[params:get(n(i, "lfo_target"))])
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
        defer_bang(target.id)
    end
    state.lfos[i] = state.lattice:new_pattern{
        enabled = true,
        division = 1/96,
        action = tick,
    }
end

local make_rhythm = function(i, targets)
    params:add_group("rhythm " .. i, 6 + #targets)
    params:add_binary(n(i, "active"), "active", "toggle", 1)
    params:add_option(n(i, "div"), "division", DIVISION_OPTS, 7)
    params:set_action(n(i, "div"), function(d)
        state.rhythms[i]:set_division(DIVISIONS[d])
    end)
    state.bangable[n(i, "div")] = true
    params:add_control(n(i, "swing"), "swing", controlspec.new(50, 90, "lin", 0, 50))
    params:set_action(n(i, "swing"), function(d)
        state.rhythms[i]:set_swing(d)
    end)
    state.bangable[n(i, "swing")] = true
    params:add_number(n(i, "length"), "length", 1, 24, 8)
    params:add_control(n(i, "fill"), "fill", controlspec.new(0, 1, "lin", 0, 1))
    params:add_control(n(i, "offset"), "offset", controlspec.new(0, 1, "lin", 0, 0))
    state.bangable[n(i, "length")] = true
    local trigs = {}
    local gen = function ()
        local l = params:get(n(i, "length"))
        local k = util.round(params:get(n(i, "fill"))*l, 1)
        local w = util.round(params:get(n(i, "offset"))*l, 1)
        trigs = er.gen(k, l, w)
    end
    params:set_action(n(i, "length"), gen)
    params:set_action(n(i, "fill"), gen)
    params:set_action(n(i, "offset"), gen)
    gen()
    for _, v in ipairs(targets) do
        params:add_binary(n(i, "to_" .. v), "to ".. v, "toggle", 0)
    end
    local t = 1
    local tick = function ()
        if params:get(n(i, "active")) == 0 then
            t = util.wrap(t + 1, 1, params:get(n(i, "length")))
            return
        end
        for _, v in ipairs(targets) do
            if params:get(n(i, "to_"..v)) > 0 then
                local p = params:lookup_param(v)
                if p.t == params.tBINARY then
                    if trigs[t] then p:set(1) else p:set(0) end
                elseif p.t == params.tTRIGGER then
                    if trigs[t] then 
                        if p.defer ~= nil then
                            clock.run(function() p:bang() end)
                        else
                            p:bang() 
                        end
                    end
                end
            end
        end
        t = util.wrap(t + 1, 1, params:get(n(i, "length")))
    end    
    state.rhythms[i] = state.lattice:new_pattern{
        enabled = true,
        division = DIVISIONS[params:get(n(i, "div"))],
        swing = params:get(n(i, "swing")),
        action = tick,
    }
end

local get_binaries = function() 
    ret = {}
    for i=1,N_RHYTHMS,1 do
        table.insert(ret, n(i, "active"))
    end
    for k,v in pairs(params.params) do
        if (v.t == params.tBINARY or v.t == params.tTRIGGER) and v.id ~= nil then
            if v.id:find("tk_%d+_to_") == nil then
                table.insert(ret, v.id)
            end
        end
    end
    return ret
end

local get_numericals = function()
    ret = {"none"}
    for k,v in pairs(params.params) do
        if (v.t == params.tCONTROL or v.t == params.tNUMBER or v.t == params.tTAPER) and v.id ~= nil then
            if v.id == "output_level" or v.id == "input_level" or v.id == "monitor_level" or v.id == "engine_level" or v.id == "softcut_level" or v.id == "tape_level" then
                -- pass
            else
                table.insert(ret, v.id)
            end
        end
    end
    return ret
end

local pre_init = function()
    local init1 = init
    state = {
        lattice = lattice:new(),
        rhythms = {},
        lfos = {},
        bangable = {},
    }   
    print("pre init hook")
    init = function()
        init1()
        local binaries = get_binaries()
        local numbers = get_numericals()
        for i=1,N_RHYTHMS,1 do
            make_rhythm(i, binaries)
        end
        for i=1,N_LFOS,1 do
            make_lfo(i, numbers)
        end
        -- after adding our params, we want to re-load default/existing values
        -- but, we don't want to re-bang script params, 
        -- or bang our params which have conflicting side-effects
        params:read(nil, true)
        bang_all()
        state.lattice:start()
    end
end


local post_cleanup = function()
    if state ~= nil then
        state.lattice:destroy()
    end
    state = nil
end
print("registering pre init hook")
mod.hook.register("script_pre_init", "test pre init", pre_init)
mod.hook.register("script_post_cleanup", "test post clean", post_cleanup)

