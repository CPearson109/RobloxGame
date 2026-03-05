local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remotes = ReplicatedStorage:WaitForChild("TycoonRemotes")
local claimRemote = remotes:FindFirstChild("ClaimPlaytimeReward") or Instance.new("RemoteFunction", remotes)
claimRemote.Name = "ClaimPlaytimeReward"
local getRewardsRemote = remotes:FindFirstChild("GetPlaytimeRewards") or Instance.new("RemoteFunction", remotes)
getRewardsRemote.Name = "GetPlaytimeRewards"
local StartGemStorm = remotes:FindFirstChild("StartGemStorm") or Instance.new("RemoteEvent", remotes)
StartGemStorm.Name = "StartGemStorm"

local TycoonMap = Workspace:WaitForChild("TycoonMap")
local Brainrots = ReplicatedStorage:WaitForChild("Brainrots")
local BrainrotCache = {}

for _, model in pairs(Brainrots:GetChildren()) do
	local lvlObj = model:FindFirstChild("Level")
	if lvlObj and lvlObj:IsA("IntValue") then
		BrainrotCache[lvlObj.Value] = model
	end
end

local TIME_REQUIREMENTS = {0, 300, 600, 900, 1800}

local function GenerateLootForDay(userId, dayNumber)
	local rng = Random.new(userId + (dayNumber * 1000)) 
	local rewards = {}

	local dayScale = 1 + (dayNumber * 0.15) 
	local typesUsed = {Cash = false, Gems = false, Items = false}

	for slot = 1, 5 do
		if slot == 5 then
			local r = rng:NextInteger(1, 3)
			if r == 1 then rewards[slot] = {Type = "GemStorm"}
			elseif r == 2 then rewards[slot] = {Type = "ItemRain", Amount = math.floor(rng:NextInteger(25, 40) * dayScale)}
			else rewards[slot] = {Type = "DynamicCash", Multiplier = 5 * dayScale} end
		else
			local typeChoice
			local available = {"DynamicCash", "Gems", "ItemRain"}

			if slot == 2 and not typesUsed.Gems then typeChoice = "Gems"
			elseif slot == 3 and not typesUsed.Cash then typeChoice = "DynamicCash"
			elseif slot == 4 and not typesUsed.Items then typeChoice = "ItemRain"
			else typeChoice = available[rng:NextInteger(1, #available)] end

			if typeChoice == "DynamicCash" then typesUsed.Cash = true
			elseif typeChoice == "Gems" then typesUsed.Gems = true
			elseif typeChoice == "ItemRain" then typesUsed.Items = true end

			if typeChoice == "DynamicCash" then
				local baseMults = {1, 1.2, 1.5, 2}
				rewards[slot] = {Type = "DynamicCash", Multiplier = baseMults[slot] * dayScale}
			elseif typeChoice == "Gems" then
				local baseGems = {20, 40, 60, 100}
				local amt = math.floor(baseGems[slot] * dayScale)
				rewards[slot] = {Type = "Gems", Amount = math.floor((amt + 5) / 10) * 10}
			elseif typeChoice == "ItemRain" then
				local baseRain = {5, 8, 12, 18}
				rewards[slot] = {Type = "ItemRain", Amount = math.floor(baseRain[slot] * dayScale)}
			end
		end
	end
	return rewards
end

local function FindPlayerPlot(player)
	for _, plot in pairs(TycoonMap:GetChildren()) do
		local owner = plot:FindFirstChild("Owner")
		if owner and owner.Value == player then return plot end
	end
	return nil
end

getRewardsRemote.OnServerInvoke = function(player)
	local ptFolder = player:WaitForChild("PlaytimeRewards", 10)
	local loginDay = player:GetAttribute("Playtime_LoginDay")
	local joinTime = player:GetAttribute("Playtime_JoinTime")

	if not ptFolder or not loginDay or not joinTime then return nil end

	local claimedSlots = {}
	for i = 1, 5 do
		local b = ptFolder:FindFirstChild("Slot" .. i)
		claimedSlots[i] = b and b.Value or false
	end

	return {
		Times = TIME_REQUIREMENTS,
		CurrentDay = loginDay,
		ClaimedSlots = claimedSlots,
		JoinTime = joinTime,
		Row1 = GenerateLootForDay(player.UserId, loginDay),
		Row2 = GenerateLootForDay(player.UserId, loginDay + 1),
		Row3 = GenerateLootForDay(player.UserId, loginDay + 2)
	}
end

claimRemote.OnServerInvoke = function(player, slotIndex)
	local ptFolder = player:FindFirstChild("PlaytimeRewards")
	local joinTime = player:GetAttribute("Playtime_JoinTime")
	local loginDay = player:GetAttribute("Playtime_LoginDay")

	if not ptFolder or not joinTime or not loginDay then return false end
	if slotIndex < 1 or slotIndex > 5 then return false end

	local slotVal = ptFolder:FindFirstChild("Slot" .. slotIndex)
	if not slotVal or slotVal.Value then return false end

	if (os.time() - joinTime) < (TIME_REQUIREMENTS[slotIndex] - 2) then return false end

	local ls = player:FindFirstChild("leaderstats")
	local values = player:FindFirstChild("Values")
	if not (ls and values) then return false end

	local cash = ls:FindFirstChild("Cash")
	local gems = ls:FindFirstChild("Gems")
	if not (cash and gems) then return false end

	local activeRewards = GenerateLootForDay(player.UserId, loginDay)
	local rewardData = activeRewards[slotIndex]

	if rewardData.Type == "DynamicCash" then
		local baseReward = math.max(500, cash.Value * 0.15)
		local finalReward = baseReward * (rewardData.Multiplier or 1)
		local digits = #tostring(math.floor(finalReward))
		local divisor = 10 ^ (math.max(1, digits - 2)) 
		cash.Value += math.floor(finalReward / divisor + 0.5) * divisor

	elseif rewardData.Type == "Gems" then
		gems.Value += rewardData.Amount

	elseif rewardData.Type == "ItemRain" then
		local plot = FindPlayerPlot(player)
		if plot then
			local itemsFolder = plot:FindFirstChild("Items")
			local floor = plot:FindFirstChild("Floor")
			local baseLevel = math.max(1, values:FindFirstChild("HighestMerge") and values.HighestMerge.Value or 1)
			if itemsFolder and floor then
				for i = 1, rewardData.Amount do
					local template = BrainrotCache[baseLevel] or BrainrotCache[1]
					if template then
						local randomItem = template:Clone()
						local rX = math.random(-25, 25)
						local rZ = math.random(-25, 25)
						local spawnPos = floor.Position + Vector3.new(rX, 40, rZ) 
						randomItem.Parent = itemsFolder
						local root = randomItem.PrimaryPart or randomItem:FindFirstChildWhichIsA("BasePart", true)
						if randomItem:IsA("Model") then randomItem:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(math.random(), math.random(), math.random()))
						elseif root then root.Position = spawnPos end
						if root then
							root.Anchored = false
							root.CanCollide = true
							pcall(function() root.CollisionGroup = "Default" end) 
							root.AssemblyLinearVelocity = Vector3.new(0, -50, 0)
						end
						task.wait(0.05) 
					end
				end
			end
		end
	elseif rewardData.Type == "GemStorm" then
		StartGemStorm:FireClient(player, 15)
	end

	slotVal.Value = true
	return true
end