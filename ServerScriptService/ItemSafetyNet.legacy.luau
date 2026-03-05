local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- [[ CONFIGURATION ]]
local FALL_LIMIT = -50 -- If an item falls below this Y height, reset it
local RESET_HEIGHT = 5 -- How high to drop them when resetting

-- A safe place to check for items
local map = Workspace:WaitForChild("TycoonMap")

local function ResetItem(item, plot)
	-- Find a safe spot (The plot's center or the owner's spawn)
	local spawn = plot:FindFirstChild("Spawn") or plot:FindFirstChild("Floor")

	if spawn then
		local root = item:IsA("Model") and item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")

		if root then
			print("[SafetyNet] Catching falling item: " .. item.Name)

			-- 1. Stop the physics insanity
			root.AssemblyLinearVelocity = Vector3.new(0,0,0)
			root.AssemblyAngularVelocity = Vector3.new(0,0,0)

			-- 2. Teleport back to safety (Randomized offset to prevent physics explosions)
			local rx = math.random(-4, 4)
			local rz = math.random(-4, 4)
			local safePos = spawn.Position + Vector3.new(rx, RESET_HEIGHT, rz)

			if item:IsA("Model") then
				item:PivotTo(CFrame.new(safePos))
			else
				root.CFrame = CFrame.new(safePos)
			end
		end
	end
end

-- [[ MAIN LOOP ]]
-- We check every 1 seconds (Checking every frame is unnecessary lag)
task.spawn(function()
	while true do
		task.wait(1)

		if map then
			for _, plot in pairs(map:GetChildren()) do
				local itemsFolder = plot:FindFirstChild("Items")

				if itemsFolder then
					for _, item in pairs(itemsFolder:GetChildren()) do
						local root = item:IsA("Model") and item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")

						if root then
							-- CHECK: Is it falling into the void?
							if root.Position.Y < FALL_LIMIT then
								ResetItem(item, plot)
							end
						end
					end
				end
			end
		end
	end
end)