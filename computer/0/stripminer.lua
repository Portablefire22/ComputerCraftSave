
function mineloop()
    
    mine()
    checkSlots()
    moveForward()
    savePosition()
    checkBranch()
    
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

function checkBranch()
    fastEnd = false
    -- Start Left Branch
    if(relativePosition.x == lastTunnel.x+3 and relativePosition.direction == 0) then
        turtle.turnLeft()
        relativePosition.direction = 3
    end

    -- Turn right at end of left branch
    if(relativePosition.z == -tonumber(args[1])) then
        turtle.turnRight()
        relativePosition.direction = 0
        mine()
        moveForward()
        mine()
        moveForward()
        mine()
        moveForward()
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
        mineloop()
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