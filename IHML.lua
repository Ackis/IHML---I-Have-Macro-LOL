local LibStub = LibStub
local IHML = LibStub("AceAddon-3.0"):NewAddon("IHML", "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("IHML")

-- Upvalues from the global namespace
local format = string.format
local pairs = pairs
local select = select
local string = string
local tonumber = tonumber
local GetMinimapZoneText = GetMinimapZoneText
local InCombatLockdown = InCombatLockdown
local CreateMacro = CreateMacro
local EditMacro = EditMacro
local GetMacroIndexByName = GetMacroIndexByName
local GetMacroInfo = GetMacroInfo
local GetMacroIconInfo = GetMacroIconInfo

-- locals
local db, c, p
local options
local bw2bm
local mName -- Need for AceConfig
local mIcon, mBody
local currentIcon -- the index for the current macro icon
local queued

local lastboss

local defaults = {
	profile = {
		autoswap = true,
		byBigWigs2BossMod = true,
		byZone = true,
		macroname = "ihml",
	}
}

-- Helper function
local function setMacro(name, icon, body, dontOverwrite)
	if dontOverwrite and mIcon[name] then return end
	mName[name] = icon and name or nil -- Makes it still possible to delete macros with setMacro(name)
	mIcon[name] = icon
	mBody[name] = body
end

local function insertDefaultMacros()
-- Please exuse the missing indent. He just couldn't make it.
-- Some macros XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
-- Daily quests -----------------------
-- Skettis --------
setMacro(L["Skettis"], 1, L["m_skettis"], true)
-- Ogri'La --------
setMacro(L["Vortex Pinnacle"], 1, L["m_vortexpinnacle"], true)
setMacro(L["Forge Camp: Wrath"], 1, L["m_forgecamp"], true)
setMacro(L["Forge Camp: Terror"], 1, L["m_forgecamp"], true)
-- Netherwing -----
-- TODO: Go figure out what macros to write
---------------------------------------

-- Karazhan ---------------------------
setMacro(L["The Curator"], 651, L["m_curator"], true)
setMacro(L["Terestian Illhoof"], 626, L["m_illhoof"], true)
---------------------------------------

-- Zul'Aman ---------------------------
setMacro(L["Halazzi"], 634, L["m_halazzi"], true)
---------------------------------------

-- Serpentshrine Cavern ---------------
setMacro(L["Fathom-Lord Karathress"], 376, L["m_flk"], true)
setMacro(L["Lady Vashj"], 728, L["m_vashj"], true)
---------------------------------------

-- Tempest Keep -----------------------
---------------------------------------

-- Mount Hyjal ------------------------
setMacro(L["Archimonde"], 275, L["m_archimonde"], true)
---------------------------------------

-- Black Temple -----------------------
setMacro(L["High Warlord Naj'entus"], 392, L["m_najentus"], true)
---------------------------------------
--XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
end

local function checkMacro(name, dontMake)
	if not name then
		IHML:Print(L["Please choose a macroname by typing: /ihml macroname <name here>"])
	elseif GetMacroIndexByName(name) == 0 then
		if dontMake then
			IHML:Print(format(L["|cffff9999Warning!|r No macro named %s found. Make it plz!"], name))
		else
			local i = 1
			while i <= 18 do 
				local test = GetMacroInfo(i)
				if not test then
					CreateMacro(name, 1, "", 1, false)
					return
				end
				i = i + 1
			end
			IHML:Print(L["|cffff9999Warning!|r No free macro space for a non character specific macro :("])
		end
	elseif GetMacroIndexByName(name) > 18 then
		IHML:Print(format(L["%s is character specific. It is recomended to use a general macro if the profile is used with more than one character. (And to get rid of this nagging ;P)"], name))
	end
end

function IHML:OnInitialize()
	db = LibStub("AceDB-3.0"):New("IHMLDB", defaults, "Default")
	self.db = db
	c = db.char
	p = db.profile
	mName = {}
	mIcon = p.macroIcon
	mBody = p.macroBody
	if not mIcon or not mBody then
		mIcon = {}
		mBody = {}
		insertDefaultMacros()
		p.macroIcon = mIcon
		p.macroBody = mBody
	else
		for k in pairs(mIcon) do
			mName[k] = k
		end
	end

	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("IHML", options)
	self.options = options
	self:RegisterChatCommand("ihml", "ChatCommand", true)
end

function IHML:OnEnable()
	self:UpdateSettings()
	checkMacro(p.macroname)
	AceLibrary("AceEvent-2.0").RegisterEvent(IHML, "Ace2_AddonEnabled", function(addon)
		-- If the addon don't have enabletrigger then it's not a bossmod
		if not addon.enabletrigger or not bw2bm then return end
		lastboss = addon.name
		IHML:SwapMacro(lastboss)
	end)
	if c.current then
		queued = c.current
		c.current = nil
		self:SwapMacro()
	end
	if MacroFrame then
		self:ADDON_LOADED("Blizzard_MacroUI") -- the MacroUI has already loaded
	else
		self:RegisterEvent("ADDON_LOADED") -- To detect when the Macro frame loads
	end
end

function IHML:OnDisable()
	bw2bm = nil
end

function IHML:ZoneChanged()
	self:SwapMacro(GetMinimapZoneText())
end

function IHML:ADDON_LOADED(addon)
	if not addon == "Blizzard_MacroUI" then return end
	-- Blizzard_MacroUI loads twice for some reason
	-- (guessing it has got something to do with the dummy addon in the AddOns-folder)
	-- MacroFrame remains nil until it has loaded for real.
	if MacroFrame == nil then return end
	-- Use secure hook, to avoid taint if editing macros in combat
	self:SecureHook("MacroPopupOkayButton_OnClick", function()
		if MacroPopupEditBox:GetText() == p.macroname then
			currentIcon = MacroPopupFrame.selectedIcon
			mIcon[c.current] = currentIcon
			--IHML:Print("Caught macro icon index: "..currentIcon)
		end
	end)
	self:UnregisterEvent("ADDON_LOADED") -- Don't need this anymore
end

function IHML:SwapMacro(new)
	new = new ~= "PLAYER_REGEN_ENABLED" and new or queued
	if not new or -- Got called without argument even when there was nothing queued.
		not mIcon[new] or -- Macro don't exists
		new == c.current then -- Macro is same as current macro. TODO: Swap anyway if the macro has been modified?
		return
	end
	if InCombatLockdown() then
		if queued and queued == new then return end
		queued = new
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "SwapMacro")
		self:Print(format(L["In combat! %s queued lol!"], queued))
		return
	end
	local icon, body = mIcon[new], mBody[new]
	self:Print(format(L["%s! I have that macro lol!"], new))
	EditMacro(GetMacroIndexByName(p.macroname), p.macroname, icon, body, 1, 0)
	c.current = new
	currentIcon = icon
	queued = nil
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end


function IHML:ChatCommand(msg)
	local arg, pos = self:GetArgs(msg, 1, 1)
	if not arg or arg == "config" or arg == "gui" or arg == "show" then
		LibStub("AceConfigDialog-3.0"):Open("IHML")
		return
	elseif arg == "help" then
		self:Print("|cffff9933Commands:|r")
		self:Print("|cffff9999config|r - Open the configuration window")
		self:Print("|cffff9999save|r - Save any modifications to the current macro")
		self:Print("|cffff9999saveas|r |cff9999ff\"new name\"|r - Save modifications to a new macro")
		self:Print("|cffff9999rename|r |cff9999ff\"new name\"|r - Change name for current macro")
		self:Print("|cffff9999delete|r |cff9999ff\"macro\"|r - Delete a macro")
		self:Print("|cffff9999list|r - List all available macros")
		-- Keep the ingame command list simple
		--self:Print("|cffff9999insertdefault|r - Reinserts the default macros")
		--self:Print("|cffff9999macroname|r |cff9999ff\"macro\"|r - Choose what macroslot IHML will swap. Default: imhl")
		self:Print("|cff9999ffAnything else|r - Swap macro")
		return
	elseif arg == "save" then
		-- Save any modifications to the current macro
		if not c.current then return self:Print("No current macro") end
		local body = select(3, GetMacroInfo(p.macroname))
		if body then
			setMacro(c.current, currentIcon, body)
			self:Print("Saved as "..c.current)
		end
		return
	elseif arg == "saveas" then
		if not c.current then return self:Print("No current macro") end
		-- Save any modifications to a new macro
		arg, pos = self:GetArgs(msg, 1, pos)
		if arg then
			if arg == "boss" then
				if not lastboss then return self:Print("No last boss nub!") end
				arg = lastboss
			end
			local body = select(3, GetMacroInfo(p.macroname))
			if body then
				setMacro(arg, currentIcon, body)
				c.current = arg
			end
			self:Print("Saved as "..arg)
		end
		return
	elseif arg == "rename" then
		if not c.current then return self:Print("No current macro") end
		-- Change name for current macro
		local arg2
		arg, arg2, pos = self:GetArgs(msg, 2, pos)
		if arg then
			if arg2 then
				if mIcon[arg] and not mIcon[arg2] then
					setMacro(arg2, mIcon[arg], mBody[arg])
					setMacro(arg)
					self:Print("Renamed \""..arg.."\" to \""..arg2.."\"")
				end
			else
				if not mIcon[arg] then
					setMacro(arg, mIcon[c.current], mBody[c.current])
					setMacro(c.current)
					c.current = arg
					self:Print("Renamed \""..c.current.."\" to \""..arg.."\"")
				end
			end
		end
		return
	elseif arg == "delete" or arg == "remove" then
		-- Delete a macro
		-- If there's no other argument, delete the current
		arg, pos = self:GetArgs(msg, 1, pos)
		if arg then
			self:Print("Deleting macro: "..arg)
			setMacro(arg)
		elseif c.current then
			self:Print("Deleting macro: "..c.current)
			setMacro(c.current)
			c.current = nil
		end
		return
	elseif arg == "list" then
		for k in pairs(mIcon) do
			self:Print(k)
		end
		return
	elseif arg == "macroname" then
		arg, pos = self:GetArgs(msg, 1, pos)
		if arg then
			checkMacro(arg, true)
			p.macroname = arg
		end
	elseif arg == "insertdefault" then
		insertDefaultMacros()
		return
	end
--	self:Print(msg)
	self:SwapMacro(msg)
end

function IHML:UpdateSettings()
	if p.autoswap then
		if p.byBigWigs2BossMod then
			bw2bm = true
		end
		if p.byZone then
			self:RegisterEvent("MINIMAP_ZONE_CHANGED", "ZoneChanged")
			self:RegisterEvent("ZONE_CHANGED", "ZoneChanged")
		end
	else
		bw2bm = nil
		self:UnregisterEvent("MINIMAP_ZONE_CHANGED")
		self:UnregisterEvent("ZONE_CHANGED")
	end
end

options = {
	type = "group",
	name = "IHML",
	args = {
		macros = {
			type = "group",
			name = L["Macros"],
			desc = L["Macros"],
			order = 100,
			--args = {}, -- defined later
		},
		option = {
			type = "group",
			name = L["Options"],
			desc = L["Options"],
			order = 200,
			get = function(k) return p[k.arg] end,
			set = function(k, v) p[k.arg] = v; IHML:UpdateSettings() end,
			--args = {}, -- defined later
		},
	}
}

options.args.option.args = {
	autoswap = {
		name = L["Auto Swap"], type = "group",
		desc = L["Auto Swap"],
		inline = true,
		order = 100,
		args = {
			use = {
				name = L["Use Auto Swap"],
				desc = L["Use Auto Swap"],
				type = "toggle",
				arg = "autoswap",
				order = 100,
			},
			events = {
				name = L["Auto Swap events"], type = "group",
				desc = L["Auto Swap events"],
				inline = true,
				order = 200,
				disabled = function(info) return not p.autoswap end,
				args = {
					bigwigs2 = {
						name = L["BigWigs"], type = "toggle",
						desc = L["By BigWigs Boss Module"],
						order = 100,
						arg = "byBigWigs2BossMod",
					},
					zone = {
						name = L["Zone"], type = "toggle",
						desc = L["By Zone"],
						order = 200,
						arg = "byZone",
					},
				},
			},
		},
	},
	macroname = {
		name = L["Used Macro"],
		desc = L["Used Macro"],
		type = "input",
		arg = "macroname",
		set = function(k, v) p["macroname"] = v or p.macroname; checkMacro(v,true) end,
		order = 200,
	},
	makemacro = {
		name = L["Make Macro"], type = "execute",
		desc = L["Make Macro"],
		order = 201,
		disabled = function() return GetMacroIndexByName(p.macroname) ~= 0 end,
		func = function() checkMacro(p.macroname) end,
	},
	insertdefault = {
		name = L["Reinsert default macros"], type = "execute",
		desc = L["Use this to recover any removed default macros. Won't replace changed versions. If you want to revert changed macros delete them first."],
		order = 300,
		func = insertDefaultMacros,
	},
}

local guiMacro
options.args.macros.args = {
	list = {
		type = "select",
		name = L["Select Macro:"],
		desc = L["Select a macro."],
		order = 100,
		values = function() return mName end,
		get = function() return mIcon[guiMacro] and guiMacro or c.current or nil end,
		set = function(info,v) guiMacro = v ~= c.current and v or nil end,
	},
	swap = {
		type = "execute",
		name = L["Swap!"],
		desc = L["Swap to the selected macro."],
		order = 101,
		func = function() IHML:SwapMacro(guiMacro) end,
	},
	macro = {
		type = "group",
		name = L["Edit Macro"],
		inline = true,
		order = 200,
		args = {
			info = {
				type = "description",
				name = L["Name: Type \"boss\" for last loaded boss module or \"zone\" for current zone.\nIcon: A number from 1 to 769. You might want to edit this from the Blizzard Macro UI."],
				order = 100,
				image = function()
					if not guiMacro and not c.current then
						guiMacro = next(mName)
					elseif guiMacro == c.current then
						guiMacro = nil
					end
					return GetMacroIconInfo(mIcon[guiMacro] or currentIcon), 56, 56
				end,
			},
			name = {
				type = "input",
				name = L["Name:"],
				desc = L["This needs to match the boss module name or zone exactly for auto swap to work."],
				order = 200,
				validate = function(info, k)
					if k == "" then
						return L["Macros must have a name!"]
					elseif k == "boss" and lastboss == nil then
						return L["No boss module loaded!"]
					elseif mIcon[k] then
						return format(L["%s already exists!"], k)
					end
					return true
				end,
				get = function() return mIcon[guiMacro] and guiMacro or c.current end,
				set = function(info,k)
					if k == "boss" then
						k = lastboss
					elseif k == "zone" then
						k = GetMinimapZoneText()
					end
					if mIcon[guiMacro] then
						setMacro(k, mIcon[guiMacro], mBody[guiMacro])
						setMacro(guiMacro)
						if guiMacro == c.current then
							c.current = k
						end
						guiMacro = k
					else
						setMacro(k, mIcon[c.current], mBody[c.current])
						setMacro(c.current)
						c.current = k
					end
				end,
			},
			icon = {
				type = "input",
				name = L["Icon:"],
				desc = L["Icon"],
				order = 300,
				validate = function(info, k)
					local n = tonumber(k) or 0
					if n <= 0 or n >= 770 then
						return false
					elseif string.format("%d",n) == k then
						return true
					end
					return false
				end,
				get = function() return mIcon[guiMacro] or currentIcon end,
				set = function(info,k)
					if mIcon[guiMacro] then
						mIcon[guiMacro] = tonumber(k)
					else
						currentIcon = tonumber(k)
						mIcon[c.current] = currentIcon
						if not InCombatLockdown() then
							EditMacro(GetMacroIndexByName(p.macroname), p.macroname, currentIcon)
						end
					end
				end,
			},
			body = {
				type = "input",
				name = "",
				desc = L["The macro goes here. Still limited to 255 characters."],
				order = 400,
				multiline = true,
				width = "full",
				get = function() return mIcon[guiMacro] and mBody[guiMacro] or mBody[c.current] end,
				set = function(info,k)
					if mIcon[guiMacro] then
						mBody[guiMacro] = k
					else
						mBody[c.current] = k
						if not InCombatLockdown() then
							EditMacro(GetMacroIndexByName(p.macroname), p.macroname, currentIcon, k)
						end
					end
				end,
			},
			new = {
				type = "execute",
				name = L["New macro"],
				desc = L["Make a new macro."],
				order = 560,
				func = function()
					local name = L["New macro"]
					if mIcon[name] then
						local i = 2
						local testname = string.format("New macro %d", name, i)
						while mIcon[testname] do
							i = i + 1
							testname = string.format("New macro %d", name, i)
						end
						name = testname
					end
					setMacro(name, 1, "")
					guiMacro = name
				end,
			},
			delete = {
				type = "execute",
				name = L["Remove!"],
				desc = L["Remove the macro."],
				order = 550,
				confirm = function() return string.format("Are you sure you want to remove %s?", mIcon[guiMacro] and guiMacro or c.current) end,
				func = function()
					if mIcon[guiMacro] then
						setMacro(guiMacro)
						guiMacro = nil
					elseif c.current then
						setMacro(c.current)
						c.current = nil
					end
				end,
			},
		},
	},
}

do
	local PROFILES_NAME = "Profiles"
	local PROFILES_DESC = "Manage Profiles"
	local DEFAULT = "Default"
	local CHARACTER_COLON = "Character: "
	local REALM_COLON = "Realm: "
	local CLASS_COLON = "Class: "
	local DELETE_PROFILE_HEADER = "Delete a profile"
	local DELETE_PROFILE_NAME = "Delete a profile"
	local DELETE_PROFILE_DESC = "Deletes a profile. Note that no check is made whether this profile is in use by other characters or not."
	local DELETE_PROFILE_COMFIRM = "Are you sure you want to delete the selected profile?"
	local CHOOSE_PROFILE_NAME = "Choose a profile"
	local NEW_PROFILE_NAME = "New"
	local NEW_PROFILE_DESC = "Enter the name of the profile to create."
	local CURRENT_PROFILE_NAME = "Current"
	local CURRENT_PROFILE_DESC = "Select an existing profile to use for this character."
	local COPY_PROFILE_HEADER = "Copy a profile"
	local COPY_PROFILE_NAME = "Copy from"
	local COPY_PROFILE_DESC = "Copy settings from another profile."
	local RESET_PROFILE = "Reset profile"
	local RESET_PROFILE_DESC = "Clear all settings of the current profile."

	local defaultProfiles
	--[[ Utility functions ]]
	-- get exisiting profiles + some default entries
	local tmpprofiles = {}
	local function getProfileList(common, nocurrent)
		defaultProfiles = defaultProfiles or {
			["Default"] = "Default",
			[db.keys.char] = "Character: " .. db.keys.char,
			[db.keys.realm] = "Realm: " .. db.keys.realm,
			[db.keys.class] = "Class: " .. UnitClass("player")
		}
		-- clear old profile table
		local profiles = {}

		-- copy existing profiles into the table
		local curr = db:GetCurrentProfile()
		for _, v in pairs(db:GetProfiles(tmpprofiles)) do
			if not (nocurrent and v == curr) then profiles[v] = v end
		end

		-- add our default profiles to choose from
		for k, v in pairs(defaultProfiles) do
			if (common or profiles[k]) and not (k == curr and nocurrent) then
				profiles[k] = v
			end
		end
		return profiles
	end

	options.args.profile_group = {
		type = "group",
		name = PROFILES_NAME,
		desc = PROFILES_DESC,
		order = 300,
		args = {
			reset = {
				order = 1,
				type = "execute",
				name = RESET_PROFILE,
				desc = RESET_PROFILE_DESC,
				func = function() db:ResetProfile() end,
			},
			spacer1 = {
				order = 2,
				type = "header",
				name = CHOOSE_PROFILE_NAME,
			},
			choose = {
				name = CURRENT_PROFILE_NAME,
				desc = CURRENT_PROFILE_DESC,
				type = "select",
				order = 3,
				get = function() return db:GetCurrentProfile() end,
				set = function(info, value) db:SetProfile(value) end,
				values = function() return getProfileList(true) end,
			},
			new = {
				name = NEW_PROFILE_NAME,
				desc = NEW_PROFILE_DESC,
				type = "input",
				order = 4,
				get = false,
				set = function(info, value) db:SetProfile(value) end,
			},
			spacer2 = {
				type = "header",
				order = 5,
				name = COPY_PROFILE_HEADER,
			},
			copyfrom = {
				order = 6,
				type = "select",
				name = COPY_PROFILE_NAME,
				desc = COPY_PROFILE_DESC,
				get = false,
				set = function(info, value) db:CopyProfile(value) end,
				values = function() return getProfileList(nil, true) end,
			},
			spacer3 = {
				type = "header",
				order = 7,
				name = DELETE_PROFILE_HEADER,
			},
			delete = {
				order = 8,
				type = "select",
				name = DELETE_PROFILE_NAME,
				desc = DELETE_PROFILE_DESC,
				get = false,
				set = function(info, value) db:DeleteProfile(value) end,
				values = function() return getProfileList(nil, true) end,
				confirm = true,
				confirmText = DELETE_PROFILE_COMFIRM,
			},
		},
	}
end

_G.IMHL = IHML
