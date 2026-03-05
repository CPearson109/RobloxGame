--!native
--!optimize 2
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("TycoonRemotes")
local assets = RS:WaitForChild("TycoonAssets")
local fxEvent = remotes:WaitForChild("PlayFX")

-- [[ ICONS ]] --
local CASH_ICON = "rbxassetid://120470884421987"
local LUCK_ICON = "rbxassetid://86706300638146"
local GEM_ICON  = "rbxassetid://122824029656207" 

-- [[ SOUND CONFIG ]] --
local MERGE_SOUND_ID = "rbxassetid://4612375233" 
local SELL_SOUND_ID  = "rbxassetid://201858045" 
local RARE_MERGE_SOUND_ID = "rbxassetid://100931270018375" 

-- [[ OPTIMIZATION CONFIG ]] --
local VISUAL_THROTTLE = 0.08 
local SOUND_THROTTLE = 0.05   

-- [[ CACHED TWEEN INFOS ]] --
local TWEEN_FLOAT_UP = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_TEXT_FADE = TweenInfo.new(0.4)
local TWEEN_ICON_BURST = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- State tracking
local lastVisualTime = 0
local lastSoundTime = 0
local rng = Random.new() 

-- Pitch Escalation State
local currentMergePitch = 1.0
local lastRealMergeTime = 0
local PITCH_TIMEOUT = 1.5 
local PITCH_INCREMENT = 0.05
local MAX_PITCH = 1.6

----------------------------------------------------------------------
-- Helper: Create Sound (Dynamic)
----------------------------------------------------------------------
local function PlayLocalSound(soundId, pitch)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = 0.5
	s.PlaybackSpeed = pitch or 1.0
	s.Parent = Workspace
	s:Play()
	Debris:AddItem(s, 2)
end

----------------------------------------------------------------------
-- Helper: Apply Random Gradient
----------------------------------------------------------------------
local function ApplyRandomGradient(textLabel)
	local gradients = {
		{Color3.fromRGB(255, 0, 127), Color3.fromRGB(255, 0, 0)},     -- Pink to Red
		{Color3.fromRGB(0, 255, 255), Color3.fromRGB(0, 85, 255)},    -- Cyan to Blue
		{Color3.fromRGB(85, 255, 127), Color3.fromRGB(0, 170, 0)},    -- Lime to Green
		{Color3.fromRGB(255, 255, 0), Color3.fromRGB(255, 170, 0)},   -- Yellow to Orange
		{Color3.fromRGB(170, 0, 255), Color3.fromRGB(85, 0, 200)},    -- Purple to Dark Purple
		{Color3.fromRGB(255, 85, 0), Color3.fromRGB(255, 0, 0)}       -- Orange to Red
	}
	local gradPair = gradients[math.random(1, #gradients)]
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, gradPair[1]), 
		ColorSequenceKeypoint.new(1, gradPair[2])    
	})
	gradient.Rotation = math.random(45, 135)
	gradient.Parent = textLabel
end

----------------------------------------------------------------------
-- Helper: Create 3D Floating Text
----------------------------------------------------------------------
local function FloatingText(text, pos, color, delayOffset, isMassive)
	if typeof(pos) ~= "Vector3" then return end

	local offset = Vector3.new(rng:NextNumber(-1,1), (delayOffset or 0), rng:NextNumber(-1,1))
	local attach = Instance.new("Attachment")
	attach.WorldPosition = pos + offset
	attach.Parent = Workspace.Terrain
	Debris:AddItem(attach, 2)

	local bb = Instance.new("BillboardGui")
	bb.Size = isMassive and UDim2.new(6, 0, 1.5, 0) or UDim2.new(3, 0, 1, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = attach 
	bb.Parent = player:WaitForChild("PlayerGui") 

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0
	tl.Font = Enum.Font.FredokaOne
	tl.TextScaled = true
	tl.Parent = bb

	if isMassive then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.new(0,0,0)
		stroke.Parent = tl
	end

	task.spawn(function()
		local tweenMove = TweenService:Create(attach, TWEEN_FLOAT_UP, {WorldPosition = attach.WorldPosition + Vector3.new(0, isMassive and 10 or 6, 0)})
		tweenMove:Play()

		task.wait(isMassive and 1.0 or 0.6)
		if not tl.Parent then return end

		local tweenAlpha = TweenService:Create(tl, TWEEN_TEXT_FADE, { TextTransparency = 1, TextStrokeTransparency = 1 })
		tweenAlpha:Play()
		tweenAlpha.Completed:Wait()

		bb:Destroy()
	end)
end

----------------------------------------------------------------------
-- Helper: Massive Combo Text Above Player
----------------------------------------------------------------------
local function SpawnComboText(comboMult)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end

	local attach = Instance.new("Attachment")
	attach.WorldPosition = head.Position + Vector3.new(0, 2.5, 0)
	attach.Parent = Workspace.Terrain
	Debris:AddItem(attach, 2.5)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(5, 0, 1.5, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = attach
	bb.Parent = player:WaitForChild("PlayerGui")

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.Text = "COMBO x" .. tostring(comboMult) .. "!"
	tl.TextColor3 = Color3.new(1, 1, 1) 
	tl.TextStrokeTransparency = 1
	tl.Font = Enum.Font.FredokaOne
	tl.TextScaled = true
	tl.Parent = bb

	ApplyRandomGradient(tl)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = tl

	tl.Rotation = rng:NextInteger(-15, 15)
	local popScale = 1.2 + math.clamp(comboMult * 0.05, 0, 0.8)
	local popTween = TweenService:Create(tl, TweenInfo.new(0.15, Enum.EasingStyle.Bounce), {Size = UDim2.new(popScale, 0, popScale, 0)})
	popTween:Play()

	task.spawn(function()
		local tweenMove = TweenService:Create(attach, TweenInfo.new(1.5), {WorldPosition = attach.WorldPosition + Vector3.new(0, 4, 0)})
		tweenMove:Play()

		task.wait(1)
		if not tl.Parent then return end

		local tweenAlpha = TweenService:Create(tl, TweenInfo.new(0.5), { TextTransparency = 1 })
		local strokeAlpha = TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 })
		tweenAlpha:Play()
		strokeAlpha:Play()
		tweenAlpha.Completed:Wait()
		bb:Destroy()
	end)
end

----------------------------------------------------------------------
-- Helper: Massive Lucky/Rare Merge Text Above Player
----------------------------------------------------------------------
local function SpawnSpecialText(text)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end

	local attach = Instance.new("Attachment")
	attach.WorldPosition = head.Position + Vector3.new(0, 4.0, 0)
	attach.Parent = Workspace.Terrain
	Debris:AddItem(attach, 2.5)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(6, 0, 2, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = attach
	bb.Parent = player:WaitForChild("PlayerGui")

	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.new(1, 0, 1, 0)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = Color3.new(1, 1, 1) 
	tl.TextStrokeTransparency = 1 
	tl.Font = Enum.Font.FredokaOne
	tl.TextScaled = true
	tl.Parent = bb

	ApplyRandomGradient(tl)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = tl

	tl.Rotation = rng:NextInteger(-15, 15)
	local popTween = TweenService:Create(tl, TweenInfo.new(0.15, Enum.EasingStyle.Bounce), {Size = UDim2.new(1.4, 0, 1.4, 0)})
	popTween:Play()

	task.spawn(function()
		local tweenMove = TweenService:Create(attach, TweenInfo.new(1.5), {WorldPosition = attach.WorldPosition + Vector3.new(0, 4, 0)})
		tweenMove:Play()

		task.wait(1)
		if not tl.Parent then return end

		local tweenAlpha = TweenService:Create(tl, TweenInfo.new(0.5), { TextTransparency = 1 })
		local strokeAlpha = TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 })
		tweenAlpha:Play()
		strokeAlpha:Play()
		tweenAlpha.Completed:Wait()
		bb:Destroy()
	end)
end

----------------------------------------------------------------------
-- Helper: Fly Icons to UI
----------------------------------------------------------------------
local function SpawnFlyingIcons(startPos, targetFrameName, iconId, color, countOverride)
	if typeof(startPos) ~= "Vector3" then return end

	local cam = Workspace.CurrentCamera
	local screenPos, onScreen = cam:WorldToScreenPoint(startPos)
	if not onScreen then return end

	local pGui = player:WaitForChild("PlayerGui")
	local tycoonUI = pGui:WaitForChild("TycoonUI")
	local targetFrame = tycoonUI:FindFirstChild(targetFrameName, true) 
	if not targetFrame then return end

	local loopCount = countOverride or 1

	task.spawn(function()
		local targetLabel = targetFrame:FindFirstChild("TextLabel") or targetFrame

		for i = 1, loopCount do
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0, 50, 0, 50) 
			icon.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
			icon.BackgroundTransparency = 1
			icon.Image = iconId or ""
			icon.ImageColor3 = color or Color3.new(1, 1, 1)
			icon.ZIndex = 10 
			icon.Parent = tycoonUI

			local spreadX = rng:NextInteger(-100, 100)
			local spreadY = rng:NextInteger(-100, 100)
			local midPos = icon.Position + UDim2.new(0, spreadX, 0, spreadY)

			local tw1 = TweenService:Create(icon, TWEEN_ICON_BURST, { Position = midPos })
			tw1:Play()

			tw1.Completed:Connect(function()
				if not targetLabel.Parent then icon:Destroy(); return end 

				local absPos = targetLabel.AbsolutePosition
				local absSize = targetLabel.AbsoluteSize
				local targetUDim = UDim2.new(0, absPos.X + (absSize.X / 2), 0, absPos.Y + (absSize.Y / 2))

				local dist = (Vector2.new(midPos.X.Offset, midPos.Y.Offset) - Vector2.new(targetUDim.X.Offset, targetUDim.Y.Offset)).Magnitude
				local flyTime = math.clamp(dist / 2500, 0.3, 0.6) 

				local tw2 = TweenService:Create(
					icon,
					TweenInfo.new(flyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = targetUDim, Size = UDim2.new(0, 0, 0, 0), ImageTransparency = 1 } 
				)
				tw2:Play()
				tw2.Completed:Connect(function()
					icon:Destroy()
				end)
			end)

			if loopCount > 1 then task.wait(0.05) end
		end
	end)
end

----------------------------------------------------------------------
-- FX EVENT HANDLER
----------------------------------------------------------------------
fxEvent.OnClientEvent:Connect(function(fxType, position, amounts)
	amounts = amounts or {}
	local now = os.clock()

	if (fxType == "Merge" or fxType == "Sell") and typeof(position) ~= "Vector3" then return end

	if now - lastVisualTime < VISUAL_THROTTLE then return end
	lastVisualTime = now

	if fxType == "Merge" then
		local isRare = amounts.RareTier and amounts.RareTier > 0

		if now - lastRealMergeTime < PITCH_TIMEOUT then
			currentMergePitch = math.clamp(currentMergePitch + PITCH_INCREMENT, 1.0, MAX_PITCH)
		else
			currentMergePitch = 1.0
		end
		lastRealMergeTime = now

		if amounts.Combo and amounts.Combo > 1 then
			SpawnComboText(amounts.Combo)
		end

		if amounts.IsLucky then
			SpawnSpecialText("LUCKY MERGE!")
		elseif isRare then
			SpawnSpecialText("RARE CONSUMED!")
		end

		if now - lastSoundTime > SOUND_THROTTLE then
			if isRare then
				PlayLocalSound(RARE_MERGE_SOUND_ID, 1.0)
			else
				PlayLocalSound(MERGE_SOUND_ID, currentMergePitch)
			end
			lastSoundTime = now
		end

		local attach = Instance.new("Attachment", Workspace.Terrain)
		attach.WorldPosition = position

		local p = assets.MergeFX:Clone()
		p.Parent = attach
		if isRare then
			for _, emitter in pairs(p:GetChildren()) do
				if emitter:IsA("ParticleEmitter") then
					emitter.Size = NumberSequence.new(emitter.Size.Keypoints[1].Value * 2) 
					emitter:Emit(30)
				end
			end
		else
			p:Emit(15) 
		end
		Debris:AddItem(attach, 1.5)

		-- 3. Visuals
		if amounts.Cash and amounts.Cash > 0 then
			FloatingText("+$" .. amounts.Formatted, position, Color3.fromRGB(85, 255, 127), 0, isRare)
			SpawnFlyingIcons(position, "CashFrame", CASH_ICON, Color3.new(1, 1, 1), isRare and 8 or 4) 
		end

		if amounts.Gems and amounts.Gems > 0 then
			FloatingText("+" .. amounts.Gems .. " Gems", position, Color3.fromRGB(170, 0, 255), 0.2, isRare)
			SpawnFlyingIcons(position, "GemsFrame", GEM_ICON, Color3.fromRGB(255, 255, 255), isRare and 6 or 1)
		elseif amounts.Cash > 0 then
			SpawnFlyingIcons(position, "GemsFrame", GEM_ICON, Color3.fromRGB(255, 255, 255), 1)
		end

		if amounts.Luck and amounts.Luck > 0 then
			FloatingText("+" .. amounts.Luck .. " Luck", position, Color3.fromRGB(170, 85, 255), 0.4, false)
			SpawnFlyingIcons(position, "LuckFrame", LUCK_ICON, Color3.fromRGB(255, 255, 255), 1)
		end

	elseif fxType == "Sell" then
		PlayLocalSound(SELL_SOUND_ID)

		local attach = Instance.new("Attachment", Workspace.Terrain)
		attach.WorldPosition = position

		local p = assets.SellFX:Clone()
		p.Parent = attach
		p:Emit(8)
		Debris:AddItem(attach, 1)

		if amounts.Cash and amounts.Cash > 0 then
			FloatingText("+$" .. amounts.Formatted, position, Color3.fromRGB(85, 255, 127), 0, false)
			SpawnFlyingIcons(position, "CashFrame", CASH_ICON, Color3.new(1, 1, 1), 3)
		end
	end
end)