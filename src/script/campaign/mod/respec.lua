local options = {
    cost = {
        resource_key = "troy_gold",
        amount = 10
    }
}

local SAVE_KEY_PREFIX = "mk_respec_count_cqi_"

local function log(msg)
    out("respec: " .. tostring(msg))
end

local function createConfirmationBox(id, text, on_accept_callback, on_cancel_callback)
	local confirmation_box = core:get_or_create_component(id, "ui/Common UI/dialogue_box")
	confirmation_box:SetVisible(true)
	confirmation_box:LockPriority()
	confirmation_box:RegisterTopMost()
	confirmation_box:SequentialFind("ok_group"):SetVisible(false)

	local dy_text = find_uicomponent(confirmation_box, "DY_text")
	dy_text:SetStateText(text, text)

	local accept_fn = function()
        confirmation_box:UnLockPriority()
        confirmation_box:Destroy()
        core:remove_listener(id .. "_confirmation_box_reject")

        if core:is_campaign() then
            cm:release_escape_key_with_callback(id .. "_confirmation_box_esc")
        elseif core:is_battle() then
            bm:release_escape_key_with_callback(id .. "_confirmation_box_esc")
        else
            effect.disable_all_shortcuts(false)
        end

        if on_accept_callback then
            on_accept_callback()
        end
    end

	local cancel_fn = function()
        confirmation_box:UnLockPriority()
        confirmation_box:Destroy()
        core:remove_listener(id .. "_confirmation_box_accept")

        if core:is_campaign() then
            cm:release_escape_key_with_callback(id .. "_confirmation_box_esc")
        elseif core:is_battle() then
            bm:release_escape_key_with_callback(id .. "_confirmation_box_esc")
        else
            effect.disable_all_shortcuts(false)
        end

        if on_cancel_callback then
            on_cancel_callback()
        end
    end

	core:add_listener(
		id .. "_confirmation_box_accept",
		"ComponentLClickUp",
		function(context)
			return context.string == "button_tick"
		end,
		accept_fn,
		false
	)

	core:add_listener(
		id .. "_confirmation_box_reject",
		"ComponentLClickUp",
		function(context)
			return context.string == "button_cancel"
		end,
		cancel_fn,
		false
	)

	if core:is_campaign() then
		cm:steal_escape_key_with_callback(id .. "_confirmation_box_esc", cancel_fn)
	elseif core:is_battle() then
		bm:steal_escape_key_with_callback(id .. "_confirmation_box_esc", cancel_fn)
	else
		effect.disable_all_shortcuts(true)
    end
    
    return confirmation_box
end

local function removeComponent(component)
    if not component then
        return
    end

    local root = core:get_ui_root()
    local dummy = find_uicomponent(root, 'DummyComponent')
    if not dummy then
        root:CreateComponent("DummyComponent", "UI/campaign ui/script_dummy")        
    end
    
    local gc = UIComponent(root:Find("DummyComponent"))
    gc:Adopt(component:Address())
    gc:DestroyChildren()
end

local function getSelectedCharCQI()
    local charCQI = cm:get_campaign_ui_manager():get_char_selected_cqi()
    local char = cm:get_character_by_cqi(charCQI)
    if char:has_military_force() then
        local unitsUIC = find_uicomponent(core:get_ui_root(), "units_panel", "main_units_panel", "units")
        for i = 0, unitsUIC:ChildCount() - 1 do
            local uic_child = UIComponent(unitsUIC:Find(i))
            if uic_child:CurrentState() == "Selected" and string.find(uic_child:Id(), "Agent") then
                local charList = char:military_force():character_list()
                local agentIndex = string.match(uic_child:Id(), "%d")
                local selectedChar = charList:item_at(tonumber(agentIndex))
                charCQI = selectedChar:command_queue_index()
                break
            end     
        end
    end
    return charCQI
end


local function getCost(rank, respecCount)
    rank = rank or 1
    respecCount = respecCount or 1

    local baseCost = options.cost.amount
    local cost = rank * baseCost

    for i = 1, respecCount do
        cost = cost * 2
    end

    return cost
end

local function resetSkills(cqi, cost)
    local char = cm:get_character_by_cqi(cqi)
    local saveKey = SAVE_KEY_PREFIX .. cqi

    local savedCount = tonumber(cm:get_saved_value(saveKey))
    if not savedCount then
        cm:set_saved_value(saveKey, 1)
    else
        cm:set_saved_value(saveKey, savedCount + 1)
    end

    cm:faction_add_pooled_resource(char:faction():name(), options.cost.resource_key, "troy_resource_factor_faction", -1 * cost)
    cm:force_reset_skills(cm:char_lookup_str(cqi))

    local buttonOK = find_uicomponent(core:get_ui_root(), "character_details_panel", "button_ok")
    if buttonOK then 
        buttonOK:SimulateLClick()
    end

    local buttonSkill = find_uicomponent(core:get_ui_root(), "CharacterInfoPopup", "skill_button")
    if buttonSkill then 
        buttonSkill:SimulateLClick()
    end
end

local function createButton(subtype)
    local existingButton = find_uicomponent(core:get_ui_root(), "character_details_panel", subtype .. "_force_reset_skills_button")
    if existingButton then
        removeComponent(existingButton)
    end

    log("create button for " .. getSelectedCharCQI());
    log("rank" .. cm:get_character_by_cqi(getSelectedCharCQI()):rank());

    local skill_points_holder = find_uicomponent(core:get_ui_root(), "character_details_panel", subtype .. "_info", "skill_points_holder")
    local button = core:get_or_create_component(subtype .. "_force_reset_skills_button", "ui/templates/round_small_button")
    local reset_skill_button = find_uicomponent(core:get_ui_root(), "character_details_panel", "button_stats_reset")

    local bW, bH = reset_skill_button:Bounds()
    local bX, bY = reset_skill_button:Position()

    button:SetImagePath("script/console/icon_reset.png")
    button:Resize(bW - 2, bH - 2)
    button:MoveTo(bX - bW, bY + 1)

    local cqi = getSelectedCharCQI()
    local char = cm:get_character_by_cqi(cqi)
    
    local cost = char:rank() * options.cost.amount
    local treasury = char:faction():pooled_resource("troy_gold"):value()

    local saveKey = SAVE_KEY_PREFIX .. cqi
    local savedRespecCount = tonumber(cm:get_saved_value(saveKey))
    if savedRespecCount then
        cost = getCost(char:rank(), savedRespecCount)
    end

    local tooltip = "Reset all skills on this " .. subtype .. "."
    if cost > treasury then
        tooltip = "[[col:red]]You don't have enough funds![[/col]]\n\nRespeccing this character would cost you ".. cost .." [[img:ui/campaign ui/pooled_resources/icon_res_gold_medium.png]].", ""
        button:SetState("inactive")
    else
        tooltip = tooltip .. "\n\nRespeccing this character would cost you " .. cost .. " [[img:ui/campaign ui/pooled_resources/icon_res_gold_medium.png]]."
        button:SetState("active")
    end

    if char:rank() == 1 then
        tooltip = "[[col:red]]Character is rank 1. No skill points allocated.[[/col]]"
        button:SetState("inactive")
    end

    button:SetTooltipText(tooltip, true)

    button:PropagatePriority(skill_points_holder:Priority())
    skill_points_holder:Adopt(button:Address())
    
    local listener = subtype .. "_respec_skills_button_listener"
    core:remove_listener(listener)
    core:add_listener(
        listener,
        "ComponentLClickUp",
        function(context) return button == UIComponent(context.component) end,    
        function(context)
            local content = "Would you like to fully respec this character ?"
            if cost > treasury then
                content = "[[col:red]]You don't have enough funds![[/col]]\n\nRespeccing this character would cost you ".. cost .." [[img:ui/campaign ui/pooled_resources/icon_res_gold_medium.png]].", ""
            else
                content = content .. "\n\nRespeccing this character would cost you " .. cost .. " [[img:ui/campaign ui/pooled_resources/icon_res_gold_medium.png]]."
                content = content .. "\n\nNext respec cost: " .. cost * 2 .. " [[img:ui/campaign ui/pooled_resources/icon_res_gold_medium.png]].", ""
            end

            if char:rank() == 1 then
                content = "[[col:red]]Character is rank 1. No skill points allocated.[[/col]]"
            end

            local confirmBox = createConfirmationBox(
                "respec_confirm_box",
                content,
                function()
                    resetSkills(cqi, cost)
                end,
                function()
                    -- log("nope")
                end
            )

            local okButton = find_uicomponent(confirmBox, "both_group", "button_tick")
            if cost > treasury or char:rank() == 1 then
                okButton:SetTooltipText(content, true)
                okButton:SetState("inactive")
            end
        end,
        true
    )
end

local function createButtons()
    cm:callback(function() createButton("hero") end, 0.1)
    cm:callback(function() createButton("agent") end, 0.1)
end

local function init()
    local listeners = {
        panelOpened = "respec_skills_button_listener",
        characterSelected = "respec_character_selected_listener",
    }

    core:remove_listener(listeners.panelOpened)
    core:remove_listener(listeners.characterSelected)

    core:add_listener(
        listeners.panelOpened,
        "PanelOpenedCampaign",
        function(context)
            return context.string == "character_details_panel"
        end,
        createButtons,
        true
    )

    core:add_listener(
        listeners.characterSelected,
        "CharacterSelected",
        function(context)
            return is_uicomponent(find_uicomponent(core:get_ui_root(), "character_details_panel"))
        end,
        createButtons,
        true
    )
end

cm:add_first_tick_callback(init)