-- [[ ServerScriptService/RebirthManager.server.luau ]] --
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local remotes = RS:WaitForChild("TycoonRemotes")
local rbFunc = remotes:WaitForChild("Rebirth")
local requestDrop = remotes:WaitForChild("RequestDrop") 

-- [[ CALIBRATION FORMULAS ]] --
local function GetRebirthRequirements(rebirths)
	local reqLevel = 15 + (rebirths * 5)
	-- Matches the PipeLevel cost formula: BaseCost * (Multiplier ^ (Level - 1))
	local reqCash = 5000 * (2.42 ^ (reqLevel - 1))

	return reqCash, reqLevel
end

rbFunc.OnServerInvoke = function(player)
	local ls = player:FindFirstChild("leaderstats")
	local upg = player:FindFirstChild("Upgrades")
	local myPlotVal = player:FindFirstChild("MyPlot") 

	if not (ls and upg) then return false end

	local currentRebirths = ls.Rebirths.Value
	local cashReq, levelReq = GetRebirthRequirements(currentRebirths)

	if ls.Cash.Value >= cashReq and ls.HighestMerge.Value >= levelReq then

		-- 1. LOCK SPAWNING
		if myPlotVal and myPlotVal.Value then
			local plot = myPlotVal.Value
			local currentId = plot:GetAttribute("RebirthID") or 0
			plot:SetAttribute("RebirthID", currentId + 1)
			plot:SetAttribute("SpawningInProgress", true)
		end

		-- 2. RESET STATS & APPLY REWARDS
		ls.Cash.Value = 0
		ls.HighestMerge.Value = 1
		ls.Rebirths.Value += 1

		-- Gem Reward: Scales with effort
		if ls:FindFirstChild("Gems") then
			ls.Gems.Value += (100 * (currentRebirths + 1))
		end

		-- Standard Resets
		upg.PipeSpeed.Value = 1
		upg.PipeLuck.Value = 1
		upg.Grinder.Value = 1
		if upg:FindFirstChild("PipeLevel") then upg.PipeLevel.Value = 1 end
		if upg:FindFirstChild("PipeCapacity") then upg.PipeCapacity.Value = 1 end
		if upg:FindFirstChild("SellValue") then upg.SellValue.Value = 1 end
		if upg:FindFirstChild("MoneyGeneration") then upg.MoneyGeneration.Value = 1 end

		-- 3. CLEAR PLOT & DISCONNECT HOLDING
		if myPlotVal and myPlotVal.Value then
			local items = myPlotVal.Value:FindFirstChild("Items")
			if items then items:ClearAllChildren() end
		end
		requestDrop:Invoke(player) -- Clears server-side 'heldItems' list 

		-- 4. PLAY SOUND
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://103181330452084" -- Rebirth Sound
		sound.Volume = 1
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			sound.Parent = root
			sound:Play()
			Debris:AddItem(sound, 6)
		else
			sound.Parent = player:FindFirstChild("PlayerGui") or player
			sound:Play()
			Debris:AddItem(sound, 6)
		end

		-- 5. UNLOCK WHEEL (Delay to allow client cleanup)
		task.delay(1.5, function()
			if myPlotVal and myPlotVal.Value then
				myPlotVal.Value:SetAttribute("SpawningInProgress", false)
			end
		end)

		return true
	end
	return false
end