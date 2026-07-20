-- ATM Farmer — Main Loader v2.0
local KeySystem = (function()
-- ══════════════════════════════════════════════════════════════
-- Dev by wraith - ATM AUTO FARM DH
-- ══════════════════════════════════════════════════════════════
return function(onSuccess)

local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")

-- ── CONFIG ────────────────────────────────────────────────────
local DISCORD_URL = "https://discord.gg/uCUSZeuM48"
local PREMIUM_URL = "https://discord.gg/uCUSZeuM48"

-- ── JUNKIE CONFIG ─────────────────────────────────────────────
local JUNKIE_SERVICE    = "ATMFARM"
local JUNKIE_IDENTIFIER = "1158702"
local JUNKIE_PROVIDER   = "FreeKey"
local SCRIPT_VER  = "v1.0.0"

-- ── JUNKIE SDK ────────────────────────────────────────────────
local Junkie = nil
local junkieLoaded = false
task.spawn(function()
	local ok, lib = pcall(function()
		return loadstring(game:HttpGet("https://jnkie.com/sdk/library.lua"))()
	end)
	if ok and lib then
		lib.service    = JUNKIE_SERVICE
		lib.identifier = JUNKIE_IDENTIFIER
		lib.provider   = JUNKIE_PROVIDER
		-- Tell Junkie our UI handles validation — skip its second key check
		if lib.Options then
			lib.Options.KeylessUI = true
		end
		Junkie = lib
	end
	junkieLoaded = true
end)
local BUILD_TAG   = "Stable"
local KEY_FILE    = "atm_farmer_key.txt"

local TIER_LABELS = {
	trial   = { label = "1-Hour Trial",    color = Color3.fromRGB(255, 200, 50)  },
	["3day"]= { label = "3-Day License",   color = Color3.fromRGB(80,  160, 220) },
	weekly  = { label = "Weekly License",  color = Color3.fromRGB(160, 80,  230) },
	monthly = { label = "Monthly License", color = Color3.fromRGB(34,  197, 94)  },
}
local TIER_DEFAULT = { label = "Standard License", color = Color3.fromRGB(34, 197, 94) }

-- ── assets/logos ───────────────────────────────────────────────────
local A_KEY     = "rbxassetid://97349417836855"
local A_DISCORD = "rbxassetid://98177077986517"
local A_PREMIUM = "rbxassetid://133983664763379"
local A_CHECK   = "rbxassetid://126043749901452"

local C_BG      = Color3.fromRGB(10,  10,  13)
local C_CARD    = Color3.fromRGB(17,  17,  22)
local C_CARD2   = Color3.fromRGB(22,  22,  28)
local C_INPUT   = Color3.fromRGB(14,  14,  18)
local C_GREEN   = Color3.fromRGB(34,  197, 94)
local C_GHOVER  = Color3.fromRGB(52,  220, 115)
local C_GDARK   = Color3.fromRGB(20,  100, 52)
local C_GBG     = Color3.fromRGB(12,  34,  20)
local C_WHITE   = Color3.fromRGB(235, 235, 245)
local C_SUB     = Color3.fromRGB(100, 100, 122)
local C_BORDER  = Color3.fromRGB(30,  30,  40)
local C_YELLOW  = Color3.fromRGB(255, 200, 50)
local C_RED     = Color3.fromRGB(220, 55,  55)
local C_BLUE    = Color3.fromRGB(88,  101, 242)
local C_GOLD    = Color3.fromRGB(212, 175, 55)


local function ti(t, s, d)
	return TweenInfo.new(t or 0.2, s or Enum.EasingStyle.Quad, d or Enum.EasingDirection.Out)
end
local function tw(o, t, p, s, d)
	local tween = TweenService:Create(o, ti(t, s, d), p)
	tween:Play()
	return tween
end

-- ── ui fac helpers ────────────────────────────────────────
local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = p
	return c
end
local function mkStroke(p, col, th)
	local s = Instance.new("UIStroke")
	s.Color = col or C_BORDER
	s.Thickness = th or 1
	s.Parent = p
	return s
end
local function pad(p, t, b, l, r)
	local x = Instance.new("UIPadding")
	x.PaddingTop    = UDim.new(0, t or 0)
	x.PaddingBottom = UDim.new(0, b or 0)
	x.PaddingLeft   = UDim.new(0, l or 0)
	x.PaddingRight  = UDim.new(0, r or 0)
	x.Parent = p
end
local function vlist(p, px, ha)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, px or 0)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = Enum.FillDirection.Vertical
	if ha then l.HorizontalAlignment = ha end
	l.Parent = p
	return l
end
local function hlist(p, px, va)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, px or 0)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = Enum.FillDirection.Horizontal
	if va then l.VerticalAlignment = va end
	l.Parent = p
	return l
end
local function spacer(parent, order, h)
	local s = Instance.new("Frame")
	s.Size = UDim2.new(1, 0, 0, h or 8)
	s.BackgroundTransparency = 1
	s.LayoutOrder = order
	s.Parent = parent
end
local function mkLbl(p, text, size, col, font, xa, order, h)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size or 13
	l.TextColor3 = col or C_WHITE
	l.Font = font or Enum.Font.Gotham
	l.TextXAlignment = xa or Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Size = UDim2.new(1, 0, 0, h or (size or 13) + 8)
	if order then l.LayoutOrder = order end
	l.Parent = p
	return l
end
local function mkImg(p, id, sz, pos, col)
	local i = Instance.new("ImageLabel")
	i.Image = id
	i.BackgroundTransparency = 1
	i.Size = sz or UDim2.new(0, 20, 0, 20)
	if pos then i.Position = pos end
	if col then i.ImageColor3 = col end
	i.ScaleType = Enum.ScaleType.Fit
	i.Parent = p
	return i
end

-- Hover button grow effect using UIScale
local function addHoverGrow(btn, scaleUp, strokeColor)
	local us = Instance.new("UIScale")
	us.Scale = 1
	us.Parent = btn
	btn.MouseEnter:Connect(function()
		tw(us, 0.12, {Scale = scaleUp or 1.04}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if strokeColor then
			local s = btn:FindFirstChildOfClass("UIStroke")
			if s then tw(s, 0.12, {Color = strokeColor}) end
		end
	end)
	btn.MouseLeave:Connect(function()
		tw(us, 0.12, {Scale = 1})
		if strokeColor then
			local s = btn:FindFirstChildOfClass("UIStroke")
			if s then tw(s, 0.12, {Color = C_BORDER}) end
		end
	end)
	btn.MouseButton1Down:Connect(function()
		tw(us, 0.08, {Scale = 0.97})
	end)
	btn.MouseButton1Up:Connect(function()
		tw(us, 0.12, {Scale = 1.04})
	end)
	return us
end

-- Stagger-in system
local staggerIdx = 0
local function staggerIn(cg, baseDelay)
	cg.GroupTransparency = 1
	local delay = (baseDelay or 0.12) + staggerIdx * 0.07
	task.delay(delay, function()
		if cg and cg.Parent then
			tw(cg, 0.28, {GroupTransparency = 0}, Enum.EasingStyle.Quint)
		end
	end)
	staggerIdx += 1
end

-- URL opener
local function openURL(url)
	pcall(function() setclipboard(url) end)
	pcall(function()
		if syn and syn.open_url_via_roblox then syn.open_url_via_roblox(url)
		else game:GetService("GuiService"):OpenBrowserWindow(url) end
	end)
end

local function saveKey(k) pcall(function() writefile(KEY_FILE, k) end) end
local function loadKey()
	local ok, v = pcall(function()
		if isfile and isfile(KEY_FILE) then return readfile(KEY_FILE) end
	end)
	return ok and v or nil
end

local function fmtTimeLeft(secs)
	secs = tonumber(secs) or 0
	if secs <= 0 then return "Expired" end
	local d = math.floor(secs / 86400)
	local h = math.floor((secs % 86400) / 3600)
	local m = math.floor((secs % 3600) / 60)
	if d > 0 then return d .. "d " .. h .. "h remaining"
	elseif h > 0 then return h .. "h " .. m .. "m remaining"
	else return m .. "m remaining" end
end

local function fmtDate(ts)
	ts = tonumber(ts)
	if not ts then return "Unknown" end
	return os.date("%b %d, %Y", ts)
end

-- ── JUNKIE VALIDATION ────────────────────────────────────────
local function validateKey(key, cb)
	key = key:gsub("^%s+", ""):gsub("%s+$", "")
	if key == "" then cb(false, "Key cannot be empty.", nil) return end
	task.spawn(function()
		-- Wait for Junkie SDK to finish loading (it loads async above)
		local waited = 0
		while not junkieLoaded and waited < 8 do
			task.wait(0.1)
			waited += 0.1
		end

		if not Junkie then
			cb(false, "Failed to load auth library. Check your connection.", nil)
			return
		end

		local result
		local ok = pcall(function()
			result = Junkie.check_key(key)
		end)

		if not ok or not result then
			cb(false, "Failed to reach auth server.", nil)
			return
		end

		if result.valid then
			-- Junkie free keys = trial tier
			-- Treat all Junkie keys as free trial since premium goes through KeyAuth
			cb(true, "Key verified!", {
				tier = "trial",
				tierlabel = "Free Trial",
				tiercolor = Color3.fromRGB(255, 200, 50),
				expiry = 0,
				timeleft = 3600,
			})
		else
			local err = result.error or "Unknown error"
			if err == "KEY_INVALID" then
				cb(false, "Invalid key — key not found.", nil)
			elseif err == "KEY_EXPIRED" then
				cb(false, "This key has expired. Get a new one.", nil)
			elseif err == "HWID_BANNED" then
				game.Players.LocalPlayer:Kick("You have been hardware banned.")
				cb(false, "Hardware banned.", nil)
			elseif err == "KEY_INVALIDATED" then
				cb(false, "This key has been disabled by staff.", nil)
			elseif err == "ALREADY_USED" then
				cb(false, "This key has already been used.", nil)
			elseif err == "HWID_MISMATCH" then
				cb(false, "HWID limit reached — key locked to another device.", nil)
			elseif err == "SERVICE_NOT_FOUND" then
				cb(false, "Auth service not found. Contact support.", nil)
			elseif err == "SERVICE_MISMATCH" then
				cb(false, "This key is for a different service.", nil)
			elseif err == "PREMIUM_REQUIRED" then
				cb(false, "A premium key is required.", nil)
			elseif err == "ERROR" then
				cb(false, "Network error — please try again.", nil)
			else
				cb(false, "Auth error: " .. tostring(err), nil)
			end
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════
-- GUI BUILD
-- ═══════════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "ATMKeySystem"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 200
local _ok, _p = pcall(function() return gethui() end)
gui.Parent = (_ok and _p) or game:GetService("CoreGui")

-- Overlay
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Parent = gui
tw(overlay, 0.4, {BackgroundTransparency = 0.55}, Enum.EasingStyle.Quad)

-- Modal
local modal = Instance.new("CanvasGroup")
modal.Size = UDim2.new(0, 570, 0, 0)
modal.AutomaticSize = Enum.AutomaticSize.Y
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.Position = UDim2.new(0.5, 0, 0.5, 0)
modal.BackgroundColor3 = C_BG
modal.BorderSizePixel = 0
modal.Active = true
modal.Draggable = true
modal.GroupTransparency = 1
modal.Parent = gui
corner(modal, 16)
mkStroke(modal, C_BORDER, 1)
vlist(modal, 0)
pad(modal, 20, 22, 22, 22)

-- Open animation: scale 0.95 → 1 + fade in
local modalScale = Instance.new("UIScale")
modalScale.Scale = 0.95
modalScale.Parent = modal
task.delay(0.05, function()
	tw(modal, 0.4, {GroupTransparency = 0}, Enum.EasingStyle.Quint)
	tw(modalScale, 0.4, {Scale = 1}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end)

-- ── CLOSE BUTTON (absolute, top-right) ────────────────────────
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -36, 0, 20)
closeBtn.AnchorPoint = Vector2.new(0, 0)
closeBtn.BackgroundColor3 = C_CARD2
closeBtn.Text = "x"
closeBtn.TextColor3 = C_SUB
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 10
closeBtn.Parent = modal
corner(closeBtn, 8)
mkStroke(closeBtn, C_BORDER)
addHoverGrow(closeBtn)
closeBtn.MouseEnter:Connect(function()
	tw(closeBtn, 0.12, {BackgroundColor3 = Color3.fromRGB(35, 35, 46), TextColor3 = C_WHITE})
end)
closeBtn.MouseLeave:Connect(function()
	tw(closeBtn, 0.12, {BackgroundColor3 = C_CARD2, TextColor3 = C_SUB})
end)
closeBtn.MouseButton1Click:Connect(function()
	tw(modal,   0.22, {GroupTransparency = 1})
	tw(overlay, 0.22, {BackgroundTransparency = 1})
	task.wait(0.25)
	gui:Destroy()
end)

-- ── SECTION 1: LOGO + TITLE ────────────────────────────────────
local headerCG = Instance.new("CanvasGroup")
headerCG.Size = UDim2.new(1, 0, 0, 0)
headerCG.AutomaticSize = Enum.AutomaticSize.Y
headerCG.BackgroundTransparency = 1
headerCG.LayoutOrder = 1
headerCG.Parent = modal
staggerIn(headerCG, 0.15)
vlist(headerCG, 0, Enum.HorizontalAlignment.Center)

-- Glow circle behind logo (pulses)
local glowWrap = Instance.new("Frame")
glowWrap.Size = UDim2.new(0, 76, 0, 76)
glowWrap.BackgroundTransparency = 1
glowWrap.LayoutOrder = 1
glowWrap.Parent = headerCG

local glowCircle = Instance.new("Frame")
glowCircle.Size = UDim2.new(0, 76, 0, 76)
glowCircle.BackgroundColor3 = C_GREEN
glowCircle.BackgroundTransparency = 0.82
glowCircle.BorderSizePixel = 0
glowCircle.Parent = glowWrap
corner(glowCircle, 38)

-- Logo circle (sits on top of glow)
local logoCircle = Instance.new("Frame")
logoCircle.Size = UDim2.new(0, 58, 0, 58)
logoCircle.Position = UDim2.new(0.5, -29, 0.5, -29)
logoCircle.BackgroundColor3 = C_GBG
logoCircle.BorderSizePixel = 0
logoCircle.Parent = glowWrap
corner(logoCircle, 29)
mkStroke(logoCircle, C_GDARK, 1.5)
mkImg(logoCircle, A_KEY, UDim2.new(0, 30, 0, 30), UDim2.new(0.5, -15, 0.5, -15))

-- Floating animation on logo (sine wave Y offset)
local logoBaseY = 0
local logoFloatConn = RunService.Heartbeat:Connect(function()
	if not gui.Parent then return end
	local t = tick()
	local floatY = math.sin(t * 1.2) * 4  -- 4px float range, 1.2 rad/s
	glowWrap.Position = UDim2.new(0, 0, 0, floatY)
end)

-- Glow pulse
task.spawn(function()
	while gui.Parent do
		tw(glowCircle, 1.4, {BackgroundTransparency = 0.75}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		task.wait(1.4)
		tw(glowCircle, 1.4, {BackgroundTransparency = 0.88}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		task.wait(1.4)
	end
end)

spacer(headerCG, 2, 14)

local titleLbl = mkLbl(headerCG, "Key System", 22, C_WHITE, Enum.Font.GothamBold,
	Enum.TextXAlignment.Center, 3, 32)

local subtitleLbl = mkLbl(headerCG, "A key is required to use the Autofarm Script.",
	13, C_SUB, Enum.Font.Gotham, Enum.TextXAlignment.Center, 4, 20)

spacer(headerCG, 5, 6)

-- ── DIVIDER ───────────────────────────────────────────────────
local div1 = Instance.new("Frame")
div1.Size = UDim2.new(1, 0, 0, 1)
div1.BackgroundColor3 = C_BORDER
div1.BorderSizePixel = 0
div1.LayoutOrder = 2
div1.Parent = modal

spacer(modal, 3, 12)

-- ── SECTION 2: DISCORD BANNER ─────────────────────────────────
local bannerCG = Instance.new("CanvasGroup")
bannerCG.Size = UDim2.new(1, 0, 0, 0)
bannerCG.AutomaticSize = Enum.AutomaticSize.Y
bannerCG.BackgroundColor3 = C_CARD
bannerCG.BorderSizePixel = 0
bannerCG.LayoutOrder = 4
bannerCG.Parent = modal
corner(bannerCG, 12)
mkStroke(bannerCG, C_BORDER)
staggerIn(bannerCG)

-- Green accent bar
local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(0, 3, 1, 0)
accentBar.BackgroundColor3 = C_GREEN
accentBar.BorderSizePixel = 0
accentBar.ZIndex = 3
accentBar.Parent = bannerCG
corner(accentBar, 2)

local bannerInner = Instance.new("Frame")
bannerInner.Size = UDim2.new(1, 0, 0, 64)
bannerInner.BackgroundTransparency = 1
bannerInner.LayoutOrder = 1
bannerInner.Parent = bannerCG
pad(bannerInner, 14, 14, 16, 16)
hlist(bannerInner, 14, Enum.VerticalAlignment.Center)

-- Discord icon
local discCircle = Instance.new("Frame")
discCircle.Size = UDim2.new(0, 44, 0, 44)
discCircle.BackgroundColor3 = Color3.fromRGB(22, 26, 50)
discCircle.BorderSizePixel = 0
discCircle.LayoutOrder = 1
discCircle.Parent = bannerInner
corner(discCircle, 22)
mkImg(discCircle, A_DISCORD, UDim2.new(0, 26, 0, 26), UDim2.new(0.5, -13, 0.5, -13))

-- Discord text block
local discTextBlock = Instance.new("Frame")
discTextBlock.Size = UDim2.new(1, -212, 1, 0)
discTextBlock.BackgroundTransparency = 1
discTextBlock.LayoutOrder = 2
discTextBlock.Parent = bannerInner
vlist(discTextBlock, 3)
pad(discTextBlock, 4, 0, 0, 0)
local dTitle = mkLbl(discTextBlock, "Join our Discord!", 14, C_WHITE, Enum.Font.GothamBold,
	Enum.TextXAlignment.Left, 1, 18)
local dSub = Instance.new("TextLabel")
dSub.Size = UDim2.new(1, 0, 0, 28)
dSub.BackgroundTransparency = 1
dSub.Text = "Get support, updates, and purchase license keys."
dSub.TextSize = 12 dSub.TextColor3 = C_SUB dSub.Font = Enum.Font.Gotham
dSub.TextXAlignment = Enum.TextXAlignment.Left dSub.TextWrapped = true
dSub.LayoutOrder = 2 dSub.Parent = discTextBlock

-- Join Discord button
local joinBtn = Instance.new("TextButton")
joinBtn.Size = UDim2.new(0, 148, 0, 38)
joinBtn.BackgroundColor3 = C_GREEN
joinBtn.Text = "  Join Discord"
joinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
joinBtn.TextSize = 13 joinBtn.Font = Enum.Font.GothamBold joinBtn.BorderSizePixel = 0
joinBtn.LayoutOrder = 3 joinBtn.Parent = bannerInner
corner(joinBtn, 9)
mkImg(joinBtn, A_DISCORD, UDim2.new(0, 15, 0, 15), UDim2.new(0, 10, 0.5, -8))
joinBtn.MouseEnter:Connect(function() tw(joinBtn, 0.15, {BackgroundColor3 = C_GHOVER}) end)
joinBtn.MouseLeave:Connect(function() tw(joinBtn, 0.15, {BackgroundColor3 = C_GREEN}) end)
addHoverGrow(joinBtn)
joinBtn.MouseButton1Click:Connect(function()
	openURL(DISCORD_URL)
	local orig = joinBtn.Text
	joinBtn.Text = "  ✓  Copied!"
	task.delay(1.8, function()
		if joinBtn and joinBtn.Parent then joinBtn.Text = orig end
	end)
end)

spacer(modal, 5, 14)

-- ── SECTION 3: GET YOUR KEY ────────────────────────────────────
local gkCG = Instance.new("CanvasGroup")
gkCG.Size = UDim2.new(1, 0, 0, 0)
gkCG.AutomaticSize = Enum.AutomaticSize.Y
gkCG.BackgroundTransparency = 1
gkCG.LayoutOrder = 6
gkCG.Parent = modal
staggerIn(gkCG)
vlist(gkCG, 10)

-- Section header
local gkHeaderRow = Instance.new("Frame")
gkHeaderRow.Size = UDim2.new(1, 0, 0, 20)
gkHeaderRow.BackgroundTransparency = 1
gkHeaderRow.LayoutOrder = 1
gkHeaderRow.Parent = gkCG
hlist(gkHeaderRow, 8, Enum.VerticalAlignment.Center)
local gkIco = mkImg(gkHeaderRow, A_KEY, UDim2.new(0, 16, 0, 16), nil, C_GREEN)
gkIco.LayoutOrder = 1
local gkTitle = Instance.new("TextLabel")
gkTitle.Size = UDim2.new(0, 200, 1, 0)
gkTitle.BackgroundTransparency = 1
gkTitle.Text = "Get Your Key"
gkTitle.TextSize = 15 gkTitle.TextColor3 = C_WHITE gkTitle.Font = Enum.Font.GothamBold
gkTitle.TextXAlignment = Enum.TextXAlignment.Left gkTitle.LayoutOrder = 2 gkTitle.Parent = gkHeaderRow

mkLbl(gkCG, "Choose how you would like to obtain your key.", 12, C_SUB,
	Enum.Font.Gotham, Enum.TextXAlignment.Left, 2, 16)

-- Thin divider
local gkDiv = Instance.new("Frame")
gkDiv.Size = UDim2.new(1, 0, 0, 1)
gkDiv.BackgroundColor3 = C_BORDER gkDiv.BorderSizePixel = 0 gkDiv.LayoutOrder = 3 gkDiv.Parent = gkCG

-- Cards row
local cardsRow = Instance.new("Frame")
cardsRow.Size = UDim2.new(1, 0, 0, 0)
cardsRow.AutomaticSize = Enum.AutomaticSize.Y
cardsRow.BackgroundTransparency = 1
cardsRow.LayoutOrder = 4
cardsRow.Parent = gkCG
local _cardsGrid = Instance.new("UIGridLayout")
_cardsGrid.CellSize = UDim2.new(0.333, -9, 0, 186)
_cardsGrid.CellPadding = UDim2.new(0, 12, 0, 0)
_cardsGrid.SortOrder = Enum.SortOrder.LayoutOrder
_cardsGrid.FillDirectionMaxCells = 3
_cardsGrid.Parent = cardsRow
cardsRow.Size = UDim2.new(1, -4, 0, 192)
cardsRow.Position = UDim2.new(0, 2, 0, 0)
cardsRow.AutomaticSize = Enum.AutomaticSize.None
local _cardsRowPad = Instance.new("UIPadding", cardsRow)
_cardsRowPad.PaddingTop    = UDim.new(0, 3)
_cardsRowPad.PaddingBottom = UDim.new(0, 3)
_cardsRowPad.PaddingLeft   = UDim.new(0, 2)
_cardsRowPad.PaddingRight  = UDim.new(0, 2)

-- Equalizer: 3 cards each exactly 1/3 width minus padding
local function makeOptionCard(order, iconId, title, desc, btnTxt, btnColor, btnTextColor, hoverColor, btnCb, iconBgColor, cardHoverColor)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)  -- grid controls size
	card.AutomaticSize = Enum.AutomaticSize.None
	card.BackgroundColor3 = C_CARD
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Parent = cardsRow
	corner(card, 12)
	local cardStroke = mkStroke(card, C_BORDER)
	vlist(card, 0, Enum.HorizontalAlignment.Center)
	pad(card, 14, 12, 14, 14)

	-- Icon circle
	local icoCircle = Instance.new("Frame")
	icoCircle.Size = UDim2.new(0, 42, 0, 42)
	icoCircle.BackgroundColor3 = iconBgColor or C_GBG
	icoCircle.BorderSizePixel = 0
	icoCircle.LayoutOrder = 1
	icoCircle.Parent = card
	corner(icoCircle, 21)
	local il = Instance.new("UIListLayout", icoCircle)
	il.HorizontalAlignment = Enum.HorizontalAlignment.Center
	il.VerticalAlignment = Enum.VerticalAlignment.Center
	local iImg = mkImg(icoCircle, iconId, UDim2.new(0, 20, 0, 20))
	iImg.LayoutOrder = 1

	spacer(card, 2, 7)
	local ct = mkLbl(card, title, 13, C_WHITE, Enum.Font.GothamBold,
		Enum.TextXAlignment.Center, 3, 15)
	spacer(card, 4, 4)
	local cd = Instance.new("TextLabel")
	cd.Size = UDim2.new(1, 0, 0, 38)
	cd.AutomaticSize = Enum.AutomaticSize.None
	cd.BackgroundTransparency = 1 cd.Text = desc
	cd.TextSize = 11 cd.TextColor3 = C_SUB cd.Font = Enum.Font.Gotham
	cd.TextXAlignment = Enum.TextXAlignment.Center cd.TextWrapped = true
	cd.LayoutOrder = 5 cd.Parent = card
	spacer(card, 6, 7)

	-- Button
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 30)
	btn.BackgroundColor3 = btnColor or C_GBG
	btn.Text = btnTxt
	btn.TextColor3 = btnTextColor or C_GREEN
	btn.TextSize = 11 btn.Font = Enum.Font.GothamBold btn.BorderSizePixel = 0
	btn.LayoutOrder = 7 btn.Parent = card
	corner(btn, 8)
	mkStroke(btn, C_BORDER)
	btn.MouseEnter:Connect(function()
		tw(btn, 0.14, {BackgroundColor3 = hoverColor or Color3.fromRGB(18, 52, 28)})
		tw(cardStroke, 0.14, {Color = (btnTextColor or C_GREEN), Thickness = 1})
	end)
	btn.MouseLeave:Connect(function()
		tw(btn, 0.14, {BackgroundColor3 = btnColor or C_GBG})
		tw(cardStroke, 0.14, {Color = C_BORDER, Thickness = 1})
	end)
	addHoverGrow(btn)
	btn.MouseButton1Click:Connect(function()
		btnCb()
		-- Flash "Copied!" feedback since openURL calls setclipboard
		local origTxt = btn.Text
		local origCol = btn.TextColor3
		btn.Text = "  ✓  Copied!"
		tw(btn, 0.1, {TextColor3 = C_GREEN})
		task.delay(1.8, function()
			if btn and btn.Parent then
				btn.Text = origTxt
				tw(btn, 0.1, {TextColor3 = origCol})
			end
		end)
	end)

	-- Card hover
	card.MouseEnter:Connect(function()
		tw(card, 0.15, {BackgroundColor3 = cardHoverColor or Color3.fromRGB(21, 21, 27)})
	end)
	card.MouseLeave:Connect(function()
		tw(card, 0.15, {BackgroundColor3 = C_CARD})
	end)
end

makeOptionCard(1, A_KEY, "Get Key", "Free 1-hour trial available.\nComplete an offer to get access.",
	"🔑  Get Key", C_GBG, C_GREEN, Color3.fromRGB(16, 50, 26),
	function()
		task.spawn(function()
			if not Junkie then
				-- SDK still loading, fall back to Discord
				openURL(DISCORD_URL)
				return
			end
			local link, err = Junkie.get_key_link()
			if link then
				openURL(link)
			elseif err == "RATE_LIMITED" then
				-- Show rate limit message in status area
				setStatus("err", "Rate limited — wait 5 minutes then try again.")
			else
				openURL(DISCORD_URL)
			end
		end)
	end,
	C_GBG, Color3.fromRGB(16, 20, 17))

makeOptionCard(2, A_PREMIUM, "Premium", "Buy a key for full access,\nexclusive features & more.",
	"★  Buy Key", Color3.fromRGB(30, 26, 12), C_GOLD, Color3.fromRGB(38, 32, 12),
	function() openURL(PREMIUM_URL) end,
	Color3.fromRGB(30, 26, 10), Color3.fromRGB(20, 18, 10))

makeOptionCard(3, A_DISCORD, "Join Discord", "Join for support, updates\n& announcements.",
	"  Join Discord", Color3.fromRGB(58, 65, 180), Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(72, 80, 210),
	function() openURL(DISCORD_URL) end,
	Color3.fromRGB(20, 22, 55),   -- icon circle bg: dark blurple
	Color3.fromRGB(16, 17, 38))   -- card hover: deeper dark blurple

spacer(modal, 7, 14)

-- ── SECTION 4: ENTER KEY ──────────────────────────────────────
local ekCG = Instance.new("CanvasGroup")
ekCG.Size = UDim2.new(1, 0, 0, 0)
ekCG.AutomaticSize = Enum.AutomaticSize.Y
ekCG.BackgroundTransparency = 1
ekCG.LayoutOrder = 8
ekCG.Parent = modal
staggerIn(ekCG)
vlist(ekCG, 10)

local ekHead = Instance.new("Frame")
ekHead.Size = UDim2.new(1, 0, 0, 20)
ekHead.BackgroundTransparency = 1
ekHead.LayoutOrder = 1
ekHead.Parent = ekCG
hlist(ekHead, 8, Enum.VerticalAlignment.Center)
local ekIco = mkImg(ekHead, A_KEY, UDim2.new(0, 16, 0, 16), nil, C_GREEN)
ekIco.LayoutOrder = 1
local ekTitle = Instance.new("TextLabel")
ekTitle.Size = UDim2.new(0, 180, 1, 0)
ekTitle.BackgroundTransparency = 1
ekTitle.Text = "Enter Key"
ekTitle.TextSize = 15 ekTitle.TextColor3 = C_WHITE ekTitle.Font = Enum.Font.GothamBold
ekTitle.TextXAlignment = Enum.TextXAlignment.Left ekTitle.LayoutOrder = 2 ekTitle.Parent = ekHead

mkLbl(ekCG, "Paste your key below and click Verify.", 12, C_SUB,
	Enum.Font.Gotham, Enum.TextXAlignment.Left, 2, 16)

-- Input + button row
local inputRow = Instance.new("Frame")
inputRow.Size = UDim2.new(1, -4, 0, 54)
inputRow.Position = UDim2.new(0, 2, 0, 0)
inputRow.BackgroundTransparency = 1
inputRow.LayoutOrder = 3
inputRow.Parent = ekCG
hlist(inputRow, 10, Enum.VerticalAlignment.Center)
local _inputRowPad = Instance.new("UIPadding", inputRow)
_inputRowPad.PaddingTop    = UDim.new(0, 2)
_inputRowPad.PaddingBottom = UDim.new(0, 2)
_inputRowPad.PaddingLeft   = UDim.new(0, 2)
_inputRowPad.PaddingRight  = UDim.new(0, 2)

-- Input frame
local inputFrame = Instance.new("Frame")
inputFrame.Size = UDim2.new(1, -180, 1, 0)
inputFrame.BackgroundColor3 = C_INPUT
inputFrame.BorderSizePixel = 0
inputFrame.LayoutOrder = 1
inputFrame.Parent = inputRow
corner(inputFrame, 10)
inputFrame.ClipsDescendants = true
local inputStroke = mkStroke(inputFrame, C_BORDER, 1.5)

-- Key icon inside input
local inputIco = mkImg(inputFrame, A_KEY, UDim2.new(0, 16, 0, 16),
	UDim2.new(0, 14, 0.5, -8), C_SUB)

local keyInput = Instance.new("TextBox")
keyInput.Size = UDim2.new(1, -44, 1, 0)
keyInput.Position = UDim2.new(0, 38, 0, 0)
keyInput.BackgroundTransparency = 1
keyInput.Text = ""
keyInput.PlaceholderText = "Enter your key here..."
keyInput.PlaceholderColor3 = C_SUB
keyInput.TextColor3 = C_WHITE
keyInput.TextSize = 13
keyInput.Font = Enum.Font.Gotham
keyInput.TextXAlignment = Enum.TextXAlignment.Left
keyInput.ClearTextOnFocus = false
keyInput.TextTruncate = Enum.TextTruncate.AtEnd
keyInput.Parent = inputFrame

keyInput.Focused:Connect(function()
	tw(inputFrame, 0.18, {BackgroundColor3 = Color3.fromRGB(18, 18, 24)})
	tw(inputStroke, 0.18, {Color = C_GREEN, Thickness = 1.5})
	tw(inputIco, 0.18, {ImageColor3 = C_GREEN})
end)
keyInput.FocusLost:Connect(function()
	tw(inputFrame, 0.18, {BackgroundColor3 = C_INPUT})
	tw(inputStroke, 0.18, {Color = C_BORDER, Thickness = 1.5})
	tw(inputIco, 0.18, {ImageColor3 = C_SUB})
end)

-- Verify button
local verifyBtn = Instance.new("TextButton")
verifyBtn.Size = UDim2.new(0, 164, 0, 50)
verifyBtn.BackgroundColor3 = C_GREEN
verifyBtn.Text = "  ✓  Verify Key"
verifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
verifyBtn.TextSize = 14
verifyBtn.Font = Enum.Font.GothamBold
verifyBtn.BorderSizePixel = 0
verifyBtn.LayoutOrder = 2
verifyBtn.Parent = inputRow
corner(verifyBtn, 10)
verifyBtn.MouseEnter:Connect(function()
	if verifyBtn.Text ~= "..." then
		tw(verifyBtn, 0.15, {BackgroundColor3 = C_GHOVER})
	end
end)
verifyBtn.MouseLeave:Connect(function()
	if verifyBtn.Text ~= "..." then
		tw(verifyBtn, 0.15, {BackgroundColor3 = C_GREEN})
	end
end)
addHoverGrow(verifyBtn)

-- Status row
local statusRow = Instance.new("Frame")
statusRow.Size = UDim2.new(1, 0, 0, 20)
statusRow.BackgroundTransparency = 1
statusRow.LayoutOrder = 4
statusRow.Parent = ekCG
hlist(statusRow, 8, Enum.VerticalAlignment.Center)

local dotWrap = Instance.new("Frame")
dotWrap.Size = UDim2.new(0, 10, 1, 0)
dotWrap.BackgroundTransparency = 1
dotWrap.LayoutOrder = 1
dotWrap.Parent = statusRow
local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.Position = UDim2.new(0.5, -4, 0.5, -4)
statusDot.BackgroundColor3 = C_SUB
statusDot.BorderSizePixel = 0
statusDot.Parent = dotWrap
corner(statusDot, 4)

local statusTxt = Instance.new("TextLabel")
statusTxt.Size = UDim2.new(1, -22, 1, 0)
statusTxt.BackgroundTransparency = 1
statusTxt.Text = "Waiting for key..."
statusTxt.TextColor3 = C_SUB
statusTxt.TextSize = 11
statusTxt.Font = Enum.Font.Gotham
statusTxt.TextXAlignment = Enum.TextXAlignment.Left
statusTxt.LayoutOrder = 2
statusTxt.Parent = statusRow

-- Pulsing dot for waiting state
local dotPulseConn = nil
local function startDotPulse(col)
	if dotPulseConn then dotPulseConn:Disconnect() dotPulseConn = nil end
	local pulseActive = true
	task.spawn(function()
		while pulseActive and gui.Parent do
			tw(statusDot, 0.7, {BackgroundTransparency = 0.3}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(0.72)
			tw(statusDot, 0.7, {BackgroundTransparency = 0}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.wait(0.72)
		end
	end)
	dotPulseConn = {Disconnect = function() pulseActive = false end}
end

local function setStatus(state, msg)
	statusTxt.Text = msg
	if dotPulseConn then dotPulseConn:Disconnect() dotPulseConn = nil end
	statusDot.BackgroundTransparency = 0

	if state == "wait" then
		tw(statusDot, 0.2, {BackgroundColor3 = C_SUB})
		statusTxt.TextColor3 = C_SUB
		startDotPulse(C_SUB)
	elseif state == "check" then
		tw(statusDot, 0.2, {BackgroundColor3 = C_YELLOW})
		statusTxt.TextColor3 = C_YELLOW
		startDotPulse(C_YELLOW)
	elseif state == "ok" then
		tw(statusDot, 0.2, {BackgroundColor3 = C_GREEN})
		statusTxt.TextColor3 = C_GREEN
	elseif state == "err" then
		tw(statusDot, 0.2, {BackgroundColor3 = C_RED})
		statusTxt.TextColor3 = C_RED
	end
end
startDotPulse(C_SUB)

spacer(modal, 9, 8)

-- Divider before footer
local div2 = Instance.new("Frame")
div2.Size = UDim2.new(1, 0, 0, 1)
div2.BackgroundColor3 = C_BORDER div2.BorderSizePixel = 0 div2.LayoutOrder = 10 div2.Parent = modal

spacer(modal, 11, 14)

-- ── SECTION 5: FOOTER ────────────────────────────────────────
local footCG = Instance.new("CanvasGroup")
footCG.Size = UDim2.new(1, 0, 0, 36)
footCG.BackgroundTransparency = 1
footCG.LayoutOrder = 12
footCG.Parent = modal
staggerIn(footCG)

local footLayout = Instance.new("UIListLayout")
footLayout.FillDirection = Enum.FillDirection.Horizontal
footLayout.SortOrder = Enum.SortOrder.LayoutOrder
footLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
footLayout.VerticalAlignment = Enum.VerticalAlignment.Center
footLayout.Parent = footCG

-- Footer columns
local function footCol(order, topText, botText, topColor, botColor)
	local col = Instance.new("Frame")
	col.Size = UDim2.new(0.333, -2, 1, 0)
	col.BackgroundTransparency = 1
	col.LayoutOrder = order
	col.Parent = footCG
	vlist(col, 2, Enum.HorizontalAlignment.Center)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 0, 14) t.BackgroundTransparency = 1
	t.Text = topText t.TextSize = 10 t.TextColor3 = topColor or C_SUB
	t.Font = Enum.Font.Gotham t.TextXAlignment = Enum.TextXAlignment.Center
	t.LayoutOrder = 1 t.Parent = col
	local b = Instance.new("TextLabel")
	b.Size = UDim2.new(1, 0, 0, 14) b.BackgroundTransparency = 1
	b.Text = botText b.TextSize = 11 b.TextColor3 = botColor or C_WHITE
	b.Font = Enum.Font.GothamBold b.TextXAlignment = Enum.TextXAlignment.Center
	b.LayoutOrder = 2 b.Parent = col
	return b
end

local footSepA = Instance.new("Frame")
footSepA.Size = UDim2.new(0, 1, 0, 24) footSepA.BackgroundColor3 = C_BORDER
footSepA.BorderSizePixel = 0 footSepA.LayoutOrder = 2 footSepA.Parent = footCG

local footSepB = Instance.new("Frame")
footSepB.Size = UDim2.new(0, 1, 0, 24) footSepB.BackgroundColor3 = C_BORDER
footSepB.BorderSizePixel = 0 footSepB.LayoutOrder = 4 footSepB.Parent = footCG

footCol(1, "Version", SCRIPT_VER, C_SUB, C_GREEN)
footCol(3, "Build",   BUILD_TAG,  C_SUB, C_WHITE)
local footStatusBot = footCol(5, "Status", "Waiting...", C_SUB, C_SUB)

-- ═══════════════════════════════════════════════════════════════
-- VERIFY LOGIC
-- ═══════════════════════════════════════════════════════════════
local verifying = false
local verifyStages = {
	{text = "Connecting...",        delay = 0.5},
	{text = "Authenticating...",    delay = 0.6},
	{text = "Validating License...",delay = 0.6},
	{text = "Checking Expiration...",delay=0.5},
	{text = "Loading...",           delay = 0},
}
local verifyStageConn = nil

local function stopStages()
	if verifyStageConn then verifyStageConn = nil end
end

local function runStages(cb)
	task.spawn(function()
		for _, stage in ipairs(verifyStages) do
			if not gui.Parent then return end
			verifyBtn.Text = stage.text
			if stage.delay > 0 then task.wait(stage.delay) end
		end
		cb()
	end)
end

-- Shake the input box on error
local function shakeInput()
	local baseX = inputFrame.Position.X.Offset
	local shakes = {8, -8, 6, -6, 4, -4, 0}
	for _, x in ipairs(shakes) do
		tw(inputFrame, 0.05, {Position = UDim2.new(0, x, 0, 0)}, Enum.EasingStyle.Linear)
		task.wait(0.055)
	end
	inputFrame.Position = UDim2.new(0, 0, 0, 0)
end

-- Red flash on input
local function flashRed()
	tw(inputStroke, 0.1, {Color = C_RED, Thickness = 2})
	task.wait(0.5)
	tw(inputStroke, 0.3, {Color = C_BORDER, Thickness = 1.5})
end

-- Green success glow
local function flashGreen()
	for _ = 1, 2 do
		tw(inputStroke, 0.15, {Color = C_GREEN, Thickness = 2.5})
		task.wait(0.18)
		tw(inputStroke, 0.15, {Color = C_GREEN, Thickness = 1})
		task.wait(0.18)
	end
	tw(inputStroke, 0.3, {Color = C_GREEN, Thickness = 1.5})
end

local function doVerify()
	if verifying then return end
	local key = keyInput.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if key == "" then
		setStatus("err", "Please enter a key first.")
		footStatusBot.Text = "No Key Entered"
		footStatusBot.TextColor3 = C_RED
		task.spawn(shakeInput)
		task.spawn(flashRed)
		return
	end

	verifying = true
	verifyBtn.BackgroundColor3 = Color3.fromRGB(26, 26, 34)
	verifyBtn.TextColor3 = C_SUB
	setStatus("check", "Connecting to auth server...")
	footStatusBot.Text = "Authenticating"
	footStatusBot.TextColor3 = C_YELLOW

	-- Run the animated stages while validation is happening in parallel
	local validationDone = false
	local validationResult = nil

	-- Start actual validation immediately
	validateKey(key, function(valid, msg, licInfo)
		validationResult = {valid = valid, msg = msg, licInfo = licInfo}
		validationDone = true
	end)

	-- Run visual stages, then wait for validation to finish
	task.spawn(function()
		for _, stage in ipairs(verifyStages) do
			if not gui.Parent then return end
			verifyBtn.Text = stage.text
			setStatus("check", stage.text)
			if stage.delay > 0 then task.wait(stage.delay) end
		end

		-- Wait for actual result if not done yet
		local waited = 0
		while not validationDone and waited < 10 do
			task.wait(0.1)
			waited += 0.1
		end

		verifying = false
		if not validationResult then
			verifyBtn.Text = "  ✓  Verify Key"
			verifyBtn.BackgroundColor3 = C_GREEN
			verifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			setStatus("err", "Connection timed out.")
			footStatusBot.Text = "Timeout"
			footStatusBot.TextColor3 = C_RED
			return
		end

		local valid = validationResult.valid
		local msg = validationResult.msg
		local licInfo = validationResult.licInfo

		if valid then
			verifyBtn.Text = "  ✓  Verified!"
			tw(verifyBtn, 0.2, {BackgroundColor3 = C_GREEN})
			verifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			setStatus("ok", "✓  " .. (msg or "Key verified!"))
			footStatusBot.Text = "Authenticated"
			footStatusBot.TextColor3 = C_GREEN
			saveKey(key)
			task.spawn(flashGreen)
			task.wait(1.0)
			-- Fade out and load
			tw(modal, 0.3, {GroupTransparency = 1})
			tw(overlay, 0.3, {BackgroundTransparency = 1})
			task.wait(0.35)
			logoFloatConn:Disconnect()
			gui:Destroy()
			-- Wire tier info into getgenv so DhcAutoFarm can read it
			-- trial = Free (1 hour), everything else = Premium
			if licInfo then
				local tier = licInfo.tier or "trial"
				local timeleft = tonumber(licInfo.timeleft) or 0
				-- Auto-detect tier from actual time remaining
				local detectedTier = tier
				if timeleft < 3600 then detectedTier = "trial"
				elseif timeleft <= 86400 * 4 then detectedTier = "3day"
				elseif timeleft <= 86400 * 8 then detectedTier = "weekly"
				else detectedTier = "monthly" end
				getgenv().IS_PREMIUM      = detectedTier ~= "trial"
				getgenv().USER_TIER       = detectedTier
				getgenv().TIER_LABEL      = licInfo.tierlabel or "Free Trial"
				getgenv().LICENSE_EXPIRY  = tonumber(licInfo.expiry) or 0
				getgenv().LICENSE_TIMELEFT= timeleft
				getgenv().LICENSE_STATUS  = "Active"
			else
				getgenv().IS_PREMIUM       = false
				getgenv().USER_TIER        = "trial"
				getgenv().TIER_LABEL       = "Free Trial"
				getgenv().LICENSE_EXPIRY   = 0
				getgenv().LICENSE_TIMELEFT = 0
				getgenv().LICENSE_STATUS   = "Active"
			end
			if onSuccess then onSuccess() end
		else
			verifyBtn.Text = "  ✓  Verify Key"
			tw(verifyBtn, 0.2, {BackgroundColor3 = C_GREEN})
			verifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			setStatus("err", "X  " .. (msg or "Invalid key."))
			footStatusBot.Text = "Auth Failed"
			footStatusBot.TextColor3 = C_RED
			task.spawn(shakeInput)
			task.spawn(flashRed)
		end
	end)
end

verifyBtn.MouseButton1Click:Connect(doVerify)
keyInput.FocusLost:Connect(function(enter) if enter then doVerify() end end)

-- Auto-validate saved key
task.spawn(function()
	task.wait(0.6)
	local saved = loadKey()
	if saved and saved ~= "" then
		keyInput.Text = saved
		setStatus("check", "Checking saved key...")
		footStatusBot.Text = "Checking..."
		footStatusBot.TextColor3 = C_YELLOW
		task.wait(0.3)
		doVerify()
	end
end)

end
end)()

-- Reset SCRIPT_KEY so the CDN loader can read it
getgenv().SCRIPT_KEY = nil

KeySystem(function()
	-- Key validated by our UI — store it for the CDN loader
	local validatedKey = ""
	pcall(function()
		validatedKey = keyInput.Text:gsub("^%s+", ""):gsub("%s+$", "")
	end)
	getgenv().SCRIPT_KEY = validatedKey ~= "" and validatedKey or ""
end)

-- Wait for key to be set
while not getgenv().SCRIPT_KEY or getgenv().SCRIPT_KEY == "" do
	task.wait(0.05)
end

-- Load the script from Junkie CDN — it reads SCRIPT_KEY server-side
local cdnUrl = "https://api.jnkie.com/api/v1/luascripts/32753/download"
local ok, result = pcall(function()
	local raw = game:HttpGet(cdnUrl)
	if raw and raw ~= "" and not raw:find("<!DOCTYPE") then
		local fn, err = loadstring(raw)
		if fn then
			fn()
		else
			warn("[ATMFarmer] loadstring failed: " .. tostring(err))
		end
	else
		warn("[ATMFarmer] CDN returned invalid response")
	end
end)
if not ok then
	warn("[ATMFarmer] CDN load failed: " .. tostring(result))
end
