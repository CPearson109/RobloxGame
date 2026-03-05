-- [[ BestCharacterDisplay.legacy.luau ]] --

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Brainrots = RS:WaitForChild("Brainrots")
local map = Workspace:WaitForChild("TycoonMap")

-- [[ CONFIGURATION ]] --
local SAFE_DIAMETER = 32 
local MAX_HEIGHT = 35    
local PLATFORM_NAME = "BestCharacterPlatform"
local Y_OFFSET = 0

-- Cache models for quick access
local BrainrotCache = {}
local function UpdateCache()
	table.clear(BrainrotCache)
	for _, model in pairs(Brainrots:GetChildren()) do
		local lvlObj = model:FindFirstChild("Level")
		if lvlObj and lvlObj:IsA("IntValue") then
			BrainrotCache[lvlObj.Value] = model
		end
	end
end
UpdateCache()
Brainrots.ChildAdded:Connect(UpdateCache)

local function GetPlot(player)
	for _, plot in pairs(map:GetChildren()) do
		local owner = plot:FindFirstChild("Owner")
		if owner and owner.Value == player then
			return plot
		end
	end
	return nil
end

local function UpdateDisplay(player, level)
	local plot = GetPlot(player)
	if not plot then return end

	local platform = plot:FindFirstChild(PLATFORM_NAME)
	if not platform then return end

	-- 1. Cleanup old display
	local oldDisplay = platform:FindFirstChild("DisplayModel")
	if oldDisplay then oldDisplay:Destroy() end

	-- 2. Get Template
	local template = BrainrotCache[level]
	if not template then return end

	-- 3. Clone and Prepare
	local clone = template:Clone()
	clone.Name = "DisplayModel"

	-- CLEANUP
	for _, v in pairs(clone:GetDescendants()) do
		if v:IsA("BillboardGui") or v:IsA("Script") or v:IsA("LocalScript") or v:IsA("ModuleScript") or v:IsA("ParticleEmitter") or v:IsA("Light") then
			v:Destroy()
		elseif v:IsA("BasePart") then
			v.Anchored = true
			v.CanCollide = false
			v.CanQuery = false 
			v.CanTouch = false 
			v.Massless = true
			v.CastShadow = false
		end
	end

	-- 4. Scale Model
	if clone:IsA("Model") then
		local currentCF, originalSize = clone:GetBoundingBox()

		if originalSize.Magnitude > 0.1 then
			local currentScaleAttribute = clone:GetScale()
			local modelDiagonal = math.sqrt(originalSize.X^2 + originalSize.Z^2)

			if modelDiagonal < 0.01 then modelDiagonal = 1 end
			if originalSize.Y < 0.01 then originalSize = Vector3.new(1,1,1) end

			local ratioDiameter = SAFE_DIAMETER / modelDiagonal
			local ratioHeight = MAX_HEIGHT / originalSize.Y
			local strictRatio = math.min(ratioDiameter, ratioHeight)

			clone:ScaleTo(currentScaleAttribute * strictRatio)
		end
	end

	-- 5. Calculate Position
	local currentCF, size = clone:GetBoundingBox()
	local platCF = platform.CFrame
	local platformTopY = platCF.Position.Y + (platform.Size.Y / 2)
	local finalY = platformTopY + (size.Y / 2) + Y_OFFSET
	local targetPos = Vector3.new(platCF.Position.X, finalY, platCF.Position.Z)

	clone:PivotTo(CFrame.new(targetPos) * currentCF.Rotation)

	-- 6. Tag for client-side spinning
	CollectionService:AddTag(clone, "SpinningDisplay") 
	clone.Parent = platform
end

local function SetupPlayer(player)
	local ls = player:WaitForChild("leaderstats", 60)
	if not ls then return end

	local highestMerge = ls:WaitForChild("HighestMerge", 30)
	if not highestMerge then return end

	local plot = nil
	while player.Parent and not plot do
		plot = GetPlot(player)
		if not plot then task.wait(0.5) end
	end

	if not plot then return end

	UpdateDisplay(player, highestMerge.Value)

	highestMerge.Changed:Connect(function()
		UpdateDisplay(player, highestMerge.Value)
	end)
end

Players.PlayerAdded:Connect(SetupPlayer)
for _, p in pairs(Players:GetPlayers()) do
	task.spawn(function() SetupPlayer(p) end)
end