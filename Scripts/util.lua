-- #region Constants
RAD90 = math.rad(90)
camAdjust = sm.vec3.new(0,0,0.575)
camAdjust_crouch = sm.vec3.new(0,0,0.3)
vec3_up = sm.vec3.new(0,0,1)
vec3_zero = sm.vec3.zero()
vec3_one = sm.vec3.one()
vec3_x = sm.vec3.new(1,0,0)
vec3_y = sm.vec3.new(1,0,0)
defaultQuat = sm.quat.identity()
projectile_cutter = sm.uuid.new("4ed831d7-71af-4f94-b50f-e67b17f80312")
projectile_railgun = sm.uuid.new("caccde30-8f1b-45ca-a4c3-e1a949724a9b")
pistolcoil = sm.uuid.new("64f6e8ad-abe6-47c7-b924-f7593637dcc1")
plasma = sm.uuid.new("69c063fe-385a-4135-8f5e-6247aec89769")
connectionType_plasma = 4096
-- #endregion


---@class RaycastResult_table : RaycastResult
---@field target Shape|Character|Harvestable

-- #region Functions
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
		target = rayResult:getShape() or rayResult:getCharacter() or rayResult:getHarvestable()
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
-- #endregion



-- #region Classes
---@class LaserProjectile
---@field pos Vec3
---@field dir Vec3
---@field strong boolean
---@field hitPos Vec3
---@field overdrive boolean
---@field owner Character|Shape

-- #region Line_gun
local line_up = sm.vec3.new(1,0,0)
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

	local rot = sm.vec3.getRotation(line_up, delta)
	local speed = spinSpeed or 0
	local deltaTime = dt or 0
	self.spinTime = self.spinTime + deltaTime * speed
	rot = rot * sm.quat.angleAxis( math.rad(self.spinTime), line_up )

	if self.strong then
		self.thickness = math.max(self.thickness - dt * 0.5, 0)
	end

	local distance = sm.vec3.new(length, self.thickness, self.thickness)
	self.effect:setPosition(startPos + delta * 0.5)
	self.effect:setScale(distance)
	self.effect:setRotation(rot)

	--this shit kills my gpu if its done every frame
	if sm.game.getCurrentTick() % 4 == 0 then
		sm.particle.createParticle( "cutter_block_destroy", endPos, defaultQuat, self.colour )
	end

	self.sound:setPosition(startPos)

    if not self.effect:isPlaying() then
        self.effect:start()
		self.sound:start()
    end
end

function Line_gun:stop()
	self.effect:stopImmediate()
	self.sound:stopImmediate()
end

function Line_gun:destroy()
	self.effect:destroy()
	self.sound:destroy()
end
-- #endregion


-- #region Line_cutter
Line_cutter = class()
---@class Line_cutter
---@field init function
---@field update function
---@field stop function
---@field setThicknessMultiplier function
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
	self.thicknessMultiplier = 1
end

function Line_cutter:setThicknessMultiplier( num )
	self.thicknessMultiplier = num
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

	local rot = sm.vec3.getRotation(line_up, delta)
	local speed = spinSpeed or 0
	local deltaTime = dt or 0
	self.spinTime = self.spinTime + deltaTime * speed
	rot = rot * sm.quat.angleAxis( math.rad(self.spinTime), line_up )

	self.currentThickness = (dying and math.max(self.currentThickness - dt * self.dyingShrink, 0) or self.thickness) * self.thicknessMultiplier
	local distance = sm.vec3.new(length, self.currentThickness, self.currentThickness)

	self.effect:setPosition(startPos + delta * 0.5)
	self.effect:setScale(distance)
	self.effect:setRotation(rot)

	if self.currentThickness >= self.thickness * 0.25 then
		sm.particle.createParticle( "cutter_block_destroy", endPos, sm.quat.identity(), self.colour )
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