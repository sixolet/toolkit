engine.name = "PolyPerc"

music = require("musicutil")

scale_names = {}
for i = 1, #music.SCALES do
  table.insert(scale_names, music.SCALES[i].name)
end

scale = {}

function init()
    print("init")
    params:add_option("scale", "scale", scale_names, 1)
    params:set_action("scale", function ()
        local s = scale_names[params:get("scale")]
        scale = music.generate_scale(12, s, 8)
    end)
    params:add_control("cutoff", "cutoff", controlspec.FREQ)
    params:set_action("cutoff", function(c) engine.cutoff(c) end)
    params:add_control("release", "release", controlspec.new(0.05, 3, "exp", 0, 0.3))
    params:set_action("release", function(c) engine.release(c) end)
    params:add_control("pw", "pw", controlspec.new(0.05, 0.95, "lin", 0, 0.5))
    params:set_action("pw", function(c) engine.pw(c) end)
    params:add_number("note", "note", 12, 127, 48)
    params:add_trigger("trig", "trig")
    params:lookup_param("trig").priority = 4
    params:set_action("trig", function (t)
        engine.hz(music.note_num_to_freq(music.snap_note_to_array(params:get("note"), scale)))
    end)
    params:add_number("note 2", "note 2", 12, 127, 48)
    params:add_trigger("trig 2", "trig 2")
    params:lookup_param("trig 2").priority = 4
    params:set_action("trig 2", function (t)
        engine.hz(music.note_num_to_freq(music.snap_note_to_array(params:get("note 2"), scale)))
    end)
    params:read()
    params:bang()
end