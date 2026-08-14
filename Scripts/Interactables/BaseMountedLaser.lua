-- dofile "$SURVIVAL_DATA/Scripts/util.lua"

---@class BaseMountedLaser : ShapeClass
BaseMountedLaser = class()
BaseMountedLaser.maxLogicParentCount = 1

function BaseMountedLaser:server_onCreate()
    self.sv_containers = {}
    self.sv_parentCount = 0
end


function BaseMountedLaser:client_getAvailableParentConnectionCount(flags)
    if bit.band(flags, connectionType_plasma) ~= 0 then
        return 1 - #self.interactable:getParents(connectionType_plasma)
    end

    if bit.band(flags, sm.interactable.connectionType.logic) ~= 0 then
        return self.maxLogicParentCount - #self.interactable:getParents(sm.interactable.connectionType.logic)
    end

    return 0
end


function BaseMountedLaser:canShoot(quantity)
	quantity = quantity or 1

    local parents = self.interactable:getParents(connectionType_plasma)
    local parent = parents[1]
    if self.sv_parentCount ~= #parents or self.shape.body:hasChanged(sm.game.getServerTick() - 1) then
        self.sv_containers = {}
        self.sv_parentCount = #parents

        if parent then
            checkPipedNeighbours(parent.shape, self.sv_containers)
        end
    end

    if parent then
        local container = parent:getContainer(0)
        if not container:canSpend(plasma, quantity) then
            for k, v in pairs(self.sv_containers) do
                if v:canSpend(plasma, quantity) then
                    container = v
                    break
                end
            end
        end

        sm.container.beginTransaction()
		sm.container.spend(container, plasma, quantity)
		return sm.container.endTransaction()
    end

    return not sm.game.getEnableAmmoConsumption()
end