local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

-- [[ CONFIGURATION ]] --
local SAFE_DIAMETER = 32 
local MAX_HEIGHT = 35    
local PLATFORM_NAME = "BestCharacterPlatform"
local Y_OFFSET = 0
local DEVELOPER_ID = 9060798783

-- Reference to your item templates
local Brainrots = ReplicatedStorage:WaitForChild("Brainrots")
local TycoonMap = Workspace:WaitForChild("TycoonMap")

-- [[ HELPER: FIND PHYSICS PART ]] --
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

-- [[ HELPER: FIND PLAYER PLOT ]] --
local function FindPlayerPlot(player)
	for _, plot in pairs(TycoonMap:GetChildren()) do
		local ownerVal = plot:FindFirstChild("Owner")
		if ownerVal and ownerVal.Value == player then
			return plot
		end
	end
	return nil
end

-- [[ HELPER: DISPLAY ON PODIUM (With Safety Scaling) ]] --
local function DisplayOnPodium(plot, template)
	local platform = plot:FindFirstChild(PLATFORM_NAME)
	if not platform then return end

	-- 1. Cleanup old display
	local oldDisplay = platform:FindFirstChild("DisplayModel")
	if oldDisplay then oldDisplay:Destroy() end

	if not template then return end

	-- 2. Clone and Prepare
	local clone = template:Clone()
	clone.Name = "DisplayModel"

	for _, v in pairs(clone:GetDescendants()) do
		if v:IsA("BillboardGui") or v:IsA("Script") or v:IsA("LocalScript") or v:IsA("ModuleScript") then
			v:Destroy()
		elseif v:IsA("BasePart") then
			v.Anchored = true
			v.CanCollide = false
			v.Massless = true
			v.CastShadow = false
		end
	end

	-- 3. Scale Model
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

	-- 4. Calculate Position on Platform
	local currentCF, size = clone:GetBoundingBox()
	local platCF = platform.CFrame
	local platformTopY = platCF.Position.Y + (platform.Size.Y / 2)

	local finalY = platformTopY + (size.Y / 2) + Y_OFFSET
	local targetPos = Vector3.new(platCF.Position.X, finalY, platCF.Position.Z)

	clone:PivotTo(CFrame.new(targetPos) * currentCF.Rotation)
	CollectionService:AddTag(clone, "SpinningDisplay") 
	clone.Parent = platform
end

-- [[ COMMAND HANDLER ]] --
Players.PlayerAdded:Connect(function(plr)
	-- Only connect the commands if the player is the developer
	if plr.UserId == DEVELOPER_ID then
		plr.Chatted:Connect(function(msg)
			local args = msg:split(" ")

			-- 1. MONEY COMMAND
			if args[1] == "/money" and args[2] then
				local amount = tonumber(args[2])
				local ls = plr:FindFirstChild("leaderstats")
				if amount and ls and ls:FindFirstChild("Cash") then
					ls.Cash.Value = amount
					print(plr.Name .. " set cash to " .. amount)
				end
			end

			-- 2. GEMS COMMAND
			if args[1] == "/gems" and args[2] then
				local amount = tonumber(args[2])
				local ls = plr:FindFirstChild("leaderstats")
				if amount and ls and ls:FindFirstChild("Gems") then
					ls.Gems.Value = amount
					print(plr.Name .. " set gems to " .. amount)
				end
			end

			-- 3. FULL RESET COMMAND (COMPLETE WIPE)
			if args[1] == "/reset" then
				print(plr.Name .. " initiated a FULL RESET.")

				-- A. Reset Leaderstats
				local ls = plr:FindFirstChild("leaderstats")
				if ls then
					if ls:FindFirstChild("Cash") then ls.Cash.Value = 0 end
					if ls:FindFirstChild("Rebirths") then ls.Rebirths.Value = 0 end
					if ls:FindFirstChild("Gems") then ls.Gems.Value = 0 end
					if ls:FindFirstChild("HighestMerge") then ls.HighestMerge.Value = 1 end
				end

				-- B. Reset Values (Multipliers, Game Passes, Limits)
				local vals = plr:FindFirstChild("Values")
				if vals then
					if vals:FindFirstChild("Multiplier1") then vals.Multiplier1.Value = "1" end
					if vals:FindFirstChild("CashMultiplier") then vals.CashMultiplier.Value = 1 end
					if vals:FindFirstChild("GemsMultiplier") then vals.GemsMultiplier.Value = 1 end
					if vals:FindFirstChild("LuckMultiplier") then vals.LuckMultiplier.Value = 1 end
					if vals:FindFirstChild("MaxPetsStorage") then vals.MaxPetsStorage.Value = 10 end 
					if vals:FindFirstChild("MaxPetsEquipped") then vals.MaxPetsEquipped.Value = 3 end

					-- Reset Game Pass Booleans
					if vals:FindFirstChild("AutoMerge") then vals.AutoMerge.Value = false end
					if vals:FindFirstChild("UnlimitedMoney") then vals.UnlimitedMoney.Value = false end
					if vals:FindFirstChild("CanTripleHatch") then vals.CanTripleHatch.Value = false end
					if vals:FindFirstChild("CanAutoHatch") then vals.CanAutoHatch.Value = false end
				end

				-- C. Reset Upgrades
				local upgrades = plr:FindFirstChild("Upgrades")
				if upgrades then
					for _, v in pairs(upgrades:GetChildren()) do
						if v:IsA("IntValue") or v:IsA("NumberValue") then
							if v.Name == "Vacuum" then v.Value = 0 else v.Value = 1 end
						end
					end
				end

				-- D. Clear Pets Inventory
				local pets = plr:FindFirstChild("Pets")
				if pets then pets:ClearAllChildren() end

				-- E. Clear Plot Items
				local plot = FindPlayerPlot(plr)
				if plot and plot:FindFirstChild("Items") then
					plot.Items:ClearAllChildren()
				end

				print(plr.Name .. " has been fully reset.")
			end

			-- 4. SPAWN ALL COMMAND
			if args[1] == "/spawnall" then
				local plot = FindPlayerPlot(plr)

				if plot then
					local itemsFolder = plot:FindFirstChild("Items")
					local floor = plot:FindFirstChild("Floor")

					if itemsFolder and floor then
						local floorY = floor.Position.Y + (floor.Size.Y / 2)
						local spawnHeight = floorY + 5 
						local spacing = 5 
						local rowLength = 8 
						local index = 0

						local allItems = Brainrots:GetChildren()

						table.sort(allItems, function(a, b)
							local l1 = a:FindFirstChild("Level") and a.Level.Value or 0
							local l2 = b:FindFirstChild("Level") and b.Level.Value or 0
							return l1 < l2
						end)

						for _, template in ipairs(allItems) do
							local newItem = template:Clone()
							local row = math.floor(index / rowLength)
							local col = index % rowLength
							local offset = Vector3.new(col * spacing, 0, row * spacing)

							local startCorner = floor.Position + Vector3.new(-20, 0, -20)
							local spawnPos = startCorner + offset
							spawnPos = Vector3.new(spawnPos.X, spawnHeight, spawnPos.Z)

							local primary = GetPhysicsPart(newItem)

							if newItem:IsA("Model") then
								newItem:PivotTo(CFrame.new(spawnPos))
							elseif primary then
								primary.CFrame = CFrame.new(spawnPos)
							end

							newItem.Parent = itemsFolder

							for _, desc in pairs(newItem:GetDescendants()) do
								if desc:IsA("BasePart") then
									desc.CanCollide = true 
									desc.Anchored = false
									desc:SetNetworkOwner(plr)
								end
							end

							index = index + 1
							task.wait(0.05)
						end
						print("Spawned " .. index .. " items.")
					else
						warn("Plot missing Items folder or Floor.")
					end
				else
					warn("You must claim a plot first to use /spawnall")
				end
			end

			-- 5. SHOW ALL (PODIUM) COMMAND
			if args[1] == "/showall" then
				local plot = FindPlayerPlot(plr)

				if plot then
					local platform = plot:FindFirstChild(PLATFORM_NAME)

					if platform then
						print("Starting Podium Showcase Loop...")

						local allItems = Brainrots:GetChildren()
						table.sort(allItems, function(a, b)
							local l1 = a:FindFirstChild("Level") and a.Level.Value or 0
							local l2 = b:FindFirstChild("Level") and b.Level.Value or 0
							return l1 < l2
						end)

						task.spawn(function()
							for _, template in ipairs(allItems) do
								if not plr or not plr.Parent then break end
								local lvl = template:FindFirstChild("Level") and template.Level.Value or 0

								if lvl >= 1 and lvl <= 139 then
									DisplayOnPodium(plot, template)
									task.wait(0.5)
								end
							end
							print("Showcase complete.")
						end)
					else
						warn("Plot is missing the podium: " .. PLATFORM_NAME)
					end
				else
					warn("Claim a plot first!")
				end
			end

		end)
	end
end)