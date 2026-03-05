local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("TycoonRemotes")
local collectEvent = remotes:WaitForChild("CollectGem")
local map = Workspace:WaitForChild("TycoonMap")

-- [[ 1. CONFIGURATION ]] --
local MAX_NORMAL_GEMS = 3      -- Standard limit (very low CPU usage)
local MAX_STORM_GEMS = 150     -- Storm limit (high visual impact)

local GEM_LIFESPAN = 30        -- Gems disappear after 30 seconds
local NORMAL_RATE = 2.5        -- Spawn rate normal
local STORM_RATE = 0.05        -- Spawn rate storm

local FALL_SPEED = 30
local PICKUP_RADIUS = 3
local PICKUP_RADIUS_SQ = PICKUP_RADIUS * PICKUP_RADIUS 
local SPAWN_HEIGHT = 80
local HOVER_HEIGHT = 2
local BOUNCE_SPEED = 2
local SPIN_SPEED = 70

-- [[ SOUND ID ]] --
local COLLECT_SOUND_ID = "rbxassetid://4612375233"

-- [[ VISUALS ]] --
local GEM_ICON = "rbxassetid://122824029656207"

-- [[ STATE ]] --
local activeGems = {}
local lastSpawn = 0
local GemTemplate = ReplicatedStorage:WaitForChild("Gem"):WaitForChild("Gem")
local cachedPlot = nil 

-- [[ STORM STATE ]] --
local isStormActive = false
local stormEndTime = 0

-- [[ REMOTE SETUP ]] --
local startStormEvent = remotes:WaitForChild("StartGemStorm")
local spawnGemBurstEvent = remotes:WaitForChild("SpawnGemBurst")

startStormEvent.OnClientEvent:Connect(function(duration)
	isStormActive = true
	stormEndTime = os.clock() + duration

	local notification = Instance.new("Hint")
	notification.Text = "GEM STORM! RAIN INCOMING!"
	notification.Parent = Workspace
	Debris:AddItem(notification, 3)
end)

----------------------------------------------------------------------
-- HELPER: FLOAT TEXT
----------------------------------------------------------------------
local lastTextTime = 0
local function LocalFloatingText(text, pos, color)
	if os.clock() - lastTextTime < 0.05 then return end 
	lastTextTime = os.clock()

	local part = Instance.new("Part")
	part.Transparency = 1
	part.CanCollide = false
	part.Anchored = true
	part.CastShadow = false
	part.Position = pos + Vector3.new(0, 1, 0)
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 50)
	bb.AlwaysOnTop = true
	bb.Parent = part

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0
	tl.Font = Enum.Font.FredokaOne
	tl.TextSize = 24
	tl.Parent = bb

	local goal = { Position = part.Position + Vector3.new(0, 6, 0) }
	local tween = TweenService:Create(part, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween:Play()

	task.delay(0.6, function()
		if not tl.Parent then return end
		local tweenAlpha = TweenService:Create(tl, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
		tweenAlpha:Play()
		tweenAlpha.Completed:Connect(function() part:Destroy() end)
	end)
	Debris:AddItem(part, 1.5)
end

----------------------------------------------------------------------
-- HELPER: FLYING ICONS
----------------------------------------------------------------------
local function LocalFlyingIcon(startPos, targetFrameName, iconId)
	local cam = Workspace.CurrentCamera
	local screenPos, onScreen = cam:WorldToScreenPoint(startPos)
	if not onScreen then return end

	task.spawn(function()
		local pGui = player:WaitForChild("PlayerGui")

		local tycoonUI = pGui:WaitForChild("TycoonUI", 10) 
		if not tycoonUI then return end

		local targetFrame = tycoonUI:FindFirstChild(targetFrameName)
		if not targetFrame then return end
		local targetLabel = targetFrame:FindFirstChild("TextLabel") or targetFrame

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 50, 0, 50)
		icon.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
		icon.BackgroundTransparency = 1
		icon.Image = iconId or ""
		icon.ImageColor3 = Color3.new(1,1,1)
		icon.ZIndex = 10
		icon.Parent = tycoonUI

		local spread = UDim2.new(0, math.random(-60, 60), 0, math.random(-60, 60))
		local midPos = icon.Position + spread
		local tw1 = TweenService:Create(icon, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = midPos })
		tw1:Play()
		tw1.Completed:Wait()

		if not targetLabel.Parent then icon:Destroy() return end

		local absPos = targetLabel.AbsolutePosition
		local absSize = targetLabel.AbsoluteSize
		local targetUDim = UDim2.new(0, absPos.X + (absSize.X/2), 0, absPos.Y + (absSize.Y/2))
		local dist = (Vector2.new(midPos.X.Offset, midPos.Y.Offset) - Vector2.new(targetUDim.X.Offset, targetUDim.Y.Offset)).Magnitude
		local flyTime = math.clamp(dist / 2500, 0.3, 0.6)

		local tw2 = TweenService:Create(icon, TweenInfo.new(flyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), 
			{ Position = targetUDim, Size = UDim2.new(0, 0, 0, 0), ImageTransparency = 1 })
		tw2:Play()
		tw2.Completed:Connect(function() icon:Destroy() end)
	end)
end

----------------------------------------------------------------------
-- MAIN LOGIC
----------------------------------------------------------------------

local function GetMyPlot()
	if cachedPlot then return cachedPlot end
	for _, plot in pairs(map:GetChildren()) do
		local owner = plot:FindFirstChild("Owner")
		if owner and owner.Value == player then 
			cachedPlot = plot 
			return plot 
		end
	end
	return nil
end

local function SetupVisuals(gem)
	if gem:IsA("BasePart") then
		gem.Anchored = true
		gem.CanCollide = false
		gem.CastShadow = false
		-- Removed Blinding PointLight
	elseif gem:IsA("Model") then
		for _, v in pairs(gem:GetDescendants()) do
			if v:IsA("BasePart") then 
				v.Anchored = true
				v.CanCollide = false
				v.CastShadow = false
			end
		end
		-- Removed Blinding PointLight
	end
end

local function SpawnGem(spawnPos, floorY)
	local gemClone = GemTemplate:Clone()
	gemClone:PivotTo(CFrame.new(spawnPos))
	SetupVisuals(gemClone)
	gemClone.Parent = Workspace

	local isPart = gemClone:IsA("BasePart") 

	table.insert(activeGems, {
		Instance = gemClone,
		FloorY = floorY,
		State = "Falling",
		Rotation = math.random(0, 360),
		HoverStart = 0,
		IsPart = isPart,
		SpawnTime = os.clock() 
	})
end

-- [[ BURST GEMS PHYSICS SPANWER ]] --
spawnGemBurstEvent.OnClientEvent:Connect(function(centerPos, amount)
	local floorY = centerPos.Y - 2
	local myPlot = GetMyPlot()
	if myPlot and myPlot:FindFirstChild("Floor") then
		floorY = myPlot.Floor.Position.Y + (myPlot.Floor.Size.Y / 2)
	end

	for i = 1, amount do
		local gemClone = GemTemplate:Clone()
		gemClone:PivotTo(CFrame.new(centerPos))
		SetupVisuals(gemClone)
		gemClone.Parent = Workspace

		local isPart = gemClone:IsA("BasePart")

		local angle = (math.pi * 2 / amount) * i + (math.random(-20, 20)/100)
		local speed = math.random(15, 30)
		local vel = Vector3.new(math.cos(angle) * speed, math.random(40, 60), math.sin(angle) * speed)

		table.insert(activeGems, {
			Instance = gemClone,
			FloorY = floorY,
			State = "Bursting",
			Velocity = vel,
			Rotation = math.random(0, 360),
			HoverStart = 0,
			IsPart = isPart,
			SpawnTime = os.clock()
		})
	end
end)

-- [[ HEARTBEAT LOOP ]] --
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()

	-- 1. DETERMINE RATES AND LIMITS
	local currentRate = NORMAL_RATE
	local currentMax = MAX_NORMAL_GEMS 

	if isStormActive then
		if now < stormEndTime then
			currentRate = STORM_RATE
			currentMax = MAX_STORM_GEMS 
		else
			isStormActive = false
		end
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")

	-- 2. SPAWNING
	if now - lastSpawn > currentRate and #activeGems < currentMax then
		lastSpawn = now
		local myPlot = GetMyPlot()

		if myPlot and myPlot:FindFirstChild("Floor") then
			local floor = myPlot.Floor
			local size = floor.Size
			local pos = floor.Position
			local rX = math.random(-size.X/2 + 3, size.X/2 - 3)
			local rZ = math.random(-size.Z/2 + 3, size.Z/2 - 3)
			SpawnGem(Vector3.new(pos.X + rX, pos.Y + SPAWN_HEIGHT, pos.Z + rZ), pos.Y + (size.Y/2))
		end
	end

	-- 3. PHYSICS & INTERACTION
	local count = #activeGems
	for i = count, 1, -1 do
		local data = activeGems[i]
		local gem = data.Instance

		-- Cleanup
		if not gem.Parent or (now - data.SpawnTime > GEM_LIFESPAN) then 
			if gem.Parent then gem:Destroy() end
			activeGems[i] = activeGems[count]
			activeGems[count] = nil
			count = count - 1
			continue 
		end

		local currentPivot = gem:GetPivot() 
		local pos = currentPivot.Position

		-- A. Movement
		local newCFrame
		if data.State == "Falling" then
			local nextY = pos.Y - (FALL_SPEED * dt)
			local targetY = data.FloorY + HOVER_HEIGHT

			if nextY <= targetY then
				data.State = "Hovering"
				data.HoverStart = now
				nextY = targetY
			end

			data.Rotation = data.Rotation + (180 * dt)
			newCFrame = CFrame.new(pos.X, nextY, pos.Z) * CFrame.Angles(0, math.rad(data.Rotation), 0)

		elseif data.State == "Bursting" then
			data.Velocity = data.Velocity + Vector3.new(0, -90 * dt, 0) -- Gravity logic
			local nextPos = pos + (data.Velocity * dt)
			local targetY = data.FloorY + HOVER_HEIGHT

			if nextPos.Y <= targetY then
				data.State = "Hovering"
				data.HoverStart = now
				nextPos = Vector3.new(nextPos.X, targetY, nextPos.Z)
			end

			data.Rotation = data.Rotation + (SPIN_SPEED * 4 * dt)
			newCFrame = CFrame.new(nextPos) * CFrame.Angles(0, math.rad(data.Rotation), 0)

		elseif data.State == "Hovering" then
			local hoverTime = now - data.HoverStart
			local yOffset = math.sin(hoverTime * BOUNCE_SPEED) * 0.5
			local baseHeight = data.FloorY + HOVER_HEIGHT

			data.Rotation = data.Rotation + (SPIN_SPEED * dt)
			newCFrame = CFrame.new(pos.X, baseHeight + yOffset, pos.Z) * CFrame.Angles(0, math.rad(data.Rotation), 0)
		end

		if data.IsPart then
			gem.CFrame = newCFrame
		else
			gem:PivotTo(newCFrame)
		end

		-- B. Collection
		if root then
			local diff = root.Position - pos
			local distSq = diff:Dot(diff)

			if distSq < PICKUP_RADIUS_SQ then
				if head then
					local s = Instance.new("Sound")
					s.SoundId = COLLECT_SOUND_ID
					s.Volume = 0.8
					s.Parent = head
					s:Play()
					Debris:AddItem(s, 2)
				end

				LocalFloatingText("+1 Gem", pos, Color3.fromRGB(170, 0, 255))
				LocalFlyingIcon(pos, "GemsFrame", GEM_ICON) 

				collectEvent:FireServer()

				gem:Destroy()

				activeGems[i] = activeGems[count]
				activeGems[count] = nil
				count = count - 1
			end
		end
	end
end)