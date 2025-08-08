dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile "$CONTENT_DATA/Scripts/util.lua"

---@class Pistol : ToolClass
---@field owner Player
---@field fpAnimations table
---@field tpAnimations table
---@field normalFireMode table
---@field isLocal boolean
---@field blendTime number
---@field aimBlendSpeed number
---@field aimWeight number
---@field primaryCooldown table
---@field secondaryCooldown table
---@field overdriveCooldown table
---@field overdriveDuration table
---@field colour Color
---@field shootEffect Effect
---@field poweronEffect Effect
Pistol = class()
Pistol.lineStats = {
	thickness = 0.35,
	colour_weak = sm.color.new(0,1,1),
	colour_strong = sm.color.new(0.75,0,0), --sm.color.new(1,0,0),
	spinSpeed = 250
}
Pistol.cooldowns = {
	primary = 0.25 * 40,
	secondary = 2 * 40,
	overdrive = 10 * 40,
	overdrive_dur = 5 * 40
}
Pistol.defaultColour = sm.color.new("#f4ff00")

local renderables = {
    "$CONTENT_DATA/Tools/LaserPistol/char_laserpistol.rend",
}
local renderablesTp = {
    "$CONTENT_DATA/Tools/LaserPistol/Animations/char_male_tp_laserpistol.rend",
	"$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool_tp_animlist.rend",
}
local renderablesFp = {
    "$CONTENT_DATA/Tools/LaserPistol/Animations/char_male_fp_laserpistol.rend",
    "$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool_fp_animlist.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function Pistol:client_onCreate()
	self.isLocal = self.tool:isLocal()
	self.owner = self.tool:getOwner()

	self.lerpProgress = 1
	self.lerpBlock = false
	self.colour = self.defaultColour
	self.overdriveActive = false

	self.shootEffect = sm.effect.createEffect("Pistol_shoot")
	self.poweronEffect = sm.effect.createEffect("Pistol_overdrive_on")

	self:loadAnimations()

	if not self.isLocal then return end

	self.crosshairSpread = 0

	self.primaryCooldown = Timer()
	self.primaryCooldown:start( self.cooldowns.primary )
	self.primaryCooldown.count = self.primaryCooldown.ticks

	self.secondaryCooldown = Timer()
	self.secondaryCooldown:start( self.cooldowns.secondary )
	self.secondaryCooldown.count = self.secondaryCooldown.ticks


	self.overdriveCooldown = Timer()
	self.overdriveCooldown:start( self.cooldowns.overdrive )
	self.overdriveCooldown.count = self.overdriveCooldown.ticks

	self.overdriveDuration = Timer()
	self.overdriveDuration:start( self.cooldowns.overdrive_dur )
end

function Pistol:client_onReload()
	if self.overdriveActive then return true end

	if self.overdriveCooldown:done() then
		self.overdriveActive = true
		self.network:sendToServer("sv_onOverdriveUpdate", true)

		sm.gui.displayAlertText("#"..self.lineStats.colour_strong:getHexStr():sub(1,6).."Overdrive activated!", 2.5)
	else
		--sm.gui.displayAlertText("Can't activate overdrive yet!", 2.5)
		sm.audio.play("RaftShark")
	end

	return true
end

function Pistol:sv_onOverdriveUpdate(toggle)
	self.network:sendToClients("cl_onOverdriveUpdate", toggle)
end

function Pistol:cl_onOverdriveUpdate(toggle)
	self.overdriveActive = toggle
	self.lerpBlock = toggle
	if self.isLocal then
		self.primaryCooldown.ticks = toggle and self.cooldowns.primary / 2 or self.cooldowns.primary
	end

	if not toggle then return end
	self.lerpProgress = 0
	self.colour = self.lineStats.colour_strong
	self.tool:setTpColor(self.colour)
	if self.isLocal then
		self.tool:setFpColor(self.colour)
	end
	self.poweronEffect:start()
end



function Pistol:client_onFixedUpdate()
	if not self.isLocal then return end

	self.primaryCooldown:tick()
	self.secondaryCooldown:tick()
	self.overdriveCooldown:tick()

	if self.overdriveActive then
		self.overdriveDuration:tick()
		if self.overdriveDuration:done() then
			self.overdriveCooldown:reset()
			self.overdriveDuration:reset()
			self.overdriveActive = false

			self.network:sendToServer("sv_onOverdriveUpdate", false)
		end
	end
end

function Pistol:client_onUpdate( dt )
	if self.lerpProgress <= 1 and not self.lerpBlock then
		self.lerpProgress = self.lerpProgress + dt
		local colour = ColourLerp( self.colour, self.defaultColour, self.lerpProgress )
		self.tool:setFpColor(colour)
		if self.isLocal then
			self.tool:setTpColor(colour)
		end
	end

	-- First person animation
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()
	local equipped = self.tool:isEquipped()

	if self.isLocal then
		self:updateFP(dt, equipped, isSprinting, isCrouching)
	end

	if equipped then
		self.shootEffect:setRotation( sm.vec3.getRotation(vec3_up, self.tool:getDirection()) )
		self.shootEffect:setPosition( self.tool:isInFirstPersonView() and self.tool:getFpBonePos( "pipe" ) or self.tool:getTpBonePos( "pipe" ) )
		self.poweronEffect:setPosition( self.tool:getPosition() )
	end

	local crouchWeight = self.tool:isCrouching() and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight
	self:updateTP(dt, crouchWeight, normalWeight)
	self:updateSpine(dt, isCrouching, isSprinting, crouchWeight, normalWeight)
	self:updateCam(dt)
end

function Pistol:updateFP(dt, equipped, isSprinting, isCrouching)
	if equipped then
		if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
			swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
		elseif not isSprinting and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
			swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
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
	self.crosshairSpread = math.max(self.crosshairSpread - dt, 0 )
	self.tool:setDispersionFraction( sm.util.clamp( self.movementDispersion + self.crosshairSpread, 0.0, 1.0 ) )
end

function Pistol:updateTP(dt, crouchWeight, normalWeight)
	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.time >= animation.info.duration - self.blendTime then
				if name == "pickup" then
					setTpAnimation( self.tpAnimations, "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 10 )
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

function Pistol:updateSpine(dt, isCrouching, isSprinting, crouchWeight, normalWeight)
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

function Pistol:updateCam(dt)
	local blend = 1 - ( (1 - 1 / self.aimBlendSpeed) ^ (dt * 60) )
	self.aimWeight = sm.util.lerp( self.aimWeight, 0, blend )
	local bobbing = 1

	local fov = sm.camera.getDefaultFov() / 3
	self.tool:updateCamera( 2.8, fov, sm.vec3.new( 0.65, 0.0, 0.05 ), self.aimWeight )
	self.tool:updateFpCamera( fov, sm.vec3.new( 0.0, 0.0, 0.0 ), self.aimWeight, bobbing )
end


function Pistol:client_onEquip( animate )
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
	for k,v in pairs( renderables ) do
		currentRenderablesTp[#currentRenderablesTp+1] = v
		currentRenderablesFp[#currentRenderablesFp+1] = v
	end

	self.tool:setTpRenderables( currentRenderablesTp )
    if self.isLocal then
        self.tool:setFpRenderables( currentRenderablesFp )
    end

	self:loadAnimations()
	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.isLocal then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end

	self.lerpProgress = 1
	self.colour = self.defaultColour
	self.tool:setFpColor(self.colour)
	if self.isLocal then
		self.tool:setTpColor(self.colour)
	end
end

function Pistol:client_onUnequip( animate )

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

local interactionText = "<img bg='gui_keybinds_bg' spacing='4'>gui_icon_refill_battery.png</img>".."<p textShadow='false' bg='gui_keybinds_bg' color='#ffffff' spacing='9'>%d / %d</p>"
local totalQuantity = sm.container.totalQuantity
function Pistol:client_onEquippedUpdate( lmb, rmb )
	if self.overdriveActive then
		sm.gui.setProgressFraction( 1 - (self.overdriveDuration.count / self.overdriveDuration.ticks) )
	end

	local primary = lmb == 1 or lmb == 2
	local secondary = rmb == 1 or rmb == 2

	local consumption = sm.game.getEnableAmmoConsumption()
	local container = sm.localPlayer.getInventory()
	local primaryAmount = self.overdriveActive and 2 or 1

	if consumption then
		sm.gui.setInteractionText(interactionText:format(totalQuantity(container, plasma), primaryAmount))
	end

	if primary and self:canFireLmb(consumption, container, primaryAmount) then
		self.primaryCooldown:reset()
		self.crosshairSpread = 0.25
		self.network:sendToServer(
			"sv_onShoot",
			{
				pos = self.tool:isInFirstPersonView() and self.tool:getFpBonePos("pipe") or self.tool:getTpBonePos("pipe"),
				dir = sm.camera.getDirection(),
				strong = false
			}
		)
	end

	if secondary and not primary and self:canFireRmb(consumption, container) then
		self.secondaryCooldown:reset()
		self.crosshairSpread = 0.5
		self.network:sendToServer(
			"sv_onShoot",
			{
				pos = self.tool:isInFirstPersonView() and self.tool:getFpBonePos("pipe") or self.tool:getTpBonePos("pipe"),
				dir = sm.camera.getDirection(),
				strong = true
			}
		)
	end

	return true, true
end

function Pistol:canFireLmb(consumption, container, primaryAmount)
	return self.primaryCooldown:done() and (not consumption or container:canSpend(plasma, primaryAmount))
end

function Pistol:canFireRmb(consumption, container)
	return self.secondaryCooldown:done() and (not consumption or container:canSpend(plasma, 5))
end

---@param args LaserProjectile
function Pistol:sv_onShoot( args, caller )
	local overdrive = self.overdriveActive
	args.owner = caller.character
	args.overdrive = overdrive
	sm.event.sendToTool(g_pManager, "sv_createProjectile", args)
	self.network:sendToClients("cl_onShoot", args)

	if sm.game.getEnableAmmoConsumption() then
		sm.container.beginTransaction()
		sm.container.spend(self.tool:getOwner():getInventory(), plasma, args.strong and 5 or (overdrive and 2 or 1))
		sm.container.endTransaction()
	end
end

---@param args LaserProjectile
function Pistol:cl_onShoot( args )
	setTpAnimation( self.tpAnimations, "shoot", 10.0 )
	if self.isLocal then
		setFpAnimation( self.fpAnimations, "shoot", 0.05 )
	end

	local overdrive = self.overdriveActive
	local colour =  (args.strong or overdrive) and self.lineStats.colour_strong or self.lineStats.colour_weak
	if not overdrive then
		self.tool:setTpColor(colour)
		if self.isLocal then
			self.tool:setFpColor(colour)
		end
		self.colour = colour
		self.lerpProgress = 0
	end

	self.shootEffect:start()
end





function Pistol.loadAnimations( self )
	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "connecttool_idle" },
			use_idle = { "connecttool_use_idle", { looping = true } },

			shoot = { "laserpistol_shoot", { crouch = "spudgun_crouch_shoot", nextAnimation = "idle" } },

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
		crouchBwd = "connecttool_crouch_bwd",

		swimIdle = "connecttool_swim_idle",
		swimFwd = "connecttool_swim_fwd",
		swimBwd = "connecttool_swim_bwd",
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

				shoot = { "laserpistol_shoot", { nextAnimation = "idle" } },

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

function Pistol.calculateFirePosition( self )
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
		if not sm.localPlayer.getPlayer().character:isAiming() then
			fireOffset = fireOffset + right * 0.05
		end
	else
		fireOffset = fireOffset + right * 0.25
		fireOffset = fireOffset:rotate( math.rad( pitch ), right )
	end
	local firePosition = GetOwnerPosition( self.tool ) + fireOffset
	return firePosition
end