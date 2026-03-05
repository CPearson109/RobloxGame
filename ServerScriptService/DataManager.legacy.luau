-- [[ ServerScriptService/DataManager.legacy.luau ]] --

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local AchievementManager = require(game.ServerScriptService.AchievementManager)

-- [[ CONFIGURATION ]] --
local AUTO_SAVE_INTERVAL = 60
local BASE_ITEM_VALUE = 8 
local VALUE_EXPONENT = 2.4 
local MERGE_REWARD_MULT = 15

-- [[ GAME PASS IDS ]] --
local GP_TRIPLE_HATCH   = 1669674065
local GP_AUTO_HATCH     = 1669971872
local GP_AUTO_MERGE     = 1696656180
local GP_UNLIMITED_CASH = 1697244377
local GP_LUCK_2X        = 1696976602
local GP_LUCK_10X       = 1697208301

-- [[ DEVELOPER PRODUCT IDS ]] --
local PRODUCT_STORAGE_ID = 3526806180
local PRODUCT_EQUIP_ID   = 3526816002
local PRODUCT_MERGE_ALL  = 3528601422
local PRODUCT_2X_CASH    = 3528635219
local PRODUCT_2X_GEMS    = 3528635351
local PRODUCT_SPIN_1     = 3527168757
local PRODUCT_SPIN_3     = 3527168889
local PRODUCT_SPIN_10    = 3527169008
local PRODUCT_PET_1      = 3528600474 
local PRODUCT_PET_2      = 3528600588 
local PRODUCT_PET_3      = 3528600746 
local PRODUCT_CASH_SMALL  = 3528600992
local PRODUCT_CASH_MEDIUM = 3528601054
local PRODUCT_CASH_LARGE  = 3528601119
local PRODUCT_GEMS_SMALL  = 3528601160
local PRODUCT_GEMS_MEDIUM = 3528601218
local PRODUCT_GEMS_LARGE  = 3528601291

-- [[ BUY NOW QUICK PRODUCT IDS ]] --
local BUY_NOW_CHEAP = 3542398418
local BUY_NOW_MED = 3542398321
local BUY_NOW_EXP = 3542397983

-- [[ DATASTORES ]] --
local PetDS = DataStoreService:GetDataStore("PetData_V8_Gems") 
local TycoonDS = DataStoreService:GetDataStore("TycoonData_V11_Passes") 

-- [[ REFERENCES ]] --
local PetsFolder = Workspace:WaitForChild("Player_Pets")
local TycoonMap = Workspace:WaitForChild("TycoonMap")
local Brainrots = ReplicatedStorage:WaitForChild("Brainrots")
local PetTemplates = ReplicatedStorage:WaitForChild("Pets")
local remotes = ReplicatedStorage:WaitForChild("TycoonRemotes")
local EggRemotes = ReplicatedStorage:WaitForChild("EggHatchingRemotes") 

-- [[ MERGE EVENT ]] --
local mergeBindable = ReplicatedStorage:FindFirstChild("MergeAllBindable") or Instance.new("BindableEvent", ReplicatedStorage)
mergeBindable.Name = "MergeAllBindable"

-- [[ NEW REMOTE: FAVORITE PROMPT ]] --
local markFavEvent = remotes:FindFirstChild("MarkFavoritePrompted") or Instance.new("RemoteEvent", remotes)
markFavEvent.Name = "MarkFavoritePrompted"

markFavEvent.OnServerEvent:Connect(function(player)
	local vals = player:FindFirstChild("Values")
	if vals and vals:FindFirstChild("HasPromptedFavorite") then
		vals.HasPromptedFavorite.Value = true
	end
end)

-- [[ CACHE ]] --
local PlayerPlotCache = {} 
local PlayerInviteHistory = {} 

-- [[ DEFAULT DATA ]] --
local DEFAULT_TYCOON_DATA = {
	Cash = 0, Gems = 0, Rebirth = 0, HighestMerge = 1, AllTimeHighestMerge = 1,
	PipeSpeed = 1, PipeLuck = 1, PipeLevel = 1, PipeCapacity = 1, 
	SellValue = 1, MoneyGeneration = 1, Grinder = 1, Vacuum = 0,
	OfflineMergeRate = 1, OfflineMergeTime = 1, LastSeen = os.time(),
	Items = {}, EquippedPets = {},
	MaxPetsStorage = 10,
	MaxPetsEquipped = 3,
	CashMultiplier = 1,
	GemsMultiplier = 1,
	AutoMerge = false,
	UnlimitedMoney = false,
	UnlockedRarities = {},
	InviteMultiplier = 0,
	InvitedPlayers = {},
	Playtime_Accumulated = 0,
	Playtime_ClaimedSlots = {false, false, false, false, false},
	Playtime_LoginDay = 1,
	Playtime_LastYDay = -1,
	HasPromptedFavorite = false
}

-- [[ HELPER FUNCTIONS ]] --
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

-- Fix: Helper function to safely spawn pets so they don't fall into the void and get deleted by the server engine
local function SecurePetSpawn(petModel, player)
	if player and player.Character and player.Character.PrimaryPart then
		petModel:PivotTo(player.Character.PrimaryPart.CFrame)
	else
		petModel:PivotTo(CFrame.new(0, 100, 0))
	end

	for _, part in pairs(petModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
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
	local additiveTotal = (rebMult + petMult + shopMult + inviteMult) - 2
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

local function FindAndCachePlot(player)
	if PlayerPlotCache[player] then return PlayerPlotCache[player] end
	for _, plot in pairs(TycoonMap:GetChildren()) do
		local ownerVal = plot:FindFirstChild("Owner")
		if ownerVal and ownerVal.Value == player then
			PlayerPlotCache[player] = plot
			return plot
		end
	end
	return nil
end

local function GetPhysicsPart(item)
	if item:IsA("Model") then return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true) end
	return item
end

local function CountPets(container, petName)
	local count = 0
	if container then
		for _, child in pairs(container:GetChildren()) do
			if child.Name == petName then count += 1 end
		end
	end
	return count
end

local function GetMoneyObj(player, currencyName)
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild(currencyName) then return ls[currencyName] end
	return nil
end

local function GetHatchLuck(player)
	local totalLuck = 0
	local s2, has2x = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GP_LUCK_2X) end)
	if s2 and has2x then totalLuck += 2 end
	local s10, has10x = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GP_LUCK_10X) end)
	if s10 and has10x then totalLuck += 10 end
	if player:FindFirstChild("Values") and player.Values:FindFirstChild("LuckMultiplier") then
		local val = player.Values.LuckMultiplier.Value
		if val > 1 then totalLuck += val end
	end
	if totalLuck < 1 then totalLuck = 1 end
	return totalLuck 
end

local function choosePet(egg, player)
	local petFolder = PetTemplates:FindFirstChild(egg.Name)
	if not petFolder then 
		return "Dog" 
	end

	local pets = petFolder:GetChildren()
	local totalWeight = 0
	local weightedTable = {}
	local luckMult = GetHatchLuck(player) 
	local highestRarityVal = 0
	for _, pet in pairs(pets) do
		if pet.Rarity.Value > highestRarityVal then highestRarityVal = pet.Rarity.Value end
	end
	for _, pet in pairs(pets) do
		local weight = pet.Rarity.Value
		local isRare = false
		if weight < highestRarityVal then 
			if luckMult >= 8 then
				local rarityRatio = highestRarityVal / math.max(1, weight)
				local dynamicMult = luckMult * (rarityRatio ^ 2) 
				weight = math.floor(weight * dynamicMult)
			else
				weight = math.floor(weight * luckMult)
			end
			isRare = true
		end
		if weight > 2000000000 then weight = 2000000000 end
		table.insert(weightedTable, {Name = pet.Name, Weight = weight, IsRare = isRare})
		totalWeight += weight
	end
	if totalWeight > 2000000000 then totalWeight = 2000000000 end
	local r = math.random(1, math.max(1, math.floor(totalWeight)))
	local currentSum = 0
	local selectedPet = weightedTable[1] and weightedTable[1].Name or "Dog"
	for _, data in ipairs(weightedTable) do
		currentSum += data.Weight
		if r <= currentSum then 
			selectedPet = data.Name
			return selectedPet
		end
	end
	return selectedPet
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

-- [[ RARITY VISUALS FOR LOADED ITEMS ]] --
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

-- [[ CORE: SAVE SYSTEM ]] --
local function SerializeAndSave(player)
	local data = {}
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		data.Cash = ls.Cash.Value
		data.Gems = ls:FindFirstChild("Gems") and ls.Gems.Value or 0
		data.Rebirth = ls.Rebirths.Value
		data.HighestMerge = ls.HighestMerge.Value
	else
		data.Cash = 0; data.Gems = 0; data.Rebirth = 0; data.HighestMerge = 1
	end

	local upg = player:FindFirstChild("Upgrades")
	if upg then
		data.PipeSpeed = upg:FindFirstChild("PipeSpeed") and upg.PipeSpeed.Value or 1
		data.PipeLuck = upg:FindFirstChild("PipeLuck") and upg.PipeLuck.Value or 1
		data.PipeLevel = upg:FindFirstChild("PipeLevel") and upg.PipeLevel.Value or 1
		data.PipeCapacity = upg:FindFirstChild("PipeCapacity") and upg.PipeCapacity.Value or 1
		data.SellValue = upg:FindFirstChild("SellValue") and upg.SellValue.Value or 1
		data.MoneyGeneration = upg:FindFirstChild("MoneyGeneration") and upg.MoneyGeneration.Value or 1
		data.Grinder = upg:FindFirstChild("Grinder") and upg.Grinder.Value or 1
		data.Vacuum = upg:FindFirstChild("Vacuum") and upg.Vacuum.Value or 0
		data.OfflineMergeRate = upg:FindFirstChild("OfflineMergeRate") and upg.OfflineMergeRate.Value or 1
		data.OfflineMergeTime = upg:FindFirstChild("OfflineMergeTime") and upg.OfflineMergeTime.Value or 1
	else
		data.PipeSpeed = 1; data.PipeLuck = 1; data.PipeLevel = 1; data.PipeCapacity = 1; 
		data.SellValue = 1; data.MoneyGeneration = 1; data.Grinder = 1; data.Vacuum = 0
		data.OfflineMergeRate = 1; data.OfflineMergeTime = 1
	end

	local vals = player:FindFirstChild("Values")
	if vals then
		data.AllTimeHighestMerge = vals:FindFirstChild("AllTimeHighestMerge") and vals.AllTimeHighestMerge.Value or 1
		data.MaxPetsStorage = vals:FindFirstChild("MaxPetsStorage") and vals.MaxPetsStorage.Value or 10
		data.MaxPetsEquipped = vals:FindFirstChild("MaxPetsEquipped") and vals.MaxPetsEquipped.Value or 3
		data.CashMultiplier = vals:FindFirstChild("CashMultiplier") and vals.CashMultiplier.Value or 1
		data.GemsMultiplier = vals:FindFirstChild("GemsMultiplier") and vals.GemsMultiplier.Value or 1
		data.AutoMerge = vals:FindFirstChild("AutoMerge") and vals.AutoMerge.Value or false
		data.UnlimitedMoney = vals:FindFirstChild("UnlimitedMoney") and vals.UnlimitedMoney.Value or false
		data.InviteMultiplier = vals:FindFirstChild("InviteMultiplier") and vals.InviteMultiplier.Value or 0
		data.HasPromptedFavorite = vals:FindFirstChild("HasPromptedFavorite") and vals.HasPromptedFavorite.Value or false
	else
		data.AllTimeHighestMerge = 1
		data.MaxPetsStorage = 10; data.MaxPetsEquipped = 3
		data.CashMultiplier = 1; data.GemsMultiplier = 1
		data.AutoMerge = false; data.UnlimitedMoney = false
		data.InviteMultiplier = 0
		data.HasPromptedFavorite = false
	end

	if player:GetAttribute("TestOfflineMode") then
		data.LastSeen = os.time() - (3600 * 10)
	else
		data.LastSeen = os.time()
	end

	data.EquippedPets = {}
	local equippedFolder = PetsFolder:FindFirstChild(player.Name)
	if equippedFolder then
		for _, pet in pairs(equippedFolder:GetChildren()) do
			table.insert(data.EquippedPets, pet.Name)
		end
	end

	data.UnlockedRarities = {}
	local urFolder = player:FindFirstChild("UnlockedRarities")
	if urFolder then
		for _, val in pairs(urFolder:GetChildren()) do
			data.UnlockedRarities[val.Name] = val.Value
		end
	end

	data.InvitedPlayers = PlayerInviteHistory[player.UserId] or {}

	local ptJoin = player:GetAttribute("Playtime_JoinTime")
	if ptJoin then
		data.Playtime_Accumulated = os.time() - ptJoin
		data.Playtime_LoginDay = player:GetAttribute("Playtime_LoginDay") or 1
		data.Playtime_LastYDay = player:GetAttribute("Playtime_LastYDay") or -1

		data.Playtime_ClaimedSlots = {false, false, false, false, false}
		local ptFolder = player:FindFirstChild("PlaytimeRewards")
		if ptFolder then
			for i=1, 5 do
				local b = ptFolder:FindFirstChild("Slot"..i)
				data.Playtime_ClaimedSlots[i] = b and b.Value or false
			end
		end
	else
		data.Playtime_Accumulated = 0
		data.Playtime_ClaimedSlots = {false, false, false, false, false}
		data.Playtime_LoginDay = 1
		data.Playtime_LastYDay = -1
	end

	data.Items = {}
	local plot = FindAndCachePlot(player)
	if plot then
		local itemsFolder = plot:FindFirstChild("Items")
		if itemsFolder then
			for _, item in pairs(itemsFolder:GetChildren()) do
				local lvlObj = item:FindFirstChild("Level", true)
				local root = GetPhysicsPart(item)
				if lvlObj and root then
					local pos = root.Position
					local _, rotY, _ = root.CFrame:ToEulerAnglesYXZ()
					table.insert(data.Items, {
						Lvl = lvlObj.Value, X = math.floor(pos.X * 100) / 100,
						Y = math.floor(pos.Y * 100) / 100, Z = math.floor(pos.Z * 100) / 100,
						Ry = math.floor(rotY * 100) / 100,
						Rarity = item:GetAttribute("Rarity") or 0
					})
				end
			end
		end
	end

	pcall(function() TycoonDS:SetAsync(tostring(player.UserId), data) end)

	local petInv = {}
	local pFolder = player:FindFirstChild("Pets")
	if pFolder then
		for _, v in pairs(pFolder:GetChildren()) do table.insert(petInv, v.Name) end
	end
	pcall(function() PetDS:SetAsync(player.UserId .. "Pets", petInv) end)
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local vals = player:FindFirstChild("Values")
	local ls = player:FindFirstChild("leaderstats")
	local pid = receiptInfo.ProductId

	if pid == BUY_NOW_CHEAP or pid == BUY_NOW_MED or pid == BUY_NOW_EXP then
		local amt = player:GetAttribute("LastDeficitAmount") or 1000
		local cur = player:GetAttribute("LastDeficitCurrency") or "Cash"
		if ls and ls:FindFirstChild(cur) then
			ls[cur].Value += amt
			task.spawn(function() SerializeAndSave(player) end)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if pid == PRODUCT_SPIN_1 or pid == PRODUCT_SPIN_3 or pid == PRODUCT_SPIN_10 then
		local pStats = player:FindFirstChild("PlayerStats")
		local spinVal = pStats and pStats:FindFirstChild("Spin")
		if spinVal then
			if pid == PRODUCT_SPIN_1 then spinVal.Value += 1 end
			if pid == PRODUCT_SPIN_3 then spinVal.Value += 3 end
			if pid == PRODUCT_SPIN_10 then spinVal.Value += 10 end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	if not vals or not ls then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if pid == PRODUCT_STORAGE_ID then
		local maxS = vals:FindFirstChild("MaxPetsStorage")
		if maxS then
			maxS.Value = maxS.Value + 10
			task.spawn(function() SerializeAndSave(player) end)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	elseif pid == PRODUCT_EQUIP_ID then
		local maxE = vals:FindFirstChild("MaxPetsEquipped")
		if maxE then
			if maxE.Value < 8 then
				maxE.Value = maxE.Value + 1
				task.spawn(function() SerializeAndSave(player) end)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	elseif pid == PRODUCT_MERGE_ALL then
		mergeBindable:Fire(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif pid == PRODUCT_2X_CASH then
		local cMult = vals:FindFirstChild("CashMultiplier")
		if cMult then
			local cur = cMult.Value
			cMult.Value = (cur == 1) and 2 or (cur * 2)
			task.spawn(function() SerializeAndSave(player) end)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	elseif pid == PRODUCT_2X_GEMS then
		local gMult = vals:FindFirstChild("GemsMultiplier")
		if gMult then
			local cur = gMult.Value
			gMult.Value = (cur == 1) and 2 or (cur * 2)
			task.spawn(function() SerializeAndSave(player) end)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	elseif pid == PRODUCT_PET_1 or pid == PRODUCT_PET_2 or pid == PRODUCT_PET_3 then
		local petToGive = "Dog"
		if pid == PRODUCT_PET_1 then petToGive = ReplicatedStorage:GetAttribute("Shop_Pet1") or "15x Pet"
		elseif pid == PRODUCT_PET_2 then petToGive = ReplicatedStorage:GetAttribute("Shop_Pet2") or "25x Pet"
		elseif pid == PRODUCT_PET_3 then petToGive = ReplicatedStorage:GetAttribute("Shop_Pet3") or "20x Pet" end
		local inv = player:FindFirstChild("Pets")
		if inv then
			local pVal = Instance.new("StringValue")
			pVal.Name = petToGive
			pVal.Parent = inv
			task.spawn(function() SerializeAndSave(player) end)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif pid == PRODUCT_CASH_SMALL then
		local amt = CalculateDynamicCash(player, 50)
		ls.Cash.Value += amt
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif pid == PRODUCT_CASH_MEDIUM then
		local amt = CalculateDynamicCash(player, 250)
		ls.Cash.Value += amt
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif pid == PRODUCT_CASH_LARGE then
		local amt = CalculateDynamicCash(player, 1000)
		ls.Cash.Value += amt
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif pid == PRODUCT_GEMS_SMALL then
		ls.Gems.Value += 200
		task.spawn(function() SerializeAndSave(player) end)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif pid == PRODUCT_GEMS_MEDIUM then
		ls.Gems.Value += 1000
		task.spawn(function() SerializeAndSave(player) end)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif pid == PRODUCT_GEMS_LARGE then
		ls.Gems.Value += 5000
		task.spawn(function() SerializeAndSave(player) end)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function CheckGamePasses(player, valFolder, forceEnable)
	local function check(id, valueName, isToggle)
		local success, hasPass = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		if success then
			local v = valFolder:FindFirstChild(valueName)
			if v then
				if hasPass then
					if forceEnable and isToggle then v.Value = true
					elseif not isToggle then v.Value = true
					end
				else
					if isToggle then v.Value = false end
				end
			end
		end
	end
	local am = valFolder:FindFirstChild("AutoMerge") or Instance.new("BoolValue", valFolder) am.Name = "AutoMerge"
	local um = valFolder:FindFirstChild("UnlimitedMoney") or Instance.new("BoolValue", valFolder) um.Name = "UnlimitedMoney"
	local lMult = valFolder:FindFirstChild("LuckMultiplier") or Instance.new("NumberValue", valFolder) lMult.Name = "LuckMultiplier"
	if not forceEnable then lMult.Value = 1 end
	local can3 = valFolder:FindFirstChild("CanTripleHatch") or Instance.new("BoolValue", valFolder) can3.Name = "CanTripleHatch"
	local canA = valFolder:FindFirstChild("CanAutoHatch") or Instance.new("BoolValue", valFolder) canA.Name = "CanAutoHatch"
	task.spawn(function()
		check(GP_AUTO_MERGE, "AutoMerge", true)
		check(GP_UNLIMITED_CASH, "UnlimitedMoney", true)
		check(GP_TRIPLE_HATCH, "CanTripleHatch", false)
		check(GP_AUTO_HATCH, "CanAutoHatch", false)
		local s1, h1 = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GP_LUCK_2X) end)
		if s1 and h1 then lMult.Value += 2 end
		local s2, h2 = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GP_LUCK_10X) end)
		if s2 and h2 then lMult.Value += 10 end
	end)
end

local refreshEvent = remotes:FindFirstChild("RefreshGamePasses") or Instance.new("RemoteEvent", remotes)
refreshEvent.Name = "RefreshGamePasses"
refreshEvent.OnServerEvent:Connect(function(player, forceEnable)
	local valFolder = player:FindFirstChild("Values")
	if valFolder then CheckGamePasses(player, valFolder, forceEnable) end
end)

local function LoadPlayer(player)
	print("[DataManager] Loading Data for:", player.Name)
	local invFolder = player:FindFirstChild("Pets") or Instance.new("Folder", player) invFolder.Name = "Pets"
	local valFolder = player:FindFirstChild("Values") or Instance.new("Folder", player) valFolder.Name = "Values"
	local ls = player:FindFirstChild("leaderstats") or Instance.new("Folder", player) ls.Name = "leaderstats"
	local upg = player:FindFirstChild("Upgrades") or Instance.new("Folder", player) upg.Name = "Upgrades"
	local mult = valFolder:FindFirstChild("Multiplier1") or Instance.new("StringValue", valFolder) mult.Name = "Multiplier1"
	mult.Value = "1"

	player.Chatted:Connect(function(msg)
		if msg:lower() == "!testoffline" then
			player:SetAttribute("TestOfflineMode", true)
			player:Kick("Simulated 10 hours offline. Rejoin to test.")
		end
	end)

	local unlockedFolder = player:FindFirstChild("UnlockedRarities") or Instance.new("Folder", player)
	unlockedFolder.Name = "UnlockedRarities"

	local equippedFolder = PetsFolder:FindFirstChild(player.Name) or Instance.new('Folder', PetsFolder)
	equippedFolder.Name = player.Name
	equippedFolder:ClearAllChildren()

	local sT, loadedData = pcall(function() return TycoonDS:GetAsync(tostring(player.UserId)) end)
	local hasPlayedBefore = true

	-- IF THEY ARE NEW
	if not sT or not loadedData then 
		loadedData = table.clone(DEFAULT_TYCOON_DATA) 
		hasPlayedBefore = false
	end

	local sP, petData = pcall(function() return PetDS:GetAsync(player.UserId.."Pets") end)

	local ahm = valFolder:FindFirstChild("AllTimeHighestMerge") or Instance.new("IntValue", valFolder)
	ahm.Name = "AllTimeHighestMerge"
	ahm.Value = loadedData.AllTimeHighestMerge or loadedData.HighestMerge or 1

	local maxS = valFolder:FindFirstChild("MaxPetsStorage") or Instance.new("IntValue", valFolder) 
	maxS.Name = "MaxPetsStorage"; maxS.Value = loadedData.MaxPetsStorage or 10
	local maxP = valFolder:FindFirstChild("MaxPetsEquipped") or Instance.new("IntValue", valFolder) 
	maxP.Name = "MaxPetsEquipped"; maxP.Value = loadedData.MaxPetsEquipped or 3
	local cMult = valFolder:FindFirstChild("CashMultiplier") or Instance.new("NumberValue", valFolder)
	cMult.Name = "CashMultiplier"; cMult.Value = loadedData.CashMultiplier or 1
	local gMult = valFolder:FindFirstChild("GemsMultiplier") or Instance.new("NumberValue", valFolder)
	gMult.Name = "GemsMultiplier"; gMult.Value = loadedData.GemsMultiplier or 1
	local am = valFolder:FindFirstChild("AutoMerge") or Instance.new("BoolValue", valFolder) 
	am.Name = "AutoMerge"; am.Value = loadedData.AutoMerge or false 
	local um = valFolder:FindFirstChild("UnlimitedMoney") or Instance.new("BoolValue", valFolder) 
	um.Name = "UnlimitedMoney"; um.Value = loadedData.UnlimitedMoney or false 
	local inviteMult = valFolder:FindFirstChild("InviteMultiplier") or Instance.new("NumberValue", valFolder)
	inviteMult.Name = "InviteMultiplier"; inviteMult.Value = loadedData.InviteMultiplier or 0

	local hasPromptedFav = valFolder:FindFirstChild("HasPromptedFavorite") or Instance.new("BoolValue", valFolder)
	hasPromptedFav.Name = "HasPromptedFavorite"
	hasPromptedFav.Value = loadedData.HasPromptedFavorite or false

	PlayerInviteHistory[player.UserId] = loadedData.InvitedPlayers or {}
	CheckGamePasses(player, valFolder, false)

	local currentYDay = os.date("!*t", os.time()).yday
	local p_loginDay = loadedData.Playtime_LoginDay or 1
	local p_lastYDay = loadedData.Playtime_LastYDay or -1
	local p_accum = loadedData.Playtime_Accumulated or 0
	local p_slots = loadedData.Playtime_ClaimedSlots or {false, false, false, false, false}

	if p_lastYDay ~= -1 and p_lastYDay ~= currentYDay then
		p_loginDay += 1
		p_accum = 0
		p_slots = {false, false, false, false, false}
	end

	player:SetAttribute("Playtime_LoginDay", p_loginDay)
	if p_loginDay >= 5 then AchievementManager.Award(player, "DailyDedication") end
	player:SetAttribute("Playtime_LastYDay", currentYDay)
	player:SetAttribute("Playtime_JoinTime", os.time() - p_accum)

	local ptFolder = Instance.new("Folder", player)
	ptFolder.Name = "PlaytimeRewards"
	for i=1, 5 do
		local b = Instance.new("BoolValue", ptFolder)
		b.Name = "Slot"..i
		b.Value = p_slots[i] or false
	end

	if loadedData.UnlockedRarities then
		for lvlStr, raritiesStr in pairs(loadedData.UnlockedRarities) do
			local val = Instance.new("StringValue", unlockedFolder)
			val.Name = lvlStr
			val.Value = raritiesStr
		end
	end

	if sP and petData then
		for _, petName in pairs(petData) do
			local v = Instance.new("StringValue", invFolder) v.Name = petName
		end
	end
	local cash = ls:FindFirstChild("Cash") or Instance.new("IntValue", ls) cash.Name = "Cash" 
	cash.Value = loadedData.Cash or 0
	local gems = ls:FindFirstChild("Gems") or Instance.new("IntValue", ls) gems.Name = "Gems"
	gems.Value = loadedData.Gems or 0 
	local reb = ls:FindFirstChild("Rebirths") or Instance.new("IntValue", ls) reb.Name = "Rebirths" 
	reb.Value = loadedData.Rebirth or 0
	local hMerge = ls:FindFirstChild("HighestMerge") or Instance.new("IntValue", ls) hMerge.Name = "HighestMerge" 
	hMerge.Value = loadedData.HighestMerge or 1
	local function setUpg(name, val)
		local v = upg:FindFirstChild(name) or Instance.new("IntValue", upg) v.Name = name v.Value = val
	end
	setUpg("PipeSpeed", loadedData.PipeSpeed or 1)
	setUpg("PipeLuck", loadedData.PipeLuck or 1)
	setUpg("PipeLevel", loadedData.PipeLevel or 1)
	setUpg("PipeCapacity", loadedData.PipeCapacity or 1)
	setUpg("SellValue", loadedData.SellValue or 1)
	setUpg("MoneyGeneration", loadedData.MoneyGeneration or 1)
	setUpg("Grinder", loadedData.Grinder or 1)
	setUpg("Vacuum", loadedData.Vacuum or 0)
	setUpg("OfflineMergeRate", loadedData.OfflineMergeRate or 1)
	setUpg("OfflineMergeTime", loadedData.OfflineMergeTime or 1)

	if loadedData.EquippedPets then
		local totalBonus = 0
		for _, petName in pairs(loadedData.EquippedPets) do
			local ownedCount = CountPets(invFolder, petName)
			local alreadyEquippedCount = CountPets(equippedFolder, petName)
			if alreadyEquippedCount < ownedCount then
				local template = nil
				for _, egg in pairs(PetTemplates:GetChildren()) do
					if egg:FindFirstChild(petName) then template = egg[petName] break end
				end
				if template then
					local clone = template:Clone()

					-- SERVER SAFE SPAWN: Ensures the pet won't be deleted by FallenPartsDestroyHeight
					SecurePetSpawn(clone, player)

					clone.Parent = equippedFolder
					local m = tonumber(template.Multiplier1.Value) or 1
					local bonus = math.max(0, m - 1)
					totalBonus += bonus
				end
			end
		end
		mult.Value = tostring(1 + totalBonus)
	end

	local followId = player.FollowUserId
	if followId and followId > 0 then
		task.spawn(function()
			task.wait(2) 
			local inviter = Players:GetPlayerByUserId(followId)
			if inviter then
				local inviterHistory = PlayerInviteHistory[inviter.UserId]
				if inviterHistory then
					local lastTime = inviterHistory[tostring(player.UserId)] or 0
					local now = os.time()
					if now - lastTime >= 86400 then 
						inviterHistory[tostring(player.UserId)] = now
						local invVals = inviter:FindFirstChild("Values")
						if invVals and invVals:FindFirstChild("InviteMultiplier") then
							invVals.InviteMultiplier.Value += 0.1
						end
						AchievementManager.Award(inviter, "Trendsetter")
					end
				end
			end
		end)
	end

	task.spawn(function()
		local myPlot = nil
		for i = 1, 120 do
			myPlot = FindAndCachePlot(player)
			if myPlot then break end
			task.wait(0.5)
		end

		if not myPlot then return end
		local itemsFolder = myPlot:WaitForChild("Items")

		if loadedData.Items then
			itemsFolder:ClearAllChildren()
			local brainrotLookup = {}
			for _, m in pairs(Brainrots:GetChildren()) do
				local l = m:FindFirstChild("Level")
				if l then brainrotLookup[l.Value] = m end
			end
			for _, itemData in pairs(loadedData.Items) do
				local template = brainrotLookup[itemData.Lvl]
				if template then
					local clone = template:Clone()
					clone.Parent = itemsFolder

					clone:SetAttribute("Rarity", itemData.Rarity or 0)
					ApplyRarityVisuals(clone, itemData.Rarity or 0)

					local root = GetPhysicsPart(clone)
					local cf = CFrame.new(itemData.X, itemData.Y, itemData.Z) * CFrame.Angles(0, itemData.Ry, 0)
					if clone:IsA("Model") then clone:PivotTo(cf) elseif root then root.CFrame = cf end
					if root then
						root.Anchored = false
						root.CanCollide = true
						root.AssemblyLinearVelocity = Vector3.new(0,0,0)
						if player and player:IsDescendantOf(game) then root:SetNetworkOwner(player) end
					end
				end
			end
		end

		-- Ensure it's not a new player before doing offline logic
		if loadedData.LastSeen and hasPlayedBefore then
			local timeOffline = os.time() - loadedData.LastSeen
			print("[OfflineMerge] Started offline calculation. Time offline (secs):", timeOffline)

			if timeOffline > 60 then 
				local maxTimeSecs = (loadedData.OfflineMergeTime or 1) * 3600
				local actualTime = math.clamp(timeOffline, 0, maxTimeSecs)
				print("[OfflineMerge] Capped calculated time (secs):", actualTime)

				local rateLvl = loadedData.OfflineMergeRate or 1
				local rateMins = 5 * (0.9 ^ (rateLvl - 1))
				local rateSecs = rateMins * 60

				local merges = math.floor(actualTime / rateSecs)
				print("[OfflineMerge] Total items generated by pipe:", merges)

				if merges > 0 then
					AchievementManager.Award(player, "PassiveIncome")
					local pipeLevel = loadedData.PipeLevel or 1
					local currentCount = merges
					local currentLevel = pipeLevel
					local totalOfflineCash = 0
					local totalOfflineGems = 0

					local gMult = 1
					local vals = player:FindFirstChild("Values")
					if vals and vals:FindFirstChild("GemsMultiplier") then
						gMult = vals.GemsMultiplier.Value
					end

					print("[OfflineMerge] Starting simulation from Pipe Level:", pipeLevel, "with", merges, "items.")

					local itemsToSpawn = {}

					while currentCount >= 1 do
						if currentCount % 2 == 1 then
							table.insert(itemsToSpawn, currentLevel)
						end

						local mergesThisLevel = math.floor(currentCount / 2)
						if mergesThisLevel > 0 then
							currentLevel += 1

							local nextItemValue = CalculateItemValue(currentLevel, player, 0)
							totalOfflineCash += math.floor(nextItemValue * MERGE_REWARD_MULT * mergesThisLevel)
							totalOfflineGems += math.max(1, math.floor(1 * gMult)) * mergesThisLevel
						end
						currentCount = mergesThisLevel
					end

					print("[OfflineMerge] Simulation complete. Highest Level:", currentLevel)
					print("[OfflineMerge] Total Offline Cash Earned:", totalOfflineCash)
					print("[OfflineMerge] Total Offline Gems Earned:", totalOfflineGems)

					local lsObj = player:FindFirstChild("leaderstats")
					if lsObj then
						local cObj = lsObj:FindFirstChild("Cash")
						if cObj then
							local MAX_INT = 2147483647
							if cObj.Value + totalOfflineCash > MAX_INT or cObj.Value + totalOfflineCash < 0 then
								cObj.Value = MAX_INT
							else
								cObj.Value += totalOfflineCash
							end
						end
						local gObj = lsObj:FindFirstChild("Gems")
						if gObj then
							local MAX_INT = 2147483647
							if gObj.Value + totalOfflineGems > MAX_INT or gObj.Value + totalOfflineGems < 0 then
								gObj.Value = MAX_INT
							else
								gObj.Value += totalOfflineGems
							end
						end
						local hObj = lsObj:FindFirstChild("HighestMerge")
						if hObj and currentLevel > hObj.Value then
							hObj.Value = currentLevel
						end
					end

					local brainrotLookup = {}
					for _, m in pairs(Brainrots:GetChildren()) do
						local l = m:FindFirstChild("Level")
						if l then brainrotLookup[l.Value] = m end
					end

					-- REVISED SPAWN LOGIC: Wider spread and vertical staggering to prevent physics overlaps
					for index, spawnLevel in ipairs(itemsToSpawn) do
						local template = brainrotLookup[spawnLevel]
						if template then
							local clone = template:Clone()
							clone.Parent = itemsFolder

							clone:SetAttribute("Rarity", 0)
							ApplyRarityVisuals(clone, 0)

							local root = GetPhysicsPart(clone)
							local floorPart = myPlot:FindFirstChild("Floor")

							local xOff = (math.random(-60, 60) / 10)
							local zOff = (math.random(-60, 60) / 10)
							local yOff = 5 + (index * 3) -- Staggers them upward by 3 studs each

							local cf = CFrame.new(0, yOff, 0)
							if floorPart then
								cf = floorPart.CFrame * CFrame.new(xOff, yOff, zOff)
							end

							if clone:IsA("Model") then clone:PivotTo(cf) elseif root then root.CFrame = cf end
							if root then
								root.Anchored = false
								root.CanCollide = true
								root.AssemblyLinearVelocity = Vector3.new(0,0,0)
								if player and player:IsDescendantOf(game) then root:SetNetworkOwner(player) end
							end
						else
							warn("[OfflineMerge] FAILED TO FIND TEMPLATE FOR LEVEL:", spawnLevel)
						end
					end

					-- [[ UI REPORT INJECTION ]] --
					local playerGui = player:WaitForChild("PlayerGui")

					-- Hide Daily Rewards temporarily so it doesn't overlap
					local dailyGui = playerGui:WaitForChild("DailyRewards", 5) 
					if dailyGui then
						dailyGui.Enabled = false
					end

					local reportGui = playerGui:WaitForChild("OfflineReportGui", 20)
					if reportGui then
						local mainFrame = reportGui:FindFirstChild("MainFrame")
						if mainFrame then
							local statsLbl = mainFrame:FindFirstChild("StatsLabel")
							if statsLbl then
								statsLbl.Text = string.format("Items Generated: %d\nCash Earned: $%s\nGems Earned: %s", merges, FormatNumber(totalOfflineCash), FormatNumber(totalOfflineGems))
							end
							mainFrame.Visible = true 
						end

						reportGui.DisplayOrder = 1
						reportGui.Enabled = true
					end
				end
			end
		end
	end)
end

local function PerformHatch(player, eggNameOrObject)
	local eggName = ""
	if typeof(eggNameOrObject) == "Instance" then eggName = eggNameOrObject.Name
	elseif typeof(eggNameOrObject) == "string" then eggName = eggNameOrObject
	end

	local plot = FindAndCachePlot(player)
	if not plot then return "Cannot Hatch" end
	local eggsFolder = plot:FindFirstChild("Eggs")
	if not eggsFolder then return "Cannot Hatch" end

	local eggModel = eggsFolder:FindFirstChild(eggName)
	if not eggModel then return "Cannot Hatch" end

	local pets = player:FindFirstChild("Pets")
	local maxS = player.Values:FindFirstChild("MaxPetsStorage")
	if pets and maxS then
		if #pets:GetChildren() >= maxS.Value then return "Inventory Full" end
	end

	local price = eggModel.Price.Value
	local currency = eggModel.Currency.Value
	local moneyObj = GetMoneyObj(player, currency)

	local um = player.Values:FindFirstChild("UnlimitedMoney")
	if currency == "Cash" and um and um.Value == true then price = 0 end

	if moneyObj and moneyObj.Value >= price then
		moneyObj.Value -= price
		AchievementManager.Award(player, "PetCollector")
		local petName = choosePet(eggModel, player) 
		local v = Instance.new("StringValue", player.Pets) v.Name = petName
		return petName
	else
		local deficit = price - (moneyObj and moneyObj.Value or 0)
		player:SetAttribute("LastDeficitAmount", deficit)
		player:SetAttribute("LastDeficitCurrency", currency)
		local pid = BUY_NOW_CHEAP
		if currency == "Cash" then
			local small = CalculateDynamicCash(player, 50)
			local med = CalculateDynamicCash(player, 250)
			if deficit > med then pid = BUY_NOW_EXP
			elseif deficit > small then pid = BUY_NOW_MED end
		else
			if deficit > 1000 then pid = BUY_NOW_EXP
			elseif deficit > 200 then pid = BUY_NOW_MED end
		end

		task.spawn(function()
			MarketplaceService:PromptProductPurchase(player, pid)
		end)
	end
	return "Cannot Hatch"
end

EggRemotes.HatchServer.OnServerInvoke = function(player, egg)
	return PerformHatch(player, egg)
end

EggRemotes.Hatch3Pets.OnServerInvoke = function(player, eggNameOrObject)
	local owns = false
	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GP_TRIPLE_HATCH)
	end)
	if success then owns = result end
	if not owns then return "The player does not own the gamepass" end

	local eggName = ""
	if typeof(eggNameOrObject) == "Instance" then eggName = eggNameOrObject.Name
	elseif typeof(eggNameOrObject) == "string" then eggName = eggNameOrObject
	end

	local plot = FindAndCachePlot(player)
	if not plot then return "Cannot Hatch" end
	local eggsFolder = plot:FindFirstChild("Eggs")
	local eggModel = eggsFolder and eggsFolder:FindFirstChild(eggName)
	if not eggModel then return "Cannot Hatch" end

	local pets = player:FindFirstChild("Pets")
	local maxS = player.Values:FindFirstChild("MaxPetsStorage")
	if pets and maxS then
		if #pets:GetChildren() + 2 >= maxS.Value then return "Inventory Full" end
	end

	local price = eggModel.Price.Value * 3 

	local currency = eggModel.Currency.Value
	local moneyObj = GetMoneyObj(player, currency)

	local um = player.Values:FindFirstChild("UnlimitedMoney")
	if currency == "Cash" and um and um.Value == true then price = 0 end

	if moneyObj and moneyObj.Value >= price then
		moneyObj.Value -= price
		AchievementManager.Award(player, "TripleThreat")
		local p1 = choosePet(eggModel, player)
		local p2 = choosePet(eggModel, player)
		local p3 = choosePet(eggModel, player)
		local v1 = Instance.new("StringValue", player.Pets) v1.Name = p1
		local v2 = Instance.new("StringValue", player.Pets) v2.Name = p2
		local v3 = Instance.new("StringValue", player.Pets) v3.Name = p3
		return p1, p2, p3
	else
		local deficit = price - (moneyObj and moneyObj.Value or 0)
		player:SetAttribute("LastDeficitAmount", deficit)
		player:SetAttribute("LastDeficitCurrency", currency)
		local pid = BUY_NOW_CHEAP
		if currency == "Cash" then
			local small = CalculateDynamicCash(player, 50)
			local med = CalculateDynamicCash(player, 250)
			if deficit > med then pid = BUY_NOW_EXP
			elseif deficit > small then pid = BUY_NOW_MED end
		else
			if deficit > 1000 then pid = BUY_NOW_EXP
			elseif deficit > 200 then pid = BUY_NOW_MED end
		end

		task.spawn(function()
			MarketplaceService:PromptProductPurchase(player, pid)
		end)
	end
	return "Cannot Hatch"
end

EggRemotes.AutoHatch.OnServerInvoke = function(player, egg)
	local owns = false
	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GP_AUTO_HATCH)
	end)
	if success then owns = result end
	if not owns then return "The player does not own the gamepass" end
	return PerformHatch(player, egg)
end

local function UpdatePlayerMultiplier(player)
	local eqFolder = PetsFolder:FindFirstChild(player.Name)
	local totalBonus = 0
	if eqFolder then
		for _, pet in pairs(eqFolder:GetChildren()) do
			local petM = tonumber(pet.Multiplier1.Value) or 1
			totalBonus += math.max(0, petM - 1)
		end
	end
	player.Values.Multiplier1.Value = tostring(math.max(1, 1 + totalBonus))
end

EggRemotes.EquipPet.OnServerInvoke = function(player, petName)
	local eqFolder = PetsFolder:FindFirstChild(player.Name)
	local invFolder = player:FindFirstChild("Pets")
	if not eqFolder or not invFolder then return "Fail" end
	local maxEquipVal = player.Values.MaxPetsEquipped.Value
	if #eqFolder:GetChildren() >= maxEquipVal then return "Full" end
	local ownedCount = CountPets(invFolder, petName)
	local equippedCount = CountPets(eqFolder, petName)
	if equippedCount >= ownedCount then return "Fail" end
	local template = nil
	for _, egg in pairs(PetTemplates:GetChildren()) do
		if egg:FindFirstChild(petName) then template = egg[petName] break end
	end
	if template then
		local c = template:Clone()

		-- SERVER SAFE SPAWN: Anchors and teleports it before parenting to Workspace
		SecurePetSpawn(c, player)

		c.Parent = eqFolder
		UpdatePlayerMultiplier(player)
		return "Equip"
	end
	return "Fail"
end

EggRemotes.UnequipPet.OnServerInvoke = function(player, petName)
	local eqFolder = PetsFolder:FindFirstChild(player.Name)
	local pet = eqFolder and eqFolder:FindFirstChild(petName)
	if pet then
		pet:Destroy()
		UpdatePlayerMultiplier(player)
		return true
	end
	return false
end

EggRemotes.UnequipAll.OnServerEvent:Connect(function(player)
	local eq = PetsFolder:FindFirstChild(player.Name)
	if eq then 
		eq:ClearAllChildren() 
		player.Values.Multiplier1.Value = "1" 
	end
end)

local unequipSync = Instance.new("RemoteFunction")
unequipSync.Name = "UnequipAllSync"
unequipSync.Parent = EggRemotes

unequipSync.OnServerInvoke = function(player)
	local eq = PetsFolder:FindFirstChild(player.Name)
	if eq then 
		eq:ClearAllChildren() 
		player.Values.Multiplier1.Value = "1" 
	end
	return true
end

EggRemotes.DeletePet.OnServerEvent:Connect(function(player, petName)
	local eq = PetsFolder:FindFirstChild(player.Name)
	local pEq = eq and eq:FindFirstChild(petName)
	if pEq then pEq:Destroy() end

	local inv = player:FindFirstChild("Pets")
	local pInv = inv and inv:FindFirstChild(petName)
	if pInv then pInv:Destroy() end

	UpdatePlayerMultiplier(player)
end)

Players.PlayerAdded:Connect(LoadPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function() LoadPlayer(player) end)
end

Players.PlayerRemoving:Connect(function(player)
	SerializeAndSave(player)
	PlayerInviteHistory[player.UserId] = nil
	local eq = PetsFolder:FindFirstChild(player.Name)
	if eq then eq:Destroy() end
	PlayerPlotCache[player] = nil
end)
game:BindToClose(function()
	for _, p in pairs(Players:GetPlayers()) do SerializeAndSave(p) end
	task.wait(3)
end)
task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		for _, p in pairs(Players:GetPlayers()) do SerializeAndSave(p) end
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then return end
	local valFolder = player:FindFirstChild("Values")
	if not valFolder then return end
	if passId == GP_AUTO_MERGE then valFolder.AutoMerge.Value = true
	elseif passId == GP_UNLIMITED_CASH then valFolder.UnlimitedMoney.Value = true
	elseif passId == GP_TRIPLE_HATCH then valFolder.CanTripleHatch.Value = true
	elseif passId == GP_AUTO_HATCH then valFolder.CanAutoHatch.Value = true
	elseif passId == GP_LUCK_2X then
		local lMult = valFolder:FindFirstChild("LuckMultiplier")
		if lMult then if lMult.Value == 1 or lMult.Value == 11 then lMult.Value += 2 end end
	elseif passId == GP_LUCK_10X then
		local lMult = valFolder:FindFirstChild("LuckMultiplier")
		if lMult then if lMult.Value < 11 then lMult.Value += 10 end end
	end
	task.spawn(function() SerializeAndSave(player) end)
end)