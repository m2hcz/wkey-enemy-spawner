local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("EnemySpawnerRemote")

local visualsFolder = workspace:FindFirstChild("ClientEnemies_" .. localPlayer.UserId)
if visualsFolder then
	visualsFolder:Destroy()
end

visualsFolder = Instance.new("Folder")
visualsFolder.Name = "ClientEnemies_" .. localPlayer.UserId
visualsFolder.Parent = workspace

local visuals = {}

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
end

local function clearVisuals()
	for _, visual in pairs(visuals) do
		visual.model:Destroy()
	end

	table.clear(visuals)
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
		for _, payload in ipairs(data.enemies or {}) do
			createVisual(payload)
		end
	elseif message == "Spawn" then
		createVisual(data)
	elseif message == "Snapshot" then
		applySnapshot(data)
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
