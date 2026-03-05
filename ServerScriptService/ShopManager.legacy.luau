-- [[ ServerScriptService/TycoonRemotesHandler.server.luau ]] --

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local remotes = ReplicatedStorage:WaitForChild("TycoonRemotes")

-- [[ CONFIG ]] --
local GP_AUTO_MERGE = 1696656180
local GP_UNLIMITED_CASH = 1697244377

-- [[ HELPER: GET OR CREATE REMOTE ]] --
local function GetRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = remotes
	end
	return r
end

-- [[ INITIALIZE REMOTES ]] --
local buyShopItem = GetRemote("BuyShopItem", "RemoteFunction")
local mergeAllEvent = GetRemote("MergeAll", "RemoteEvent")
local refreshEvent = GetRemote("RefreshGamePasses", "RemoteEvent")
local toggleAutoMerge = GetRemote("ToggleAutoMerge", "RemoteEvent")
local toggleUnlimited = GetRemote("ToggleUnlimited", "RemoteEvent")

-- [[ TOGGLE LOGIC ]] --
toggleAutoMerge.OnServerEvent:Connect(function(player)
	local success, owns = pcall(function() 
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GP_AUTO_MERGE) 
	end)

	if success and owns then
		local vals = player:FindFirstChild("Values")
		if vals and vals:FindFirstChild("AutoMerge") then
			vals.AutoMerge.Value = not vals.AutoMerge.Value
		end
	end
end)

toggleUnlimited.OnServerEvent:Connect(function(player)
	local success, owns = pcall(function() 
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GP_UNLIMITED_CASH) 
	end)

	if success and owns then
		local vals = player:FindFirstChild("Values")
		if vals and vals:FindFirstChild("UnlimitedMoney") then
			vals.UnlimitedMoney.Value = not vals.UnlimitedMoney.Value
		end
	end
end)

-- [[ BUY ITEM LOGIC ]] --
-- Currently acts as a placeholder if you aren't using in-game cash for these items
buyShopItem.OnServerInvoke = function(player, itemName)
	warn("BuyShopItem called by " .. player.Name .. " for " .. tostring(itemName) .. " but logic is empty.")
	return false 
end