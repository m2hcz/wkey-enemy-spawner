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
local MIN_SPAWN_RATE = 0.25
local MAX_SPAWN_RATE = 20
local MIN_MAX_ENEMIES = 1
local MAX_MAX_ENEMIES = 250
local SIMULATION_HZ = 20
local SNAPSHOT_HZ = 10
local ACTION_DISTANCE = 4.5
local ACTION_COOLDOWN = 1.25
local POSITION_PRECISION = 100
local YAW_PRECISION = 1000

local REMOTE_RATE_LIMITS = {
	RequestSync = {
		capacity = 2,
		refillPerSecond = 0.5,
	},
	SetConfig = {
		capacity = 3,
		refillPerSecond = 1,
	},
	KillAll = {
		capacity = 1,
		refillPerSecond = 0.2,
	},
	EnemyClicked = {
		capacity = 8,
		refillPerSecond = 4,
	},
}

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
local simulationAccumulator = 0
local snapshotAccumulator = 0
local serverRng = Random.new()
local remoteBuckets = {}

local enemyMaterials = {
	Enum.Material.Plastic,
	Enum.Material.SmoothPlastic,
	Enum.Material.Neon,
	Enum.Material.Metal,
	Enum.Material.Glass,
	Enum.Material.ForceField,
}

local enemyColors = {
	Color3.fromRGB(255, 84, 84),
	Color3.fromRGB(255, 176, 72),
	Color3.fromRGB(73, 214, 155),
	Color3.fromRGB(85, 170, 255),
	Color3.fromRGB(178, 121, 255),
	Color3.fromRGB(255, 99, 185),
}

local function roundTo(value, precision)
	return math.round(value * precision) / precision
end

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function getRemoteBucket(player, message)
	local limit = REMOTE_RATE_LIMITS[message]
	if not limit then
		return nil, nil
	end

	local playerBuckets = remoteBuckets[player]
	if not playerBuckets then
		playerBuckets = {}
		remoteBuckets[player] = playerBuckets
	end

	local bucket = playerBuckets[message]
	if not bucket then
		bucket = {
			tokens = limit.capacity,
			updatedAt = os.clock(),
		}
		playerBuckets[message] = bucket
	end

	return bucket, limit
end

local function allowRemote(player, message)
	if type(message) ~= "string" then
		return false
	end

	local bucket, limit = getRemoteBucket(player, message)
	if not bucket then
		return false
	end

	local now = os.clock()
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.updatedAt = now
	bucket.tokens = math.min(limit.capacity, bucket.tokens + elapsed * limit.refillPerSecond)

	if bucket.tokens < 1 then
		return false
	end

	bucket.tokens -= 1
	return true
end

local function colorPayload(color)
	return {
		r = math.round(color.R * 255),
		g = math.round(color.G * 255),
		b = math.round(color.B * 255),
	}
end

local function randomPlatformPoint(rng, margin, y)
	return Vector3.new(
		rng:NextNumber(-HALF_X + margin, HALF_X - margin),
		y,
		rng:NextNumber(-HALF_Z + margin, HALF_Z - margin)
	)
end

local function clampEnemyPosition(position, radius)
	return Vector3.new(
		math.clamp(position.X, -HALF_X + radius, HALF_X - radius),
		PLATFORM_TOP_Y + radius,
		math.clamp(position.Z, -HALF_Z + radius, HALF_Z - radius)
	)
end

local function isOnPlatform(position)
	return position.X >= -HALF_X
		and position.X <= HALF_X
		and position.Z >= -HALF_Z
		and position.Z <= HALF_Z
		and position.Y >= PLATFORM_TOP_Y - 6
		and position.Y <= PLATFORM_TOP_Y + 18
end

local function flatDistanceSquared(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return dx * dx + dz * dz
end

local function getClosestPlayerOnPlatform(position)
	local closestPlayer = nil
	local closestRoot = nil
	local closestDistanceSquared = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if root and humanoid and humanoid.Health > 0 and isOnPlatform(root.Position) then
			local distanceSquared = flatDistanceSquared(position, root.Position)
			if distanceSquared < closestDistanceSquared then
				closestPlayer = player
				closestRoot = root
				closestDistanceSquared = distanceSquared
			end
		end
	end

	return closestPlayer, closestRoot, closestDistanceSquared
end

local function configPayload()
	return {
		spawnRate = roundTo(config.spawnRate, 100),
		maxEnemies = config.maxEnemies,
	}
end

local function spawnPayload(enemy)
	return {
		id = enemy.id,
		x = roundTo(enemy.position.X, POSITION_PRECISION),
		y = roundTo(enemy.position.Y, POSITION_PRECISION),
		z = roundTo(enemy.position.Z, POSITION_PRECISION),
		yaw = roundTo(enemy.yaw, YAW_PRECISION),
		scale = roundTo(enemy.scale, 100),
		radius = roundTo(enemy.radius, 100),
		speed = roundTo(enemy.speed, 100),
		material = enemy.material.Name,
		color = colorPayload(enemy.color),
	}
end

local function snapshotPayload()
	local snapshot = table.create(#enemyOrder)

	for index, id in ipairs(enemyOrder) do
		local enemy = enemies[id]
		if enemy then
			snapshot[index] = {
				id,
				roundTo(enemy.position.X, POSITION_PRECISION),
				roundTo(enemy.position.Z, POSITION_PRECISION),
				roundTo(enemy.yaw, YAW_PRECISION),
			}
		end
	end

	return snapshot
end

local function currentEnemyPayloads()
	local payloads = table.create(#enemyOrder)

	for index, id in ipairs(enemyOrder) do
		local enemy = enemies[id]
		if enemy then
			payloads[index] = spawnPayload(enemy)
		end
	end

	return payloads
end

local function spawnEnemy()
	if #enemyOrder >= config.maxEnemies then
		return
	end

	nextEnemyNumber += 1

	local seed = serverRng:NextInteger(1, 1000000000)
	local rng = Random.new(seed)
	local scale = rng:NextNumber(0.8, 1.35)
	local radius = scale
	local id = string.format("EN-%04d", nextEnemyNumber)
	local position = randomPlatformPoint(rng, radius + 0.5, PLATFORM_TOP_Y + radius)
	local yaw = rng:NextNumber(-math.pi, math.pi)
	local material = enemyMaterials[rng:NextInteger(1, #enemyMaterials)]
	local color = enemyColors[rng:NextInteger(1, #enemyColors)]

	local enemy = {
		id = id,
		seed = seed,
		position = position,
		yaw = yaw,
		scale = scale,
		radius = radius,
		speed = rng:NextNumber(7, 12),
		material = material,
		color = color,
		wanderGoal = randomPlatformPoint(rng, radius + 0.5, PLATFORM_TOP_Y + radius),
		nextWanderAt = os.clock() + rng:NextNumber(1.5, 4),
		lastActionAt = 0,
	}

	enemies[id] = enemy
	table.insert(enemyOrder, id)
	remote:FireAllClients("Spawn", spawnPayload(enemy))
end

local function clearEnemies(sourceName)
	if #enemyOrder == 0 then
		return
	end

	table.clear(enemies)
	table.clear(enemyOrder)
	remote:FireAllClients("Clear")
	print(string.format("[EnemySpawner] %s cleared all enemies.", sourceName))
end

local function updateEnemy(enemy, dt, now)
	local targetPlayer, targetRoot, targetDistanceSquared = getClosestPlayerOnPlatform(enemy.position)
	local targetPosition
	local speed = enemy.speed

	if targetRoot then
		targetPosition = Vector3.new(targetRoot.Position.X, enemy.position.Y, targetRoot.Position.Z)

		if targetDistanceSquared <= ACTION_DISTANCE * ACTION_DISTANCE and now - enemy.lastActionAt >= ACTION_COOLDOWN then
			enemy.lastActionAt = now
			print(string.format("[EnemySpawner] Enemy %s reached %s.", enemy.id, targetPlayer.Name))
			remote:FireAllClients("Action", {
				id = enemy.id,
				playerName = targetPlayer.Name,
			})
		end
	else
		if now >= enemy.nextWanderAt or flatDistanceSquared(enemy.position, enemy.wanderGoal) <= 2.25 then
			local rng = Random.new(enemy.seed + math.floor(now * 1000))
			enemy.wanderGoal = randomPlatformPoint(rng, enemy.radius + 0.5, PLATFORM_TOP_Y + enemy.radius)
			enemy.nextWanderAt = now + rng:NextNumber(1.5, 4)
		end

		targetPosition = enemy.wanderGoal
		speed = enemy.speed * 0.45
	end

	local delta = Vector3.new(targetPosition.X - enemy.position.X, 0, targetPosition.Z - enemy.position.Z)
	local distance = delta.Magnitude

	if distance > 0.05 then
		local direction = delta.Unit
		local stepDistance = math.min(distance, speed * dt)
		local nextPosition = enemy.position + direction * stepDistance
		enemy.position = clampEnemyPosition(nextPosition, enemy.radius)
		enemy.yaw = math.atan2(-direction.X, -direction.Z)
	end
end

local function updateEnemies(dt)
	local now = os.clock()

	for _, id in ipairs(enemyOrder) do
		local enemy = enemies[id]
		if enemy then
			updateEnemy(enemy, dt, now)
		end
	end
end

local function sendSnapshot()
	if #enemyOrder == 0 then
		return
	end

	remote:FireAllClients("Snapshot", snapshotPayload())
end

local function syncPlayer(player)
	remote:FireClient(player, "Sync", {
		config = configPayload(),
		platform = {
			sizeX = PLATFORM_SIZE.X,
			sizeZ = PLATFORM_SIZE.Z,
			topY = PLATFORM_TOP_Y,
		},
		enemies = currentEnemyPayloads(),
	})
end

local function setConfig(player, requestedConfig)
	if type(requestedConfig) ~= "table" then
		return
	end

	local changed = false

	if isFiniteNumber(requestedConfig.spawnRate) then
		local nextSpawnRate = math.clamp(requestedConfig.spawnRate, MIN_SPAWN_RATE, MAX_SPAWN_RATE)
		if nextSpawnRate ~= config.spawnRate then
			config.spawnRate = nextSpawnRate
			changed = true
		end
	end

	if isFiniteNumber(requestedConfig.maxEnemies) then
		local nextMaxEnemies = math.clamp(math.round(requestedConfig.maxEnemies), MIN_MAX_ENEMIES, MAX_MAX_ENEMIES)
		if nextMaxEnemies ~= config.maxEnemies then
			config.maxEnemies = nextMaxEnemies
			changed = true
		end
	end

	if not changed then
		return
	end

	remote:FireAllClients("Config", configPayload())
	print(string.format(
		"[EnemySpawner] %s set spawnRate=%.2f maxEnemies=%d.",
		player.Name,
		config.spawnRate,
		config.maxEnemies
	))
end

remote.OnServerEvent:Connect(function(player, message, data)
	if not allowRemote(player, message) then
		return
	end

	if message == "RequestSync" then
		syncPlayer(player)
	elseif message == "SetConfig" then
		setConfig(player, data)
	elseif message == "KillAll" then
		clearEnemies(player.Name)
	elseif message == "EnemyClicked"
		and type(data) == "string"
		and #data <= 16
		and string.match(data, "^EN%-%d+$")
		and enemies[data]
	then
		print(string.format("[EnemySpawner] %s clicked enemy %s.", player.Name, data))
	end
end)

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

Players.PlayerRemoving:Connect(function(player)
	remoteBuckets[player] = nil
end)

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

	simulationAccumulator += dt
	if simulationAccumulator >= 1 / SIMULATION_HZ then
		local step = simulationAccumulator
		simulationAccumulator = 0
		updateEnemies(step)
	end

	snapshotAccumulator += dt
	if snapshotAccumulator >= 1 / SNAPSHOT_HZ then
		snapshotAccumulator = 0
		sendSnapshot()
	end
end)
