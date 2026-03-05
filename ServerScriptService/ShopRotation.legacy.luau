-- [[ ServerScriptService/ShopRotator.server.luau ]] --

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ROTATION_TIME = 10 * 60 -- 10 Minutes
local ATTRIBUTE_NEXT = "Shop_NextRotation"

-- [[ PET POOLS ]] --
local ShopPetsFolder = ReplicatedStorage:WaitForChild("Pets"):WaitForChild("ShopPets")

local POOLS = {
	Slot1 = {}, -- 15x Pets
	Slot2 = {}, -- 25x Pets
	Slot3 = {}  -- 20x Pets
}

-- Dynamically group pets by multiplier
for _, pet in pairs(ShopPetsFolder:GetChildren()) do
	local multObj = pet:FindFirstChild("Multiplier1")
	if multObj then
		local mult = tonumber(multObj.Value)
		if mult == 15 then
			table.insert(POOLS.Slot1, pet.Name)
		elseif mult == 25 then
			table.insert(POOLS.Slot2, pet.Name)
		elseif mult == 20 then
			table.insert(POOLS.Slot3, pet.Name)
		end
	end
end

local function RotateShop()
	print("[ShopRotator] Rotating Shop Items...")

	-- Safety: Ensure pools are not empty
	if #POOLS.Slot1 > 0 then
		local p1 = POOLS.Slot1[math.random(1, #POOLS.Slot1)]
		ReplicatedStorage:SetAttribute("Shop_Pet1", p1)
	end

	if #POOLS.Slot2 > 0 then
		local p2 = POOLS.Slot2[math.random(1, #POOLS.Slot2)]
		ReplicatedStorage:SetAttribute("Shop_Pet2", p2)
	end

	if #POOLS.Slot3 > 0 then
		local p3 = POOLS.Slot3[math.random(1, #POOLS.Slot3)]
		ReplicatedStorage:SetAttribute("Shop_Pet3", p3)
	end

	-- Set Timer
	ReplicatedStorage:SetAttribute(ATTRIBUTE_NEXT, workspace:GetServerTimeNow() + ROTATION_TIME)
end

-- Initialize on Server Start
RotateShop()

-- Loop
task.spawn(function()
	while true do
		task.wait(1)
		local nextTime = ReplicatedStorage:GetAttribute(ATTRIBUTE_NEXT) or 0
		if workspace:GetServerTimeNow() >= nextTime then
			RotateShop()
		end
	end
end)