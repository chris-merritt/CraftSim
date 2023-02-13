_, CraftSim = ...

---@class CraftSim.RecipeData
---@field recipeID number 
---@field categoryID number
---@field subtypeID number
---@field recipeType number
---@field learned boolean
---@field numSkillUps? number
---@field recipeIcon? string
---@field recipeName? string
---@field supportsQualities boolean
---@field supportsCraftingStats boolean
---@field supportsInspiration boolean
---@field supportsMulticraft boolean
---@field supportsResourcefulness boolean
---@field supportsCraftingspeed boolean
---@field isGear boolean
---@field isSoulbound boolean
---@field isEnchantingRecipe boolean
---@field isSalvageRecipe boolean
---@field baseItemAmount number
---@field maxQuality number
---@field allocationItemGUID? string
---@field professionData CraftSim.ProfessionData
---@field reagentData CraftSim.ReagentData
---@field specializationData CraftSim.SpecializationData
---@field professionGearSet CraftSim.ProfessionGearSet
---@field professionStats CraftSim.ProfessionStats The ProfessionStats of that recipe considering gear, reagents, buffs.. etc
---@field baseProfessionStats CraftSim.ProfessionStats The ProfessionStats of that recipe without gear or reagents
---@field professionStatModifiers CraftSim.ProfessionStats Will add/subtract to final stats (Used in Simulation Mode, usually 0)
---@field priceData CraftSim.PriceData
---@field resultData CraftSim.ResultData

CraftSim.RecipeData = CraftSim.Object:extend()

local print = CraftSim.UTIL:SetDebugPrint(CraftSim.CONST.DEBUG_IDS.EXPORT_V2)

---@return CraftSim.RecipeData?
function CraftSim.RecipeData:new(recipeID, isRecraft)
    self.professionData = CraftSim.ProfessionData(recipeID)

    if not self.professionData.isLoaded then
        print("Could not create recipeData: professionData not loaded")
        return nil
    end

    
    local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
    
	if not recipeInfo then
		print("Could not create recipeData: recipeInfo nil")
		return nil
	end
    
    self.recipeID = recipeID
    self.categoryID = recipeInfo.categoryID

    if recipeInfo.hyperlink then
        local subclassID = select(7, GetItemInfoInstant(recipeInfo.hyperlink))
        self.subtypeID = subclassID
    end
    
    self.isRecraft = isRecraft or false
    self.recipeType = CraftSim.UTIL:GetRecipeType(recipeInfo)
    self.learned = recipeInfo.learned or false
	self.numSkillUps = recipeInfo.numSkillUps
	self.recipeIcon = recipeInfo.icon
	self.recipeName = recipeInfo.name
	self.supportsQualities = recipeInfo.supportsQualities or false
	self.supportsCraftingStats = recipeInfo.supportsCraftingStats or false
    self.isEnchantingRecipe = recipeInfo.isEnchantingRecipe or false
    self.isSalvageRecipe = recipeInfo.isSalvageRecipe or false
    self.allocationItemGUID = nil
    self.maxQuality = recipeInfo.maxQuality
    self.isGear = recipeInfo.hasSingleItemOutput and recipeInfo.qualityIlvlBonuses ~= nil

    self.supportsInspiration = false
    self.supportsMulticraft = false
    self.supportsResourcefulness = false
    self.supportsCraftingspeed = true -- this is always supported (but does not show in details UI when 0)

    -- fetch possible required/optional/finishing reagents, if possible categorize by quality?

    self.specializationData = CraftSim.SpecializationData(self)

    local schematicInfo = C_TradeSkillUI.GetRecipeSchematic(self.recipeID, self.isRecraft)
    if not schematicInfo then
        print("No RecipeData created: SchematicInfo not found")
        return
    end
    self.reagentData = CraftSim.ReagentData(self, schematicInfo)

    self.baseItemAmount = (schematicInfo.quantityMin + schematicInfo.quantityMax) / 2
    self.isSoulbound = (schematicInfo.outputItemID and CraftSim.UTIL:isItemSoulbound(schematicInfo.outputItemID)) or false

    self.professionGearSet = CraftSim.ProfessionGearSet(self.professionData.professionInfo.profession)
    
    local baseOperationInfo = C_TradeSkillUI.GetCraftingOperationInfo(self.recipeID, {}, self.allocationItemGUID)
    
    self.baseProfessionStats = CraftSim.ProfessionStats()
    self.professionStats = CraftSim.ProfessionStats()
    self.professionStatModifiers = CraftSim.ProfessionStats()
    
    self.baseProfessionStats:SetStatsByOperationInfo(self, baseOperationInfo)

    self.baseProfessionStats:SetInspirationBaseBonusSkill(self.baseProfessionStats.recipeDifficulty.value, self.maxQuality)

    -- subtract stats from current set to get base stats
    local equippedProfessionGearSet = CraftSim.ProfessionGearSet(self.professionData.professionInfo.profession)
    equippedProfessionGearSet:LoadCurrentEquippedSet()
    
    self.baseProfessionStats:subtract(equippedProfessionGearSet.professionStats)
    -- As we dont know in this case what the factors are without gear and reagents and such
    -- we set them to 0 and let them accumulate in UpdateProfessionStats
    self.baseProfessionStats:ClearFactors()

    self:UpdateProfessionStats()
    
    self.resultData = CraftSim.ResultData(self)
    self.resultData:Update()

    self.priceData = CraftSim.PriceData(self)
end

---@class CraftSim.ReagentListItem
---@field itemID number
---@field quantity number

---@param reagentList CraftSim.ReagentListItem[]
function CraftSim.RecipeData:SetReagents(reagentList)
    -- go through required reagents and set quantity accordingly

    for _, reagent in pairs(self.reagentData.requiredReagents) do
        local totalQuantity = 0
        for _, reagentItem in pairs(reagent.items) do
            local listReagent = CraftSim.UTIL:Find(reagentList, function(listReagent) return listReagent.itemID == reagentItem.item:GetItemID() end)
            if listReagent then
                reagentItem.quantity = listReagent.quantity
                totalQuantity = totalQuantity + listReagent.quantity
            end
        end
        if totalQuantity > reagent.requiredQuantity then
            error("CraftSim: RecipeData SetReagents Error: total set quantity > requiredQuantity -> " .. totalQuantity .. " / " .. reagent.requiredQuantity)
        end
    end
end

---@param itemID number
function CraftSim.RecipeData:SetSalvageItem(itemID)
    if self.isSalvageRecipe then
        self.reagentData.salvageReagentSlot:SetItem(itemID)
    else
        error("CraftSim Error: Trying to set salvage item on non salvage recipe")
    end
end

function CraftSim.RecipeData:SetEquippedProfessionGearSet()
    self.professionGearSet:LoadCurrentEquippedSet()
end

function CraftSim.RecipeData:SetAllReagentsBySchematicForm()
    local schematicInfo = C_TradeSkillUI.GetRecipeSchematic(self.recipeID, self.isRecraft)
    local schematicForm = CraftSim.UTIL:GetSchematicFormByVisibility()
    
    local reagentSlots = schematicForm.reagentSlots
    local currentTransaction = schematicForm:GetTransaction()

    if self.isRecraft then
        self.allocationItemGUID = currentTransaction:GetRecraftAllocation()
    end

    if self.isSalvageRecipe then
        local salvageAllocation = currentTransaction:GetSalvageAllocation()
		if salvageAllocation and schematicForm.salvageSlot then
            self.reagentData.salvageReagentSlot:SetItem(salvageAllocation:GetItemID())
            self.reagentData.salvageReagentSlot.requiredQuantity = schematicForm.salvageSlot.quantityRequired
        elseif not schematicForm.salvageSlot then
            error("CraftSim RecipeData Error: Salvage Recipe without salvageSlot")
        end
    end

    local currentOptionalReagent = 1
	local currentFinishingReagent = 1

    for slotIndex, currentSlot in pairs(schematicInfo.reagentSlotSchematics) do
        local reagentType = currentSlot.reagentType
        if reagentType == CraftSim.CONST.REAGENT_TYPE.REQUIRED then
            local slotAllocations = currentTransaction:GetAllocations(slotIndex)
            
            for i, reagent in pairs(currentSlot.reagents) do
                local reagentAllocation = (slotAllocations and slotAllocations:FindAllocationByReagent(reagent)) or nil
                local allocations = 0
                if reagentAllocation ~= nil then
                    allocations = reagentAllocation:GetQuantity()
                end
                local craftSimReagentItem = nil
                for _, craftSimReagent in pairs(self.reagentData.requiredReagents) do
                    craftSimReagentItem = CraftSim.UTIL:Find(craftSimReagent.items, function(cr) return cr.item:GetItemID() == reagent.itemID end)
                    if craftSimReagentItem then
                        break
                    end
                end
                if not craftSimReagentItem then
                    error("Error: Open Recipe Reagent not included in recipeData")
                end
                craftSimReagentItem.quantity = allocations
            end
            
        elseif reagentType == CraftSim.CONST.REAGENT_TYPE.OPTIONAL then
            if reagentSlots[reagentType] ~= nil then
                local optionalSlots = reagentSlots[reagentType][currentOptionalReagent]
                if not optionalSlots then
                    return
                end
                local button = optionalSlots.Button
                local allocatedItemID = button:GetItemID()
                if allocatedItemID then
                    self:SetOptionalReagent(allocatedItemID)
                end
                
                currentOptionalReagent = currentOptionalReagent + 1
            end

        elseif reagentType == CraftSim.CONST.REAGENT_TYPE.FINISHING_REAGENT then
            if reagentSlots[reagentType] ~= nil then
                local optionalSlots = reagentSlots[reagentType][currentFinishingReagent]
                if not optionalSlots then
                    return
                end
                local button = optionalSlots.Button
                local allocatedItemID = button:GetItemID()
                if allocatedItemID then
                    self:SetOptionalReagent(allocatedItemID)
                end
                
                currentFinishingReagent = currentFinishingReagent + 1
            end
        end
    end
end

---@param itemID number
function CraftSim.RecipeData:SetOptionalReagent(itemID)
    self.reagentData:SetOptionalReagent(itemID)
end

-- Update the professionStats property of the RecipeData according to set reagents and gearSet (and any stat modifiers)
function CraftSim.RecipeData:UpdateProfessionStats()
    local skillRequiredReagents = self.reagentData:GetSkillFromRequiredReagents()
    local optionalStats = self.reagentData:GetProfessionStatsByOptionals()
    local itemStats = self.professionGearSet.professionStats
    local specExtraFactors = self.specializationData:GetExtraFactors()

    self.professionStats:Clear()

    -- Dont forget to set this.. cause it is ignored by add/subtract
    self.professionStats:SetInspirationBaseBonusSkill(self.baseProfessionStats.recipeDifficulty.value, self.maxQuality)

    self.professionStats:add(self.baseProfessionStats)

    self.professionStats.skill:addValue(skillRequiredReagents)

    self.professionStats:add(optionalStats)

    print("stats before item add")
    print(self.professionStats)

    self.professionStats:add(itemStats)

    print("stats before add spec, after item add")
    print(self.professionStats)
    self.professionStats:add(specExtraFactors)
    print("stats after add spec")
    print(self.professionStats)

    -- finally add any custom modifiers
    self.professionStats:add(self.professionStatModifiers)
end

--- Updates professionStats based on reagentData and professionGearSet -> Then updates resultData based on professionStats -> Then updates priceData based on resultData
function CraftSim.RecipeData:Update()
    self:UpdateProfessionStats()
    self.resultData:Update()
    self.priceData:Update()
end

--- We need copy constructors or CopyTable will run into references of recipeData
---@return CraftSim.RecipeData recipeDataCopy
function CraftSim.RecipeData:Copy()
    local copy = CraftSim.RecipeData(self.recipeID, self.isRecraft)
    copy.reagentData = self.reagentData:Copy(copy)
    copy.professionGearSet = self.professionGearSet:Copy()
    copy.professionStats = self.professionStats:Copy()
    copy.baseProfessionStats = self.baseProfessionStats:Copy()
    copy.professionStatModifiers = self.professionStatModifiers:Copy()
    copy.priceData = self.priceData:Copy(copy) -- Is this needed or covered by constructor?
    copy.resultData = self.resultData:Copy(copy) -- Is this needed or covered by constructor?
    -- copy spec data or already handled in constructor?

    copy:Update()
    return copy
end