dofile("$GAME_DATA/Scripts/game/AnimationUtil.lua")
dofile("$SURVIVAL_DATA/Scripts/util.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua")

---@class Katana : ToolClass
---@field isLocal boolean
---@field animationsLoaded boolean
---@field equipped boolean
---@field swingCooldowns table
---@field fpAnimations table
---@field tpAnimations table
---@field cutPlain Effect
---@field owner Player
Katana = class()
Katana.bladeModeDirData = {
	{
		name = "Horizontal",
		dir = calculateRightVector,
		transformNormal = function( dir )
			if (dir.x ~= 0 or dir.y ~= 0) and dir.z ~= 0 then
				return sm.vec3.new(0,0,dir.z)
			end

			return dir
		end
	},
	{
		name = "Vertical",
		dir = calculateUpVector,
		transformNormal = function( dir )
			if (dir.y ~= 0 or dir.z ~= 0) and dir.x ~= 0 then
				return sm.vec3.new(dir.x,0,0)
			end

			return dir
		end
	}
}
Katana.bladeModeCutSize = 100

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

sm.tool.preloadRenderables(renderables)
sm.tool.preloadRenderables(renderablesTp)
sm.tool.preloadRenderables(renderablesFp)

local Range = 6 --3.0
local SwingStaminaSpend = 1.5
local Damage = 45

local vec3_zero = sm.vec3.zero()
local vec3_one = sm.vec3.one()
local vec3_up = sm.vec3.new(0,0,1)

Katana.swingCount = 2
Katana.mayaFrameDuration = 1.0 / 30.0
Katana.freezeDuration = 0.075

Katana.swings = { "sledgehammer_attack1", "sledgehammer_attack2" }
Katana.swingFrames = { 4.2 * Katana.mayaFrameDuration, 4.2 * Katana.mayaFrameDuration }
Katana.swingExits = { "sledgehammer_exit1", "sledgehammer_exit2" }

Katana.swings_heavy = { "sledgehammer_attack_heavy1", "sledgehammer_attack_heavy2" }
Katana.swingExits_heavy = { "sledgehammer_exit_heavy1", "sledgehammer_exit_heavy2" }

function Katana.client_onCreate(self)
	self.owner = self.tool:getOwner()
	self.isLocal = self.tool:isLocal()
	self:init()

	if not self.isLocal then return end

	self.cutPlain = sm.effect.createEffect("ShapeRenderable")
	self.cutPlain:setParameter("uuid", blk_wood1)
	self.cutPlain:setParameter("visualization", true)

	self.bladeMode = 1
	self.isInBladeMode = false
end

function Katana:client_onToggle()
	self.bladeMode = self.bladeMode < #self.bladeModeDirData and self.bladeMode + 1 or 1
	sm.gui.displayAlertText("Cut mode: #df7f00"..self.bladeModeDirData[self.bladeMode].name, 2.5)

	return true
end

function Katana:client_onDestroy()
	if not self.isLocal then return end

	self.cutPlain:destroy()
end

function Katana.init(self)

	self.attackCooldownTimer = 0.0
	self.freezeTimer = 0.0
	self.pendingRaycastFlag = false
	self.nextAttackFlag = false
	self.currentSwing = 1

	self.swingCooldowns = {}
	for i = 1, self.swingCount do
		self.swingCooldowns[i] = 0.0
	end

	self.dispersionFraction = 0.001

	self.blendTime = 0.2
	self.blendSpeed = 10.0

	self.sharedCooldown = 0.0
	self.hitCooldown = 1.0
	self.blockCooldown = 0.5
	self.swing = false
	self.block = false

	self.wantBlockSprint = false

	if self.animationsLoaded == nil then
		self.animationsLoaded = false
	end
end

function Katana.client_onUpdate(self, dt)
	if not self.animationsLoaded then
		return
	end

	self.attackCooldownTimer = math.max(self.attackCooldownTimer - dt, 0.0)

	updateTpAnimations(self.tpAnimations, self.equipped, dt)
	if self.isLocal then
		-- #region Blade Mode visuals
		local shouldStopPlain = true
		if self.isInBladeMode then
			local start = sm.localPlayer.getRaycastStart()
			local hit, ray = sm.physics.raycast(start, start + sm.localPlayer.getDirection() * Range, self.owner.character, sm.physics.filter.dynamicBody + sm.physics.filter.staticBody)
			shouldStopPlain = not self.equipped or not hit

			if not shouldStopPlain then
				local data = self.bladeModeDirData[self.bladeMode]
				local normal = data.transformNormal(RoundVector(ray.normalWorld))
				local dir = RoundVector(data.dir(normal))

				local size = sm.vec3.one() * ((normal + dir) * self.bladeModeCutSize)
				size.x = sm.util.clamp( math.abs(size.x), 1, self.bladeModeCutSize )
				size.y = sm.util.clamp( math.abs(size.y), 1, self.bladeModeCutSize )
				size.z = sm.util.clamp( math.abs(size.z), 1, self.bladeModeCutSize )

				local pointLocal = ray.pointWorld --+ normal
				local a = pointLocal * sm.construction.constants.subdivisions
				local gridPos = sm.vec3.new( math.floor( a.x ), math.floor( a.y ), math.floor( a.z ) ) - vec3_one
				local worldPos = gridPos * sm.construction.constants.subdivideRatio + ( vec3_one * 3 * sm.construction.constants.subdivideRatio ) * 0.5

				self.cutPlain:setPosition(worldPos)
				self.cutPlain:setScale(size / 4)
				self.cutPlain:setRotation(ray:getShape().worldRotation)

				if not self.cutPlain:isPlaying() then
					self.cutPlain:start()
				end
			end
		end

		if shouldStopPlain and self.cutPlain:isPlaying() then
			self.cutPlain:stop()
		end
		-- #endregion


		if self.fpAnimations.currentAnimation == self.swings[self.currentSwing] then
			self:updateFreezeFrame(self.swings[self.currentSwing], dt)
		elseif self.fpAnimations.currentAnimation == self.swings_heavy[self.currentSwing] then
			self:updateFreezeFrame(self.swings_heavy[self.currentSwing], dt)
		end

		local preAnimation = self.fpAnimations.currentAnimation
		updateFpAnimations(self.fpAnimations, self.equipped, dt)

		if preAnimation ~= self.fpAnimations.currentAnimation then
			local keepBlockSprint = false
			local endedSwing = (preAnimation == self.swings[self.currentSwing] and
				self.fpAnimations.currentAnimation == self.swingExits[self.currentSwing]) or
				(preAnimation == self.swings_heavy[self.currentSwing] and
				self.fpAnimations.currentAnimation == self.swingExits_heavy[self.currentSwing])

			if self.nextAttackFlag == true and endedSwing == true then
				self.currentSwing = self.currentSwing < self.swingCount and self.currentSwing + 1 or 1

				local params = { name = self.fpAnimations.currentAnimation == self.swingExits[self.currentSwing] and self.swings[self.currentSwing] or self.swings_heavy[self.currentSwing] }
				self.network:sendToServer("server_startEvent", params)
				sm.audio.play("Sledgehammer - Swing")
				self.pendingRaycastFlag = true
				self.nextAttackFlag = false
				self.attackCooldownTimer = self.swingCooldowns[self.currentSwing]
				keepBlockSprint = true

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

end

function Katana.updateFreezeFrame(self, state, dt)
	local p = 1 - math.max(math.min(self.freezeTimer / self.freezeDuration, 1.0), 0.0)
	local playRate = p * p * p * p
	self.fpAnimations.animations[state].playRate = playRate
	self.freezeTimer = math.max(self.freezeTimer - dt, 0.0)
end

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

	local tpAnimation = self.tpAnimations.animations[params.name]
	if tpAnimation then
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

		local blend = not isSwing
		setTpAnimation(self.tpAnimations, params.name, blend and 0.2 or 0.0)
	end


	if not self.isLocal then return end

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

function Katana:client_onEquippedUpdate(lmb, rmb, f)
	if self.pendingRaycastFlag then
		local time = 0.0
		local frameTime = 0.0
		if self.fpAnimations.currentAnimation == self.swings[self.currentSwing]then
			time = self.fpAnimations.animations[self.swings[self.currentSwing]].time
			frameTime = self.swingFrames[self.currentSwing]
		elseif self.fpAnimations.currentAnimation == self.swings_heavy[self.currentSwing]then
			time = self.fpAnimations.animations[self.swings_heavy[self.currentSwing]].time
			frameTime = self.swingFrames[self.currentSwing]
		end

		if time >= frameTime and frameTime ~= 0 then
			self.pendingRaycastFlag = false
			local raycastStart = sm.localPlayer.getRaycastStart()
			local direction = sm.localPlayer.getDirection()
			local success, result = sm.physics.raycast(raycastStart, raycastStart + direction * Range, self.owner.character)
			if success then
				self.freezeTimer = self.freezeDuration
			end

			if self.isInBladeMode then
				if success then
					local ray = RayResultToTable(result)
					if self.isInBladeMode and type(ray.target) == "Shape" then
						self.network:sendToServer(
							"sv_bladeModeCut",
							{
								ray = ray,
								mode = self.bladeMode
							}
						)
					end
				end
			else
				sm.melee.meleeAttack(melee_sledgehammer, Damage, raycastStart, direction * Range, self.owner)
			end
		end
	end

	if lmb == 1 or lmb == 2 then
		if self.fpAnimations.currentAnimation == self.swings[self.currentSwing] then
			if self.attackCooldownTimer < 0.125 then
				self.nextAttackFlag = true
			end
		else
			if self.attackCooldownTimer <= 0 then
				self.currentSwing = 1
				self.network:sendToServer("server_startEvent", { name = self.swings[self.currentSwing] })
				sm.audio.play("Sledgehammer - Swing")
				self.pendingRaycastFlag = true
				self.nextAttackFlag = false
				self.attackCooldownTimer = self.swingCooldowns[self.currentSwing]
			end
		end
	end

	if rmb == 1 or rmb == 2 then
		if self.fpAnimations.currentAnimation == self.swings_heavy[self.currentSwing] then
			if self.attackCooldownTimer < 0.125 then
				self.nextAttackFlag = true
			end
		else
			if self.attackCooldownTimer <= 0 then
				self.currentSwing = 1
				self.network:sendToServer("server_startEvent", { name = self.swings_heavy[self.currentSwing] })
				sm.audio.play("Sledgehammer - Swing")
				self.pendingRaycastFlag = true
				self.nextAttackFlag = false
				self.attackCooldownTimer = self.swingCooldowns[self.currentSwing]
			end
		end
	end

	self.isInBladeMode = f

	return true, true
end

function Katana:sv_bladeModeCut( args )
	local ray = args.ray
	local target = ray.target

	if sm.item.isBlock(target.uuid) then
		local data = self.bladeModeDirData[args.mode]
		---@type Vec3
		local pos = ray.pointWorld
		---@type Vec3
		local normal = data.transformNormal(RoundVector(ray.normalWorld))
		---@type Vec3
		local dir = RoundVector(data.dir(normal))

		local size = AbsVector(sm.vec3.one() * ((normal + dir) * self.bladeModeCutSize))
		local size_clamped = sm.vec3.new(
			sm.util.clamp( size.x, 1, self.bladeModeCutSize ),
			sm.util.clamp( size.y, 1, self.bladeModeCutSize ),
			sm.util.clamp( size.z, 1, self.bladeModeCutSize )
		)

		target:destroyBlock( target:getClosestBlockLocalPosition(pos - target.worldRotation * (size * 0.25)), size_clamped )
	else
		target:destroyShape()
	end
end


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

	--self:init()
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
		setTpAnimation(self.tpAnimations, "unequip")
		if self.isLocal and self.fpAnimations.currentAnimation ~= "unequip" then
			swapFpAnimation(self.fpAnimations, "equip", "unequip", 0.2)
		end
	end
end



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
	--self.swingCooldowns[1] = self.fpAnimations.animations["sledgehammer_attack1"].info.duration
	self.swingCooldowns[1] = 0.6
	--self.swingCooldowns[2] = self.fpAnimations.animations["sledgehammer_attack2"].info.duration
	self.swingCooldowns[2] = 0.6

	self.animationsLoaded = true

end