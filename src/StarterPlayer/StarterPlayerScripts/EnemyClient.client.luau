local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("EnemySpawnerRemote")

local visualsFolder = workspace:FindFirstChild("ClientEnemies_" .. localPlayer.UserId)
if visualsFolder then
	visualsFolder:Destroy()
end

visualsFolder = Instance.new("Folder")
visualsFolder.Name = "ClientEnemies_" .. localPlayer.UserId
visualsFolder.Parent = workspace

local visuals = {}

local config = {
	spawnRate = 1,
	maxEnemies = 20,
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EnemySpawnerControls"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.fromOffset(16, 16)
panel.Size = UDim2.fromOffset(280, 184)
panel.BackgroundColor3 = Color3.fromRGB(24, 27, 33)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(85, 95, 120)
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 10)
title.Size = UDim2.fromOffset(252, 24)
title.Font = Enum.Font.GothamBold
title.Text = "Enemy Spawner"
title.TextColor3 = Color3.fromRGB(242, 245, 255)
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local countLabel = Instance.new("TextLabel")
countLabel.Name = "Count"
countLabel.BackgroundTransparency = 1
countLabel.Position = UDim2.fromOffset(14, 36)
countLabel.Size = UDim2.fromOffset(252, 20)
countLabel.Font = Enum.Font.Gotham
countLabel.Text = "0 active"
countLabel.TextColor3 = Color3.fromRGB(180, 188, 204)
countLabel.TextSize = 13
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = panel

local function makeLabel(text, y)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(14, y)
	label.Size = UDim2.fromOffset(112, 28)
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = Color3.fromRGB(224, 228, 238)
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = panel
	return label
end

local function makeButton(name, text, x, y, width, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromOffset(x, y)
	button.Size = UDim2.fromOffset(width, 28)
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 15
	button.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	return button
end

makeLabel("Spawn rate", 66)
makeLabel("Max enemies", 104)

local rateValue = Instance.new("TextLabel")
rateValue.BackgroundTransparency = 1
rateValue.Position = UDim2.fromOffset(154, 66)
rateValue.Size = UDim2.fromOffset(58, 28)
rateValue.Font = Enum.Font.GothamBold
rateValue.Text = "1.00/s"
rateValue.TextColor3 = Color3.fromRGB(242, 245, 255)
rateValue.TextSize = 14
rateValue.Parent = panel

local maxValue = Instance.new("TextLabel")
maxValue.BackgroundTransparency = 1
maxValue.Position = UDim2.fromOffset(154, 104)
maxValue.Size = UDim2.fromOffset(58, 28)
maxValue.Font = Enum.Font.GothamBold
maxValue.Text = "20"
maxValue.TextColor3 = Color3.fromRGB(242, 245, 255)
maxValue.TextSize = 14
maxValue.Parent = panel

local rateDown = makeButton("RateDown", "-", 124, 66, 28, Color3.fromRGB(58, 68, 88))
local rateUp = makeButton("RateUp", "+", 222, 66, 28, Color3.fromRGB(58, 68, 88))
local maxDown = makeButton("MaxDown", "-", 124, 104, 28, Color3.fromRGB(58, 68, 88))
local maxUp = makeButton("MaxUp", "+", 222, 104, 28, Color3.fromRGB(58, 68, 88))
local killAll = makeButton("KillAll", "Kill All", 14, 146, 236, Color3.fromRGB(201, 66, 66))

local function visualCount()
	local count = 0
	for _ in pairs(visuals) do
		count += 1
	end
	return count
end

local function updateHud()
	rateValue.Text = string.format("%.2f/s", config.spawnRate)
	maxValue.Text = tostring(config.maxEnemies)
	countLabel.Text = string.format("%d active", visualCount())
end

local function sendConfig(nextConfig)
	remote:FireServer("SetConfig", {
		spawnRate = nextConfig.spawnRate or config.spawnRate,
		maxEnemies = nextConfig.maxEnemies or config.maxEnemies,
	})
end

rateDown.MouseButton1Click:Connect(function()
	sendConfig({
		spawnRate = math.max(0.25, config.spawnRate - 0.25),
	})
end)

rateUp.MouseButton1Click:Connect(function()
	sendConfig({
		spawnRate = math.min(20, config.spawnRate + 0.25),
	})
end)

maxDown.MouseButton1Click:Connect(function()
	sendConfig({
		maxEnemies = math.max(1, config.maxEnemies - 5),
	})
end)

maxUp.MouseButton1Click:Connect(function()
	sendConfig({
		maxEnemies = math.min(250, config.maxEnemies + 5),
	})
end)

killAll.MouseButton1Click:Connect(function()
	remote:FireServer("KillAll")
end)

local function materialFromName(name)
	for _, material in ipairs(Enum.Material:GetEnumItems()) do
		if material.Name == name then
			return material
		end
	end

	return Enum.Material.Plastic
end

local function colorFromPayload(payload)
	if type(payload) ~= "table" then
		return Color3.fromRGB(255, 255, 255)
	end

	return Color3.fromRGB(payload.r or 255, payload.g or 255, payload.b or 255)
end

local function destroyVisual(id)
	local visual = visuals[id]
	if not visual then
		return
	end

	visual.model:Destroy()
	visuals[id] = nil
	updateHud()
end

local function clearVisuals()
	for _, visual in pairs(visuals) do
		visual.model:Destroy()
	end

	table.clear(visuals)
	updateHud()
end

local function createVisual(payload)
	if visuals[payload.id] then
		destroyVisual(payload.id)
	end

	local id = payload.id
	local scale = payload.scale or 1
	local baseColor = colorFromPayload(payload.color)
	local material = materialFromName(payload.material)
	local cframe = CFrame.new(payload.x, payload.y, payload.z) * CFrame.Angles(0, payload.yaw or 0, 0)

	local model = Instance.new("Model")
	model.Name = "Enemy_" .. id
	model:SetAttribute("EnemyId", id)
	model.Parent = visualsFolder

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(scale * 2, scale * 2, scale * 2)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = true
	body.Material = material
	body.Color = baseColor
	body:SetAttribute("EnemyId", id)
	body.Parent = model

	local eye = Instance.new("Part")
	eye.Name = "Eye"
	eye.Size = Vector3.new(scale * 0.45, scale * 0.45, scale * 0.28)
	eye.Anchored = true
	eye.CanCollide = false
	eye.CanQuery = true
	eye.Material = Enum.Material.SmoothPlastic
	eye.Color = Color3.fromRGB(248, 250, 255)
	eye:SetAttribute("EnemyId", id)
	eye.Parent = model

	local labelGui = Instance.new("BillboardGui")
	labelGui.Name = "IdLabel"
	labelGui.Adornee = body
	labelGui.AlwaysOnTop = true
	labelGui.Size = UDim2.fromOffset(90, 22)
	labelGui.StudsOffsetWorldSpace = Vector3.new(0, scale + 1.1, 0)
	labelGui.Parent = body

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = id
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 12
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.25
	label.Parent = labelGui

	model.PrimaryPart = body
	body.CFrame = cframe
	eye.CFrame = cframe * CFrame.new(0, 0, -scale)
	model:PivotTo(cframe)

	visuals[id] = {
		id = id,
		model = model,
		body = body,
		baseColor = baseColor,
		currentCFrame = cframe,
		targetCFrame = cframe,
		y = payload.y,
		actionUntil = 0,
	}

	updateHud()
end

local function applySnapshot(snapshot)
	for _, item in ipairs(snapshot) do
		local id = item[1]
		local x = item[2]
		local z = item[3]
		local yaw = item[4]
		local visual = visuals[id]

		if visual then
			visual.targetCFrame = CFrame.new(x, visual.y, z) * CFrame.Angles(0, yaw, 0)
		end
	end
end

local function applyConfig(nextConfig)
	if type(nextConfig) ~= "table" then
		return
	end

	config.spawnRate = nextConfig.spawnRate or config.spawnRate
	config.maxEnemies = nextConfig.maxEnemies or config.maxEnemies
	updateHud()
end

local function playAction(payload)
	local visual = payload and visuals[payload.id]
	if not visual then
		return
	end

	visual.actionUntil = os.clock() + 0.35
	print(string.format("[EnemyClient] Enemy %s acted near %s.", payload.id, payload.playerName or "a player"))
end

remote.OnClientEvent:Connect(function(message, data)
	if message == "Sync" then
		clearVisuals()
		applyConfig(data.config)
		for _, payload in ipairs(data.enemies or {}) do
			createVisual(payload)
		end
	elseif message == "Spawn" then
		createVisual(data)
	elseif message == "Snapshot" then
		applySnapshot(data)
	elseif message == "Config" then
		applyConfig(data)
	elseif message == "Action" then
		playAction(data)
	elseif message == "Clear" then
		clearVisuals()
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local alpha = 1 - math.exp(-dt * 18)
	local now = os.clock()

	for _, visual in pairs(visuals) do
		visual.currentCFrame = visual.currentCFrame:Lerp(visual.targetCFrame, alpha)
		visual.model:PivotTo(visual.currentCFrame)

		if now <= visual.actionUntil then
			visual.body.Color = Color3.fromRGB(255, 70, 70)
		else
			visual.body.Color = visual.baseColor
		end
	end
end)

remote:FireServer("RequestSync")
updateHud()
