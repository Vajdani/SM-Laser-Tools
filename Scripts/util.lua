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

--thanks QMark
---@param vector Vec3
---@return Vec3 right
function calculateRightVector(vector)
    local yaw = math.atan2(vector.y, vector.x) - math.pi / 2
    return sm.vec3.new(math.cos(yaw), math.sin(yaw), 0)
end

---@param vector Vec3
---@return Vec3 up
function calculateUpVector(vector)
    return calculateRightVector(vector):cross(vector)
end