--!native
--!optimize 2
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- [[ CONFIGURATION ]] --
local ITEMS_CONTAINER_NAME = "Items"
local RENDER_DISTANCE = 200 
local HIGH_DETAIL_DIST = 60 

-- [[ SETTINGS ]] --
local MIN_MOVEMENT = 0.08 
local MAX_MOVEMENT = 0.12 
local BASE_SPEED = 2.0 

-- [[ LISTS ]] --
local IGNORE_LIST = {
	"hand", "finger", "thumb", "palm", "fist", "grasp", "wrist",
	"foot", "feet", "toe", "heel", "ankle",
	"root", "humanoidrootpart", "hip", "lowerbody", "base", "main",
	"leg", "knee", "thigh", "calf", "shin"
}
local SPINE_LIST = {
	"head", "neck", "torso", "spine", "chest", "upperbody", "body", "waist"
}

-- [[ OPTIMIZATION CACHE ]] --
local math_sin = math.sin
local math_cos = math.cos
local math_clamp = math.clamp
local cf_angles = CFrame.Angles

-- [[ STATE ]] --
local ActiveMobs = {} 
local MobMap = {}     
local WatchedPlots = {} 
local Camera = Workspace.CurrentCamera

-- [[ REGISTRATION ]] --
local function registerMob(model)
	if not model or not model.Parent then return end
	if MobMap[model] then return end 

	local primaryPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
	if not primaryPart then return end

	local size = model:GetExtentsSize()
	local height = size.Y

	if height < 0.5 then return end 

	local speedMod = 1 / math.sqrt(math_clamp(height, 1, 10))
	local myAmp = MIN_MOVEMENT + (math.random() * (MAX_MOVEMENT - MIN_MOVEMENT))
	local timeOffset = math.random() * 100 

	local rootY = primaryPart.Position.Y
	local floorY = rootY - (height / 2)

	local boneData = {}
	local hasBones = false

	for _, bone in ipairs(model:GetDescendants()) do
		if bone:IsA("Bone") then
			local name = bone.Name:lower()

			local isIgnored = false
			for _, badName in ipairs(IGNORE_LIST) do
				if name:find(badName, 1, true) then isIgnored = true; break end
			end

			if not isIgnored then
				local isSpine = false
				for _, sName in ipairs(SPINE_LIST) do
					if name:find(sName, 1, true) then isSpine = true; break end
				end

				local currentBoneY = bone.WorldPosition.Y
				local distFromFloor = currentBoneY - floorY
				local dampener = math_clamp(distFromFloor / 3, 0, 1)

				if dampener > 0.05 then
					table.insert(boneData, {
						B = bone, 
						O = bone.Transform, 
						S = isSpine,
						D = dampener
					})
					hasBones = true
				end
			end
		end
	end

	if hasBones then
		local data = {
			Model = model,
			Root = primaryPart,
			Bones = boneData,
			Speed = BASE_SPEED * speedMod,
			Amp = myAmp,
			Off = timeOffset,
			LODGroup = math.random(1, 3) 
		}
		table.insert(ActiveMobs, data)
		MobMap[model] = data
	end
end

-- [[ THE HEARTBEAT LOOP ]] --
local frameCount = 0
local updateStep = 1 / 20
local timeAccumulator = 0

RunService.Heartbeat:Connect(function(deltaTime)
	timeAccumulator += deltaTime
	if timeAccumulator < updateStep then return end
	timeAccumulator = 0

	frameCount = frameCount + 1
	local now = time()
	local camPos = Camera.CFrame.Position

	local count = #ActiveMobs
	local i = 1

	while i <= count do
		local data = ActiveMobs[i]

		-- 1. CLEANUP
		if not data.Model.Parent or not data.Root.Parent then
			MobMap[data.Model] = nil

			ActiveMobs[i] = ActiveMobs[count]
			ActiveMobs[count] = nil
			count = count - 1
			continue 
		end

		-- 2. Distance Check
		local dist = (data.Root.Position - camPos).Magnitude

		-- 3. LOD THROTTLING
		local skip = false
		if dist > RENDER_DISTANCE then
			skip = true
		elseif dist > HIGH_DETAIL_DIST then
			if frameCount % 3 ~= data.LODGroup then
				skip = true
			end
		end

		if not skip then
			-- 4. Animation Math
			local t = (now * data.Speed) + data.Off
			
			local sineBase = math_sin(t) * data.Amp
			local cosineBase = math_cos(t) * data.Amp * 0.5

			for _, bData in ipairs(data.Bones) do
				local damp = bData.D
				local rx = sineBase * damp

				local rotation
				if bData.S then
					rotation = cf_angles(rx, 0, 0)
				else
					rotation = cf_angles(rx, 0, cosineBase * damp)
				end

				bData.B.Transform = bData.O * rotation
			end
		end

		i = i + 1
	end
end)

-- [[ SETUP ]] --
local function setupPlot(plotModel)
	if WatchedPlots[plotModel] then return end 

	local itemsFolder = plotModel:FindFirstChild(ITEMS_CONTAINER_NAME)
	if not itemsFolder then itemsFolder = plotModel:WaitForChild(ITEMS_CONTAINER_NAME, 5) end

	if itemsFolder then
		WatchedPlots[plotModel] = itemsFolder
	end
end

local function scanObject(obj)
	if obj:IsA("Model") and obj.Name:lower():find("plot") then
		task.spawn(function() setupPlot(obj) end)
	elseif obj:IsA("Folder") or obj.Name == "Map" or obj.Name == "Tycoons" then
		for _, child in ipairs(obj:GetChildren()) do scanObject(child) end
		obj.ChildAdded:Connect(scanObject)
	end
end

Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")
for _, child in ipairs(Workspace:GetChildren()) do scanObject(child) end
Workspace.ChildAdded:Connect(scanObject)

task.spawn(function()
	while true do
		task.wait(1)
		for plotModel, itemsFolder in pairs(WatchedPlots) do
			if plotModel.Parent and itemsFolder.Parent then
				for _, item in ipairs(itemsFolder:GetChildren()) do
					if not MobMap[item] then
						registerMob(item)
					end
				end
			else
				WatchedPlots[plotModel] = nil
			end
		end
	end
end)