local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local REMOTE_NAME = "EnemySpawnerRemote"
local PLATFORM_NAME = "EnemyPlatform"

local PLATFORM_SIZE = Vector3.new(50, 2, 50)
local PLATFORM_CFRAME = CFrame.new(0, 0, 0)
local PLATFORM_TOP_Y = PLATFORM_CFRAME.Position.Y + PLATFORM_SIZE.Y / 2
local HALF_X = PLATFORM_SIZE.X / 2
local HALF_Z = PLATFORM_SIZE.Z / 2

local DEFAULT_SPAWN_RATE = 1
local DEFAULT_MAX_ENEMIES = 20

local config = {
	spawnRate = DEFAULT_SPAWN_RATE,
	maxEnemies = DEFAULT_MAX_ENEMIES,
}

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

local arenaFolder = Workspace:FindFirstChild("EnemyArena")
if not arenaFolder then
	arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "EnemyArena"
	arenaFolder.Parent = Workspace
end

local platform = arenaFolder:FindFirstChild(PLATFORM_NAME)
if not platform then
	platform = Instance.new("Part")
	platform.Name = PLATFORM_NAME
	platform.Anchored = true
	platform.Size = PLATFORM_SIZE
	platform.CFrame = PLATFORM_CFRAME
	platform.Material = Enum.Material.Slate
	platform.Color = Color3.fromRGB(45, 52, 64)
	platform.TopSurface = Enum.SurfaceType.Smooth
	platform.BottomSurface = Enum.SurfaceType.Smooth
	platform.Parent = arenaFolder
end

local boundaryColor = Color3.fromRGB(79, 140, 255)
local boundarySpecs = {
	{ name = "NorthBoundary", size = Vector3.new(50, 0.25, 0.25), cframe = CFrame.new(0, PLATFORM_TOP_Y + 0.15, -HALF_Z) },
	{ name = "SouthBoundary", size = Vector3.new(50, 0.25, 0.25), cframe = CFrame.new(0, PLATFORM_TOP_Y + 0.15, HALF_Z) },
	{ name = "EastBoundary", size = Vector3.new(0.25, 0.25, 50), cframe = CFrame.new(HALF_X, PLATFORM_TOP_Y + 0.15, 0) },
	{ name = "WestBoundary", size = Vector3.new(0.25, 0.25, 50), cframe = CFrame.new(-HALF_X, PLATFORM_TOP_Y + 0.15, 0) },
}

for _, spec in ipairs(boundarySpecs) do
	local boundary = arenaFolder:FindFirstChild(spec.name)
	if not boundary then
		boundary = Instance.new("Part")
		boundary.Name = spec.name
		boundary.Anchored = true
		boundary.CanCollide = false
		boundary.Size = spec.size
		boundary.CFrame = spec.cframe
		boundary.Material = Enum.Material.Neon
		boundary.Color = boundaryColor
		boundary.Parent = arenaFolder
	end
end

local enemies = {}
local enemyOrder = {}
local nextEnemyNumber = 0
local spawnAccumulator = 0
local serverRng = Random.new()

local function randomPlatformPoint(rng, margin, y)
	return Vector3.new(
		rng:NextNumber(-HALF_X + margin, HALF_X - margin),
		y,
		rng:NextNumber(-HALF_Z + margin, HALF_Z - margin)
	)
end

local function spawnEnemy()
	if #enemyOrder >= config.maxEnemies then
		return
	end

	nextEnemyNumber += 1

	local id = string.format("EN-%04d", nextEnemyNumber)
	local position = randomPlatformPoint(serverRng, 1.5, PLATFORM_TOP_Y + 1)

	enemies[id] = {
		id = id,
		position = position,
	}

	table.insert(enemyOrder, id)
	remote:FireAllClients("Spawn", {
		id = id,
		x = position.X,
		y = position.Y,
		z = position.Z,
	})
end

local function connectPlayer(player)
	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root then
			root.CFrame = CFrame.new(0, PLATFORM_TOP_Y + 5, 0)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	connectPlayer(player)
end

Players.PlayerAdded:Connect(connectPlayer)

RunService.Heartbeat:Connect(function(dt)
	local spawnInterval = 1 / config.spawnRate

	spawnAccumulator += dt
	if #enemyOrder >= config.maxEnemies then
		spawnAccumulator = 0
	else
		while spawnAccumulator >= spawnInterval and #enemyOrder < config.maxEnemies do
			spawnAccumulator -= spawnInterval
			spawnEnemy()
		end
	end
end)
