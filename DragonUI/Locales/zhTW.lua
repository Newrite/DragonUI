--[[
 DragonUI - Traditional Chinese Locale (zhTW)
 Community translation — Edit this file to contribute!

 Guidelines:
 - Use `true` for strings you haven't translated yet (falls back to English)
 - Keep format specifiers like %s, %d, %.1f intact
 - Keep slash commands untranslated (/dragonui, /dui, /rl)
 - Keep "DragonUI" as addon name untranslated
 - Keep color codes |cff...|r outside of L[] strings
]]

local L = LibStub("AceLocale-3.0"):NewLocale("DragonUI", "zhTW")
if not L then return end

-- Example:
-- L["Cannot toggle editor mode during combat!"] = "戰鬥中無法切換編輯模式！"

-- UnitFrameLayers compatibility popup
L["TooltipWidget"] = true
L["DragonUI - UnitFrameLayers Detected"] = true
L["DragonUI already includes Unit Frame Layers functionality (heal prediction, absorb shields, and animated health loss)."] = true
L["Choose how to resolve this overlap:"] = true
L["Use DragonUI: disable external UnitFrameLayers and enable DragonUI layers."] = true
L["Disable Both: disable external UnitFrameLayers and keep DragonUI layers disabled."] = true
L["Use DragonUI"] = true
L["Disable Both"] = true
L["DragonUI - D3D9Ex Warning"] = "DragonUI - D3D9Ex 警告"
L["DragonUI detected that your client is using D3D9Ex."] = "DragonUI 偵測到你的客戶端正在使用 D3D9Ex。"
L["DragonUI's action bar system is not compatible with D3D9Ex."] = "DragonUI 的動作條系統與 D3D9Ex 不相容。"
L["Some DragonUI action bar textures will be missing while this mode is active."] = "啟用此模式時，部分 DragonUI 動作條材質會缺失。"
L["If you want to disable this mode, open WTF\\Config.wtf."] = "如果你想停用這個模式，請打開 WTF\\Config.wtf。"
L["Delete this line:"] = "刪除這一行："
L["Or replace it with:"] = "或改成這一行："
L["Hide Gryphons"] = "隱藏獅鷲"
L["Understood"] = "知道了"
L["Buttons"] = "按鈕"
L["Main Bars"] = "主動作條"
L["Stance Button %d"] = true
L["Pet Action Button %d"] = true
L["Multicast Button %d"] = true
L["Totem Call Button"] = true
L["Totem Recall Button"] = true

L["Copy Text"] = "複製文字"

-- Minimap tooltip strings
L["Minimap Buttons"] = "小地圖按鈕"
L["Minimap Buttons Collector"] = "小地圖按鈕"
L["Left-click to show or hide minimap addon buttons."] = "左鍵開啟小地圖插件按鈕。"
L["Right-click to open DragonUI settings."] = "右鍵開啟 DragonUI 設定。"
L["Drag to move"] = "拖曳以移動"
L["Animated minimap border effects for DragonUI."] = "DragonUI 的小地圖動畫邊框效果。"

-- 編輯模式標籤
L["TargetCastbar"] = "目標施法條"
L["FocusCastbar"] = "焦點施法條"
L["Right-click to reset"] = "右鍵重設"
L["Status Tooltip:"] = "狀態提示："
L["Top"] = "上"
L["Bottom"] = "下"
L["Left"] = "左"
L["Right"] = "右"
L["Error Messages"] = "錯誤訊息"
L["ErrorMessages"] = "錯誤訊息"

-- Bag Sort (Sell Scrap)
L["Sell Scrap"] = "出售垃圾"
L["Click to sell all gray (poor) items to vendor."] = "點擊將所有灰色（粗糙）物品出售給商人。"
L["A merchant window must be open."] = "必須先開啟商人視窗。"
L["Open a merchant window first to sell scrap items."] = "請先開啟商人視窗再出售垃圾物品。"
L["Sold %d scrap item(s) for %s."] = "出售了%d件垃圾物品，獲得%s。"
L["No scrap items to sell."] = "沒有可出售的垃圾物品。"

-- BNet Toast Module
L["BNet Toast"] = "BNet 提醒"
L["Friend online/offline notifications with Battle.net toasts and chat messages"] = "好友上線/離線的戰網提醒和聊天通知"
L["Position & Scale"] = "位置與縮放"
L["Scale of the BNet toast frame."] = "戰網提示框架的縮放比例。"
L["Horizontal position of the BNet toast from the screen center. Negative values move left, positive values move right."] = "戰網提示距螢幕中心的水平位置。負值向左移動，正值向右移動。"
L["Vertical offset of the BNet toast frame. Negative values move down, positive values move up."] = "戰網提示框架的垂直偏移。負值向下移動，正值向上移動。"

-- NamePlates
L["Nameplates"] = "名牌"
L["Apply DragonUI nameplate styling."] = "將 DragonUI 樣式套用至名牌。"

