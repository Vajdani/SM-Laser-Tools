dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile "$CONTENT_DATA/Scripts/util.lua"

---@class PlasmaContainer : ShapeClass
PlasmaContainer = class( nil )
PlasmaContainer.maxChildCount = -1
PlasmaContainer.connectionOutput = connectionType_plasma
PlasmaContainer.colorNormal = sm.color.new( 0x84ff32ff )
PlasmaContainer.colorHighlight = sm.color.new( 0xa7ff4fff )

local ContainerSize = 10

function PlasmaContainer:server_onCreate()
	self.stackSize = self.data.stackSize
	local container = self.interactable:getContainer( 0 )
	if not container then
		container = self.interactable:addContainer( 0, ContainerSize, self.stackSize )
	end

	if self.data.filterUid then
		local filters = { sm.uuid.new( self.data.filterUid ) }
		container:setFilters( filters )
	end

	self.container = container
end

function PlasmaContainer:client_canCarry()
	if self.container and sm.exists( self.container ) then
		return not self.container:isEmpty()
	end
	return false
end

function PlasmaContainer:client_onInteract( character, state )
	if not state or not self.container then return end

	local gui = sm.gui.createContainerGui(true)
	gui:setText( "UpperName", "#{CONTAINER_TITLE_GENERIC}" )
	gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
	gui:setContainer( "UpperGrid", self.container )
	gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
	gui:open()
end

function PlasmaContainer:client_onUpdate()
	local quantities = sm.container.quantity( self.container )
	local quantity = 0
	for _,q in ipairs( quantities ) do
		quantity = quantity + q
	end

	self.interactable:setUvFrameIndex(math.floor((ContainerSize - math.ceil( quantity / self.stackSize )) * 0.5))
end
