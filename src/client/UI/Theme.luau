--!strict
--[[
	Theme
	Colors, fonts and sizes for the sci-fi UI. Every screen pulls from here
	so the look can be retuned in one place.
]]

local Theme = {
	Colors = {
		Backdrop = Color3.fromRGB(8, 11, 17),
		Panel = Color3.fromRGB(16, 21, 31),
		PanelRaised = Color3.fromRGB(24, 31, 45),
		Stroke = Color3.fromRGB(58, 88, 120),
		Accent = Color3.fromRGB(110, 220, 255),
		Power = Color3.fromRGB(255, 214, 90),
		Text = Color3.fromRGB(228, 236, 244),
		TextDim = Color3.fromRGB(136, 152, 172),
		Success = Color3.fromRGB(110, 230, 150),
		Warning = Color3.fromRGB(255, 200, 90),
		Error = Color3.fromRGB(255, 110, 110),
		Info = Color3.fromRGB(150, 200, 255),
	},
	Fonts = {
		Title = Enum.Font.GothamBold,
		Body = Enum.Font.Gotham,
		Mono = Enum.Font.RobotoMono,
	},
	TextSize = {
		Title = 18,
		Body = 14,
		Small = 12,
	},
	CornerRadius = UDim.new(0, 6),
	Padding = 10,
}

return Theme
