local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local TycoonMap = Workspace:WaitForChild("TycoonMap")

-- [[ CONFIG ]] --
local RENDER_DISTANCE = 120 
local CHECK_INTERVAL = 1.0  

local plotItems = {}

-- [[ FUNCTION: HIDE/SHOW PLOT ]] --
local function UpdatePlotVisibility(plot)
	local itemsFolder = plot:FindFirstChild("Items")
	local ownerVal = plot:FindFirstChild("Owner")
	local floor = plot:FindFirstChild("Floor")

	if not itemsFolder or not floor then return end

	if ownerVal and ownerVal.Value == player then
		for _, item in ipairs(itemsFolder:GetChildren()) do
			if item:GetAttribute("IsHidden") then
				for _, part in ipairs(item:GetDescendants()) do
					if part:IsA("BasePart") or part:IsA("Decal") then
						part.Transparency = part:GetAttribute("OrigTrans") or 0
						if part:IsA("BasePart") then
							local origShadow = part:GetAttribute("OrigShadow")
							if origShadow ~= nil then part.CastShadow = origShadow else part.CastShadow = true end
						end
					end
					if part:IsA("ParticleEmitter") or part:IsA("BillboardGui") or part:IsA("Beam") or part:IsA("Light") then
						part.Enabled = true
					end
				end
				item:SetAttribute("IsHidden", nil)
			end
		end
		return
	end

	local myPos = player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart.Position
	if not myPos then return end

	local plotPos = floor.Position
	local dist = (myPos - plotPos).Magnitude

	local shouldHide = true 

	for _, item in ipairs(itemsFolder:GetChildren()) do
		if shouldHide and not item:GetAttribute("IsHidden") then
			item:SetAttribute("IsHidden", true)
			for _, part in ipairs(item:GetDescendants()) do
				if part:IsA("BasePart") or part:IsA("Decal") then
					part:SetAttribute("OrigTrans", part.Transparency)
					if part:IsA("BasePart") then
						part:SetAttribute("OrigShadow", part.CastShadow)
						part.CastShadow = false
					end
					part.Transparency = 1 
				end
				if part:IsA("ParticleEmitter") or part:IsA("BillboardGui") or part:IsA("Beam") or part:IsA("Light") then
					part.Enabled = false
				end
			end
		elseif not shouldHide and item:GetAttribute("IsHidden") then
			item:SetAttribute("IsHidden", nil)
			for _, part in ipairs(item:GetDescendants()) do
				if part:IsA("BasePart") or part:IsA("Decal") then
					part.Transparency = part:GetAttribute("OrigTrans") or 0
					if part:IsA("BasePart") then
						local origShadow = part:GetAttribute("OrigShadow")
						if origShadow ~= nil then part.CastShadow = origShadow else part.CastShadow = true end
					end
				end
				if part:IsA("ParticleEmitter") or part:IsA("BillboardGui") or part:IsA("Beam") or part:IsA("Light") then
					part.Enabled = true
				end
			end
		end
	end
end

-- [[ LOOP ]] --
local function MonitorPlot(plot)
	local items = plot:WaitForChild("Items", 5)
	if not items then return end

	items.ChildAdded:Connect(function(child)
		local ownerVal = plot:FindFirstChild("Owner")
		if ownerVal and ownerVal.Value ~= player then
			task.wait()
			child:SetAttribute("IsHidden", true)
			for _, part in ipairs(child:GetDescendants()) do
				if part:IsA("BasePart") or part:IsA("Decal") then
					part:SetAttribute("OrigTrans", part.Transparency)
					if part:IsA("BasePart") then
						part:SetAttribute("OrigShadow", part.CastShadow)
						part.CastShadow = false
					end
					part.Transparency = 1
				end
				if part:IsA("ParticleEmitter") or part:IsA("BillboardGui") or part:IsA("Beam") or part:IsA("Light") then
					part.Enabled = false
				end
			end
		end
	end)
end

for _, plot in ipairs(TycoonMap:GetChildren()) do
	MonitorPlot(plot)
end

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		for _, plot in ipairs(TycoonMap:GetChildren()) do
			UpdatePlotVisibility(plot)
		end
	end
end)