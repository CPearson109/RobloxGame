local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local remotes = RS:WaitForChild("TycoonRemotes")

local collectEvent = remotes:FindFirstChild("CollectGem")
if not collectEvent then
	collectEvent = Instance.new("RemoteEvent")
	collectEvent.Name = "CollectGem"
	collectEvent.Parent = remotes
end

local MAX_BURST = 150
local REFILL_RATE = 2.5
local playerBuckets = {}

collectEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	local data = playerBuckets[player] or {Tokens = MAX_BURST, LastUpdate = now}

	local elapsed = now - data.LastUpdate
	data.Tokens = math.min(MAX_BURST, data.Tokens + (elapsed * REFILL_RATE))
	data.LastUpdate = now

	if data.Tokens >= 1 then
		data.Tokens -= 1
		playerBuckets[player] = data

		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local gems = ls:FindFirstChild("Gems")
			if gems then gems.Value += 1 end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerBuckets[player] = nil
end)