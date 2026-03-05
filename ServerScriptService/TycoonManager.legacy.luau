--[[ ServerScriptService/TycoonManager.legacy.luau ]] -- 

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local PS = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local AchievementManager = require(game.ServerScriptService.AchievementManager)

local remotes = RS:WaitForChild("TycoonRemotes")
local map = Workspace:WaitForChild("TycoonMap")
local fxEvent = remotes:WaitForChild("PlayFX")

-- [[ NEW REMOTE FOR BURSTING GEMS ]] --
local spawnGemBurst = remotes:FindFirstChild("SpawnGemBurst") or Instance.new("RemoteEvent", remotes)
spawnGemBurst.Name = "SpawnGemBurst"

-- [[ MERGE ALL BINDABLE ]] --
local mergeBindable = RS:FindFirstChild("MergeAllBindable") or Instance.new("BindableEvent", RS)
mergeBindable.Name = "MergeAllBindable"

-- [[ CONFIGURATION ]] --
local CARRY_ANIM_ID = "rbxassetid://110453759466328" 
local HOLD_DISTANCE_BUFFER = 1.0 
local HOVER_HEIGHT = 5.0 
local PLAYER_ROOT_TO_FLOOR = 3.0 

-- [[ ECONOMY CONSTANTS ]] --
local BASE_ITEM_VALUE = 8     
local VALUE_EXPONENT = 2.4  
local MERGE_REWARD_MULT = 15  

-- [[ BUY NOW QUICK PRODUCT IDS ]] --
local BUY_NOW_CHEAP = 3542398418
local BUY_NOW_MED = 3542398321
local BUY_NOW_EXP = 3542397983

-- [[ REMOTES SETUP ]] --
local requestDropFunc = remotes:FindFirstChild("RequestDrop") or Instance.new("BindableFunction", remotes)
requestDropFunc.Name = "RequestDrop"
local requestPickupFunc = remotes:FindFirstChild("RequestPickup") or Instance.new("BindableFunction", remotes)
requestPickupFunc.Name = "RequestPickup"
local unlockEvent = remotes:FindFirstChild("UnlockItem") or Instance.new("RemoteEvent", remotes)
unlockEvent.Name = "UnlockItem"
local mergeFunc = remotes:FindFirstChild("TryMergeLocal") or Instance.new("RemoteFunction", remotes)
mergeFunc.Name = "TryMergeLocal"
local upgradeFunc = remotes:FindFirstChild("UpgradeMachine") or Instance.new("RemoteFunction", remotes)
upgradeFunc.Name = "UpgradeMachine"

local Brainrots = RS:WaitForChild("Brainrots", 10)
local BrainrotCache = {}
for _, model in pairs(Brainrots:GetChildren()) do
	local lvlObj = model:FindFirstChild("Level")
	if lvlObj and lvlObj:IsA("IntValue") then
		BrainrotCache[lvlObj.Value] = model
	end
end

local heldAnimTracks = {} 
local heldItems = {}
local playerCombos = {}

local ReleaseItem

Players.PlayerRemoving:Connect(function(player)
	playerCombos[player] = nil
	if heldItems[player] then
		ReleaseItem(player)
	end
	heldItems[player] = nil
	heldAnimTracks[player] = nil
end)

local SUFFIXES = {"k", "mil", "bil", "tril", "quad", "quin", "sext", "sept", "oct", "non", "dec"}
local function FormatNumber(n)
	if not n then return "0" end
	if n < 1000 then return tostring(math.floor(n)) end
	local index = math.floor(math.log10(n) / 3)
	local suffix = SUFFIXES[math.min(index, #SUFFIXES)] or "?"
	local divisor = 10 ^ (index * 3)
	local num = n / divisor
	return string.format("%.2f%s", num, suffix)
end

-- [[ SERVER CONFIGURATION ]] --
local CONFIG = {
	PipeSpeed = { BaseCost = 250, Multiplier = 3.15, MaxLevel = 30 },
	PipeLevel = { BaseCost = 5000, Multiplier = 2.42, MaxLevel = 147 }, 
	PipeLuck  = { BaseCost = 10000, Multiplier = 12.5, MaxLevel = 20 },
	PipeCapacity = { BaseCost = 15000, Multiplier = 22.0, MaxLevel = 10 },
	SellValue = { BaseCost = 7500, Multiplier = 15.0, MaxLevel = 20 },
	MoneyGeneration = { BaseCost = 5000, Multiplier = 24.0, MaxLevel = 15 },
	Grinder = { BaseCost = 1000, Multiplier = 4.6, MaxLevel = 50 },
}

-- [[ PAID CONFIG ]] --
local PAID_CONFIG = {
	MaxPetsStorage = { Cost = 1000, Type = "Limit", Increment = 100, HardCap = 200 },
	MaxPetsEquipped = { Cost = 1500, Type = "Limit", Increment = 100, HardCap = 8 },
	Boost_2xCash = { Cost = 200, Type = "Boost", Duration = 60 },
	Boost_5xCash = { Cost = 400, Type = "Boost", Duration = 60 },
	Boost_10xCash = { Cost = 1000, Type = "Boost", Duration = 60 },
	Boost_2xSpinLuck = { Cost = 200, Type = "Boost", Duration = 60 },
	Boost_2xSpinSpeed = { Cost = 200, Type = "Boost", Duration = 60 },
	Boost_2xCashGenerationSpeed = { Cost = 200, Type = "Boost", Duration = 60 },
	OfflineMergeRate = { Cost = 100, Type = "StandardPaid", MaxLevel = 25 },
	OfflineMergeTime = { Cost = 100, Type = "StandardPaid", MaxLevel = 48 },
}

local BUTTON_MAP = {
	["Storage"] = "MaxPetsStorage",
	["Equip"] = "MaxPetsEquipped",
	["Equips"] = "MaxPetsEquipped",
	["2x Cash"] = "Boost_2xCash",
	["5x Cash"] = "Boost_5xCash",
	["10x Cash"] = "Boost_10xCash",
	["Spin Luck"] = "Boost_2xSpinLuck",
	["Spin Speed"] = "Boost_2xSpinSpeed",
	["Gen Speed"] = "Boost_2xCashGenerationSpeed"
}

-- [[ HELPER: OWNERSHIP CHECK ]] --
local function GetPhysicsPart(item)
	if not item then return nil end
	if item:IsA("Model") then
		if item.PrimaryPart then return item.PrimaryPart end
		return item:FindFirstChildWhichIsA("BasePart", true)
	elseif item:IsA("BasePart") then return item end
	return nil
end

local function GetPlotFromItem(item)
	local current = item
	while current and current ~= Workspace do
		if current.Parent == map then return current end 
		current = current.Parent
	end
	return nil
end

local function VerifyOwnership(player, item)
	if not item then return false end
	local plot = GetPlotFromItem(item)
	if not plot then return false end
	local ownerVal = plot:FindFirstChild("Owner")
	return ownerVal and ownerVal.Value == player
end

local function GetCost(typeName, currentLevel)
	if not CONFIG[typeName] then return 99999999 end
	return math.floor(CONFIG[typeName].BaseCost * (CONFIG[typeName].Multiplier ^ (currentLevel - 1)))
end

local function UnlockRarityForPlayer(player, level, rarity)
	if not player or rarity <= 0 then return end
	local urFolder = player:FindFirstChild("UnlockedRarities")
	if not urFolder then return end

	local lvlStr = tostring(level)
	local rarStr = tostring(rarity)

	local val = urFolder:FindFirstChild(lvlStr)
	if not val then
		val = Instance.new("StringValue", urFolder)
		val.Name = lvlStr
		val.Value = rarStr
	else
		local rarities = string.split(val.Value, ",")
		local found = false
		for _, r in ipairs(rarities) do
			if r == rarStr then found = true break end
		end
		if not found then
			val.Value = val.Value .. "," .. rarStr
		end
	end
end

local function CalculateDynamicCash(player, multiplier)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return 1000 end
	local highest = ls:FindFirstChild("HighestMerge") and ls.HighestMerge.Value or 1
	local bestItemValue = BASE_ITEM_VALUE * (VALUE_EXPONENT ^ (highest - 1))
	local reb = ls:FindFirstChild("Rebirths")
	if reb then bestItemValue = bestItemValue * (1 + (reb.Value * 0.5)) end
	local rawAmount = bestItemValue * multiplier
	if rawAmount > 1000 then
		local magnitude = 10 ^ math.floor(math.log10(rawAmount))
		rawAmount = math.floor(rawAmount / magnitude * 10) / 10 * magnitude
	end
	return math.max(rawAmount, 500)
end

local function GetTotalCashMult(player)
	if not player then return 1 end

	local rebMult = 1
	if player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Rebirths") then
		local r = player.leaderstats.Rebirths.Value
		if r > 0 then rebMult = (1 + (r * 0.5)) end
	end

	local petMult = 1
	if player:FindFirstChild("Values") and player.Values:FindFirstChild("Multiplier1") then
		petMult = tonumber(player.Values.Multiplier1.Value) or 1
	end

	local shopMult = 1
	if player:FindFirstChild("Values") and player.Values:FindFirstChild("CashMultiplier") then
		shopMult = player.Values.CashMultiplier.Value
	end

	local inviteMult = 0
	if player:FindFirstChild("Values") and player.Values:FindFirstChild("InviteMultiplier") then
		inviteMult = player.Values.InviteMultiplier.Value
	end

	local boostMult = 1
	local now = workspace:GetServerTimeNow()
	if player:GetAttribute("Boost_2xCash_End") and player:GetAttribute("Boost_2xCash_End") > now then boostMult = boostMult * 2 end
	if player:GetAttribute("Boost_5xCash_End") and player:GetAttribute("Boost_5xCash_End") > now then boostMult = boostMult * 5 end
	if player:GetAttribute("Boost_10xCash_End") and player:GetAttribute("Boost_10xCash_End") > now then boostMult = boostMult * 10 end

	local additiveTotal = (rebMult + petMult + shopMult) - 2 + inviteMult
	if additiveTotal < 1 then additiveTotal = 1 end

	return additiveTotal * boostMult
end

local function CalculateItemValue(level, player, rarityLevel)
	local rawValue = BASE_ITEM_VALUE * (VALUE_EXPONENT ^ (level - 1))
	local sellMult = 1
	if player and player:FindFirstChild("Upgrades") and player.Upgrades:FindFirstChild("SellValue") then
		local svLvl = player.Upgrades.SellValue.Value
		sellMult = 1 + ((svLvl - 1) * 0.2) 
	end
	local totalMult = GetTotalCashMult(player)

	local rarityMult = 1
	rarityLevel = rarityLevel or 0
	if rarityLevel == 1 then rarityMult = 5
	elseif rarityLevel == 2 then rarityMult = 10
	elseif rarityLevel == 3 then rarityMult = 25
	elseif rarityLevel == 4 then rarityMult = 100
	end

	return rawValue * sellMult * totalMult * rarityMult
end

local function ApplyRarityVisuals(item, rarityTier)
	local root = item:FindFirstChildWhichIsA("BasePart", true)
	if item:IsA("Model") and item.PrimaryPart then root = item.PrimaryPart end
	if not root then return end

	local rarityUI = root:FindFirstChild("RarityUI") or item:FindFirstChild("RarityUI", true)

	if rarityTier <= 0 then
		if rarityUI then rarityUI.Enabled = false end
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("ParticleEmitter") then child.Enabled = false end
		end
		return
	end

	local textLabel, grad
	if rarityUI then
		rarityUI.Enabled = true
		textLabel = rarityUI:FindFirstChildWhichIsA("TextLabel", true)
		if textLabel then grad = textLabel:FindFirstChildWhichIsA("UIGradient") end
	end

	local pColor, pRate, pText
	if rarityTier == 1 then
		pText = "LEGENDARY"
		pColor = ColorSequence.new(Color3.fromRGB(255, 170, 0))
		pRate = 8
	elseif rarityTier == 2 then
		pText = "MYTHIC"
		pColor = ColorSequence.new(Color3.fromRGB(255, 0, 0))
		pRate = 15
	elseif rarityTier == 3 then
		pText = "BRAINROT GOD"
		pColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.8, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255))
		})
		pRate = 25
	elseif rarityTier == 4 then
		pText = "SECRET"
		pColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
		})
		pRate = 40
	end

	if textLabel then textLabel.Text = pText end
	if grad and pColor then grad.Color = pColor end

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			child.Enabled = true
			child.Color = pColor
			child.Rate = pRate
			child.LightEmission = 0.2
			child.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), 
				NumberSequenceKeypoint.new(0.5, 1), 
				NumberSequenceKeypoint.new(1, 0)
			})
			child.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(0.5, 0.3),
				NumberSequenceKeypoint.new(1, 1)
			})
		end
	end
end

local function AddStabilizer(part)
	for _, c in pairs(part:GetChildren()) do
		if c.Name == "UprightGyro" then c:Destroy() end 
	end
	local bg = Instance.new("BodyGyro")
	bg.Name = "UprightGyro"
	bg.MaxTorque = Vector3.new(400000, 0, 400000)
	bg.P = 3000;
	bg.D = 500;
	bg.CFrame = CFrame.new() 
	bg.Parent = part
end

local function PlaceOnFloorCorrectly(item, targetX, targetZ, floorY)
	local cf, size
	if item:IsA("Model") then cf, size = item:GetBoundingBox()
	else cf = item.CFrame; size = item.Size end
	local currentBottomY = cf.Position.Y - (size.Y / 2)
	local requiredLift = floorY - currentBottomY
	local currentPivot = item:GetPivot()
	local targetCFrame = CFrame.new(targetX, currentPivot.Position.Y, targetZ) * currentPivot.Rotation
	item:PivotTo(targetCFrame + Vector3.new(0, requiredLift + HOVER_HEIGHT, 0))
end

local function SetupModelPhysics(item, groupName, massState)
	local primary = GetPhysicsPart(item)
	for _, part in pairs(item:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
			if part ~= primary then
				part.Massless = true; part.CanCollide = false
			else
				part.Massless = massState
			end
		end
	end
	if item:IsA("BasePart") then
		item.CollisionGroup = groupName; item.Massless = massState
	end
end

local function PlayCarryAnim(player)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChild("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChild("Animator") or Instance.new("Animator", humanoid)
	local anim = Instance.new("Animation")
	anim.AnimationId = CARRY_ANIM_ID
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play()
	heldAnimTracks[player] = track
end

local function StopCarryAnim(player)
	if heldAnimTracks[player] then
		heldAnimTracks[player]:Stop()
		heldAnimTracks[player] = nil
	end
end

-- [[ COLLISION GROUPS ]] --
local barriersGroup = "TycoonBarriers"
local itemsGroup = "TycoonItems"
local playersGroup = "TycoonPlayers"
local holdingGroup = "TycoonPlayersHolding"

pcall(function() PS:RegisterCollisionGroup(barriersGroup) end)
pcall(function() PS:RegisterCollisionGroup(itemsGroup) end)
pcall(function() PS:RegisterCollisionGroup(playersGroup) end)
pcall(function() PS:RegisterCollisionGroup(holdingGroup) end)

pcall(function() PS:CollisionGroupSetCollidable(itemsGroup, "Default", true) end)
pcall(function() PS:CollisionGroupSetCollidable(barriersGroup, itemsGroup, true) end)
pcall(function() PS:CollisionGroupSetCollidable(barriersGroup, playersGroup, false) end)
pcall(function() PS:CollisionGroupSetCollidable(barriersGroup, holdingGroup, true) end)
pcall(function() PS:CollisionGroupSetCollidable(playersGroup, playersGroup, false) end)
pcall(function() PS:CollisionGroupSetCollidable(holdingGroup, holdingGroup, false) end)
pcall(function() PS:CollisionGroupSetCollidable(playersGroup, holdingGroup, false) end)
pcall(function() PS:CollisionGroupSetCollidable(itemsGroup, playersGroup, false) end)
pcall(function() PS:CollisionGroupSetCollidable(itemsGroup, holdingGroup, false) end)
pcall(function() PS:CollisionGroupSetCollidable(itemsGroup, itemsGroup, true) end)

local function SetPlayerCollision(char, groupName)
	if not char then return end
	for _, part in pairs(char:GetDescendants()) do
		if part:IsA("BasePart") then part.CollisionGroup = groupName end
	end
end

local function AssignPlayerGroup(char)
	SetPlayerCollision(char, playersGroup)
	char.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then 
			local player = Players:GetPlayerFromCharacter(char)
			if player and player:GetAttribute("IsHolding") then
				part.CollisionGroup = holdingGroup
			else
				part.CollisionGroup = playersGroup
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(AssignPlayerGroup)
	if plr.Character then AssignPlayerGroup(plr.Character) end
end)

-- [[ UPGRADE HANDLER ]] --
upgradeFunc.OnServerInvoke = function(player, typeName)
	local ls = player:FindFirstChild("leaderstats")
	local upg = player:FindFirstChild("Upgrades")
	if not ls then return false end
	if BUTTON_MAP[typeName] then typeName = BUTTON_MAP[typeName] end

	if PAID_CONFIG and PAID_CONFIG[typeName] then
		local conf = PAID_CONFIG[typeName]
		local gems = ls:FindFirstChild("Gems")
		if gems then
			if gems.Value >= conf.Cost then
				if conf.Type == "StandardPaid" then
					local lvlObj = player:FindFirstChild("Upgrades") and player.Upgrades:FindFirstChild(typeName)
					if lvlObj and lvlObj.Value < conf.MaxLevel then
						gems.Value -= conf.Cost
						lvlObj.Value += 1
						return true
					end
					return false
				elseif conf.Type == "Limit" then
					local values = player:FindFirstChild("Values")
					if values then
						local targetVal = values:FindFirstChild(typeName)
						if targetVal and targetVal.Value < conf.HardCap then
							gems.Value -= conf.Cost
							targetVal.Value += conf.Increment
							if typeName == "MaxPetsStorage" and targetVal.Value >= conf.HardCap then
								AchievementManager.Award(player, "StorageWars")
							elseif typeName == "MaxPetsEquipped" and targetVal.Value >= conf.HardCap then
								AchievementManager.Award(player, "PetArmy")
							end
							return true
						end
					end
				elseif conf.Type == "Boost" then
					gems.Value -= conf.Cost
					local now = workspace:GetServerTimeNow()
					local attrName = typeName .. "_End"
					local currentEnd = player:GetAttribute(attrName) or 0
					if currentEnd < now then currentEnd = now end
					player:SetAttribute(attrName, currentEnd + conf.Duration)
					return true
				end
			else
				local deficit = conf.Cost - gems.Value
				player:SetAttribute("LastDeficitAmount", deficit)
				player:SetAttribute("LastDeficitCurrency", "Gems")
				local pid = BUY_NOW_CHEAP
				if deficit > 1000 then pid = BUY_NOW_EXP
				elseif deficit > 200 then pid = BUY_NOW_MED end

				task.spawn(function()
					MarketplaceService:PromptProductPurchase(player, pid)
				end)
			end
		end
		return false
	end

	local cash = ls:FindFirstChild("Cash")
	local lvlObj = upg and upg:FindFirstChild(typeName)
	if not lvlObj then return false end
	if cash and lvlObj and CONFIG and CONFIG[typeName] then
		local cost = GetCost(typeName, lvlObj.Value)
		local um = player:FindFirstChild("Values") and player.Values:FindFirstChild("UnlimitedMoney")
		if um and um.Value == true then cost = 0 end
		if cash.Value >= cost and lvlObj.Value < CONFIG[typeName].MaxLevel then
			cash.Value -= cost
			lvlObj.Value += 1
			return true
		elseif lvlObj.Value < CONFIG[typeName].MaxLevel then
			local deficit = cost - cash.Value
			player:SetAttribute("LastDeficitAmount", deficit)
			player:SetAttribute("LastDeficitCurrency", "Cash")

			local small = CalculateDynamicCash(player, 50)
			local med = CalculateDynamicCash(player, 250)

			local pid = BUY_NOW_CHEAP
			if deficit > med then pid = BUY_NOW_EXP
			elseif deficit > small then pid = BUY_NOW_MED end

			task.spawn(function()
				MarketplaceService:PromptProductPurchase(player, pid)
			end)
		end
	end
	return false
end

-- [[ ITEM HANDLING ]] --
ReleaseItem = function(player)
	if not player then return end
	local item = heldItems[player]
	local char = player.Character
	if char then
		if char:FindFirstChild("HumanoidRootPart") then
			local root = char.HumanoidRootPart
			if root:FindFirstChild("CarryWeld") then root.CarryWeld:Destroy() end
		end
		SetPlayerCollision(char, playersGroup)
	end
	if item then
		local primary = GetPhysicsPart(item)
		if primary then
			if primary:FindFirstChild("CarryWeld") then primary.CarryWeld:Destroy() end
			item:SetAttribute("HeldBy", nil)
			SetupModelPhysics(item, itemsGroup, false) 
			primary.CanCollide = true 
			AddStabilizer(primary)
			if primary.Parent and not primary.Anchored then primary:SetNetworkOwner(nil) end
		end
	end
	StopCarryAnim(player)
	heldItems[player] = nil
	player:SetAttribute("IsHolding", false)
	return item
end

requestDropFunc.OnInvoke = function(player) return ReleaseItem(player) end

local function PickupItem(player, item)
	if heldItems[player] then return end
	if not item or not item.Parent then return end
	if item:GetAttribute("HeldBy") then return end 

	if not VerifyOwnership(player, item) then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local primary = GetPhysicsPart(item)
	if not primary then return end

	-- Check for Humanoid and safely extract it
	local hasHumanoid = false
	for _, h in pairs(item:GetDescendants()) do 
		if h:IsA("Humanoid") then 
			hasHumanoid = true
			h.BreakJointsOnDeath = false -- Prevent Motor6Ds from shattering
			h:Destroy() 
		end 
	end

	-- If it had a Humanoid, weld all pieces to the root so it doesn't fall apart
	if hasHumanoid then
		for _, p in pairs(item:GetDescendants()) do 
			if p:IsA("BasePart") and p ~= primary then
				local w = Instance.new("WeldConstraint")
				w.Name = "ModelStructureWeld"
				w.Part0 = primary
				w.Part1 = p
				w.Parent = primary
			end 
		end
	end

	for _, p in pairs(item:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false end end
	if primary.Parent and not primary.Anchored then primary:SetNetworkOwner(player) end

	item:SetAttribute("ThrownBy", nil)
	item:SetAttribute("JustThrown", nil)
	item:SetAttribute("MergeCooldown", nil)

	if primary:FindFirstChild("UprightGyro") then primary.UprightGyro:Destroy() end
	primary.CanCollide = false
	primary.CustomPhysicalProperties = PhysicalProperties.new(10, 1.0, 0.3, 100, 100)

	local cf, size
	if item:IsA("Model") then cf, size = item:GetBoundingBox() else cf = item.CFrame; size = item.Size end

	local holdDist = (size.Z / 2) + HOLD_DISTANCE_BUFFER 
	local distToFeet = primary.Position.Y - (cf.Position.Y - (size.Y / 2)) - PLAYER_ROOT_TO_FLOOR
	local targetOffset = CFrame.new(0, distToFeet, -holdDist)

	if item:IsA("Model") then
		local holdCF = root.CFrame * targetOffset
		local rx, ry, rz = root.CFrame.Rotation:ToEulerAnglesYXZ()
		item:PivotTo(CFrame.new(holdCF.Position) * CFrame.fromEulerAnglesYXZ(0, ry, 0))
	else
		primary.CFrame = root.CFrame * targetOffset
	end

	local weld = Instance.new("WeldConstraint", root)
	weld.Name = "CarryWeld"
	weld.Part0 = root
	weld.Part1 = primary

	heldItems[player] = item
	item:SetAttribute("HeldBy", player.Name)
	player:SetAttribute("IsHolding", true)
	if primary.Parent and not primary.Anchored then primary:SetNetworkOwner(player) end
	SetPlayerCollision(char, holdingGroup)
	SetupModelPhysics(item, holdingGroup, true)
	PlayCarryAnim(player)
end

requestPickupFunc.OnInvoke = function(player, item) PickupItem(player, item); return true end

remotes.Pickup.OnServerEvent:Connect(function(player, hitPart)
	if heldItems[player] then return end
	if not hitPart or not hitPart:IsDescendantOf(Workspace) then return end
	local item
	if hitPart.Parent and hitPart.Parent:IsA("Model") and hitPart.Parent:FindFirstChild("Level", true) then
		item = hitPart.Parent
	elseif hitPart:IsA("BasePart") and hitPart:FindFirstChild("Level", true) then
		item = hitPart
	end

	if item and item.Name ~= "HostedItem" then
		if VerifyOwnership(player, item) then
			local physicsPart = GetPhysicsPart(item)
			if physicsPart then
				local dist = (player.Character.HumanoidRootPart.Position - physicsPart.Position).Magnitude
				if dist < 30 then PickupItem(player, item) end
			end
		end
	end
end)

remotes.Throw.OnServerEvent:Connect(function(player, powerPct)
	local item = heldItems[player]
	if not item then return end
	local primary = GetPhysicsPart(item)
	if not primary then return end
	if primary:FindFirstChild("CarryWeld") then primary.CarryWeld:Destroy() end
	local root, char = nil, player.Character
	if char then 
		root = char:FindFirstChild("HumanoidRootPart")
		if root and root:FindFirstChild("CarryWeld") then root.CarryWeld:Destroy() end
		SetPlayerCollision(char, playersGroup)
	end
	StopCarryAnim(player)
	primary.CanCollide = true
	item:SetAttribute("HeldBy", nil)
	SetupModelPhysics(item, itemsGroup, false) 
	AddStabilizer(primary) 
	if primary.Parent and not primary.Anchored then
		primary:SetNetworkOwner(player)
		if root then
			local lookVec = root.CFrame.LookVector
			primary.CustomPhysicalProperties = PhysicalProperties.new(10, 0.2, 0.1, 100, 100)
			local gyro = Instance.new("BodyGyro", primary)
			gyro.Name = "ThrowGyro"
			gyro.MaxTorque = Vector3.new(400000, 0, 400000)
			gyro.P = 3000; gyro.D = 500; gyro.CFrame = CFrame.new() 
			primary.AssemblyLinearVelocity = (lookVec * 100) + Vector3.new(0, 15, 0)
			primary.AssemblyAngularVelocity = Vector3.new(0,0,0)
			task.delay(1, function()
				if primary and primary.Parent then
					primary.CustomPhysicalProperties = PhysicalProperties.new(10, 0.8, 0.3, 100, 100)
					if gyro then gyro:Destroy() end
					AddStabilizer(primary)
					if not item:GetAttribute("HeldBy") then primary:SetNetworkOwner(nil) end
				end
			end)
		end
	end
	fxEvent:FireClient(player, "Throw", primary.Position)
	heldItems[player] = nil
	player:SetAttribute("IsHolding", false)
	item:SetAttribute("ThrownBy", player.Name)
	item:SetAttribute("JustThrown", true)
	task.delay(1.5, function() if item and item.Parent then item:SetAttribute("JustThrown", nil); item:SetAttribute("ThrownBy", nil) end end)
	AchievementManager.Award(player, "Yeet")
end)

remotes.SellItem.OnServerEvent:Connect(function(player)
	local item = ReleaseItem(player)
	if not item then return end

	if not VerifyOwnership(player, item) then item:Destroy(); return end

	local um = player:FindFirstChild("Values") and player.Values:FindFirstChild("UnlimitedMoney")
	if um and um.Value == true then item:Destroy(); return end
	local lvl = item:FindFirstChild("Level", true)
	local primary = GetPhysicsPart(item)
	if lvl and primary then
		local level = lvl.Value
		local rarity = item:GetAttribute("Rarity") or 0
		local singleItemValue = CalculateItemValue(level, player, rarity)
		local grindLvl = 1
		if player:FindFirstChild("Upgrades") then grindLvl = player.Upgrades.Grinder.Value end
		local grinderMult = 1 + ((grindLvl - 1) * 0.2) 
		local finalCash = math.floor(singleItemValue * grinderMult)
		if player:FindFirstChild("leaderstats") then
			local cashObj = player.leaderstats:FindFirstChild("Cash")
			if cashObj then
				if cashObj:IsA("IntValue") then
					local MAX_INT = 2147483647
					if cashObj.Value + finalCash > MAX_INT or cashObj.Value + finalCash < 0 then
						cashObj.Value = MAX_INT
					else
						cashObj.Value += finalCash
					end
				else
					cashObj.Value += finalCash
				end
				AchievementManager.Award(player, "FirstSale")
			end
		end
		fxEvent:FireClient(player, "Sell", primary.Position, {Cash = finalCash, Formatted = FormatNumber(finalCash)})
	end
	item:Destroy()
end)

local function PerformMerge(player, item1, item2, ignoreDistance)
	if not item1 or not item2 then return false end
	if item1.Name == "HostedItem" or item2.Name == "HostedItem" then return false end
	if not item1.Parent or not item2.Parent then return false end
	if item1 == item2 then return false end

	-- DEBOUNCE
	if item1:GetAttribute("ServerMerging") or item2:GetAttribute("ServerMerging") then return false end
	item1:SetAttribute("ServerMerging", true)
	item2:SetAttribute("ServerMerging", true)

	local plot1 = GetPlotFromItem(item1)
	local plot2 = GetPlotFromItem(item2)
	if not plot1 or not plot2 or plot1 ~= plot2 then return false end

	if not player then
		local ownerVal = plot1:FindFirstChild("Owner")
		if ownerVal and ownerVal.Value then player = ownerVal.Value end
	else
		local ownerVal = plot1:FindFirstChild("Owner")
		if not ownerVal or ownerVal.Value ~= player then return false end
	end

	local lvl1 = item1:FindFirstChild("Level", true)
	local lvl2 = item2:FindFirstChild("Level", true)
	if not lvl1 or not lvl2 or lvl1.Value ~= lvl2.Value then return false end

	local primary1 = GetPhysicsPart(item1)
	local primary2 = GetPhysicsPart(item2)

	if not ignoreDistance and not item1:GetAttribute("JustThrown") and not item2:GetAttribute("JustThrown") then
		if primary1 and primary2 then
			if (primary1.Position - primary2.Position).Magnitude > 25 then
				return false
			end
		end
	end

	local rarity1 = item1:GetAttribute("Rarity") or 0
	local rarity2 = item2:GetAttribute("Rarity") or 0
	local maxRarity = math.max(rarity1, rarity2)
	local newRarity = math.max(0, maxRarity - 1)

	local level = lvl1.Value
	local nextLevel = level + 1
	local isLucky = false

	if player and player:FindFirstChild("Upgrades") and player.Upgrades:FindFirstChild("PipeLuck") then
		local luckLvl = player.Upgrades.PipeLuck.Value
		if math.random() <= (0.05 + (luckLvl * 0.02)) then 
			if BrainrotCache[level + 2] then
				nextLevel = level + 2
				isLucky = true
			end
		end
	end

	local template = BrainrotCache[nextLevel]

	if not template then return false end 

	if player and heldItems[player] and (heldItems[player] == item1 or heldItems[player] == item2) then
		ReleaseItem(player)
	end

	local mergeCenter = (primary1.Position + primary2.Position) * 0.5
	local floorY = 0.5
	if item1.Parent and item1.Parent.Parent and item1.Parent.Parent:FindFirstChild("Floor") then
		local f = item1.Parent.Parent.Floor
		floorY = f.Position.Y + (f.Size.Y * 0.5)
	end

	item1:Destroy()
	item2:Destroy()

	local currentCombo = 1
	if player then
		local now = workspace:GetServerTimeNow()
		if not playerCombos[player] then 
			playerCombos[player] = {count = 1, lastTime = 0} 
		end

		if now - playerCombos[player].lastTime < 1.5 then
			playerCombos[player].count = playerCombos[player].count + 1 
		else
			playerCombos[player].count = 1
		end
		playerCombos[player].lastTime = now
		currentCombo = playerCombos[player].count
	end

	if player and player:FindFirstChild("leaderstats") then
		local um = player:FindFirstChild("Values") and player.Values:FindFirstChild("UnlimitedMoney")
		local cashReward = 0
		local gemReward = 0

		local rareMergeCashMult = 1
		local rareMergePhysicalGemAmount = 0

		if maxRarity == 1 then rareMergeCashMult = 5; rareMergePhysicalGemAmount = 2
		elseif maxRarity == 2 then rareMergeCashMult = 15; rareMergePhysicalGemAmount = 4
		elseif maxRarity == 3 then rareMergeCashMult = 35; rareMergePhysicalGemAmount = 6
		elseif maxRarity == 4 then rareMergeCashMult = 150; rareMergePhysicalGemAmount = 10
		end

		if not um or um.Value == false then
			local nextItemValue = CalculateItemValue(nextLevel, player, 0)
			cashReward = math.floor(nextItemValue * MERGE_REWARD_MULT * currentCombo * rareMergeCashMult)

			local cashObj = player.leaderstats:FindFirstChild("Cash")
			if cashObj then
				if cashObj:IsA("IntValue") then
					local MAX_INT = 2147483647
					if cashObj.Value + cashReward > MAX_INT or cashObj.Value + cashReward < 0 then
						cashObj.Value = MAX_INT
					else
						cashObj.Value += cashReward
					end
				else
					cashObj.Value += cashReward
				end
			end
		end

		local gems = player.leaderstats:FindFirstChild("Gems")
		if gems then
			local gMult = 1
			if player:FindFirstChild("Values") and player.Values:FindFirstChild("GemsMultiplier") then
				gMult = player.Values.GemsMultiplier.Value
			end
			local amount = math.max(1, math.floor(1 * gMult * currentCombo))

			if gems:IsA("IntValue") then
				local MAX_INT = 2147483647
				if gems.Value + amount > MAX_INT or gems.Value + amount < 0 then
					gems.Value = MAX_INT
				else
					gems.Value += amount
				end
			else
				gems.Value += amount
			end

			gemReward = amount
		end

		if maxRarity > 0 then
			spawnGemBurst:FireClient(player, mergeCenter, rareMergePhysicalGemAmount)
		end

		fxEvent:FireClient(player, "Merge", mergeCenter, {Cash = cashReward, Gems = gemReward, Formatted = FormatNumber(cashReward), Combo = currentCombo, IsLucky = isLucky, RareTier = maxRarity})

		if player.leaderstats:FindFirstChild("HighestMerge") then
			if nextLevel > player.leaderstats.HighestMerge.Value then
				player.leaderstats.HighestMerge.Value = nextLevel
			end
		end

		local vals = player:FindFirstChild("Values")
		if vals and vals:FindFirstChild("AllTimeHighestMerge") then
			if nextLevel > vals.AllTimeHighestMerge.Value then
				vals.AllTimeHighestMerge.Value = nextLevel
				unlockEvent:FireClient(player, nextLevel)
			end
		end
	end

	local newItem = template:Clone()
	local newPrimary = GetPhysicsPart(newItem)
	local lObj = newItem:FindFirstChild("Level", true)
	if lObj then lObj.Value = nextLevel end
	newItem:SetAttribute("Rarity", newRarity)
	ApplyRarityVisuals(newItem, newRarity)

	if plot1 and plot1:FindFirstChild("Items") then
		newItem.Parent = plot1.Items
	elseif player and player:FindFirstChild("MyPlot") and player.MyPlot.Value then
		newItem.Parent = player.MyPlot.Value.Items
	end

	PlaceOnFloorCorrectly(newItem, mergeCenter.X, mergeCenter.Z, floorY)
	if newPrimary then
		newPrimary.CanCollide = true; newPrimary.Anchored = false
		SetupModelPhysics(newItem, itemsGroup, false)
		AddStabilizer(newPrimary)
		if player then newPrimary:SetNetworkOwner(player)
		else
			local plot = newItem.Parent and newItem.Parent.Parent
			local ownerVal = plot and plot:FindFirstChild("Owner")
			if ownerVal and ownerVal.Value then newPrimary:SetNetworkOwner(ownerVal.Value) else newPrimary:SetNetworkOwner(nil) end
		end
	end

	if player then
		AchievementManager.Award(player, "FirstMerge")
		if maxRarity == 4 then AchievementManager.Award(player, "Secret") end
		if currentCombo >= 5 then AchievementManager.Award(player, "ComboCraze") end 
		if maxRarity > 0 then AchievementManager.Award(player, "GemShower") end
		if item1:GetAttribute("JustThrown") or item2:GetAttribute("JustThrown") then AchievementManager.Award(player, "AirStrike") end

		if player.leaderstats:FindFirstChild("Cash") and player.leaderstats.Cash.Value >= 1000000 then 
			AchievementManager.Award(player, "HighRoller") 
		end
	end

	return true
end

local function TryMergeItems(item1, item2, floor, ignoreDistance) PerformMerge(nil, item1, item2, ignoreDistance) end
mergeFunc.OnServerInvoke = function(player, item1, item2) return PerformMerge(player, item1, item2, false) end

local function GetItemsByLevel(itemsFolder)
	local organized = {}
	for _, item in pairs(itemsFolder:GetChildren()) do
		if item.Name == "HostedItem" then continue end 
		if item:GetAttribute("HeldBy") then continue end 
		local lvl = item:FindFirstChild("Level", true)
		if lvl then
			if not organized[lvl.Value] then organized[lvl.Value] = {} end
			table.insert(organized[lvl.Value], item)
		end
	end
	return organized
end

local function RunMergeAll(player)
	if not player then return end
	local myPlotVal = player:FindFirstChild("MyPlot")
	if not myPlotVal or not myPlotVal.Value then return end
	local itemsFolder = myPlotVal.Value:FindFirstChild("Items")
	if not itemsFolder then return end
	local mergedSomething = true
	while mergedSomething do
		mergedSomething = false
		local organized = GetItemsByLevel(itemsFolder)
		for level, itemList in pairs(organized) do
			if not BrainrotCache[level + 1] then continue end
			while #itemList >= 2 do
				local item1 = table.remove(itemList)
				local item2 = table.remove(itemList)
				local success = PerformMerge(player, item1, item2, true)
				if success then mergedSomething = true end
				task.wait() 
			end
		end
	end
end

remotes:WaitForChild("MergeAll").OnServerEvent:Connect(RunMergeAll)
if mergeBindable then mergeBindable.Event:Connect(RunMergeAll) end

task.spawn(function()
	while true do
		task.wait(1.5)
		for _, player in pairs(Players:GetPlayers()) do
			local vals = player:FindFirstChild("Values")
			if vals and vals:FindFirstChild("AutoMerge") and vals.AutoMerge.Value == true then
				local myPlotVal = player:FindFirstChild("MyPlot")
				if myPlotVal and myPlotVal.Value then
					local itemsFolder = myPlotVal.Value:FindFirstChild("Items")
					if itemsFolder then
						local organized = GetItemsByLevel(itemsFolder)
						for level, itemList in pairs(organized) do
							if not BrainrotCache[level + 1] then continue end 
							for i = 1, #itemList - 1, 2 do
								local item1 = itemList[i]
								local item2 = itemList[i+1]
								local p1 = GetPhysicsPart(item1)
								local p2 = GetPhysicsPart(item2)
								if p1 and p2 and not p1.Anchored and not p2.Anchored then
									if p2:FindFirstChild("AutoMergeAlign") then continue end
									local att1 = Instance.new("Attachment", p1)
									local att2 = Instance.new("Attachment", p2)
									local align = Instance.new("AlignPosition")
									align.Name = "AutoMergeAlign"
									align.Attachment0 = att2
									align.Attachment1 = att1 
									align.Mode = Enum.PositionAlignmentMode.TwoAttachment 
									align.MaxForce = 20000 
									align.MaxVelocity = 8 
									align.Responsiveness = 5 
									align.Parent = p2
									game.Debris:AddItem(align, 2)
									game.Debris:AddItem(att1, 2)
									game.Debris:AddItem(att2, 2)
								end
							end
						end
					end
				end
			end
		end
	end
end)

local function SpawnCashGenLoop(player)
	task.spawn(function()
		while player and player.Parent do
			local waitTime = 3.0 
			local upgrades = player:FindFirstChild("Upgrades")
			if upgrades and upgrades:FindFirstChild("MoneyGeneration") then
				local lvl = upgrades.MoneyGeneration.Value
				waitTime = math.max(0.5, 3.0 * (0.95 ^ (lvl - 1))) 
			end
			local now = workspace:GetServerTimeNow()
			local endGenBoost = player:GetAttribute("Boost_2xCashGenerationSpeed_End")
			if endGenBoost and endGenBoost > now then waitTime = waitTime * 0.5 end
			task.wait(waitTime)
			if not player.Parent then break end 
			local plot = nil
			for _, p in pairs(map:GetChildren()) do
				if p:FindFirstChild("Owner") and p.Owner.Value == player then plot = p break end
			end
			if plot then
				local itemsFolder = plot:FindFirstChild("Items")
				local leaderstats = player:FindFirstChild("leaderstats")
				if itemsFolder and leaderstats then
					local um = player:FindFirstChild("Values") and player.Values:FindFirstChild("UnlimitedMoney")
					if not um or um.Value == false then
						local totalGenerated = 0
						local visualData = {}

						for _, item in pairs(itemsFolder:GetChildren()) do
							if item.Name == "HostedItem" then continue end
							local lvlObj = item:FindFirstChild("Level", true)
							local root = GetPhysicsPart(item)
							if lvlObj and root then
								local lvl = lvlObj.Value
								local rarity = item:GetAttribute("Rarity") or 0

								local itemIncome = CalculateItemValue(lvl, player, rarity)
								if itemIncome > 0 then
									totalGenerated += itemIncome
									table.insert(visualData, {
										Pos = root.Position + Vector3.new(0, 2, 0),
										Amt = math.floor(itemIncome),
										Formatted = FormatNumber(itemIncome)
									})
								end
							end
						end

						local currentFraction = player:GetAttribute("FractionalCash") or 0
						local rawTotal = totalGenerated + currentFraction
						local finalCash = math.floor(rawTotal)
						player:SetAttribute("FractionalCash", rawTotal - finalCash)

						local cashObj = leaderstats:FindFirstChild("Cash")
						if finalCash > 0 and cashObj then
							if cashObj:IsA("IntValue") then
								local MAX_INT = 2147483647
								if cashObj.Value + finalCash > MAX_INT or cashObj.Value + finalCash < 0 then
									cashObj.Value = MAX_INT
								else
									cashObj.Value += finalCash
								end
							else
								cashObj.Value += finalCash
							end
							fxEvent:FireClient(player, "PassiveGen", visualData)
						end
					end
				end
			end
		end
	end)
end

Players.PlayerAdded:Connect(SpawnCashGenLoop)
for _, p in ipairs(Players:GetPlayers()) do SpawnCashGenLoop(p) end

local function MonitorPlot(plot)
	local items = plot:WaitForChild("Items", 10)
	local floor = plot:WaitForChild("Floor", 10)
	if not items or not floor then return end
	local function TryMergeSimple(item, otherItem)
		if not item.Parent or not otherItem.Parent then return end
		if item == otherItem then return end
		local l1 = item:FindFirstChild("Level", true)
		local l2 = otherItem:FindFirstChild("Level", true)
		if l1 and l2 and l1.Value == l2.Value then TryMergeItems(item, otherItem, floor, true) end
	end
	local function SetupItem(item)
		if not item:IsA("Model") and not item:IsA("BasePart") then return end
		if item.Name == "HostedItem" then return end
		local root = GetPhysicsPart(item)
		if not root then return end

		local lvlObj = item:FindFirstChild("Level", true)
		local rarity = item:GetAttribute("Rarity") or 0
		if lvlObj then
			local ownerVal = plot:FindFirstChild("Owner")
			if ownerVal and ownerVal.Value then
				UnlockRarityForPlayer(ownerVal.Value, lvlObj.Value, rarity)
			end
		end

		if item:GetAttribute("Hooked") then return end
		item:SetAttribute("Hooked", true)
		root.CanTouch = true
		SetupModelPhysics(item, itemsGroup, false)
		AddStabilizer(root)
		root.Touched:Connect(function(hit)
			if not hit.Parent then return end
			if item.Name == "HostedItem" then return end
			local otherItem
			if hit.Parent == items then otherItem = hit 
			elseif hit.Parent.Parent == items then otherItem = hit.Parent 
			else return end
			if otherItem.Name == "HostedItem" then return end
			TryMergeSimple(item, otherItem)
		end)
	end
	items.ChildAdded:Connect(SetupItem)
	for _, item in pairs(items:GetChildren()) do SetupItem(item) end
end
for _, plot in pairs(map:GetChildren()) do MonitorPlot(plot) end
map.ChildAdded:Connect(MonitorPlot)