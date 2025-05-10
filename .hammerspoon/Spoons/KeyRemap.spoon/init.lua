local obj = {}
obj.__index = obj

-- Function to press a key
local function pressFn(mods, key)
    if key == nil then
        key = mods
        mods = {}
    end

    return function() hs.eventtap.keyStroke(mods, key, 1000) end
end

-- Function to remap a key
local function remap(mods, key, pressFn)
    hs.hotkey.bind(mods, key, pressFn, nil, pressFn)
end

-- Function to start the Spoon (bind all key remaps)
function obj:start()
    -- remap({'alt'}, 'e', pressFn('escape'))
    remap({'alt'}, 'q', pressFn('escape'))

    remap({'alt'}, 'j', pressFn('left'))
    remap({'alt'}, 'k', pressFn('down'))
    remap({'alt'}, 'i', pressFn('up'))
    remap({'alt'}, 'l', pressFn('right'))
    remap({'alt', 'shift'}, 'j', pressFn({'shift'}, 'left'))
    remap({'alt', 'shift'}, 'k', pressFn({'shift'}, 'down'))
    remap({'alt', 'shift'}, 'i', pressFn({'shift'}, 'up'))
    remap({'alt', 'shift'}, 'l', pressFn({'shift'}, 'right'))
    
    remap({'alt', 'cmd'}, 'j', pressFn({'alt'}, 'left'))
    remap({'alt', 'cmd'}, 'l', pressFn({'alt'}, 'right'))
    remap({'alt', 'cmd', 'shift'}, 'j', pressFn({'alt shift'}, 'left'))
    remap({'alt', 'cmd', 'shift'}, 'l', pressFn({'alt shift'}, 'right'))
    
    remap({'alt'}, 'o', pressFn({'ctrl'}, 'e'))
    remap({'alt'}, 'u', pressFn({'ctrl'}, 'a'))
    remap({'alt', 'shift'}, 'o', pressFn({'ctrl shift'}, 'e'))
    remap({'alt', 'shift'}, 'u', pressFn({'ctrl shift'}, 'a'))

    remap({'alt'}, 'y', pressFn('pageup'))
    remap({'alt'}, 'n', pressFn('pagedown'))
    remap({'alt', 'shift'}, 'y', pressFn({'shift'}, 'pageup'))
    remap({'alt', 'shift'}, 'n', pressFn({'shift'}, 'pagedown'))
    
    remap({'alt'}, 'h', pressFn('delete'))
    remap({'alt'}, ';', pressFn('forwarddelete'))

    -- remap({'alt', 'cmd'}, ';', pressFn({'cmd'}, 'delete'))
    remap({'alt'}, 'space', pressFn('return'))

    hs.alert.show("Key Remap Spoon loaded")
end

return obj