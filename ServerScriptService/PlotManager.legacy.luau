local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local map = Workspace:WaitForChild("TycoonMap")

local function AssignPlot(player)
	if player:FindFirstChild("MyPlot") then return end

	for _, plot in pairs(map:GetChildren()) do
		if plot:FindFirstChild("Owner") and plot.Owner.Value == nil then
			plot.Owner.Value = player
			plot.Name = player.Name .. "_Plot"

			local sign = plot:FindFirstChild("Sign")
			if sign and sign:FindFirstChild("SurfaceGui") then
				sign.SurfaceGui.TextLabel.Text = player.Name
				sign.Color = Color3.fromRGB(85, 255, 127) 
			end

			local tag = Instance.new("ObjectValue")
			tag.Name = "MyPlot"
			tag.Value = plot
			tag.Parent = player
			print("Assigned plot to " .. player.Name)
			return
		end
	end
end

local function FreePlot(player)
	local plot = map:FindFirstChild(player.Name .. "_Plot")
	if plot then
		local itemsToClear = plot.Items:GetChildren() 
		local platform = plot:FindFirstChild("BestCharacterPlatform")
		local displayToClear = platform and platform:FindFirstChild("DisplayModel")

		-- FIX: Freeze all items instantly so the server doesn't get 
		-- crushed by a physics lag spike when network ownership transfers.
		for _, item in ipairs(itemsToClear) do
			for _, part in ipairs(item:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			if item:IsA("BasePart") then
				item.Anchored = true
			end
		end

		plot.Owner.Value = nil
		plot.Name = "Plot_Empty"

		task.delay(3, function()
			for _, item in ipairs(itemsToClear) do
				if item and item.Parent then item:Destroy() end
			end

			if displayToClear and displayToClear.Parent then 
				displayToClear:Destroy() 
			end

			if plot.Name == "Plot_Empty" then 
				local sign = plot:FindFirstChild("Sign")
				if sign and sign:FindFirstChild("SurfaceGui") then
					sign.SurfaceGui.TextLabel.Text = "Claim Plot"
					sign.Color = Color3.fromRGB(255, 255, 255)
				end
			end
		end)
	end
end

Players.PlayerAdded:Connect(AssignPlot)
Players.PlayerRemoving:Connect(FreePlot)

for _, p in pairs(Players:GetPlayers()) do
	AssignPlot(p)
end