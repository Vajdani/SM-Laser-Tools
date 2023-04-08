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