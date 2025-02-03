local ToolItems = {
	["99c5dde3-1c24-41f4-9fc0-fd183c88673e"] = sm.uuid.new("c5d3db44-b21a-41c7-b8ba-b2d9edaf7f0a"), --Laser Cutter
	["e3bd2dd1-1bb0-4964-b46c-d4d58cfec074"] = sm.uuid.new("1d8a0366-5867-4768-a487-e34e608d0db9") --Laser Pistol
}

local oldGetToolProxyItem = GetToolProxyItem
function getToolProxyItemHook( toolUuid )
	local item = oldGetToolProxyItem( toolUuid )
	if not item then
		item = ToolItems[tostring( toolUuid )]
	end

	return item
end
GetToolProxyItem = getToolProxyItemHook

if _GetToolProxyItem then
	local oldGetToolProxyItem2 = _GetToolProxyItem
	function getToolProxyItemHook2( toolUuid )
		local item = oldGetToolProxyItem2( toolUuid )
		if not item then
			item = ToolItems[tostring( toolUuid )]
		end

		return item
	end
	_GetToolProxyItem = getToolProxyItemHook2
end

if FantGetToolProxyItem then
	local oldGetToolProxyItem3 = FantGetToolProxyItem
	function getToolProxyItemHook3( toolUuid )
		local item = oldGetToolProxyItem3( toolUuid )
		if not item then
			item = ToolItems[tostring( toolUuid )]
		end

		return item
	end
	FantGetToolProxyItem = getToolProxyItemHook3
end



dofile "$GAME_DATA/Scripts/game/BasePlayer.lua"


if not CottonPlant then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/CottonPlant.lua"
end

function CottonPlant.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit()
end

function CottonPlant:sv_onHit()
	if not self.harvested and sm.exists( self.harvestable ) then
		sm.effect.playEffect( "Cotton - Picked", self.harvestable.worldPosition )

		if SurvivalGame then
			local harvest = {
				lootUid = obj_resource_cotton,
				lootQuantity = 1
			}
			local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
			sm.projectile.harvestableCustomProjectileAttack( harvest, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
		end
		sm.harvestable.createHarvestable( hvs_farmables_growing_cottonplant, self.harvestable.worldPosition, self.harvestable.worldRotation )
		sm.harvestable.destroy( self.harvestable )
		self.harvested = true
	end
end


if not PigmentFlower then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/PigmentFlower.lua"
end

function PigmentFlower.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit()
end

function PigmentFlower:sv_onHit()
	if not self.harvested and sm.exists( self.harvestable ) then
		sm.effect.playEffect( "Pigmentflower - Picked", self.harvestable.worldPosition )

		if SurvivalGame then
			local harvest = {
				lootUid = obj_resource_flower,
				lootQuantity = 1
			}
			local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
			sm.projectile.harvestableCustomProjectileAttack( harvest, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
		end
		sm.harvestable.createHarvestable( hvs_farmables_growing_pigmentflower, self.harvestable.worldPosition, self.harvestable.worldRotation )
		sm.harvestable.destroy( self.harvestable )
		self.harvested = true
	end
end


if not OilGeyser then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/OilGeyser.lua"
end

function OilGeyser:sv_onHit( params, player )
	if not self.harvested and sm.exists( self.harvestable ) then
		if SurvivalGame then
			local harvest = {
				lootUid = obj_resource_crudeoil,
				lootQuantity = randomStackAmount( 1, 2, 4 )
			}
			local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
			sm.projectile.harvestableCustomProjectileAttack( harvest, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )

		end

		sm.effect.playEffect( "Oilgeyser - Picked", self.harvestable.worldPosition )
		sm.harvestable.createHarvestable( hvs_farmables_growing_oilgeyser, self.harvestable.worldPosition, self.harvestable.worldRotation )
		sm.harvestable.destroy( self.harvestable )
		self.harvested = true
	end
end


if not MatureHarvestable then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/MatureHarvestable.lua"
end

function MatureHarvestable:sv_onHit()
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
		sm.effect.playEffect( "Plants - Picked", self.harvestable:getPosition() )

		local harvest = {
			lootUid = sm.uuid.new( self.data.harvest ),
			lootQuantity = self.data.amount
		}
		local seed = {
			lootUid = sm.uuid.new( self.data.seed ),
			lootQuantity = randomStackAmountAvg2()
		}
		local pos = self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.5 )
		sm.projectile.harvestableCustomProjectileAttack( harvest, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )
		sm.projectile.harvestableCustomProjectileAttack( seed, projectile_loot, 0, pos, sm.noise.gunSpread( sm.vec3.new( 0, 0, 1 ), 20 ) * 5, self.harvestable, 0 )

		sm.harvestable.createHarvestable( hvs_soil, self.harvestable:getPosition(), self.harvestable:getRotation() )
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


-- if not WoodHarvestable then
-- 	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/WoodHarvestable.lua"
-- end

-- function WoodHarvestable:sv_e_onHit(args)
-- 	self:sv_onHit(args.damage, args.position)
-- end



-- if not StoneHarvestable then
-- 	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/StoneHarvestable.lua"
-- end

-- function StoneHarvestable:sv_e_onHit(args)
-- 	self:sv_onHit(args.damage, args.position)
-- end