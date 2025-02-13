-- #region Constants
RAD90 = math.rad(90)
camAdjust = sm.vec3.new(0,0,0.575)
camAdjust_crouch = sm.vec3.new(0,0,0.3)
vec3_up = sm.vec3.new(0,0,1)
vec3_zero = sm.vec3.zero()
vec3_one = sm.vec3.one()
vec3_x = sm.vec3.new(1,0,0)
vec3_y = sm.vec3.new(0,1,0)
vec3_1eighth = sm.vec3.new(0.125,0.125,0.125)
defaultQuat = sm.quat.identity()
projectile_railgun = sm.uuid.new("caccde30-8f1b-45ca-a4c3-e1a949724a9b")
pistolcoil = sm.uuid.new("64f6e8ad-abe6-47c7-b924-f7593637dcc1")
plasma = sm.uuid.new("69c063fe-385a-4135-8f5e-6247aec89769")
connectionType_plasma = 4096
-- #endregion


local slipOnContact = {
	["97fe0cf2-0591-4e98-9beb-9186f4fd83c8"] = true --hvs_loot
}
for k, v in pairs(sm.json.open("$SURVIVAL_DATA/Objects/Database/ShapeSets/harvests.json").partList) do
	slipOnContact[v.uuid] = true
end

for k, v in pairs(sm.json.open("$SURVIVAL_DATA/Harvestables/Database/HarvestableSets/hvs_farmables.json").harvestableList) do
	if v.name:find("broken") then
		slipOnContact[v.uuid] = true
	end
end

for k, v in pairs(sm.json.open("$SURVIVAL_DATA/Harvestables/Database/HarvestableSets/hvs_plantables.json").harvestableList) do
	if not v.name:find("mature") then
		slipOnContact[v.uuid] = true
	end
end

function ShouldLaserSkipTarget(uuid)
	return slipOnContact[tostring(uuid)] == true
end

local explosiveClasses = {
	CannonNuke = true,
	Explosive = true
}
function IsExplosiveClass(classname)
	--return explosiveClasses[classname] == true
	return false
end

-- #region Functions
---@param char Character
function SendDamageEventToCharacter(char, args)
	if not sm.exists(char) then return end

	if char:isPlayer() then
		sm.event.sendToPlayer(char:getPlayer(), "sv_e_takeDamage", args)
	else
		local unit = char:getUnit()
		if not sm.exists(unit) then return end

		sm.event.sendToUnit(unit, "sv_e_takeDamage", args)
	end
end

---@class RaycastResult_table : RaycastResult
---@field target Shape|Character|Harvestable

---@param rayResult RaycastResult
---@return RaycastResult_table
function RayResultToTable( rayResult )
    return {
        valid = rayResult.valid,
        originWorld = rayResult.originWorld,
        directionWorld = rayResult.directionWorld,
        normalWorld = rayResult.normalWorld,
        normalLocal = rayResult.normalLocal,
        pointWorld = rayResult.pointWorld,
        pointLocal = rayResult.pointLocal,
        type = rayResult.type,
        fraction = rayResult.fraction,
		target = rayResult:getShape() or rayResult:getCharacter() or rayResult:getHarvestable() or (rayResult:getJoint() or {}).shapeA
    }
end

---@param vector Vec3
---@return Vec3 rounded
function RoundVector( vector )
    return sm.vec3.new(round(vector.x), round(vector.y), round(vector.z))
end

---@param vector Vec3
---@return Vec3 rounded
function AbsVector( vector )
    return sm.vec3.new(math.abs(vector.x), math.abs(vector.y), math.abs(vector.z))
end

---@param bool boolean
---@return integer
function BoolToVal( bool )
    return bool and 1 or 0
end

---@param c1 Color
---@param c2 Color
---@param t number
---@return Color
function ColourLerp(c1, c2, t)
    local r = sm.util.lerp(c1.r, c2.r, t)
    local g = sm.util.lerp(c1.g, c2.g, t)
    local b = sm.util.lerp(c1.b, c2.b, t)
    return sm.color.new(r,g,b)
end

function checkPipedNeighbours(parentShape, containers)
	for _k, shape in pairs(parentShape:getPipedNeighbours()) do
		local int = shape.interactable
		local id = shape.id
		if int:hasOutputType(connectionType_plasma) and containers[id] == nil then
			containers[id] = int:getContainer(0)
			checkPipedNeighbours(shape, containers)
		end
	end
end

---@param shape Shape
---@return Vec3
function GetAccurateShapePosition(shape)
    return shape:getInterpolatedWorldPosition() + shape.velocity * 0.0125
end

---@param shape Shape
---@return Vec3
function GetAccurateShapeUp(shape)
    local ang = shape.body.angularVelocity
    local length = ang:length()
    local dir = shape:getInterpolatedUp()
    if length < FLT_EPSILON then return dir end

    return dir:rotate(length * 0.025, ang)
end

---@param shape Shape
---@return Vec3
function GetAccurateShapeRight(shape)
    local ang = shape.body.angularVelocity
    local length = ang:length()
    local dir = shape:getInterpolatedRight()
    if length < FLT_EPSILON then return dir end

    return dir:rotate(length * 0.025, ang)
end

---@param shape Shape
---@return Vec3
function GetAccurateShapeAt(shape)
    local ang = shape.body.angularVelocity
    local length = ang:length()
    local dir = shape:getInterpolatedAt()
    if length < FLT_EPSILON then return dir end

    return dir:rotate(length * 0.025, ang)
end

--Thank you so much Programmer Alex
function getClosestBlockGlobalPosition( target, worldPos )
	local A = sm.item.isBlock(target.uuid) and target:getClosestBlockLocalPosition( worldPos ) * 0.25 or target.localPosition * 0.25
	local B = target.localPosition * 0.25 - vec3_1eighth
	local C = target:getBoundingBox()
	return target:transformLocalPoint( A-(B+C*0.5) )
end
-- #endregion



-- #region Classes
---@class LaserProjectile
---@field pos Vec3
---@field dir Vec3
---@field strong boolean
---@field hitPos? Vec3
---@field overdrive boolean
---@field owner Character|Shape
---@field tool? Tool

-- #region Line_gun
---@class Line_gun
---@field init function
---@field update function
---@field stop function
---@field destroy function
Line_gun = class()
function Line_gun:init( thickness, colour, strong )
    self.effect = sm.effect.createEffect("ShapeRenderable")
	self.effect:setParameter("uuid", sm.uuid.new("b6cedcb3-8cee-4132-843f-c9efed50af7c"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( vec3_one * thickness )
	self.sound = sm.effect.createEffect( "Cutter_beam_sound" )

	if not strong then
		self.trail = sm.effect.createEffect("Laser_trail")
		self.trail:setParameter("Color", colour)
	end

	self.colour = colour
    self.thickness = thickness
	self.spinTime = 0
	self.strong = strong
end


---@param startPos Vec3
---@param endPos Vec3
---@param dt number
---@param spinSpeed number
function Line_gun:update( startPos, endPos, dt, spinSpeed )
	local delta = endPos - startPos
    local length = delta:length()

    if length < 0.0001 then
        return
	end

	local rot = sm.vec3.getRotation(vec3_x, delta)
	local speed = spinSpeed or 0
	local deltaTime = dt or 0
	self.spinTime = self.spinTime + deltaTime * speed
	rot = rot * sm.quat.angleAxis( math.rad(self.spinTime), vec3_x )

	if self.strong then
		self.thickness = math.max(self.thickness - dt * 0.5, 0)
	end

	local distance = sm.vec3.new(length, self.thickness, self.thickness)
	self.effect:setPosition(startPos + delta * 0.5)
	self.effect:setScale(distance)
	self.effect:setRotation(rot)

	if self.trail then
		self.trail:setPosition(startPos)
		self.trail:setRotation(sm.vec3.getRotation(vec3_y, -delta))
	end

	--this shit kills my gpu if its done every frame
	--[[if sm.game.getCurrentTick() % 4 == 0 then
		sm.particle.createParticle( "cutter_block_destroy", endPos, defaultQuat, self.colour )
	end]]

	self.sound:setPosition(startPos)

    if not self.effect:isPlaying() then
        self.effect:start()
		self.sound:start()
		if self.trail then self.trail:start() end
    end
end

function Line_gun:stop()
	self.effect:stop()
	self.sound:stop()
	if self.trail then self.trail:stop() end
end

function Line_gun:destroy()
	self.effect:destroy()
	self.sound:destroy()
	if self.trail then self.trail:destroy() end
end
-- #endregion


-- #region Line_cutter
Line_cutter = class()
---@class Line_cutter
---@field init function
---@field update function
---@field stop function
function Line_cutter:init( thickness, colour, dyingShrink )
    self.effect = sm.effect.createEffect("ShapeRenderable")
	self.effect:setParameter("uuid", sm.uuid.new("b6cedcb3-8cee-4132-843f-c9efed50af7c"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( vec3_one * thickness )
	self.sound = sm.effect.createEffect( "Cutter_beam_sound" )

	self.colour = colour
    self.thickness = thickness
	self.currentThickness = thickness
	self.spinTime = 0
	self.dyingShrink = dyingShrink or 1
end

---@param startPos Vec3
---@param endPos Vec3
---@param dt number
---@param spinSpeed number
function Line_cutter:update( startPos, endPos, dt, spinSpeed, dying )
	local delta = endPos - startPos
    local length = delta:length()

    if length < 0.0001 then
        return
	end

	local rot = sm.vec3.getRotation(vec3_x, delta)
	local speed = spinSpeed or 0
	local deltaTime = dt or 0
	self.spinTime = self.spinTime + deltaTime * speed
	rot = rot * sm.quat.angleAxis( math.rad(self.spinTime), vec3_x )

	self.currentThickness = (dying and math.max(self.currentThickness - deltaTime * self.dyingShrink, 0) or self.thickness)
	local distance = sm.vec3.new(length, self.currentThickness, self.currentThickness)

	self.effect:setPosition(startPos + delta * 0.5)
	self.effect:setScale(distance)
	self.effect:setRotation(rot)

	if self.currentThickness >= self.thickness * 0.25 then
		sm.particle.createParticle( "cutter_block_destroy", endPos, defaultQuat, self.colour )
	end

	self.sound:setPosition(startPos)

    if not self.effect:isPlaying() then
        self.effect:start()
		self.sound:start()
    end
end

function Line_cutter:stop()
	self.effect:stopImmediate()
	self.sound:stopImmediate()
end
-- #endregion
-- #endregion



-- #region Legally obtained things

--Thanks to Questionable Mark for all of these functions
---@param vector Vec3
---@return Vec3 right
function calculateRightVector(vector)
    local yaw = math.atan(vector.y, vector.x) - math.pi / 2
    return sm.vec3.new(math.cos(yaw), math.sin(yaw), 0)
end

---@param vector Vec3
---@return Vec3 up
function calculateUpVector(vector)
    return calculateRightVector(vector):cross(vector)
end
-- #endregion