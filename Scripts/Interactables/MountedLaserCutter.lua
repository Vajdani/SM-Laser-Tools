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
MountedLaserCutter.connectionInput = sm.interactable.connectionType.logic + connectionType_plasma
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

local barrelAdjust = sm.vec3.new(0,-0.02,0.278)
local on = "#269e44On"
local off = "#9e2626Off"

function MountedLaserCutter:server_onCreate()
	self.sv = {}
	self.sv_data = self.storage:load()
	if self.sv_data == nil then
		self.sv_data = {}
		self.sv_data.damage = self.defaultDamage
		self.sv_data.range = self.defaultRange
		self.sv_data.line = false
	end

	self:sv_updateGui({ dmg = self.sv_data.damage, range = self.sv_data.range, line = self.sv_data.line })

	self.sv_unitDamageTimer = Timer()
	self.sv_unitDamageTimer:start( self.unitDamageTicks )

	self.sv_parentCount = -1
	self.sv_containers = {}
	self:getInputs(false)
end

function MountedLaserCutter:server_onFixedUpdate()
	local active = self:getInputs(false)
	if not active then return end

	local shape = self.shape
	local selfDir = GetAccurateShapeUp(shape)
	local selfPos = GetAccurateShapePosition(shape) + self.shape.worldRotation * barrelAdjust
	local endPos = selfPos + selfDir * self.sv_data.range
	local hit, result = sm.physics.raycast( selfPos, endPos )

	if not hit then return end

	local hitPos = result.pointWorld
	local target = result:getShape() or result:getCharacter() or result:getHarvestable()
	if not target or not sm.exists(target) then return end

	self:sv_fire(target, hitPos, result)
end

function MountedLaserCutter:sv_fire(target, hitPos, result)
	local _type = type(target)
	local isChar = _type == "Character"
	if isChar and not self.sv_unitDamageTimer:done() then
		self.sv_unitDamageTimer:tick()
		return
	end

	if sm.game.getEnableAmmoConsumption() then
		local spent = false
		for k, container in pairs(self.sv_containers) do
			if container:canSpend(plasma, 1) then
				sm.container.beginTransaction()
				sm.container.spend(container, plasma, 1)
				sm.container.endTransaction()
				spent = true
				break
			end
		end

		if not spent then return end
	end

	if _type == "Shape" then
		local data = sm.item.getFeatureData(target.uuid)
		if data and data.classname == "Package" then
			sm.event.sendToInteractable( target.interactable, "sv_e_open" )
		else
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
		end
	elseif isChar then
		self.sv_unitDamageTimer:reset()
		sm.projectile.shapeProjectileAttack(
			projectile_cutter,
			self.sv_data.damage,
			self.shape:transformPoint(hitPos),
			self.shape.yAxis,
			self.shape
		)
	else
		sm.physics.explode( hitPos, 3, 1, 1, 1 )
	end
end

function MountedLaserCutter:sv_updateGui( args )
	self.sv_data.damage = args.dmg
	self.sv_data.range = args.range
	self.sv_data.line = args.line
	self.storage:save( self.sv_data )

	self.network:sendToClients( "cl_updateGui", args )
end



function MountedLaserCutter:client_onCreate()
	self.cl_boltValue = 0.0

	self.cl_damage = self.defaultDamage
	self.cl_range = self.defaultRange

	self.cl_gui = sm.gui.createGuiFromLayout( "$CONTENT_DATA/Gui/Mounted.layout", false )
	self.cl_gui:setTextChangedCallback( "input_dmg", "cl_input_dmg" )
	self.cl_gui:setTextChangedCallback( "input_range", "cl_input_range" )
	self.cl_gui:setIconImage( "icon", self.shape.uuid )
	self.cl_gui:setButtonCallback( "laser", "cl_input_laser" )
	self.cl_gui:setText( "laser", off )

	self.cl_line = Line_cutter()
	self.cl_line:init( self.lineThickness, self.shape.color, 0.4 )
	self.cl_lineAlways = false
	self.cl_activeSound = sm.effect.createEffect( "Cutter_active_sound", self.interactable )

	self.cl_lastPos = sm.vec3.zero()
	self.cl_beamStopTimer = self.beamStopSeconds
end

function MountedLaserCutter:cl_input_dmg( widget, value )
	local num = tonumber(value)
	if num == nil then
		if value ~= "" then
			self.cl_gui:setText( "input_dmg", tostring(self.cl_damage) )
			sm.audio.play("RaftShark")
		end
		return
	end

	self.cl_damage = num
	self.network:sendToServer("sv_updateGui", { dmg = self.cl_damage, range = self.cl_range, line = self.cl_lineAlways })
end

function MountedLaserCutter:cl_input_range( widget, value )
	local num = tonumber(value)
	if num == nil then
		if value ~= "" then
			self.cl_gui:setText( "input_range", tostring(self.cl_range) )
			sm.audio.play("RaftShark")
		end
		return
	end

	self.cl_range = num
	self.network:sendToServer("sv_updateGui", { dmg = self.cl_damage, range = self.cl_range, line = self.cl_lineAlways })
end

function MountedLaserCutter:cl_input_laser()
	self.network:sendToServer("sv_updateGui", { dmg = self.cl_damage, range = self.cl_range, line = not self.cl_lineAlways })
end

function MountedLaserCutter:cl_updateGui( args )
	self.cl_damage = args.dmg
	self.cl_range = args.range
	self.cl_lineAlways = args.line

	self.cl_gui:setText( "input_dmg", tostring(self.cl_damage) )
	self.cl_gui:setText( "input_range", tostring(self.cl_range) )
	self.cl_gui:setText( "laser", self.cl_lineAlways and on or off )
end

function MountedLaserCutter:client_onInteract( char, state )
	if not state then return end

	self.cl_gui:setText( "input_dmg", tostring(self.cl_damage) )
	self.cl_gui:setText( "input_range", tostring(self.cl_range) )
	self.cl_gui:open()
end

function MountedLaserCutter:client_onUpdate( dt )
	local active = self:getInputs(true)
	local hit, result = false, nil
	local shape = self.shape
	local selfDir = GetAccurateShapeUp(shape)
	local selfPos = GetAccurateShapePosition(shape) + self.shape.worldRotation * barrelAdjust
	local target

	if active then
		if not self.cl_activeSound:isPlaying() then
			self.cl_activeSound:start()
		end

		local endPos = selfPos + selfDir * self.cl_range
		hit, result = sm.physics.raycast( selfPos, endPos )

		target = result:getShape() or result:getCharacter()

		if hit and target then
			self.cl_lastPos = result.pointWorld
			self.cl_beamStopTimer = self.beamStopSeconds
			self.cl_line:update( selfPos, result.pointWorld, dt, 250, false )
		elseif self.cl_lineAlways then
			self.cl_lastPos = endPos
			self.cl_beamStopTimer = self.beamStopSeconds
			self.cl_line:update( selfPos, hit and result.pointWorld or endPos, dt, 250, false )
		end
	elseif self.cl_activeSound:isPlaying() then
		self.cl_activeSound:stop()
	end

	if (not active or not hit or not target) and self.cl_line.effect:isPlaying() then
		self.cl_beamStopTimer = math.max(self.cl_beamStopTimer - dt, 0)
		self.cl_line:update( selfPos, self.cl_lastPos, dt, 250, true )

		if self.cl_beamStopTimer <= 0 then
			self.cl_line:stop()
		end
	end

	local max = active and (hit and 1 or 0.5) or 0
	self.cl_boltValue = sm.util.lerp(self.cl_boltValue, max, dt * 10)

	if self.cl_boltValue ~= self.cl_prevBoltValue then
		self.interactable:setPoseWeight( 0, self.cl_boltValue )
		self.cl_prevBoltValue = self.cl_boltValue
	end

	local col = self.shape.color
	if self.cl_line.colour ~= col then
		self.cl_line.colour = col
		self.cl_line.effect:setParameter("color", col)
	end
end

function MountedLaserCutter:client_onDestroy()
	self.cl_line:stop()
	self.cl_gui:close()
end



function MountedLaserCutter:getInputs(client)
	local parents = self.interactable:getParents()
	local active, hasChecked = false, false
	local containers = {}

	for k, parent in pairs(parents) do
		if parent.active then active = true end

		if not client and parent:hasOutputType(connectionType_plasma)
		   and (self.shape.body:hasChanged(sm.game.getServerTick() - 1) or #parents ~= self.sv_parentCount) and not hasChecked then
			local parentShape = parent.shape
			containers[parentShape.id] = parentShape.interactable:getContainer(0)
			checkPipedNeighbours(parentShape, containers)

			self.sv_containers = containers
			self.sv_parentCount = #parents
			hasChecked = true
		end
	end

	return active
end