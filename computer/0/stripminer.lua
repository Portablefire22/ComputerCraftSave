-- BEGIN JSON LIBRARY --
local type = type
local next = next
local error = error
local tonumber = tonumber
local tostring = tostring
local utf8_char = string.char
local table_concat = table.concat
local table_sort = table.sort
local string_char = string.char
local string_byte = string.byte
local string_find = string.find
local string_match = string.match
local string_gsub = string.gsub
local string_sub = string.sub
local string_format = string.format
local setmetatable = setmetatable
local getmetatable = getmetatable
local huge = math.huge
local tiny = -huge
 
local json = {}
json.object = {}
 
function math_type(number)
	if math.floor(number) == number then
		return "integer"
	else
		return "float"
	end
end
-- json.encode --
local statusVisited
local statusBuilder
 
local encode_map = {}
 
local encode_escape_map = {
    [ "\"" ] = "\\\"",
    [ "\\" ] = "\\\\",
    [ "/" ]  = "\\/",
    [ "\b" ] = "\\b",
    [ "\f" ] = "\\f",
    [ "\n" ] = "\\n",
    [ "\r" ] = "\\r",
    [ "\t" ] = "\\t",
}
 
local decode_escape_set = {}
local decode_escape_map = {}
for k, v in next, encode_escape_map do
    decode_escape_map[v] = k
    decode_escape_set[string_byte(v, 2)] = true
end
 
for i = 0, 31 do
    local c = string_char(i)
    if not encode_escape_map[c] then
        encode_escape_map[c] = string_format("\\u%04x", i)
    end
end
 
local function encode(v)
    local res = encode_map[type(v)](v)
    statusBuilder[#statusBuilder+1] = res
end
 
encode_map["nil"] = function ()
    return "null"
end
 
local function encode_string(v)
    return string_gsub(v, '[\0-\31\\"]', encode_escape_map)
end
 
function encode_map.string(v)
    statusBuilder[#statusBuilder+1] = '"'
    statusBuilder[#statusBuilder+1] = encode_string(v)
    return '"'
end
 
local function convertreal(v)
    local g = string_format('%.16g', v)
    if tonumber(g) == v then
        return g
    end
    return string_format('%.17g', v)
end
 
if string_match(tostring(1/2), "%p") == "," then
    local _convertreal = convertreal
    function convertreal(v)
        return string_gsub(_convertreal(v), ',', '.')
    end
end
 
function encode_map.number(v)
    if v ~= v or v <= tiny or v >= huge then
        error("unexpected number value '" .. tostring(v) .. "'")
    end
    return convertreal(v)
end
 
function encode_map.boolean(v)
    if v then
        return "true"
    else
        return "false"
    end
end
 
function encode_map.table(t)
    local first_val = next(t)
    if first_val == nil then
        if getmetatable(t) == json.object then
            return "{}"
        else
            return "[]"
        end
    end
    if statusVisited[t] then
        error("circular reference")
    end
    statusVisited[t] = true
    if type(first_val) == 'string' then
        local key = {}
        for k in next, t do
            if type(k) ~= "string" then
                error("invalid table: mixed or invalid key types")
            end
            key[#key+1] = k
        end
        table_sort(key)
        local k = key[1]
        statusBuilder[#statusBuilder+1] = '{"'
        statusBuilder[#statusBuilder+1] = encode_string(k)
        statusBuilder[#statusBuilder+1] = '":'
        encode(t[k])
        for i = 2, #key do
            local k = key[i]
            statusBuilder[#statusBuilder+1] = ',"'
            statusBuilder[#statusBuilder+1] = encode_string(k)
            statusBuilder[#statusBuilder+1] = '":'
            encode(t[k])
        end
        statusVisited[t] = nil
        return "}"
    else
        local max = 0
        for k in next, t do
            if math_type(k) ~= "integer" or k <= 0 then
                error("invalid table: mixed or invalid key types")
            end
            if max < k then
                max = k
            end
        end
        statusBuilder[#statusBuilder+1] = "["
        encode(t[1])
        for i = 2, max do
            statusBuilder[#statusBuilder+1] = ","
            encode(t[i])
        end
        statusVisited[t] = nil
        return "]"
    end
end
 
local function encode_unexpected(v)
    if v == json.null then
        return "null"
    else
        error("unexpected type '"..type(v).."'")
    end
end
encode_map[ "function" ] = encode_unexpected
encode_map[ "userdata" ] = encode_unexpected
encode_map[ "thread"   ] = encode_unexpected
 
function json.encode(v)
    statusVisited = {}
    statusBuilder = {}
    encode(v)
    return table_concat(statusBuilder)
end
 
json._encode_map = encode_map
json._encode_string = encode_string
 
-- json.decode --
 
local statusBuf
local statusPos
local statusTop
local statusAry = {}
local statusRef = {}
 
local function find_line()
    local line = 1
    local pos = 1
    while true do
        local f, _, nl1, nl2 = string_find(statusBuf, '([\n\r])([\n\r]?)', pos)
        if not f then
            return line, statusPos - pos + 1
        end
        local newpos = f + ((nl1 == nl2 or nl2 == '') and 1 or 2)
        if newpos > statusPos then
            return line, statusPos - pos + 1
        end
        pos = newpos
        line = line + 1
    end
end
 
local function decode_error(msg)
    error(string_format("ERROR: %s at line %d col %d", msg, find_line()))
end
 
local function get_word()
    return string_match(statusBuf, "^[^ \t\r\n%]},]*", statusPos)
end
 
local function next_byte()
    local pos = string_find(statusBuf, "[^ \t\r\n]", statusPos)
    if pos then
        statusPos = pos
        return string_byte(statusBuf, pos)
    end
    return -1
end
 
local function consume_byte(c)
    local _, pos = string_find(statusBuf, c, statusPos)
    if pos then
        statusPos = pos + 1
        return true
    end
end
 
local function expect_byte(c)
    local _, pos = string_find(statusBuf, c, statusPos)
    if not pos then
        decode_error(string_format("expected '%s'", string_sub(c, #c)))
    end
    statusPos = pos
end
 
local function decode_unicode_surrogate(s1, s2)
    return utf8_char(0x10000 + (tonumber(s1, 16) - 0xd800) * 0x400 + (tonumber(s2, 16) - 0xdc00))
end
 
local function decode_unicode_escape(s)
    return utf8_char(tonumber(s, 16))
end
 
local function decode_string()
    local has_unicode_escape = false
    local has_escape = false
    local i = statusPos + 1
    while true do
        i = string_find(statusBuf, '["\\\0-\31]', i)
        if not i then
            decode_error "expected closing quote for string"
        end
        local x = string_byte(statusBuf, i)
        if x < 32 then
            statusPos = i
            decode_error "control character in string"
        end
        if x == 34 --[[ '"' ]] then
            local s = string_sub(statusBuf, statusPos + 1, i - 1)
            if has_unicode_escape then
                s = string_gsub(string_gsub(s
                    , "\\u([dD][89aAbB]%x%x)\\u([dD][c-fC-F]%x%x)", decode_unicode_surrogate)
                    , "\\u(%x%x%x%x)", decode_unicode_escape)
            end
            if has_escape then
                s = string_gsub(s, "\\.", decode_escape_map)
            end
            statusPos = i + 1
            return s
        end
        --assert(x == 92 --[[ "\\" ]])
        local nx = string_byte(statusBuf, i+1)
        if nx == 117 --[[ "u" ]] then
            if not string_match(statusBuf, "^%x%x%x%x", i+2) then
                statusPos = i
                decode_error "invalid unicode escape in string"
            end
            has_unicode_escape = true
            i = i + 6
        else
            if not decode_escape_set[nx] then
                statusPos = i
                decode_error("invalid escape char '" .. (nx and string_char(nx) or "<eol>") .. "' in string")
            end
            has_escape = true
            i = i + 2
        end
    end
end
 
local function decode_number()
    local num, c = string_match(statusBuf, '^([0-9]+%.?[0-9]*)([eE]?)', statusPos)
    if not num or string_byte(num, -1) == 0x2E --[[ "." ]] then
        decode_error("invalid number '" .. get_word() .. "'")
    end
    if c ~= '' then
        num = string_match(statusBuf, '^([^eE]*[eE][-+]?[0-9]+)[ \t\r\n%]},]', statusPos)
        if not num then
            decode_error("invalid number '" .. get_word() .. "'")
        end
    end
    statusPos = statusPos + #num
    return tonumber(num)
end
 
local function decode_number_zero()
    local num, c = string_match(statusBuf, '^(.%.?[0-9]*)([eE]?)', statusPos)
    if not num or string_byte(num, -1) == 0x2E --[[ "." ]] or string_match(statusBuf, '^.[0-9]+', statusPos) then
        decode_error("invalid number '" .. get_word() .. "'")
    end
    if c ~= '' then
        num = string_match(statusBuf, '^([^eE]*[eE][-+]?[0-9]+)[ \t\r\n%]},]', statusPos)
        if not num then
            decode_error("invalid number '" .. get_word() .. "'")
        end
    end
    statusPos = statusPos + #num
    return tonumber(num)
end
 
local function decode_number_negative()
    statusPos = statusPos + 1
    local c = string_byte(statusBuf, statusPos)
    if c then
        if c == 0x30 then
            return -decode_number_zero()
        elseif c > 0x30 and c < 0x3A then
            return -decode_number()
        end
    end
    decode_error("invalid number '" .. get_word() .. "'")
end
 
local function decode_true()
    if string_sub(statusBuf, statusPos, statusPos+3) ~= "true" then
        decode_error("invalid literal '" .. get_word() .. "'")
    end
    statusPos = statusPos + 4
    return true
end
 
local function decode_false()
    if string_sub(statusBuf, statusPos, statusPos+4) ~= "false" then
        decode_error("invalid literal '" .. get_word() .. "'")
    end
    statusPos = statusPos + 5
    return false
end
 
local function decode_null()
    if string_sub(statusBuf, statusPos, statusPos+3) ~= "null" then
        decode_error("invalid literal '" .. get_word() .. "'")
    end
    statusPos = statusPos + 4
    return json.null
end
 
local function decode_array()
    statusPos = statusPos + 1
    local res = {}
    if consume_byte "^[ \t\r\n]*%]" then
        return res
    end
    statusTop = statusTop + 1
    statusAry[statusTop] = true
    statusRef[statusTop] = res
    return res
end
 
local function decode_object()
    statusPos = statusPos + 1
    local res = {}
    if consume_byte "^[ \t\r\n]*}" then
        return setmetatable(res, json.object)
    end
    statusTop = statusTop + 1
    statusAry[statusTop] = false
    statusRef[statusTop] = res
    return res
end
 
local decode_uncompleted_map = {
    [ string_byte '"' ] = decode_string,
    [ string_byte "0" ] = decode_number_zero,
    [ string_byte "1" ] = decode_number,
    [ string_byte "2" ] = decode_number,
    [ string_byte "3" ] = decode_number,
    [ string_byte "4" ] = decode_number,
    [ string_byte "5" ] = decode_number,
    [ string_byte "6" ] = decode_number,
    [ string_byte "7" ] = decode_number,
    [ string_byte "8" ] = decode_number,
    [ string_byte "9" ] = decode_number,
    [ string_byte "-" ] = decode_number_negative,
    [ string_byte "t" ] = decode_true,
    [ string_byte "f" ] = decode_false,
    [ string_byte "n" ] = decode_null,
    [ string_byte "[" ] = decode_array,
    [ string_byte "{" ] = decode_object,
}
local function unexpected_character()
    decode_error("unexpected character '" .. string_sub(statusBuf, statusPos, statusPos) .. "'")
end
local function unexpected_eol()
    decode_error("unexpected character '<eol>'")
end
 
local decode_map = {}
for i = 0, 255 do
    decode_map[i] = decode_uncompleted_map[i] or unexpected_character
end
decode_map[-1] = unexpected_eol
 
local function decode()
    return decode_map[next_byte()]()
end
 
local function decode_item()
    local top = statusTop
    local ref = statusRef[top]
    if statusAry[top] then
        ref[#ref+1] = decode()
    else
        expect_byte '^[ \t\r\n]*"'
        local key = decode_string()
        expect_byte '^[ \t\r\n]*:'
        statusPos = statusPos + 1
        ref[key] = decode()
    end
    if top == statusTop then
        repeat
            local chr = next_byte(); statusPos = statusPos + 1
            if chr == 44 --[[ "," ]] then
                return
            end
            if statusAry[statusTop] then
                if chr ~= 93 --[[ "]" ]] then decode_error "expected ']' or ','" end
            else
                if chr ~= 125 --[[ "}" ]] then decode_error "expected '}' or ','" end
            end
            statusTop = statusTop - 1
        until statusTop == 0
    end
end
 
function json.decode(str)
    if type(str) ~= "string" then
        error("expected argument of type string, got " .. type(str))
    end
    statusBuf = str
    statusPos = 1
    statusTop = 0
    local res = decode()
    while statusTop > 0 do
        decode_item()
    end
    if string_find(statusBuf, "[^ \t\r\n]", statusPos) then
        decode_error "trailing garbage"
    end
    return res
end



-- Main Code 


function mineloop(ws)
    
    mine()
    mapSurroundings(ws)
    mapVerticalSurroundings(ws)
    checkSlots()
    moveForward()
    savePosition()
    checkBranch(ws)
    
end

--- TODO ---

--  Room mapping, should be pretty easy with relative coordinates
    -- Inspect all blocks surrounding the turtle and store them along with relative position X,Y,Z
    -- Using this information I could parse it into a local web page and use it to track the turtle progress
    -- This could then be adapated into making rooms for a base or even mapping out my base
    -- Mark when it has found diamonds, along with their relative coords.

function moveForward()
    if(not turtle.detect()) then
        turtle.forward()
        if(relativePosition.direction == 0) then
            relativePosition.x = relativePosition.x + 1
        elseif (relativePosition.direction == 1) then
            relativePosition.z = relativePosition.z + 1
        elseif (relativePosition.direction == 2) then
            relativePosition.x = relativePosition.x - 1
        elseif (relativePosition.direction == 3) then
            relativePosition.z = relativePosition.z - 1
        else 
            print("Direction not found.")
        end
    end
end

function checkSlots()
    local slot = 1
    local slotsInUse = 0
    while slot < 16 do
        if turtle.getItemCount(slot) > 0 then
            slotsInUse = slotsInUse + 1 
        end
        slot = slot + 1
    end
    if slotsInUse == 15 then
        disposeItems()
    end
    return slotsInUse
end

function checkBranch(ws)
    fastEnd = false
    -- Start Left Branch
    if(relativePosition.x == lastTunnel.x+3 and relativePosition.direction == 0) then
        turtle.turnLeft()
        relativePosition.direction = 3
    end

    -- Turn right at end of left branch
    if(relativePosition.z == -tonumber(args[1])) then
        mapSurroundings(ws)
        mapVerticalSurroundings(ws)
        turtle.turnRight()
        relativePosition.direction = 0
        for i=1, 4, 1 do 
            mine()
            moveForward()
            mapSurroundings(ws)
            mapVerticalSurroundings(ws)
        end
        turtle.turnRight()
        relativePosition.direction = 1
    end

    -- Turn to origin if in main branch
    if(relativePosition.z == 0 and relativePosition.direction == 1) then
        turtle.turnLeft()
        relativePosition.direction = 0
        lastTunnel.x = relativePosition.x
        lastTunnel.y = relativePosition.y
        lastTunnel.z = relativePosition.z
        relativePosition.tunnelsComplete = relativePosition.tunnelsComplete + 1
    end
    if (checkSlots() >= 10) then
        disposeItems()
        if (checkSlots() >= 10) then
            fastEnd = true
        end
    end
    -- Return to home once complete
    if(relativePosition.z == 0 and relativePosition.direction == 0 and (relativePosition.tunnelsComplete >= tonumber(args[2]) or fastEnd)) then
        turtle.turnLeft()
        turtle.turnLeft()
        relativePosition.direction = 2
    end

    -- Stop after basing
    if(relativePosition.x == 0 and relativePosition.direction == 2) then
        os.exit()
    end         
    
end

function mine()
    success, data = turtle.inspectUp()
    
    success2, data2 = turtle.inspectDown()
    success3, data3 = turtle.inspect()

    print(data.name)
    while(success and (data.name ~= "minecraft:water" and data.name ~= "minecraft:lava")) do
        turtle.digUp()
        success, data = turtle.inspectUp()
    end
    while(success2 and (data2.name ~= "minecraft:chest" and ( data2.name ~= "minecraft:water" and data2.name ~= "minecraft:lava"))) do
        turtle.digDown()
        success2, data2 = turtle.inspectDown()
    end
   
    while(success3 and (data3.name ~= "minecraft:water" and data3.name ~= "minecraft:lava")) do
        turtle.dig()
        success3, data3 = turtle.inspect()
    end
end

function main()

    local ws, err = setupWebsocket() 

    if(string.upper(args[1]) == "CONTINUE") then 
        previousOperation = io.open("previousMine.dat", "r")
        data = {}
        rawData = previousOperation:read("*all")
        data = textutils.unserialize(rawData)
        relativePosition.x = data.x
        relativePosition.y = data.y
        relativePosition.z = data.z
        relativePosition.direction = data.direction
        relativePosition.tunnelsComplete = data.tunnelsComplete
        args = data.args

    end
    while true do
        mineloop(ws)
    end
end

function disposeItems() 
    blacklist = {"minecraft:gravel","minecraft:cobblestone","minecraft:cobbled_deepslate","minecraft:dirt","minecraft:tuff","minecraft:flint"}
    turtle.select(16)
    turtle.placeDown()
    local slot = 1
    while slot < 16 do
        if(turtle.getItemCount(slot) ~= 0) then
            turtle.select(slot)
            for index, value in ipairs(blacklist) do
                if turtle.getItemDetail(slot).name == value then
                    turtle.refuel()
                    turtle.dropDown()
                    break
                end
            end
        end
        slot = slot + 1
    end
    turtle.select(1)
end

function savePosition()
    saveFile.x = relativePosition.x
    saveFile.y = relativePosition.y
    saveFile.z = relativePosition.z
    saveFile.direction = relativePosition.direction
    saveFile.tunnelsComplete = relativePosition.tunnelsComplete
    saveFile.args = args
    currentOperation = io.open("previousMine.dat", "w")
    currentOperation:write(textutils.serialize(saveFile))
    currentOperation:close(currentOperation)
end

function sendData(ws)
    ws.send(json.encode(
        {
            positionData=relativePosition,
            arguments=args,
        }
    ))
end

function sendBlockData(ws, block) -- Send the blocks to the left, right, top, botton, and front of turtle
    ws.send(json.encode(block))
    ws.send(json.encode(relativePosition))
end

function setupWebsocket()
    local ws, err = http.websocket("ws://localhost:7071")
    if err then
        print("Failed to establish connection")
        print("Error:", err)
        return
    elseif ws then 
        local message = os.getComputerLabel() .. ":CONNECTION"
        ws.send(message)
        local msg, bin = ws.receive() -- Response
        if msg then
            print("Received: " .. msg)
        end
    end
    --local message = os.getComputerLabel() .. ":STORAGE:" .. "HEWWO"
    --ws.send(message)
    return ws
end

function mapSurroundings(ws)
    
    local j = 0
    while j < 4 do 
        local block = {
            blockName = "Null",
            x = relativePosition.x,
            y = relativePosition.y,
            z = relativePosition.z,
        }
        local exists, data = turtle.inspect()
        if exists then
            block.blockName = data.name
        else
            block.blockName = "minecraft:air"
        end
        if(relativePosition.direction == 0) then
            block.x = relativePosition.x + 1
        elseif (relativePosition.direction == 1) then
            block.z = relativePosition.z + 1
        elseif (relativePosition.direction == 2) then
            block.x = relativePosition.x - 1
        elseif (relativePosition.direction == 3) then
            block.z = relativePosition.z - 1
        else 
            print("Direction not found.")
        end
        sendBlockData(ws, block)
        relativePosition.direction = relativePosition.direction + 1
        if relativePosition.direction == 4 then
            relativePosition.direction = 0
        end 
        turtle.turnRight()
        j = j + 1 
    end
end

function mapVerticalSurroundings(ws)
    local block = {
        blockName = "Null",
        x = relativePosition.x,
        y = relativePosition.y,
        z = relativePosition.z,
    }
    turtle.up()
    relativePosition.y = relativePosition.y + 1
    local exists, data = turtle.inspectUp()
    if exists then 
        block.blockName = data.name
    else
        block.blockName = "minecraft:air"
    end
    block.y = relativePosition.y + 1 
    sendBlockData(ws, block)
    mapSurroundings(ws)
    turtle.down()
    relativePosition.y = relativePosition.y - 1
    turtle.down()
    relativePosition.y = relativePosition.y - 1
    local exists, data = turtle.inspectDown()
    if exists then 
        block.blockName = data.name
    else
        block.blockName = "minecraft:air"
    end
    block.y = relativePosition.y - 1 
    sendBlockData(ws, block)
    mapSurroundings(ws)
    turtle.up()
    relativePosition.y = relativePosition.y + 1
end
    -- Pos X = Forward
    -- Pos Y = Up
    -- Pos Z = Right
    -- Directions
    -- 0 = Origin
    -- 1 = Right
    -- 2 = Backwards
    -- 3 = Left

relativePosition = {
    x = 0,
    y = 0,
    z = 0,
    direction = 0,
    tunnelsComplete = 0,
}
data = {
    x = 0,
    y = 0,
    z = 0,
    direction = 0,
    tunnelsComplete = 0,
    args = {},
}
lastTunnel = {
    x = 0,
    y = 0,
    z = 0,
}

saveFile = {
    x = 0,
    y = 0,
    z = 0,
    direction = 0,
    tunnelsComplete = 0,
    args = {},
}




args = {...}

main()