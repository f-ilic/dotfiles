VERSION = "1.0.0"

local micro = import("micro")
local buffer = import("micro/buffer")
local config = import("micro/config")
local util = import("micro/util")

-- Patterns that define selection boundaries
local BRACKET_PAIRS = {
    {open = "(", close = ")"},
    {open = "[", close = "]"},
    {open = "{", close = "}"},
    {open = "<", close = ">"}
}

local QUOTE_CHARS = {'"', "'", "`"}

-- Get word boundaries at cursor position
local function getWordBounds(buf, loc)
    local line = util.String(buf:Line(loc.Y))
    if line == "" then return nil, nil end
    
    local start = loc.X
    local endPos = loc.X
    
    -- If we're on a non-word character, return nil
    if not line:sub(start + 1, start + 1):match("[%w_]") then
        return nil, nil
    end
    
    -- Expand backwards
    while start > 0 and line:sub(start, start):match("[%w_]") do
        start = start - 1
    end
    
    -- Expand forwards
    while endPos < #line and line:sub(endPos + 2, endPos + 2):match("[%w_]") do
        endPos = endPos + 1
    end
    
    return start, endPos + 1
end

-- Find all enclosing bracket/quote pairs and return them sorted by size
local function findAllEnclosingPairs(buf, selStart, selEnd)
    local pairs = {}
    
    -- For multi-line brackets, we need to search the entire buffer (or at least nearby lines)
    local numLines = buf:LinesNum()
    
    -- Check for brackets across multiple lines
    for _, pair in ipairs(BRACKET_PAIRS) do
        -- Search backwards from selection start to find opening brackets
        for startY = selStart.Y, 0, -1 do
            local line = util.String(buf:Line(startY))
            local searchEnd = startY == selStart.Y and selStart.X - 1 or #line - 1
            
            for startX = searchEnd, 0, -1 do
                if line:sub(startX + 1, startX + 1) == pair.open then
                    -- Found an opening bracket, now find its matching closing bracket
                    local level = 0
                    local found = false
                    
                    -- Search forward from this position
                    for endY = startY, numLines - 1 do
                        local endLine = util.String(buf:Line(endY))
                        local searchStart = (endY == startY) and startX + 1 or 0
                        
                        for endX = searchStart, #endLine - 1 do
                            local char = endLine:sub(endX + 1, endX + 1)
                            if char == pair.open then
                                level = level + 1
                            elseif char == pair.close then
                                if level == 0 then
                                    -- Found the matching closing bracket
                                    -- Check if this pair encloses our selection
                                    local enclosesStart = (startY < selStart.Y) or (startY == selStart.Y and startX < selStart.X)
                                    local enclosesEnd = (endY > selEnd.Y) or (endY == selEnd.Y and endX >= selEnd.X)
                                    
                                    if enclosesStart and enclosesEnd then
                                        -- Calculate size (rough estimate for sorting)
                                        local size = (endY - startY) * 1000 + (endX - startX)
                                        table.insert(pairs, {
                                            startY = startY,
                                            startX = startX,
                                            endY = endY,
                                            endX = endX + 1,
                                            size = size
                                        })
                                    end
                                    found = true
                                    break
                                else
                                    level = level - 1
                                end
                            end
                        end
                        if found then break end
                    end
                end
            end
        end
    end
    
    -- For quotes, only check on the same line
    if selStart.Y == selEnd.Y then
        local line = util.String(buf:Line(selStart.Y))
        for _, quote in ipairs(QUOTE_CHARS) do
            local inQuote = false
            local quoteStart = nil
            
            for x = 0, #line - 1 do
                if line:sub(x + 1, x + 1) == quote then
                    if not inQuote then
                        quoteStart = x
                        inQuote = true
                    else
                        -- Found closing quote
                        if quoteStart < selStart.X and x >= selEnd.X then
                            table.insert(pairs, {
                                startY = selStart.Y,
                                startX = quoteStart,
                                endY = selStart.Y,
                                endX = x + 1,
                                size = x - quoteStart
                            })
                        end
                        inQuote = false
                    end
                end
            end
        end
    end
    
    -- Sort by size (smallest first)
    table.sort(pairs, function(a, b) return a.size < b.size end)
    
    return pairs
end

-- Expand selection intelligently
function expandSelection(bp)
    local cursor = bp.Buf:GetActiveCursor()
    local hasSelection = cursor:HasSelection()
    
    if not hasSelection then
        -- First expansion: select word
        local start, endPos = getWordBounds(bp.Buf, cursor.Loc)
        if start and endPos then
            cursor:SetSelectionStart(buffer.Loc(start, cursor.Loc.Y))
            cursor:SetSelectionEnd(buffer.Loc(endPos, cursor.Loc.Y))
            cursor.Loc = buffer.Loc(endPos, cursor.Loc.Y)
            return true
        end
        -- If no word, just select to line
        cursor:SelectLine()
        return true
    else
        -- Get current selection bounds
        local selStart = cursor.OrigSelection[1]
        local selEnd = cursor.CurSelection[1]
        
        -- Make sure selStart is before selEnd
        if selStart.Y > selEnd.Y or (selStart.Y == selEnd.Y and selStart.X > selEnd.X) then
            selStart, selEnd = selEnd, selStart
        end
        
        -- Find all enclosing pairs
        local enclosingPairs = findAllEnclosingPairs(bp.Buf, selStart, selEnd)
        
        -- Try to expand to the smallest enclosing pair that's larger than current selection
        if #enclosingPairs > 0 then
            local nextPair = enclosingPairs[1]
            cursor:SetSelectionStart(buffer.Loc(nextPair.startX, nextPair.startY))
            cursor:SetSelectionEnd(buffer.Loc(nextPair.endX, nextPair.endY))
            cursor.Loc = buffer.Loc(nextPair.endX, nextPair.endY)
            return true
        end
        
        -- If no enclosing pairs found, expand to line
        if selStart.Y == selEnd.Y then
            local lineLen = util.String(bp.Buf:Line(selStart.Y))
            if selStart.X > 0 or selEnd.X < #lineLen then
                cursor:SelectLine()
                return true
            end
        end
    end
    
    return false
end

-- Shrink selection
function shrinkSelection(bp)
    local cursor = bp.Buf:GetActiveCursor()
    
    if not cursor:HasSelection() then
        return false
    end
    
    -- Get current selection bounds
    local selStart = cursor.OrigSelection[1]
    local selEnd = cursor.CurSelection[1]
    
    -- Make sure selStart is before selEnd
    if selStart.Y > selEnd.Y or (selStart.Y == selEnd.Y and selStart.X > selEnd.X) then
        selStart, selEnd = selEnd, selStart
    end
    
    -- Find all enclosing pairs
    local enclosingPairs = findAllEnclosingPairs(bp.Buf, selStart, selEnd)
    
    -- Filter to only pairs that are SMALLER than current selection
    local smallerPairs = {}
    local currentSize = (selEnd.Y - selStart.Y) * 1000 + (selEnd.X - selStart.X)
    for _, pair in ipairs(enclosingPairs) do
        if pair.size < currentSize then
            table.insert(smallerPairs, pair)
        end
    end
    
    -- If we have smaller pairs, pick the largest one
    if #smallerPairs > 0 then
        local prevPair = smallerPairs[#smallerPairs]
        cursor:SetSelectionStart(buffer.Loc(prevPair.startX, prevPair.startY))
        cursor:SetSelectionEnd(buffer.Loc(prevPair.endX, prevPair.endY))
        cursor.Loc = buffer.Loc(prevPair.startX, prevPair.startY)
        return true
    end
    
    -- Try to shrink to word
    local wordStart, wordEnd = getWordBounds(bp.Buf, cursor.Loc)
    if wordStart and wordEnd then
        local wordSize = wordEnd - wordStart
        if wordSize < currentSize then
            cursor:SetSelectionStart(buffer.Loc(wordStart, cursor.Loc.Y))
            cursor:SetSelectionEnd(buffer.Loc(wordEnd, cursor.Loc.Y))
            cursor.Loc = buffer.Loc(wordStart, cursor.Loc.Y)
            return true
        end
    end
    
    -- Otherwise just deselect
    cursor:ResetSelection()
    return false
end

function init()
    config.MakeCommand("expandselection", expandSelection, config.NoComplete)
    config.MakeCommand("shrinkselection", shrinkSelection, config.NoComplete)
end
