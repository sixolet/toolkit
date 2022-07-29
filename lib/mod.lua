local mod = require 'core/mods'
local lattice = require("lattice")
local er = require("er")
local deque = require('container/deque')

local matrix = require('matrix/lib/matrix')

local DIVISIONS = {1/16, 1/12, 1/8, 1/7, 1/6, 1/5, 1/4, 1/3, 1/2, 3/4, 1, 5/4, 6/4, 7/4, 2, 4, 8, 32, 64, 128}
local DIVISION_OPTS = {
    "1/16", "1/12", "1/8", "1/7", "1/6", "1/5", "1/4", "1/3", "1/2", "3/4", "4/4", "5/4", "6/4", "7/4", "2", "4", "8", "32", "64", "128"}

local N_RHYTHMS = 4
local N_LFOS = 4
local N_MULTS = 4
local N_SEQS = 4

local toolkit = {}


local n = function(i, s)
    return "tk_" .. i .. "_" ..s
end

local make_seq = function(i)
    params:add_group("sequence "..i, 7 + 16)
    params:add_number(n(i, "seq_pos"), "position", 1, 16, 1, nil, true)
    params:add_binary(n(i, "seq_active"), "active", "toggle", 1)
    params:add_number(n(i, "seq_length"), "length", 1, 16, 4)
    params:add_control(n(i, "seq_shred"), "shred", controlspec.new(0, 1, "lin", 0, 0))
    params:add_control(n(i, "seq_zero"), "zero", controlspec.new(0, 1, "lin", 0, 0))
    params:add_trigger(n(i, "seq_advance"), "advance")
    params:lookup_param(n(i, "seq_advance")).priority = 1
    params:add_trigger(n(i, "seq_reset"), "reset")
    params:lookup_param(n(i, "seq_reset")).priority = 2
    matrix:add_unipolar("seq_"..i, "seq "..i)
    local mod_value = function()
        if params:get(n(i, "seq_active")) > 0 then
            return params:get(n(i, "val_"..params:get(n(i, "seq_pos"))))
        else
            return nil
        end
    end
    matrix:defer_bang(n(i, "seq_length"))
    params:set_action(n(i, "seq_advance"), function() 
        local pos = params:get_unmodded(n(i, "seq_pos")) -- raw value
        if math.random() < params:get(n(i, "seq_shred")) then
            -- randomize the old _modulated_ position
            params:set(n(i, "val_"..params:get(n(i, "seq_pos"))), math.random())
        end
        if math.random() < params:get(n(i, "seq_zero")) then
            -- zero the old _modulated_ position
            params:set(n(i, "val_"..params:get(n(i, "seq_pos"))), 0)
        end
        -- set the new _raw_ position
        params:set(n(i, "seq_pos"), util.wrap(pos + 1, 1, params:get(n(i, "seq_length"))))
        matrix:set("seq_"..i, mod_value())
    end)
    params:set_action(n(i, "seq_reset"), function()
        params:set(n(i, "seq_pos"), 1)
        matrix:set("seq_"..i, mod_value())
    end)

    for j=1,16,1 do
        params:add_control(n(i, "val_"..j), "value "..j, controlspec.new(0, 1, "lin", 0, 0))
    end
    params:set_action(n(i, "seq_pos"), function()
        matrix:set("seq_"..i, mod_value())
    end)
    params:set_action(n(i, "seq_active"), function()
        matrix:set("seq_"..i, mod_value())
    end)
    params:set_action(n(i, "seq_length"), function(l)
        for j=1,16,1 do
            if j <= l then
                params:show(n(i, "val_"..j))
            else
                params:hide(n(i, "val_"..j))
            end
        end
        params:set(n(i, "seq_pos"), util.wrap(params:get(n(i, "seq_pos")), 1, params:get(n(i, "seq_length"))))
    end)
end

local make_lfo = function(i)
    params:add_group("lfo "..i, 6)
    params:add_binary(n(i, "clocked"), "clocked", "toggle", 0)
    matrix:defer_bang(n(i, "clocked"))
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
    matrix:defer_bang(n(i, "shape"))
    params:set_action(n(i, "shape"), function (s)
        if s == 2 or s == 3 then
            params:show(n(i, "lfo_width"))
        else
            params:hide(n(i, "lfo_width"))
        end
        _menu.rebuild_params()
    end)
    params:add_control(n(i, "lfo_width"), "width", controlspec.new(0, 1, "lin", 0, 0.5))
    matrix:add_unipolar("lfo_"..i, "lfo "..i)

    local last_phase = 0
    local rand_value = 0
    local tick = function()

        if not matrix:used("lfo_" .. i) then
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
        local width = params:get(n(i, "lfo_width"))
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
        matrix:set("lfo_"..i, (value - 0.5*params:get(n(i, "lfo_bipolar"))))
    end
    toolkit.lfos[i] = toolkit.lattice:new_pattern{
        enabled = true,
        division = 1/96,
        action = tick,
    }
end

local make_rhythm = function(i)
    params:add_group("rhythm " .. i, 6)
    params:add_binary(n(i, "rhythm_active"), "active", "toggle", 1)
    params:add_option(n(i, "div"), "division", DIVISION_OPTS, 7)
    params:set_action(n(i, "div"), function(d)
        toolkit.rhythms[i]:set_division(DIVISIONS[d])
        -- This arcane machination is required to preserve appropriate swing and beats when changing divisions.
        local tick_length = toolkit.rhythms[i].division * toolkit.lattice.ppqn * toolkit.lattice.meter
        local two_phase = (toolkit.lattice.transport % (2*tick_length))/tick_length
        toolkit.rhythms[i].phase = toolkit.lattice.transport % tick_length
        toolkit.rhythms[i].downbeat = (two_phase < 1)
    end)
    matrix:defer_bang(n(i, "div"))
    params:add_control(n(i, "swing"), "swing", controlspec.new(50, 90, "lin", 0, 50))
    params:set_action(n(i, "swing"), function(d)
        toolkit.rhythms[i]:set_swing(d)
    end)
    matrix:defer_bang(n(i, "swing"))
    params:add_number(n(i, "rhythm_length"), "length", 1, 24, 8)
    params:add_control(n(i, "rhythm_fill"), "fill", controlspec.new(0, 1, "lin", 0, 1))
    params:add_control(n(i, "rhythm_offset"), "offset", controlspec.new(0, 1, "lin", 0, 0))
    matrix:defer_bang(n(i, "rhythm_length"))
    toolkit.trigs[i] = {}
    local gen = function ()
        local l = params:get(n(i, "rhythm_length"))
        local k = util.round(params:get(n(i, "rhythm_fill"))*l, 1)
        local w = util.round(params:get(n(i, "rhythm_offset"))*l, 1)
        toolkit.trigs[i] = er.gen(k, l, w)
    end
    params:set_action(n(i, "rhythm_length"), gen)
    params:set_action(n(i, "rhythm_fill"), gen)
    params:set_action(n(i, "rhythm_offset"), gen)
    matrix:add_binary("rhythm_"..i, "rhythm "..i)
    gen()
    local t = 1
    local tick = function ()
        if params:get(n(i, "rhythm_active")) == 0 then
            t = util.wrap(t + 1, 1, params:get(n(i, "rhythm_length")))
            return
        end
        if toolkit.trigs[i][t] then
            matrix:set("rhythm_"..i, 1)
        else
            matrix:set("rhythm_"..i, 0)
        end
        t = util.wrap(t + 1, 1, params:get(n(i, "rhythm_length")))
    end    
    toolkit.rhythms[i] = toolkit.lattice:new_pattern{
        enabled = true,
        division = DIVISIONS[params:get(n(i, "div"))],
        swing = params:get(n(i, "swing")),
        action = tick,
    }
end

local pre_init = function()
    print("pre-init")
    toolkit.lattice = lattice:new()
    toolkit.rhythms = {}
    toolkit.lfos = {}
    toolkit.trigs = {}
    matrix:add_post_init_hook(function() 
        for i=1,N_RHYTHMS,1 do
            make_rhythm(i)
        end
        for i=1,N_LFOS,1 do
            make_lfo(i)
        end
        for i=1,N_SEQS,1 do
            make_seq(i)
        end
        toolkit.lattice:start()
    end)
end


local post_cleanup = function()
    if toolkit.lattice ~= nil then
        toolkit.lattice:destroy()
        toolkit.lattice = nil
    end
end
mod.hook.register("script_pre_init", "toolkit pre init", pre_init)
mod.hook.register("script_post_cleanup", "toolkit post clean", post_cleanup)

return toolkit
