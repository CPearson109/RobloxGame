local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("TycoonRemotes")
local throwEvent = remotes:WaitForChild("Throw")
local pickupEvent = remotes:WaitForChild("Pickup")
local mergeFunc = remotes:WaitForChild("TryMergeLocal") 

local Brainrots = RS:WaitForChild("Brainrots")
local map = Workspace:WaitForChild("TycoonMap")

local pickupSound = Instance.new("Sound")
pickupSound.SoundId = "rbxassetid://17481582653"
pickupSound.Volume = 0.2
pickupSound.Parent = SoundService

local throwSound = Instance.new("Sound")
throwSound.SoundId = "rbxassetid://139731037802687"
throwSound.Volume = 5.0 
throwSound.Parent = SoundService

local function PlayLocalSound(id, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = volume or 0.5
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 2)
end

local function HasNextLevel(currentLevel)
	for _, b in pairs(Brainrots:GetChildren()) do
		local l = b:FindFirstChild("Level")
		if l and l.Value == currentLevel + 1 then return true end
	end
	return false
end

local function IsMyItem(item)
	local myPlot = player:FindFirstChild("MyPlot")
	if myPlot and myPlot.Value then
		return item:IsDescendantOf(myPlot.Value)
	end
	return false
end

local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("InteractionUI")
local throwBtn = gui:WaitForChild("ThrowButton")
local qLabel = throwBtn:WaitForChild("Q")

qLabel.Visible = UserInputService.KeyboardEnabled

local function GetPhysicsPart(item)
	if not item then return nil end
	if item:IsA("Model") then
		if item.PrimaryPart then return item.PrimaryPart end
		return item:FindFirstChildWhichIsA("BasePart", true)
	elseif item:IsA("BasePart") then
		return item
	end
	return nil
end

local function ShakeCamera()
	local cam = Workspace.CurrentCamera
	local start = tick()
	local duration = 0.15 
	local intensity = 0.45

	task.spawn(function()
		while tick() - start < duration do
			local offset = Vector3.new(
				math.random(-1, 1) * intensity,
				math.random(-1, 1) * intensity,
				0
			)
			cam.CFrame = cam.CFrame * CFrame.new(offset * 0.1)
			RunService.RenderStepped:Wait()
		end
	end)
end

local function CreateBurstFX(pos)
	local att = Instance.new("Attachment", Workspace.Terrain)
	att.WorldPosition = pos

	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 10
	light.Color = Color3.fromRGB(255, 227, 114)
	light.Shadows = true
	light.Parent = att

	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(light, tweenInfo, {Brightness = 0, Range = 0})
	t:Play()
	t.Completed:Connect(function() t:Destroy() end) 

	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxassetid://1084969997" 

	local colors = {
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 50, 50)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 200, 0)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 255, 255)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(170, 0, 255)),
	}
	p.Color = ColorSequence.new(colors)
	p.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0)})
	p.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
	p.Lifetime = NumberRange.new(0.25, 0.5) 
	p.Speed = NumberRange.new(30, 45) 
	p.Drag = 8 
	p.SpreadAngle = Vector2.new(360, 360)
	p.Acceleration = Vector3.new(0, 10, 0)
	p.LightEmission = 1 
	p.Parent = att

	p:Emit(60) 
	game.Debris:AddItem(att, 1.5)
end

-- [[ OPTIMIZED SHRINK LOGIC ]]
local function Shrink(item)
	if not item then return end

	if item:IsA("Model") then
		local scaleVal = Instance.new("NumberValue")
		scaleVal.Value = item:GetScale()
		item:SetAttribute("OriginalScale", scaleVal.Value)

		-- Fix: Prevent falling through map while shrinking
		if item.PrimaryPart then item.PrimaryPart.Anchored = true end

		local t = TweenService:Create(scaleVal, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Value = 0.01})
		local conn
		conn = scaleVal.Changed:Connect(function(val)
			if item and item.Parent then item:ScaleTo(val) end
		end)
		t:Play()
		t.Completed:Connect(function() conn:Disconnect(); scaleVal:Destroy() end)
	elseif item:IsA("BasePart") then
		item:SetAttribute("OriginalSize", item.Size)
		item.CanCollide = false
		item.Anchored = true
		local t = TweenService:Create(item, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = Vector3.new(0.01, 0.01, 0.01), Transparency = 1})
		t:Play()
	end

	for _, p in pairs(item:GetDescendants()) do
		if p:IsA("BillboardGui") or p:IsA("SurfaceGui") or p:IsA("ScreenGui") then p.Enabled = false end
		if p:IsA("GuiObject") then p.Visible = false end
	end
end

local function RestoreItem(item)
	if not item or not item.Parent then return end
	item:SetAttribute("MergeCooldown", nil)
	if item:IsA("Model") then
		local origScale = item:GetAttribute("OriginalScale")
		if origScale then item:ScaleTo(origScale) end
	elseif item:IsA("BasePart") then
		local origSize = item:GetAttribute("OriginalSize")
		if origSize then item.Size = origSize end
		item.Transparency = 0
	end
	for _, p in pairs(item:GetDescendants()) do
		if p:IsA("BillboardGui") or p:IsA("SurfaceGui") or p:IsA("ScreenGui") then p.Enabled = true end
		if p:IsA("GuiObject") then p.Visible = true end
	end
end

local function ImplodeAndVanish(item1, item2)
	local p1 = GetPhysicsPart(item1)
	local p2 = GetPhysicsPart(item2)
	local burstPos = p2 and p2.Position or (p1 and p1.Position)

	if burstPos then CreateBurstFX(burstPos) end
	ShakeCamera()
	Shrink(item1)
	Shrink(item2)
end

-- OPTIMIZATION: Cache OverlapParams outside the loop
local thrownParams = OverlapParams.new()
thrownParams.FilterType = Enum.RaycastFilterType.Include
thrownParams.FilterDescendantsInstances = {map}

local function TrackThrownItem(item)
	if not item then return end
	local start = tick()
	local connection
	local timeAccumulator = 0

	connection = RunService.Heartbeat:Connect(function(dt)
		timeAccumulator += dt
		if timeAccumulator < 0.05 then return end -- 20 times a second
		timeAccumulator = 0

		if not item or not item.Parent or tick() - start > 2 then
			if connection then connection:Disconnect() end
			return
		end

		local root = GetPhysicsPart(item)
		if not root then return end
		local parts = Workspace:GetPartBoundsInRadius(root.Position, 5, thrownParams)

		for _, hit in ipairs(parts) do
			local other = hit.Parent
			if other and other ~= item then
				if not IsMyItem(other) then continue end 

				local l1 = item:FindFirstChild("Level")
				local l2 = other:FindFirstChild("Level")
				if l1 and l2 and l1.Value == l2.Value then
					if not HasNextLevel(l1.Value) then return end

					-- DEBOUNCE
					if item:GetAttribute("Merging") or other:GetAttribute("Merging") then return end
					item:SetAttribute("Merging", true)
					other:SetAttribute("Merging", true)

					if connection then connection:Disconnect() end

					ImplodeAndVanish(item, other)

					task.spawn(function()
						local success = mergeFunc:InvokeServer(item, other)
						if not success then
							item:SetAttribute("Merging", nil)
							other:SetAttribute("Merging", nil)
							RestoreItem(item)
							RestoreItem(other)
						end
					end)
					return
				end
			end
		end
	end)
end

-- OPTIMIZATION: Cache highlights so we don't have to scan the map
local activeHighlights = {}

local function ClearHighlights()
	for _, hl in ipairs(activeHighlights) do
		if hl then hl:Destroy() end
	end
	table.clear(activeHighlights)
end

local function HighlightMatchingItems(heldItem)
	ClearHighlights() 
	if not heldItem then return end

	local levelObj = heldItem:FindFirstChild("Level")
	if not levelObj then return end
	local targetLevel = levelObj.Value

	for _, plot in pairs(map:GetChildren()) do
		local ownerVal = plot:FindFirstChild("Owner")
		if ownerVal and ownerVal.Value == player then
			local itemsFolder = plot:FindFirstChild("Items")
			if itemsFolder then
				for _, item in pairs(itemsFolder:GetChildren()) do
					if item ~= heldItem then
						local l = item:FindFirstChild("Level")
						if l and l.Value == targetLevel then
							local hl = Instance.new("Highlight")
							hl.Name = "MergeHighlight"
							hl.Adornee = item
							hl.FillTransparency = 1 
							hl.OutlineColor = Color3.fromRGB(255, 255, 0)
							hl.OutlineTransparency = 0
							hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
							hl.Parent = item
							table.insert(activeHighlights, hl)
						end
					end
				end
			end
		end
	end
end

local function UpdateButton()
	task.wait(0.05) 
	local isHolding = player:GetAttribute("IsHolding")
	throwBtn.Visible = isHolding

	if isHolding then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local weld = root:FindFirstChild("CarryWeld")
			if weld and weld.Part1 then
				local p = weld.Part1
				local heldItem = nil
				if p.Parent and p.Parent:IsA("Model") then heldItem = p.Parent else heldItem = p end
				HighlightMatchingItems(heldItem)
				return
			end
		end
	end
	ClearHighlights()
end

local function ConnectWeldWatch(char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	root.ChildAdded:Connect(function(child) if child.Name == "CarryWeld" then UpdateButton() end end)
	root.ChildRemoved:Connect(function(child) if child.Name == "CarryWeld" then UpdateButton() end end)
end

player:GetAttributeChangedSignal("IsHolding"):Connect(UpdateButton)

if player.Character then ConnectWeldWatch(player.Character) end
player.CharacterAdded:Connect(ConnectWeldWatch)

task.wait(1) 
UpdateButton()

local function PerformThrow()
	local heldItem = nil
	local isHolding = player:GetAttribute("IsHolding")
	if isHolding then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local weld = root:FindFirstChild("CarryWeld")
			if weld and weld.Part1 then
				local p = weld.Part1
				if p.Parent and p.Parent:IsA("Model") then heldItem = p.Parent else heldItem = p end
			end
		end
	end
	throwSound:Play()
	throwEvent:FireServer(1.0)
	if heldItem then TrackThrownItem(heldItem) end
end

throwBtn.MouseButton1Click:Connect(PerformThrow)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.Q then
		if player:GetAttribute("IsHolding") then PerformThrow() end
	end
end)

local lastCheck = 0
local PICKUP_RANGE = 6 
local MERGE_RANGE = 6
local lastPickupAttempt = 0
local PICKUP_COOLDOWN = 0.3 

-- OPTIMIZATION: Cache OverlapParams outside the loop
local mainLoopParams = OverlapParams.new()
mainLoopParams.FilterType = Enum.RaycastFilterType.Include
mainLoopParams.FilterDescendantsInstances = {map}

RunService.Heartbeat:Connect(function(dt)
	lastCheck += dt
	if lastCheck < 0.05 then return end -- Locked strictly to 20 times a second
	lastCheck = 0

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local parts = Workspace:GetPartBoundsInRadius(root.Position, MERGE_RANGE, mainLoopParams)

	local isHolding = player:GetAttribute("IsHolding")
	local heldItem = nil

	if isHolding then
		local weld = root:FindFirstChild("CarryWeld")
		if weld and weld.Part1 then
			local p = weld.Part1
			if p.Parent and p.Parent:IsA("Model") then heldItem = p.Parent else heldItem = p end
		end
	end

	for _, hit in ipairs(parts) do
		local hitItem = hit.Parent
		local itemTarget = nil

		if hitItem and hitItem:FindFirstChild("Level") then itemTarget = hitItem
		elseif hit:FindFirstChild("Level") then itemTarget = hit end

		if not itemTarget then continue end
		if itemTarget:GetAttribute("MergeCooldown") then continue end
		if itemTarget.Name == "HostedItem" then continue end
		if not IsMyItem(itemTarget) then continue end 

		if heldItem and itemTarget ~= heldItem then
			local l1 = heldItem:FindFirstChild("Level")
			local l2 = itemTarget:FindFirstChild("Level")

			if l1 and l2 and l1.Value == l2.Value then
				if not HasNextLevel(l1.Value) then return end

				-- DEBOUNCE
				if heldItem:GetAttribute("Merging") or itemTarget:GetAttribute("Merging") then return end
				heldItem:SetAttribute("Merging", true)
				itemTarget:SetAttribute("Merging", true)

				heldItem:SetAttribute("MergeCooldown", true)
				itemTarget:SetAttribute("MergeCooldown", true)

				local weld = root:FindFirstChild("CarryWeld")
				if weld then weld:Destroy() end

				ImplodeAndVanish(heldItem, itemTarget)

				task.spawn(function()
					local success = mergeFunc:InvokeServer(heldItem, itemTarget)
					if not success then
						heldItem:SetAttribute("Merging", nil)
						itemTarget:SetAttribute("Merging", nil)
						RestoreItem(heldItem)
						RestoreItem(itemTarget)
					end
				end)
				return 
			end
		end

		if not isHolding then
			if (hit.Position - root.Position).Magnitude < PICKUP_RANGE then
				local physPart = GetPhysicsPart(itemTarget)
				if physPart and not physPart.Anchored and not itemTarget:GetAttribute("JustThrown") then
					if tick() - lastPickupAttempt > PICKUP_COOLDOWN then
						lastPickupAttempt = tick()
						pickupSound:Play() 
						pickupEvent:FireServer(hit)
					end
					return 
				end
			end
		end
	end
end)