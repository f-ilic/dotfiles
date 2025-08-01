local obj = {}
obj.__index = obj

-- Configuration
-- (removed doubleTapSpeed as we're not using double-tap anymore)

-- Modal state variables
obj.modalActive = false
obj.modalHotkeys = {}
obj.disabledKeys = {}

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
    return hs.hotkey.bind(mods, key, pressFn, nil, pressFn)
end

-- Toggle modal mode
function obj:toggleModal()
    self.modalActive = not self.modalActive
    self:updateModalState()
end

-- Set modal mode to unlocked (normal mode)
function obj:setUnlocked()
    self.modalActive = false
    self:updateModalState()
end

-- Set modal mode to locked (modal mode)
function obj:setLocked()
    self.modalActive = true
    self:updateModalState()
end

-- Update the modal state (show indicator and enable/disable hotkeys)
function obj:updateModalState()
    -- Show mode indicator with colors
    if self.modalActive then
        -- Green for modal mode (locked)
        hs.alert.show("🔒", {
            strokeColor = {white = 0},
            fillColor = {red = 0, green = 0, blue = 0, alpha = 1},
            textColor = {white = 1},
            textSize = 30,
            radius = 8,
            atScreenEdge = 0
        }, 1.5)
    else
        -- Red for normal mode (unlocked)
        hs.alert.show("🔓", {
            strokeColor = {white = 0},
            fillColor = {red = 0, green = 0, blue = 0, alpha = 1},
            textColor = {white = 1},
            textSize = 30,
            radius = 8,
            atScreenEdge = 0
        }, 1.5)
    end
    
    -- Toggle modal hotkeys
    for _, hotkey in ipairs(self.modalHotkeys) do
        if self.modalActive then
            hotkey:enable()
        else
            hotkey:disable()
        end
    end
    
    -- Toggle disabled keys (prevent accidental typing in modal mode)
    for _, hotkey in ipairs(self.disabledKeys) do
        if self.modalActive then
            hotkey:enable()
        else
            hotkey:disable()
        end
    end
end

-- Function to start the Spoon (bind all key remaps)
function obj:start()
    -- Modal control keys
    remap({'alt'}, '1', function() self:setUnlocked() end)  -- Alt+1: Always unlock (normal mode)
    remap({'alt'}, '2', function() self:setLocked() end)    -- Alt+2: Always lock (modal mode)
    remap({'alt'}, '0', function() self:toggleModal() end)  -- Alt+0: Toggle between modes


    -------------- NORMAL MODE --------------
    remap({'alt'}, 'q', pressFn('escape'))  -- Escape

    -- Navigation (arrow keys)
    remap({'alt'}, 'j', pressFn('left'))
    remap({'alt'}, 'k', pressFn('down'))
    remap({'alt'}, 'i', pressFn('up'))
    remap({'alt'}, 'l', pressFn('right'))
    
    -- Navigation with selection (shift + arrow keys)
    remap({'alt', 'shift'}, 'j', pressFn({'shift'}, 'left'))
    remap({'alt', 'shift'}, 'k', pressFn({'shift'}, 'down'))
    remap({'alt', 'shift'}, 'i', pressFn({'shift'}, 'up'))
    remap({'alt', 'shift'}, 'l', pressFn({'shift'}, 'right'))
    
    -- Word navigation (alt + arrow keys)
    remap({'alt', 'cmd'}, 'j', pressFn({'alt'}, 'left'))
    remap({'alt', 'cmd'}, 'l', pressFn({'alt'}, 'right'))
    
    -- Word navigation with selection (alt + shift + arrow keys)
    remap({'alt', 'cmd', 'shift'}, 'j', pressFn({'alt, shift'}, 'left'))
    remap({'alt', 'cmd', 'shift'}, 'l', pressFn({'alt, shift'}, 'right'))
    
    -- Line navigation (home/end)
    remap({'alt'}, 'o', pressFn({'ctrl'}, 'e'))
    remap({'alt'}, 'u', pressFn({'ctrl'}, 'a'))
    
    -- Line navigation with selection (shift + home/end)
    remap({'alt', 'shift'}, 'o', pressFn({'shift'}, 'end'))
    remap({'alt', 'shift'}, 'u', pressFn({'shift'}, 'home'))

    -- Page navigation
    remap({'alt'}, 'n', pressFn('pageup'))
    remap({'alt'}, 'm', pressFn('pagedown'))
    
    -- Page navigation with selection
    remap({'alt', 'shift'}, 'n', pressFn({'shift'}, 'pageup'))
    remap({'alt', 'shift'}, 'm', pressFn({'shift'}, 'pagedown'))
    
    -- Deletion
    remap({'alt'}, 'h', pressFn('delete'))
    remap({'alt'}, ';', pressFn('forwarddelete'))
    
    remap({'alt'}, 'space', pressFn('return'))  -- Enter
    
    -------------- MODAL MODE --------------
    -- Modal hotkeys (without alt, disabled by default)
    table.insert(self.modalHotkeys, remap({}, 'q', pressFn('escape')):disable())  -- Escape
    
    -- Navigation
    table.insert(self.modalHotkeys, remap({}, 'j', pressFn('left')):disable())    -- left
    table.insert(self.modalHotkeys, remap({}, 'k', pressFn('down')):disable())    -- down
    table.insert(self.modalHotkeys, remap({}, 'i', pressFn('up')):disable())      -- up
    table.insert(self.modalHotkeys, remap({}, 'l', pressFn('right')):disable())   -- right
    
    -- Navigation + selection
    table.insert(self.modalHotkeys, remap({'shift'}, 'j', pressFn({'shift'}, 'left')):disable())   -- shift+left
    table.insert(self.modalHotkeys, remap({'shift'}, 'k', pressFn({'shift'}, 'down')):disable())   -- shift+down
    table.insert(self.modalHotkeys, remap({'shift'}, 'i', pressFn({'shift'}, 'up')):disable())     -- shift+up
    table.insert(self.modalHotkeys, remap({'shift'}, 'l', pressFn({'shift'}, 'right')):disable())  -- shift+right
    
    -- Word navigation
    table.insert(self.modalHotkeys, remap({'cmd'}, 'j', pressFn({'alt'}, 'left')):disable())             -- word left
    table.insert(self.modalHotkeys, remap({'cmd'}, 'l', pressFn({'alt'}, 'right')):disable())            -- word right
    table.insert(self.modalHotkeys, remap({'cmd', 'shift'}, 'j', pressFn({'alt, shift'}, 'left')):disable())   -- word+select left
    table.insert(self.modalHotkeys, remap({'cmd', 'shift'}, 'l', pressFn({'alt, shift'}, 'right')):disable())  -- word+select right
    
    -- Line navigation
    table.insert(self.modalHotkeys, remap({}, 'o', pressFn({'ctrl'}, 'e')):disable())              -- end of line
    table.insert(self.modalHotkeys, remap({}, 'u', pressFn({'ctrl'}, 'a')):disable())              -- start of line
    table.insert(self.modalHotkeys, remap({'shift'}, 'o', pressFn({'shift'}, 'end')):disable())    -- select to end
    table.insert(self.modalHotkeys, remap({'shift'}, 'u', pressFn({'shift'}, 'home')):disable())   -- select to start
    
    -- Page navigation
    table.insert(self.modalHotkeys, remap({}, 'n', pressFn('pageup')):disable())                   -- page up
    table.insert(self.modalHotkeys, remap({}, 'm', pressFn('pagedown')):disable())                 -- page down
    table.insert(self.modalHotkeys, remap({'shift'}, 'n', pressFn({'shift'}, 'pageup')):disable()) -- select page up
    table.insert(self.modalHotkeys, remap({'shift'}, 'm', pressFn({'shift'}, 'pagedown')):disable()) -- select page down
    
    -- Deletion & Enter
    table.insert(self.modalHotkeys, remap({}, 'h', pressFn('delete')):disable())          -- backspace
    table.insert(self.modalHotkeys, remap({}, ';', pressFn('forwarddelete')):disable())   -- delete
    table.insert(self.modalHotkeys, remap({}, 'space', pressFn('return')):disable())      -- enter

    -- Disable common typing keys in modal mode to prevent accidents
    local typingKeys = {'a', 'b', 'c', 'd', 'e', 'f', 'g', 'p', 'r', 's', 't', 'v', 'w', 'x', 'y', 'z'}
    for _, key in ipairs(typingKeys) do
        table.insert(self.disabledKeys, hs.hotkey.bind({}, key, function() end, nil, nil):disable())
    end
    
    -- Disable number keys
    for i = 0, 9 do
        table.insert(self.disabledKeys, hs.hotkey.bind({}, tostring(i), function() end, nil, nil):disable())
    end
    
    -- Disable other common keys that might cause issues
    local otherKeys = {',', '.', '/', '\\', '\'', '[', ']', '=', '-', '`'}
    for _, key in ipairs(otherKeys) do
        table.insert(self.disabledKeys, hs.hotkey.bind({}, key, function() end, nil, nil):disable())
    end

    hs.alert.show("Key Remap Spoon loaded\n\nModal controls:\n   Alt+1: Unlock 🔓\n   Alt+2: Lock 🔒\n   Alt+0: Toggle", 5)
end

return obj
