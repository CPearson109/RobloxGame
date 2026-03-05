local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local camera = Workspace.CurrentCamera
local player = Players.LocalPlayer

-- [[ OPTIMIZATION CONFIG ]]
local SPIN_SPEED = 15 -- Degrees per second
local RENDER_DISTANCE = 150 -- Studs. Won't spin if further than this.
local UPDATE_THROTTLE = 0 -- Set to 2 to update every 2nd frame if still lagging (0 = smooth)

-- [[ STATE ]]
local spinners = {} -- Cache table to avoid calling GetTagged every frame

-- [[ FUNCTIONS ]]
local function OnSpinnerAdded(model)
	if model:IsA("Model") or model:IsA("BasePart") then
		spinners[model] = true
	end
end

local function OnSpinnerRemoved(model)
	spinners[model] = nil
end

-- [[ INITIALIZE ]]
-- 1. Grab existing ones
for _, model in ipairs(CollectionService:GetTagged("SpinningDisplay")) do
	OnSpinnerAdded(model)
end

-- 2. Listen for new ones (Performance: handled via events, not polling)
CollectionService:GetInstanceAddedSignal("SpinningDisplay"):Connect(OnSpinnerAdded)
CollectionService:GetInstanceRemovedSignal("SpinningDisplay"):Connect(OnSpinnerRemoved)

-- [[ LOOP ]]
local rad = math.rad
local frameCount = 0

RunService.RenderStepped:Connect(function(dt)
	-- Throttle check (Optional: skips frames for lower end devices)
	if UPDATE_THROTTLE > 0 then
		frameCount += 1
		if frameCount % UPDATE_THROTTLE ~= 0 then return end
		dt = dt * UPDATE_THROTTLE -- Compensate rotation for skipped frames
	end

	local rotationStep = rad(SPIN_SPEED * dt)
	local camPos = camera.CFrame.Position

	for model, _ in pairs(spinners) do
		if model.Parent then
			-- Get position efficiently
			local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")

			if primary then
				-- DISTANCE CULLING:
				-- If the player is too far, don't do the math. 
				-- This saves HUGE CPU usage on full servers.
				if (primary.Position - camPos).Magnitude < RENDER_DISTANCE then
					model:PivotTo(model:GetPivot() * CFrame.Angles(0, rotationStep, 0))
				end
			end
		else
			-- Cleanup if parent is lost but tag remains (Edge case)
			spinners[model] = nil
		end
	end
end)