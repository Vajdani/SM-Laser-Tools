dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile "$CONTENT_DATA/Scripts/util.lua"

---@class MountedLaserCutter : ShapeClass
---@field sv table
---@field cl table
MountedLaserCutter = class()
MountedLaserCutter.maxParentCount = -1
MountedLaserCutter.maxChildCount = 0
MountedLaserCutter.connectionInput = sm.interactable.connectionType.logic --bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.ammo )
MountedLaserCutter.connectionOutput = sm.interactable.connectionType.none
MountedLaserCutter.colorNormal = sm.color.new( 0xcb0a00ff )
MountedLaserCutter.colorHighlight = sm.color.new( 0xee0a00ff )
MountedLaserCutter.poseWeightCount = 1

MountedLaserCutter.defaultDamage = 45
MountedLaserCutter.defaultRange = 15
MountedLaserCutter.lineThickness = 0.2
MountedLaserCutter.lineColour = sm.color.new(0,1,1)
MountedLaserCutter.spinSpeed = 250
MountedLaserCutter.beamStopSeconds = 1
MountedLaserCutter.unitDamageTicks = 10

local barrelAdjust = sm.vec3.one() * 0.4
local on = "#269e44On"
local off = "#9e2626Off"

function MountedLaserCutter.server_onCreate( self )
	self:sv_init()
end

function MountedLaserCutter.server_onRefresh( self )
	self:sv_init()
end

function MountedLaserCutter.sv_init( self )
	self.sv = {}
	self.sv.data = self.storage:load()
	if self.sv.data == nil then
		self.sv.data = {}
		self.sv.data.damage = self.defaultDamage
		self.sv.data.range = self.defaultRange
		self.sv.data.line = false
	end

	self:sv_updateGui({ dmg = self.sv.data.damage, range = self.sv.data.range, line = self.sv.data.line })

	self.sv.unitDamageTimer = Timer()
	self.sv.unitDamageTimer:start( self.unitDamageTicks )
end

function MountedLaserCutter.server_onFixedUpdate( self )
	if not self:shouldFire() then return end

	local selfDir = self.shape.up
	local selfPos = self.shape.worldPosition + barrelAdjust * selfDir
	local endPos = selfPos + selfDir * self.sv.data.range
	local hit, result = sm.physics.raycast( selfPos, endPos )

	if not hit then return end

	local hitPos = result.pointWorld
	local target = result:getShape() or result:getCharacter() or result:getHarvestable()
	if not target or not sm.exists(target) then return end

	local type = type(target)
	if type == "Shape" then
		sm.effect.playEffect(
			"Sledgehammer - Destroy",
			hitPos,
			sm.vec3.zero(),
			sm.vec3.getRotation( sm.vec3.new(0,0,1), result.normalWorld ),
			sm.vec3.one(),
			{ Material = target:getMaterialId() }
		)

		if sm.item.isBlock( target.uuid ) then
			target:destroyBlock( target:getClosestBlockLocalPosition(hitPos) )
		else
			target:destroyShape( 0 )
		end
	elseif type == "Character" then
		self.sv.unitDamageTimer:tick()
		if self.sv.unitDamageTimer:done() then
			self.sv.unitDamageTimer:reset()
			sm.projectile.shapeProjectileAttack(
				projectile_potato,
				self.sv.data.damage,
				self.shape:transformPoint(hitPos),
				(target.worldPosition - hitPos),
				self.shape
			)
		end
	else
		sm.physics.explode( hitPos, 3, 1, 1, 1 )
	end
end

function MountedLaserCutter:sv_updateGui( args )
	self.sv.data.damage = args.dmg
	self.sv.data.range = args.range
	self.sv.data.line = args.line
	self.storage:save( self.sv.data )

	self.network:sendToClients( "cl_updateGui", args )
end



function MountedLaserCutter.client_onCreate( self )
	self.cl = {}
	self.cl.boltValue = 0.0

	self.cl.damage = self.defaultDamage
	self.cl.range = self.defaultRange

	self.cl.gui = sm.gui.createGuiFromLayout( "$CONTENT_DATA/Gui/Mounted.layout", false )
	self.cl.gui:setTextAcceptedCallback( "input_dmg", "cl_input_dmg" )
	self.cl.gui:setTextAcceptedCallback( "input_range", "cl_input_range" )
	self.cl.gui:setIconImage( "icon", self.shape.uuid )
	self.cl.gui:setButtonCallback( "laser", "cl_input_laser" )
	self.cl.gui:setText( "laser", off )

	self.cl.line = Line_cutter()
	self.cl.line:init( self.lineThickness, self.lineColour, 0.4 )
	self.cl.lineAlways = false
	self.cl.activeSound = sm.effect.createEffect( "Cutter_active_sound", self.interactable )

	self.cl.lastPos = sm.vec3.zero()
	self.cl.beamStopTimer = self.beamStopSeconds
end

function MountedLaserCutter:cl_input_dmg( widget, value )
	local num = tonumber(value)
	if num == nil then
		self.cl.gui:setText( "input_dmg", tostring(self.cl.damage) )
		sm.audio.play("RaftShark")
		return
	end

	self.cl.damage = num
	self.network:sendToServer("sv_updateGui", { dmg = self.cl.damage, range = self.cl.range, line = self.cl.lineAlways })
end

function MountedLaserCutter:cl_input_range( widget, value )
	local num = tonumber(value)
	if num == nil then
		self.cl.gui:setText( "input_range", tostring(self.cl.range) )
		sm.audio.play("RaftShark")
		return
	end

	self.cl.range = num
	self.network:sendToServer("sv_updateGui", { dmg = self.cl.damage, range = self.cl.range, line = self.cl.lineAlways })
end

function MountedLaserCutter:cl_input_laser()
	self.network:sendToServer("sv_updateGui", { dmg = self.cl.damage, range = self.cl.range, line = not self.cl.lineAlways })
end

function MountedLaserCutter:cl_updateGui( args )
	self.cl.damage = args.dmg
	self.cl.range = args.range
	self.cl.lineAlways = args.line

	self.cl.gui:setText( "input_dmg", string.format("%.3f", tostring(self.cl.damage) ) )
	self.cl.gui:setText( "input_range", string.format("%.3f", tostring(self.cl.range) ) )
	self.cl.gui:setText( "laser", self.cl.lineAlways and on or off )
end

function MountedLaserCutter:client_onInteract( char, state )
	if not state then return end

	self.cl.gui:open()
end

function MountedLaserCutter.client_onUpdate( self, dt )
	local active = self:shouldFire()
	local hit, result = false, nil
	local selfDir = self.shape.up
	local selfPos = self.shape.worldPosition + barrelAdjust * selfDir
	local target

	if active then
		if not self.cl.activeSound:isPlaying() then
			self.cl.activeSound:start()
		end

		local endPos = selfPos + selfDir * self.cl.range
		hit, result = sm.physics.raycast( selfPos, endPos )

		target = result:getShape() or result:getCharacter()

		if hit and target then
			self.cl.lastPos = result.pointWorld
			self.cl.beamStopTimer = self.beamStopSeconds
			self.cl.line:update( selfPos, result.pointWorld, dt, 250, false )
		elseif self.cl.lineAlways then
			self.cl.lastPos = endPos
			self.cl.beamStopTimer = self.beamStopSeconds
			self.cl.line:update( selfPos, endPos, dt, 250, false )
		end
	elseif self.cl.activeSound:isPlaying() then
		self.cl.activeSound:stop()
	end

	if (not active or not hit or not target) and self.cl.line.effect:isPlaying() then
		self.cl.beamStopTimer = math.max(self.cl.beamStopTimer - dt, 0)
		self.cl.line:update( selfPos, self.cl.lastPos, dt, 250, true )

		if self.cl.beamStopTimer <= 0 then
			self.cl.line:stop()
		end
	end

	local max = active and (hit and 1 or 0.5) or 0
	self.cl.boltValue = sm.util.lerp(self.cl.boltValue, max, dt * 10)

	if self.cl.boltValue ~= self.cl.prevBoltValue then
		self.interactable:setPoseWeight( 0, self.cl.boltValue )
		self.cl.prevBoltValue = self.cl.boltValue
	end
end

function MountedLaserCutter:client_onDestroy()
	self.cl.line:stop()
	self.cl.gui:close()
end



function MountedLaserCutter:shouldFire()
	local parents = self.interactable:getParents()
	for k, parent in pairs(parents) do
		if parent.active then
			return true
		end
	end

	return false
end