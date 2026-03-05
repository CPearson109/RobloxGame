-- [[ StarterPlayerScripts/MachineClient.local.luau ]] --

--!native
--!optimize 2
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("TycoonRemotes")
local rollEvent = remotes:WaitForChild("AnimateRoll")
local upgradeFunc = remotes:WaitForChild("UpgradeMachine")
local brainrots = RS:WaitForChild("Brainrots")
local fxEvent = remotes:WaitForChild("PlayFX") 

print("MachineClient Final Loaded (CPU Optimized)")

-- [[ VISUAL CONFIG ]] --
local SPIN_DURATION_MULTIPLIER = 1
local VISIBLE_VIEWPORT_WIDTH = 40 
local VIEWPORT_BUFFER = 5
local DISTANCE_FROM_PART = -1
local HEIGHT_OFFSET = 0
local ROTATION_OFFSET = 180
local HIDE_CFRAME = CFrame.new(0, -5000, 0) 
local FIXED_HEIGHT = 12
local FRAME_PADDING_X = 4.0
local FRAME_THICKNESS = 0.5
local FRAME_COLOR = Color3.new(0.1, 0.1, 0.1)
local BACKBOARD_DEPTH = 0.5
local BACKBOARD_OFFSET = 1.2
local BACKBOARD_MATERIAL = Enum.Material.SmoothPlastic
local BACKBOARD_TRANSPARENCY = 0.4

-- CACHED CFRAMES FOR OPTIMIZATION
local ROTATION_CF = CFrame.Angles(0, math.rad(ROTATION_OFFSET), 0)
local BACKBOARD_OFFSET_CF = CFrame.new(0, 0, BACKBOARD_OFFSET)

local RARITY_COLORS = {
	[1] = Color3.fromRGB(0, 170, 255),
	[2] = Color3.fromRGB(255, 0, 127),
	[3] = Color3.fromRGB(255, 170, 0),
	[4] = Color3.fromRGB(85, 255, 0),
	[5] = Color3.fromRGB(170, 0, 255),
	[10] = Color3.fromRGB(50, 255, 50),
	[25] = Color3.fromRGB(50, 150, 255),
	[50] = Color3.fromRGB(255, 0, 255),
	[75] = Color3.fromRGB(255, 255, 0),
	[100] = Color3.fromRGB(255, 0, 0),
}
local FALLBACK_COLOR = Color3.fromRGB(255, 255, 255)

-- [[ AUDIO HELPERS ]] --
local function PlayUISound(id, vol)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = vol or 0.5
	s.Parent = Workspace
	s:Play()
	Debris:AddItem(s, 3)
end

local function Play3DSound(id, parentPart, vol, loop)
	if not parentPart then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = vol or 0.6
	s.RollOffMaxDistance = 120 -- Capped range
	s.RollOffMinDistance = 50
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Looped = loop or false
	s.Parent = parentPart
	s:Play()
	if not loop then Debris:AddItem(s, 5) end
	return s
end

-- [[ FORMAT NUMBER FUNCTION ]] --
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

-- [[ CLIENT UPGRADE CONFIGURATION ]] --
local UPGRADE_CONFIG = {
	SpeedButton = { UpgradeName = "PipeSpeed", StatType = "Speed", Label = "Speed", BaseCost = 250, Multiplier = 3.15, MaxLevel = 30 },
	LevelButton = { UpgradeName = "PipeLevel", StatType = "BaseLevel", Label = "Base Lvl", BaseCost = 5000, Multiplier = 2.42, MaxLevel = 147 },
	LuckButton = { UpgradeName = "PipeLuck", StatType = "Luck", Label = "Luck", BaseCost = 10000, Multiplier = 12.5, MaxLevel = 20 },
	CapacityButton = { UpgradeName = "PipeCapacity", StatType = "Capacity", Label = "Capacity", BaseCost = 15000, Multiplier = 22.0, MaxLevel = 10 },
	SellValueButton = { UpgradeName = "SellValue", StatType = "Sell", Label = "Sell Value", BaseCost = 7500, Multiplier = 15.0, MaxLevel = 20 },
	MoneyGenerationButton = { UpgradeName = "MoneyGeneration", StatType = "Money", Label = "Money Gen", BaseCost = 5000, Multiplier = 24.0, MaxLevel = 15 }
}

local PAID_UPGRADE_CONFIG = {
	PetStorage = { UpgradeName = "MaxPetsStorage", StatType = "Limit", Label = "+10 Space", Cost = 1000, MaxLevel = 200, IsPaid = true },
	PetEquiped = { UpgradeName = "MaxPetsEquipped", StatType = "Limit", Label = "+1 Equip", Cost = 1500, MaxLevel = 8, IsPaid = true },
	["2xCash"] = { UpgradeName = "Boost_2xCash", StatType = "Timer", Label = "2x Cash", Cost = 200, IsPaid = true },
	["5xCash"] = { UpgradeName = "Boost_5xCash", StatType = "Timer", Label = "5x Cash", Cost = 600, IsPaid = true },
	["10xCash"] = { UpgradeName = "Boost_10xCash", StatType = "Timer", Label = "10x Cash", Cost = 1000, IsPaid = true },
	["2xSpinLuck"] = { UpgradeName = "Boost_2xSpinLuck", StatType = "Timer", Label = "2x Luck", Cost = 200, IsPaid = true },
	["2xSpinSpeed"] = { UpgradeName = "Boost_2xSpinSpeed", StatType = "Timer", Label = "2x Speed", Cost = 200, IsPaid = true },
	["2xCashGenerationSpeed"] = { UpgradeName = "Boost_2xCashGenerationSpeed", StatType = "Timer", Label = "2x Gen", Cost = 100, IsPaid = true },
}

local OFFLINE_UPGRADE_CONFIG = {
	OfflineMergeSpeed = { UpgradeName = "OfflineMergeRate", StatType = "OfflineRate", Label = "Merge Rate", Cost = 100, MaxLevel = 25, IsPaid = true },
	OfflineMergeTime = { UpgradeName = "OfflineMergeTime", StatType = "OfflineTime", Label = "Max Time", Cost = 100, MaxLevel = 48, IsPaid = true }
}

local function CalculateStat(type, level)
	local now = workspace:GetServerTimeNow()
	if type == "Speed" then 
		local base = 6 * (0.95 ^ (level - 1))
		local endBoost = player:GetAttribute("Boost_2xSpinSpeed_End")
		if endBoost and endBoost > now then base = base * 0.5 end
		return string.format("%.1fs", base)
	elseif type == "Luck" then 
		local base = 1 + ((level - 1) * 0.5) 
		local endBoost = player:GetAttribute("Boost_2xSpinLuck_End")
		if endBoost and endBoost > now then base = base * 2 end 
		return string.format("x%.1f", base)
	elseif type == "Capacity" then 
		local totalCap = 15 + (level * 3)
		return string.format("Max: %d", totalCap)
	elseif type == "Sell" then 
		return string.format("x%.1f", 1 + ((level - 1) * 0.2))
	elseif type == "Money" then 
		local interval = 3.0 * (0.95 ^ (level - 1))
		local endBoost = player:GetAttribute("Boost_2xCashGenerationSpeed_End")
		if endBoost and endBoost > now then interval = interval * 0.5 end 
		return string.format("%.2fs", interval)
	elseif type == "BaseLevel" then
		return string.format("Start: Lvl %d", level)
	elseif type == "OfflineRate" then
		return string.format("%.1f mins", 5 * (0.9 ^ (level - 1)))
	elseif type == "OfflineTime" then
		return string.format("%d Hour(s)", level)
	end
	return "???"
end

-- [[ POOLING SYSTEM ]] --
local BrainrotCache = {}
local AvailableLevels = {}
local ModelPool = {}
local ActiveSpinModels = {} 

local function PrepareModelForRender(model)
	if not model then return end
	local primary = model.PrimaryPart
	if not primary then
		for _, v in ipairs(model:GetDescendants()) do
			if v:IsA("BasePart") then primary = v; break end
		end
		model.PrimaryPart = primary
	end
	for _, v in ipairs(model:GetDescendants()) do
		if v:IsA("BasePart") then
			v.Anchored = true 
			v.CanCollide = false
			v.CanQuery = false
			v.CanTouch = false
			v.CastShadow = false
		elseif v:IsA("BillboardGui") or v:IsA("ParticleEmitter") or v:IsA("Light") then
			v:Destroy()
		end
	end
end

local function RebuildAvailableLevels()
	table.clear(AvailableLevels)
	for lvl, _ in pairs(BrainrotCache) do
		if typeof(lvl) == "number" then table.insert(AvailableLevels, lvl) end
	end
	table.sort(AvailableLevels)
end

local function UpdateCache()
	table.clear(BrainrotCache)
	for _, model in pairs(brainrots:GetChildren()) do
		local lvlObj = model:FindFirstChild("Level")
		if lvlObj and lvlObj:IsA("IntValue") then
			BrainrotCache[lvlObj.Value] = model
		end
	end
	RebuildAvailableLevels()
end
UpdateCache()
brainrots.ChildAdded:Connect(UpdateCache)

local function GetPooledModel(level)
	if not ModelPool[level] then ModelPool[level] = {} end
	local pool = ModelPool[level]
	while #pool > 0 do
		local model = table.remove(pool)
		local success, _ = pcall(function() return model.Parent end)
		if success then return model end
	end
	local template = BrainrotCache[level]
	if template then
		local clone = template:Clone()
		PrepareModelForRender(clone)
		return clone
	end
	return nil
end

local function ReturnModelToPool(model, level)
	if not model then return end
	if not ModelPool[level] then ModelPool[level] = {} end
	if model.Parent ~= nil or pcall(function() model.Parent = nil end) then
		model.Parent = nil
		table.insert(ModelPool[level], model)
	end
end

local function getCost(level, config)
	if config.IsPaid then return config.Cost end 
	return math.floor(config.BaseCost * (config.Multiplier ^ (math.max(level, 1) - 1)))
end

local function GetRarityColor(level)
	local bestMatch = FALLBACK_COLOR
	local highestThreshold = -1
	for threshold, color in pairs(RARITY_COLORS) do
		if level >= threshold and threshold > highestThreshold then
			highestThreshold = threshold
			bestMatch = color
		end
	end
	return bestMatch
end

local function GetRandomLevelForWheel()
	local upgrades = player:FindFirstChild("Upgrades")
	local baseIndex = upgrades and upgrades:FindFirstChild("PipeLevel") and upgrades.PipeLevel.Value or 1
	local luckLvl = upgrades and upgrades:FindFirstChild("PipeLuck") and upgrades.PipeLuck.Value or 1
	if #AvailableLevels == 0 then return 1 end
	local centerIndex = math.clamp(baseIndex, 1, #AvailableLevels)
	local r = math.random()
	if r > 0.8 then
		local bonus = math.random(1, math.floor(luckLvl/3) + 1)
		centerIndex = math.clamp(centerIndex + bonus, 1, #AvailableLevels)
	elseif r < 0.1 then
		centerIndex = math.clamp(centerIndex - 1, 1, #AvailableLevels)
	end
	return AvailableLevels[centerIndex]
end

local activeGuis = {}

local function FindLabelSafe(container, button, names)
	for _, name in ipairs(names) do
		local found = button:FindFirstChild(name)
		if found then return found end
		found = container:FindFirstChild(name)
		if found then return found end
	end
	return nil
end

local function setupUpgradeButton(frameContainer, config)
	local buyButton = frameContainer:FindFirstChild("BuyButton")
	if not buyButton then return end
	local costLabel = FindLabelSafe(frameContainer, buyButton, {"CostLabel", "PriceLabel", "Price"})
	local levelLabel = FindLabelSafe(frameContainer, buyButton, {"LevelLabel", "Level"})
	local rateLabel = FindLabelSafe(frameContainer, buyButton, {"RateLabel", "Rate", "Desc"})
	local conn = nil
	local isAlive = true

	frameContainer.Destroying:Connect(function() 
		isAlive = false 
		if conn then conn:Disconnect() end
	end)

	if config.StatType == "Timer" then
		local lastSecond = -1
		local function updateTimer()
			if not isAlive then return end
			local endTime = player:GetAttribute(config.UpgradeName .. "_End") or 0
			local timeLeft = math.max(0, endTime - workspace:GetServerTimeNow())
			local currentSecond = math.ceil(timeLeft)

			if currentSecond == lastSecond then return end
			lastSecond = currentSecond

			if timeLeft > 0 then
				local m = math.floor(timeLeft / 60)
				local s = math.floor(timeLeft % 60)
				local timeStr = string.format("%02d:%02d", m, s)
				if rateLabel then rateLabel.Text = timeStr end 
				if levelLabel then levelLabel.Text = timeStr end
			else
				if levelLabel then levelLabel.Text = "" end
				if rateLabel then rateLabel.Text = config.Label end 
			end
			if costLabel then costLabel.Text = tostring(config.Cost) end
		end

		updateTimer()
		task.spawn(function()
			while isAlive do
				updateTimer()
				task.wait(0.2) 
			end
		end)

	elseif config.StatType == "Limit" then
		task.spawn(function()
			local values = player:WaitForChild("Values", math.huge)
			local valObj = values:WaitForChild(config.UpgradeName, math.huge)
			local function updateLimit()
				if not valObj then return end
				local cur = valObj.Value
				local max = config.MaxLevel
				local maxed = cur >= max
				if buyButton then
					buyButton.Active = not maxed
					buyButton.AutoButtonColor = not maxed
					buyButton.ImageColor3 = maxed and Color3.fromRGB(100, 100, 100) or Color3.fromRGB(0, 170, 0)
				end
				if costLabel then costLabel.Text = maxed and "MAX" or tostring(config.Cost) end
				if levelLabel then levelLabel.Text = cur .. " / " .. max end
				if rateLabel then rateLabel.Text = config.Label end
			end
			updateLimit()
			conn = valObj.Changed:Connect(updateLimit)
		end)
	else
		task.spawn(function()
			local upgradesFolder = player:WaitForChild("Upgrades", math.huge)
			local upgradeValue = upgradesFolder:WaitForChild(config.UpgradeName, math.huge)
			local function updateText()
				if not isAlive then return end
				local currentLevel = upgradeValue.Value
				local nextCost = getCost(currentLevel, config)
				local maxed = currentLevel >= config.MaxLevel
				if buyButton then
					buyButton.Active = not maxed
					buyButton.AutoButtonColor = not maxed
					buyButton.ImageColor3 = maxed and Color3.fromRGB(100, 100, 100) or Color3.fromRGB(0, 170, 0)
				end
				if costLabel then 
					if config.IsPaid then
						costLabel.Text = maxed and "MAXED" or tostring(nextCost)
					else
						costLabel.Text = maxed and "MAXED" or "$" .. FormatNumber(nextCost)
					end
				end
				if levelLabel then levelLabel.Text = currentLevel .. " / " .. config.MaxLevel end
				if rateLabel then rateLabel.Text = CalculateStat(config.StatType, currentLevel) end
			end
			updateText()
			conn = upgradeValue.Changed:Connect(updateText)

			task.spawn(function()
				while isAlive do
					task.wait(0.5) 
					if isAlive then updateText() end
				end
			end)
		end)
	end

	if buyButton then
		buyButton.MouseButton1Click:Connect(function()
			if buyButton.Active then
				PlayUISound("133292918309565", 0.6) 
			end
			if upgradeFunc then upgradeFunc:InvokeServer(config.UpgradeName) end
		end)
	end
end

local function FindScreenPartInPlot(plot, partName)
	local spin = plot:FindFirstChild("Spin")
	if spin and spin:FindFirstChild(partName) then return spin[partName] end
	if plot:FindFirstChild(partName) then return plot[partName] end
	local deepFind = plot:FindFirstChild(partName, true)
	if deepFind then return deepFind end
	return nil
end

local function SetupScreen(plot, screenName, configTable)
	if activeGuis[plot] and activeGuis[plot][screenName] and activeGuis[plot][screenName].Parent then return true end

	local screenPart = FindScreenPartInPlot(plot, screenName)
	if not screenPart then return false end

	local wsGui = screenPart:FindFirstChild("UpgradeGui") or screenPart:FindFirstChildWhichIsA("SurfaceGui")
	if not wsGui then return false end

	-- Verify ALL buttons have fully streamed to the client before cloning
	for key, _ in pairs(configTable) do
		if not wsGui:FindFirstChild(key, true) then return false end
	end

	wsGui.Enabled = false 

	local clone = wsGui:Clone()
	clone.Name = screenName .. "_" .. plot.Name
	clone.Adornee = screenPart
	clone.Parent = player:WaitForChild("PlayerGui")
	clone.Enabled = true 
	clone.ResetOnSpawn = false
	clone.Face = Enum.NormalId.Front 

	local mainFrame = clone:FindFirstChild("Frame") or clone
	if mainFrame:IsA("GuiObject") then mainFrame.ZIndex = 10 end

	local function SetupIfFound(name, config)
		local btn = mainFrame:FindFirstChild(name, true)
		if btn then setupUpgradeButton(btn, config) end
	end

	if mainFrame then 
		for key, conf in pairs(configTable) do SetupIfFound(key, conf) end
	end

	if not activeGuis[plot] then activeGuis[plot] = {} end
	activeGuis[plot][screenName] = clone
	return true
end

-- [[ ROLL LOGIC ]] --
local currentSpinFolder = nil
local currentSpinTween = nil
local currentSpinConnection = nil
local currentCompleteConnection = nil

local function BuildStaticWheel(plot)
	if currentSpinFolder then return true end
	local spinAnchor = plot:FindFirstChild("CharacterSpin", true) or plot:FindFirstChild("Spin", true)
	if not spinAnchor then return false end

	if #AvailableLevels == 0 then return false end

	local spinContainer = Instance.new("Folder")
	spinContainer.Name = "ClientSpinWheel"
	spinContainer.Parent = Workspace
	currentSpinFolder = spinContainer

	local offsetValue = Instance.new("NumberValue")
	offsetValue.Value = 0
	offsetValue.Parent = spinContainer

	local TOTAL_ITEMS = 15 
	local itemsData = {}
	local currentTotalWidth = 0

	for i = 1, TOTAL_ITEMS do
		local lvl = GetRandomLevelForWheel()
		local template = BrainrotCache[lvl]
		if template then
			local visualWidth = template:IsA("Model") and select(2, template:GetBoundingBox()).X or template.Size.X
			local frameWidth = visualWidth + FRAME_PADDING_X
			local positionOnTape = currentTotalWidth + (frameWidth / 2)
			currentTotalWidth = currentTotalWidth + frameWidth
			table.insert(itemsData, {
				Level = lvl,
				FrameWidth = frameWidth,
				TapePosition = positionOnTape,
				Instance = nil, 
				Backboard = nil,
				ActiveModel = nil
			})
		end
	end

	for i, data in ipairs(itemsData) do
		local rarityColor = GetRarityColor(data.Level)
		local frame = Instance.new("Part")
		frame.Size = Vector3.new(data.FrameWidth, FIXED_HEIGHT, 0.2)
		frame.Transparency = 1
		frame.Anchored = true 
		frame.CanCollide = false
		frame.CanQuery = false
		frame.Parent = spinContainer

		local outline = Instance.new("SelectionBox")
		outline.Adornee = frame
		outline.Color3 = FRAME_COLOR
		outline.LineThickness = FRAME_THICKNESS
		outline.Parent = frame

		local backboard = Instance.new("Part")
		backboard.Color = rarityColor
		backboard.Material = BACKBOARD_MATERIAL
		backboard.Transparency = BACKBOARD_TRANSPARENCY
		backboard.Size = Vector3.new(data.FrameWidth, FIXED_HEIGHT, BACKBOARD_DEPTH)
		backboard.Anchored = true
		backboard.CanCollide = false
		backboard.Parent = spinContainer

		data.Instance = frame
		data.Backboard = backboard
	end

	-- Constant render loop so it doesn't break if the anchor loads off-center
	local function UpdateStaticPositions()
		if not spinContainer.Parent then return end
		local anchorCF = spinAnchor:IsA("Model") and spinAnchor:GetPivot() or spinAnchor.CFrame
		local centerFrame = anchorCF * CFrame.new(0, HEIGHT_OFFSET, -DISTANCE_FROM_PART)
		local cullLimit = (VISIBLE_VIEWPORT_WIDTH / 2) + VIEWPORT_BUFFER

		for _, data in ipairs(itemsData) do
			local relativeX = data.TapePosition
			if relativeX > -cullLimit and relativeX < cullLimit then
				local finalCF = centerFrame * CFrame.new(-relativeX, 0, 0) * ROTATION_CF
				data.Instance.CFrame = finalCF
				data.Backboard.CFrame = finalCF * BACKBOARD_OFFSET_CF

				if not data.ActiveModel then
					data.ActiveModel = GetPooledModel(data.Level)
					if data.ActiveModel then
						data.ActiveModel.Parent = spinContainer
						table.insert(ActiveSpinModels, {Model = data.ActiveModel, Level = data.Level})
					end
				end
				if data.ActiveModel and data.ActiveModel.PrimaryPart then
					data.ActiveModel:PivotTo(finalCF)
				end
			else
				if data.ActiveModel then
					ReturnModelToPool(data.ActiveModel, data.Level)
					for k, v in ipairs(ActiveSpinModels) do
						if v.Model == data.ActiveModel then table.remove(ActiveSpinModels, k); break end
					end
					data.ActiveModel = nil
				end
				data.Instance.CFrame = HIDE_CFRAME
				data.Backboard.CFrame = HIDE_CFRAME
			end
		end
	end

	UpdateStaticPositions()
	if not currentSpinConnection then
		currentSpinConnection = RunService.RenderStepped:Connect(UpdateStaticPositions)
	end

	return true
end

local function SetupPlotListener(plot)
	task.spawn(function()
		local ownerVal = plot:WaitForChild("Owner", 10)
		if ownerVal then
			local function checkOwner()
				if ownerVal.Value == player then 
					task.spawn(function()
						local pipeLoaded = false
						local paidLoaded = false
						local offlineLoaded = false
						local wheelLoaded = false

						while ownerVal.Value == player and plot.Parent do
							if not pipeLoaded then pipeLoaded = SetupScreen(plot, "PipeScreen", UPGRADE_CONFIG) end
							if not paidLoaded then paidLoaded = SetupScreen(plot, "PipeScreenPaid", PAID_UPGRADE_CONFIG) end
							if not offlineLoaded then offlineLoaded = SetupScreen(plot, "PipeScreenOfflineMerge", OFFLINE_UPGRADE_CONFIG) end
							if not wheelLoaded then wheelLoaded = BuildStaticWheel(plot) end

							if pipeLoaded and paidLoaded and offlineLoaded and wheelLoaded then
								break
							end
							task.wait(1)
						end
					end)
				elseif activeGuis[plot] then 
					for _, gui in pairs(activeGuis[plot]) do gui:Destroy() end
					activeGuis[plot] = nil

					if currentSpinFolder then 
						currentSpinFolder:Destroy()
						currentSpinFolder = nil
					end
					for _, item in pairs(ActiveSpinModels) do ReturnModelToPool(item.Model, item.Level) end
					table.clear(ActiveSpinModels)
				end
			end

			ownerVal.Changed:Connect(checkOwner)
			checkOwner()
		end
	end)
end

rollEvent.OnClientEvent:Connect(function(plot, winningLevel, serverDuration)
	if not plot then return end

	local ownerVal = plot:FindFirstChild("Owner")
	if not ownerVal or ownerVal.Value ~= player then 
		return 
	end

	SetupScreen(plot, "PipeScreen", UPGRADE_CONFIG)
	SetupScreen(plot, "PipeScreenPaid", PAID_UPGRADE_CONFIG)
	SetupScreen(plot, "PipeScreenOfflineMerge", OFFLINE_UPGRADE_CONFIG)

	if currentSpinConnection then currentSpinConnection:Disconnect(); currentSpinConnection = nil end
	if currentSpinTween then currentSpinTween:Cancel(); currentSpinTween = nil end
	if currentCompleteConnection then currentCompleteConnection:Disconnect() end

	for _, item in pairs(ActiveSpinModels) do ReturnModelToPool(item.Model, item.Level) end
	table.clear(ActiveSpinModels)
	if currentSpinFolder then currentSpinFolder:Destroy() end
	local spinContainer = Instance.new("Folder")
	spinContainer.Name = "ClientSpinWheel"
	spinContainer.Parent = Workspace
	currentSpinFolder = spinContainer
	local spinAnchor = plot:FindFirstChild("Spin") and plot.Spin:FindFirstChild("CharacterSpin")
	if not spinAnchor then return end

	local tickSound = spinAnchor:FindFirstChild("WheelTickSound")
	if not tickSound then
		tickSound = Instance.new("Sound")
		tickSound.Name = "WheelTickSound"
		tickSound.SoundId = "rbxassetid://137872392480008"
		tickSound.Volume = 1.5
		tickSound.RollOffMaxDistance = 120
		tickSound.RollOffMinDistance = 45
		tickSound.RollOffMode = Enum.RollOffMode.InverseTapered
		tickSound.Parent = spinAnchor
	end

	local offsetValue = Instance.new("NumberValue")
	offsetValue.Parent = spinContainer
	local TOTAL_ITEMS = 50
	local WINNER_INDEX = 40
	local itemsData = {}
	local currentTotalWidth = 0
	local levelCounts = {} 

	local currentWheelIndex = 1

	for i = 1, TOTAL_ITEMS do
		local lvl = (i == WINNER_INDEX) and winningLevel or GetRandomLevelForWheel()
		local template = BrainrotCache[lvl]
		if template then
			local visualWidth = template:IsA("Model") and select(2, template:GetBoundingBox()).X or template.Size.X
			local frameWidth = visualWidth + FRAME_PADDING_X
			local positionOnTape = currentTotalWidth + (frameWidth / 2)
			currentTotalWidth = currentTotalWidth + frameWidth
			if not levelCounts[lvl] then levelCounts[lvl] = 0 end
			levelCounts[lvl] += 1
			table.insert(itemsData, {
				Level = lvl,
				FrameWidth = frameWidth,
				TapePosition = positionOnTape,
				Index = i,
				Instance = nil, 
				Backboard = nil,
				ActiveModel = nil
			})
		end
	end
	for lvl, count in pairs(levelCounts) do
		local currentPoolSize = ModelPool[lvl] and #ModelPool[lvl] or 0
		local needed = count - currentPoolSize
		if needed > 0 then
			for _ = 1, needed do
				local tmpl = BrainrotCache[lvl]
				if tmpl then
					local m = tmpl:Clone()
					PrepareModelForRender(m)
					ReturnModelToPool(m, lvl) 
				end
			end
		end
	end
	for i, data in ipairs(itemsData) do
		local rarityColor = GetRarityColor(data.Level)
		local frame = Instance.new("Part")
		frame.Size = Vector3.new(data.FrameWidth, FIXED_HEIGHT, 0.2)
		frame.Transparency = 1
		frame.Anchored = true 
		frame.CanCollide = false
		frame.CanQuery = false
		frame.Parent = spinContainer
		frame.CFrame = HIDE_CFRAME
		local outline = Instance.new("SelectionBox")
		outline.Adornee = frame
		outline.Color3 = FRAME_COLOR
		outline.LineThickness = FRAME_THICKNESS
		outline.Parent = frame
		local backboard = Instance.new("Part")
		backboard.Color = rarityColor
		backboard.Material = BACKBOARD_MATERIAL
		backboard.Transparency = BACKBOARD_TRANSPARENCY
		backboard.Size = Vector3.new(data.FrameWidth, FIXED_HEIGHT, BACKBOARD_DEPTH)
		backboard.Anchored = true
		backboard.CanCollide = false
		backboard.Parent = spinContainer
		backboard.CFrame = HIDE_CFRAME
		data.Instance = frame
		data.Backboard = backboard
	end
	local function UpdatePositions()
		if not spinContainer.Parent then return end
		local currentOffset = offsetValue.Value
		local anchorCF = spinAnchor:IsA("Model") and spinAnchor:GetPivot() or spinAnchor.CFrame
		local centerFrame = anchorCF * CFrame.new(0, HEIGHT_OFFSET, -DISTANCE_FROM_PART)
		local cullLimit = (VISIBLE_VIEWPORT_WIDTH / 2) + VIEWPORT_BUFFER

		local closestIdx = 1
		local minDist = math.huge

		for i, data in ipairs(itemsData) do
			local dist = math.abs(data.TapePosition - currentOffset)
			if dist < minDist then
				minDist = dist
				closestIdx = i
			end

			if data.Detached then continue end
			local relativeX = data.TapePosition - currentOffset
			if relativeX > -cullLimit and relativeX < cullLimit then
				local finalCF = centerFrame * CFrame.new(-relativeX, 0, 0) * ROTATION_CF
				data.Instance.CFrame = finalCF
				data.Backboard.CFrame = finalCF * BACKBOARD_OFFSET_CF
				if not data.ActiveModel then
					data.ActiveModel = GetPooledModel(data.Level)
					if data.ActiveModel then
						data.ActiveModel.Parent = spinContainer
						table.insert(ActiveSpinModels, {Model = data.ActiveModel, Level = data.Level})
					end
				end
				if data.ActiveModel and data.ActiveModel.PrimaryPart then
					data.ActiveModel:PivotTo(finalCF)
				end
			else
				if data.ActiveModel then
					ReturnModelToPool(data.ActiveModel, data.Level)
					for k, v in ipairs(ActiveSpinModels) do
						if v.Model == data.ActiveModel then table.remove(ActiveSpinModels, k); break end
					end
					data.ActiveModel = nil
				end
				if data.Instance.Position.Y > -4000 then
					data.Instance.CFrame = HIDE_CFRAME
					data.Backboard.CFrame = HIDE_CFRAME
				end
			end
		end

		if closestIdx ~= currentWheelIndex then
			currentWheelIndex = closestIdx
			tickSound:Play() 
		end
	end
	currentSpinConnection = RunService.RenderStepped:Connect(UpdatePositions)
	local winningItem = itemsData[WINNER_INDEX]
	local safeTotalTime = math.max(0.1, serverDuration - 0.15) 
	local dropTime = math.min(0.5, safeTotalTime * 0.4) 
	local spinTime = safeTotalTime - dropTime
	local ti = TweenInfo.new(spinTime, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	currentSpinTween = TweenService:Create(offsetValue, ti, { Value = winningItem.TapePosition })
	currentCompleteConnection = currentSpinTween.Completed:Connect(function()
		if currentSpinConnection then currentSpinConnection:Disconnect(); currentSpinConnection = nil end

		Play3DSound("132188255620885", spinAnchor, 0.4, false) 

		offsetValue.Value = winningItem.TapePosition
		UpdatePositions()
		local winnerData = itemsData[WINNER_INDEX]
		if not winnerData.ActiveModel then
			winnerData.ActiveModel = GetPooledModel(winnerData.Level)
			winnerData.ActiveModel.Parent = spinContainer
			winnerData.ActiveModel:PivotTo(winnerData.Instance.CFrame)
		else
			for k, v in ipairs(ActiveSpinModels) do
				if v.Model == winnerData.ActiveModel then table.remove(ActiveSpinModels, k); break end
			end
		end
		winnerData.Detached = true
		local finalModel = winnerData.ActiveModel
		winnerData.ActiveModel = nil
		if finalModel and finalModel.PrimaryPart then
			local suckValue = Instance.new("CFrameValue")
			suckValue.Value = finalModel:GetPivot()
			suckValue.Parent = spinContainer
			local suckTween = TweenService:Create(suckValue, TweenInfo.new(dropTime, Enum.EasingStyle.Exponential, Enum.EasingDirection.In), {
				Value = suckValue.Value * CFrame.new(0, -15, 0)
			})
			local conn = suckValue.Changed:Connect(function(val)
				if finalModel.Parent then finalModel:PivotTo(val) end
			end)
			suckTween.Completed:Connect(function()
				conn:Disconnect()
				suckValue:Destroy()
				finalModel:Destroy()
			end)
			suckTween:Play()
		end
	end)
	currentSpinTween:Play()
end)

task.spawn(function()
	local map = Workspace:WaitForChild("TycoonMap", 60)
	if map then
		for _, plot in ipairs(map:GetChildren()) do
			SetupPlotListener(plot)
		end
		-- Catch any plots that load dynamically after the initial check
		map.ChildAdded:Connect(SetupPlotListener)
	end
end)


-- [[ PASSIVE MONEY VISUALS ]] --

local MoneyPopupTemplate = Instance.new("Part")
MoneyPopupTemplate.Name = "MoneyPopup"
MoneyPopupTemplate.Transparency = 1
MoneyPopupTemplate.CanCollide = false
MoneyPopupTemplate.CanQuery = false
MoneyPopupTemplate.CanTouch = false
MoneyPopupTemplate.Anchored = true
MoneyPopupTemplate.Size = Vector3.new(0.5, 0.5, 0.5)

local popGui = Instance.new("BillboardGui")
popGui.AlwaysOnTop = true
popGui.LightInfluence = 0
popGui.Size = UDim2.new(5, 0, 2.5, 0) 
popGui.Parent = MoneyPopupTemplate

local popLabel = Instance.new("TextLabel")
popLabel.Name = "Label"
popLabel.Size = UDim2.new(1, 0, 1, 0)
popLabel.BackgroundTransparency = 1
popLabel.TextColor3 = Color3.fromRGB(85, 255, 127) 
popLabel.TextStrokeTransparency = 0
popLabel.TextStrokeColor3 = Color3.new(0,0,0)
popLabel.Font = Enum.Font.FredokaOne
popLabel.TextScaled = true 
popLabel.Parent = popGui

local function CreateFloatingText(position, amount, formatted)
	local part = MoneyPopupTemplate:Clone()
	part.Position = position

	local label = part.BillboardGui.Label
	if formatted then 
		label.Text = "+$" .. formatted 
	else 
		label.Text = "+$" .. FormatNumber(amount) 
	end

	part.Parent = Workspace.CurrentCamera 

	local tweenInfo = TweenInfo.new(4.0, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	local moveTween = TweenService:Create(part, tweenInfo, {
		Position = position + Vector3.new(0, 4, 0) 
	})
	local fadeTween = TweenService:Create(label, tweenInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1
	})

	moveTween:Play()
	fadeTween:Play()
	Debris:AddItem(part, 4.5)
end

fxEvent.OnClientEvent:Connect(function(action, data, extra)
	if action == "PassiveGen" and data then
		for _, info in ipairs(data) do
			CreateFloatingText(info.Pos, info.Amt, info.Formatted)
		end
	elseif action == "Sell" or action == "Merge" then
		if action == "Sell" then
			PlayUISound("128618867765188", 0.5) 
		end
		local pos = data 
		local amt = extra and extra.Cash
		local fmt = extra and extra.Formatted
		if pos and amt then
			CreateFloatingText(pos, amt, fmt)
		end
	end
end)