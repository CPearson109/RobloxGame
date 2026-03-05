-- [[ ServerScriptService/LeaderboardManager.server.luau ]] --

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimePlayedDS = DataStoreService:GetOrderedDataStore("TimePlayed_Global_V1")
local RobuxSpentDS = DataStoreService:GetOrderedDataStore("RobuxSpent_Global_V1")
local FastestMaxLevelDS = DataStoreService:GetOrderedDataStore("FastestMaxLevel_Global_V1")

local UPDATE_INTERVAL = 60 

-- NEW LOCATION REFERENCE 
local Map = Workspace:WaitForChild("TycoonMap")
local Path = Map:WaitForChild("Path")
local LeaderboardsFolder = Path:WaitForChild("Leaderboards")

-- Session Tracking
local sessionData = {}

local function GetMaxLevel()
	local brainrots = ReplicatedStorage:FindFirstChild("Brainrots")
	if not brainrots then return 999 end
	local max = 0
	for _, child in pairs(brainrots:GetChildren()) do
		local lvl = child:FindFirstChild("Level")
		if lvl and lvl.Value > max then max = lvl.Value end
	end
	return max
end

local function FormatTime(seconds)
	if not seconds or seconds == 0 then return "00:00:00" end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function FormatNumber(n)
	return tostring(n):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
end

local function UpdateSurfaceGui(boardModel, dataStore, ascending, isTime)
	if not boardModel then return end

	-- Look for the SurfaceGui inside the board 
	local surfaceGui = boardModel:FindFirstChild("Leaderboard", true) 
		or boardModel:FindFirstChildWhichIsA("SurfaceGui", true)
	if not surfaceGui then return end

	-- Find specific folders: Names, Score, Photos 
	local namesFolder = surfaceGui:FindFirstChild("Names")
	local scoresFolder = surfaceGui:FindFirstChild("Score") or surfaceGui:FindFirstChild("Scores")
	local photosFolder = surfaceGui:FindFirstChild("Photos")

	if not namesFolder or not scoresFolder then return end

	local success, pages = pcall(function()
		return dataStore:GetSortedAsync(ascending, 10) 
	end)

	if success and pages then
		local data = pages:GetCurrentPage()

		for i = 1, 10 do
			local nameLbl = namesFolder:FindFirstChild("Name" .. i)
			local scoreLbl = scoresFolder:FindFirstChild("Score" .. i)
			local photoLbl = photosFolder and photosFolder:FindFirstChild("Photo" .. i)

			if nameLbl and scoreLbl then
				local entry = data[i]

				if entry then
					local playerName = "Unknown"
					pcall(function() 
						playerName = Players:GetNameFromUserIdAsync(entry.key) 
					end)

					local valDisplay = isTime and FormatTime(entry.value) or FormatNumber(entry.value)

					nameLbl.Text = playerName
					scoreLbl.Text = valDisplay

					if photoLbl and photoLbl:IsA("ImageLabel") then
						photoLbl.Image = "rbxthumb://type=AvatarHeadShot&id=" .. entry.key .. "&w=150&h=150"
						photoLbl.ImageTransparency = 0
					end
				else
					nameLbl.Text = "..."
					scoreLbl.Text = "..."
					if photoLbl and photoLbl:IsA("ImageLabel") then 
						photoLbl.ImageTransparency = 1 
					end
				end
			end
		end
	end
end

local function UpdateTimerDisplay(boardModel, timeLeft)
	if not boardModel then return end
	local timerPart = boardModel:FindFirstChild("UpdateBoardTimer")
	if timerPart then
		local timerGui = timerPart:FindFirstChild("Timer")
		if timerGui then
			local textLabel = timerGui:FindFirstChildWhichIsA("TextLabel")
			if textLabel then
				textLabel.Text = string.format("Updating the board in %d seconds", timeLeft)
			end
		end
	end
end

-- Refresh Loop
task.spawn(function()
	task.wait(5)

	while true do
		-- TARGET NEW FOLDER 
		local boardTime = LeaderboardsFolder:FindFirstChild("TimePlayedLeaderboard")
		local boardRobux = LeaderboardsFolder:FindFirstChild("RobuxSpent")
		local boardFastest = LeaderboardsFolder:FindFirstChild("FastestMaxLevel")

		UpdateSurfaceGui(boardTime, TimePlayedDS, false, true)
		UpdateSurfaceGui(boardRobux, RobuxSpentDS, false, false)
		UpdateSurfaceGui(boardFastest, FastestMaxLevelDS, true, true)

		-- Run visual countdown for the next refresh 
		for timeLeft = UPDATE_INTERVAL, 1, -1 do
			UpdateTimerDisplay(boardTime, timeLeft)
			UpdateTimerDisplay(boardRobux, timeLeft)
			UpdateTimerDisplay(boardFastest, timeLeft)
			task.wait(1)
		end
	end
end)

-- Player Tracking
Players.PlayerAdded:Connect(function(player)
	local joinTime = os.time()

	local successTime, playedTime = pcall(function() return TimePlayedDS:GetAsync(player.UserId) end)
	local successRobux, robuxSpent = pcall(function() return RobuxSpentDS:GetAsync(player.UserId) end)
	local successFastest, fastestTime = pcall(function() return FastestMaxLevelDS:GetAsync(player.UserId) end)

	sessionData[player] = {
		JoinTime = joinTime,
		BaseTimePlayed = (successTime and playedTime) or 0,
		RobuxSpent = (successRobux and robuxSpent) or 0,
		FastTimerAccumulated = (successFastest and fastestTime) or 0,
		TimerStart = joinTime,
		ReachedMax = false
	}

	local ls = player:WaitForChild("leaderstats", 10)
	if ls then
		local highestMerge = ls:WaitForChild("HighestMerge", 5)
		if highestMerge then
			local maxLvl = GetMaxLevel()

			if highestMerge.Value >= maxLvl then
				sessionData[player].ReachedMax = true
			end

			highestMerge.Changed:Connect(function(newVal)
				if newVal == 1 then
					sessionData[player].FastTimerAccumulated = 0
					sessionData[player].TimerStart = os.time()
					sessionData[player].ReachedMax = false
					pcall(function() FastestMaxLevelDS:RemoveAsync(player.UserId) end)

				elseif newVal >= maxLvl and not sessionData[player].ReachedMax then
					sessionData[player].ReachedMax = true
					local totalFastTime = sessionData[player].FastTimerAccumulated + (os.time() - sessionData[player].TimerStart)
					pcall(function() FastestMaxLevelDS:SetAsync(player.UserId, totalFastTime) end)
				end
			end)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local data = sessionData[player]
	if data then
		local sessionTime = os.time() - data.JoinTime
		local totalTime = data.BaseTimePlayed + sessionTime

		pcall(function() TimePlayedDS:SetAsync(player.UserId, totalTime) end)
		pcall(function() RobuxSpentDS:SetAsync(player.UserId, data.RobuxSpent) end)

		if not data.ReachedMax then
			local fastTimeElapsed = os.time() - data.TimerStart
			local totalFastTime = data.FastTimerAccumulated + fastTimeElapsed
			pcall(function() FastestMaxLevelDS:SetAsync(player.UserId, totalFastTime) end)
		end

		sessionData[player] = nil
	end
end)

-- Track Robux Purchases
local function OnPurchase(player, productId, isGamePass)
	if not player then return end
	local data = sessionData[player]
	if not data then return end

	pcall(function()
		local productInfo = MarketplaceService:GetProductInfo(productId, isGamePass and Enum.InfoType.GamePass or Enum.InfoType.Product)
		if productInfo and productInfo.PriceInRobux then
			data.RobuxSpent += productInfo.PriceInRobux
			RobuxSpentDS:SetAsync(player.UserId, data.RobuxSpent)
		end
	end)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if wasPurchased then OnPurchase(player, passId, true) end
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
	if wasPurchased then 
		local player = Players:GetPlayerByUserId(userId)
		OnPurchase(player, productId, false) 
	end
end)

-- BindToClose to save data on server shutdown
game:BindToClose(function()
	for _, player in pairs(Players:GetPlayers()) do
		local data = sessionData[player]
		if data then
			local sessionTime = os.time() - data.JoinTime
			pcall(function() TimePlayedDS:SetAsync(player.UserId, data.BaseTimePlayed + sessionTime) end)
			pcall(function() RobuxSpentDS:SetAsync(player.UserId, data.RobuxSpent) end)
			if not data.ReachedMax then
				pcall(function() FastestMaxLevelDS:SetAsync(player.UserId, data.FastTimerAccumulated + (os.time() - data.TimerStart)) end)
			end
		end
	end
end)