local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- [[ CONFIGURATION ]]
local BARRIER_MODEL_NAME = "TycoonBarriers"

local GROUP_WALLS = "TycoonBarriers"
local GROUP_PLAYER_HOLDING = "TycoonPlayersHolding"
local GROUP_PLAYER_NORMAL = "TycoonPlayers"

-----------------------------------------------------------------------
-- 1. SETUP PHYSICS RULES
-----------------------------------------------------------------------
local function SetupGroups()
	-- Create Groups (Safe wrap in case they exist)
	pcall(function() PhysicsService:RegisterCollisionGroup(GROUP_WALLS) end)
	pcall(function() PhysicsService:RegisterCollisionGroup(GROUP_PLAYER_HOLDING) end)
	pcall(function() PhysicsService:RegisterCollisionGroup(GROUP_PLAYER_NORMAL) end)

	-- Rule A: Normal Players walk THROUGH Walls
	PhysicsService:CollisionGroupSetCollidable(GROUP_WALLS, GROUP_PLAYER_NORMAL, false)

	-- Rule B: Holding Players HIT Walls
	PhysicsService:CollisionGroupSetCollidable(GROUP_WALLS, GROUP_PLAYER_HOLDING, true)

	-- Rule C: Items HIT Walls (Optional, keeps loose items inside)
	pcall(function() PhysicsService:RegisterCollisionGroup("TycoonItems") end)
	PhysicsService:CollisionGroupSetCollidable(GROUP_WALLS, "TycoonItems", true)
end

-----------------------------------------------------------------------
-- 2. FIX WALL PARTS (The Missing Step)
-----------------------------------------------------------------------
local function FixBarrierPart(part)
	if part:IsA("BasePart") then
		-- CRITICAL: Must be True for collision groups to work!
		part.CanCollide = true 
		part.Anchored = true
		part.Transparency = 1 -- Force invisible
		part.CollisionGroup = GROUP_WALLS
	end
end

local function ScanForBarriers()
	-- Search entire TycoonMap for the barrier models
	local map = Workspace:WaitForChild("TycoonMap", 5)
	if map then
		for _, plot in pairs(map:GetChildren()) do
			local barriers = plot:FindFirstChild(BARRIER_MODEL_NAME)
			if barriers then
				for _, part in pairs(barriers:GetDescendants()) do
					FixBarrierPart(part)
				end
				-- Listen for new parts added later
				barriers.DescendantAdded:Connect(FixBarrierPart)
			end
		end
	end
end

-----------------------------------------------------------------------
-- 3. HANDLE PLAYERS
-----------------------------------------------------------------------
local function SetCharGroup(char, groupName)
	for _, part in pairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

local function MonitorPlayer(player)
	player.CharacterAdded:Connect(function(char)
		-- 1. Default to Normal (Pass through walls)
		-- Wait a moment for character to load fully
		task.wait(0.2) 
		SetCharGroup(char, GROUP_PLAYER_NORMAL)

		-- 2. Watch for "IsHolding" changes
		player:GetAttributeChangedSignal("IsHolding"):Connect(function()
			if player:GetAttribute("IsHolding") then
				-- Player picked up item -> BLOCK THEM
				SetCharGroup(char, GROUP_PLAYER_HOLDING)
			else
				-- Player dropped item -> RELEASE THEM
				SetCharGroup(char, GROUP_PLAYER_NORMAL)
			end
		end)
	end)
end

-----------------------------------------------------------------------
-- STARTUP
-----------------------------------------------------------------------
SetupGroups()
ScanForBarriers() -- Fixes the walls immediately
for _, p in pairs(Players:GetPlayers()) do MonitorPlayer(p) end
Players.PlayerAdded:Connect(MonitorPlayer)

-- Extra check to keep finding walls if map loads late
Workspace.ChildAdded:Connect(function(c)
	if c.Name == "TycoonMap" then
		task.wait(1)
		ScanForBarriers()
	end
end)