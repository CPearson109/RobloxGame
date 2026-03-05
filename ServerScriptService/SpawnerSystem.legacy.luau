-- ServerScriptService/SpawnerSystem.lua

local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local AchievementManager = require(game.ServerScriptService.AchievementManager)

local map = Workspace:WaitForChild("TycoonMap")
local brainrots = RS:WaitForChild("Brainrots")
local remotes = RS:WaitForChild("TycoonRemotes")

local rollEvent = remotes:FindFirstChild("AnimateRoll")
if not rollEvent then
	rollEvent = Instance.new("RemoteEvent")
	rollEvent.Name = "AnimateRoll"
	rollEvent.Parent = remotes
end

-- [[ LOOKUP TABLE ]] --
local BrainrotCache = {}
local AvailableLevels = {}

local function UpdateBrainrotCache()
	table.clear(BrainrotCache)
	table.clear(AvailableLevels)
	for _, model in pairs(brainrots:GetChildren()) do
		local lvlObj = model:FindFirstChild("Level")
		if lvlObj and lvlObj:IsA("IntValue") then
			local lvl = lvlObj.Value
			BrainrotCache[lvl] = model
			table.insert(AvailableLevels, lvl)
		end
	end
	table.sort(AvailableLevels)
end

UpdateBrainrotCache()
brainrots.ChildAdded:Connect(UpdateBrainrotCache)
brainrots.ChildRemoved:Connect(UpdateBrainrotCache)

-- [[ 1. SPEED LOGIC ]] --
local MIN_DURATION = 1.0
local MAX_DURATION = 6.0
local MAX_SPEED_LEVEL = 30 

local function GetCycleDuration(level, player)
	local lvl = math.clamp(level, 1, MAX_SPEED_LEVEL)
	local alpha = (lvl - 1) / (MAX_SPEED_LEVEL - 1)
	local baseDuration = MAX_DURATION - (alpha * (MAX_DURATION - MIN_DURATION))

	if player then
		local now = workspace:GetServerTimeNow()
		local endBoost = player:GetAttribute("Boost_2xSpinSpeed_End")
		if endBoost and endBoost > now then
			return baseDuration * 0.5 
		end
	end

	return baseDuration
end

-- [[ 2. CAPACITY LOGIC ]] --
local BASE_CAPACITY = 15
local CAPACITY_PER_LEVEL = 3

local function GetMaxCapacity(capLevel)
	return BASE_CAPACITY + ((capLevel or 1) * CAPACITY_PER_LEVEL)
end

-- [[ 3. SPAWN LOGIC ]] --
local function GetSpawnLevel(baseLevelIndex, luckLevel)
	if #AvailableLevels == 0 then return 1 end
	local centerIndex = math.clamp(baseLevelIndex, 1, #AvailableLevels)
	luckLevel = luckLevel or 1

	local weights = {}
	local totalWeight = 0

	for i = -2, 4 do 
		local targetIndex = centerIndex + i
		if targetIndex >= 1 and targetIndex <= #AvailableLevels then
			local w = 0
			if i == 0 then w = 100
			elseif i < 0 then w = 10
			elseif i > 0 then
				local luckMultiplier = (luckLevel * 5) 
				local distanceDecay = (i * 15)
				local baseChance = 20
				w = math.max(0, baseChance + luckMultiplier - distanceDecay)
			end
			weights[targetIndex] = w
			totalWeight += w
		end
	end

	local roll = math.random(1, totalWeight)
	local cumulative = 0
	for index, weight in pairs(weights) do
		cumulative += weight
		if roll <= cumulative then return AvailableLevels[index] end
	end
	return AvailableLevels[centerIndex]
end

-- [[ RARITY LOGIC RE-WRITE ]] --
local function GetRarityRoll(luckLvl)
	-- At max luck, chance caps out at roughly ~33% to get ANY rarity.
	local maxRarityChance = 5.0 + (luckLvl * 0.6) 
	maxRarityChance = math.clamp(maxRarityChance, 0, 33)

	local roll = math.random() * 100

	-- Draw 1: Are we getting a rarity at all?
	if roll <= maxRarityChance then
		-- Draw 2: Which rarity is it?
		local subRoll = math.random() * 100

		-- Inside the rare pool, odds dynamically shift based on luck
		local secretChance = 0.5 + (luckLvl * 0.2)
		local godChance = 3.0 + (luckLvl * 0.5)
		local mythicChance = 15.0 + (luckLvl * 1.0)

		if subRoll <= secretChance then return 4 end
		if subRoll <= secretChance + godChance then return 3 end
		if subRoll <= secretChance + godChance + mythicChance then return 2 end

		-- Remaining chance goes to Legendary
		return 1 
	end

	return 0 -- Normal (No rarity)
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

-- [[ PHYSICS HELPERS ]] --
local function GetPhysicsPart(item)
	if not item then return nil end
	if item:IsA("Model") then
		if item.PrimaryPart then return item.PrimaryPart end
		return item:FindFirstChildWhichIsA("BasePart", true)
	elseif item:IsA("BasePart") then return item end
	return nil
end

local function GetBottomOffset(item, physicsPart)
	local cf, size
	if item:IsA("Model") then cf, size = item:GetBoundingBox()
	else cf = item.CFrame; size = item.Size end
	return physicsPart.Position.Y - (cf.Position.Y - (size.Y / 2))
end

-- [[ SIDE-AWARE SPOT FINDER ]] --
local function FindEmptySpot(plot)
	local floor = plot:FindFirstChild("Floor")
	local itemsFolder = plot:FindFirstChild("Items")
	if not floor then return Vector3.new(0, 10, 0), 10 end 

	local floorTopY = floor.Position.Y + (floor.Size.Y * 0.5)

	local SPIN_MODEL_PADDING = 25  
	local WALL_PADDING = 5         
	local ITEM_SPACING = 3.5       

	local halfX = (floor.Size.X / 2)
	local halfZ = (floor.Size.Z / 2)

	local minX = -halfX + WALL_PADDING
	local maxX = halfX - WALL_PADDING

	local minZ = -halfZ + SPIN_MODEL_PADDING 
	local maxZ = halfZ - WALL_PADDING

	local bestSpot = Vector3.new(0, floorTopY, 0)

	for i = 1, 10 do
		local rX = math.random() * (maxX - minX) + minX
		local rZ = math.random() * (maxZ - minZ) + minZ

		local worldPos = floor.CFrame:PointToWorldSpace(Vector3.new(
			(rX), 
			(floor.Size.Y/2),
			(rZ)
			))

		local tooClose = false
		if itemsFolder then
			for _, child in pairs(itemsFolder:GetChildren()) do
				local pp = GetPhysicsPart(child)
				if pp then
					local dist = (Vector3.new(pp.Position.X, 0, pp.Position.Z) - Vector3.new(worldPos.X, 0, worldPos.Z)).Magnitude
					if dist < ITEM_SPACING then
						tooClose = true
						break
					end
				end
			end
		end

		bestSpot = worldPos
		if not tooClose then
			break 
		end
	end

	return bestSpot, floorTopY
end

local function AddStabilizer(part)
	for _, c in pairs(part:GetChildren()) do
		if c.Name == "UprightGyro" then c:Destroy() end
	end
	local bg = Instance.new("BodyGyro")
	bg.Name = "UprightGyro"
	bg.MaxTorque = Vector3.new(400000, 0, 400000)
	bg.P = 3000; bg.D = 500
	bg.CFrame = CFrame.new()
	bg.Parent = part
end

-- [[ MAIN LOOP ]] --
while true do
	task.wait(0.1)

	for _, plot in pairs(map:GetChildren()) do
		if plot:GetAttribute("IsRebirthing") then continue end

		local ownerVal = plot:FindFirstChild("Owner")
		local itemsFolder = plot:FindFirstChild("Items")

		local spinFolder = plot:FindFirstChild("Spin")
		local pipeScreen = nil
		if spinFolder then
			pipeScreen = spinFolder:FindFirstChild("PipeScreen")
		else
			pipeScreen = plot:FindFirstChild("PipeScreen")
		end

		if ownerVal and ownerVal.Value ~= nil and itemsFolder and pipeScreen then

			if plot:GetAttribute("SpawningInProgress") == true then continue end

			local player = ownerVal.Value
			local speedLvl = 1
			local baseLvl = 1
			local luckLvl = 1
			local capLvl = 1

			if player:FindFirstChild("Upgrades") then
				local u = player.Upgrades
				if u:FindFirstChild("PipeSpeed") then speedLvl = u.PipeSpeed.Value end
				if u:FindFirstChild("PipeLevel") then baseLvl = u.PipeLevel.Value end
				if u:FindFirstChild("PipeLuck") then luckLvl = u.PipeLuck.Value end
				if u:FindFirstChild("PipeCapacity") then capLvl = u.PipeCapacity.Value end
			end

			local now = workspace:GetServerTimeNow()
			local endLuck = player:GetAttribute("Boost_2xSpinLuck_End")
			if endLuck and endLuck > now then
				luckLvl = luckLvl * 2
			end

			local currentMax = GetMaxCapacity(capLvl)
			local currentItemsCount = #itemsFolder:GetChildren()

			-- Allow exactly one "dummy roll" if the floor is full to trigger the UI
			if currentItemsCount >= currentMax then
				if plot:GetAttribute("DummyRollDone") then
					continue
				else
					plot:SetAttribute("DummyRollDone", true)
					AchievementManager.Award(player, "PipeJam")
				end
			else
				plot:SetAttribute("DummyRollDone", nil)
			end

			local totalCycleTime = GetCycleDuration(speedLvl, player)
			local startRebirthId = plot:GetAttribute("RebirthID") or 0

			plot:SetAttribute("SpawningInProgress", true)

			local spawnLevel = GetSpawnLevel(baseLvl, luckLvl)
			local rarityTier = GetRarityRoll(luckLvl)

			rollEvent:FireAllClients(plot, spawnLevel, totalCycleTime)

			task.delay(totalCycleTime, function()
				local success, err = pcall(function()

					local currentRebirthId = plot:GetAttribute("RebirthID") or 0
					if currentRebirthId ~= startRebirthId then return end
					if #itemsFolder:GetChildren() >= currentMax then return end

					local template = BrainrotCache[spawnLevel]
					if template then
						local item = template:Clone()
						item:SetAttribute("Immune", true)
						item:SetAttribute("Rarity", rarityTier)

						task.delay(3, function() if item then item:SetAttribute("Immune", nil) end end)

						item.Parent = itemsFolder
						local physicsPart = GetPhysicsPart(item)

						ApplyRarityVisuals(item, rarityTier)

						local spawnOrigin
						local playerCannon = plot:FindFirstChild("Player Cannon")
						local spawnPart = playerCannon and playerCannon:FindFirstChild("SpawnPart")

						if spawnPart then 
							spawnOrigin = spawnPart.Position 
						else 
							spawnOrigin = pipeScreen.Position + (pipeScreen.CFrame.LookVector * 5) 
						end

						if item:IsA("Model") then item:PivotTo(CFrame.new(spawnOrigin))
						elseif physicsPart then physicsPart.Position = spawnOrigin end

						if physicsPart then
							physicsPart.Anchored = false
							physicsPart.CanCollide = false
							pcall(function() physicsPart.CollisionGroup = "TycoonItems" end)

							AddStabilizer(physicsPart)

							if player and player:IsDescendantOf(game) then
								physicsPart:SetNetworkOwner(player)
							end

							local offsetFromBottom = GetBottomOffset(item, physicsPart)
							local floorTargetVec, floorY = FindEmptySpot(plot)

							local targetY = floorY + offsetFromBottom + 0.2
							local targetPos = Vector3.new(floorTargetVec.X, targetY, floorTargetVec.Z)

							local direction = (targetPos - physicsPart.Position)
							local travelTime = 1.2
							local gravity = Workspace.Gravity

							local vx = direction.X / travelTime
							local vz = direction.Z / travelTime
							local vy = (direction.Y + (0.5 * gravity * (travelTime * travelTime))) / travelTime

							physicsPart.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
							physicsPart.AssemblyAngularVelocity = Vector3.new(0, math.random(-5, 5), 0)

							task.delay(0.3, function()
								if physicsPart and physicsPart.Parent then
									physicsPart.CanCollide = true
								end
							end)
						end
					end
				end)

				if not success then
					warn("Spawner Error: " .. tostring(err))
				end

				plot:SetAttribute("SpawningInProgress", false)
			end)
		end
	end
end