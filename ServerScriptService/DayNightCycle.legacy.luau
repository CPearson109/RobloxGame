local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TycoonMap = Workspace:WaitForChild("TycoonMap")

-- [[ TIME CONFIGURATION ]] --
local dayLengthMinutes = 4 
local hoursPerSecond = 24 / (dayLengthMinutes * 60)

local SUNRISE_TIME = 6.0  -- 6:00 AM 
local SUNSET_TIME  = 18.0 -- 6:00 PM 

local activeLights = {}
local isNightTime = false 

local function RegisterLight(light)
	if light:IsA("PointLight") or light:IsA("SurfaceLight") or light:IsA("SpotLight") then
		if not light:GetAttribute("OriginalBrightness") then
			light:SetAttribute("OriginalBrightness", light.Brightness)
		end
		light.Enabled = isNightTime
		table.insert(activeLights, light)
	end
end

for _, obj in ipairs(TycoonMap:GetDescendants()) do
	RegisterLight(obj)
end
TycoonMap.DescendantAdded:Connect(RegisterLight)

-- [[ UPDATE LOGIC (ONLY RUNS TWICE A DAY) ]] --
local function ToggleLights(turnOn)
	isNightTime = turnOn
	for i = #activeLights, 1, -1 do
		local light = activeLights[i]
		if light and light.Parent then
			light.Enabled = turnOn
			if turnOn then
				light.Brightness = light:GetAttribute("OriginalBrightness") or 1
			end
		else
			table.remove(activeLights, i)
		end
	end
end

-- [[ MAIN LOOP ]] --
RunService.Heartbeat:Connect(function(deltaTime)
	Lighting.ClockTime = Lighting.ClockTime + (hoursPerSecond * deltaTime)

	local time = Lighting.ClockTime

	if (time >= SUNSET_TIME or time < SUNRISE_TIME) and not isNightTime then
		ToggleLights(true)
	elseif (time >= SUNRISE_TIME and time < SUNSET_TIME) and isNightTime then
		ToggleLights(false)
	end
end)

-- Initial Sync
isNightTime = (Lighting.ClockTime >= SUNSET_TIME or Lighting.ClockTime < SUNRISE_TIME)
ToggleLights(isNightTime)