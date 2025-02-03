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
		end
	end
end



if not WoodHarvestable then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/WoodHarvestable.lua"
end

function WoodHarvestable:sv_e_onHit(args)
	self:sv_onHit(args.damage, args.position)
end



if not StoneHarvestable then
	dofile "$SURVIVAL_DATA/Scripts/game/harvestable/StoneHarvestable.lua"
end

function StoneHarvestable:sv_e_onHit(args)
	self:sv_onHit(args.damage, args.position)
end