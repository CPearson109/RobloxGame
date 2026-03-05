local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")

-- We use a specific DataStore just for Spins
local SpinDataStore = DataStoreService:GetDataStore("SpinSystem_Data") 

local SpinEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Spin")
local SpinModule = require(ReplicatedStorage:WaitForChild("SpinModule"))
local Brainrots = ReplicatedStorage:WaitForChild("Brainrots")
local TycoonMap = Workspace:WaitForChild("TycoonMap")

-- [[ GEM STORM REMOTE ]] --
local Remotes = ReplicatedStorage:WaitForChild("TycoonRemotes")
local StartGemStorm = Remotes:FindFirstChild("StartGemStorm")
if not StartGemStorm then
	StartGemStorm = Instance.new("RemoteEvent")
	StartGemStorm.Name = "StartGemStorm"
	StartGemStorm.Parent = Remotes
end

-- [[ CACHE LEVELS ]] --
local BrainrotCache = {}
for _, model in pairs(Brainrots:GetChildren()) do
	local lvlObj = model:FindFirstChild("Level")
	if lvlObj and lvlObj:IsA("IntValue") then
		BrainrotCache[lvlObj.Value] = model
	end
end

local function PlayerJoined(Player)
	local PlayerStats = Instance.new("Folder", Player)
	PlayerStats.Name = "PlayerStats"

	local SpinTime = Instance.new("NumberValue", PlayerStats)
	SpinTime.Name = "SpinTime"
	SpinTime.Value = SpinModule.Spin.SpinTimeForReward

	local Spin = Instance.new("NumberValue", PlayerStats)
	Spin.Name = "Spin"
	Spin.Value = SpinDataStore:GetAsync("Spin"..Player.UserId) or 1

	task.spawn(function()
		while task.wait(1) do
			if SpinTime.Value > 0 then
				SpinTime.Value -= 1
			elseif SpinTime.Value <= 0 then
				SpinTime.Value = SpinModule.Spin.SpinTimeForReward
				Spin.Value += 1
			end
		end
	end)
end

local function PlayerRemoved(Player)
	local PlayerStats = Player:FindFirstChild("PlayerStats")
	if PlayerStats then
		local Spin = PlayerStats:FindFirstChild("Spin")
		if Spin then
			SpinDataStore:SetAsync("Spin"..Player.UserId, Spin.Value)
		end
	end
end

local function StudioSave()
	task.wait(0.7)
end

-- [[ HELPER: FIND PLOT ]] --
local function FindPlayerPlot(player)
	for _, plot in pairs(TycoonMap:GetChildren()) do
		local owner = plot:FindFirstChild("Owner")
		if owner and owner.Value == player then return plot end
	end
	return nil
end

-- [[ HELPER: DYNAMIC CASH ]] --
local function CalculateDynamicCash(player)
	local currentCash = player.leaderstats.Cash.Value
	-- Give 15% of current cash, or 500 minimum
	local reward = math.max(500, currentCash * 0.15)

	-- Round to a nice number
	local digits = #tostring(math.floor(reward))
	local divisor = 10 ^ (math.max(1, digits - 2)) 
	return math.floor(reward / divisor + 0.5) * divisor
end

local function SpinEventFire(Player, SpinReward)
	local Spin = Player:FindFirstChild("PlayerStats") and Player:FindFirstChild("PlayerStats"):FindFirstChild("Spin")
	if not Spin then return end

	if Spin.Value >= 1 then
		Spin.Value -= 1

		local rewardInfo = SpinModule.Spin.Rewards[SpinReward]
		if not rewardInfo then return end

		------------------------------------------------------
		-- 1. ITEM RAIN
		------------------------------------------------------
		if rewardInfo.Type == "ItemRain" then
			local plot = FindPlayerPlot(Player)
			if plot then
				local itemsFolder = plot:FindFirstChild("Items")
				local floor = plot:FindFirstChild("Floor")

				-- [[ LEVEL ALIGNMENT FIX ]] --
				local baseLevel = 1
				if Player:FindFirstChild("Upgrades") and Player.Upgrades:FindFirstChild("PipeLevel") then
					baseLevel = Player.Upgrades.PipeLevel.Value
				end

				if itemsFolder and floor then
					for i = 1, rewardInfo.Amount do
						-- Drop item matching upgrade level
						local template = BrainrotCache[baseLevel] or BrainrotCache[1]

						if template then
							local randomItem = template:Clone()
							local rX = math.random(-25, 25)
							local rZ = math.random(-25, 25)
							local spawnPos = floor.Position + Vector3.new(rX, 40, rZ) 

							randomItem.Parent = itemsFolder

							-- [[ PHYSICS FIX ]] --
							local root = randomItem.PrimaryPart or randomItem:FindFirstChildWhichIsA("BasePart", true)

							if randomItem:IsA("Model") then
								randomItem:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(math.random(), math.random(), math.random()))
							elseif root then
								root.Position = spawnPos
							end

							if root then
								root.Anchored = false
								root.CanCollide = true -- Immediate collision
								-- FORCE "Default" group so it hits floor
								pcall(function() root.CollisionGroup = "Default" end) 
								root.AssemblyLinearVelocity = Vector3.new(0, -50, 0) -- Slam it down
							end
							-- [[ END PHYSICS FIX ]] --

							task.wait(0.05) 
						end
					end
				end
			end

			------------------------------------------------------
			-- 2. GEM STORM
			------------------------------------------------------
		elseif rewardInfo.Type == "GemStorm" then
			StartGemStorm:FireClient(Player, 15)

			------------------------------------------------------
			-- 3. DYNAMIC CASH
			------------------------------------------------------
		elseif rewardInfo.Type == "DynamicCash" then
			local amount = CalculateDynamicCash(Player)
			local Currency = Player.leaderstats:FindFirstChild("Cash")
			if Currency then
				Currency.Value += amount
			end

			------------------------------------------------------
			-- 4. STANDARD REWARDS
			------------------------------------------------------
		else
			local leaderstats = Player:WaitForChild("leaderstats", 5) 
			if leaderstats then
				local Currency = leaderstats:FindFirstChild(rewardInfo.Reward)
				if Currency then
					Currency.Value += rewardInfo.Amount
				end
			end
		end
	end
end

Players.PlayerAdded:Connect(PlayerJoined)
Players.PlayerRemoving:Connect(PlayerRemoved)
game:BindToClose(StudioSave)
SpinEvent.OnServerEvent:Connect(SpinEventFire)