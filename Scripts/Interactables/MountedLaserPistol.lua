dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile "$CONTENT_DATA/Scripts/util.lua"

---@class MountedLaserPistol : ShapeClass
---@field sv table
---@field cl table
MountedLaserPistol = class()
MountedLaserPistol.maxParentCount = -1
MountedLaserPistol.maxChildCount = 0
MountedLaserPistol.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.electricity --bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.ammo )
MountedLaserPistol.connectionOutput = sm.interactable.connectionType.none
MountedLaserPistol.colorNormal = sm.color.new( 0xcb0a00ff )
MountedLaserPistol.colorHighlight = sm.color.new( 0xee0a00ff )
MountedLaserPistol.poseWeightCount = 1

MountedLaserPistol.damage = 45
MountedLaserPistol.primaryTicks = 0.25 * 40
MountedLaserPistol.secondaryTicks = 2 * 40
MountedLaserPistol.overdriveCooldownTicks = 10 * 40
MountedLaserPistol.overdriveDurationTicks = 5 * 40

local input_primary = "df7f00"
local input_primary2 = "df7f01"
local input_secondary = "eeeeee"
local input_overdrive = "222222"
local colour_weak = sm.color.new(0,1,1)
local colour_strong = sm.color.new(0.75,0,0)
local barrelAdjust = sm.vec3.new(0,-0.02,0.278)

function MountedLaserPistol:server_onCreate()
	self.sv_primaryTimer = Timer()
	self.sv_primaryTimer:start( self.primaryTicks )
	self.sv_primaryTimer.count = self.sv_primaryTimer.ticks

	self.sv_secondaryTimer = Timer()
	self.sv_secondaryTimer:start( self.secondaryTicks )
	self.sv_secondaryTimer.count = self.sv_secondaryTimer.ticks

	self.sv_overdriveCooldown = Timer()
	self.sv_overdriveCooldown:start( self.overdriveCooldownTicks )
	self.sv_overdriveCooldown.count = self.sv_overdriveCooldown.ticks

	self.sv_overdriveDuration = Timer()
	self.sv_overdriveDuration:start( self.overdriveDurationTicks )
	self.sv_overdriveActive = false
end

function MountedLaserPistol:server_onFixedUpdate()
	self.sv_primaryTimer:tick()
	self.sv_secondaryTimer:tick()
	self.sv_overdriveCooldown:tick()

	local primary, secondary, overdrive, container = self:getInputs()
	local freeFire = not sm.game.getEnableAmmoConsumption()
	if primary and self.sv_primaryTimer:done() and (freeFire or container and container:canSpend(obj_consumable_battery, 1)) then
		self.sv_primaryTimer:reset()
		self:sv_fire(container, false)
	end

	if secondary and not primary and self.sv_secondaryTimer:done() and (freeFire or container and container:canSpend(obj_consumable_battery, 5)) then
		self.sv_secondaryTimer:reset()
		self:sv_fire(container, true, 5)
	end

	if overdrive and self.sv_overdriveCooldown:done() and not self.sv_overdriveActive then
		self.sv_overdriveActive = true
		self.sv_primaryTimer.ticks = self.primaryTicks / 2
		self.network:sendToClients("cl_overdrive", true)
	end

	if self.sv_overdriveActive then
		self.sv_overdriveDuration:tick()
		if self.sv_overdriveDuration:done() then
			self.sv_overdriveDuration:reset()
			self.sv_overdriveCooldown:reset()
			self.sv_overdriveActive = false
			self.sv_primaryTimer.ticks = self.primaryTicks
			self.network:sendToClients("cl_overdrive", false)
		end
	end
end

function MountedLaserPistol:sv_fire(container, strong, quantity)
	if container then
		sm.container.beginTransaction()
		sm.container.spend(container, obj_consumable_battery, quantity or (self.sv_overdriveActive and 2 or 1))
		sm.container.endTransaction()
	end

	sm.event.sendToTool(
		g_pManager,
		"sv_createProjectile",
		{
			pos = self.shape:transformLocalPoint(barrelAdjust),
			dir = self.shape.up,
			strong = strong,
			overdrive = self.sv_overdriveActive,
			owner = self.shape
		}
	)
	self.network:sendToClients("cl_fire", strong)
end



function MountedLaserPistol:client_onCreate()
	self.cl_boltValue = 0
	self.cl_activeSound = sm.effect.createEffect( "Cutter_active_sound", self.interactable )
	self.cl_shootEffect = sm.effect.createEffect("Pistol_shoot", self.interactable)
	self.cl_shootEffect:setOffsetPosition(barrelAdjust)
	self.cl_poweronEffect = sm.effect.createEffect("Pistol_overdrive_on", self.interactable)

	self.interactable:setSubMeshVisible("glow", false)

	local colour = self.shape.color
	self.cl_coilEffect = sm.effect.createEffect("ShapeRenderable", self.interactable)
	self.cl_coilEffect:setParameter("uuid", pistolcoil)
	self.cl_coilEffect:setParameter("color", colour)
	self.cl_coilEffect:setScale(vec3_one * 0.25)
	self.cl_coilEffect:setOffsetRotation(sm.quat.angleAxis(math.rad(90), vec3_x))
	self.cl_coilEffect:start()

	self.lerpProgress = 1
	self.lerpBlock = false
	self.colour = colour
	self.shapeColour = colour
end

function MountedLaserPistol:client_onUpdate( dt )
	local primary = self:getInputs()
	local sound = self.cl_activeSound
	local playing = sound:isPlaying()
	if primary and not playing then
		sound:start()
	elseif not primary and playing then
		sound:stop()
	end

	if self.cl_boltValue > 0.0 then
		self.cl_boltValue = self.cl_boltValue - dt * 10
	end
	if self.cl_boltValue ~= self.cl_prevBoltValue then
		self.interactable:setPoseWeight( 0, self.cl_boltValue )
		self.cl_prevBoltValue = self.cl_boltValue
	end

	local shapeColour = self.shape.color
	if shapeColour ~= self.shapeColour then
		self.shapeColour = shapeColour
		self.cl_coilEffect:setParameter("color", shapeColour)
	end

	if self.lerpProgress <= 1 and not self.lerpBlock then
		self.lerpProgress = self.lerpProgress + dt
		self.cl_coilEffect:setParameter("color", ColourLerp( self.colour, shapeColour, self.lerpProgress ))
	end
end

function MountedLaserPistol:cl_fire(strong)
	self.cl_boltValue = 1
	self.cl_shootEffect:start()

	if not self.lerpBlock then
		self.lerpProgress = 0
		local colour = strong and colour_strong or colour_weak
		self.cl_coilEffect:setParameter("color", colour)
		self.colour = colour
	end
end

function MountedLaserPistol:cl_overdrive(state)
	self.lerpBlock = state
	if state then
		self.cl_poweronEffect:start()
		self.lerpProgress = 0
		self.cl_coilEffect:setParameter("color", colour_strong)
		self.colour = colour_strong
	end
end



function MountedLaserPistol:getInputs()
	local parents = self.interactable:getParents()
	local primary, secondary, overdrive = false, false, false
	local container
	for k, parent in pairs(parents) do
		if parent:hasOutputType(1) and parent.active then
			local colour = parent.shape.color:getHexStr():sub(1,6)
			if colour == input_primary or colour == input_primary2 then
				primary = true
			elseif colour == input_secondary then
				secondary = true
			elseif colour == input_overdrive then
				overdrive = true
			end
		end

		if parent:hasOutputType(512) then
			container = parent:getContainer(0)
		end
	end

	return primary, secondary, overdrive, container
end