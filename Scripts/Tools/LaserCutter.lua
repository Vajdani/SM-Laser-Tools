dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile "$CONTENT_DATA/Scripts/util.lua"

---@class Cutter : ToolClass
---@field owner Player
---@field unitDamageTimer table
---@field line table
---@field firing boolean
---@field fpAnimations table
---@field tpAnimations table
---@field normalFireMode table
---@field activeSound Effect
---@field cutVisualization Effect
---@field isLocal boolean
---@field blendTime number
---@field cutSize number
Cutter = class()
Cutter.beamLength = 15
Cutter.lineThickness_fp = 0.075
Cutter.lineThickness_tp = 0.2
Cutter.lineColour = sm.color.new(0,1,1)
Cutter.lineSpinSpeed = 250
Cutter.lineShrink = 0.4
Cutter.unitDamageTicks = 10
Cutter.maxCutSize = 7

local camOffsetTp = sm.vec3.new( 0.65, 0.0, 0.05 )
local camOffsetFp = vec3_zero

local renderables = {
    "$CONTENT_DATA/Tools/LaserCutter/char_lasercutter.rend",
}
local renderablesTp = {
    "$CONTENT_DATA/Tools/LaserCutter/Animations/char_male_tp_lasercutter.rend",
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
	self.firing = false
	self.activeSound = sm.effect.createEffect( "Cutter_active_sound", self.owner.character )
	self.line = Line_cutter()
	self.line:init( self.isLocal and self.lineThickness_fp or self.lineThickness_tp, self.lineColour, self.lineShrink )
	self.lastPos = vec3_zero

	self:loadAnimations()

	if not self.isLocal then return end

	self.unitDamageTimer = Timer()
	self.unitDamageTimer:start( self.unitDamageTicks )
	self.cutSize = 1

	self.cutVisualization = sm.effect.createEffect( "ShapeRenderable" )
	self.cutVisualization:setParameter("visualization", true)
end

function Cutter:client_onDestroy()
	if sm.exists(self.cutVisualization) then
		self.cutVisualization:destroy()
	end
end

function Cutter:server_onCreate()
	if true then return end

	sm.container.beginTransaction()
	sm.container.collect(self.tool:getOwner():getHotbar(), sm.uuid.new("3f5c15b0-d0a6-4ee3-a178-5643a61402cf"), 1)
	sm.container.collect(self.tool:getOwner():getHotbar(), sm.uuid.new("704fdad0-99bf-45a7-b24e-dfbeb028b54f"), 1)
	sm.container.endTransaction()
end

function Cutter:client_onReload()
	if self.cutSize == self.maxCutSize then return true end

	self.cutSize = math.min(self.cutSize + 2, self.maxCutSize)
	sm.gui.displayAlertText("Cutting Size: #df7f00"..tostring(self.cutSize), 2.5)
	sm.audio.play("PaintTool - ColorPick")

	return true
end

function Cutter:client_onToggle()
	if self.cutSize == 1 then return true end

	self.cutSize = math.max(self.cutSize - 2, 1)
	sm.gui.displayAlertText("Cutting Size: #df7f00"..tostring(self.cutSize), 2.5)
	sm.audio.play("PaintTool - ColorPick")

	return true
end

function Cutter:sv_updateFiring( firing )
	self.network:sendToClients( "cl_updateFiring", firing )
end

function Cutter:cl_updateFiring( firing )
	self.firing = firing
end



function Cutter:cl_getBeamStart(dt)
	local char = self.owner.character
	return self.tool:isInFirstPersonView() and
	self.tool:getFpBonePos( "pipe" ) - char.direction * 0.15 * ((sm.camera.getFov() - 45) / 45) + char.velocity * (dt or 0.015) or
	self.tool:getTpBonePos( "pipe" )
end

function Cutter:canFire(_type, target)
	if not sm.game.getEnableAmmoConsumption() then return true, 0 end

	if not sm.exists(target) then return false, 0 end

	local container = sm.localPlayer.getInventory()
	local quantity = (_type == "Shape" and sm.item.isBlock(target.uuid)) and self.cutSize^2 or 1
	return container:canSpend(plasma, quantity), quantity
end

function Cutter:cl_updateDyingBeam( dt )
	local beamStart = self:cl_getBeamStart(dt)
	self.line:update( beamStart, self.lastPos, dt, self.lineSpinSpeed, true )

	if self.line.currentThickness <= 0 then
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
	local hit = false
	local result, target

	if self.isLocal then
		local isFP = self.tool:isInFirstPersonView()
		if isFP ~= self.isFP then
			self.isFP = isFP
			self.line.thickness = isFP and self.lineThickness_fp or self.lineThickness_tp
		end
	end

	if self.firing then
		if not self.activeSound:isPlaying() then
			self.activeSound:start()
		end

		local raycastStart = playerPos + (playerChar:isCrouching() and camAdjust_crouch or camAdjust)
		hit, result = sm.physics.raycast( raycastStart, raycastStart + playerDir * self.beamLength, playerChar )

		if hit then
			target = result:getShape() or result:getCharacter() or result:getHarvestable() or result:getJoint()
			if target and sm.exists(target) then
				local uuid = type(target) == "Character" and target:getCharacterType() or target.uuid
				if ShouldLaserSkipTarget(uuid) then
					target = nil
					goto skip
				end

				local beamEnd =  result.pointWorld
				self.line:update( self:cl_getBeamStart(dt), beamEnd, dt, self.lineSpinSpeed, false )
				self.lastPos = beamEnd
				if self.isLocal then self.normal = result.normalLocal end
			end

			::skip::
		end
	else
		self.activeSound:stop()

		if self.isLocal and self.line.effect:isPlaying() then
			self.unitDamageTimer:reset()
		end
		self.line:stop()
	end

	if (not hit or not target) and self.line.effect:isPlaying() then
		self:cl_updateDyingBeam(dt)
	end

	return target
end

function Cutter:sv_cut( args )
	---@type Shape
	local shape = args.shape
	if not sm.exists(shape) then return end

	local uuid = shape.uuid
	if ShouldLaserSkipTarget(uuid) then return end

	if sm.item.isHarvestablePart(uuid) then
		sm.event.sendToInteractable(shape.interactable, "sv_onHit", 1000)
		return
	end

	local classname = (sm.item.getFeatureData(uuid) or {}).classname
	if classname == "Package" then
		sm.event.sendToInteractable( shape.interactable, "sv_e_open" )
	elseif IsExplosiveClass(classname) then
		sm.event.sendToInteractable( shape.interactable, "server_tryExplode" )
	else
		---@type Vec3
		local pos = args.pos
		---@type Vec3
		local normal = args.normal
		local material = shape.materialId
		local effectRot = sm.vec3.getRotation( vec3_up, normal )
		local effectData = { Material = material, Color = shape.color }

		if sm.item.isBlock(uuid) then
			normal = RoundVector(normal)
			local cutSize = args.size
			local size = vec3_one * cutSize - AbsVector(normal) * (cutSize - 1)
			local destroyPos = pos - (size + normal) * (1 / 12)
			shape:destroyBlock(shape:getClosestBlockLocalPosition(destroyPos), size)
		else
			local int = shape.interactable
			if not int or int.type ~= "scripted" or not sm.event.sendToInteractable(int, "sv_e_onHit", {
				damage = 45,
				source = self.tool:getOwner(),
				position = args.pos,
				normal = args.normal
			}) then
				shape:destroyShape()
			end
		end

		sm.effect.playEffect( "Sledgehammer - Destroy", pos, vec3_zero, effectRot, vec3_one, effectData )
	end

	self:sv_consumeAmmo(args.ammo)
end

function Cutter:sv_damageHarvestable( args )
	local target, pos = args.target, args.pos
	if not sm.event.sendToHarvestable(target, "sv_e_onHit", { damage = 1000, position = pos }) then
		sm.physics.explode( pos, 3, 1, 1, 1 )
	end

	self:sv_consumeAmmo(args.ammo)
end

function Cutter:sv_consumeAmmo(ammo)
	if sm.game.getEnableAmmoConsumption() then
		sm.container.beginTransaction()
		sm.container.spend(self.tool:getOwner():getInventory(), plasma, ammo)
		sm.container.endTransaction()
	end
end

function Cutter:sv_damageCharacter(char)
	SendDamageEventToCharacter(char, { damage = 45 })
	self:sv_consumeAmmo(1)
end



function Cutter:client_onFixedUpdate()
	if not self.isLocal or not self.tool:isEquipped() then return end

	local target = self.target
	if target and sm.exists(target) then
		local beamEnd = self.lastPos
		local _type = type(target)
		local canFire, ammo = self:canFire(_type, target)
		if canFire then
			if _type == "Shape" or _type == "Joint" then
				self.network:sendToServer( "sv_cut",
					{
						shape = _type == "Joint" and target.shapeA or target,
						pos = beamEnd,
						normal = self.normal,
						size = self.cutSize,
						ammo = ammo
					}
				)
			elseif _type == "Character" then
				self.unitDamageTimer:tick()
				if self.unitDamageTimer:done() then
					self.unitDamageTimer:reset()
					self.network:sendToServer( "sv_damageCharacter", target )
				end
			else
				self.unitDamageTimer:tick()
				if self.unitDamageTimer:done() then
					self.unitDamageTimer:reset()
					self.network:sendToServer( "sv_damageHarvestable", { target = target, pos = beamEnd, ammo = ammo } )
				end
			end
		end
	end
end

function Cutter:client_onUpdate(dt)
	self.target = self:cl_cut(dt)
	local isSprinting = self.tool:isSprinting()
	local isCrouching = self.tool:isCrouching()
	local equipped    = self.tool:isEquipped()

	if self.isLocal then
		self:updateFP(dt, equipped, self.target, isSprinting, isCrouching)
	end

	local crouchWeight = self.tool:isCrouching() and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight
	self:updateTP(dt, equipped, crouchWeight, normalWeight)
	self:updateSpine(dt, isCrouching, isSprinting, crouchWeight, normalWeight)

	self.tool:updateCamera( 2.8, 0, camOffsetTp, 0 )
	self.tool:updateFpCamera( 0, camOffsetFp, 0, 1 )
end

function Cutter:updateFP(dt, equipped, target, isSprinting, isCrouching)
	if equipped then
		if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
			swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
		elseif not isSprinting and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
			swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
		end

		if self.firing and self.fpAnimations.currentAnimation ~= "use_idle" then
			setFpAnimation( self.fpAnimations, "use_idle", 0.2 )
		elseif not self.firing and self.fpAnimations.currentAnimation == "use_idle" then
			setFpAnimation( self.fpAnimations, "idle", 0.5 )
		end

		local canAfford = not sm.game.getEnableAmmoConsumption() or self:cl_displayAmmo()
		local canDisplay = false
		if canAfford then
			local rayStart, rayDir = sm.localPlayer.getRaycastStart(), sm.localPlayer.getDirection()
			local hit, result = sm.physics.raycast(rayStart, rayStart + rayDir * self.beamLength, self.owner.character, sm.physics.filter.default + sm.physics.filter.areaTrigger) --sm.localPlayer.getRaycast(self.beamLength)
			local _target = result:getShape()
			canDisplay = _target ~= nil --and _target.erasable

			if canDisplay then
				local normal = result.normalLocal
				local uuid = _target.uuid
				local isBlock = sm.item.isBlock(uuid)
				if uuid ~= self.cutVisualizationUUID then
					self.cutVisualization:stop()
					if isBlock then
						uuid = blk_plastic
					end

					self.cutVisualization:setParameter("uuid", uuid)
					self.cutVisualizationUUID = uuid
				end

				if isBlock then
					self.cutVisualization:setScale((vec3_one * self.cutSize - RoundVector(AbsVector(normal)) * (self.cutSize - 1)) * 0.25)
					self.cutVisualization:setPosition(getClosestBlockGlobalPosition(_target, result.pointWorld))
				else
					if sm.item.isPart(uuid) then
						self.cutVisualization:setScale(sm.vec3.one() * 0.25)
					else
						self.cutVisualization:setScale(_target:getBoundingBox())
					end

					self.cutVisualization:setPosition(_target:getInterpolatedWorldPosition() + _target.velocity * dt)
				end
				self.cutVisualization:setRotation(_target.worldRotation)

				if not self.cutVisualization:isPlaying() then self.cutVisualization:start() end
			end
		end

		if not (canAfford and canDisplay) and self.cutVisualization:isPlaying() then
			self.cutVisualization:stop()
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
	local spreadFactor = self.firing and 0.25 or 0
	spreadFactor = target ~= nil and spreadFactor * 2 or spreadFactor
	self.tool:setDispersionFraction( sm.util.clamp( self.movementDispersion + spreadFactor, 0.0, 1.0 ) )
	self.tool:setCrossHairAlpha( 1.0 )
	self.tool:setInteractionTextSuppressed( false )
end

function Cutter:updateTP(dt, equipped, crouchWeight, normalWeight)
	if equipped then
		if self.firing and self.tpAnimations.currentAnimation ~= "use_idle" then
			setTpAnimation( self.tpAnimations, "use_idle", 10 )
		elseif not self.firing and self.tpAnimations.currentAnimation == "use_idle" then
			setTpAnimation( self.tpAnimations, "idle", 2.5 )
		end
	end

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
end

function Cutter:updateSpine(dt, isCrouching, isSprinting, crouchWeight, normalWeight)
	-- Third Person joint lock
	local playerDir = self.tool:getSmoothDirection()
	local angle = math.asin( playerDir:dot( sm.vec3.new( 0, 0, 1 ) ) ) / ( math.pi / 2 )
	local relativeMoveDirection = self.tool:getRelativeMoveDirection()
	if ( ( ( self.tpAnimations.currentAnimation == "shoot" and ( relativeMoveDirection:length() > 0 or isCrouching) ) ) and not isSprinting ) then
		self.jointWeight = math.min( self.jointWeight + ( 10.0 * dt ), 1.0 )
	else
		self.jointWeight = math.max( self.jointWeight - ( 6.0 * dt ), 0.0 )
	end

	if ( not isSprinting ) then
		self.spineWeight = math.min( self.spineWeight + ( 10.0 * dt ), 1.0 )
	else
		self.spineWeight = math.max( self.spineWeight - ( 10.0 * dt ), 0.0 )
	end

	local finalAngle = ( 0.5 + angle * 0.5 )
	self.tool:updateAnimation( "spudgun_spine_bend", finalAngle, self.spineWeight )

	local totalOffsetZ = sm.util.lerp( -22.0, -26.0, crouchWeight )
	local totalOffsetY = sm.util.lerp( 6.0, 12.0, crouchWeight )
	local crouchTotalOffsetX = sm.util.clamp( ( angle * 60.0 ) -15.0, -60.0, 40.0 )
	local normalTotalOffsetX = sm.util.clamp( ( angle * 50.0 ), -45.0, 50.0 )
	local totalOffsetX = sm.util.lerp( normalTotalOffsetX, crouchTotalOffsetX , crouchWeight )
	local finalJointWeight = ( self.jointWeight )

	self.tool:updateJoint( "jnt_hips", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.35 * finalJointWeight * ( normalWeight ) )
	local crouchSpineWeight = ( 0.35 / 3 ) * crouchWeight
	self.tool:updateJoint( "jnt_spine1", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight )  * finalJointWeight )
	self.tool:updateJoint( "jnt_spine2", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_spine3", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.45 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_head", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.3 * finalJointWeight )
end



function Cutter:client_onEquip( animate )
	if animate then
		sm.audio.play( "ConnectTool - Equip", self.tool:getPosition() )
	end

	self.jointWeight = 0.0

	local currentRenderablesTp = {}
	local currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do
		currentRenderablesTp[#currentRenderablesTp+1] = v
		currentRenderablesFp[#currentRenderablesFp+1] = v
	end

	local col = sm.color.new("#ff0008")
	self.tool:setTpRenderables( currentRenderablesTp )
	self.tool:setTpColor(col)
	if self.isLocal then
		self.tool:setFpRenderables( currentRenderablesFp )
		self.tool:setFpColor(col)
		self.target = nil
		self.normal = vec3_zero
	end

	self:loadAnimations()
	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.isLocal then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function Cutter:client_onUnequip( animate )
	self.line.effect:stopImmediate()
	self.firing = false

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

			self.target = nil
			self.normal = vec3_zero
			self.cutVisualization:stop()
		end
	end
end

function Cutter:client_onEquippedUpdate( lmb )
	local firing = lmb == 1 or lmb == 2
	if firing ~= self.firing then
		self.network:sendToServer("sv_updateFiring", firing)
	end

	return true, true
end

local interactionText = "<img bg='gui_keybinds_bg' spacing='4'>gui_icon_refill_battery.png</img>".."<p textShadow='false' bg='gui_keybinds_bg' color='#ffffff' spacing='9'>%d / %d</p>"
function Cutter:cl_displayAmmo()
	local container = sm.localPlayer.getInventory()
	local plasmaCount = sm.container.totalQuantity(container, plasma)
	local plasmaNeeded = self.cutSize^2
	sm.gui.setInteractionText(interactionText:format(plasmaCount, plasmaNeeded))

	return plasmaCount >= plasmaNeeded
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
	self.blendTime = 0.2
	self.jointWeight = 0.0
	self.spineWeight = 0.0
end