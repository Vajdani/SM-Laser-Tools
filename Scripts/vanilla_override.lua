if not RayProjectileManager then
	return
else
	sm.LaserTools_GameHooked = true
end

local ToolItems = {
	["99c5dde3-1c24-41f4-9fc0-fd183c88673e"] = sm.uuid.new("c5d3db44-b21a-41c7-b8ba-b2d9edaf7f0a"), --Laser Cutter
	["e3bd2dd1-1bb0-4964-b46c-d4d58cfec074"] = sm.uuid.new("1d8a0366-5867-4768-a487-e34e608d0db9") --Laser Pistol
}

local oldGetToolProxyItem = GetToolProxyItem
function GetToolProxyItem( toolUuid )
	local item = oldGetToolProxyItem( toolUuid )
	if not item then
		item = ToolItems[tostring( toolUuid )]
	end

	return item
end

if _GetToolProxyItem then
	local oldGetToolProxyItem2 = _GetToolProxyItem
	function _GetToolProxyItem( toolUuid )
		local item = oldGetToolProxyItem2( toolUuid )
		if not item then
			item = ToolItems[tostring( toolUuid )]
		end

		return item
	end
end

if FantGetToolProxyItem then
	local oldGetToolProxyItem3 = FantGetToolProxyItem
	function FantGetToolProxyItem( toolUuid )
		local item = oldGetToolProxyItem3( toolUuid )
		if not item then
			item = ToolItems[tostring( toolUuid )]
		end

		return item
	end
end

dofile "$GAME_DATA/Scripts/game/BasePlayer.lua"

if not CottonPlant then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/CottonPlant.lua"
end

if not PigmentFlower then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/PigmentFlower.lua"
end

if not OilGeyser then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/OilGeyser.lua"
end

if not MatureHarvestable then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/MatureHarvestable.lua"
end

LaserTools_codeDefined = LaserTools_codeDefined or false

LaserTools_oldBindCMD = LaserTools_oldBindCMD or sm.game.bindChatCommand
function sm.game.bindChatCommand(command, params, callback, help)
	if not LaserTools_codeDefined then
		LaserTools_codeDefined = true

		function CottonPlant.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
			self:sv_onHit()
		end

		function CottonPlant:sv_onHit()
			if not self.harvested and sm.exists( self.harvestable ) then
				if SurvivalGame then
					local loot = { lootUid = ITEMS.obj_seed_cotton, lootQuantity = PlantSeedDropAmount( ITEMS.obj_seed_cotton ) }
					local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
					sm.projectile.harvestableCustomProjectileAttack( loot, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
				end

				sm.effect.playEffect( "Cotton - Picked", self.harvestable.worldPosition )
				sm.harvestable.createHarvestable( hvs_farmables_growing_cottonplant, self.harvestable.worldPosition, self.harvestable.worldRotation )
				sm.harvestable.destroy( self.harvestable )
				self.harvested = true
				self.harvestable.publicData.harvested = true
			end
		end



		function PigmentFlower.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
			self:sv_onHit()
		end

		function PigmentFlower:sv_onHit()
			if not self.harvested and sm.exists( self.harvestable ) then
				if SurvivalGame then
					local loot = { lootUid = ITEMS.obj_seed_pigmentflower, lootQuantity = PlantSeedDropAmount( ITEMS.obj_seed_pigmentflower ) }
					local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
					sm.projectile.harvestableCustomProjectileAttack( loot, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
				end

				sm.effect.playEffect( "Pigmentflower - Picked", self.harvestable.worldPosition )
				sm.harvestable.createHarvestable( hvs_farmables_growing_pigmentflower, self.harvestable.worldPosition, self.harvestable.worldRotation )
				sm.harvestable.destroy( self.harvestable )
				self.harvested = true
				self.harvestable.publicData.harvested = true
			end
		end



		function OilGeyser:sv_onHit()
			if not self.harvested and sm.exists( self.harvestable ) then
				if SurvivalGame then
					local loot = { lootUid = ITEMS.obj_seed_pigmentflower, randomStackAmount( 1, 2, 4 ) }
					local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
					sm.projectile.harvestableCustomProjectileAttack( loot, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
				end

				sm.effect.playEffect( "Oilgeyser - Picked", self.harvestable.worldPosition )
				sm.harvestable.createHarvestable( hvs_farmables_growing_oilgeyser, self.harvestable.worldPosition, self.harvestable.worldRotation )
				sm.harvestable.destroy( self.harvestable )
				self.harvested = true
				self.harvestable.publicData.harvested = true
			end
		end



		function MatureHarvestable:sv_onHit()
			if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
				sm.effect.playEffect( "Plants - Picked", self.harvestable:getPosition() )

				local harvest = {
					lootUid = sm.uuid.new( self.data.harvest ),
					lootQuantity = self.data.amount
				}
				local seedUuid = sm.uuid.new( self.data.seed )
				local seed = { lootUid = seedUuid, lootQuantity = PlantSeedDropAmount( seedUuid ) }
				local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
				sm.projectile.harvestableCustomProjectileAttack( harvest, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
				if seed.lootQuantity > 0 then
					sm.projectile.harvestableCustomProjectileAttack( seed, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
				end

				sm.harvestable.createHarvestable( hvs_soil, self.harvestable:getPosition(), self.harvestable:getRotation() )
				RaidManager.Sv_CropDestroyed( self.harvestable )

				self.harvestable:destroy()
				self.harvestable.publicData.harvested = true
			end
		end

		for k, global in pairs(_G) do
			if type(global) == "table" then
				if global.server_onUnitUpdate then
					function global:sv_e_takeDamage(args)
						if not sm.exists(self.unit) then return end

						local char = self.unit.character
						if isAnyOf(char:getCharacterType(), g_tapebots) then
							self:sv_takeDamage( args.damage or 0, args.impact or sm.vec3.zero(), args.headHit or false )
						else
							self:sv_takeDamage( args.damage or 0, args.impact or sm.vec3.zero(), args.hitPos or self.unit.character.worldPosition )
						end
					end

					print("[LASER TOOLS] HOOKED UNIT CLASS", k)
				elseif global.client_onCancel or global.server_onInventoryChanges then
					function global:sv_e_takeDamage(args)
						local char = self.player.character
						if sm.exists(char) then
							self:sv_takeDamage( args.damage or 0, args.impact or sm.vec3.zero(), args.hitPos or self.player.character.worldPosition )
						end
					end

					print("[LASER TOOLS] HOOKED PLAYER CLASS", k)
				elseif global.sv_onHit then
					function global:sv_e_onHit(args)
						self:sv_onHit(args.damage, args.position)
					end

					print("[LASER TOOLS] HOOKED HARVESTABLE CLASS", k)
				end
			end
		end
	end

	return LaserTools_oldBindCMD(command, params, callback, help)
end