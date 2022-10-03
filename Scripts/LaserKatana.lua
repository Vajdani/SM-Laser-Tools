--please never make me destroy multiple blocks at once ever again
--I hate this


--[[
TODO:
1. remove continued swinging from the heavy attack
2. better cutting plane
]]


-- #region Class vars and other stuff
dofile("$GAME_DATA/Scripts/game/AnimationUtil.lua")
dofile("$SURVIVAL_DATA/Scripts/util.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua")
dofile "$CONTENT_DATA/Scripts/util.lua"

---@class Katana : ToolClass
---@field isLocal boolean
---@field animationsLoaded boolean
---@field equipped boolean
---@field swingCooldowns table
---@field fpAnimations table
---@field tpAnimations table
---@field cutPlane Effect
---@field owner Player
---@field bladeHud GuiInterface
Katana = class()
Katana.bladeModeDirData = {
	{
		name = "Horizontal",
		dir = calculateRightVector,
		---@param dir Vec3
		---@return Vec3
		transformNormal = function( dir )
			local x, y, z = dir.x, dir.y, dir.z
			local xyDiffer = (x ~= 0 or y ~= 0)
			local zDiffer = z ~= 0

			if xyDiffer then
				if zDiffer then
					return sm.vec3.new(0,0,z)
				elseif x == -1 and y == -1 then
					return dir + vec3_x
				elseif math.abs(x) == 1 and math.abs(y) == 1 then
					return dir - vec3_x
				end
			end

			return dir
		end
	},
	{
		name = "Vertical",
		dir = calculateUpVector,
		---@param dir Vec3
		---@return Vec3
		transformNormal = function( dir )
			local x, y, z = dir.x, dir.y, dir.z
			local yzDiffer = (y ~= 0 or z ~= 0)
			local xDiffer = x ~= 0

			if yzDiffer then
				if xDiffer then
					return sm.vec3.new(x,0,0)
				elseif y == -1 and z == -1 then
					return dir + vec3_up
				elseif math.abs(y) == 1 and math.abs(z) == 1 then
					return dir - vec3_up
				end
			end

			return dir
		end
	}
}
Katana.bladeModeCutSize = 100
Katana.cutPlaneColours = {
	min = sm.color.new(0, 0, 0, 0),
	max = sm.color.new(0, 0.93, 1, 0.2)
}
Katana.swingCount = 2
Katana.mayaFrameDuration = 1.0 / 30.0
Katana.freezeDuration = 0.075
Katana.swingFrames = { 4.2 * Katana.mayaFrameDuration, 4.2 * Katana.mayaFrameDuration }
Katana.swings = { "sledgehammer_attack1", "sledgehammer_attack2" }
Katana.swingExits = { "sledgehammer_exit1", "sledgehammer_exit2" }
Katana.swings_heavy = { "sledgehammer_attack_heavy1", "sledgehammer_attack_heavy2" }
Katana.swingExits_heavy = { "sledgehammer_exit_heavy1", "sledgehammer_exit_heavy2" }
Katana.chargedAttackBegin = 0.3 * 40

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_sledgehammer/char_sledgehammer.rend"
}
local renderablesTp = {
	"$CONTENT_DATA/Tools/LaserKatana/char_male_tp_laserkatana.rend",
	"$CONTENT_DATA/Tools/LaserKatana/char_laserkatana_fp_animlist.rend"
}
local renderablesFp = {
	"$CONTENT_DATA/Tools/LaserKatana/char_male_fp_laserkatana.rend",
	"$CONTENT_DATA/Tools/LaserKatana/char_laserkatana_fp_animlist.rend"
}

local Range = 7.5 --3.0
local SwingStaminaSpend = 1.5
local Damage = 45

sm.tool.preloadRenderables(renderables)
sm.tool.preloadRenderables(renderablesTp)
sm.tool.preloadRenderables(renderablesFp)
-- #endregion


-- #region Setup
function Katana.client_onCreate(self)
	self.owner = self.tool:getOwner()
	self.isLocal = self.tool:isLocal()
	self.charging = false
	self.chargedAttackCharge = 0
	self:init()

	if not self.isLocal then return end

	self.cutPlane = sm.effect.createEffect("Katana_cut_plane")
	self.cutPlane:setParameter("minColor", self.cutPlaneColours.min)
	self.cutPlane:setParameter("maxColor", self.cutPlaneColours.max)
	--[[self.cutPlane = sm.effect.createEffect("ShapeRenderable")
	self.cutPlane:setParameter("uuid", blk_wood1)
	self.cutPlane:setParameter("visualization", true)]]

	self.bladeMode = 1
	self.isInBladeMode = false
	self.bladeHud = sm.gui.createGuiFromLayout(
		"$CONTENT_DATA/Gui/BladeMode.layout",
		false,
		{
			isHud = true,
			isInteractive = false,
			needsCursor = false,
			hidesHotbar = false,
			isOverlapped = false,
			backgroundAlpha = 0
		}
	)

	self.blockCharge = false
	self.heavyAttackStartTick = 0
end

function Katana:client_onDestroy()
	if not self.isLocal then return end

	self.cutPlane:destroy()
	self.bladeHud:destroy()
end

function Katana.init(self)
	self.attackCooldownTimer = 0.0
	self.freezeTimer = 0.0
	self.pendingRaycastFlag = false
	self.nextAttackFlag = false
	self.currentSwing = 1

	self.swingCooldowns = {
		{ 0.6, 0.6, holdTime = 0.125 },
		{ 0.6, 0.6, holdTime = 0.125 } --{ 1, 1, holdTime = 0.25 }
	}

	self.dispersionFraction = 0.001
	self.blendTime = 0.2
	self.blendSpeed = 10.0

	if self.animationsLoaded == nil then
		self.animationsLoaded = false
	end
end
-- #endregion


-- #region Input
function Katana:client_onReload()
	return true
end

function Katana:client_onToggle()
	self.bladeMode = self.bladeMode < #self.bladeModeDirData and self.bladeMode + 1 or 1
	sm.gui.displayAlertText("Cut mode: #df7f00"..self.bladeModeDirData[self.bladeMode].name, 2.5)

	return true
end

function Katana:client_onEquippedUpdate(lmb, rmb, f)
	local lightAnim = self.swings[self.currentSwing]
	local heavyAnim = self.swings_heavy[self.currentSwing]

	if self.pendingRaycastFlag then
		local time = 0.0
		local frameTime = 0.0

		if self.fpAnimations.currentAnimation == lightAnim then
			time = self.fpAnimations.animations[lightAnim].time
			frameTime = self.swingFrames[self.currentSwing]
		elseif self.fpAnimations.currentAnimation == heavyAnim then
			time = self.fpAnimations.animations[heavyAnim].time
			frameTime = self.swingFrames[self.currentSwing]
		end

		if time >= frameTime and frameTime ~= 0 then
			self.pendingRaycastFlag = false
			local raycastStart = sm.localPlayer.getRaycastStart()
			local direction = sm.localPlayer.getDirection()

			sm.melee.meleeAttack(melee_sledgehammer, Damage, raycastStart, direction * Range, self.owner)

			local success, result = sm.physics.raycast(raycastStart, raycastStart + direction * Range, self.owner.character)
			if success then
				self.freezeTimer = self.freezeDuration
			end
		end
	end

	if lmb == 1 or (lmb == 2 and not self.isInBladeMode) then
		self:cl_katanaSwing( lightAnim, 1 )
	end

	if not self.isInBladeMode and self.owner.character:isOnGround() then
		self:cl_handleHeavyAttack( rmb, heavyAnim )
	end

	if f ~= self.isInBladeMode then
		if f then self.bladeHud:open() else self.bladeHud:close() end

		self.isInBladeMode = f
		self.tool:setBlockSprint(f)
		self.tool:setMovementSlowDown(f)
	end

	return true, true
end
-- #endregion


-- #region Util functions
function Katana.updateFreezeFrame(self, state, dt)
	local p = 1 - math.max(math.min(self.freezeTimer / self.freezeDuration, 1.0), 0.0)
	local playRate = p * p * p * p
	self.fpAnimations.animations[state].playRate = playRate
	self.freezeTimer = math.max(self.freezeTimer - dt, 0.0)
end

function Katana:isSwingAnim( params )
	local isSwing = false
	for i = 1, self.swingCount do
		if self.swings[i] == params.name then
			self.tpAnimations.animations[self.swings[i]].playRate = 1
			isSwing = true
		elseif self.swings_heavy[i] == params.name then
			self.tpAnimations.animations[self.swings_heavy[i]].playRate = 1
			isSwing = true
		end
	end

	return isSwing
end

--Thank you so much Programmer Alex
function Katana:calculateCuttingPlanePos( target, worldPos )
	local A = target:getClosestBlockLocalPosition( worldPos )/4
	local B = target.localPosition/4 - sm.vec3.new(0.125,0.125,0.125)
	local C = target:getBoundingBox()
	return target:transformLocalPoint( A-(B+C/2) )
end
-- #endregion


function Katana:client_onUpdate(dt)
	if not self.animationsLoaded then
		return
	end

	local ownerChar = self.owner.character

	self.attackCooldownTimer = math.max(self.attackCooldownTimer - dt, 0.0)
	updateTpAnimations(self.tpAnimations, self.equipped, dt)

	if self.charging then
		self.chargedAttackCharge = sm.util.clamp(self.chargedAttackCharge + dt, 0, 1)
		local progress = self.chargedAttackCharge - 0.5
		setFpAnimationProgress( self.tpAnimations, "sledgehammer_attack_heavy1", progress )

		if self.isLocal then
			setFpAnimationProgress( self.fpAnimations, "sledgehammer_attack_heavy1", progress )
			sm.gui.setProgressFraction( self.chargedAttackCharge/1 )

			local performAttack = self.chargedAttackCharge >= 1
			ownerChar.movementSpeedFraction = performAttack and 1 or 0

			if performAttack then
				self.network:sendToServer("sv_performChargedAttack")
			end
		end
	end


	if not self.isLocal then return end

	local shouldStopPlane = true
	if self.isInBladeMode then
		local start = sm.localPlayer.getRaycastStart()
		local hit, ray = sm.physics.raycast(start, start + sm.localPlayer.getDirection() * Range, ownerChar, sm.physics.filter.dynamicBody + sm.physics.filter.staticBody)
		shouldStopPlane = not self.equipped --or not hit

		if not shouldStopPlane then
			local pos, scale, rot = vec3_zero, vec3_zero, sm.quat.identity()
			local data = self.bladeModeDirData[self.bladeMode]
			local cutSize = self.bladeModeCutSize

			if hit then
				local normal = data.transformNormal(RoundVector(ray.normalLocal))
				local dir = RoundVector(data.dir(normal))

				scale = vec3_one * ((normal + dir) * cutSize)
				scale.x = sm.util.clamp( math.abs(scale.x), 1, cutSize )
				scale.y = sm.util.clamp( math.abs(scale.y), 1, cutSize )
				scale.z = sm.util.clamp( math.abs(scale.z), 1, cutSize )
			else
				scale = data.name == "Horizontal" and
				sm.vec3.new(cutSize, cutSize, 0.1) or
				sm.vec3.new(0.1, cutSize, cutSize)
			end
			scale = scale * 0.0625

			local shape = ray:getShape()
			pos = hit and self:calculateCuttingPlanePos( shape, ray.pointWorld ) or self.tool:getTpBonePos("jnt_head")
			rot = hit and shape.worldRotation or sm.camera.getRotation()

			self.cutPlane:setPosition(pos)
			self.cutPlane:setScale(scale)
			self.cutPlane:setRotation(rot)

			if not self.cutPlane:isPlaying() then
				self.cutPlane:start()
			end
		end
	end

	if shouldStopPlane and self.cutPlane:isPlaying() then
		self.cutPlane:stop()
	end


	local swing = self.currentSwing
	local lightAnim = self.swings[swing]
	local heavyAnim = self.swings_heavy[swing]
	local lightAnim_exit = self.swingExits[swing]
	local heavyAnim_exit = self.swingExits_heavy[swing]

	if self.fpAnimations.currentAnimation == lightAnim then
		self:updateFreezeFrame(lightAnim, dt)
	elseif self.fpAnimations.currentAnimation == heavyAnim then
		self:updateFreezeFrame(heavyAnim, dt)
	end

	local preAnimation = self.fpAnimations.currentAnimation
	updateFpAnimations(self.fpAnimations, self.equipped, dt)

	if preAnimation ~= self.fpAnimations.currentAnimation then
		local keepBlockSprint = false
		local isLightExit = self.fpAnimations.currentAnimation == lightAnim_exit
		local endedSwing = (preAnimation == lightAnim and isLightExit) or
			(preAnimation == heavyAnim and self.fpAnimations.currentAnimation == heavyAnim_exit)

		if self.nextAttackFlag == true and endedSwing == true then
			swing = swing < self.swingCount and swing + 1 or 1
			self.network:sendToServer(
				"server_startEvent",
				{
					name = isLightExit and self.swings[swing] or self.swings_heavy[swing]
				}
			)
			sm.audio.play("Sledgehammer - Swing")

			self.pendingRaycastFlag = true
			self.nextAttackFlag = false
			self.attackCooldownTimer = self.swingCooldowns[BoolToVal(not isLightExit) + 1][swing]
			keepBlockSprint = true

			self.currentSwing = swing
		elseif isAnyOf(self.fpAnimations.currentAnimation, { "guardInto", "guardIdle", "guardExit", "guardBreak", "guardHit" }) then
			keepBlockSprint = true
		end

		self.tool:setBlockSprint(keepBlockSprint)
	end

	local isSprinting = self.tool:isSprinting()
	if isSprinting and self.fpAnimations.currentAnimation == "idle" and self.attackCooldownTimer <= 0 and
		not isAnyOf(self.fpAnimations.currentAnimation, { "sprintInto", "sprintIdle" }) then
		local params = { name = "sprintInto" }
		self:client_startLocalEvent(params)
	end

	if (not isSprinting and isAnyOf(self.fpAnimations.currentAnimation, { "sprintInto", "sprintIdle" })) and
		self.fpAnimations.currentAnimation ~= "sprintExit" then
		local params = { name = "sprintExit" }
		self:client_startLocalEvent(params)
	end
end


-- #region Events
function Katana.server_startEvent(self, params)
	local player = self.tool:getOwner()
	if player then
		sm.event.sendToPlayer(player, "sv_e_staminaSpend", SwingStaminaSpend)
	end
	self.network:sendToClients("client_startLocalEvent", params)
end

function Katana.client_startLocalEvent(self, params)
	self:client_handleEvent(params)
end


function Katana.client_handleEvent(self, params)
	if params.name == "equip" then
		self.equipped = true
	elseif params.name == "unequip" then
		self.equipped = false
	end

	if not self.animationsLoaded then
		return
	end

	local isSwing = self:isSwingAnim( params )
	local tpAnimation = self.tpAnimations.animations[params.name]
	if tpAnimation then
		local blend = not isSwing
		setTpAnimation(self.tpAnimations, params.name, blend and 0.2 or 0.0)
	end

	if not self.isLocal then return end

	if isSwing or isAnyOf(params.name, { "guardInto", "guardIdle", "guardExit", "guardBreak", "guardHit" }) then
		self.tool:setBlockSprint(true)
	else
		self.tool:setBlockSprint(false)
	end

	if params.name == "guardInto" then
		swapFpAnimation(self.fpAnimations, "guardExit", "guardInto", 0.2)
	elseif params.name == "guardExit" then
		swapFpAnimation(self.fpAnimations, "guardInto", "guardExit", 0.2)
	elseif params.name == "sprintInto" then
		swapFpAnimation(self.fpAnimations, "sprintExit", "sprintInto", 0.2)
	elseif params.name == "sprintExit" then
		swapFpAnimation(self.fpAnimations, "sprintInto", "sprintExit", 0.2)
	else
		local blend = not (isSwing or isAnyOf(params.name, { "equip", "unequip" }))
		setFpAnimation(self.fpAnimations, params.name, blend and 0.2 or 0.0)
	end
end
-- #endregion


-- #region Katana
function Katana:cl_katanaSwing( anim, mode )
	if self.isInBladeMode then
		self:cl_bladeModeCut( mode )
	else
		local cooldownData = self.swingCooldowns[mode]
		if self.fpAnimations.currentAnimation == anim then
			if self.attackCooldownTimer < cooldownData.holdTime then
				self.nextAttackFlag = true
			end
		else
			if self.attackCooldownTimer <= 0 then
				self.currentSwing = 1
				self.network:sendToServer("server_startEvent", { name = anim })
				sm.audio.play("Sledgehammer - Swing")
				self.pendingRaycastFlag = true
				self.nextAttackFlag = false
				self.attackCooldownTimer = cooldownData[self.currentSwing]
			end
		end
	end
end

function Katana:cl_bladeModeCut( mode )
	--self.bladeMode = mode
	local raycastStart = sm.localPlayer.getRaycastStart()
	local hit, result = sm.physics.raycast(
		raycastStart,
		raycastStart + sm.localPlayer.getDirection() * Range,
		self.owner.character
	)

	if not hit then return end

	local ray = RayResultToTable(result)
	if self.isInBladeMode and type(ray.target) == "Shape" then
		self.network:sendToServer(
			"sv_bladeModeCut",
			{
				ray = ray,
				mode = self.bladeMode --mode
			}
		)
	end
end

function Katana:sv_bladeModeCut( args )
	local ray = args.ray
	local target = ray.target

	if sm.item.isBlock(target.uuid) then
		local data = self.bladeModeDirData[args.mode]
		---@type Vec3
		local pos = ray.pointWorld
		---@type Vec3
		local normal = data.transformNormal(RoundVector(ray.normalLocal))
		---@type Vec3
		local dir = RoundVector(data.dir(normal))

		local cutSize = self.bladeModeCutSize
		local size = AbsVector(sm.vec3.one() * ((normal + dir) * cutSize))
		local size_clamped = sm.vec3.new(
			sm.util.clamp( size.x, 1, cutSize ),
			sm.util.clamp( size.y, 1, cutSize ),
			sm.util.clamp( size.z, 1, cutSize )
		)

		target:destroyBlock( target:getClosestBlockLocalPosition(pos - target.worldRotation * (size * 0.25)), size_clamped )
	else
		target:destroyShape()
	end

	self:server_startEvent({ name = "sledgehammer_attack_heavy1" })
end


function Katana:cl_handleHeavyAttack( state, anim )
	local tick = sm.game.getCurrentTick()
	local canCharge = tick - self.heavyAttackStartTick >= self.chargedAttackBegin

	if state == 1 then
		self.heavyAttackStartTick = tick
	elseif state == 2 and canCharge and not self.charging and not self.blockCharge then
		self.network:sendToServer("sv_updateChargeAttack", true)
		self.blockCharge = true
	elseif state == 3 then
		if not canCharge then
			self:cl_katanaSwing( anim, 2 )
			return
		end

		self.blockCharge = false
		self.network:sendToServer("sv_updateChargeAttack", false )
	end
end

function Katana:sv_updateChargeAttack( state )
	self.network:sendToClients("cl_updateChargeAttack", state)
end

function Katana:cl_updateChargeAttack( state )
	self.charging = state
	self.chargedAttackCharge = 0

	if self.isLocal then
		self.tool:setBlockSprint(state)
		self.tool:setMovementSlowDown(state)
	end

	local anim = state and "sledgehammer_attack_heavy1" or "idle"
	if self.tpAnimations.currentAnimation == anim then return end

	local speed = state and 0.2 or 0.5
	setTpAnimation( self.tpAnimations, anim, speed )
	if self.isLocal then
		setFpAnimation( self.fpAnimations, anim, speed )
	end
end

function Katana:sv_performChargedAttack()
	self:sv_updateChargeAttack( false )

	local owner = self.tool:getOwner()
	local char = owner.character
	local pos = char.worldPosition + sm.vec3.new(0,0,0.575)
	local dir = char.direction
	for i = 1, 50 do
		sm.projectile.projectileAttack(
			projectile_potato,
			50,
			pos,
			sm.noise.gunSpread(dir, i) * 130,
			owner
		)
	end
end
-- #endregion


-- #region Equip
function Katana.client_onEquip(self, animate)
	if animate then
		sm.audio.play("Sledgehammer - Equip", self.tool:getPosition())
	end

	self.equipped = true

	local currentRenderablesTp = {}
	local currentRenderablesFp = {}
	for k, v in pairs(renderablesTp) do currentRenderablesTp[#currentRenderablesTp + 1] = v end
	for k, v in pairs(renderablesFp) do currentRenderablesFp[#currentRenderablesFp + 1] = v end
	for k, v in pairs(renderables) do currentRenderablesTp[#currentRenderablesTp + 1] = v end
	for k, v in pairs(renderables) do currentRenderablesFp[#currentRenderablesFp + 1] = v end

	self.tool:setTpRenderables(currentRenderablesTp)
	if self.isLocal then
		self.tool:setFpRenderables(currentRenderablesFp)
	end

	self:init()
	self:loadAnimations()

	setTpAnimation(self.tpAnimations, "equip", 0.0001)
	if self.isLocal then
		swapFpAnimation(self.fpAnimations, "unequip", "equip", 0.2)
	end
end

function Katana.client_onUnequip(self, animate)
	self.equipped = false
	if sm.exists(self.tool) then
		if animate then
			sm.audio.play("Sledgehammer - Unequip", self.tool:getPosition())
		end

		self:cl_updateChargeAttack( false )

		setTpAnimation(self.tpAnimations, "unequip")
		if self.isLocal then
			self.owner.character.movementSpeedFraction = 1
			self.blockCharge = false

			if self.fpAnimations.currentAnimation ~= "unequip" then
				swapFpAnimation(self.fpAnimations, "equip", "unequip", 0.2)
			end
		end
	end
end
-- #endregion


-- #region get out
function Katana.loadAnimations(self)

	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			equip = { "sledgehammer_pickup", { nextAnimation = "idle" } },
			unequip = { "sledgehammer_putdown" },
			idle = { "sledgehammer_idle", { looping = true } },

			sledgehammer_attack1 = { "sledgehammer_attack1", { nextAnimation = "sledgehammer_exit1" } },
			sledgehammer_attack2 = { "sledgehammer_attack2", { nextAnimation = "sledgehammer_exit2" } },
			sledgehammer_exit1 = { "sledgehammer_exit1", { nextAnimation = "idle" } },
			sledgehammer_exit2 = { "sledgehammer_exit2", { nextAnimation = "idle" } },

			sledgehammer_attack_heavy1 = { "sledgehammer_attack_heavy1", { nextAnimation = "sledgehammer_exit_heavy1" } },
			sledgehammer_attack_heavy2 = { "sledgehammer_attack_heavy2", { nextAnimation = "sledgehammer_exit_heavy2" } },
			sledgehammer_exit_heavy1 = { "sledgehammer_exit_heavy1", { nextAnimation = "idle" } },
			sledgehammer_exit_heavy2 = { "sledgehammer_exit_heavy2", { nextAnimation = "idle" } },

			--[[
			guardInto = { "sledgehammer_guard_into", { nextAnimation = "guardIdle" } },
			guardIdle = { "sledgehammer_guard_idle", { looping = true } },
			guardExit = { "sledgehammer_guard_exit", { nextAnimation = "idle" } },

			guardBreak = { "sledgehammer_guard_break", { nextAnimation = "idle" } } --,
			--guardHit = { "sledgehammer_guard_hit", { nextAnimation = "guardIdle" } }
			--guardHit is missing for tp
			]]
		}
	)
	local movementAnimations = {
		idle = "sledgehammer_idle",
		--idleRelaxed = "sledgehammer_idle_relaxed",

		runFwd = "sledgehammer_run_fwd",
		runBwd = "sledgehammer_run_bwd",

		sprint = "sledgehammer_sprint",

		jump = "sledgehammer_jump",
		jumpUp = "sledgehammer_jump_up",
		jumpDown = "sledgehammer_jump_down",

		land = "sledgehammer_jump_land",
		landFwd = "sledgehammer_jump_land_fwd",
		landBwd = "sledgehammer_jump_land_bwd",

		crouchIdle = "sledgehammer_crouch_idle",
		crouchFwd = "sledgehammer_crouch_fwd",
		crouchBwd = "sledgehammer_crouch_bwd"

	}

	for name, animation in pairs(movementAnimations) do
		self.tool:setMovementAnimation(name, animation)
	end

	setTpAnimation(self.tpAnimations, "idle", 5.0)

	if self.isLocal then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "sledgehammer_pickup", { nextAnimation = "idle" } },
				unequip = { "sledgehammer_putdown" },
				idle = { "sledgehammer_idle", { looping = true } },

				sprintInto = { "sledgehammer_sprint_into", { nextAnimation = "sprintIdle" } },
				sprintIdle = { "sledgehammer_sprint_idle", { looping = true } },
				sprintExit = { "sledgehammer_sprint_exit", { nextAnimation = "idle" } },

				sledgehammer_attack1 = { "sledgehammer_attack1", { nextAnimation = "sledgehammer_exit1" } },
				sledgehammer_attack2 = { "sledgehammer_attack2", { nextAnimation = "sledgehammer_exit2" } },
				sledgehammer_exit1 = { "sledgehammer_exit1", { nextAnimation = "idle" } },
				sledgehammer_exit2 = { "sledgehammer_exit2", { nextAnimation = "idle" } },

				sledgehammer_attack_heavy1 = { "sledgehammer_attack_heavy1", { nextAnimation = "sledgehammer_exit_heavy1" } },
				sledgehammer_attack_heavy2 = { "sledgehammer_attack_heavy2", { nextAnimation = "sledgehammer_exit_heavy2" } },
				sledgehammer_exit_heavy1 = { "sledgehammer_exit_heavy1", { nextAnimation = "idle" } },
				sledgehammer_exit_heavy2 = { "sledgehammer_exit_heavy2", { nextAnimation = "idle" } },

				--[[guardInto = { "sledgehammer_guard_into", { nextAnimation = "guardIdle" } },
				guardIdle = { "sledgehammer_guard_idle", { looping = true } },
				guardExit = { "sledgehammer_guard_exit", { nextAnimation = "idle" } },

				guardBreak = { "sledgehammer_guard_break", { nextAnimation = "idle" } },
				guardHit = { "sledgehammer_guard_hit", { nextAnimation = "guardIdle" } }]]

			}
		)
		setFpAnimation(self.fpAnimations, "idle", 0.0)
	end

	self.animationsLoaded = true
end
-- #endregion