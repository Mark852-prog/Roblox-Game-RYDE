--!strict
--[[
	Theme / UI kit

	RYDE's visual language, used by every screen so the UI stays consistent:
	  * Dark glass panels, one electric-teal accent for anything interactive
	    or important, red only for braking / warnings.
	  * Montserrat Heavy Italic for headings and big numbers (speed),
	    Gotham for body text.
	  * Every button gives feedback: hover colour + nudge + sound, click sound.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundConfig = require(Shared.Config.SoundConfig)

local Theme = {}

Theme.Colors = {
	background = Color3.fromRGB(10, 12, 16),
	panel = Color3.fromRGB(16, 19, 25),
	panelLight = Color3.fromRGB(28, 32, 41),
	stroke = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(240, 243, 247),
	textDim = Color3.fromRGB(150, 158, 172),
	accent = Color3.fromRGB(40, 230, 175),
	accentDark = Color3.fromRGB(20, 120, 95),
	warning = Color3.fromRGB(255, 176, 32),
	danger = Color3.fromRGB(255, 64, 72),
	locked = Color3.fromRGB(90, 96, 108),
}

Theme.Fonts = {
	display = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
	heading = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic),
	body = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	bodyBold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
	mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
}

-- Generic instance builder: Theme.new("Frame", { Size = ..., Parent = ... }, { children })
function Theme.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.corner(radius: number?): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Theme.stroke(transparency: number?, color: Color3?, thickness: number?): UIStroke
	return Theme.new("UIStroke", {
		Color = color or Theme.Colors.stroke,
		Transparency = transparency or 0.88,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.padding(all: number): UIPadding
	return Theme.new("UIPadding", {
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
	})
end

-- A dark glass panel.
function Theme.panel(props: { [string]: any }?): Frame
	local p = props or {}
	local frame = Theme.new("Frame", {
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, { Theme.corner(14), Theme.stroke(0.9) })
	for k, v in p do
		frame[k] = v
	end
	return frame
end

function Theme.label(text: string, font: Font, size: number, props: { [string]: any }?): TextLabel
	local label = Theme.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = font,
		TextSize = size,
		TextColor3 = Theme.Colors.text,
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, size + 4),
	})
	if props then
		for k, v in props do
			label[k] = v
		end
	end
	return label
end

-- Short UI sounds (2D, through the UI SoundGroup).
local soundCache: { [string]: Sound } = {}
function Theme.playUISound(key: string)
	local def = SoundConfig.Sounds[key]
	if not def then
		return
	end
	local sound = soundCache[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "RYDE_UI_" .. key
		sound.SoundId = SoundConfig.assetUri(def.id)
		sound.Volume = def.volume
		sound.SoundGroup = SoundService:FindFirstChild("UI") :: SoundGroup?
		sound.Parent = SoundService
		soundCache[key] = sound
	end
	sound.TimePosition = 0
	sound:Play()
end

--[[
	Interactive feedback for any GuiButton: hover sound, colour and a small
	nudge; click sound. `onHover(true/false)` lets callers add their own.
]]
function Theme.bindButton(button: GuiButton, onClick: () -> (), onHover: ((boolean) -> ())?)
	button.AutoButtonColor = false
	button.MouseEnter:Connect(function()
		Theme.playUISound("UIHover")
		if onHover then
			onHover(true)
		end
	end)
	button.MouseLeave:Connect(function()
		if onHover then
			onHover(false)
		end
	end)
	button.Activated:Connect(function()
		Theme.playUISound("UIClick")
		onClick()
	end)
end

function Theme.tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local tween = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

-- A filled pill button (e.g. SELECT, APPLY).
function Theme.pillButton(text: string, props: { [string]: any }?, onClick: () -> ()): TextButton
	local button = Theme.new("TextButton", {
		BackgroundColor3 = Theme.Colors.accent,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.heading,
		TextSize = 18,
		TextColor3 = Theme.Colors.background,
		Text = text,
		Size = UDim2.fromOffset(160, 44),
	}, { Theme.corner(22) })
	if props then
		for k, v in props do
			button[k] = v
		end
	end
	local base = button.BackgroundColor3
	Theme.bindButton(button, onClick, function(hovered)
		Theme.tween(button, 0.15, { BackgroundColor3 = if hovered then base:Lerp(Color3.new(1, 1, 1), 0.25) else base })
	end)
	return button
end

return Theme
