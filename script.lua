local DropFolder = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Drop")
local CashierFolder = workspace:FindFirstChild("Cashiers")
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera

local lastATMCFrame = nil
local visited = {}
local MAX_DROP_DISTANCE = 50
local isPickingUp = false
local activeATM = nil
local activeATMPos = nil
-- Gate that prevents double-counting. Race condition: watchDropFolder ChildAdded fires
-- and counts the drop, then collectDropsAfterBreak finds the same drop still in workspace
-- (server hasn't removed it yet) and counts it again. This table stops that.
local pickedUpDrops = {}

local HEAVY_PUNCH_WINDUP = 0.5
local HEAVY_PUNCH_HOLD = 5
local HEAVY_PUNCH_COOLDOWN = 1
local KNIFE_WINDUP = 0.3
local KNIFE_HOLD = 5
local KNIFE_COOLDOWN = 0.5
local MAX_NO_DAMAGE_PUNCHES = 3
local OPEN_SIZE_TOLERANCE = 0.2
local OPEN_SIZE_AVAILABLE_Z = 0.09999994933605194
local ATM_RADIUS = 20
local RADIUS_SCAN_INTERVAL = 0.5

-- ══ HIDDEN FARM MODE CONSTANTS ══
local HF_RAYCAST_DIST   = 25     -- studs to raycast downward from wedge
local HF_HOVER_ABOVE    = -0.5    -- studs above found floor (lower = more underground)
local HF_MIN_DEPTH      = 2      -- wedge must be at least this far above hidden Y
local HF_CHAR_HEIGHT    = 5      -- approximate HRP-to-feet character height
local HF_BELOW_FLOOR    = 1.8    -- studs below floor surface when clipping in (no gap)
-- Groups where hidden mode failed this session — fall back to normal for these
local hiddenFailedGroups = {}
-- Clear failed groups each full loop so ATMs get re-evaluated after reset
local function clearHiddenFailed() hiddenFailedGroups = {} end

getgenv().ATM_RUNNING = false
getgenv().ATM_STARTED = false
getgenv().RADIUS_ENABLED = false
getgenv().FAST_BREAK = false
getgenv().HIDDEN_FARM = false

-- Set by key system before this script loads. trial = Free, 3day/weekly/monthly = Premium.
local IS_PREMIUM = getgenv and getgenv().IS_PREMIUM == true or false
local DISCORD_INVITE = "https://discord.gg/uCUSZeuM48"

local farmStart = nil
local totalElapsed = 0
local totalEarned = 0
local punchCount = 0
local atmCount = 0
local dropsCollected = 0
local atmsSkipped = 0
local currentAction = "Press Start to begin farming."

local SHOP_LOCATIONS = {
	["[Knife] - $169"]                  = CFrame.new(-277.649994, 18.8493271, -236.000046, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	["[RPG] - $22510"]                  = CFrame.new(113.624893, -29.6487064, -267.469269, -0.999999762, -0.000690576038, -8.63220048e-05, -0.000690576038, 0.999999762, -2.98059604e-08, 8.63220048e-05, 2.98059604e-08, -1),
	["5 [RPG Ammo] - $1126"]            = CFrame.new(118.66507, -29.6498013, -267.469788, -1, 0.000172614207, -8.63816167e-05, 0.000172673812, 0.999999762, -0.000690568588, 8.62623929e-05, -0.000690583489, -0.999999762),
	["[Flamethrower] - $10130"]         = CFrame.new(-157.122437, 50.9133568, -105.401451),
	["140 [Flamethrower Ammo] - $1126"] = CFrame.new(-157.122437, 50.9133568, -105.401451),
}

local function getHRP()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function getHum()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function formatTime(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then return string.format("%dh %dm %ds", h, m, s)
	elseif m > 0 then return string.format("%dm %ds", m, s)
	else return string.format("%ds", s) end
end

local function formatMoney(amount)
	if amount >= 1000000 then return string.format("$%.1fM", amount / 1000000)
	elseif amount >= 1000 then return string.format("$%.1fK", amount / 1000)
	else return string.format("$%d", amount) end
end

local function getDropValue(drop)
	local billboard = drop:FindFirstChildOfClass("BillboardGui")
	if not billboard then return 0 end
	-- GetDescendants searches the ENTIRE BillboardGui tree, not just direct children.
	-- This handles any nesting (BillboardGui > Frame > TextLabel, etc).
	-- Strip $, brackets, commas, spaces, and % signs, then grab the first number.
	for _, v in ipairs(billboard:GetDescendants()) do
		if v:IsA("TextLabel") and v.Text ~= "" then
			local clean = v.Text:gsub("[%$%[%]%+%%%s]", ""):gsub(",", ""):match("%d+")
			local val = tonumber(clean)
			if val and val > 0 then return val end
		end
	end
	return 0
end

local function getElapsed()
	if not getgenv().ATM_RUNNING or not farmStart then return totalElapsed end
	return totalElapsed + (os.time() - farmStart)
end

local function isCashierOpen(cashierGroup)
	local openPart = cashierGroup:FindFirstChild("Open")
	if openPart and openPart:IsA("BasePart") then
		return math.abs(openPart.Size.Z - OPEN_SIZE_AVAILABLE_Z) < OPEN_SIZE_TOLERANCE
	end
	local h = cashierGroup:FindFirstChildOfClass("Humanoid")
	if h then return h.Health > 0 end
	return false
end

local function findVaults()
	local vaults = {}
	for _, v in ipairs(workspace:GetDescendants()) do
		if v.Name == "VAULT" and v:IsA("Model") then table.insert(vaults, v) end
	end
	return vaults
end

local function isVaultOpen(vault)
	local h = vault:FindFirstChildOfClass("Humanoid")
	if h then return h.Health > 0 end
	local head = vault:FindFirstChild("Head")
	if head and head:FindFirstChild("HealthGui") then return true end
	return false
end

local function countWedges(cashierGroup)
	local count = 0
	for _, v in ipairs(cashierGroup:GetChildren()) do
		if v.Name == "Wedge" and v:IsA("BasePart") then count += 1 end
	end
	return count
end

local function getATMOffset(cashierGroup)
	if countWedges(cashierGroup) >= 2 then return CFrame.new(0, -4, 0.5)
	else return CFrame.new(0, 0, 0) end
end

local function getATMPosition(cashierGroup)
	local wedge = cashierGroup:FindFirstChild("Wedge")
	if wedge then return wedge.Position end
	local h = cashierGroup:FindFirstChild("Head")
	if h then return h.Position end
	return nil
end

-- ══ HIDDEN FARM POSITION CALCULATOR ══
-- Uses raycasting to find the real floor under the ATM/cashier,
-- then returns a CFrame that hides the player below the structure.
--
-- Strategy:
--   1. Raycast downward from the wedge, excluding the cashier group,
--      to find the floor surface beneath it.
--   2. Calculate gap height = wedge.Y - floor.Y
--   3. If gap >= character height: stand upright in the gap (fully hidden in the cavity)
--   4. If gap < character height but > 0: clip player slightly below the floor surface.
--      PlatformStand prevents physics from ejecting them.
--   5. If no floor found: use a fixed 6-stud drop below the wedge.
--   6. If the result would put the player too close to the wedge (< HF_MIN_DEPTH),
--      the ATM has no usable cavity → return nil (fall back to normal).
--
-- Returned CFrame is always upright (no rotation), so the character never flips.
local function findHiddenCFrame(cashierGroup, wedgeBlock)
	-- Skip groups that already failed this loop cycle
	if hiddenFailedGroups[cashierGroup] then return nil end

	local wedgePos = wedgeBlock.Position

	-- Raycast params: exclude the cashier structure so we hit the world floor, not the counter
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {cashierGroup}
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Cast from just below the wedge center downward
	local origin = Vector3.new(wedgePos.X, wedgePos.Y - 0.5, wedgePos.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -HF_RAYCAST_DIST, 0), params)

	local hiddenY
	if result then
		local floorY = result.Position.Y
		local gap    = wedgePos.Y - floorY

		if gap >= HF_CHAR_HEIGHT then
			-- Roomy cavity: stand with feet just above the floor
			hiddenY = floorY + HF_HOVER_ABOVE
		else
			-- Tight or no cavity: clip slightly below the floor surface
			-- PlatformStand will keep us here despite physics
			hiddenY = floorY - HF_BELOW_FLOOR
		end
	else
		-- No floor detected within range — drop a fixed amount
		hiddenY = wedgePos.Y - 8
	end

	-- Reject if the hidden Y is too close to the wedge (not hidden at all)
	if hiddenY >= wedgePos.Y - HF_MIN_DEPTH then
		return nil
	end

	-- Return a clean upright CFrame at the hidden position (same X/Z as wedge)
	return CFrame.new(wedgePos.X, hiddenY, wedgePos.Z)
end

local function snapshotDrops()
	local snapshot = {}
	if not DropFolder then return snapshot end
	for _, drop in ipairs(DropFolder:GetChildren()) do
		if drop.Name == "MoneyDrop" then snapshot[drop] = true end
	end
	return snapshot
end

local function safeTeleport(cframe)
	local hrp = getHRP()
	if not hrp then return end
	pcall(function() hrp.CFrame = cframe end)
end

local function pickupDrop(drop)
	if not drop or not drop.Parent then return end
	local hrp = getHRP()
	if not hrp then return end
	local dropValue = getDropValue(drop)
	local pos = drop:IsA("BasePart") and drop.Position or (drop.PrimaryPart and drop.PrimaryPart.Position)
	if not pos then return end
	pcall(function() hrp.CFrame = CFrame.new(pos) * CFrame.new(0, 2, 0) end)
	task.wait(0.03)
	if not drop.Parent then return end
	local cd = drop:FindFirstChildOfClass("ClickDetector")
	if cd then fireclickdetector(cd, 0, "MouseClick")
	else firetouchinterest(hrp, drop, true) task.wait(0.02) firetouchinterest(hrp, drop, false) end
	-- Guard is ONLY around the counter — collection itself runs every time (harmless duplicate
	-- clicks do nothing server-side), but totalEarned only increments once per drop.
	if not pickedUpDrops[drop] then
		pickedUpDrops[drop] = true
		if dropValue > 0 then totalEarned += dropValue end
		dropsCollected += 1
	end
end

local function getKnife()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("[Knife]") or player.Backpack:FindFirstChild("[Knife]")
end

local function hasKnife() return getKnife() ~= nil end

local function buyKnife()
	local hrp = getHRP()
	if not hrp then return false end
	currentAction = "Buying Knife..."
	pcall(function() hrp.CFrame = SHOP_LOCATIONS["[Knife] - $169"] end)
	task.wait(0.4)
	local shopFolder = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
	if not shopFolder then return false end
	local knifeItem = shopFolder:FindFirstChild("[Knife] - $169")
	if not knifeItem then return false end
	local cd = knifeItem:FindFirstChildOfClass("ClickDetector")
	if not cd then return false end
	fireclickdetector(cd, 0, "MouseClick")
	task.wait(0.5)
	return hasKnife()
end

local function ensureKnife()
	if hasKnife() then return true end
	return buyKnife()
end

local function knifeHeavySwing(atmHumanoid)
	if not getgenv().ATM_RUNNING then return false, 0 end
	local char = player.Character
	if not char then return false, 0 end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false, 0 end
	local knife = getKnife()
	if not knife then return false, 0 end
	local hpBefore = atmHumanoid and atmHumanoid.Health or 0
	hum:EquipTool(knife)
	task.wait(KNIFE_WINDUP)
	if not getgenv().ATM_RUNNING then return false, 0 end
	knife:Activate()
	task.wait(KNIFE_HOLD)
	task.wait(KNIFE_COOLDOWN)
	local hpAfter = atmHumanoid and atmHumanoid.Health or 0
	punchCount += 1
	return true, hpBefore - hpAfter
end

local radiusPaintSignal = nil
pcall(function()
	radiusPaintSignal = DrawingImmediate.GetPaint(1)
end)

local function drawCircleOnGround(center, radius, color, opacity, segments)
	if not DrawingImmediate then return end
	segments = segments or 32
	local points = {}
	for i = 0, segments - 1 do
		local angle = (i / segments) * math.pi * 2
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local screenPos, onScreen = Camera:WorldToViewportPoint(Vector3.new(x, center.Y, z))
		table.insert(points, {pos = Vector2.new(screenPos.X, screenPos.Y), onScreen = onScreen})
	end
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		if a.onScreen or b.onScreen then DrawingImmediate.Line(a.pos, b.pos, color, opacity, 1) end
	end
end

if radiusPaintSignal then
	radiusPaintSignal:Connect(function()
		if not getgenv().RADIUS_ENABLED then return end
		if not activeATM or not activeATMPos then return end
		local sc, onScreen = Camera:WorldToViewportPoint(activeATMPos)
		if not onScreen then return end
		drawCircleOnGround(activeATMPos, ATM_RADIUS, Color3.fromRGB(255, 255, 255), 1, 32)
		DrawingImmediate.Text(Vector2.new(sc.X - 30, sc.Y - 20), 0, 13, Color3.fromRGB(255, 255, 255), 1, activeATM.Name .. " | ACTIVE TARGET", false)
	end)
end

-- ══════════════════════════════════════
-- GUI
-- ══════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "ATMFarmer"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = gethui()

-- ══ LOADING SCREEN ══
-- Shown before main menu; fades out after LOAD_TIME seconds.
do
	local LOAD_TIME = 2.2

	local loadScreen = Instance.new("CanvasGroup")
	loadScreen.Size       = UDim2.new(0, 340, 0, 215)
	loadScreen.AnchorPoint= Vector2.new(0.5, 0.5)
	loadScreen.Position   = UDim2.new(0.5, 0, 0.5, 0)
	loadScreen.BackgroundColor3 = Color3.fromRGB(10, 10, 13)
	loadScreen.BorderSizePixel  = 0
	loadScreen.GroupTransparency= 1
	loadScreen.ZIndex     = 50
	loadScreen.Parent     = gui
	Instance.new("UICorner",   loadScreen).CornerRadius = UDim.new(0, 16)
	local lsStroke = Instance.new("UIStroke", loadScreen)
	lsStroke.Color = Color3.fromRGB(34, 197, 94)
	lsStroke.Thickness = 1.5

	-- Fade in immediately
	TweenService:Create(loadScreen, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {GroupTransparency = 0}):Play()

	-- Icon
	local lsIco = Instance.new("ImageLabel")
	lsIco.Size = UDim2.new(0, 36, 0, 36)
	lsIco.AnchorPoint = Vector2.new(0.5, 0)
	lsIco.Position = UDim2.new(0.5, 0, 0, 22)
	lsIco.BackgroundTransparency = 1
	lsIco.Image = "rbxassetid://82352293916728"
	lsIco.ScaleType = Enum.ScaleType.Fit
	lsIco.Parent = loadScreen

	-- Title
	local lsTitle = Instance.new("TextLabel")
	lsTitle.Size = UDim2.new(1, 0, 0, 26)
	lsTitle.Position = UDim2.new(0, 0, 0, 64)
	lsTitle.BackgroundTransparency = 1
	lsTitle.Text = "ATM Farmer"
	lsTitle.TextColor3 = Color3.fromRGB(235, 235, 245)
	lsTitle.TextSize = 20
	lsTitle.Font = Enum.Font.GothamBold
	lsTitle.TextXAlignment = Enum.TextXAlignment.Center
	lsTitle.Parent = loadScreen

	-- Subtitle / version
	local lsVer = Instance.new("TextLabel")
	lsVer.Size = UDim2.new(1, 0, 0, 14)
	lsVer.Position = UDim2.new(0, 0, 0, 90)
	lsVer.BackgroundTransparency = 1
	lsVer.Text = "v1.0.0  •  by Loganbacon28"
	lsVer.TextColor3 = Color3.fromRGB(55, 55, 72)
	lsVer.TextSize = 10
	lsVer.Font = Enum.Font.Gotham
	lsVer.TextXAlignment = Enum.TextXAlignment.Center
	lsVer.Parent = loadScreen

	-- Spinner ring: 8 dots arranged in a circle
	local spinContainer = Instance.new("Frame")
	spinContainer.Size = UDim2.new(0, 40, 0, 40)
	spinContainer.AnchorPoint = Vector2.new(0.5, 0)
	spinContainer.Position = UDim2.new(0.5, 0, 0, 112)
	spinContainer.BackgroundTransparency = 1
	spinContainer.Parent = loadScreen

	local NUM_DOTS = 8
	local spinDots = {}
	for i = 1, NUM_DOTS do
		local angle = ((i - 1) / NUM_DOTS) * math.pi * 2
		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, 6, 0, 6)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.new(0.5, math.cos(angle) * 15, 0.5, math.sin(angle) * 15)
		dot.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
		dot.BackgroundTransparency = 1 - (i / NUM_DOTS)
		dot.BorderSizePixel = 0
		dot.Parent = spinContainer
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		spinDots[i] = dot
	end

	-- Progress bar background
	local pbBg = Instance.new("Frame")
	pbBg.Size = UDim2.new(0, 270, 0, 4)
	pbBg.AnchorPoint = Vector2.new(0.5, 0)
	pbBg.Position = UDim2.new(0.5, 0, 0, 162)
	pbBg.BackgroundColor3 = Color3.fromRGB(26, 26, 34)
	pbBg.BorderSizePixel = 0
	pbBg.Parent = loadScreen
	Instance.new("UICorner", pbBg).CornerRadius = UDim.new(0, 2)

	-- Progress fill
	local pbFill = Instance.new("Frame")
	pbFill.Size = UDim2.new(0, 0, 1, 0)
	pbFill.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
	pbFill.BorderSizePixel = 0
	pbFill.Parent = pbBg
	Instance.new("UICorner", pbFill).CornerRadius = UDim.new(0, 2)

	-- Status text (cycles through messages)
	local lsStatus = Instance.new("TextLabel")
	lsStatus.Size = UDim2.new(1, 0, 0, 14)
	lsStatus.Position = UDim2.new(0, 0, 0, 175)
	lsStatus.BackgroundTransparency = 1
	lsStatus.Text = "Initializing systems..."
	lsStatus.TextColor3 = Color3.fromRGB(55, 55, 72)
	lsStatus.TextSize = 10
	lsStatus.Font = Enum.Font.Gotham
	lsStatus.TextXAlignment = Enum.TextXAlignment.Center
	lsStatus.Parent = loadScreen

	-- Percentage text
	local lsPct = Instance.new("TextLabel")
	lsPct.Size = UDim2.new(1, 0, 0, 14)
	lsPct.Position = UDim2.new(0, 0, 0, 193)
	lsPct.BackgroundTransparency = 1
	lsPct.Text = "0%"
	lsPct.TextColor3 = Color3.fromRGB(34, 197, 94)
	lsPct.TextSize = 10
	lsPct.Font = Enum.Font.GothamBold
	lsPct.TextXAlignment = Enum.TextXAlignment.Center
	lsPct.Parent = loadScreen

	-- Animate the loading screen
	local LOAD_MSGS = {
		{t = 0.00, msg = "Initializing systems..."},
		{t = 0.20, msg = "Loading interface..."},
		{t = 0.42, msg = "Fetching player data..."},
		{t = 0.64, msg = "Connecting to server..."},
		{t = 0.82, msg = "Verifying license..."},
		{t = 0.95, msg = "Almost ready..."},
	}

	-- Animate progress bar smoothly
	TweenService:Create(pbFill,
		TweenInfo.new(LOAD_TIME - 0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
		{Size = UDim2.new(1, 0, 1, 0)}):Play()

	task.spawn(function()
		local startTime = tick()
		local spinOffset = 0
		local msgIdx = 0

		while tick() - startTime < LOAD_TIME do
			local elapsed  = tick() - startTime
			local progress = math.clamp(elapsed / LOAD_TIME, 0, 1)

			-- Spin dots
			spinOffset = (spinOffset + 0.18) % NUM_DOTS
			for i = 1, NUM_DOTS do
				local t = ((i - 1 - spinOffset) % NUM_DOTS) / NUM_DOTS
				spinDots[i].BackgroundTransparency = t * 0.9
			end

			-- Update percentage
			lsPct.Text = math.floor(progress * 100) .. "%"

			-- Cycle messages
			for mi, entry in ipairs(LOAD_MSGS) do
				if progress >= entry.t and mi > msgIdx then
					msgIdx = mi
					lsStatus.Text = entry.msg
					-- Quick fade-in for message
					lsStatus.TextTransparency = 0.8
					TweenService:Create(lsStatus, TweenInfo.new(0.2), {TextTransparency = 0}):Play()
				end
			end

			task.wait(0.05)
		end

		-- Final state: 100% + welcome message
		lsPct.Text    = "100%"
		lsStatus.Text = "Welcome, " .. player.DisplayName .. "!"
		TweenService:Create(lsStatus, TweenInfo.new(0.2), {TextColor3 = Color3.fromRGB(34, 197, 94)}):Play()

		task.wait(0.55)

		-- Fade out loading screen — menu slides in simultaneously
		TweenService:Create(loadScreen, TweenInfo.new(0.45, Enum.EasingStyle.Quint), {GroupTransparency = 1}):Play()
		task.wait(0.5)
		loadScreen:Destroy()
	end)
end -- end loading screen scope

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 390, 0, 700)
main.Position = UDim2.new(0, 12, 0.5, -325)  -- starts 25px below, slides up as loading fades
main.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
do local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Color3.fromRGB(32, 32, 38)
mainStroke.Thickness = 1 end
-- Slide up to final position as loading screen fades (~2.75s)
task.delay(2.75, function()
	TweenService:Create(main, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{Position = UDim2.new(0, 12, 0.5, -350)}):Play()
end)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = Color3.fromRGB(16, 16, 19)
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
local hfix = Instance.new("Frame")
hfix.Size = UDim2.new(1, 0, 0.5, 0)
hfix.Position = UDim2.new(0, 0, 0.5, 0)
hfix.BackgroundColor3 = Color3.fromRGB(16, 16, 19)
hfix.BorderSizePixel = 0
hfix.Parent = header

local iconLbl = Instance.new("ImageLabel")
iconLbl.Size = UDim2.new(0, 26, 0, 26)
iconLbl.Position = UDim2.new(0, 12, 0.5, -13)
iconLbl.BackgroundTransparency = 1
iconLbl.Image = "rbxassetid://82352293916728"
iconLbl.ScaleType = Enum.ScaleType.Fit
iconLbl.Parent = header

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, -150, 1, 0)
headerTitle.Position = UDim2.new(0, 46, 0, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Text = "ATM Farmer"
headerTitle.TextColor3 = Color3.fromRGB(235, 235, 240)
headerTitle.TextSize = 15
headerTitle.Font = Enum.Font.GothamBold
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.TextYAlignment = Enum.TextYAlignment.Center
headerTitle.Parent = header

local shopOpenBtn = Instance.new("TextButton")
shopOpenBtn.Size = UDim2.new(0, 68, 0, 26)
shopOpenBtn.Position = UDim2.new(1, -106, 0.5, -13)
shopOpenBtn.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
shopOpenBtn.Text = "   Shop"
shopOpenBtn.TextColor3 = Color3.fromRGB(140, 140, 158)
shopOpenBtn.TextSize = 11
shopOpenBtn.Font = Enum.Font.GothamBold
shopOpenBtn.BorderSizePixel = 0
shopOpenBtn.Parent = header
Instance.new("UICorner", shopOpenBtn).CornerRadius = UDim.new(0, 7)
Instance.new("UIStroke", shopOpenBtn).Color = Color3.fromRGB(34, 34, 44)
local shopBtnIcon = Instance.new("ImageLabel")
shopBtnIcon.Size = UDim2.new(0, 12, 0, 12)
shopBtnIcon.Position = UDim2.new(0, 9, 0.5, -6)
shopBtnIcon.BackgroundTransparency = 1
shopBtnIcon.Image = "rbxassetid://127805931579487"
shopBtnIcon.ImageColor3 = Color3.fromRGB(130, 130, 148)
shopBtnIcon.ScaleType = Enum.ScaleType.Fit
shopBtnIcon.Parent = shopOpenBtn

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.Position = UDim2.new(1, -36, 0.5, -13)
closeBtn.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
closeBtn.Text = "x"
closeBtn.TextColor3 = Color3.fromRGB(148, 148, 162)
closeBtn.TextSize = 12
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 7)
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(34, 34, 44)
closeBtn.MouseButton1Click:Connect(function()
	getgenv().ATM_RUNNING = false getgenv().ATM_STARTED = false
	getgenv().RADIUS_ENABLED = false getgenv().FAST_BREAK = false getgenv().HIDDEN_FARM = false
	local h = getHum() if h then h.PlatformStand = false end
	gui:Destroy()
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -52)
scroll.Position = UDim2.new(0, 0, 0, 52)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 2
scroll.ScrollBarImageColor3 = Color3.fromRGB(40, 40, 50)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = main

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 8)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scroll

local scrollPad = Instance.new("UIPadding")
scrollPad.PaddingTop = UDim.new(0, 10) scrollPad.PaddingBottom = UDim.new(0, 12)
scrollPad.PaddingLeft = UDim.new(0, 10) scrollPad.PaddingRight = UDim.new(0, 10)
scrollPad.Parent = scroll

local function makeCard(order)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 0) card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = Color3.fromRGB(19, 19, 23) card.BorderSizePixel = 0
	card.LayoutOrder = order card.Parent = scroll
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
	local cs = Instance.new("UIStroke", card) cs.Color = Color3.fromRGB(30, 30, 37) cs.Thickness = 1
	Instance.new("UIListLayout", card).SortOrder = Enum.SortOrder.LayoutOrder
	local cp = Instance.new("UIPadding", card)
	cp.PaddingTop = UDim.new(0, 11) cp.PaddingBottom = UDim.new(0, 11)
	cp.PaddingLeft = UDim.new(0, 13) cp.PaddingRight = UDim.new(0, 13)
	return card
end

local function makeCardHeader(parent, order, icon, title, iconIsImage)
	local row = Instance.new("Frame") row.Size = UDim2.new(1, 0, 0, 18) row.BackgroundTransparency = 1 row.LayoutOrder = order row.Parent = parent
	if iconIsImage then
		local img = Instance.new("ImageLabel") img.Size = UDim2.new(0, 14, 0, 14) img.Position = UDim2.new(0, 0, 0.5, -7) img.BackgroundTransparency = 1 img.Image = "rbxassetid://" .. tostring(icon) img.ScaleType = Enum.ScaleType.Fit img.Parent = row
	else
		local iL = Instance.new("TextLabel") iL.Size = UDim2.new(0, 14, 1, 0) iL.BackgroundTransparency = 1 iL.Text = icon iL.TextSize = 11 iL.Font = Enum.Font.GothamBold iL.TextColor3 = Color3.fromRGB(25, 190, 75) iL.TextXAlignment = Enum.TextXAlignment.Center iL.TextYAlignment = Enum.TextYAlignment.Center iL.Parent = row
	end
	local tL = Instance.new("TextLabel") tL.Size = UDim2.new(1, -18, 1, 0) tL.Position = UDim2.new(0, 20, 0, 0) tL.BackgroundTransparency = 1 tL.Text = title tL.TextColor3 = Color3.fromRGB(205, 205, 215) tL.TextSize = 12 tL.Font = Enum.Font.GothamBold tL.TextXAlignment = Enum.TextXAlignment.Left tL.TextYAlignment = Enum.TextYAlignment.Center tL.Parent = row
	return row
end

local function makeCardHeaderWithScan(parent, order, icon, title, iconIsImage)
	local row = makeCardHeader(parent, order, icon, title, iconIsImage)
	local tL = row:FindFirstChildOfClass("TextLabel") if tL then tL.Size = UDim2.new(1, -130, 1, 0) end
	local scanLbl = Instance.new("TextLabel") scanLbl.Size = UDim2.new(0, 110, 1, 0) scanLbl.Position = UDim2.new(1, -110, 0, 0) scanLbl.BackgroundTransparency = 1 scanLbl.Text = "Last scan: never" scanLbl.TextColor3 = Color3.fromRGB(48, 48, 60) scanLbl.TextSize = 8 scanLbl.Font = Enum.Font.Gotham scanLbl.TextXAlignment = Enum.TextXAlignment.Right scanLbl.TextYAlignment = Enum.TextYAlignment.Center scanLbl.Parent = row
	return row, scanLbl
end

local function makeSpacer(parent, order, h)
	local s = Instance.new("Frame") s.Size = UDim2.new(1, 0, 0, h) s.BackgroundTransparency = 1 s.LayoutOrder = order s.Parent = parent
end

local function makeDivider(parent, order)
	local d = Instance.new("Frame") d.Size = UDim2.new(1, 0, 0, 1) d.BackgroundColor3 = Color3.fromRGB(28, 28, 36) d.BorderSizePixel = 0 d.LayoutOrder = order d.Parent = parent
end

-- ══ PRE-DECLARE: vars used by UpdatePlayerStatus + Heartbeat after avatar block ══
local avatarStroke, statusDot, statusTxt, paidLbl

do -- ── Avatar card scope ── (locals freed after this block)
-- ══ LICENSE DATA FROM KEY SYSTEM ══
-- Read everything the key system stored before loading this script
local licTierleft  = tonumber(getgenv and getgenv().LICENSE_TIMELEFT or 0) or 0
local licExpiry    = tonumber(getgenv and getgenv().LICENSE_EXPIRY    or 0) or 0
local licStatus    = (getgenv and getgenv().LICENSE_STATUS)  or "Active"
local licTierRaw   = (getgenv and getgenv().USER_TIER)       or "trial"

-- Auto-detect display label + color from time remaining
local function getLicenseDisplay(secs)
	if secs < 3600 then
		return "🆓  Free Trial",    Color3.fromRGB(34, 197, 94),  false
	elseif secs <= 86400 * 4 then
		return "📅  3-Day",         Color3.fromRGB(50, 200, 220), true
	elseif secs <= 86400 * 8 then
		return "👑  Weekly",        Color3.fromRGB(255, 255, 255), true
	elseif secs <= 86400 * 32 then
		return "👑  Monthly",       Color3.fromRGB(212, 175, 55), true
	else
		return "👑  Premium",       Color3.fromRGB(34, 197, 94),  true
	end
end

local function fmtCountdown(secs)
	if secs <= 0 then return "Expired" end
	local d = math.floor(secs / 86400)
	local h = math.floor((secs % 86400) / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	if d > 0 then return d .. "d " .. h .. "h " .. m .. "m"
	elseif h > 0 then return h .. "h " .. m .. "m " .. s .. "s"
	else return m .. "m " .. s .. "s" end
end

local function fmtExpiry(ts)
	if not ts or ts == 0 then return "Unknown" end
	return os.date("%b %d, %Y  %I:%M %p", ts)
end

local licLabel, licColor, _ = getLicenseDisplay(licTierleft)
local secondsLeft = licTierleft  -- live countdown tracker

-- ══ AVATAR CARD ══
local avCard = makeCard(1)

-- Top row: avatar + name + status dot
local avRow = Instance.new("Frame")
avRow.Size = UDim2.new(1, 0, 0, 70)
avRow.BackgroundTransparency = 1
avRow.LayoutOrder = 1
avRow.Parent = avCard

local avatarRing = Instance.new("Frame")
avatarRing.Size = UDim2.new(0, 48, 0, 48)
avatarRing.Position = UDim2.new(0, 0, 0.5, -24)
avatarRing.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
avatarRing.BorderSizePixel = 0
avatarRing.Parent = avRow
Instance.new("UICorner", avatarRing).CornerRadius = UDim.new(1, 0)
avatarStroke = Instance.new("UIStroke", avatarRing)
avatarStroke.Color = Color3.fromRGB(55, 55, 70)  -- gray default, green when farming
avatarStroke.Thickness = 2.5

-- Glow ring behind avatar (invisible until farming active)
local glowRing = Instance.new("Frame")
glowRing.Size = UDim2.new(0, 62, 0, 62)
glowRing.Position = UDim2.new(0, -7, 0.5, -31)
glowRing.BackgroundColor3 = Color3.fromRGB(25, 190, 75)
glowRing.BackgroundTransparency = 1
glowRing.BorderSizePixel = 0
glowRing.ZIndex = 0
glowRing.Parent = avRow
Instance.new("UICorner", glowRing).CornerRadius = UDim.new(1, 0)
-- Store reference so UpdatePlayerStatus can animate it
_G._atmFarmerGlowRing = glowRing
local avatarImg = Instance.new("ImageLabel")
avatarImg.Size = UDim2.new(1, 0, 1, 0)
avatarImg.BackgroundTransparency = 1
avatarImg.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png"
avatarImg.ScaleType = Enum.ScaleType.Crop
avatarImg.Parent = avatarRing
Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(1, 0)

statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 13, 0, 13)
statusDot.Position = UDim2.new(0, 34, 0, 39)
statusDot.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
statusDot.BorderSizePixel = 0
statusDot.ZIndex = 3
statusDot.Parent = avRow
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)
local dotOutline = Instance.new("UIStroke", statusDot)
dotOutline.Color = Color3.fromRGB(19, 19, 23)
dotOutline.Thickness = 2.5

-- Welcome message
local displayLbl = Instance.new("TextLabel")
displayLbl.Size = UDim2.new(1, -58, 0, 16)
displayLbl.Position = UDim2.new(0, 58, 0, 9)  -- slides up to y=3
displayLbl.BackgroundTransparency = 1
displayLbl.Text = "Welcome, " .. player.DisplayName .. "!"
displayLbl.TextColor3 = Color3.fromRGB(240, 240, 245)
displayLbl.TextSize = 13
displayLbl.Font = Enum.Font.GothamBold
displayLbl.TextXAlignment = Enum.TextXAlignment.Left
displayLbl.Parent = avRow

local tagLbl = Instance.new("TextLabel")
tagLbl.Size = UDim2.new(1, -58, 0, 12)
tagLbl.Position = UDim2.new(0, 58, 0, 20)
tagLbl.BackgroundTransparency = 1
tagLbl.Text = "@" .. player.Name
tagLbl.TextColor3 = Color3.fromRGB(58, 58, 76)
tagLbl.TextSize = 10
tagLbl.Font = Enum.Font.Gotham
tagLbl.TextXAlignment = Enum.TextXAlignment.Left
tagLbl.Parent = avRow

-- Premium / Free Trial status badge
local tierStatusLbl = Instance.new("TextLabel")
tierStatusLbl.Size = UDim2.new(1, -58, 0, 12)
tierStatusLbl.Position = UDim2.new(0, 58, 0, 33)
tierStatusLbl.BackgroundTransparency = 1
tierStatusLbl.Text = IS_PREMIUM and "👑 Premium" or "🆓 Free Trial"
tierStatusLbl.TextColor3 = IS_PREMIUM and Color3.fromRGB(212, 175, 55) or Color3.fromRGB(34, 197, 94)
tierStatusLbl.TextSize = 10
tierStatusLbl.Font = Enum.Font.GothamBold
tierStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
tierStatusLbl.TextTransparency = 1  -- starts invisible
tierStatusLbl.Parent = avRow

-- Welcome fade-in animations — timed to start as loading screen fades out
displayLbl.TextTransparency = 1
tagLbl.TextTransparency = 1
task.delay(2.9, function()
	TweenService:Create(displayLbl, TweenInfo.new(0.55, Enum.EasingStyle.Quint), {TextTransparency = 0}):Play()
	TweenService:Create(displayLbl, TweenInfo.new(0.5, Enum.EasingStyle.Quint),
		{Position = UDim2.new(0, 58, 0, 3)}):Play()
end)
task.delay(3.05, function()
	TweenService:Create(tagLbl, TweenInfo.new(0.45, Enum.EasingStyle.Quint), {TextTransparency = 0}):Play()
end)
task.delay(3.2, function()
	TweenService:Create(tierStatusLbl, TweenInfo.new(0.45, Enum.EasingStyle.Quint), {TextTransparency = 0}):Play()
end)

statusTxt = Instance.new("TextLabel")
statusTxt.Size = UDim2.new(1, -58, 0, 12)
statusTxt.Position = UDim2.new(0, 58, 0, 46)
statusTxt.BackgroundTransparency = 1
statusTxt.Text = "Idle — waiting to start"
statusTxt.TextColor3 = Color3.fromRGB(58, 58, 76)
statusTxt.TextSize = 10
statusTxt.Font = Enum.Font.Gotham
statusTxt.TextXAlignment = Enum.TextXAlignment.Left
statusTxt.TextTruncate = Enum.TextTruncate.AtEnd
statusTxt.Parent = avRow

-- Divider between avatar row and license panel
local avDiv = Instance.new("Frame")
avDiv.Size = UDim2.new(1, 0, 0, 1)
avDiv.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
avDiv.BorderSizePixel = 0
avDiv.LayoutOrder = 2
avDiv.Parent = avCard

-- ── LICENSE INFO PANEL ────────────────────────────────────
local licPanel = Instance.new("Frame")
licPanel.Size = UDim2.new(1, 0, 0, 0)
licPanel.AutomaticSize = Enum.AutomaticSize.Y
licPanel.BackgroundTransparency = 1
licPanel.LayoutOrder = 3
licPanel.Parent = avCard

local licPanelLayout = Instance.new("UIListLayout", licPanel)
licPanelLayout.FillDirection = Enum.FillDirection.Horizontal
licPanelLayout.VerticalAlignment = Enum.VerticalAlignment.Center
licPanelLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Left: countdown + expiry
local licLeft = Instance.new("Frame")
licLeft.Size = UDim2.new(1, -90, 0, 0)
licLeft.AutomaticSize = Enum.AutomaticSize.Y
licLeft.BackgroundTransparency = 1
licLeft.LayoutOrder = 1
licLeft.Parent = licPanel
local licLeftL = Instance.new("UIListLayout", licLeft)
licLeftL.SortOrder = Enum.SortOrder.LayoutOrder
licLeftL.Padding = UDim.new(0, 2)

local countdownLbl = Instance.new("TextLabel")
countdownLbl.Size = UDim2.new(1, 0, 0, 14)
countdownLbl.BackgroundTransparency = 1
countdownLbl.Text = "⏱  " .. fmtCountdown(secondsLeft) .. " remaining"
countdownLbl.TextColor3 = licColor
countdownLbl.TextSize = 11
countdownLbl.Font = Enum.Font.GothamBold
countdownLbl.TextXAlignment = Enum.TextXAlignment.Left
countdownLbl.LayoutOrder = 1
countdownLbl.Parent = licLeft

local expiryLbl = Instance.new("TextLabel")
expiryLbl.Size = UDim2.new(1, 0, 0, 13)
expiryLbl.BackgroundTransparency = 1
expiryLbl.Text = "Expires  " .. fmtExpiry(licExpiry)
expiryLbl.TextColor3 = Color3.fromRGB(58, 58, 76)
expiryLbl.TextSize = 9
expiryLbl.Font = Enum.Font.Gotham
expiryLbl.TextXAlignment = Enum.TextXAlignment.Left
expiryLbl.LayoutOrder = 2
expiryLbl.Parent = licLeft

-- Right: tier badge
local badgeWrap = Instance.new("Frame")
badgeWrap.Size = UDim2.new(0, 88, 0, 0)
badgeWrap.AutomaticSize = Enum.AutomaticSize.Y
badgeWrap.BackgroundTransparency = 1
badgeWrap.LayoutOrder = 2
badgeWrap.Parent = licPanel
local badgeWrapL = Instance.new("UIListLayout", badgeWrap)
badgeWrapL.HorizontalAlignment = Enum.HorizontalAlignment.Right
badgeWrapL.VerticalAlignment = Enum.VerticalAlignment.Center

local tierBadge = Instance.new("TextLabel")
tierBadge.Size = UDim2.new(0, 80, 0, 22)
tierBadge.BackgroundColor3 = Color3.new(
	licColor.R * 0.12, licColor.G * 0.12, licColor.B * 0.12)
tierBadge.BorderSizePixel = 0
tierBadge.Text = licLabel
tierBadge.TextColor3 = licColor
tierBadge.TextSize = 10
tierBadge.Font = Enum.Font.GothamBold
tierBadge.TextXAlignment = Enum.TextXAlignment.Center
tierBadge.LayoutOrder = 1
tierBadge.Parent = badgeWrap
local tierBadgeC = Instance.new("UICorner", tierBadge)
tierBadgeC.CornerRadius = UDim.new(0, 6)
local tierBadgeS = Instance.new("UIStroke", tierBadge)
tierBadgeS.Color = licColor
tierBadgeS.Thickness = 1

local statusBadge = Instance.new("TextLabel")
statusBadge.Size = UDim2.new(0, 80, 0, 16)
statusBadge.BackgroundTransparency = 1
statusBadge.Text = "● " .. licStatus
statusBadge.TextColor3 = Color3.fromRGB(34, 197, 94)
statusBadge.TextSize = 9
statusBadge.Font = Enum.Font.GothamBold
statusBadge.TextXAlignment = Enum.TextXAlignment.Right
statusBadge.LayoutOrder = 2
statusBadge.Parent = badgeWrap

-- Padding inside the license panel
local licPanelPad = Instance.new("UIPadding", licPanel)
licPanelPad.PaddingTop = UDim.new(0, 8)
licPanelPad.PaddingBottom = UDim.new(0, 4)

-- ── LIVE COUNTDOWN ─────────────────────────────────────────
-- Ticks every second, updates countdownLbl in real time.
-- When the license expires mid-session, badge turns red.
task.spawn(function()
	while gui and gui.Parent do
		task.wait(1)
		secondsLeft = math.max(0, secondsLeft - 1)
		if countdownLbl and countdownLbl.Parent then
			if secondsLeft <= 0 then
				countdownLbl.Text = "⏱  Expired"
				countdownLbl.TextColor3 = Color3.fromRGB(210, 55, 55)
				statusBadge.Text = "● Expired"
				statusBadge.TextColor3 = Color3.fromRGB(210, 55, 55)
				tierBadge.TextColor3 = Color3.fromRGB(210, 55, 55)
			else
				countdownLbl.Text = "⏱  " .. fmtCountdown(secondsLeft) .. " remaining"
				-- Warning color in last 5 minutes
				if secondsLeft <= 300 then
					countdownLbl.TextColor3 = Color3.fromRGB(220, 160, 40)
				end
			end
		end
	end
end)

-- ══ PLAYER STATUS SYSTEM ══
paidLbl = Instance.new("TextLabel")  -- kept for UpdatePlayerStatus compat
paidLbl.Size = UDim2.new(0, 0, 0, 0)
paidLbl.BackgroundTransparency = 1
paidLbl.Text = ""
paidLbl.Visible = false
paidLbl.Parent = avRow

end -- ── end avatar card scope ── (all temp locals freed)

local currentStatusState = "idle"
local _glowPulseActive = false
local function UpdatePlayerStatus(state, statusText)
	if state ~= currentStatusState then
		currentStatusState = state
		local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local glow = _G._atmFarmerGlowRing  -- glow ring created inside do block

		if state == "active" then
			-- Green ring + glow pulse
			TweenService:Create(avatarStroke, ti, {Color = Color3.fromRGB(25, 190, 75)}):Play()
			TweenService:Create(statusDot,   ti, {BackgroundColor3 = Color3.fromRGB(25, 190, 75)}):Play()
			statusTxt.TextColor3 = Color3.fromRGB(25, 190, 75)
			-- Start glow pulse
			_glowPulseActive = true
			task.spawn(function()
				while _glowPulseActive do
					if glow then TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.55}):Play() end
					task.wait(0.95)
					if not _glowPulseActive then break end
					if glow then TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.82}):Play() end
					task.wait(0.95)
				end
				-- Fade glow out when stopped
				if glow then TweenService:Create(glow, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play() end
			end)
		elseif state == "paused" then
			-- Stop glow, gray ring
			_glowPulseActive = false
			TweenService:Create(avatarStroke, ti, {Color = Color3.fromRGB(55, 55, 70)}):Play()
			TweenService:Create(statusDot,   ti, {BackgroundColor3 = Color3.fromRGB(55, 55, 70)}):Play()
			statusTxt.TextColor3 = Color3.fromRGB(58, 58, 76)
		elseif state == "idle" then
			-- Stop glow, gray ring
			_glowPulseActive = false
			TweenService:Create(avatarStroke, ti, {Color = Color3.fromRGB(55, 55, 70)}):Play()
			TweenService:Create(statusDot,   ti, {BackgroundColor3 = Color3.fromRGB(55, 55, 70)}):Play()
			statusTxt.TextColor3 = Color3.fromRGB(58, 58, 76)
		elseif state == "error" then
			_glowPulseActive = false
			TweenService:Create(avatarStroke, ti, {Color = Color3.fromRGB(210, 55, 55)}):Play()
			TweenService:Create(statusDot,   ti, {BackgroundColor3 = Color3.fromRGB(210, 55, 55)}):Play()
			statusTxt.TextColor3 = Color3.fromRGB(210, 55, 55)
		end
	end
	statusTxt.Text = statusText or (state == "active" and "Autofarming") or (state == "paused" and "Paused") or (state == "idle" and "Idle — waiting to start") or (state == "error" and "Error occurred") or "Unknown"
end

local function onCharacterAdded(newChar)
	character = newChar
	humanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
	humanoid = newChar:WaitForChild("Humanoid")
	isPickingUp = false lastATMCFrame = nil activeATM = nil activeATMPos = nil
	currentAction = "Respawned — resuming..."
	humanoid.PlatformStand = false
	if not getgenv().ATM_RUNNING then
		UpdatePlayerStatus(getgenv().ATM_STARTED and "paused" or "idle")
	end
end
player.CharacterAdded:Connect(onCharacterAdded)

-- ══ PRE-DECLARE: live scanner values ══
local atmAvailVal, atmBrokenVal, detScanLbl
local vaultOpenVal, vaultClosedVal, vaultScanLbl

do -- ── detection + vault card scope ──
-- ══ DETECTION CARDS ══
local detCard = makeCard(2)
local _, _detScanLbl = makeCardHeaderWithScan(detCard, 1, 98439685495165, "Live Detection", true)
detScanLbl = _detScanLbl
makeSpacer(detCard, 2, 6)
local detGrid = Instance.new("Frame") detGrid.Size = UDim2.new(1, 0, 0, 62) detGrid.BackgroundTransparency = 1 detGrid.LayoutOrder = 3 detGrid.Parent = detCard
local detGL = Instance.new("UIListLayout", detGrid) detGL.FillDirection = Enum.FillDirection.Horizontal detGL.Padding = UDim.new(0, 7)

local function makeDetBox(parent, layoutOrder, bg, iconAsset, labelText, valColor)
	local box = Instance.new("Frame") box.Size = UDim2.new(0.5, -4, 1, 0) box.BackgroundColor3 = bg box.BorderSizePixel = 0 box.LayoutOrder = layoutOrder box.Parent = parent
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)
	local iconBg = Instance.new("Frame") iconBg.Size = UDim2.new(0, 32, 0, 32) iconBg.Position = UDim2.new(0, 7, 0, 14)
	iconBg.BackgroundColor3 = Color3.fromRGB(math.clamp(math.floor(valColor.R*255*0.18),0,255), math.clamp(math.floor(valColor.G*255*0.18),0,255), math.clamp(math.floor(valColor.B*255*0.18),0,255))
	iconBg.BorderSizePixel = 0 iconBg.Parent = box
	Instance.new("UICorner", iconBg).CornerRadius = UDim.new(0, 6)
	local iconImg = Instance.new("ImageLabel") iconImg.Size = UDim2.new(0, 19, 0, 19) iconImg.Position = UDim2.new(0.5, -10, 0.5, -10) iconImg.BackgroundTransparency = 1 iconImg.Image = "rbxassetid://" .. tostring(iconAsset) iconImg.ScaleType = Enum.ScaleType.Fit iconImg.ImageColor3 = valColor iconImg.Parent = iconBg
	local vL = Instance.new("TextLabel") vL.Size = UDim2.new(1, -46, 0, 22) vL.Position = UDim2.new(0, 42, 0, 10) vL.BackgroundTransparency = 1 vL.Text = "0" vL.TextColor3 = valColor vL.TextSize = 20 vL.Font = Enum.Font.GothamBold vL.TextXAlignment = Enum.TextXAlignment.Left vL.TextYAlignment = Enum.TextYAlignment.Center vL.Parent = box
	local nL = Instance.new("TextLabel") nL.Size = UDim2.new(1, -46, 0, 12) nL.Position = UDim2.new(0, 42, 0, 34) nL.BackgroundTransparency = 1 nL.Text = labelText nL.TextColor3 = valColor nL.TextSize = 9 nL.Font = Enum.Font.Gotham nL.TextXAlignment = Enum.TextXAlignment.Left nL.TextYAlignment = Enum.TextYAlignment.Center nL.Parent = box
	return vL
end

atmAvailVal  = makeDetBox(detGrid, 1, Color3.fromRGB(13,30,15), 83562019198470, "ATMs Available", Color3.fromRGB(25,190,75))
atmBrokenVal = makeDetBox(detGrid, 2, Color3.fromRGB(30,13,13), 88329562081184, "ATMs Broken",    Color3.fromRGB(210,55,55))

-- ══ VAULT CARDS ══
local vaultCard = makeCard(3)
local _, _vaultScanLbl = makeCardHeaderWithScan(vaultCard, 1, 88774952696393, "Live Vault Detection", true)
vaultScanLbl = _vaultScanLbl
makeSpacer(vaultCard, 2, 6)
local vaultGrid = Instance.new("Frame") vaultGrid.Size = UDim2.new(1, 0, 0, 62) vaultGrid.BackgroundTransparency = 1 vaultGrid.LayoutOrder = 3 vaultGrid.Parent = vaultCard
local vGL = Instance.new("UIListLayout", vaultGrid) vGL.FillDirection = Enum.FillDirection.Horizontal vGL.Padding = UDim.new(0, 7)
vaultOpenVal   = makeDetBox(vaultGrid, 1, Color3.fromRGB(13,30,15), 94851890970090, "Vaults Open",   Color3.fromRGB(25,190,75))
vaultClosedVal = makeDetBox(vaultGrid, 2, Color3.fromRGB(30,13,13), 77505460123202, "Vaults Closed", Color3.fromRGB(210,55,55))
end -- ── end detection + vault scope ──

-- ══ AUTOMATION CARD ══
local autoCard = makeCard(4)
makeCardHeader(autoCard, 1, 121618404766337, "Automation", true)
makeSpacer(autoCard, 2, 9)

local function makeToggleRow(parent, order, title, subtitle, enableText)
	local wrap = Instance.new("Frame") wrap.Size = UDim2.new(1, 0, 0, 60) wrap.BackgroundTransparency = 1 wrap.LayoutOrder = order wrap.Parent = parent
	local titleL = Instance.new("TextLabel") titleL.Size = UDim2.new(1, 0, 0, 16) titleL.BackgroundTransparency = 1 titleL.Text = title titleL.TextColor3 = Color3.fromRGB(210, 210, 220) titleL.TextSize = 12 titleL.Font = Enum.Font.GothamBold titleL.TextXAlignment = Enum.TextXAlignment.Left titleL.Parent = wrap
	local subL = Instance.new("TextLabel") subL.Size = UDim2.new(1, 0, 0, 12) subL.Position = UDim2.new(0, 0, 0, 18) subL.BackgroundTransparency = 1 subL.Text = subtitle subL.TextColor3 = Color3.fromRGB(58, 58, 75) subL.TextSize = 9 subL.Font = Enum.Font.Gotham subL.TextXAlignment = Enum.TextXAlignment.Left subL.Parent = wrap
	local track = Instance.new("TextButton") track.Size = UDim2.new(0, 42, 0, 22) track.Position = UDim2.new(0, 0, 0, 34) track.BackgroundColor3 = Color3.fromRGB(30, 30, 42) track.Text = "" track.BorderSizePixel = 0 track.Parent = wrap
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local thumb = Instance.new("Frame") thumb.Size = UDim2.new(0, 16, 0, 16) thumb.Position = UDim2.new(0, 3, 0.5, -8) thumb.BackgroundColor3 = Color3.fromRGB(82, 82, 105) thumb.BorderSizePixel = 0 thumb.Parent = track
	Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)
	local togLbl = Instance.new("TextLabel") togLbl.Size = UDim2.new(1, -50, 0, 22) togLbl.Position = UDim2.new(0, 50, 0, 34) togLbl.BackgroundTransparency = 1 togLbl.Text = enableText togLbl.TextColor3 = Color3.fromRGB(82, 82, 105) togLbl.TextSize = 10 togLbl.Font = Enum.Font.Gotham togLbl.TextXAlignment = Enum.TextXAlignment.Left togLbl.TextYAlignment = Enum.TextYAlignment.Center togLbl.Parent = wrap
	return track, thumb, subL, togLbl
end

local radTrack, radThumb, radSubLbl, radTogLbl = makeToggleRow(autoCard, 3, "ATM Radius", "Scan " .. ATM_RADIUS .. " studs around active ATM — OFF", "Enable ATM Radius")
do local radBadge = Instance.new("TextLabel")
radBadge.Size = UDim2.new(0, 68, 0, 14) radBadge.Position = UDim2.new(1, -70, 0, 1)
radBadge.BackgroundColor3 = Color3.fromRGB(38, 30, 8) radBadge.BorderSizePixel = 0
radBadge.Text = "👑 PREMIUM" radBadge.TextColor3 = Color3.fromRGB(212, 160, 40)
radBadge.TextSize = 8 radBadge.Font = Enum.Font.GothamBold
radBadge.TextXAlignment = Enum.TextXAlignment.Center radBadge.ZIndex = 3
radBadge.Parent = radTrack.Parent
Instance.new("UICorner", radBadge).CornerRadius = UDim.new(0, 4) end
makeSpacer(autoCard, 4, 3) makeDivider(autoCard, 5) makeSpacer(autoCard, 6, 3)

local fbTrack, fbThumb, fbSubLbl, fbTogLbl = makeToggleRow(autoCard, 7, "Fast Break ATM", "Use knife for instant break — OFF", "Enable Fast Break")
do local fbBadge = Instance.new("TextLabel")
fbBadge.Size = UDim2.new(0, 68, 0, 14) fbBadge.Position = UDim2.new(1, -70, 0, 1)
fbBadge.BackgroundColor3 = Color3.fromRGB(38, 30, 8) fbBadge.BorderSizePixel = 0
fbBadge.Text = "👑 PREMIUM" fbBadge.TextColor3 = Color3.fromRGB(212, 160, 40)
fbBadge.TextSize = 8 fbBadge.Font = Enum.Font.GothamBold
fbBadge.TextXAlignment = Enum.TextXAlignment.Center fbBadge.ZIndex = 3
fbBadge.Parent = fbTrack.Parent
Instance.new("UICorner", fbBadge).CornerRadius = UDim.new(0, 4) end
makeSpacer(autoCard, 8, 3) makeDivider(autoCard, 9) makeSpacer(autoCard, 10, 3)

local hfTrack, hfThumb, hfSubLbl, hfTogLbl = makeToggleRow(autoCard, 11,
	"Underground Mode",
	"To avoid people killing you while farming — OFF",
	"Enable Underground Mode")
do local ugBadge = Instance.new("TextLabel")
ugBadge.Size = UDim2.new(0, 68, 0, 14) ugBadge.Position = UDim2.new(1, -70, 0, 1)
ugBadge.BackgroundColor3 = Color3.fromRGB(38, 30, 8) ugBadge.BorderSizePixel = 0
ugBadge.Text = "👑 PREMIUM" ugBadge.TextColor3 = Color3.fromRGB(212, 160, 40)
ugBadge.TextSize = 8 ugBadge.Font = Enum.Font.GothamBold
ugBadge.TextXAlignment = Enum.TextXAlignment.Center ugBadge.ZIndex = 3
ugBadge.Parent = hfTrack.Parent
Instance.new("UICorner", ugBadge).CornerRadius = UDim.new(0, 4) end

local function animateToggle(track, thumb, on)
	local ti = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if on then
		TweenService:Create(track, ti, {BackgroundColor3 = Color3.fromRGB(22, 160, 60)}):Play()
		TweenService:Create(thumb, ti, {Position = UDim2.new(1, -19, 0.5, -8), BackgroundColor3 = Color3.fromRGB(255, 255, 255)}):Play()
	else
		TweenService:Create(track, ti, {BackgroundColor3 = Color3.fromRGB(30, 30, 42)}):Play()
		TweenService:Create(thumb, ti, {Position = UDim2.new(0, 3, 0.5, -8), BackgroundColor3 = Color3.fromRGB(82, 82, 105)}):Play()
	end
end

local function setRadiusToggle(on)
	getgenv().RADIUS_ENABLED = on animateToggle(radTrack, radThumb, on)
	radSubLbl.Text = "Scan " .. ATM_RADIUS .. " studs around active ATM — " .. (on and "ON" or "OFF")
	radSubLbl.TextColor3 = on and Color3.fromRGB(25, 175, 65) or Color3.fromRGB(58, 58, 75)
	radTogLbl.TextColor3 = on and Color3.fromRGB(25, 190, 75) or Color3.fromRGB(82, 82, 105)
end

local function setFastBreakToggle(on)
	getgenv().FAST_BREAK = on animateToggle(fbTrack, fbThumb, on)
	fbSubLbl.Text = "Use knife for instant break — " .. (on and "ON" or "OFF")
	fbSubLbl.TextColor3 = on and Color3.fromRGB(25, 175, 65) or Color3.fromRGB(58, 58, 75)
	fbTogLbl.TextColor3 = on and Color3.fromRGB(25, 190, 75) or Color3.fromRGB(82, 82, 105)
end

local function setHiddenFarmToggle(on)
	getgenv().HIDDEN_FARM = on animateToggle(hfTrack, hfThumb, on)
	hfSubLbl.Text = "To avoid people killing you while farming — " .. (on and "ON" or "OFF")
	hfSubLbl.TextColor3 = on and Color3.fromRGB(25, 175, 65) or Color3.fromRGB(58, 58, 75)
	hfTogLbl.TextColor3 = on and Color3.fromRGB(25, 190, 75) or Color3.fromRGB(82, 82, 105)
	if not on then
		clearHiddenFailed()
		local h = getHum() if h then h.PlatformStand = false end
	end
end

-- ══ NOTIFICATION SYSTEM ══
-- Declared first so showPremiumPopup can safely call it
local function showNotification(title, message, duration)
	duration = duration or 3
	local notif = Instance.new("Frame")
	notif.Size = UDim2.new(0, 260, 0, 0) notif.AutomaticSize = Enum.AutomaticSize.Y
	notif.AnchorPoint = Vector2.new(1, 1)
	notif.Position = UDim2.new(1, 320, 1, -20)
	notif.BackgroundColor3 = Color3.fromRGB(18, 18, 24) notif.BorderSizePixel = 0 notif.ZIndex = 60
	notif.Parent = gui
	Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 10)
	Instance.new("UIStroke", notif).Color = Color3.fromRGB(34, 197, 94)
	local nLayout = Instance.new("UIListLayout", notif) nLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local nPad = Instance.new("UIPadding", notif)
	nPad.PaddingTop=UDim.new(0,12) nPad.PaddingBottom=UDim.new(0,12) nPad.PaddingLeft=UDim.new(0,14) nPad.PaddingRight=UDim.new(0,14)
	local nt = Instance.new("TextLabel") nt.Size=UDim2.new(1,0,0,16) nt.BackgroundTransparency=1 nt.Text=title nt.TextColor3=Color3.fromRGB(34,197,94) nt.TextSize=13 nt.Font=Enum.Font.GothamBold nt.TextXAlignment=Enum.TextXAlignment.Left nt.LayoutOrder=1 nt.Parent=notif
	local nm = Instance.new("TextLabel") nm.Size=UDim2.new(1,0,0,0) nm.AutomaticSize=Enum.AutomaticSize.Y nm.BackgroundTransparency=1 nm.Text=message nm.TextColor3=Color3.fromRGB(100,100,122) nm.TextSize=11 nm.Font=Enum.Font.Gotham nm.TextXAlignment=Enum.TextXAlignment.Left nm.TextWrapped=true nm.LayoutOrder=2 nm.Parent=notif
	TweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position=UDim2.new(1,-14,1,-20)}):Play()
	task.delay(duration, function()
		if notif and notif.Parent then
			TweenService:Create(notif, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Position=UDim2.new(1,320,1,-20)}):Play()
			task.wait(0.3) if notif then notif:Destroy() end
		end
	end)
end

-- ══ PREMIUM POPUP ══
local function showPremiumPopup()
	local popOverlay = Instance.new("Frame")
	popOverlay.Size = UDim2.new(1, 0, 1, 0)
	popOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	popOverlay.BackgroundTransparency = 1
	popOverlay.BorderSizePixel = 0
	popOverlay.ZIndex = 50
	popOverlay.Parent = gui
	TweenService:Create(popOverlay, TweenInfo.new(0.2), {BackgroundTransparency = 0.55}):Play()

	local pop = Instance.new("CanvasGroup")
	pop.Size = UDim2.new(0, 300, 0, 0)
	pop.AutomaticSize = Enum.AutomaticSize.Y
	pop.AnchorPoint = Vector2.new(0.5, 0.5)
	pop.Position = UDim2.new(0.5, 0, 0.5, 0)
	pop.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	pop.BorderSizePixel = 0
	pop.GroupTransparency = 1
	pop.ZIndex = 51
	pop.Parent = gui
	Instance.new("UICorner", pop).CornerRadius = UDim.new(0, 14)
	local popStroke = Instance.new("UIStroke", pop)
	popStroke.Color = Color3.fromRGB(212, 160, 40) popStroke.Thickness = 1
	local popLayout = Instance.new("UIListLayout", pop) popLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local popPad = Instance.new("UIPadding", pop)
	popPad.PaddingTop = UDim.new(0, 22) popPad.PaddingBottom = UDim.new(0, 20)
	popPad.PaddingLeft = UDim.new(0, 20) popPad.PaddingRight = UDim.new(0, 20)

	local popScale = Instance.new("UIScale", pop) popScale.Scale = 0.88
	TweenService:Create(pop, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {GroupTransparency = 0}):Play()
	TweenService:Create(popScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

	local crownWrap = Instance.new("Frame") crownWrap.Size = UDim2.new(1,0,0,44) crownWrap.BackgroundTransparency = 1 crownWrap.LayoutOrder = 1 crownWrap.Parent = pop
	local crownCircle = Instance.new("Frame") crownCircle.Size = UDim2.new(0,44,0,44) crownCircle.AnchorPoint = Vector2.new(0.5,0) crownCircle.Position = UDim2.new(0.5,0,0,0) crownCircle.BackgroundColor3 = Color3.fromRGB(38,30,8) crownCircle.BorderSizePixel = 0 crownCircle.Parent = crownWrap
	Instance.new("UICorner", crownCircle).CornerRadius = UDim.new(1,0)
	local crownTxt = Instance.new("TextLabel") crownTxt.Size = UDim2.new(1,0,1,0) crownTxt.BackgroundTransparency = 1 crownTxt.Text = "👑" crownTxt.TextSize = 22 crownTxt.Font = Enum.Font.GothamBold crownTxt.TextXAlignment = Enum.TextXAlignment.Center crownTxt.TextYAlignment = Enum.TextYAlignment.Center crownTxt.Parent = crownCircle

	local s1 = Instance.new("Frame") s1.Size=UDim2.new(1,0,0,10) s1.BackgroundTransparency=1 s1.LayoutOrder=2 s1.Parent=pop

	local popTitle = Instance.new("TextLabel") popTitle.Size=UDim2.new(1,0,0,22) popTitle.BackgroundTransparency=1 popTitle.Text="Premium Feature" popTitle.TextColor3=Color3.fromRGB(212,175,55) popTitle.TextSize=16 popTitle.Font=Enum.Font.GothamBold popTitle.TextXAlignment=Enum.TextXAlignment.Center popTitle.LayoutOrder=3 popTitle.Parent=pop

	local s2 = Instance.new("Frame") s2.Size=UDim2.new(1,0,0,8) s2.BackgroundTransparency=1 s2.LayoutOrder=4 s2.Parent=pop

	local popMsg = Instance.new("TextLabel") popMsg.Size=UDim2.new(1,0,0,0) popMsg.AutomaticSize=Enum.AutomaticSize.Y popMsg.BackgroundTransparency=1 popMsg.Text="This feature is only available for Premium users.\n\nUpgrade your key to unlock this feature and gain access to every premium option." popMsg.TextColor3=Color3.fromRGB(120,120,138) popMsg.TextSize=12 popMsg.Font=Enum.Font.Gotham popMsg.TextXAlignment=Enum.TextXAlignment.Center popMsg.TextWrapped=true popMsg.LayoutOrder=5 popMsg.Parent=pop

	local s3 = Instance.new("Frame") s3.Size=UDim2.new(1,0,0,16) s3.BackgroundTransparency=1 s3.LayoutOrder=6 s3.Parent=pop

	local btnRow = Instance.new("Frame") btnRow.Size=UDim2.new(1,0,0,36) btnRow.BackgroundTransparency=1 btnRow.LayoutOrder=7 btnRow.Parent=pop
	local btnL = Instance.new("UIListLayout",btnRow) btnL.FillDirection=Enum.FillDirection.Horizontal btnL.Padding=UDim.new(0,10) btnL.HorizontalAlignment=Enum.HorizontalAlignment.Center

	local function closePopup()
		TweenService:Create(pop, TweenInfo.new(0.2,Enum.EasingStyle.Quad), {GroupTransparency=1}):Play()
		TweenService:Create(popScale, TweenInfo.new(0.2,Enum.EasingStyle.Quad), {Scale=0.9}):Play()
		TweenService:Create(popOverlay, TweenInfo.new(0.2), {BackgroundTransparency=1}):Play()
		task.wait(0.25) pop:Destroy() popOverlay:Destroy()
	end

	local okBtn = Instance.new("TextButton") okBtn.Size=UDim2.new(0,110,1,0) okBtn.BackgroundColor3=Color3.fromRGB(26,26,34) okBtn.Text="OK" okBtn.TextColor3=Color3.fromRGB(180,180,195) okBtn.TextSize=13 okBtn.Font=Enum.Font.GothamBold okBtn.BorderSizePixel=0 okBtn.LayoutOrder=1 okBtn.Parent=btnRow
	Instance.new("UICorner",okBtn).CornerRadius=UDim.new(0,8)
	okBtn.MouseButton1Click:Connect(function() task.spawn(closePopup) end)

	local upgradeBtn = Instance.new("TextButton") upgradeBtn.Size=UDim2.new(0,140,1,0) upgradeBtn.BackgroundColor3=Color3.fromRGB(212,160,40) upgradeBtn.Text="  Upgrade" upgradeBtn.TextColor3=Color3.fromRGB(255,255,255) upgradeBtn.TextSize=13 upgradeBtn.Font=Enum.Font.GothamBold upgradeBtn.BorderSizePixel=0 upgradeBtn.LayoutOrder=2 upgradeBtn.Parent=btnRow
	Instance.new("UICorner",upgradeBtn).CornerRadius=UDim.new(0,8)
	upgradeBtn.MouseButton1Click:Connect(function()
		pcall(function() setclipboard(DISCORD_INVITE) end)
		upgradeBtn.Text = "✓ Copied!" upgradeBtn.BackgroundColor3 = Color3.fromRGB(34,150,70)
		task.spawn(function()
			task.wait(2)
			upgradeBtn.Text = "  Upgrade" upgradeBtn.BackgroundColor3 = Color3.fromRGB(212,160,40)
		end)
		task.spawn(function()
			task.wait(0.3)
			showNotification("Discord Copied!", "Join the Discord server to purchase Premium keys and receive support.", 3)
		end)
	end)
end

-- ══ PREMIUM TOGGLE SHAKE ══
local function shakePremiumToggle(track)
	local base = track.Position
	for _, x in ipairs({5,-5,4,-4,2,-2,0}) do
		TweenService:Create(track, TweenInfo.new(0.05, Enum.EasingStyle.Linear),
			{Position = UDim2.new(base.X.Scale, base.X.Offset+x, base.Y.Scale, base.Y.Offset)}):Play()
		task.wait(0.055)
	end
	track.Position = base
end

-- ══ PREMIUM-AWARE TOGGLE HANDLERS ══
radTrack.MouseButton1Click:Connect(function()
	if not IS_PREMIUM then
		task.spawn(function() shakePremiumToggle(radTrack) end)
		showPremiumPopup() return
	end
	setRadiusToggle(not getgenv().RADIUS_ENABLED)
end)

fbTrack.MouseButton1Click:Connect(function()
	if not IS_PREMIUM then
		task.spawn(function() shakePremiumToggle(fbTrack) end)
		showPremiumPopup() return
	end
	setFastBreakToggle(not getgenv().FAST_BREAK)
end)

hfTrack.MouseButton1Click:Connect(function()
	if not IS_PREMIUM then
		task.spawn(function() shakePremiumToggle(hfTrack) end)
		showPremiumPopup() return
	end
	setHiddenFarmToggle(not getgenv().HIDDEN_FARM)
end)

-- ══ STATS CARD ══
local statsCard = makeCard(5)
makeCardHeader(statsCard, 1, 92424302331652, "Stats", true)
makeSpacer(statsCard, 2, 9)

local earnCell = Instance.new("Frame") earnCell.Size = UDim2.new(1, 0, 0, 44) earnCell.BackgroundColor3 = Color3.fromRGB(14,14,18) earnCell.BorderSizePixel = 0 earnCell.LayoutOrder = 3 earnCell.Parent = statsCard
Instance.new("UICorner", earnCell).CornerRadius = UDim.new(0, 7)
Instance.new("UIStroke", earnCell).Color = Color3.fromRGB(26, 26, 33)

local earnLblT = Instance.new("TextLabel") earnLblT.Size = UDim2.new(0.5, 0, 0, 11) earnLblT.Position = UDim2.new(0, 7, 0, 5) earnLblT.BackgroundTransparency = 1 earnLblT.Text = "Total Earned" earnLblT.TextColor3 = Color3.fromRGB(58,58,76) earnLblT.TextSize = 9 earnLblT.Font = Enum.Font.Gotham earnLblT.TextXAlignment = Enum.TextXAlignment.Left earnLblT.Parent = earnCell
local earningsBig = Instance.new("TextLabel") earningsBig.Size = UDim2.new(0.5, 0, 0, 20) earningsBig.Position = UDim2.new(0, 7, 0, 18) earningsBig.BackgroundTransparency = 1 earningsBig.Text = "$0" earningsBig.TextColor3 = Color3.fromRGB(25,190,75) earningsBig.TextSize = 15 earningsBig.Font = Enum.Font.GothamBold earningsBig.TextXAlignment = Enum.TextXAlignment.Left earningsBig.Parent = earnCell
local runtimeLbl = Instance.new("TextLabel") runtimeLbl.Size = UDim2.new(0.5, -7, 0, 11) runtimeLbl.Position = UDim2.new(0.5, 0, 0, 5) runtimeLbl.BackgroundTransparency = 1 runtimeLbl.Text = "Not started" runtimeLbl.TextColor3 = Color3.fromRGB(58,58,76) runtimeLbl.TextSize = 9 runtimeLbl.Font = Enum.Font.Gotham runtimeLbl.TextXAlignment = Enum.TextXAlignment.Right runtimeLbl.Parent = earnCell
local earnRateLbl = Instance.new("TextLabel") earnRateLbl.Size = UDim2.new(0.5, -7, 0, 20) earnRateLbl.Position = UDim2.new(0.5, 0, 0, 18) earnRateLbl.BackgroundTransparency = 1 earnRateLbl.Text = "$0/min" earnRateLbl.TextColor3 = Color3.fromRGB(58,58,76) earnRateLbl.TextSize = 11 earnRateLbl.Font = Enum.Font.GothamBold earnRateLbl.TextXAlignment = Enum.TextXAlignment.Right earnRateLbl.Parent = earnCell

makeSpacer(statsCard, 4, 6)
local statsGrid = Instance.new("Frame") statsGrid.Size = UDim2.new(1, 0, 0, 74) statsGrid.BackgroundTransparency = 1 statsGrid.LayoutOrder = 5 statsGrid.Parent = statsCard
local sGL = Instance.new("UIGridLayout", statsGrid) sGL.CellSize = UDim2.new(0.5, -4, 0, 34) sGL.CellPadding = UDim2.new(0, 6, 0, 6) sGL.SortOrder = Enum.SortOrder.LayoutOrder sGL.FillDirectionMaxCells = 2

local function makeStatCell(order, label)
	local cell = Instance.new("Frame") cell.BackgroundColor3 = Color3.fromRGB(14,14,18) cell.BorderSizePixel = 0 cell.LayoutOrder = order cell.Parent = statsGrid
	Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 6) Instance.new("UIStroke", cell).Color = Color3.fromRGB(26, 26, 33)
	local lL = Instance.new("TextLabel") lL.Size = UDim2.new(1,-8,0,10) lL.Position = UDim2.new(0,5,0,4) lL.BackgroundTransparency = 1 lL.Text = label lL.TextColor3 = Color3.fromRGB(58,58,76) lL.TextSize = 8 lL.Font = Enum.Font.Gotham lL.TextXAlignment = Enum.TextXAlignment.Left lL.Parent = cell
	local vL = Instance.new("TextLabel") vL.Size = UDim2.new(1,-8,0,16) vL.Position = UDim2.new(0,5,0,15) vL.BackgroundTransparency = 1 vL.Text = "0" vL.TextColor3 = Color3.fromRGB(210,210,222) vL.TextSize = 13 vL.Font = Enum.Font.GothamBold vL.TextXAlignment = Enum.TextXAlignment.Left vL.Parent = cell
	return vL
end

local punchVal    = makeStatCell(1, "Total Punches")
local dropsVal    = makeStatCell(2, "Drops Collected")
local skippedVal  = makeStatCell(3, "ATMs Skipped")
local earnRateVal = makeStatCell(4, "Earn Rate")
earnRateVal.TextColor3 = Color3.fromRGB(25, 190, 75)

local actionCard = makeCard(6)
makeCardHeader(actionCard, 1, "▶", "Current Action")
makeSpacer(actionCard, 2, 5)
local actionLbl = Instance.new("TextLabel") actionLbl.Size = UDim2.new(1, 0, 0, 13) actionLbl.BackgroundTransparency = 1 actionLbl.Text = "Press Start to begin farming." actionLbl.TextColor3 = Color3.fromRGB(88,88,112) actionLbl.TextSize = 10 actionLbl.Font = Enum.Font.Gotham actionLbl.TextXAlignment = Enum.TextXAlignment.Left actionLbl.TextTruncate = Enum.TextTruncate.AtEnd actionLbl.LayoutOrder = 3 actionLbl.Parent = actionCard

local btnWrap = Instance.new("Frame") btnWrap.Size = UDim2.new(1, 0, 0, 44) btnWrap.BackgroundTransparency = 1 btnWrap.LayoutOrder = 7 btnWrap.Parent = scroll
local toggleBtn = Instance.new("TextButton") toggleBtn.Size = UDim2.new(1, 0, 0, 44) toggleBtn.BackgroundColor3 = Color3.fromRGB(25,175,65) toggleBtn.Text = "▶  START FARMING" toggleBtn.TextColor3 = Color3.fromRGB(255,255,255) toggleBtn.TextSize = 13 toggleBtn.Font = Enum.Font.GothamBold toggleBtn.BorderSizePixel = 0 toggleBtn.Parent = btnWrap
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 10)

-- ══ SHOP WINDOW ══
local shopWindow = Instance.new("Frame") shopWindow.Size = UDim2.new(0,265,0,330) shopWindow.Position = UDim2.new(0,410,0.5,-165) shopWindow.BackgroundColor3 = Color3.fromRGB(12,12,14) shopWindow.BorderSizePixel = 0 shopWindow.Active = true shopWindow.Draggable = true shopWindow.Visible = false shopWindow.Parent = gui
Instance.new("UICorner", shopWindow).CornerRadius = UDim.new(0, 14) Instance.new("UIStroke", shopWindow).Color = Color3.fromRGB(32,32,38)
local sWH = Instance.new("Frame") sWH.Size = UDim2.new(1,0,0,46) sWH.BackgroundColor3 = Color3.fromRGB(16,16,19) sWH.BorderSizePixel = 0 sWH.Parent = shopWindow
Instance.new("UICorner", sWH).CornerRadius = UDim.new(0, 14)
local sWHfix = Instance.new("Frame") sWHfix.Size = UDim2.new(1,0,0.5,0) sWHfix.Position = UDim2.new(0,0,0.5,0) sWHfix.BackgroundColor3 = Color3.fromRGB(16,16,19) sWHfix.BorderSizePixel = 0 sWHfix.Parent = sWH
local sWIcon = Instance.new("ImageLabel") sWIcon.Size = UDim2.new(0,14,0,14) sWIcon.Position = UDim2.new(0,12,0.5,-7) sWIcon.BackgroundTransparency = 1 sWIcon.Image = "rbxassetid://127805931579487" sWIcon.ImageColor3 = Color3.fromRGB(130,130,148) sWIcon.ScaleType = Enum.ScaleType.Fit sWIcon.Parent = sWH
local sWT = Instance.new("TextLabel") sWT.Size = UDim2.new(1,-80,1,0) sWT.Position = UDim2.new(0,32,0,0) sWT.BackgroundTransparency = 1 sWT.Text = "Shop" sWT.TextColor3 = Color3.fromRGB(220,220,230) sWT.TextSize = 14 sWT.Font = Enum.Font.GothamBold sWT.TextXAlignment = Enum.TextXAlignment.Left sWT.TextYAlignment = Enum.TextYAlignment.Center sWT.Parent = sWH
local sWC = Instance.new("TextButton") sWC.Size = UDim2.new(0,26,0,26) sWC.Position = UDim2.new(1,-36,0.5,-13) sWC.BackgroundColor3 = Color3.fromRGB(22,22,28) sWC.Text = "x" sWC.TextColor3 = Color3.fromRGB(148,148,162) sWC.TextSize = 12 sWC.Font = Enum.Font.GothamBold sWC.BorderSizePixel = 0 sWC.Parent = sWH
Instance.new("UICorner", sWC).CornerRadius = UDim.new(0, 7) Instance.new("UIStroke", sWC).Color = Color3.fromRGB(34,34,44)
sWC.MouseButton1Click:Connect(function() shopWindow.Visible = false end)
shopOpenBtn.MouseButton1Click:Connect(function() shopWindow.Visible = not shopWindow.Visible end)

local shopStatusLbl = Instance.new("TextLabel") shopStatusLbl.Size = UDim2.new(1,-20,0,12) shopStatusLbl.Position = UDim2.new(0,10,0,50) shopStatusLbl.BackgroundTransparency = 1 shopStatusLbl.Text = "Select an item to purchase" shopStatusLbl.TextColor3 = Color3.fromRGB(64,64,82) shopStatusLbl.TextSize = 9 shopStatusLbl.Font = Enum.Font.Gotham shopStatusLbl.TextXAlignment = Enum.TextXAlignment.Left shopStatusLbl.Parent = shopWindow

local function makeShopRow(yPos, icon, label, price, btnColor)
	local row = Instance.new("Frame") row.Size = UDim2.new(1,-20,0,50) row.Position = UDim2.new(0,10,0,yPos) row.BackgroundColor3 = Color3.fromRGB(19,19,23) row.BorderSizePixel = 0 row.Parent = shopWindow
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9) Instance.new("UIStroke", row).Color = Color3.fromRGB(30,30,37)
	local iL = Instance.new("TextLabel") iL.Size = UDim2.new(0,26,0,26) iL.Position = UDim2.new(0,8,0.5,-13) iL.BackgroundTransparency = 1 iL.Text = icon iL.TextSize = 17 iL.Font = Enum.Font.GothamBold iL.TextXAlignment = Enum.TextXAlignment.Center iL.TextYAlignment = Enum.TextYAlignment.Center iL.Parent = row
	local nL = Instance.new("TextLabel") nL.Size = UDim2.new(1,-110,0,16) nL.Position = UDim2.new(0,40,0,9) nL.BackgroundTransparency = 1 nL.Text = label nL.TextColor3 = Color3.fromRGB(210,210,222) nL.TextSize = 12 nL.Font = Enum.Font.GothamBold nL.TextXAlignment = Enum.TextXAlignment.Left nL.Parent = row
	local pL = Instance.new("TextLabel") pL.Size = UDim2.new(1,-110,0,11) pL.Position = UDim2.new(0,40,0,27) pL.BackgroundTransparency = 1 pL.Text = price pL.TextColor3 = Color3.fromRGB(64,64,82) pL.TextSize = 9 pL.Font = Enum.Font.Gotham pL.TextXAlignment = Enum.TextXAlignment.Left pL.Parent = row
	local btn = Instance.new("TextButton") btn.Size = UDim2.new(0,50,0,28) btn.Position = UDim2.new(1,-58,0.5,-14) btn.BackgroundColor3 = btnColor btn.Text = "BUY" btn.TextColor3 = Color3.fromRGB(255,255,255) btn.TextSize = 11 btn.Font = Enum.Font.GothamBold btn.BorderSizePixel = 0 btn.Parent = row
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
	return btn
end

local rpgBtn       = makeShopRow(66,  "🚀", "RPG",               "$22,510", Color3.fromRGB(170,36,36))
local rpgAmmoBtn   = makeShopRow(122, "🔋", "RPG Ammo",          "$1,126",  Color3.fromRGB(115,42,160))
local flameBtn     = makeShopRow(178, "🔥", "Flamethrower",      "$10,130", Color3.fromRGB(165,82,10))
local flameAmmoBtn = makeShopRow(234, "⚡", "Flamethrower Ammo", "$1,126",  Color3.fromRGB(16,90,155))

local SHOP_ITEMS = {
	[rpgBtn]       = {name = "[RPG] - $22510",                  label = "RPG"},
	[rpgAmmoBtn]   = {name = "5 [RPG Ammo] - $1126",            label = "RPG Ammo"},
	[flameBtn]     = {name = "[Flamethrower] - $10130",         label = "Flamethrower"},
	[flameAmmoBtn] = {name = "140 [Flamethrower Ammo] - $1126", label = "Flamethrower Ammo"},
}

local shopBusy = false
local function buyItem(btn, itemName, label)
	if shopBusy then return end shopBusy = true
	local hrp = getHRP()
	if not hrp then shopStatusLbl.Text = "No character found!" shopStatusLbl.TextColor3 = Color3.fromRGB(210,55,55) shopBusy = false return end
	local orig, origCol = btn.Text, btn.BackgroundColor3
	btn.Text = "..." btn.BackgroundColor3 = Color3.fromRGB(42,42,52)
	local tpCF = SHOP_LOCATIONS[itemName]
	if not tpCF then shopStatusLbl.Text = "No location for " .. label shopStatusLbl.TextColor3 = Color3.fromRGB(210,55,55) btn.Text = orig btn.BackgroundColor3 = origCol shopBusy = false return end
	shopStatusLbl.Text = "Teleporting to " .. label .. "..." shopStatusLbl.TextColor3 = Color3.fromRGB(175,138,38)
	pcall(function() hrp.CFrame = tpCF end) task.wait(0.5)
	local shopFolder = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
	if not shopFolder then shopStatusLbl.Text = "Shop folder not found!" shopStatusLbl.TextColor3 = Color3.fromRGB(210,55,55) btn.Text = orig btn.BackgroundColor3 = origCol shopBusy = false return end
	local shopItem = shopFolder:FindFirstChild(itemName)
	if not shopItem then shopStatusLbl.Text = label .. " not found!" shopStatusLbl.TextColor3 = Color3.fromRGB(210,55,55) btn.Text = orig btn.BackgroundColor3 = origCol shopBusy = false return end
	local cd = shopItem:FindFirstChildOfClass("ClickDetector")
	if not cd then shopStatusLbl.Text = "ClickDetector missing!" shopStatusLbl.TextColor3 = Color3.fromRGB(210,55,55) btn.Text = orig btn.BackgroundColor3 = origCol shopBusy = false return end
	shopStatusLbl.Text = "Purchasing " .. label .. "..." shopStatusLbl.TextColor3 = Color3.fromRGB(175,138,38)
	fireclickdetector(cd, 0, "MouseClick") task.wait(0.35)
	shopStatusLbl.Text = "✓  " .. label .. " purchased!" shopStatusLbl.TextColor3 = Color3.fromRGB(25,190,75)
	btn.Text = "✓" btn.BackgroundColor3 = Color3.fromRGB(20,120,48)
	task.wait(2) shopStatusLbl.Text = "Select an item to purchase" shopStatusLbl.TextColor3 = Color3.fromRGB(64,64,82)
	btn.Text = orig btn.BackgroundColor3 = origCol shopBusy = false
end
for btn, data in pairs(SHOP_ITEMS) do
	local cb, cd2 = btn, data
	cb.MouseButton1Click:Connect(function() task.spawn(function() buyItem(cb, cd2.name, cd2.label) end) end)
end

-- ══ LIVE SCANNER ══
task.spawn(function()
	while true do
		local cashierList = CashierFolder and CashierFolder:GetChildren() or {}
		local avail, broken = 0, 0
		for _, cg in ipairs(cashierList) do
			if isCashierOpen(cg) then avail += 1 if visited[cg] then visited[cg] = nil end
			else broken += 1 end
		end
		atmAvailVal.Text = tostring(avail) atmBrokenVal.Text = tostring(broken)
		detScanLbl.Text = "Last scan: " .. os.date("%H:%M:%S")
		local vaults = findVaults()
		local openV, closedV = 0, 0
		for _, v in ipairs(vaults) do if isVaultOpen(v) then openV += 1 else closedV += 1 end end
		vaultOpenVal.Text = tostring(openV) vaultClosedVal.Text = tostring(closedV)
		vaultScanLbl.Text = "Last scan: " .. os.date("%H:%M:%S")
		task.wait(5)
	end
end)

task.spawn(function()
	while true do
		task.wait(RADIUS_SCAN_INTERVAL)
		if not getgenv().RADIUS_ENABLED then continue end
		if not activeATM or not activeATMPos then continue end
		if isPickingUp or not DropFolder then continue end
		local char = player.Character if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart") if not hrp then continue end
		local currentATMPos = activeATMPos if not currentATMPos then continue end
		local toPickup = {}
		for _, drop in ipairs(DropFolder:GetChildren()) do
			if drop.Name ~= "MoneyDrop" or not drop.Parent then continue end
			local dropPos = drop:IsA("BasePart") and drop.Position or (drop.PrimaryPart and drop.PrimaryPart.Position)
			if not dropPos then continue end
			if (currentATMPos - dropPos).Magnitude <= ATM_RADIUS then
				table.insert(toPickup, {drop = drop, dist = (currentATMPos - dropPos).Magnitude})
			end
		end
		if #toPickup == 0 then continue end
		table.sort(toPickup, function(a, b) return a.dist < b.dist end)
		isPickingUp = true
		for _, entry in ipairs(toPickup) do
			if not activeATMPos then break end
			if not entry.drop.Parent then continue end
			local dv = getDropValue(entry.drop)
			local pos = entry.drop:IsA("BasePart") and entry.drop.Position or (entry.drop.PrimaryPart and entry.drop.PrimaryPart.Position)
			if not pos then continue end
			local cHRP = getHRP() if not cHRP then continue end
			pcall(function() cHRP.CFrame = CFrame.new(pos) * CFrame.new(0, 2, 0) end)
			task.wait(0.05)
			if not entry.drop.Parent then continue end
			local cd3 = entry.drop:FindFirstChildOfClass("ClickDetector")
			if cd3 then fireclickdetector(cd3, 0, "MouseClick")
			else firetouchinterest(cHRP, entry.drop, true) task.wait(0.02) firetouchinterest(cHRP, entry.drop, false) end
			if dv > 0 then totalEarned += dv end
			dropsCollected += 1
			task.wait(0.05)
		end
		local fHRP = getHRP()
		if lastATMCFrame and fHRP then pcall(function() fHRP.CFrame = lastATMCFrame end) end
		isPickingUp = false
	end
end)

local function watchDropFolder()
	if not DropFolder then return end
	DropFolder.ChildAdded:Connect(function(drop)
		if not getgenv().ATM_RUNNING then return end
		if drop.Name ~= "MoneyDrop" then return end
		task.wait(0.03)
		if not drop.Parent then return end
		local pos = drop:IsA("BasePart") and drop.Position or (drop.PrimaryPart and drop.PrimaryPart.Position)
		if not pos then return end
		local hrp = getHRP() if not hrp then return end
		if (hrp.Position - pos).Magnitude > MAX_DROP_DISTANCE then return end
		if not isPickingUp then
			if lastATMCFrame then safeTeleport(lastATMCFrame) task.wait(0.03) end
			pickupDrop(drop)
		end
	end)
end

-- Periodically purge the pickedUpDrops table of drops that no longer exist in workspace.
-- Keeps memory clean — without this the table would grow forever as drops are collected.
task.spawn(function()
	while true do
		task.wait(15)
		for drop in pairs(pickedUpDrops) do
			if not drop.Parent then
				pickedUpDrops[drop] = nil
			end
		end
	end
end)

local function isRunning() return getgenv().ATM_RUNNING == true end
local function getCombatTool()
	local char = player.Character if not char then return nil end
	return char:FindFirstChild("Combat") or player.Backpack:FindFirstChild("Combat")
end

local function heavyPunch(atmHumanoid)
	if not isRunning() then return false, 0 end
	local char = player.Character if not char then return false, 0 end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false, 0 end
	local combat = getCombatTool() if not combat then return false, 0 end
	local hpBefore = atmHumanoid and atmHumanoid.Health or 0
	hum:EquipTool(combat)
	task.wait(HEAVY_PUNCH_WINDUP)
	if not isRunning() then return false, 0 end
	combat:Activate()
	task.wait(HEAVY_PUNCH_HOLD) task.wait(HEAVY_PUNCH_COOLDOWN)
	local hpAfter = atmHumanoid and atmHumanoid.Health or 0
	punchCount += 1
	return true, hpBefore - hpAfter
end

local function disableFastBreak() setFastBreakToggle(false) end

local function doKnifeSwings(atmHumanoid)
	if not ensureKnife() then currentAction = "Knife not found — falling back" disableFastBreak() return false end
	local c2 = player.Character if not c2 or not c2:FindFirstChild("HumanoidRootPart") then return false end
	currentAction = "Fast Break — Knife Swing 1"
	local ok1, _ = knifeHeavySwing(atmHumanoid) if not ok1 then return false end
	if atmHumanoid and atmHumanoid.Health <= 0 then atmCount += 1 currentAction = getgenv().RADIUS_ENABLED and "ATM Broke — Collecting (Radius)" or "ATM Broke — Collecting Cash" return true end
	if not isRunning() then return false end
	local c3 = player.Character if not c3 or not c3:FindFirstChild("HumanoidRootPart") then return false end
	currentAction = "Fast Break — Knife Swing 2"
	local ok2, _ = knifeHeavySwing(atmHumanoid) if not ok2 then return false end
	if atmHumanoid and atmHumanoid.Health <= 0 then atmCount += 1 currentAction = getgenv().RADIUS_ENABLED and "ATM Broke — Collecting (Radius)" or "ATM Broke — Collecting Cash" return true end
	atmsSkipped += 1 currentAction = "Done" return false
end

local function collectDropsAfterBreak(dropsBefore)
	if not DropFolder or not activeATMPos then return end
	local function getNew()
		local nearby = {}
		if not activeATMPos then return nearby end
		for _, drop in ipairs(DropFolder:GetChildren()) do
			if drop.Name ~= "MoneyDrop" or not drop.Parent then continue end
			if dropsBefore[drop] then continue end
			local pos = drop:IsA("BasePart") and drop.Position or (drop.PrimaryPart and drop.PrimaryPart.Position)
			if not pos then continue end
			if (activeATMPos - pos).Magnitude <= ATM_RADIUS then
				table.insert(nearby, {drop = drop, dist = (activeATMPos - pos).Magnitude})
			end
		end
		table.sort(nearby, function(a, b) return a.dist < b.dist end)
		return nearby
	end
	isPickingUp = true
	local nearby = getNew() local wc = 0
	while #nearby == 0 and wc < 8 do task.wait(0.2) wc += 1 nearby = getNew() end
	while #nearby > 0 do
		if not isRunning() or not activeATMPos then break end
		for _, entry in ipairs(nearby) do
			if not isRunning() or not activeATMPos then break end
			if not entry.drop.Parent then continue end
			pickupDrop(entry.drop) task.wait(0.04)
		end
		nearby = getNew()
	end
	isPickingUp = false
end

-- ══ CORE ATM HIT FUNCTION ══
-- Hidden Farm Mode logic:
--   1. Call findHiddenCFrame to get raycast-based position below the ATM.
--   2. If valid: use it, enable PlatformStand, mark usingHidden = true.
--   3. PlatformStand prevents physics from fighting the heartbeat CFrame lock.
--   4. If no damage after MAX_NO_DAMAGE_PUNCHES while hidden:
--        → flag this group as failed, immediately switch to normal position,
--          continue the fight from normal spot (no ATM is skipped).
--   5. After ATM breaks: restore PlatformStand = false.
--   6. Next visit to same group uses normal position (hiddenFailedGroups entry).
local function hitATM(cashierGroup, wedgeBlock)
	if not isRunning() then return end
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end
	local atmHumanoid = cashierGroup:FindFirstChildOfClass("Humanoid")
	local normalCF = wedgeBlock.CFrame * getATMOffset(cashierGroup)
	local usingHidden = false

	if getgenv().HIDDEN_FARM then
		local hiddenCF = findHiddenCFrame(cashierGroup, wedgeBlock)
		if hiddenCF then
			lastATMCFrame = hiddenCF
			usingHidden = true
			currentAction = "Hidden Farm — Moving Below ATM"
		else
			lastATMCFrame = normalCF
			currentAction = "Hidden unavailable — Normal Position"
		end
	else
		lastATMCFrame = normalCF
		currentAction = "Teleporting to ATM"
	end

	activeATM = cashierGroup
	activeATMPos = getATMPosition(cashierGroup) or wedgeBlock.Position

	local hum = getHum()
	if usingHidden and hum then hum.PlatformStand = true end

	local lockConn = RunService.Heartbeat:Connect(function()
		if not isRunning() then return end
		local hrp = getHRP()
		if hrp then pcall(function() hrp.CFrame = lastATMCFrame end) end
	end)

	task.wait(0.3)
	local dropsBefore = snapshotDrops()

	local function restorePhysics()
		if usingHidden then
			local h2 = getHum()
			if h2 then h2.PlatformStand = false end
		end
	end

	if getgenv().FAST_BREAK then
		local broke = doKnifeSwings(atmHumanoid)
		lockConn:Disconnect() restorePhysics()
		if not isRunning() then activeATM = nil activeATMPos = nil return end
		if broke then task.wait(0.2) collectDropsAfterBreak(dropsBefore) end
	else
		currentAction = usingHidden and "Hidden Farm — Punching" or "Punching ATM"
		local pn, nds = 0, 0
		while atmHumanoid and atmHumanoid.Health > 0 and isRunning() do
			local c2 = player.Character
			if not c2 or not c2:FindFirstChild("HumanoidRootPart") then task.wait(2) break end
			pn += 1
			local ok, dmg = heavyPunch(atmHumanoid)
			if not ok then break end
			if dmg <= 0 then
				nds += 1
				-- If hidden and can't deal damage: flag group, switch to normal, keep going
				if usingHidden and nds >= MAX_NO_DAMAGE_PUNCHES then
					hiddenFailedGroups[cashierGroup] = true
					usingHidden = false
					lastATMCFrame = normalCF
					restorePhysics()
					currentAction = "Hidden failed — Switching to Normal"
					nds = 0  -- reset no-damage counter so normal position gets a fair shot
				elseif not usingHidden and nds >= MAX_NO_DAMAGE_PUNCHES then
					atmsSkipped += 1 currentAction = "Done" break
				end
			else nds = 0 end
			if atmHumanoid.Health <= 0 then
				atmCount += 1
				currentAction = getgenv().RADIUS_ENABLED and "ATM Broke — Collecting (Radius)" or "ATM Broke — Collecting Cash"
				break
			end
		end
		lockConn:Disconnect() restorePhysics()
		if not isRunning() then activeATM = nil activeATMPos = nil return end
		task.wait(0.2) collectDropsAfterBreak(dropsBefore)
	end

	currentAction = "Done"
	activeATM = nil activeATMPos = nil
	task.wait(0.15) safeTeleport(lastATMCFrame) task.wait(0.15)
	currentAction = "Scanning for ATMs"
end

local function hitATMs()
	if getgenv().FAST_BREAK and not hasKnife() then currentAction = "Buying Knife..." ensureKnife() end
	local cashierList = CashierFolder and CashierFolder:GetChildren() or {}
	for _, cg in ipairs(cashierList) do
		if not isRunning() then break end
		if visited[cg] then continue end
		if not isCashierOpen(cg) then currentAction = "Scanning for ATMs" continue end
		visited[cg] = true
		local wb = cg:FindFirstChild("Wedge")
		if not wb then continue end
		hitATM(cg, wb)
	end
end

local function startFarmLoop()
	task.spawn(function()
		watchDropFolder()
		while getgenv().ATM_STARTED do
			if getgenv().ATM_RUNNING then
				local char = player.Character
				if not char or not char:FindFirstChild("HumanoidRootPart") then
					currentAction = "Waiting for respawn..." task.wait(3) continue
				end
				local hum2 = char:FindFirstChildOfClass("Humanoid")
				if hum2 and hum2.Health <= 0 then
					currentAction = "Dead — waiting to respawn..." task.wait(3) continue
				end
				currentAction = "Scanning for ATMs"
				-- Clear failed groups at start of each new loop — ATMs may have reset
				clearHiddenFailed()
				visited = {} hitATMs()
				if getgenv().ATM_RUNNING then
					currentAction = "Waiting for ATMs to reset..."
					local ws = os.time()
					while os.time() - ws < 30 do if not getgenv().ATM_STARTED then break end task.wait(1) end
				end
			else task.wait(0.5) end
		end
		UpdatePlayerStatus("idle")
	end)
end

toggleBtn.MouseButton1Click:Connect(function()
	if not getgenv().ATM_STARTED then
		getgenv().ATM_STARTED = true getgenv().ATM_RUNNING = true
		farmStart = os.time()
		toggleBtn.BackgroundColor3 = Color3.fromRGB(165, 32, 32)
		toggleBtn.Text = "⏸  PAUSE FARMING"
		currentAction = "Scanning for ATMs"
		startFarmLoop()
	else
		getgenv().ATM_RUNNING = not getgenv().ATM_RUNNING
		if getgenv().ATM_RUNNING then
			farmStart = os.time()
			toggleBtn.BackgroundColor3 = Color3.fromRGB(165, 32, 32)
			toggleBtn.Text = "⏸  PAUSE FARMING"
			currentAction = "Scanning for ATMs"
		else
			if farmStart then totalElapsed += os.time() - farmStart farmStart = nil end
			toggleBtn.BackgroundColor3 = Color3.fromRGB(25, 175, 65)
			toggleBtn.Text = "▶  RESUME FARMING"
			currentAction = "Paused"
			local h = getHum() if h then h.PlatformStand = false end
		end
	end
end)

RunService.Heartbeat:Connect(function()
	pcall(function()
		local elapsed = getElapsed()
		local mins = math.max(elapsed / 60, 0.016)
		local rate = totalEarned / mins
		earningsBig.Text = formatMoney(totalEarned)
		runtimeLbl.Text  = getgenv().ATM_STARTED and formatTime(elapsed) or "Not started"
		earnRateLbl.Text = getgenv().ATM_STARTED and (formatMoney(math.floor(rate)) .. "/min") or "$0/min"
		punchVal.Text    = tostring(punchCount)
		dropsVal.Text    = tostring(dropsCollected)
		skippedVal.Text  = tostring(atmsSkipped)
		earnRateVal.Text = getgenv().ATM_STARTED and (formatMoney(math.floor(rate)) .. "/min") or "$0/min"
		earnRateVal.TextColor3 = getgenv().ATM_STARTED and Color3.fromRGB(25, 190, 75) or Color3.fromRGB(210, 210, 222)
		actionLbl.Text = currentAction
		if getgenv().ATM_RUNNING then UpdatePlayerStatus("active", currentAction)
		elseif getgenv().ATM_STARTED then UpdatePlayerStatus("paused")
		else UpdatePlayerStatus("idle") end
	end)
end)
