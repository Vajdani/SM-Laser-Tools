dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

---@class Cutter : ToolClass
---@field owner Player
---@field beamStopTimer table
---@field unitDamageTimer table
---@field line table
---@field inputStates table
---@field fpAnimations table
---@field tpAnimations table
---@field normalFireMode table
---@field activeSound Effect
---@field isLocal boolean
---@field blendTime number
---@field aimBlendSpeed number
---@field aimWeight number
---@field cutSize number
Cutter = class()
Cutter.cuttableObjs = {
	blk_scrapmetal,
	blk_metal1,
	blk_metal2,
	blk_metal3,
}
Cutter.beamLength = 15^2 --15 meters, the script uses vec3:length2() instead of vec3:length() because its faster
Cutter.lineStats = {
	thickness = 0.05,
	colour = sm.color.new(0,1,1),
	spinSpeed = 250
}
Cutter.beamStopTicks = 40
Cutter.unitDamageTicks = 10

local renderables = {
    "$CONTENT_DATA/Tools/LaserCutter/char_cuttertool.rend",
}
local renderablesTp = {
    "$GAME_DATA/Character/Char_Male/Animations/char_male_tp_connecttool.rend",
    "$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool_tp_animlist.rend"
}
local renderablesFp = {
    "$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool_fp_animlist.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function Cutter.client_onCreate( self )
	self.isLocal = self.tool:isLocal()
	self.owner = self.tool:getOwner()
	self.inputStates = {
		primaryState = 0,
		secondaryState = 0
	}
	self.activeSound = sm.effect.createEffect( "Cutter_active_sound", self.owner.character )
	self.line = Line_cutter()
	self.line:init( self.lineStats.thickness, self.lineStats.colour )
	self.beamStopTimer = Timer()
	self.beamStopTimer:start( self.beamStopTicks )
	self.beamStopTimer.count = self.beamStopTimer.ticks
	self.lastPos = sm.vec3.zero()

	self:loadAnimations()

	if not self.isLocal then return end

	self.unitDamageTimer = Timer()
	self.unitDamageTimer:start( self.unitDamageTicks )
	self.cutSize = 1
end


function Cutter:client_onReload()
	--self.cutSize = self.cutSize + 2
	--sm.gui.displayAlertText(tostring(self.cutSize), 2.5)

	return true
end

function Cutter:client_onToggle()
	--self.cutSize = math.max(self.cutSize - 2, 1)
	--sm.gui.displayAlertText(tostring(self.cutSize), 2.5)

	return true
end


function Cutter:cl_getBeamStart()
	local char = self.owner.character
	return self.tool:isInFirstPersonView() and
	self.tool:getFpBonePos( "pipe" ) - char.direction * 0.15 or
	self.tool:getTpBonePos( "pipe" )
end

function Cutter:cl_updateDyingBeam( dt )
	self.beamStopTimer:tick()
	local beamStart = self:cl_getBeamStart()
	self.line:update( beamStart, self.lastPos, dt, self.lineStats.spinSpeed )

	if self.beamStopTimer:done() then
		self.line:stop()
	end
end

function Cutter:cl_cut( dt )
	if not self.activeSound or not sm.exists(self.activeSound) then
		self.activeSound = sm.effect.createEffect( "Cutter_active_sound", self.owner.character )
	end

	local playerChar = self.owner.character
	local playerPos = playerChar.worldPosition
	local playerDir = playerChar.direction
	local firing = isAnyOf(self.inputStates.primaryState, {sm.tool.interactState.start, sm.tool.interactState.hold}) and self.tool:isEquipped()
	local hit = false
	local result, target

	if firing then
		if not self.activeSound:isPlaying() then
			self.activeSound:start()
		end

		local raycastStart = playerPos + camAdjust
		hit, result = sm.physics.raycast( raycastStart, raycastStart + playerDir * self.beamLength, playerChar )

		if hit and (result.pointWorld - playerPos):length2() <= self.beamLength then
			target = result:getShape() or result:getCharacter() or result:getHarvestable()

			if target then
				local beamEnd =  result.pointWorld
				self.line:update( self:cl_getBeamStart(), beamEnd, dt, self.lineStats.spinSpeed )

				self.lastPos = beamEnd
				self.beamStopTimer:reset()

				if self.isLocal then
					local type = type(target)
					if type == "Shape" then
						self.network:sendToServer( "sv_cut",
							{
								shape = target,
								pos = beamEnd,
								normal = result.normalWorld,
								size = self.cutSize
							}
						)
					elseif type == "Character" then
						self.unitDamageTimer:tick()

						if self.unitDamageTimer:done() then
							self.unitDamageTimer:reset()
							sm.projectile.projectileAttack(
								projectile_potato,
								45,
								beamEnd,
								(target.worldPosition - beamEnd),
								self.owner
							)
						end
					else
						self.network:sendToServer( "sv_explode", beamEnd)
					end
				end
			end
		end
	else
		--for some fucking reason, if I dont stop this multiple times, it wont stop
		self.activeSound:stop()

		if self.line.effect:isPlaying() then
			self.line:stop()
			self.beamStopTimer.count = self.beamStopTimer.ticks

			if self.isLocal then
				self.unitDamageTimer:reset()
			end
		end
	end

	if (not hit or not target or (result.pointWorld - playerPos):length2() <= self.beamLength) and self.line.effect:isPlaying() then
		self:cl_updateDyingBeam(dt)
	end

	return firing, target
end

function Cutter:sv_cut( args )
	---@type Shape
	local shape = args.shape
	if sm.exists(shape) then
		---@type Vec3
		local pos = args.pos
		---@type Vec3
		local normal = args.normal
		local material = shape:getMaterialId()
		local effectRot = sm.vec3.getRotation( sm.vec3.new(0,0,1), normal )
		local effectData = { Material = material }
		--local shapeRot = shape.worldRotation

    	if sm.item.isBlock( shape.uuid ) then
			--[[local rot = sm.vec3.getRotation(sm.vec3.new(1, 0, 0), normal) * sm.quat.fromEuler(sm.vec3.new(0, 0, 90))
			local size = args.size
			local size_vec3 = rot * sm.vec3.new(size, 1, size)
			size_vec3.x = sm.util.clamp(math.ceil(size_vec3.x), 1, size)
			size_vec3.y = sm.util.clamp(math.ceil(size_vec3.y), 1, size)
			size_vec3.z = sm.util.clamp(math.ceil(size_vec3.z), 1, size)]]

			local destroyPos = pos --- (shapeRot * (size_vec3/12))
			shape:destroyBlock( shape:getClosestBlockLocalPosition(destroyPos), vec3_one --[[size_vec3]] )

			--[[for i = 0, size_vec3.x - 1 do
				for j = 0, size_vec3.y - 1 do
					for k = 0, size_vec3.z - 1 do]]
						sm.effect.playEffect(
							"Sledgehammer - Destroy",
							destroyPos, --+ (sm.vec3.new(i, j, k) * 0.25),
							vec3_zero,
							effectRot,
							vec3_one,
							effectData
						)
			--[[		end
				end
			end]]
		else
			shape:destroyShape()

			sm.effect.playEffect(
				"Sledgehammer - Destroy",
				pos,
				vec3_zero,
				effectRot,
				vec3_one,
				effectData
			)
		end
	end
end

function Cutter:sv_explode( pos )
	sm.physics.explode( pos, 3, 1, 1, 1 )
end


function Cutter:sv_syncInputs( inputs )
	self.network:sendToClients( "cl_syncInputs", inputs )
end

function Cutter:cl_syncInputs( inputs )
	self.inputStates = inputs
end


function Cutter:client_onFixedUpdate( dt )
	self:cl_cut(dt)
end

function Cutter:client_onUpdate( dt )
	local firing, target = self:cl_cut(dt)

	-- First person animation
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()
	local equipped = self.tool:isEquipped()

	if self.isLocal then
		if equipped then
			if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
				swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
			elseif not isSprinting and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
				swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
			end

			if firing and self.fpAnimations.currentAnimation ~= "use_idle" then
				setFpAnimation( self.fpAnimations, "use_idle", 0.2 )
			elseif not firing and self.fpAnimations.currentAnimation == "use_idle" then
				setFpAnimation( self.fpAnimations, "idle", 0.5 )
			end
		end
		updateFpAnimations( self.fpAnimations, equipped, dt )

		local dispersion = 0.0
		local fireMode = self.normalFireMode
		dispersion = isCrouching and fireMode.minDispersionCrouching or fireMode.minDispersionStanding

		if self.tool:getRelativeMoveDirection():length() > 0 then
			dispersion = dispersion + fireMode.maxMovementDispersion * self.tool:getMovementSpeedFraction()
		end

		if not self.tool:isOnGround() then
			dispersion = dispersion * fireMode.jumpDispersionMultiplier
		end

		self.movementDispersion = dispersion
		local spreadFactor = firing and 0.25 or 0
		spreadFactor = target ~= nil and spreadFactor * 2 or spreadFactor
		self.tool:setDispersionFraction( clamp( self.movementDispersion + spreadFactor, 0.0, 1.0 ) )
		self.tool:setCrossHairAlpha( 1.0 )
		self.tool:setInteractionTextSuppressed( false )
	end

	if equipped then
		if firing and self.tpAnimations.currentAnimation ~= "use_idle" then
			setTpAnimation( self.tpAnimations, "use_idle", 10 )
		elseif not firing and self.tpAnimations.currentAnimation == "use_idle" then
			setTpAnimation( self.tpAnimations, "idle", 2.5 )
		end
	end

	local crouchWeight = self.tool:isCrouching() and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight
	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.time >= animation.info.duration - self.blendTime then
				if name == "pickup" then
					setTpAnimation( self.tpAnimations, "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 0.001 )
				end
			end
		else
			animation.weight = math.max( animation.weight - ( self.tpAnimations.blendSpeed * dt ), 0.0 )
		end

		totalWeight = totalWeight + animation.weight
	end

	totalWeight = totalWeight == 0 and 1.0 or totalWeight
	for name, animation in pairs( self.tpAnimations.animations ) do
		local weight = animation.weight / totalWeight
		if name == "idle" then
			self.tool:updateMovementAnimation( animation.time, weight )
		elseif animation.crouch then
			self.tool:updateAnimation( animation.info.name, animation.time, weight * normalWeight )
			self.tool:updateAnimation( animation.crouch.name, animation.time, weight * crouchWeight )
		else
			self.tool:updateAnimation( animation.info.name, animation.time, weight )
		end
	end

	-- Camera update
	local blend = 1 - ( (1 - 1 / self.aimBlendSpeed) ^ (dt * 60) )
	self.aimWeight = sm.util.lerp( self.aimWeight,  0, blend )
	local bobbing =  1

	local fov = sm.camera.getDefaultFov() / 3
	self.tool:updateCamera( 2.8, fov, sm.vec3.new( 0.65, 0.0, 0.05 ), self.aimWeight )
	self.tool:updateFpCamera( fov, sm.vec3.new( 0.0, 0.0, 0.0 ), self.aimWeight, bobbing )
end

function Cutter.client_onEquip( self, animate )
	if animate then
		sm.audio.play( "ConnectTool - Equip", self.tool:getPosition() )
	end

	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	local currentRenderablesTp = {}
	local currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	self:loadAnimations()

	self.tool:setTpRenderables( currentRenderablesTp )
	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )

	if self.isLocal then
		-- Sets Cutter renderable, change this to change the mesh
		self.tool:setFpRenderables( currentRenderablesFp )
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function Cutter.client_onUnequip( self, animate )
	self.line.effect:stopImmediate()

	if sm.localPlayer.getPlayer() == self.owner then
		self.inputStates.primaryState = sm.tool.interactState.null
	end

	if sm.exists( self.tool ) then
		if animate then
			sm.audio.play( "ConnectTool - Unequip", self.tool:getPosition() )
		end
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.isLocal then
			self.tool:setMovementSlowDown( false )
			self.tool:setBlockSprint( false )
			self.tool:setCrossHairAlpha( 1.0 )
			self.tool:setInteractionTextSuppressed( false )
			if self.fpAnimations.currentAnimation ~= "unequip" then
				swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
			end
		end
	end
end

function Cutter.client_onEquippedUpdate( self, primaryState, secondaryState )
	local inputStates = { primaryState = primaryState, secondaryState = secondaryState }

	if self.inputStates.primaryState ~= primaryState or self.inputStates.secondaryState ~= secondaryState then
		self.inputStates = inputStates
		self.network:sendToServer("sv_syncInputs", inputStates)
	end

	return true, true
end


function Cutter.loadAnimations( self )
	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "connecttool_idle" },
			use_idle = { "connecttool_use_idle", { looping = true } },

			pickup = { "connecttool_pickup", { nextAnimation = "idle" } },
			putdown = { "connecttool_putdown" },
		}
	)
	local movementAnimations = {
		idle = "connecttool_idle",
		--idleRelaxed = "connecttool_relax",

		sprint = "connecttool_sprint",
		runFwd = "connecttool_run_fwd",
		runBwd = "connecttool_run_bwd",

		jump = "connecttool_jump",
		jumpUp = "connecttool_jump_up",
		jumpDown = "connecttool_jump_down",

		land = "connecttool_jump_land",
		landFwd = "connecttool_jump_land_fwd",
		landBwd = "connecttool_jump_land_bwd",

		crouchIdle = "connecttool_crouch_idle",
		crouchFwd = "connecttool_crouch_fwd",
		crouchBwd = "connecttool_crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	if self.isLocal then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "connecttool_pickup", { nextAnimation = "idle" } },
				unequip = { "connecttool_putdown" },

				idle = { "connecttool_idle", { looping = true } },
				use_idle = { "connecttool_use_idle", { looping = true } },

				sprintInto = { "connecttool_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 0.2 } },
				sprintExit = { "connecttool_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "connecttool_sprint_idle", { looping = true } },
			}
		)
	end

	self.normalFireMode = {
		minDispersionStanding = 0.1,
		minDispersionCrouching = 0.04,

		maxMovementDispersion = 0.4,
		jumpDispersionMultiplier = 2
	}

	self.movementDispersion = 0.0
	self.aimBlendSpeed = 3.0
	self.blendTime = 0.2
	self.jointWeight = 0.0
	self.spineWeight = 0.0
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
end

function Cutter.calculateFirePosition( self )
	local crouching = self.tool:isCrouching()
	local firstPerson = self.tool:isInFirstPersonView()
	local dir = sm.localPlayer.getDirection()
	local pitch = math.asin( dir.z )
	local right = sm.localPlayer.getRight()

	local fireOffset = sm.vec3.new( 0.0, 0.0, 0.0 )

	if crouching then
		fireOffset.z = 0.15
	else
		fireOffset.z = 0.45
	end

	if firstPerson then
		if not isAnyOf(self.inputStates.secondaryState, {sm.tool.interactState.start, sm.tool.interactState.hold}) then
			fireOffset = fireOffset + right * 0.05
		end
	else
		fireOffset = fireOffset + right * 0.25
		fireOffset = fireOffset:rotate( math.rad( pitch ), right )
	end
	local firePosition = GetOwnerPosition( self.tool ) + fireOffset
	return firePosition
end