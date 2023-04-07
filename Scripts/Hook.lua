Hook = class()

local oldHud = sm.gui.createSurvivalHudGui
function hudHook()
    dofile("$CONTENT_a898c2c4-de95-4899-9442-697ced66b832/Scripts/util.lua")
	return oldHud()
end
sm.gui.createSurvivalHudGui = hudHook