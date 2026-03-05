local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function UpdateBeam()
    local myPlotVal = player:FindFirstChild("MyPlot")
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not myPlotVal or not myPlotVal.Value or not root then return false end
    
    local plot = myPlotVal.Value
    local target = plot:FindFirstChild("Sign")
    local floor = plot:FindFirstChild("Floor") 
    
    if not target or not floor then return false end

    -- ZONE CHECK
    local relPos = floor.CFrame:PointToObjectSpace(root.Position)
    local halfSize = 45 
    local onPlot = (math.abs(relPos.X) < halfSize) and (math.abs(relPos.Z) < halfSize)

    if onPlot then
        if root:FindFirstChild("GuideBeam") then root.GuideBeam:Destroy() end
        script:Destroy()
        return true 
    end

    local beam = root:FindFirstChild("GuideBeam")
    if not beam then
        local att0 = Instance.new("Attachment", root)
        local att1 = target:FindFirstChild("TargetBeamAtt") or Instance.new("Attachment", target)
        att1.Name = "TargetBeamAtt"
        
        beam = Instance.new("Beam")
        beam.Name = "GuideBeam"
        beam.Attachment0 = att0
        beam.Attachment1 = att1
		beam.Texture = "rbxassetid://94691168967579"
        beam.TextureMode = Enum.TextureMode.Wrap
        beam.TextureLength = 3
        beam.TextureSpeed = 2
        beam.FaceCamera = true
        beam.Width0 = 2.5
        beam.Width1 = 2.5
        beam.Color = ColorSequence.new(Color3.fromRGB(0, 170, 255))
        beam.Parent = root
    end
    return false 
end

while task.wait(0.5) do if UpdateBeam() then break end end
