-- #region Constants
vec3_up = sm.vec3.new(0,0,1)
camAdjust = sm.vec3.new(0,0,0.575)
vec3_zero = sm.vec3.zero()
vec3_one = sm.vec3.one()
vec3_x = sm.vec3.new(1,0,0)
vec3_y = sm.vec3.new(1,0,0)
-- #endregion


-- #region Functions
---@param rayResult RaycastResult
---@return table
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
-- #endregion


-- #region Classes
-- #region Line_gun
local line_up = sm.vec3.new(1,0,0)
Line_gun = class()
function Line_gun:init( thickness, colour, strong )
    self.effect = sm.effect.createEffect("ShapeRenderable")
	self.effect:setParameter("uuid", sm.uuid.new("b6cedcb3-8cee-4132-843f-c9efed50af7c"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( sm.vec3.one() * thickness )
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
        sm.log.warning("Line_gun:update() | Length of 'endPos - startPos' must be longer than 0.")
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
		sm.particle.createParticle( "cutter_block_destroy", endPos, sm.quat.identity(), self.colour )
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
function Line_cutter:init( thickness, colour, dyingShrink )
    self.effect = sm.effect.createEffect("ShapeRenderable")
	self.effect:setParameter("uuid", sm.uuid.new("b6cedcb3-8cee-4132-843f-c9efed50af7c"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( sm.vec3.one() * thickness )
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
        sm.log.warning("Line_cutter:update() | Length of 'endPos - startPos' must be longer than 0.")
        return
	end

	local rot = sm.vec3.getRotation(line_up, delta)
	local speed = spinSpeed or 0
	local deltaTime = dt or 0
	self.spinTime = self.spinTime + deltaTime * speed
	rot = rot * sm.quat.angleAxis( math.rad(self.spinTime), line_up )

	self.currentThickness = dying and math.max(self.currentThickness - dt * self.dyingShrink, 0) or self.thickness
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

--thanks QMark
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