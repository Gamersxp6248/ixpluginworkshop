PLUGIN.name = "Item Spawn Menu"
PLUGIN.author = "Rune Knight & Khall & ɅµЋƵƵ"
PLUGIN.description = "Adds a tab to the spawn menu for item spawning and the possibility to undo them, now overhauled"

CAMI.RegisterPrivilege({
    Name = "Item Spawn Menu - Spawning",
    MinAccess = "admin"
})

CAMI.RegisterPrivilege({
    Name = "Item Spawn Menu - Wiping",
    MinAccess = "superadmin"
})

function PLUGIN:GetCategoryIcon(category)
    local icons = {
        ["Ammunition"] = "icon16/tab.png",
        ["Signalis - Ammunition"] = "icon16/basket.png",
        ["Clothing"] = "icon16/user_suit.png",
        ["Consumables"] = "icon16/pill.png",
        ["Medical"] = "icon16/heart.png",
        ["misc"] = "icon16/error.png",
        ["Permits"] = "icon16/note.png",
        ["Storage"] = "icon16/package.png",
        ["Weapons"] = "icon16/gun.png",
    }
    
    return hook.Run("GetItemSpawnMenuIcons", category) or icons[category] or "icon16/folder.png"
end

if SERVER then
    util.AddNetworkString("ItemSpawn_Request")
    util.AddNetworkString("ItemGive_Request")
    util.AddNetworkString("ItemClean_Request")
    util.AddNetworkString("ItemTeleport_Request")

    ix.log.AddType("ItemSpawn_Request", function(client, itemName)
        return string.format("%s spawned the item: \"%s\".", client:GetCharacter():GetName(), tostring(itemName))
    end)

    ix.log.AddType("ItemClean_Request", function(client, itemName)
        return string.format("%s completely wiped the item: \"%s\" from all entities / players.", client:GetCharacter():GetName(), tostring(itemName))
    end)

    net.Receive("ItemSpawn_Request", function(len, client)
        local uniqueID = net.ReadString()

        if not CAMI.PlayerHasAccess(client, "Item Spawn Menu - Spawning", nil) then return end

        for _, item in pairs(ix.item.list) do
            if item.uniqueID == uniqueID then
                ix.item.Spawn(item.uniqueID, client:GetShootPos() + client:GetAimVector() * 84 + Vector(0, 0, 16), function(item, entity)
                    if IsValid(entity) then
                        undo.Create(item.name)
                        undo.AddEntity(entity)
                        undo.SetPlayer(client)
                        undo.Finish()
                    end
                end)

                ix.log.Add(client, "ItemSpawn_Request", item.name)
                break
            end
        end
    end)
    
    net.Receive("ItemClean_Request", function(len, client)
        local uniqueID = net.ReadString()
        
        if not CAMI.PlayerHasAccess(client, "Item Spawn Menu - Wiping", nil) then return end
        
        if (!uniqueID or uniqueID == "") then return end
        print("[CleanupAll] Removing all items with uniqueID: " .. uniqueID)
        local counter = 0
        
        -- Player Inventories
        for _, ply in ipairs(player.GetAll()) do
            local char = ply:GetCharacter()
            if (char) then
                local inv = char:GetInventory()
                if (inv) then
                    for _, item in pairs(inv:GetItems(true)) do
                        if (item.uniqueID == uniqueID) then
                            item:Remove()
                            counter = counter + 1
                        end
                    end
                end
            end
        end
        
        local query = string.format("DELETE FROM ix_items WHERE unique_id = '%s';",uniqueID)
        local prequery = sql.Query("SELECT COUNT(*) AS c FROM ix_items WHERE unique_id = '" .. uniqueID .. "';")
        
        counter = counter + ((prequery and tonumber(prequery[1].c)) or 0)
        
        sql.Query(query)
        print("[CleanupAll] Wiped all offline instances from ix_items database") -- I hope
        
        --[[
        local query2 = sql.SQLStr(uniqueID)
        local CharData = sql.Query("SELECT id, data FROM ix_characters;")
        if CharData then
            print("[CleanupAll] Wiped all offline instances from ix_characters") -- I hope
            for _, row in ipairs(CharData) do
                local data = util.JSONToTable(row.data or "{}") or {}
                PrintTable(data)
                local extra = data.inventory or {}
                
                local changed = false
                
                for invID, items in pairs(extra or {}) do
                    for itemID, itemData in pairs(items or {}) do
                        if itemData.uniqueID == uniqueID then
                            extra[invID][itemID] = nil
                            counter = counter + 1
                            changed = true
                        end
                    end
                end
                
                if changed then
                    data.inventory = extra
                    local newJSON = sql.SQLStr(util.TableToJSON(data))
                    sql.Query("UPDATE ix_characters SET data = " .. newJSON .. " WHERE id = " .. row.id .. ";")
                end
            end
        else
            print(sql.LastError())
        end
        ]]
        
        for _, ent in ipairs(ents.GetAll()) do
            if !IsValid(ent) then continue end
            if ent:GetClass() == "ix_item" and ent.GetItemTable and ent:GetItemTable().uniqueID == uniqueID then
                ent:Dissolve( 2, 20 )
                counter = counter + 1
                continue
            end
            local inv = ent.GetInventory and ent:GetInventory()
            if (inv) then
                for _, item in pairs(inv:GetItems(true)) do
                    if (item.uniqueID == uniqueID) then
                        counter = counter + 1
                        item:Remove()
                    end
                end
            end
        end
        
        print("[CleanupAll] We removed an estimated total of: " .. counter .. " items.")
	ix.log.Add(client, "ItemClean_Request", item.name)
    end)
    
    net.Receive("ItemTeleport_Request", function(len, client)
        local uniqueID = net.ReadString()
        
        if not CAMI.PlayerHasAccess(client, "Item Spawn Menu - Spawning", nil) then return end
        
        local TableToSortByDistance = {}
	local furthest = 256000
        for k,item in ipairs(ents.FindByClass( "ix_item" )) do
            if item.GetItemTable and (item:GetItemTable().uniqueID == uniqueID) then
		TableToSortByDistance[#TableToSortByDistance + 1] = item
                continue
            end
        end
        local closestguess = nil
        for k,target in ipairs(TableToSortByDistance) do
            if !closestguess then
                closestguess = target
                furthest = target:GetPos():DistToSqr( client:GetPos() )
                continue
            end
            if furthest > target:GetPos():DistToSqr( client:GetPos() ) then
                closestguess = target
                furthest = target:GetPos():DistToSqr( client:GetPos() )
                continue
            end
        end
        if closestguess then
            client:SetAngles( (closestguess:GetPos() - client:GetPos()):Angle() )
            client:SetPos(closestguess:GetPos() - client:GetAngles():Forward()*50)
            client:SetEyeAngles( (closestguess:GetPos() - client:EyePos()):Angle() )
            return
        end
        client:Notify("There is no " .. uniqueID .. " nearby!")
    end)

    net.Receive("ItemGive_Request", function(len, player)
        if not CAMI.PlayerHasAccess(player, "Item Spawn Menu - Spawning", nil) then return end

        local data = net.ReadString()
        if #data <= 0 then return end

        local uniqueID = data:lower()

        if not ix.item.list[uniqueID] then
            for k, v in SortedPairs(ix.item.list) do
                if ix.util.StringMatches(v.name, uniqueID) then
                    uniqueID = k
                    break
                end
            end
        end

        local success, error = player:GetCharacter():GetInventory():Add(uniqueID, 1)

        if success then
            player:NotifyLocalized("itemCreated")
        else
            player:NotifyLocalized(tostring(error))
        end
    end)
else
	local PLUGIN = PLUGIN
    
    local matOutline = Material( "gui/contenticon-hovered.png", "nocull" )
    local function OpenItemCleanPopup(item)
        local frame = vgui.Create("DFrame")
        frame:SetTitle("Confirm Delete All")
        frame:SetSize(400, 200)
        frame:Center()
        frame:MakePopup()
        frame:DoModal()
        frame:SetBackgroundBlur(true)
        
        local label = vgui.Create("DLabel", frame)
        label:SetText("Вы уверены, что хотите удалить все копии этого предмета?\n\n" ..
            "Это удалит все версии этого предмета из:\n" ..
            "• Сетевой инвентарь игрока\n" ..
            "• Персонажи офлайн-игроков\n" ..
            "• Список контейнеров\n" ..
            "• Предметы, выпавшие на землю")
        label:SetWrap(true)
        label:SetSize(360, 120)
        label:SetPos(20, 30)
        
        local yesBtn = vgui.Create("DButton", frame)
        yesBtn:SetText("Да, уничтожить все копии этого предмета.")
        yesBtn:SetSize(360, 30)
        yesBtn:SetPos(20, 150)
        yesBtn.DoClick = function()
            net.Start("ItemClean_Request")
            net.WriteString(item.uniqueID)
            net.SendToServer()
            frame:Close()
        end
        
        local noBtn = vgui.Create("DButton", frame)
        noBtn:SetText("Нет, я нажал на эту кнопку по ошибке.")
        noBtn:SetSize(360, 30)
        noBtn:SetPos(20, 185)
        noBtn.DoClick = function()
            frame:Close()
        end
        
        frame:SetTall(230) -- Extend height to fit buttons cleanly
    end
    
    function PLUGIN:InitializedPlugins()
        if SERVER then return end
        RunConsoleCommand("spawnmenu_reload")
    end

    spawnmenu.AddCreationTab("Items", function()
        local panel = vgui.Create("SpawnmenuContentPanel")
        local tree, nav = panel.ContentNavBar.Tree, panel.OldSpawnlists

        local categories = {}
        for uid, item in pairs(ix.item.list) do
            local category = item.category
            categories[category] = categories[category] or {}
            table.insert(categories[category], item)
        end

        for category, items in SortedPairs(categories) do
            local icon16 = PLUGIN:GetCategoryIcon(category)
            local node = tree:AddNode(L(category), icon16)
            node.DoClick = function(self)
                if self.PropPanel and IsValid(self.PropPanel) then 
                    self.PropPanel:Remove()
                    self.PropPanel = nil
                end

                self.PropPanel = vgui.Create("ContentContainer", panel)
                self.PropPanel:SetVisible(false)
                self.PropPanel:SetTriggerSpawnlistChange(false)

                for _, item in SortedPairsByMemberValue(items, "name") do
                    spawnmenu.CreateContentIcon("item", self.PropPanel, {
                        nicename = item.spawnmenulabel or (item.GetName and item:GetName()) or item.name,
                        spawnname = item.uniqueID,
                    })
                end

                panel:SwitchPanel(self.PropPanel)
            end
        end

        local firstNode = tree:Root():GetChildNode(0)
        if IsValid(firstNode) then
            firstNode:InternalDoClick()
        end

        return panel
    end, "icon16/cog_add.png", 201)

    spawnmenu.AddContentType("item", function(panel, data)
        local name, uniqueID = data.nicename, data.spawnname
        local icon = vgui.Create("SpawnIcon", panel)

        local item = ix.item.list[uniqueID]
        
        icon:SetWide(128 * item.width)
        icon:SetTall(128 * item.height)
        icon:InvalidateLayout(true)

        icon:SetModel((item.GetModel and item:GetModel()) or item.model,(item.GetSkin and item:GetSkin()) or item.skin)
        --icon:SetText( name )
        local tooltiptodisplay = name .. " (" .. uniqueID .. ")\n\n"
        local displaylooper = 1
        for k,v in ipairs(string.Explode( " ", item.description )) do
            if string.find( v, "\n", 1, true ) then
                displaylooper = -2 -- Descriptions that already indent should have some leniency
            end
            v = v .. " "
            
            if displaylooper >= 8 then
                displaylooper = 0
                tooltiptodisplay = tooltiptodisplay .. "\n"
            end
            tooltiptodisplay = tooltiptodisplay .. v
            displaylooper = displaylooper + 1
        end
        icon:SetTooltip( tooltiptodisplay )

        icon.DoClick = function(self)
            surface.PlaySound("ui/buttonclickrelease.wav")
            if not CAMI.PlayerHasAccess(LocalPlayer(), "Item Spawn Menu - Spawning", nil) then 
                return
            end
            
            net.Start("ItemSpawn_Request")
            net.WriteString(uniqueID)
            net.SendToServer()
        end

        function icon:OpenMenu()
            local menu = DermaMenu()

            local copyOption = menu:AddOption("Скопировать ID предмета", function()
                SetClipboardText(item.uniqueID)
            end)
            copyOption:SetIcon("icon16/page_copy.png")

            local giveOption = menu:AddOption("Выдать себе", function()
                net.Start("ItemGive_Request")
                net.WriteString(item.uniqueID)
                net.SendToServer()
            end)
            
            giveOption:SetIcon("icon16/user_add.png")
            
            local debugOption = menu:AddOption("Дэбаггинг", function()
		print("-- Start of Item Debug Block --")
                PrintTable(item)
		print("-- End of Item Debug Block --")
            end)
            
            debugOption:SetIcon("icon16/application_xp_terminal.png")

            local teleportOption = menu:AddOption("Телепортироватся к", function()
                net.Start("ItemTeleport_Request")
                net.WriteString(item.uniqueID)
                net.SendToServer()
            end)
            
            teleportOption:SetIcon("icon16/map_go.png")

            local refreshOption = menu:AddOption("Перезагрузить иконку", function()
                if IsValid(icon) then
                    icon:RebuildSpawnIcon()
                end
            end)
            refreshOption:SetIcon("icon16/arrow_refresh.png")
            
            local cleanOption = menu:AddOption("Удалить все!", function()
                OpenItemCleanPopup(item)
            end)
            cleanOption:SetIcon("icon16/cancel.png")
            
            menu:Open()
        end
        function icon:PaintOver(iwd,ihg)
            iwd = iwd + 0
            ihg = ihg + 0
            local color2drawwith = ix.config.Get("color",Color(255,255,255,255))
            draw.NoTexture()
            color2drawwith.a = 92
            surface.SetDrawColor( color2drawwith )
            for I=1,item.width do
                if I == 1 then continue end
                surface.DrawRect( iwd/item.width * (I - 1), ihg/32, 1, ihg - ihg/16 )
            end
            for I=1,item.height do
                if I == 1 then continue end
                surface.DrawRect( iwd/32, ihg/item.height * (I - 1), iwd - iwd/16, 1 )
            end
            color2drawwith.a = 128
            surface.SetDrawColor( color2drawwith )
            surface.DrawRect( iwd/32, ihg - ihg/32 - 16, iwd - iwd/16, 16 )
            color2drawwith.a = 255
            surface.SetMaterial(matOutline)
            surface.SetDrawColor( color2drawwith )
            surface.DrawTexturedRect( 0, 0, iwd, ihg )
            draw.DrawText( name or "No Name Provided", "HudHintTextSmall", iwd/2 - 2, ihg - ihg/32 - 13 + 2, Color(0,0,0,255), TEXT_ALIGN_CENTER )
            draw.DrawText( name or "No Name Provided", "HudHintTextSmall", iwd/2, ihg - ihg/32 - 13, Color(255,255,255,255), TEXT_ALIGN_CENTER )
            draw.DrawText( item.width .. "x" .. item.height, "HudHintTextSmall", 2 + 6 * item.width, 8, Color(255,255,255,255), TEXT_ALIGN_LEFT )
        end
        
        icon:InvalidateLayout(true)

        if IsValid(panel) then
            panel:Add(icon)
        end

        return icon
    end)
end