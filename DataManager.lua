--[[ 
    DataManager V2 Corrigido com Sistema de LifeHearts e Reset Completo
--]]

--> Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--> Dependencies
local GameConfig = require(ReplicatedStorage.GameConfig)

local AttributeModule = require(ReplicatedStorage.Modules.Shared.Attribute)
local QuestLibrary = require(ReplicatedStorage.Modules.Shared.QuestLibrary)
local ContentLibrary = require(ReplicatedStorage.Modules.Shared.ContentLibrary)
local AttributeFunctions = require(ServerStorage.Modules.Server.AttributeFunctions)

--> Variables
local UserData = DataStoreService:GetDataStore("UserData")
local SameKeyCooldown = {}

--------------------------------------------------------------------------------
-- Tabelas de configuração de Classes e Profs
--------------------------------------------------------------------------------

local ClassesConfig = {
	Nightblade = {Main = {"Speed", 3}, Minus = {"MagicPower", -2}, Sub = "Lockpicking", Weapon = "Dagger"},
	Blademaster = {Main = {"AttackPower", 3}, Minus = {"Mana", -2}, Sub = "Blacksmithing", Weapon = "Sword"},
	Spellweaver = {Main = {"MagicPower", 3}, Minus = {"Health", -2}, Sub = "Alchemy", Weapon = "Wand"},
	Warden = {Main = {"Health", 3}, Minus = {"AttackPower", -2}, Sub = "Enchanting", Weapon = "Wand"},
	Sharpscout = {Main = {"Luck", 3}, Minus = {"MagicDefense", -2}, Sub = "Farming", Weapon = "Bow"},
	Tidebreaker = {Main = {"Stamina", 3}, Minus = {"Luck", -2}, Sub = "Sailing", Weapon = "Bow"},
	Runeguard = {Main = {"MagicDefense", 3}, Minus = {"Stamina", -2}, Sub = "Crafting", Weapon = "Wand"},
	Cragborn = {Main = {"Defense", 3}, Minus = {"Speed", -2}, Sub = "Mining", Weapon = "Sword"},
	Venomblade = {Main = {"Mana", 3}, Minus = {"Defense", -2}, Sub = "Fishing", Weapon = "Dagger"},
}

local ProfList = {
	Professions = {"Mining", "Farming", "Fishing", "Crafting", "Lockpicking", "Alchemy", "Blacksmithing", "Sailing", "Enchanting"},
	Weapons = {"Sword", "Dagger", "Bow", "Wand"}
}
--------------------------------------------------------------------------------

local PlayerData = Instance.new("Folder")
PlayerData.Name = "PlayerData"
PlayerData.Parent = ReplicatedStorage

-- RemoteEvent to change slot from client
local ChangeSlotEvent = ReplicatedStorage:FindFirstChild("ChangeSlot")
if not ChangeSlotEvent then
	ChangeSlotEvent = Instance.new("RemoteEvent")
	ChangeSlotEvent.Name = "ChangeSlot"
	ChangeSlotEvent.Parent = ReplicatedStorage
end

-- Evento pra avisar o client que pode abrir o menu
local OpenCharacterMenu = ReplicatedStorage:FindFirstChild("OpenCharacterMenu") or Instance.new("RemoteEvent")
OpenCharacterMenu.Name = "OpenCharacterMenu"
OpenCharacterMenu.Parent = ReplicatedStorage

-- Evento pra spawnar o player
local SpawnPlayerEvent = ReplicatedStorage:FindFirstChild("SpawnPlayer") or Instance.new("RemoteEvent")
SpawnPlayerEvent.Name = "SpawnPlayer"
SpawnPlayerEvent.Parent = ReplicatedStorage

-- Evento para quando o personagem morre (LifeHearts = 0)
local PlayerDeathEvent = ReplicatedStorage:FindFirstChild("PlayerDeath") or Instance.new("RemoteEvent")
PlayerDeathEvent.Name = "PlayerDeath"
PlayerDeathEvent.Parent = ReplicatedStorage

-- Evento para resetar o personagem
local ResetCharacterEvent = ReplicatedStorage:FindFirstChild("ResetCharacter") or Instance.new("RemoteEvent")
ResetCharacterEvent.Name = "ResetCharacter"
ResetCharacterEvent.Parent = ReplicatedStorage

local function ClampStat(ValueObject: IntValue, Min: number?, Max: number?)
	local minValue = (type(Min) == "number") and Min or -math.huge
	local maxValue = (type(Max) == "number") and Max or math.huge

	ValueObject.Changed:Connect(function()
		ValueObject.Value = math.clamp(ValueObject.Value, minValue, maxValue)
	end)
end


local function CreateStat(ClassName: string, Name: string, DefaultValue, ClampInfo)
	local Stat = Instance.new(ClassName)
	Stat.Name = Name
	Stat.Value = (DefaultValue or 0)
	if ClampInfo and (Stat:IsA("NumberValue") or Stat:IsA("IntValue")) then
		ClampStat(Stat, unpack(ClampInfo))
	end
	return Stat
end

-- Função para resetar completamente o personagem
local function ResetCharacterCompletely(player)
	local pData = PlayerData:FindFirstChild(player.UserId)
	if not pData then return end
	print(`[RESET] Resetando personagem de {player.Name} completamente...`)

	local Stats = pData:WaitForChild("Stats")
	for StatName, Data in GameConfig.Leaderstats do
		local Constraint = Data.Constraint or {0}
		local Stat = Stats:FindFirstChild(StatName)
		if Stat then Stat.Value = Constraint[1] or 1 end
	end

	pData.LifeHearts.Value = 3
	for _, f in pData.Items:GetDescendants() do f:Destroy() end
	for _, a in pData.Attributes:GetChildren() do a.Value = 0 end
	pData.Points.Value = 0
	for _, f in pData.Quests.Completed:GetChildren() do f:Destroy() end
	for _, f in pData.Quests.Active:GetChildren() do f:Destroy() end
	for _, s in pData.EquippedSlots:GetChildren() do s.Value = "" end
	for _, s in pData.Hotbar:GetChildren() do s.Value = "" end
	pData.ActiveArmor.Value = ""

	local Statuses = player:FindFirstChild("Statuses")
	if Statuses then for _, s in Statuses:GetChildren() do s:Destroy() end end
	for _, b in {"Backpack","StarterGear"} do
		local folder = player:FindFirstChild(b)
		if folder then for _, it in folder:GetChildren() do it:Destroy() end end
	end

	AttributeModule:SetAttribute(player, "SavedCFrame", nil)
	print(`[RESET] Personagem de {player.Name} resetado com sucesso!`)
	task.wait(1)
	SaveData(player)
	ResetCharacterEvent:FireClient(player, true)
end

-- Sistema de LifeHearts
local LifeHeartsDebounce = {}

local function SetupLifeHeartsSystem(player)
	local pData = PlayerData:FindFirstChild(player.UserId)
	if not pData then return end

	local lifeHearts = pData:FindFirstChild("LifeHearts")
	if not lifeHearts then
		lifeHearts = CreateStat("IntValue", "LifeHearts", 3, {0, math.huge})
		lifeHearts.Parent = pData
	end

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		local characterDebounceKey = character

		humanoid.Died:Connect(function()
			if LifeHeartsDebounce[characterDebounceKey] then
				return
			end

			LifeHeartsDebounce[characterDebounceKey] = true

			local currentHearts = lifeHearts.Value
			if currentHearts > 0 then
				lifeHearts.Value = currentHearts - 1

				-- ?? RESET COMPLETO QUANDO CHEGAR A 0 CORAÇÕES
				if lifeHearts.Value <= 0 then
					warn(`[MORTE PERMANENTE] Player {player.Name} ficou sem corações! Resetando personagem...`)

					-- Dispara evento de morte permanente
					PlayerDeathEvent:FireClient(player)

					-- Espera um pouco antes do reset
					task.wait(3)

					-- Reseta o personagem completamente
					ResetCharacterCompletely(player)

					-- Respawna o jogador após o reset
					task.wait(2)
					if player and player.Parent then
						player:LoadCharacter()
					end
				else
					warn(`Player {player.Name} morreu. Corações restantes: {lifeHearts.Value}`)
				end
			end

			task.delay(5, function()
				LifeHeartsDebounce[characterDebounceKey] = nil
			end)
		end)
	end)

	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(Players) then
			for key, value in pairs(LifeHeartsDebounce) do
				if typeof(key) == "Instance" and key:IsDescendantOf(player) then
					LifeHeartsDebounce[key] = nil
				end
			end
		end
	end)
end

-- Função para resetar LifeHearts (quando troca de slot ou revive)
local function ResetLifeHearts(player)
	local pData = PlayerData:FindFirstChild(player.UserId)
	if not pData then return end

	local lifeHearts = pData:FindFirstChild("LifeHearts")
	if lifeHearts then
		lifeHearts.Value = 3
	end
end

local function CreateProfsFolder()
	local Profs = Instance.new("Folder")
	Profs.Name = "Profs"

	local function makeSkill(folder, name)
		local f = Instance.new("Folder")
		f.Name = name
		CreateStat("IntValue", "Level", 1).Parent = f
		CreateStat("NumberValue", "Exp", 0).Parent = f
		CreateStat("NumberValue", "ExpNextLevel", 100).Parent = f
		f.Parent = folder
	end

	for _, category in ProfList.Professions do makeSkill(Profs, category) end
	for _, weapon in ProfList.Weapons do makeSkill(Profs, weapon) end

	return Profs
end

-- CORREÇÃO: Função para atualizar atributos de forma segura
local function SafeUpdateAttribute(attributeName, player, attributesFolder)
	local attributeValue = attributesFolder:WaitForChild(attributeName)
	if AttributeFunctions[attributeName] then
		AttributeFunctions[attributeName](nil, player, attributesFolder)
	end
end

local function CreateDataFolder(Player)
	local old = PlayerData:FindFirstChild(Player.UserId)
	if old then old:Destroy() end
	local pData = Instance.new("Folder")
	pData.Name = Player.UserId

	-- Stats
	local Stats = Instance.new("Folder")
	Stats.Name = "Stats"
	Stats.Parent = pData
	for StatName, Data in GameConfig.Leaderstats do
		local Constraint = Data.Constraint or {0}
		CreateStat("NumberValue", StatName, Constraint[1], Constraint).Parent = Stats
	end

	-- LifeHearts
	CreateStat("IntValue", "LifeHearts", 3, {0, math.huge}).Parent = pData

	-- Classe
	local Classe = Instance.new("StringValue")
	Classe.Name = "Classe"
	Classe.Value = "None"
	Classe.Parent = pData

	-- Profs
	local Profs = CreateProfsFolder()
	Profs.Parent = pData

	-- Items
	local Items = Instance.new("Folder")
	Items.Name = "Items"
	for itemType in GameConfig.Categories do
		local f = Instance.new("Folder")
		f.Name = itemType
		f.Parent = Items
	end
	Items.Parent = pData

	-- Attributes
	local Attributes = Instance.new("Folder")
	Attributes.Name = "Attributes"
	for attr in GameConfig.Attributes do
		CreateStat("NumberValue", attr, 0).Parent = Attributes
	end
	Attributes.Parent = pData

	CreateStat("NumberValue", "Points", 0).Parent = pData

	-- Chests
	local Chests = Instance.new("Folder"); Chests.Name = "Chests"
	for _, Chest in CollectionService:GetTagged("Chest") do
		local cfg = Chest:FindFirstChild("Config") and require(Chest.Config)
		if cfg and cfg.Name then CreateStat("NumberValue", cfg.Name, 0).Parent = Chests end
	end
	Chests.Parent = pData

	-- Quests
	local Quests = Instance.new("Folder"); Quests.Name = "Quests"
	local Completed = Instance.new("Folder"); Completed.Name = "Completed"; Completed.Parent = Quests
	local Active = Instance.new("Folder"); Active.Name = "Active"; Active.Parent = Quests
	Quests.Parent = pData

	-- Equipped / Armor / Hotbar
	local Equipped = Instance.new("Folder"); Equipped.Name = "EquippedSlots"
	for i=1, GameConfig.EquippedAccessoryMax do CreateStat("StringValue", tostring(i), "").Parent = Equipped end
	Equipped.Parent = pData

	CreateStat("StringValue","ActiveArmor","").Parent = pData
	local Hotbar = Instance.new("Folder"); Hotbar.Name="Hotbar"
	for i=1,9 do CreateStat("StringValue", tostring(i), "").Parent=Hotbar end
	Hotbar.Parent=pData

	-- Attributes function bindings
	task.spawn(function()
		local folder = pData:WaitForChild("Attributes")
		for attr in GameConfig.Attributes do
			local val = folder:FindFirstChild(attr)
			if val and AttributeFunctions[attr] then
				val.Changed:Connect(function()
					AttributeFunctions[attr](nil, Player, folder)
				end)
			end
		end
	end)

	SetupLifeHeartsSystem(Player)
	return pData
end

-- CORREÇÃO: UnloadData com waits adequados
local function UnloadData(Player: Player, Data: any, pData: Instance)
	local RejoinTime = tick() - (Data.LastJoin or tick())

	-- Stats
	local Stats = pData:WaitForChild("Stats")
	for StatName, StatValue in Data.Stats do
		local Stat = Stats:FindFirstChild(StatName)
		if Stat then
			Stat.Value = StatValue
		end
	end

	-- LifeHearts (SISTEMA NOVO)
	local LifeHearts = pData:WaitForChild("LifeHearts")
	if Data.LifeHearts then
		LifeHearts.Value = Data.LifeHearts
	else
		LifeHearts.Value = 3 -- Valor padrão se não existir nos dados salvos
	end

	-- Items (mantido igual)
	local Items = pData:WaitForChild("Items")
	for ItemType, NewData in GameConfig.Categories do
		local ConvertedToolTable = (Data.Converted and Data.Items[ItemType]) or {}
		if not Data.Converted then
			for Index, Value in Data.Items[ItemType] or {} do
				if typeof(Index) == "number" then
					ConvertedToolTable[Value] = (ConvertedToolTable[Value] and ConvertedToolTable[Value] + 1) or 1
				else
					ConvertedToolTable[Index] = Value
				end
			end
		end

		local isATool = NewData.IsATool
		local Folder = Items:WaitForChild(ItemType)

		if isATool then
			-- UnloadTools function precisa ser definida
			local StarterGear = Player:WaitForChild("StarterGear")
			local Backpack = Player:WaitForChild("Backpack")

			for ItemName, Value in ConvertedToolTable do
				if Value <= 0 then continue end

				local Library = ContentLibrary[ItemType] or {}
				local Tool = Library[ItemName]
				if Tool then
					if not StarterGear:FindFirstChild(Tool.Name) then
						Tool.Instance:Clone().Parent = StarterGear
					end
					if not Backpack:FindFirstChild(Tool.Name) then
						Tool.Instance:Clone().Parent = Backpack
					end

					local Stat = CreateStat("NumberValue", ItemName, Value)
					Stat.Parent = Folder
				end
			end
		else
			for ItemName, Value in ConvertedToolTable do
				if Value <= 0 then continue end

				local Item = ContentLibrary[ItemType] and ContentLibrary[ItemType][ItemName]
				if Item then
					local Stat = CreateStat("NumberValue", ItemName, Value)
					Stat.Parent = Folder
				end
			end
		end
	end

	-- CORREÇÃO: Attributes com wait adequado e verificação
	local Attributes = pData:WaitForChild("Attributes")
	if Data.Attributes then
		-- Espera todos os atributos serem criados antes de tentar modificar
		for attrName in GameConfig.Attributes do
			Attributes:WaitForChild(attrName)
		end

		for attrName, attrValue in Data.Attributes do
			local Attribute = Attributes:FindFirstChild(attrName)
			if Attribute then
				Attribute.Value = attrValue
			end
		end
	end

	-- Points
	local Points = pData:WaitForChild("Points")
	if Data.Points then
		Points.Value = Data.Points
	end

	-- Restante do código permanece similar...
	-- [ChestCooldowns, Quests, Statuses, EquippedSlots, Interactions, Hotbar, etc]

	-- Chest cooldowns
	local ChestCooldowns = pData:WaitForChild("Chests")
	if Data.ChestCooldowns then
		for Name, Cooldown in Data.ChestCooldowns do
			local Value = ChestCooldowns:FindFirstChild(Name)
			if Value then
				Value.Value = math.max(0, Cooldown - RejoinTime)
			end
		end
	end

	-- Quests
	local Quests = pData:WaitForChild("Quests")
	if Data.Quests then
		-- Completed
		for _, questName in Data.Quests.Completed do
			local Value = Instance.new("BoolValue")
			Value.Name = questName
			Value.Value = true
			Value.Parent = Quests.Completed
		end

		-- Active
		for questName, questData in Data.Quests.Active do
			local Folder = Instance.new("Folder")
			Folder.Name = questName
			Folder:SetAttribute("Start", questData.Start or os.time())

			for reqName, reqData in questData.Data do
				local ReqFolder = Instance.new("Folder")
				ReqFolder.Name = reqName

				for valueName, value in reqData do
					if typeof(value) == "boolean" then
						local BoolValue = Instance.new("BoolValue")
						BoolValue.Name = valueName
						BoolValue.Value = value
						BoolValue.Parent = ReqFolder
					elseif typeof(value) == "number" then
						local NumberValue = Instance.new("NumberValue")
						NumberValue.Name = valueName
						NumberValue.Value = value
						NumberValue.Parent = ReqFolder
					end
				end

				ReqFolder.Parent = Folder
			end

			Folder.Parent = Quests.Active
		end
	end

	-- Equipped accessories
	local EquippedSlots = pData:WaitForChild("EquippedSlots")
	if Data.EquippedSlots then
		for index, itemName in Data.EquippedSlots do
			local Slot = EquippedSlots:FindFirstChild(tostring(index))
			if Slot then
				Slot.Value = itemName
			end
		end
	end

	-- Preferences / Misc
	pData:WaitForChild("ActiveArmor").Value = Data.ActiveArmor or ""

	local Hotbar = pData:WaitForChild("Hotbar")
	if Data.Hotbar then
		for slotNumber, itemName in Data.Hotbar do
			local Slot = Hotbar:FindFirstChild(slotNumber)
			if Slot then
				Slot.Value = itemName or ""
			end
		end
	end

	-- Saved position
	if Data.SavedCFrame then
		task.spawn(function()
			local Character = Player.Character or Player.CharacterAdded:Wait()
			Player.CharacterAppearanceLoaded:Wait()
			task.wait(0.5)
			Character:PivotTo(CFrame.new(Data.SavedCFrame.X, Data.SavedCFrame.Y, Data.SavedCFrame.Z))
		end)
	end
end

-- Saves per item registry (unchanged)
local function UnloadTools(ConvertedToolTable, Folder, Player, AssetType)
	local StarterGear = Player:WaitForChild("StarterGear")
	local Backpack = Player:WaitForChild("Backpack")

	for ItemName, Value in ConvertedToolTable do
		if Value <= 0 then
			continue
		end

		local Library = ContentLibrary[AssetType] or {}

		local Tool = Library[ItemName]
		if Tool then
			if not StarterGear:FindFirstChild(Tool.Name) then
				Tool.Instance:Clone().Parent = StarterGear
			end

			if not Backpack:FindFirstChild(Tool.Name) then
				Tool.Instance:Clone().Parent = Backpack
			end

			local Stat = CreateStat("NumberValue", ItemName)
			Stat.Parent = Folder
			Stat.Value = Value
		end
	end
end

-- Yields until the game considers the game as being able to call a save/load to datastores (unchanged)
local function WaitForRequestBudget(RequestType)
	local CurrentBudget = DataStoreService:GetRequestBudgetForRequestType(RequestType)
	while CurrentBudget < 1 do
		CurrentBudget = DataStoreService:GetRequestBudgetForRequestType(RequestType)
		task.wait(5)
	end
end

-- Helper to compose DataStore key per slot
local function DataKeyFor(player, slot)
	slot = tonumber(slot) or 1
	slot = math.clamp(slot, 1, 3)
	return "user/" .. player.UserId .. "/slot" .. tostring(slot)
end

-- Attempt to save user data. Now saves per-slot key. Returns whether or not the request was successful.
local function SaveData(Player: Player): boolean
	if not Player:GetAttribute("DataLoaded") then
		return false
	end

	local pData = PlayerData:FindFirstChild(Player.UserId)
	local StarterGear = Player:FindFirstChild("StarterGear")
	if not pData or not StarterGear then
		return false
	end

	-- Same Key Cooldown (can't write to the same key within GameConfig.PreLoadTime)
	if SameKeyCooldown[Player.UserId] then
		repeat task.wait() until not SameKeyCooldown[Player.UserId]
	end
	SameKeyCooldown[Player.UserId] = true
	task.delay(GameConfig.PreLoadTime, function()
		SameKeyCooldown[Player.UserId] = nil
	end)

	-- Compose DataToSave (same structure as original)
	local DataToSave = {}
	DataToSave.Stats = {}
	DataToSave.Items = {}

	DataToSave.Attributes = {}
	DataToSave.ChestCooldowns = {}

	DataToSave.Statuses = {}

	DataToSave.Quests = {
		Completed = {},
		Active = {},
	}

	DataToSave.Interactions = {}

	DataToSave.EquippedSlots = {}
	for Iteration = 1, GameConfig.EquippedAccessoryMax do
		DataToSave.EquippedSlots[Iteration] = ""
	end

	-- Stats
	local Stats = pData:FindFirstChild("Stats")
	for _, ValueObject in Stats:GetChildren() do
		DataToSave.Stats[ValueObject.Name] = ValueObject.Value
	end

	-- LifeHearts (SISTEMA NOVO)
	local LifeHearts = pData:FindFirstChild("LifeHearts")
	if LifeHearts then
		DataToSave.LifeHearts = LifeHearts.Value
	end

	-- Items
	local Items = pData:FindFirstChild("Items")
	local function CollectiveSave(AssetType)
		local Folder = Items:FindFirstChild(AssetType)
		if not Folder then
			warn(`DataManager: folder for {AssetType} doesn't exist!`)
			return
		end

		for _, ValueObject in Folder:GetChildren() do
			local DontSave = ValueObject:GetAttribute("DontSave")
			if not ValueObject:IsA("NumberValue") and DontSave then
				continue
			end

			local Library = ContentLibrary[AssetType] or {}
			if Library[ValueObject.Name] then
				if ValueObject:IsA("NumberValue") then
					DataToSave.Items[AssetType][ValueObject.Name] = ValueObject.Value - (DontSave or 0)
				else
					table.insert(DataToSave.Items[AssetType], ValueObject.Name)
				end
			end
		end
	end

	for ItemType, Data in GameConfig.Categories do
		DataToSave.Items[ItemType] = {}
		CollectiveSave(ItemType)
	end

	-- Attributes
	for _, Attribute in pData.Attributes:GetChildren() do
		DataToSave.Attributes[Attribute.Name] = Attribute.Value
	end

	DataToSave.Points = pData.Points.Value

	-- Chest cooldowns
	for _, Cooldown in pData.Chests:GetChildren() do
		DataToSave.ChestCooldowns[Cooldown.Name] = Cooldown.Value
	end

	-- Quests
	for _, Value in pData.Quests.Completed:GetChildren() do
		table.insert(DataToSave.Quests.Completed, Value.Name)
	end

	for _, Folder in pData.Quests.Active:GetChildren() do
		local SaveTable = {}

		local QuestData = QuestLibrary[Folder.Name]
		if not QuestData then
			warn(`[KIT: Quest {Folder.Name} no longer exists but is in players' datastore. Was this a mistake? (2)]`)
			continue
		end

		for Name, Data in QuestData.Requirements do
			SaveTable[Name] = {}

			for NewName, Value in Data do
				if typeof(Value) == "function" then
					SaveTable[Name][NewName] = false
				else
					SaveTable[Name][Value[1]] = 0
				end
			end
		end 

		for _, NewFolder in Folder:GetChildren() do
			for _, Value in NewFolder:GetChildren() do
				SaveTable[NewFolder.Name][Value.Name] = Value.Value
			end
		end

		DataToSave.Quests.Active[Folder.Name] = {
			Data = SaveTable,
			Start = Folder:GetAttribute("Start") or os.time()
		}
	end

	-- Potion effects
	local Statuses = Player:FindFirstChild("Statuses")
	if Statuses then
		for _, Status in Statuses:GetChildren() do
			DataToSave.Statuses[Status.Name] = {
				Duration = Status:GetAttribute("Duration"),
				Boost = Status:GetAttribute("Boost"),
				Addition = Status:GetAttribute("Addition"),
			}
		end
	end

	-- NPC interactions
	local Interactions = pData:FindFirstChild("Interactions")
	if Interactions then
		for _, Value in Interactions:GetChildren() do
			DataToSave.Interactions[Value.Name] = Value.Value
		end
	end

	-- Equipped accessories
	for Index in DataToSave.EquippedSlots do
		local Value = pData.EquippedSlots:FindFirstChild(tostring(Index))
		if Value then
			DataToSave.EquippedSlots[Index] = Value.Value
		end
	end

	-- Preferences / Misc
	local SavedCFrame = AttributeModule:GetAttribute(Player, "SavedCFrame")

	if GameConfig.SaveCurrentLocation and SavedCFrame and not AttributeModule:GetAttribute(Player, "DontSaveCFrame") then
		DataToSave.SavedCFrame = {
			X = SavedCFrame.Position.X,
			Y = SavedCFrame.Position.Y,
			Z = SavedCFrame.Position.Z
		}
	end

	DataToSave.ActiveArmor = pData.ActiveArmor.Value

	DataToSave.Hotbar = {}
	for _, ValueObject in pData.Hotbar:GetChildren() do
		DataToSave.Hotbar[ValueObject.Name] = ValueObject.Value
	end

	DataToSave.LastJoin = tick()
	DataToSave.Converted = true

	-- Save to DataStore using slot key
	local slot = Player:GetAttribute("Slot") or 1
	slot = math.clamp(slot, 1, 3)
	DataToSave.ActiveSlot = slot

	local Success = nil :: boolean
	local Response = nil :: any
	local key = DataKeyFor(Player, slot)

	repeat
		WaitForRequestBudget(Enum.DataStoreRequestType.SetIncrementAsync)

		Success, Response = pcall(function()
			return UserData:UpdateAsync(key, function(old)
				-- Return DataToSave to write it
				return DataToSave
			end)
		end)
	until Success

	print(`DataManager: User {Player.Name}'s data (slot {slot}) saved successfully.`)

	return Success
end

-- Attempt to load user data. Now loads per-slot, with legacy fallback/migration.
local function LoadData(Player: Player): (boolean, any)
	local Success = nil :: boolean
	local Response = nil :: any

	-- Step 1: Try to load legacy "user/<UserId>" to fetch last ActiveSlot if present (non-destructive)
	local legacySuccess, legacyResponse = pcall(function()
		local requested = nil
		UserData:UpdateAsync("user/".. Player.UserId, function(data)
			requested = data
		end)
		return requested
	end)

	-- Determine player's slot: priority -> player's attribute (if set) -> legacy.ActiveSlot -> default 1
	local pickedSlot = Player:GetAttribute("Slot")
	if not pickedSlot then
		if legacySuccess and legacyResponse and type(legacyResponse) == "table" and legacyResponse.ActiveSlot then
			pickedSlot = tonumber(legacyResponse.ActiveSlot) or 1
		else
			pickedSlot = 1
		end
	end
	pickedSlot = math.clamp(pickedSlot, 1, 3)
	Player:SetAttribute("Slot", pickedSlot)

	-- Step 2: Try to load per-slot data
	local slotKey = DataKeyFor(Player, pickedSlot)

	repeat
		Success, Response = pcall(function()
			local requested = nil
			UserData:UpdateAsync(slotKey, function(data)
				requested = data
			end)
			return requested
		end)

		if (not Success) or (Response == "wait") then
			task.wait(4)
		end
	until Success

	-- If slot data not present but legacy data exists, migrate legacy to slot1 (only if pickedSlot == 1)
	if not Response and legacySuccess and legacyResponse then
		-- Use legacy data as slot1 backup/migration
		if pickedSlot == 1 then
			Response = legacyResponse
			-- Save migrated data to slot key (best-effort)
			local migrated = false
			local saveOk, _ = pcall(function()
				-- Write legacy data into slot1 key
				UserData:UpdateAsync(slotKey, function() return Response end)
				migrated = true
			end)
			if migrated then
				print(`DataManager: Migrated legacy data for user {Player.Name} into slot1.`)
			end
		end
	end

	if Response then
		local lv = (Response.Stats and Response.Stats.Level) and Response.Stats.Level or "?"
		print(`DataManager: User {Player.Name}'s data (slot {pickedSlot}) loaded into the game with Level {lv}.`)
	else
		print(`DataManager: User {Player.Name} has loaded into the game for the first time on slot {pickedSlot}.`)
	end

	return true, Response
end

-- Função para resetar a pasta de dados
local function ResetDataFolder(pData: Instance, Player: Player)
	local ItemsFolder = pData:FindFirstChild("Items")
	if not ItemsFolder then return end

	-- Para cada tipo de item
	for _, TypeFolder in ipairs(ItemsFolder:GetChildren()) do
		if TypeFolder:IsA("Folder") then
			-- Remove todos os itens dentro do tipo
			for _, Item in ipairs(TypeFolder:GetChildren()) do
				Item:Destroy()
			end
		end
	end
end

-- On player added: load selected slot (default 1) and populate pData (keeps structure)
local function OnPlayerAdded(Player)
	Player:SetAttribute("Slot", Player:GetAttribute("Slot") or 1)
	Player:SetAttribute("DataLoaded", false)

	local ok, data = LoadData(Player)
	if not ok then Player:Kick("DataStore falhou.") return end

	local pData = CreateDataFolder(Player)
	pData:SetAttribute("Slot", Player:GetAttribute("Slot") or 1)
	if data then task.wait(0.5) UnloadData(Player, data, pData) end
	pData.Parent = PlayerData
	Player:SetAttribute("DataLoaded", true)
	SetupLifeHeartsSystem(Player)
	repeat task.wait() until PlayerData:FindFirstChild(Player.UserId)
	OpenCharacterMenu:FireClient(Player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
for _, p in Players:GetPlayers() do OnPlayerAdded(p) end

Players.PlayerRemoving:Connect(function(p)
	SaveData(p)
	local old = PlayerData:FindFirstChild(p.UserId)
	if old then old:Destroy() end
end)

ResetCharacterEvent.OnServerEvent:Connect(function(player)
	if player and player.Parent then ResetCharacterCompletely(player) end
end)

game:BindToClose(function()
	if RunService:IsStudio() then return end
	for _, p in Players:GetPlayers() do SaveData(p) end
	task.wait(1)
end)

while task.wait(GameConfig.SaveTime) do
	for _, p in Players:GetPlayers() do task.spawn(SaveData, p) end
end



Players.PlayerAdded:Connect(OnPlayerAdded)
for _, p in Players:GetPlayers() do OnPlayerAdded(p) end

-- Save on leave (saves to slot key)
Players.PlayerRemoving:Connect(function(Player)
	SaveData(Player)

	local oldData = PlayerData:FindFirstChild(Player.UserId)
	if oldData then
		oldData:Destroy()
	end
end)

-- RemoteEvent: change slot (1..3) - com reset seguro do PlayerData
ChangeSlotEvent.OnServerEvent:Connect(function(Player, NewSlot)
	local slot = tonumber(NewSlot)
	if not slot or slot < 1 or slot > 3 then return end

	-- Salva slot anterior
	SaveData(Player)

	-- Desativa temporariamente o DataLoaded
	Player:SetAttribute("DataLoaded", false)

	-- Pega a pasta existente de PlayerData
	local pData = PlayerData:FindFirstChild(Player.UserId)
	if pData then
		-- Limpa todo o conteúdo da pasta sem destruir a referência
		ResetDataFolder(pData, Player)
	else
		-- Caso não exista (raro), cria normalmente
		pData = CreateDataFolder(Player)
		pData.Parent = PlayerData
	end

	-- Limpa inventário/statuses atuais do jogador
	for _, obj in ipairs({"Backpack", "StarterGear", "Statuses"}) do
		local f = Player:FindFirstChild(obj)
		if f then
			for _, c in f:GetChildren() do
				c:Destroy()
			end
		end
	end

	-- Define novo slot
	Player:SetAttribute("Slot", slot)

	-- Carrega dados do slot selecionado
	local ok, data = LoadData(Player)
	if not ok then
		warn("Erro ao trocar de slot para o jogador " .. Player.Name)
		return
	end

	-- Reaplica os dados carregados
	if data then
		task.wait(0.5)
		UnloadData(Player, data, pData)
	end

	-- Reset LifeHearts quando troca de slot
	ResetLifeHearts(Player)

	-- Certifica-se que o PlayerData está visível/ativo
	pData.Parent = PlayerData

	-- Configura o sistema de LifeHearts novamente
	SetupLifeHeartsSystem(Player)

	-- Pequeno delay para garantir que todos os sistemas estão prontos
	task.wait(3)

	-- Marca DataLoaded como true
	Player:SetAttribute("DataLoaded", true)
end)

-- Adiciona handler para reset manual via cliente (opcional)
ResetCharacterEvent.OnServerEvent:Connect(function(player)
	if player and player.Parent then
		ResetCharacterCompletely(player)
	end
end)

-- Server closing: save all players (unchanged logic)
game:BindToClose(function()
	if RunService:IsStudio() then
		print("DataManager: Can't save BindToClose in studio.")
		task.wait(1)
		return
	end

	for _, Player in Players:GetPlayers() do
		SaveData(Player)
	end
	task.wait(1)
end)

-- Auto-save loop (unchanged)
while task.wait(GameConfig.SaveTime) do
	for _, Player in Players:GetPlayers() do
		task.spawn(SaveData, Player)
	end
end

return {}