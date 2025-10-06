-- MirandaTweenPlus - Edição Completa (otimizada para mobile)
-- Integração: removido FPS Devourer, adicionado Desync Body (Anti-Hit), Source (Inf Jump / JumpBoost) e FLY TO BASE
-- Discord principal atualizado: https://discord.gg/jRBhKqVGZj
-- Data da modificação: 2025-09-30
-- Otimizações mobile: cache de descendants, pooling de sons, intervalos ajustados, debounce otimizado

----------------------------------------------------------------
-- PERSISTÊNCIA (somente BEST / SECRET / BASE)
----------------------------------------------------------------
local CONFIG_DIR = 'MirandaTweenPlus'
local CONFIG_FILE = CONFIG_DIR .. '/config.json'
local defaultConfig = { espBest = false, espSecret = false, espBase = false, autoLaser = false, xRay = false }
local currentConfig = {}
local HttpService = game:GetService('HttpService')
local function safeDecode(str)
    local ok, res = pcall(function()
        return HttpService:JSONDecode(str)
    end)
    return ok and res or nil
end
local function safeEncode(tbl)
    local ok, res = pcall(function()
        return HttpService:JSONEncode(tbl)
    end)
    return ok and res or '{}'
end
local function ensureDir()
    if isfolder and not isfolder(CONFIG_DIR) then
        pcall(function()
            makefolder(CONFIG_DIR)
        end)
    end
end
local function loadConfig()
    for k, v in pairs(defaultConfig) do
        currentConfig[k] = v
    end
    if not (isfile and readfile and isfile(CONFIG_FILE)) then
        return
    end
    local ok, data = pcall(function()
        return readfile(CONFIG_FILE)
    end)
    if ok and data and #data > 0 then
        local decoded = safeDecode(data)
        if decoded then
            for k, v in pairs(defaultConfig) do
                if decoded[k] ~= nil then
                    currentConfig[k] = decoded[k]
                end
            end
        end
    end
end
local saveDebounce = false
local function saveConfig()
    if not writefile then
        return
    end
    if saveDebounce then
        return
    end
    saveDebounce = true
    task.delay(0.35, function()
        saveDebounce = false
    end)
    ensureDir()
    local json = safeEncode(currentConfig)
    pcall(function()
        writefile(CONFIG_FILE, json)
    end)
end

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')
local Workspace = game:GetService('Workspace')
local RunService = game:GetService('RunService')
local StarterGui = game:GetService('StarterGui')
local TweenService = game:GetService('TweenService')
local SoundService = game:GetService('SoundService')
local player = Players.LocalPlayer
local playerGui = player:WaitForChild('PlayerGui')

----------------------------------------------------------------
-- LIMPA GUI ANTIGA
----------------------------------------------------------------
do
    local old = playerGui:FindFirstChild('MirandaTweenPlus_FULL')
    if old then
        pcall(function()
            old:Destroy()
        end)
    end
    local old3d = playerGui:FindFirstChild('Miranda3DFloor')
    if old3d then
        pcall(function()
            old3d:Destroy()
        end)
    end
end

----------------------------------------------------------------
-- UTILITÁRIOS
----------------------------------------------------------------
local function getHumanoid()
    local c = player.Character
    return c and c:FindFirstChildOfClass('Humanoid')
end
local function getHRP()
    local c = player.Character
    return c and c:FindFirstChild('HumanoidRootPart')
end
local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore(
            'SendNotification',
            { Title = title or 'Info', Text = text or '', Duration = dur or 3 }
        )
    end)
end
local function showNotification(title, text, dur)
    notify(title, text, dur)
end

-- safe GetAttribute helper
local function safeGetAttribute(obj, name)
    if not obj then
        return nil
    end
    if obj.GetAttribute then
        local ok, res = pcall(function()
            return obj:GetAttribute(name)
        end)
        if ok then
            return res
        end
    end
    return nil
end

----------------------------------------------------------------
-- ESTADOS ESP
----------------------------------------------------------------
local espConfig = {
    enabledBest = false,
    enabledSecret = false,
    enabledBase = false,
    enabledPlayer = false,
}
local statusLabel
local espBoxes = {}

----------------------------------------------------------------
-- PARSE MONEY
----------------------------------------------------------------
local function parseMoneyPerSec(text)
    if not text then
        return 0
    end
    local mult = 1
    local numberStr = text:match('[%d%.]+')
    if not numberStr then
        return 0
    end
    if text:find('K') then
        mult = 1_000
    elseif text:find('M') then
        mult = 1_000_000
    elseif text:find('B') then
        mult = 1_000_000_000
    elseif text:find('T') then
        mult = 1_000_000_000_000
    elseif text:find('Q') then
        mult = 1_000_000_000_000_000
    end
    local number = tonumber(numberStr)
    return number and number * mult or 0
end

----------------------------------------------------------------
-- VISUAL CONSTANTES
----------------------------------------------------------------
local ESP_FONT_NAME = Enum.Font.GothamSemibold
local ESP_RED_BRIGHT = Color3.fromRGB(255, 0, 60)
local ESP_GREEN = Color3.fromRGB(0, 240, 60)

-- Intervalos otimizados para mobile
local ESP_UPDATE_INTERVAL = 1.5
local BASE_UPDATE_INTERVAL = 1.5
local GLOW_UPDATE_INTERVAL = 0.25

----------------------------------------------------------------
-- CACHE SYSTEM (otimização mobile)
----------------------------------------------------------------
local plotCache = {}
local CACHE_LIFETIME = 3

local function getCachedDescendants(obj)
    if not obj or not obj.Parent then
        return {}
    end
    local now = tick()
    local cached = plotCache[obj]
    if cached and (now - cached.time) < CACHE_LIFETIME then
        return cached.descendants
    end
    local desc = obj:GetDescendants()
    plotCache[obj] = { descendants = desc, time = now }
    return desc
end

-- Limpa cache periodicamente
task.spawn(function()
    while true do
        task.wait(10)
        local now = tick()
        for obj, data in pairs(plotCache) do
            if
                not obj
                or not obj.Parent
                or (now - data.time) > CACHE_LIFETIME
            then
                plotCache[obj] = nil
            end
        end
    end
end)

----------------------------------------------------------------
-- SOUND POOLING (otimização mobile)
----------------------------------------------------------------
local soundPool = {}
local MAX_SOUNDS = 2

local function playSoundOptimized(soundId, volume)
    pcall(function()
        -- Limpa sons inválidos
        for i = #soundPool, 1, -1 do
            if not soundPool[i] or not soundPool[i].Parent then
                table.remove(soundPool, i)
            end
        end

        -- Limita sons simultâneos
        if #soundPool >= MAX_SOUNDS then
            local oldest = table.remove(soundPool, 1)
            if oldest then
                oldest:Destroy()
            end
        end

        local s = Instance.new('Sound')
        s.SoundId = soundId
        s.Volume = volume or 1
        s.Looped = false
        s.Parent = SoundService

        table.insert(soundPool, s)

        s:Play()
        s.Ended:Connect(function()
            task.wait(0.3)
            pcall(function()
                s:Destroy()
            end)
        end)
    end)
end

----------------------------------------------------------------
-- CLEAR FUNÇÕES
----------------------------------------------------------------
local function clearAllBestSecret()
    local plotsFolder = Workspace:FindFirstChild('Plots')
    if not plotsFolder then
        return
    end
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        for _, inst in ipairs(plot:GetDescendants()) do
            if
                inst:IsA('BillboardGui')
                and (inst.Name == 'Best_ESP' or inst.Name == 'Secret_ESP')
            then
                pcall(function()
                    inst:Destroy()
                end)
            end
        end
    end
end

local function clearPlayerESP()
    for plr, objs in pairs(espBoxes) do
        if objs.box then
            pcall(function()
                objs.box:Destroy()
            end)
        end
        if objs.text then
            pcall(function()
                objs.text:Destroy()
            end)
        end
    end
    espBoxes = {}
end

----------------------------------------------------------------
-- BEST / SECRET ESP (otimizado)
----------------------------------------------------------------
local function updateBestSecret()
    local plotsFolder = Workspace:FindFirstChild('Plots')
    if not plotsFolder then
        clearAllBestSecret()
        return
    end
    if not (espConfig.enabledBest or espConfig.enabledSecret) then
        clearAllBestSecret()
        return
    end

    local myPlotName
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local plotSign = plot:FindFirstChild('PlotSign')
        if
            plotSign
            and plotSign:FindFirstChild('YourBase')
            and plotSign.YourBase.Enabled
        then
            myPlotName = plot.Name
            break
        end
    end

    local bestPetInfo
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot.Name ~= myPlotName then
            -- Usa cache otimizado
            local descendants = getCachedDescendants(plot)
            for _, desc in ipairs(descendants) do
                if
                    desc:IsA('TextLabel')
                    and desc.Name == 'Rarity'
                    and desc.Parent
                    and desc.Parent:FindFirstChild('DisplayName')
                then
                    local parentModel = desc.Parent.Parent
                    local rarity = desc.Text
                    local displayName = desc.Parent.DisplayName.Text

                    if rarity == 'Secret' then
                        if espConfig.enabledSecret then
                            if not parentModel:FindFirstChild('Secret_ESP') then
                                local billboard = Instance.new('BillboardGui')
                                billboard.Name = 'Secret_ESP'
                                billboard.Size = UDim2.new(0, 198, 0, 60)
                                billboard.StudsOffset = Vector3.new(0, 3.3, 0)
                                billboard.AlwaysOnTop = true
                                billboard.Parent = parentModel
                                local label = Instance.new('TextLabel')
                                label.Text = displayName
                                label.Size = UDim2.new(1, 0, 1, 0)
                                label.BackgroundTransparency = 1
                                label.TextScaled = true
                                label.Font = ESP_FONT_NAME
                                label.TextColor3 = ESP_RED_BRIGHT
                                label.TextStrokeColor3 = Color3.new(0, 0, 0)
                                label.TextStrokeTransparency = 0.2
                                label.Parent = billboard
                            end
                        else
                            if parentModel:FindFirstChild('Secret_ESP') then
                                parentModel.Secret_ESP:Destroy()
                            end
                        end
                    end

                    if espConfig.enabledBest then
                        local genLabel =
                            desc.Parent:FindFirstChild('Generation')
                        if genLabel and genLabel:IsA('TextLabel') then
                            local mps = parseMoneyPerSec(genLabel.Text)
                            if not bestPetInfo or mps > bestPetInfo.mps then
                                bestPetInfo = {
                                    petName = displayName,
                                    genText = genLabel.Text,
                                    mps = mps,
                                    model = parentModel,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    if espConfig.enabledBest then
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            for _, inst in ipairs(plot:GetDescendants()) do
                if inst:IsA('BillboardGui') and inst.Name == 'Best_ESP' then
                    pcall(function()
                        inst:Destroy()
                    end)
                end
            end
        end
        if bestPetInfo and bestPetInfo.mps > 0 and bestPetInfo.model then
            local billboard = Instance.new('BillboardGui')
            billboard.Name = 'Best_ESP'
            billboard.Size = UDim2.new(0, 303, 0, 75)
            billboard.StudsOffset = Vector3.new(0, 4.84, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = bestPetInfo.model
            local nameLabel = Instance.new('TextLabel')
            nameLabel.Size = UDim2.new(1, 0, 0, 35)
            nameLabel.Position = UDim2.new(0, 0, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = bestPetInfo.petName
            nameLabel.TextColor3 = ESP_RED_BRIGHT
            nameLabel.Font = ESP_FONT_NAME
            nameLabel.TextSize = 25
            nameLabel.TextStrokeTransparency = 0.07
            nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            nameLabel.Parent = billboard
            local moneyLabel = Instance.new('TextLabel')
            moneyLabel.Size = UDim2.new(1, 0, 0, 22)
            moneyLabel.Position = UDim2.new(0, 0, 0, 35)
            moneyLabel.BackgroundTransparency = 1
            moneyLabel.Text = bestPetInfo.genText
            moneyLabel.TextColor3 = ESP_GREEN
            moneyLabel.Font = ESP_FONT_NAME
            moneyLabel.TextSize = 22
            moneyLabel.TextStrokeTransparency = 0.17
            moneyLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            moneyLabel.Parent = billboard
        end
    end
end

----------------------------------------------------------------
-- PLAYER ESP
----------------------------------------------------------------
local function updatePlayerESP()
    if espConfig.enabledPlayer then
        for _, plr in ipairs(Players:GetPlayers()) do
            if
                plr ~= player
                and plr.Character
                and plr.Character:FindFirstChild('HumanoidRootPart')
            then
                local hrp = plr.Character.HumanoidRootPart
                if not espBoxes[plr] then
                    espBoxes[plr] = {}
                    local box = Instance.new('BoxHandleAdornment')
                    box.Size = Vector3.new(4, 6, 4)
                    box.Adornee = hrp
                    box.AlwaysOnTop = true
                    box.ZIndex = 10
                    box.Transparency = 0.5
                    box.Color3 = Color3.fromRGB(250, 0, 60)
                    box.Parent = hrp
                    espBoxes[plr].box = box

                    local billboard = Instance.new('BillboardGui')
                    billboard.Adornee = hrp
                    billboard.Size = UDim2.new(0, 200, 0, 30)
                    billboard.StudsOffset = Vector3.new(0, 4, 0)
                    billboard.AlwaysOnTop = true
                    local label = Instance.new('TextLabel', billboard)
                    label.Size = UDim2.new(1, 0, 1, 0)
                    label.BackgroundTransparency = 1
                    label.TextColor3 = Color3.fromRGB(220, 0, 60)
                    label.TextStrokeTransparency = 0
                    label.Text = plr.Name
                    label.Font = Enum.Font.GothamBold
                    label.TextSize = 18
                    espBoxes[plr].text = billboard
                    billboard.Parent = hrp
                else
                    if espBoxes[plr].box then
                        espBoxes[plr].box.Adornee = hrp
                    end
                    if espBoxes[plr].text then
                        espBoxes[plr].text.Adornee = hrp
                    end
                end
            else
                if espBoxes[plr] then
                    if espBoxes[plr].box then
                        pcall(function()
                            espBoxes[plr].box:Destroy()
                        end)
                    end
                    if espBoxes[plr].text then
                        pcall(function()
                            espBoxes[plr].text:Destroy()
                        end)
                    end
                    espBoxes[plr] = nil
                end
            end
        end
    else
        clearPlayerESP()
    end
end

Players.PlayerRemoving:Connect(function(plr)
    local objs = espBoxes[plr]
    if objs then
        if objs.box then
            pcall(function()
                objs.box:Destroy()
            end)
        end
        if objs.text then
            pcall(function()
                objs.text:Destroy()
            end)
        end
        espBoxes[plr] = nil
    end
end)

----------------------------------------------------------------
-- LOOP PRINCIPAL DE ESP
----------------------------------------------------------------
task.spawn(function()
    while true do
        task.wait(ESP_UPDATE_INTERVAL)
        if espConfig.enabledBest or espConfig.enabledSecret then
            pcall(updateBestSecret)
        end
        if espConfig.enabledPlayer then
            pcall(updatePlayerESP)
        end
    end
end)

----------------------------------------------------------------
-- CARREGA CONFIG
----------------------------------------------------------------
loadConfig()
espConfig.enabledBest = currentConfig.espBest
espConfig.enabledSecret = currentConfig.espSecret
espConfig.enabledBase = currentConfig.espBase
espConfig.enabledPlayer = false

-- Initialize autoLaser and xRay from config (will be activated after buttons are created)
local initialAutoLaser = currentConfig.autoLaser
local initialXRay = currentConfig.xRay

----------------------------------------------------------------
-- AIMBOT TEIA
----------------------------------------------------------------
local WEBSLINGER_NAME = 'Web Slinger'
local function getClosestPlayerWithLowerTorso()
    local myChar = player.Character
    local myHRP = myChar and myChar:FindFirstChild('HumanoidRootPart')
    if not myHRP then
        return nil
    end
    local closest, closestDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if
            plr ~= player
            and plr.Character
            and plr.Character:FindFirstChild('LowerTorso')
        then
            local lt = plr.Character.LowerTorso
            local dist = (lt.Position - myHRP.Position).Magnitude
            if dist < closestDist then
                closest, closestDist = plr, dist
            end
        end
    end
    return closest
end
local function fireWebSlingerLowerTorso()
    local bp = player:FindFirstChildOfClass('Backpack')
    if bp and bp:FindFirstChild(WEBSLINGER_NAME) then
        player.Character.Humanoid:EquipTool(bp[WEBSLINGER_NAME])
    end
    if not player.Character:FindFirstChild(WEBSLINGER_NAME) then
        return
    end
    local remoteEvent = ReplicatedStorage:FindFirstChild('Packages')
        and ReplicatedStorage.Packages:FindFirstChild('Net')
        and ReplicatedStorage.Packages.Net:FindFirstChild('RE/UseItem')
    if not remoteEvent then
        return
    end
    local alvo = getClosestPlayerWithLowerTorso()
    if
        alvo
        and alvo.Character
        and alvo.Character:FindFirstChild('LowerTorso')
    then
        local lt = alvo.Character.LowerTorso
        remoteEvent:FireServer(lt.Position, lt)
    end
end

----------------------------------------------------------------
-- PAINEL PRINCIPAL (GUI) + TOGGLES + DRAG
----------------------------------------------------------------
local gui = Instance.new('ScreenGui')
gui.Name = 'MirandaTweenPlus_FULL'
gui.ResetOnSpawn = false
gui.Parent = playerGui

local menu = Instance.new('Frame')
menu.Size = UDim2.new(0, 180, 0, 255)
menu.Position = UDim2.new(0.5, -90, 0.5, -127)
menu.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
menu.BackgroundTransparency = 0.15
menu.BorderSizePixel = 0
menu.Visible = false
menu.Name = 'VIPMenu'
menu.Parent = gui
Instance.new('UICorner', menu).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new('UIStroke', menu)
stroke.Thickness = 3
stroke.Transparency = 0.15

-- Glow otimizado
task.spawn(function()
    while menu.Parent do
        task.wait(GLOW_UPDATE_INTERVAL)
        local t = math.sin(tick() * 1.4)
        stroke.Color = t > 0 and Color3.fromRGB(255, 215 + 20 * t, 30 * t)
            or Color3.fromRGB(
                255 - math.floor(40 * -t),
                0,
                60 - math.floor(40 * -t)
            )
    end
end)

local title = Instance.new('TextLabel', menu)
title.Size = UDim2.new(1, 0, 0, 22)
title.Text = 'MIRANDA HUB'
title.TextColor3 = Color3.fromRGB(255, 0, 60)
title.Font = Enum.Font.Arcade
title.TextSize = 15
title.BackgroundTransparency = 1

local tiktokLabel = Instance.new('TextLabel', menu)
tiktokLabel.Size = UDim2.new(1, -20, 0, 14)
tiktokLabel.Position = UDim2.new(0, 10, 0, 22)
tiktokLabel.BackgroundTransparency = 1
tiktokLabel.Text = 'TIKTOK: @mirandacallruim'
tiktokLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
tiktokLabel.Font = Enum.Font.Arcade
tiktokLabel.TextSize = 12
tiktokLabel.TextXAlignment = Enum.TextXAlignment.Center

statusLabel = Instance.new('TextLabel', menu)
statusLabel.Size = UDim2.new(0.9, 0, 0, 15)
statusLabel.Position = UDim2.new(0.05, 0, 1, -18)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Arcade
statusLabel.TextColor3 = Color3.fromRGB(255, 0, 60)
statusLabel.TextSize = 11
statusLabel.Text = ''
statusLabel.TextTransparency = 1
local function showStatus(msg, color)
    if statusLabel then
        statusLabel.Text = msg
        statusLabel.TextColor3 = color or Color3.fromRGB(255, 0, 60)
        statusLabel.TextTransparency = 0
    end
end

local espBtnY, espBtnH, espBtnW, espBtnGap = 38, 22, 0.455, 0.04

local function makePersistToggle(btn, key, onColor, offColor, label, callback)
    btn.MouseButton1Click:Connect(function()
        currentConfig[key] = not currentConfig[key]
        saveConfig()
        espConfig['enabled' .. key:sub(4):gsub('^%l', string.upper)] =
            currentConfig[key]
        btn.BackgroundColor3 = currentConfig[key] and onColor or offColor
        showStatus(label .. ' ' .. (currentConfig[key] and 'ON' or 'OFF'))
        if callback then
            callback(currentConfig[key])
        end
    end)
end

local function makeRuntimeToggle(
    btn,
    stateKey,
    onColor,
    offColor,
    label,
    callback
)
    btn.MouseButton1Click:Connect(function()
        espConfig[stateKey] = not espConfig[stateKey]
        btn.BackgroundColor3 = espConfig[stateKey] and onColor or offColor
        showStatus(label .. ' ' .. (espConfig[stateKey] and 'ON' or 'OFF'))
        if callback then
            callback(espConfig[stateKey])
        end
    end)
end

local btnEspBest = Instance.new('TextButton', menu)
btnEspBest.Size = UDim2.new(espBtnW, -2, 0, espBtnH)
btnEspBest.Position = UDim2.new(espBtnGap, 0, 0, espBtnY)
btnEspBest.BackgroundColor3 = espConfig.enabledBest
        and Color3.fromRGB(250, 80, 80)
    or Color3.fromRGB(200, 0, 60)
btnEspBest.Text = 'ESP BEST'
btnEspBest.Font = Enum.Font.Arcade
btnEspBest.TextColor3 = Color3.new(1, 1, 1)
btnEspBest.TextSize = 12
btnEspBest.BorderSizePixel = 0
Instance.new('UICorner', btnEspBest).CornerRadius = UDim.new(0, 8)
makePersistToggle(
    btnEspBest,
    'espBest',
    Color3.fromRGB(250, 80, 80),
    Color3.fromRGB(200, 0, 60),
    'ESP BEST',
    function(on)
        espConfig.enabledBest = on
        if on then
            pcall(updateBestSecret)
        else
            clearAllBestSecret()
        end
    end
)

local btnEspSecret = Instance.new('TextButton', menu)
btnEspSecret.Size = UDim2.new(espBtnW, -2, 0, espBtnH)
btnEspSecret.Position = UDim2.new(espBtnGap * 2 + espBtnW, 2, 0, espBtnY)
btnEspSecret.BackgroundColor3 = espConfig.enabledSecret
        and Color3.fromRGB(250, 60, 60)
    or Color3.fromRGB(0, 0, 0)
btnEspSecret.Text = 'ESP SECRET'
btnEspSecret.Font = Enum.Font.Arcade
btnEspSecret.TextColor3 = Color3.new(1, 1, 1)
btnEspSecret.TextSize = 12
btnEspSecret.BorderSizePixel = 0
Instance.new('UICorner', btnEspSecret).CornerRadius = UDim.new(0, 8)
makePersistToggle(
    btnEspSecret,
    'espSecret',
    Color3.fromRGB(250, 60, 60),
    Color3.fromRGB(0, 0, 0),
    'ESP SECRET',
    function(on)
        espConfig.enabledSecret = on
        if on then
            pcall(updateBestSecret)
        else
            clearAllBestSecret()
        end
    end
)

local espBaseY, espBaseH = espBtnY + espBtnH + 6, 30
local btnEspBase = Instance.new('TextButton', menu)
btnEspBase.Size = UDim2.new(0.9, 0, 0, espBaseH)
btnEspBase.Position = UDim2.new(0.05, 0, 0, espBaseY)
btnEspBase.BackgroundColor3 = espConfig.enabledBase
        and Color3.fromRGB(250, 0, 60)
    or Color3.fromRGB(220, 0, 60)
btnEspBase.Text = 'ESP BASE'
btnEspBase.Font = Enum.Font.Arcade
btnEspBase.TextColor3 = Color3.new(1, 1, 1)
btnEspBase.TextSize = 15
btnEspBase.BorderSizePixel = 0
Instance.new('UICorner', btnEspBase).CornerRadius = UDim.new(0, 8)
makePersistToggle(
    btnEspBase,
    'espBase',
    Color3.fromRGB(250, 0, 60),
    Color3.fromRGB(220, 0, 60),
    'ESP BASE',
    function(on)
        espConfig.enabledBase = on
        if on then
            if typeof(startBaseESP) == 'function' then
                pcall(startBaseESP)
            end
        else
            if typeof(stopBaseESP) == 'function' then
                pcall(stopBaseESP)
            end
        end
    end
)

local espPlayerY = espBaseY + espBaseH + 6
local btnEspPlayer = Instance.new('TextButton', menu)
btnEspPlayer.Size = UDim2.new(0.9, 0, 0, 28)
btnEspPlayer.Position = UDim2.new(0.05, 0, 0, espPlayerY)
btnEspPlayer.BackgroundColor3 = espConfig.enabledPlayer
        and Color3.fromRGB(250, 0, 60)
    or Color3.fromRGB(220, 0, 60)
btnEspPlayer.Text = 'ESP PLAYER'
btnEspPlayer.Font = Enum.Font.Arcade
btnEspPlayer.TextColor3 = Color3.new(1, 1, 1)
btnEspPlayer.TextSize = 15
btnEspPlayer.BorderSizePixel = 0
Instance.new('UICorner', btnEspPlayer).CornerRadius = UDim.new(0, 8)
makeRuntimeToggle(
    btnEspPlayer,
    'enabledPlayer',
    Color3.fromRGB(250, 0, 60),
    Color3.fromRGB(220, 0, 60),
    'ESP PLAYER',
    function(on)
        if on then
            pcall(updatePlayerESP)
        else
            clearPlayerESP()
        end
    end
)

-- AUTO LASER e X-RAY state
local autoLaserActive = false
local xRayActive = false
local autoLaserConn
local xRayConn

local autoLaserY = espPlayerY + 28 + 6
local btnAutoLaser = Instance.new('TextButton', menu)
btnAutoLaser.Size = UDim2.new(0.9, 0, 0, 28)
btnAutoLaser.Position = UDim2.new(0.05, 0, 0, autoLaserY)
btnAutoLaser.BackgroundColor3 = currentConfig.autoLaser and Color3.fromRGB(250, 0, 60) or Color3.fromRGB(220, 0, 60)
btnAutoLaser.Text = 'AUTO LASER'
btnAutoLaser.Font = Enum.Font.Arcade
btnAutoLaser.TextColor3 = Color3.new(1, 1, 1)
btnAutoLaser.TextSize = 15
btnAutoLaser.BorderSizePixel = 0
Instance.new('UICorner', btnAutoLaser).CornerRadius = UDim.new(0, 8)
makePersistToggle(
    btnAutoLaser,
    'autoLaser',
    Color3.fromRGB(250, 0, 60),
    Color3.fromRGB(220, 0, 60),
    'AUTO LASER',
    function(on)
        autoLaserActive = on
        if on then
            if autoLaserConn then
                autoLaserConn:Disconnect()
            end
            autoLaserConn = RunService.Heartbeat:Connect(function()
                local char = player.Character
                if not char then return end
                local hrp = char:FindFirstChild('HumanoidRootPart')
                if not hrp then return end
                
                for _, obj in ipairs(Workspace:GetDescendants()) do
                    if obj:IsA('ProximityPrompt') and obj.Enabled then
                        local action = (obj.ActionText or ''):lower()
                        if action:find('laser') or action:find('collect') then
                            local parent = obj.Parent
                            if parent and parent:IsA('BasePart') then
                                local dist = (parent.Position - hrp.Position).Magnitude
                                if dist <= obj.MaxActivationDistance then
                                    pcall(function()
                                        fireproximityprompt(obj)
                                    end)
                                end
                            end
                        end
                    end
                end
            end)
        else
            if autoLaserConn then
                autoLaserConn:Disconnect()
                autoLaserConn = nil
            end
        end
    end
)

local xRayY = autoLaserY + 28 + 6
local btnXRay = Instance.new('TextButton', menu)
btnXRay.Size = UDim2.new(0.9, 0, 0, 28)
btnXRay.Position = UDim2.new(0.05, 0, 0, xRayY)
btnXRay.BackgroundColor3 = currentConfig.xRay and Color3.fromRGB(250, 0, 60) or Color3.fromRGB(220, 0, 60)
btnXRay.Text = 'X-RAY'
btnXRay.Font = Enum.Font.Arcade
btnXRay.TextColor3 = Color3.new(1, 1, 1)
btnXRay.TextSize = 15
btnXRay.BorderSizePixel = 0
Instance.new('UICorner', btnXRay).CornerRadius = UDim.new(0, 8)
makePersistToggle(
    btnXRay,
    'xRay',
    Color3.fromRGB(250, 0, 60),
    Color3.fromRGB(220, 0, 60),
    'X-RAY',
    function(on)
        xRayActive = on
        if on then
            if xRayConn then
                xRayConn:Disconnect()
            end
            xRayConn = RunService.Heartbeat:Connect(function()
                for _, obj in ipairs(Workspace:GetDescendants()) do
                    if obj:IsA('BasePart') then
                        pcall(function()
                            obj.LocalTransparencyModifier = 0.7
                        end)
                    end
                end
            end)
        else
            if xRayConn then
                xRayConn:Disconnect()
                xRayConn = nil
            end
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA('BasePart') then
                    pcall(function()
                        obj.LocalTransparencyModifier = 0
                    end)
                end
            end
        end
    end
)

local aimbotY = xRayY + 28 + 6
local btnAimbotMain = Instance.new('TextButton', menu)
btnAimbotMain.Size = UDim2.new(0.9, 0, 0, 28)
btnAimbotMain.Position = UDim2.new(0.05, 0, 0, aimbotY)
btnAimbotMain.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
btnAimbotMain.Text = 'AIMBOT TEIA'
btnAimbotMain.Font = Enum.Font.Arcade
btnAimbotMain.TextColor3 = Color3.new(0, 0, 0)
btnAimbotMain.TextSize = 15
btnAimbotMain.BorderSizePixel = 0
Instance.new('UICorner', btnAimbotMain).CornerRadius = UDim.new(0, 8)
btnAimbotMain.MouseButton1Click:Connect(function()
    fireWebSlingerLowerTorso()
    showStatus('Aimbot Teia Usado!', Color3.fromRGB(60, 255, 60))
    btnAimbotMain.Text = 'Aimbot Teia Usado!'
    btnAimbotMain.BackgroundColor3 = Color3.fromRGB(60, 255, 60)
    task.wait(0.6)
    btnAimbotMain.Text = 'AIMBOT TEIA'
    btnAimbotMain.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
end)

local btnDiscordMain = Instance.new('TextButton', menu)
btnDiscordMain.Size = UDim2.new(0.9, 0, 0, 28)
btnDiscordMain.Position = UDim2.new(0.05, 0, 0, aimbotY + 28 + 8)
btnDiscordMain.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
btnDiscordMain.Text = 'DISCORD'
btnDiscordMain.Font = Enum.Font.Arcade
btnDiscordMain.TextColor3 = Color3.new(1, 1, 1)
btnDiscordMain.TextSize = 14
btnDiscordMain.BorderSizePixel = 0
Instance.new('UICorner', btnDiscordMain).CornerRadius = UDim.new(0, 8)
btnDiscordMain.MouseButton1Click:Connect(function()
    local link = 'https://discord.gg/jRBhKqVGZj'
    local copied = false
    if typeof(setclipboard) == 'function' then
        pcall(function()
            setclipboard(link)
            copied = true
        end)
    end
    if copied then
        showStatus('discord copiado', Color3.fromRGB(100, 255, 120))
        notify('Discord', 'discord copiado.', 4)
    else
        showStatus('Abra: ' .. link, Color3.fromRGB(255, 255, 0))
        notify('Discord', link, 5)
    end
end)

do
    local bottom = aimbotY + 28 + 8 + 28 + 18
    menu.Size = UDim2.new(0, 180, 0, bottom)
end

-- Initialize AUTO LASER and X-RAY from saved config
if initialAutoLaser then
    task.defer(function()
        autoLaserActive = true
        if autoLaserConn then
            autoLaserConn:Disconnect()
        end
        autoLaserConn = RunService.Heartbeat:Connect(function()
            local char = player.Character
            if not char then return end
            local hrp = char:FindFirstChild('HumanoidRootPart')
            if not hrp then return end
            
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA('ProximityPrompt') and obj.Enabled then
                    local action = (obj.ActionText or ''):lower()
                    if action:find('laser') or action:find('collect') then
                        local parent = obj.Parent
                        if parent and parent:IsA('BasePart') then
                            local dist = (parent.Position - hrp.Position).Magnitude
                            if dist <= obj.MaxActivationDistance then
                                pcall(function()
                                    fireproximityprompt(obj)
                                end)
                            end
                        end
                    end
                end
            end
        end)
    end)
end

if initialXRay then
    task.defer(function()
        xRayActive = true
        if xRayConn then
            xRayConn:Disconnect()
        end
        xRayConn = RunService.Heartbeat:Connect(function()
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA('BasePart') then
                    pcall(function()
                        obj.LocalTransparencyModifier = 0.7
                    end)
                end
            end
        end)
    end)
end

----------------------------------------------------------------
-- PAINEL SECUNDÁRIO: Desync / Inf Jump / Fly to Base
----------------------------------------------------------------
local panel = Instance.new('Frame', gui)
panel.Name = 'DevourerPanel'
panel.BackgroundColor3 = Color3.fromRGB(23, 23, 31)
panel.BackgroundTransparency = 0.13
panel.BorderSizePixel = 0
panel.Size = UDim2.new(0, 160, 0, 240)
panel.Position = UDim2.new(0.5, 100, 0.5, -120)
panel.Visible = true
Instance.new('UICorner', panel).CornerRadius = UDim.new(0, 12)
local title2 = Instance.new('TextLabel', panel)
title2.Size = UDim2.new(1, 0, 0, 20)
title2.Text = 'TOOLS'
title2.TextColor3 = Color3.new(1, 1, 1)
title2.Font = Enum.Font.Arcade
title2.TextSize = 14
title2.BackgroundTransparency = 1

----------------------------------------------------------------
-- DESYNC / ANTI-HIT (simplificado)
----------------------------------------------------------------
local antiHitActive = false
local clonerActive = false
local desyncActive = false
local cloneListenerConn
local antiHitRunning = false

local function safeDisconnectConn(conn)
    if conn and typeof(conn) == 'RBXScriptConnection' then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

local function trySetFlag()
    pcall(function()
        if setfflag then
            setfflag('WorldStepMax', '-99999999999999')
        end
    end)
end
local function resetFlag()
    pcall(function()
        if setfflag then
            setfflag('WorldStepMax', '1')
        end
    end)
end

local function activateDesync()
    if desyncActive then
        return
    end
    desyncActive = true
    trySetFlag()
end
local function deactivateDesync()
    if not desyncActive then
        return
    end
    desyncActive = false
    resetFlag()
end

local function activateClonerDesync(callback)
    if clonerActive then
        if callback then
            callback()
        end
        return
    end
    clonerActive = true

    local Backpack = player:FindFirstChildOfClass('Backpack')
    local function equipQuantumCloner()
        if not Backpack then
            return
        end
        local tool = Backpack:FindFirstChild('Quantum Cloner')
        if tool then
            local humanoid = player.Character
                and player.Character:FindFirstChildOfClass('Humanoid')
            if humanoid then
                humanoid:EquipTool(tool)
            end
        end
    end
    equipQuantumCloner()

    local REUseItem =
        ReplicatedStorage.Packages.Net:FindFirstChild('RE/UseItem')
    if REUseItem then
        REUseItem:FireServer()
    end
    local REQuantumClonerOnTeleport =
        ReplicatedStorage.Packages.Net:FindFirstChild(
            'RE/QuantumCloner/OnTeleport'
        )
    if REQuantumClonerOnTeleport then
        REQuantumClonerOnTeleport:FireServer()
    end

    -- Tela de carregamento simples
    local overlayGui = Instance.new('ScreenGui')
    overlayGui.Name = 'MirandaDesyncOverlay'
    overlayGui.ResetOnSpawn = false
    overlayGui.Parent = playerGui

    local blackFrame = Instance.new('Frame', overlayGui)
    blackFrame.Size = UDim2.new(2, 0, 2, 0)
    blackFrame.Position = UDim2.new(-0.5, 0, -0.5, 0)
    blackFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    blackFrame.BackgroundTransparency = 0
    blackFrame.ZIndex = 9999

    local label = Instance.new('TextLabel', blackFrame)
    label.Size = UDim2.new(1, 0, 0, 100)
    label.Position = UDim2.new(0, 0, 0.45, -50)
    label.BackgroundTransparency = 1
    label.Text = 'Miranda Desync You'
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Font = Enum.Font.Arcade
    label.TextSize = 32
    label.ZIndex = 10000

    local cloneName = tostring(player.UserId) .. '_Clone'
    cloneListenerConn = Workspace.ChildAdded:Connect(function(obj)
        if obj.Name == cloneName and obj:IsA('Model') then
            if cloneListenerConn then
                cloneListenerConn:Disconnect()
            end
            cloneListenerConn = nil

            task.delay(1.6, function()
                pcall(function()
                    if overlayGui then
                        overlayGui:Destroy()
                    end
                end)

                playSoundOptimized('rbxassetid://144686873', 1)
                notify('Desync', 'Desync Sucessfull', 4)
                showStatus('Desync Sucessfull', Color3.fromRGB(100, 255, 120))

                if callback then
                    pcall(callback)
                end
            end)
        end
    end)
end

local function deactivateClonerDesync()
    if not clonerActive then
        local existingClone =
            Workspace:FindFirstChild(tostring(player.UserId) .. '_Clone')
        if existingClone then
            pcall(function()
                existingClone:Destroy()
            end)
        end
        clonerActive = false
        return
    end

    clonerActive = false

    local clone = Workspace:FindFirstChild(tostring(player.UserId) .. '_Clone')
    if clone then
        pcall(function()
            clone:Destroy()
        end)
    end

    if cloneListenerConn then
        cloneListenerConn:Disconnect()
        cloneListenerConn = nil
    end
end

local function deactivateAntiHit()
    if antiHitRunning then
        if cloneListenerConn then
            cloneListenerConn:Disconnect()
            cloneListenerConn = nil
        end
        antiHitRunning = false
    end

    deactivateClonerDesync()
    deactivateDesync()
    antiHitActive = false

    local possibleClone =
        Workspace:FindFirstChild(tostring(player.UserId) .. '_Clone')
    if possibleClone then
        pcall(function()
            possibleClone:Destroy()
        end)
    end

    showNotification('Anti-Hit desativado.', Color3.fromRGB(255, 100, 100), 2)
    if typeof(updateDesyncButton) == 'function' then
        pcall(updateDesyncButton)
    end
end

local function executeAntiHit()
    if antiHitRunning then
        return
    end
    antiHitRunning = true

    if typeof(updateDesyncButton) == 'function' then
        pcall(updateDesyncButton)
    end

    activateDesync()
    task.wait(0.1)
    activateClonerDesync(function()
        deactivateDesync()
        antiHitRunning = false
        antiHitActive = true
        showNotification(
            'Anti-Hit ativado com sucesso!',
            Color3.fromRGB(0, 255, 0),
            3
        )
        if typeof(updateDesyncButton) == 'function' then
            pcall(updateDesyncButton)
        end
    end)
end

player.CharacterAdded:Connect(function()
    task.delay(0.3, function()
        local clone =
            Workspace:FindFirstChild(tostring(player.UserId) .. '_Clone')
        if clone then
            pcall(function()
                clone:Destroy()
            end)
        end
    end)
end)

----------------------------------------------------------------
-- SOURCE (Inf Jump / Jump Boost / Gravity spoof)
----------------------------------------------------------------
local NORMAL_GRAV = 196.2
local REDUCED_GRAV = 40
local NORMAL_JUMP = 50
local BOOST_JUMP = 35
local BOOST_SPEED = 22

local spoofedGravity = NORMAL_GRAV
pcall(function()
    local mt = getrawmetatable(Workspace)
    if mt then
        setreadonly(mt, false)
        local oldIndex = mt.__index
        mt.__index = function(self, k)
            if k == 'Gravity' then
                return spoofedGravity
            end
            return oldIndex(self, k)
        end
        setreadonly(mt, true)
    end
end)

local gravityLow = false
local sourceActive = false

local function setJumpPower(jump)
    local h = player.Character
        and player.Character:FindFirstChildOfClass('Humanoid')
    if h then
        h.JumpPower = jump
        h.UseJumpPower = true
    end
end

local speedBoostConn
local function enableSpeedBoostAssembly(state)
    if speedBoostConn then
        speedBoostConn:Disconnect()
        speedBoostConn = nil
    end
    if state then
        speedBoostConn = RunService.Heartbeat:Connect(function()
            local char = player.Character
            if char then
                local root = char:FindFirstChild('HumanoidRootPart')
                local h = char:FindFirstChildOfClass('Humanoid')
                if root and h and h.MoveDirection.Magnitude > 0 then
                    root.Velocity = Vector3.new(
                        h.MoveDirection.X * BOOST_SPEED,
                        root.Velocity.Y,
                        h.MoveDirection.Z * BOOST_SPEED
                    )
                end
            end
        end)
    end
end

local infiniteJumpConn
local function enableInfiniteJump(state)
    if infiniteJumpConn then
        infiniteJumpConn:Disconnect()
        infiniteJumpConn = nil
    end
    if state then
        infiniteJumpConn = UserInputService.JumpRequest:Connect(function()
            local h = player.Character
                and player.Character:FindFirstChildOfClass('Humanoid')
            if
                h
                and gravityLow
                and h:GetState() ~= Enum.HumanoidStateType.Seated
            then
                local root = player.Character:FindFirstChild('HumanoidRootPart')
                if root then
                    root.Velocity = Vector3.new(
                        root.Velocity.X,
                        h.JumpPower,
                        root.Velocity.Z
                    )
                end
            end
        end)
    end
end

local function antiRagdoll()
    local char = player.Character
    if char then
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA('BodyVelocity') or v:IsA('BodyAngularVelocity') then
                v:Destroy()
            end
        end
    end
end

local function toggleForceField()
    local char = player.Character
    if char then
        if gravityLow then
            if not char:FindFirstChildOfClass('ForceField') then
                local ff = Instance.new('ForceField', char)
                ff.Visible = false
            end
        else
            for _, ff in ipairs(char:GetChildren()) do
                if ff:IsA('ForceField') then
                    ff:Destroy()
                end
            end
        end
    end
end

local btnDesync = Instance.new('TextButton', panel)
btnDesync.Size = UDim2.new(0.88, 0, 0, 40)
btnDesync.Position = UDim2.new(0.06, 0, 0, 24)
btnDesync.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
btnDesync.Text = 'DESYNC BODY'
btnDesync.Font = Enum.Font.Arcade
btnDesync.TextColor3 = Color3.new(1, 1, 1)
btnDesync.TextSize = 14
btnDesync.BorderSizePixel = 0
Instance.new('UICorner', btnDesync).CornerRadius = UDim.new(0, 8)

local btnInfJump = Instance.new('TextButton', panel)
btnInfJump.Size = UDim2.new(0.88, 0, 0, 30)
btnInfJump.Position = UDim2.new(0.06, 0, 0, 24 + 40 + 8)
btnInfJump.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
btnInfJump.Text = 'INF JUMP'
btnInfJump.Font = Enum.Font.Arcade
btnInfJump.TextColor3 = Color3.new(1, 1, 1)
btnInfJump.TextSize = 14
btnInfJump.BorderSizePixel = 0
Instance.new('UICorner', btnInfJump).CornerRadius = UDim.new(0, 8)

local function updateDesyncButton()
    if antiHitRunning then
        btnDesync.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
    elseif antiHitActive then
        btnDesync.BackgroundColor3 = Color3.fromRGB(60, 200, 60)
    else
        btnDesync.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
    end
    btnDesync.Text = 'DESYNC BODY'
end

btnDesync.MouseButton1Click:Connect(function()
    if antiHitRunning then
        showStatus('Anti-Hit em execução...', Color3.fromRGB(255, 200, 50))
        return
    end
    if antiHitActive then
        deactivateAntiHit()
        updateDesyncButton()
        showStatus('DESYNC BODY OFF')
    else
        executeAntiHit()
        updateDesyncButton()
        showStatus('DESYNC BODY ON', Color3.fromRGB(60, 200, 60))
    end
end)

local greenOn = Color3.fromRGB(60, 200, 60)
local redOff = Color3.fromRGB(80, 0, 0)
local function updateInfJumpButton()
    btnInfJump.BackgroundColor3 = sourceActive and greenOn or redOff
    btnInfJump.Text = 'INF JUMP'
end

local function switchGravityJump()
    gravityLow = not gravityLow
    sourceActive = gravityLow
    Workspace.Gravity = gravityLow and REDUCED_GRAV or NORMAL_GRAV
    setJumpPower(gravityLow and BOOST_JUMP or NORMAL_JUMP)
    enableSpeedBoostAssembly(gravityLow)
    enableInfiniteJump(gravityLow)
    antiRagdoll()
    toggleForceField()
    spoofedGravity = NORMAL_GRAV
    updateInfJumpButton()
    showStatus(
        'Inf Jump ' .. (sourceActive and 'ON' or 'OFF'),
        sourceActive and greenOn or redOff
    )
end

btnInfJump.MouseButton1Click:Connect(function()
    switchGravityJump()
end)

----------------------------------------------------------------
-- FLY TO BASE
----------------------------------------------------------------
local btnFlyToBase
local flyActive = false
local flyConn
local flyAtt, flyLV
local flyCharRemovingConn
local destTouchedConn
local destPartRef
local flyRestoreOldGravity, flyRestoreOldJumpPower

local FLY_SUCCESS_SOUND_ID = 'rbxassetid://144686873'
local FLY_SUCCESS_VOLUME = 1

local FLY_GRAV = 20
local FLY_JUMP = 7
local FLY_STOPDIST = 7
local FLY_XZ_SPEED = 22
local FLY_Y_BASE = -1.0
local FLY_Y_MAX = -2.2
local FLY_TIME_STEP = 1.5

local function setFlyButtonActive(state)
    if btnFlyToBase then
        btnFlyToBase.BackgroundColor3 = state and greenOn or redOff
    end
end

local function playFlySuccessSound()
    playSoundOptimized(FLY_SUCCESS_SOUND_ID, FLY_SUCCESS_VOLUME)
end

local function clearFlyConnections()
    if flyConn then
        pcall(function()
            flyConn:Disconnect()
        end)
        flyConn = nil
    end
    if flyCharRemovingConn then
        pcall(function()
            flyCharRemovingConn:Disconnect()
        end)
        flyCharRemovingConn = nil
    end
    if destTouchedConn then
        pcall(function()
            destTouchedConn:Disconnect()
        end)
        destTouchedConn = nil
    end
end

local function destroyFlyBodies()
    if flyLV then
        pcall(function()
            flyLV:Destroy()
        end)
        flyLV = nil
    end
    if flyAtt then
        pcall(function()
            flyAtt:Destroy()
        end)
        flyAtt = nil
    end
    destPartRef = nil
end

local function findMyDeliveryPart()
    local plots = Workspace:FindFirstChild('Plots')
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild('PlotSign')
            if
                sign
                and sign:FindFirstChild('YourBase')
                and sign.YourBase.Enabled
            then
                local delivery = plot:FindFirstChild('DeliveryHitbox')
                if delivery and delivery:IsA('BasePart') then
                    return delivery
                end
            end
        end
    end
    return nil
end

local function flyGetDescent(dist)
    local maxdist = 200
    dist = math.clamp(dist, 0, maxdist)
    local t = 1 - (dist / maxdist)
    return FLY_Y_BASE + (FLY_Y_MAX - FLY_Y_BASE) * t
end

local function restoreSourceAndPhysics()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass('Humanoid')
    if hum then
        if gravityLow then
            Workspace.Gravity = REDUCED_GRAV
            setJumpPower(BOOST_JUMP)
            enableSpeedBoostAssembly(true)
            enableInfiniteJump(true)
        else
            Workspace.Gravity = NORMAL_GRAV
            setJumpPower(NORMAL_JUMP)
            enableSpeedBoostAssembly(false)
            enableInfiniteJump(false)
        end
        spoofedGravity = NORMAL_GRAV
    else
        Workspace.Gravity = flyRestoreOldGravity or NORMAL_GRAV
        spoofedGravity = NORMAL_GRAV
        pcall(function()
            if hum and flyRestoreOldJumpPower then
                hum.JumpPower = flyRestoreOldJumpPower
            end
        end)
    end
end

local function cleanupFly()
    clearFlyConnections()
    destroyFlyBodies()
    restoreSourceAndPhysics()
    setFlyButtonActive(false)
end

local function finishFly(success)
    flyActive = false
    cleanupFly()
    if success then
        playFlySuccessSound()
        showStatus('Fly to Base concluído!', greenOn)
    else
        showStatus('Fly to Base cancelado.', Color3.fromRGB(255, 200, 100))
    end
end

local function startFlyToBase()
    if flyActive then
        finishFly(false)
        return
    end

    local destPart = findMyDeliveryPart()
    if not destPart then
        showStatus('Delivery da sua base não encontrada')
        return
    end

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass('Humanoid')
    local hrp = char and char:FindFirstChild('HumanoidRootPart')
    if not (hum and hrp) then
        return
    end

    flyRestoreOldGravity = Workspace.Gravity
    flyRestoreOldJumpPower = hum.JumpPower

    enableSpeedBoostAssembly(false)
    enableInfiniteJump(false)

    Workspace.Gravity = FLY_GRAV
    spoofedGravity = NORMAL_GRAV
    hum.UseJumpPower = true
    hum.JumpPower = FLY_JUMP

    flyActive = true
    setFlyButtonActive(true)

    flyAtt = Instance.new('Attachment')
    flyAtt.Name = 'FlyToBaseAttachment'
    flyAtt.Parent = hrp

    flyLV = Instance.new('LinearVelocity')
    flyLV.Attachment0 = flyAtt
    flyLV.RelativeTo = Enum.ActuatorRelativeTo.World
    flyLV.MaxForce = math.huge
    flyLV.Parent = hrp

    destPartRef = destPart

    local reached = false
    local lastYUpdate = 0

    do
        local pos = hrp.Position
        local destPos = destPart.Position
        local distXZ = (Vector3.new(destPos.X, pos.Y, destPos.Z) - pos).Magnitude
        local yVel = flyGetDescent(distXZ)
        local dirXZ = Vector3.new(destPos.X - pos.X, 0, destPos.Z - pos.Z)
        if dirXZ.Magnitude > 0 then
            dirXZ = dirXZ.Unit
        else
            dirXZ = Vector3.new()
        end
        flyLV.VectorVelocity =
            Vector3.new(dirXZ.X * FLY_XZ_SPEED, yVel, dirXZ.Z * FLY_XZ_SPEED)
        lastYUpdate = tick()
    end

    destTouchedConn = destPart.Touched:Connect(function(hit)
        if not flyActive then
            return
        end
        local ch = player.Character
        if ch and hit and hit:IsDescendantOf(ch) then
            reached = true
            finishFly(true)
        end
    end)

    if flyConn then
        flyConn:Disconnect()
        flyConn = nil
    end
    flyConn = RunService.Heartbeat:Connect(function()
        if not flyActive then
            cleanupFly()
            return
        end

        if not (hrp and hrp.Parent and hum and hum.Parent) then
            finishFly(false)
            return
        end

        local pos = hrp.Position
        local destPos = destPart.Position
        local distXZ = (Vector3.new(destPos.X, pos.Y, destPos.Z) - pos).Magnitude

        if distXZ < FLY_STOPDIST and not reached then
            reached = true
            finishFly(true)
            return
        end

        if tick() - lastYUpdate >= FLY_TIME_STEP then
            local yVel = flyGetDescent(distXZ)
            local dirXZ = Vector3.new(destPos.X - pos.X, 0, destPos.Z - pos.Z)
            if dirXZ.Magnitude > 0 then
                dirXZ = dirXZ.Unit
            else
                dirXZ = Vector3.new()
            end
            flyLV.VectorVelocity = Vector3.new(
                dirXZ.X * FLY_XZ_SPEED,
                yVel,
                dirXZ.Z * FLY_XZ_SPEED
            )
            lastYUpdate = tick()
        end
    end)

    if flyCharRemovingConn then
        flyCharRemovingConn:Disconnect()
        flyCharRemovingConn = nil
    end
    flyCharRemovingConn = player.CharacterRemoving:Connect(function()
        if flyActive then
            finishFly(false)
        else
            cleanupFly()
        end
    end)
end

_G.Miranda_StartFlyToBase = startFlyToBase

updateDesyncButton()
updateInfJumpButton()

----------------------------------------------------------------
-- ESP BASE (otimizado com cache)
----------------------------------------------------------------
do
    local Workspace_local = game:GetService('Workspace')

    local function clearBaseESP_repl()
        local plotsFolder = Workspace_local:FindFirstChild('Plots')
        if plotsFolder then
            for _, plot in pairs(plotsFolder:GetChildren()) do
                local descendants = getCachedDescendants(plot)
                for _, model in pairs(descendants) do
                    if typeof(model) == 'Instance' then
                        if model:FindFirstChild('Base_ESP') then
                            pcall(function()
                                model.Base_ESP:Destroy()
                            end)
                        end
                    end
                end
            end
        end
    end

    local function updateESPBase()
        local plotsFolder = Workspace_local:FindFirstChild('Plots')
        if not plotsFolder then
            return
        end

        local myPlotName
        for _, plot in pairs(plotsFolder:GetChildren()) do
            local plotSign = plot:FindFirstChild('PlotSign')
            if
                plotSign
                and plotSign:FindFirstChild('YourBase')
                and plotSign.YourBase.Enabled
            then
                myPlotName = plot.Name
                break
            end
        end

        if not espConfig.enabledBase or not myPlotName then
            clearBaseESP_repl()
            return
        end

        for _, plot in pairs(plotsFolder:GetChildren()) do
            if plot.Name ~= myPlotName then
                local purchases = plot:FindFirstChild('Purchases')
                local pb = purchases and purchases:FindFirstChild('PlotBlock')
                local main = pb and pb:FindFirstChild('Main')
                local gui = main and main:FindFirstChild('BillboardGui')
                local timeLb = gui and gui:FindFirstChild('RemainingTime')
                if timeLb and main then
                    local parentModel = main
                    local existingBillboard =
                        parentModel:FindFirstChild('Base_ESP')
                    if not existingBillboard then
                        local billboard = Instance.new('BillboardGui')
                        billboard.Name = 'Base_ESP'
                        billboard.Size = UDim2.new(0, 140, 0, 36)
                        billboard.StudsOffset = Vector3.new(0, 5, 0)
                        billboard.AlwaysOnTop = true
                        billboard.Parent = parentModel

                        local label = Instance.new('TextLabel')
                        label.Text = timeLb.Text
                        label.Size = UDim2.new(1, 0, 1, 0)
                        label.BackgroundTransparency = 1
                        label.TextScaled = true
                        label.TextColor3 = Color3.fromRGB(220, 0, 60)
                        label.Font = Enum.Font.Arcade
                        label.TextStrokeTransparency = 0.5
                        label.TextStrokeColor3 = Color3.new(0, 0, 0)
                        label.Parent = billboard

                        pcall(function()
                            if billboard.SetAttribute then
                                billboard:SetAttribute('lastTime', label.Text)
                            end
                        end)
                    else
                        local label =
                            existingBillboard:FindFirstChildOfClass('TextLabel')
                        if label then
                            local last =
                                safeGetAttribute(existingBillboard, 'lastTime')
                            local newText = timeLb.Text
                            if last ~= newText then
                                label.Text = newText
                                pcall(function()
                                    if existingBillboard.SetAttribute then
                                        existingBillboard:SetAttribute(
                                            'lastTime',
                                            newText
                                        )
                                    end
                                end)
                            end
                        end
                    end
                elseif main and main:FindFirstChild('Base_ESP') then
                    pcall(function()
                        main.Base_ESP:Destroy()
                    end)
                end
            end
        end
    end

    function startBaseESP()
        espConfig.enabledBase = true
        pcall(updateESPBase)
    end

    function stopBaseESP()
        espConfig.enabledBase = false
        pcall(clearBaseESP_repl)
    end

    task.spawn(function()
        while true do
            task.wait(BASE_UPDATE_INTERVAL)
            pcall(updateESPBase)
        end
    end)
end

----------------------------------------------------------------
-- GO TO BEST + NEW STEAL FLOOR
----------------------------------------------------------------
local ProximityPromptService = game:GetService('ProximityPromptService')

-- GO TO BEST state
local goToBestActive = false
local goToBestConn
local goToBestAtt, goToBestLV

-- NEW STEAL FLOOR state
local stealFloorActive = false
local stealFloorConn, stealFloorPromptConn, stealFloorDiedConn
local stealFloorAtt, stealFloorLV
local stealFloorOriginalProps = {}

local function safeDisconnectHelper(conn)
    if conn and typeof(conn) == 'RBXScriptConnection' then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

-- GO TO BEST Functions
local function goToBestFindBestPet()
    local plotsFolder = Workspace:FindFirstChild('Plots')
    if not plotsFolder then return nil end
    
    local myPlotName
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local plotSign = plot:FindFirstChild('PlotSign')
        if plotSign and plotSign:FindFirstChild('YourBase') and plotSign.YourBase.Enabled then
            myPlotName = plot.Name
            break
        end
    end
    
    local bestPet = nil
    local bestMps = 0
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot.Name ~= myPlotName then
            for _, desc in ipairs(getCachedDescendants(plot)) do
                if desc:IsA('TextLabel') and desc.Name == 'Rarity' and desc.Parent and desc.Parent:FindFirstChild('DisplayName') then
                    local genLabel = desc.Parent:FindFirstChild('Generation')
                    if genLabel and genLabel:IsA('TextLabel') then
                        local mps = parseMoneyPerSec(genLabel.Text)
                        if mps > bestMps then
                            bestMps = mps
                            bestPet = desc.Parent.Parent
                        end
                    end
                end
            end
        end
    end
    
    return bestPet
end

local function goToBestEnable()
    if goToBestActive then
        goToBestDisable()
        return
    end
    
    local bestPet = goToBestFindBestPet()
    if not bestPet then
        showStatus('Best pet not found')
        return
    end
    
    local char = player.Character
    local hrp = char and char:FindFirstChild('HumanoidRootPart')
    if not hrp then return end
    
    goToBestActive = true
    
    goToBestAtt = Instance.new('Attachment')
    goToBestAtt.Name = 'GoToBest_Attachment'
    goToBestAtt.Parent = hrp
    
    goToBestLV = Instance.new('LinearVelocity')
    goToBestLV.Attachment0 = goToBestAtt
    goToBestLV.RelativeTo = Enum.ActuatorRelativeTo.World
    goToBestLV.MaxForce = math.huge
    goToBestLV.Parent = hrp
    
    safeDisconnectHelper(goToBestConn)
    goToBestConn = RunService.Heartbeat:Connect(function()
        if not goToBestActive or not goToBestLV then return end
        if not (hrp and hrp.Parent and bestPet and bestPet.Parent) then
            goToBestDisable()
            return
        end
        
        local targetPos = bestPet:GetPivot().Position
        local currentPos = hrp.Position
        local direction = (targetPos - currentPos).Unit
        local distance = (targetPos - currentPos).Magnitude
        
        if distance < 5 then
            goToBestDisable()
            showStatus('Reached best pet!', greenOn)
            return
        end
        
        goToBestLV.VectorVelocity = direction * 25
    end)
end

function goToBestDisable()
    goToBestActive = false
    if goToBestLV then pcall(function() goToBestLV:Destroy() end) goToBestLV = nil end
    if goToBestAtt then pcall(function() goToBestAtt:Destroy() end) goToBestAtt = nil end
    safeDisconnectHelper(goToBestConn)
    goToBestConn = nil
end

-- NEW STEAL FLOOR Functions
local function stealFloorSetTransparency(active)
    local plots = Workspace:FindFirstChild('Plots')
    if not plots then return end
    
    if active then
        stealFloorOriginalProps = {}
        for _, plot in ipairs(plots:GetChildren()) do
            local containers = {plot:FindFirstChild('Decorations'), plot:FindFirstChild('AnimalPodiums')}
            for _, container in ipairs(containers) do
                if container then
                    for _, obj in ipairs(container:GetDescendants()) do
                        if obj:IsA('BasePart') then
                            stealFloorOriginalProps[obj] = {Transparency = obj.Transparency}
                            obj.Transparency = 0.7
                        end
                    end
                end
            end
        end
    else
        for part, props in pairs(stealFloorOriginalProps) do
            if part and part.Parent then
                part.Transparency = props.Transparency
            end
        end
        stealFloorOriginalProps = {}
    end
end

local function stealFloorTeleportToGround()
    local char = player.Character
    local rp = char and char:FindFirstChild('HumanoidRootPart')
    local hum = char and char:FindFirstChildOfClass('Humanoid')
    if not (rp and hum and hum.Health > 0) then return end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {char}
    
    local rayResult = Workspace:Raycast(rp.Position, Vector3.new(0, -1500, 0), rayParams)
    if rayResult then
        rp.CFrame = CFrame.new(rp.Position.X, rayResult.Position.Y + hum.HipHeight, rp.Position.Z)
        if stealFloorActive then
            stealFloorDisable()
        end
    end
end

local function stealFloorEnable(btn)
    if stealFloorActive then return end
    
    local hum = getHumanoid()
    local root = getHRP()
    if not (hum and hum.Health > 0 and root) then return end
    
    stealFloorActive = true
    stealFloorSetTransparency(true)
    
    stealFloorAtt = Instance.new('Attachment')
    stealFloorAtt.Name = 'StealFloor_Attachment'
    stealFloorAtt.Parent = root
    
    stealFloorLV = Instance.new('LinearVelocity')
    stealFloorLV.Attachment0 = stealFloorAtt
    stealFloorLV.MaxForce = 500000
    stealFloorLV.ForceLimitMode = Enum.ForceLimitMode.PerAxis
    stealFloorLV.MaxAxesForce = Vector3.new(0, math.huge, 0)
    stealFloorLV.VectorVelocity = Vector3.new(0, 24, 0)
    stealFloorLV.Parent = root
    
    safeDisconnectHelper(stealFloorConn)
    stealFloorConn = RunService.Heartbeat:Connect(function()
        if not stealFloorActive or not stealFloorLV then return end
        local h = getHumanoid()
        if not (h and h.Health > 0) then
            stealFloorDisable(btn)
            return
        end
        stealFloorLV.VectorVelocity = Vector3.new(0, 24, 0)
    end)
    
    safeDisconnectHelper(stealFloorPromptConn)
    stealFloorPromptConn = ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
        if who == player then
            local act = (prompt.ActionText or ''):lower()
            if string.find(act, 'steal') then
                stealFloorTeleportToGround()
                if btn then
                    btn.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
                end
            end
        end
    end)
    
    safeDisconnectHelper(stealFloorDiedConn)
    if hum then
        stealFloorDiedConn = hum.Died:Connect(function()
            stealFloorDisable(btn)
        end)
    end
end

function stealFloorDisable(btn)
    if not stealFloorActive then
        stealFloorSetTransparency(false)
        if stealFloorLV then pcall(function() stealFloorLV:Destroy() end) end
        if stealFloorAtt then pcall(function() stealFloorAtt:Destroy() end) end
        safeDisconnectHelper(stealFloorConn)
        safeDisconnectHelper(stealFloorPromptConn)
        safeDisconnectHelper(stealFloorDiedConn)
        stealFloorLV, stealFloorAtt, stealFloorConn, stealFloorPromptConn, stealFloorDiedConn = nil, nil, nil, nil, nil
        return
    end
    stealFloorActive = false
    stealFloorSetTransparency(false)
    if stealFloorLV then pcall(function() stealFloorLV:Destroy() end) stealFloorLV = nil end
    if stealFloorAtt then pcall(function() stealFloorAtt:Destroy() end) stealFloorAtt = nil end
    safeDisconnectHelper(stealFloorConn)
    safeDisconnectHelper(stealFloorPromptConn)
    safeDisconnectHelper(stealFloorDiedConn)
    stealFloorConn, stealFloorPromptConn, stealFloorDiedConn = nil, nil, nil
    if btn then
        btn.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
    end
end

player.CharacterAdded:Connect(function()
    task.wait(0.1)
    stealFloorDisable(nil)
    goToBestDisable()
end)

-- Botão FLY TO BASE (mantido no mesmo lugar)
local flyY = 24 + 40 + 8 + 30 + 8
btnFlyToBase = Instance.new('TextButton', panel)
btnFlyToBase.Size = UDim2.new(0.88, 0, 0, 30)
btnFlyToBase.Position = UDim2.new(0.06, 0, 0, flyY)
btnFlyToBase.BackgroundColor3 = redOff
btnFlyToBase.Text = 'FLY TO BASE'
btnFlyToBase.Font = Enum.Font.Arcade
btnFlyToBase.TextColor3 = Color3.new(1, 1, 1)
btnFlyToBase.TextSize = 14
btnFlyToBase.BorderSizePixel = 0
Instance.new('UICorner', btnFlyToBase).CornerRadius = UDim.new(0, 8)
btnFlyToBase.MouseButton1Click:Connect(function()
    startFlyToBase()
end)

-- Botão GO TO BEST
local goToBestY = flyY + 30 + 8
local btnGoToBest = Instance.new('TextButton', panel)
btnGoToBest.Size = UDim2.new(0.88, 0, 0, 30)
btnGoToBest.Position = UDim2.new(0.06, 0, 0, goToBestY)
btnGoToBest.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
btnGoToBest.Text = 'GO TO BEST'
btnGoToBest.Font = Enum.Font.Arcade
btnGoToBest.TextColor3 = Color3.new(1, 1, 1)
btnGoToBest.TextSize = 14
btnGoToBest.BorderSizePixel = 0
Instance.new('UICorner', btnGoToBest).CornerRadius = UDim.new(0, 8)
btnGoToBest.MouseButton1Click:Connect(function()
    if not goToBestActive then
        goToBestEnable()
        btnGoToBest.BackgroundColor3 = Color3.fromRGB(60, 200, 60)
        showStatus('Go to Best ON', Color3.fromRGB(60, 200, 60))
    else
        goToBestDisable()
        btnGoToBest.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
        showStatus('Go to Best OFF')
    end
end)

-- Botão STEAL FLOOR (NOVO)
local stealFloorY = goToBestY + 30 + 8
local btnStealFloorNew = Instance.new('TextButton', panel)
btnStealFloorNew.Size = UDim2.new(0.88, 0, 0, 30)
btnStealFloorNew.Position = UDim2.new(0.06, 0, 0, stealFloorY)
btnStealFloorNew.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
btnStealFloorNew.Text = 'STEAL FLOOR'
btnStealFloorNew.Font = Enum.Font.Arcade
btnStealFloorNew.TextColor3 = Color3.new(1, 1, 1)
btnStealFloorNew.TextSize = 15
btnStealFloorNew.BorderSizePixel = 0
Instance.new('UICorner', btnStealFloorNew).CornerRadius = UDim.new(0, 8)
btnStealFloorNew.MouseButton1Click:Connect(function()
    if not stealFloorActive then
        stealFloorEnable(btnStealFloorNew)
        btnStealFloorNew.BackgroundColor3 = Color3.fromRGB(60, 200, 60)
        showStatus('Steal Floor ON', Color3.fromRGB(60, 200, 60))
    else
        stealFloorDisable(btnStealFloorNew)
        btnStealFloorNew.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
        showStatus('Steal Floor OFF')
    end
end)

-- Ajusta altura do painel para incluir os novos botões
do
    local bottom = stealFloorY + 30 + 12
    panel.Size = UDim2.new(0, 160, 0, bottom)
end

----------------------------------------------------------------
-- REMOÇÃO DE ACESSÓRIOS
----------------------------------------------------------------
local function removeAccessoriesFromCharacter(character)
    if not character then
        return
    end
    for _, item in ipairs(character:GetChildren()) do
        if item:IsA('Accessory') then
            pcall(function()
                item:Destroy()
            end)
        end
    end
end

local playersWithAccessoryListener = {}
local function ensureAccessoryListenerForPlayer(p)
    if not p or p == player or playersWithAccessoryListener[p] then
        return
    end
    playersWithAccessoryListener[p] = true
    p.CharacterAdded:Connect(function(ch)
        task.wait(0.2)
        removeAccessoriesFromCharacter(ch)
    end)
end

local function stripOtherPlayersAccessories_once()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            if p.Character then
                removeAccessoriesFromCharacter(p.Character)
            end
            ensureAccessoryListenerForPlayer(p)
        end
    end
end
stripOtherPlayersAccessories_once()

Players.PlayerAdded:Connect(function(p)
    if p ~= player then
        ensureAccessoryListenerForPlayer(p)
        if p.Character then
            task.wait(0.2)
            removeAccessoriesFromCharacter(p.Character)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(30)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and p.Character then
                pcall(function()
                    removeAccessoriesFromCharacter(p.Character)
                end)
            end
        end
    end
end)

----------------------------------------------------------------
-- BOTÃO OPEN + DRAG
----------------------------------------------------------------
local openBtn = Instance.new('ImageButton')
openBtn.Size = UDim2.new(0, 50, 0, 50)
openBtn.Position = UDim2.new(0, 20, 0.5, -20)
openBtn.Image = 'rbxassetid://108139283757930'
openBtn.BackgroundTransparency = 1
openBtn.Name = 'OpenButton'
openBtn.Parent = gui
Instance.new('UICorner', openBtn).CornerRadius = UDim.new(1, 0)
local glowBtn = Instance.new('UIStroke', openBtn)
glowBtn.Thickness = 2
glowBtn.Transparency = 0.15

task.spawn(function()
    while openBtn.Parent do
        task.wait(GLOW_UPDATE_INTERVAL)
        local t = math.sin(tick() * 1.4)
        glowBtn.Color = t > 0 and Color3.fromRGB(255, 215 + 20 * t, 30 * t)
            or Color3.fromRGB(
                255 - math.floor(40 * -t),
                0,
                60 - math.floor(40 * -t)
            )
    end
end)

openBtn.MouseButton1Click:Connect(function()
    menu.Visible = not menu.Visible
end)
panel.Visible = true

local function makeDraggable(obj)
    local dragging = false
    local dragStart, startPos
    obj.InputBegan:Connect(function(inp)
        if
            inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            dragStart = inp.Position
            startPos = obj.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    obj.InputChanged:Connect(function(inp)
        if
            inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch
        then
            if dragging then
                local delta = inp.Position - dragStart
                obj.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end
    end)
end

makeDraggable(menu)
makeDraggable(panel)
makeDraggable(openBtn)

notify('Miranda Hub', 'Script carregado com sucesso!', 5)

----------------------------------------------------------------
-- FINAL: Script otimizado para mobile
----------------------------------------------------------------
-- Otimizações aplicadas:
-- 1. Cache de GetDescendants (reduz varredura de árvore)
-- 2. Sound pooling (limita sons simultâneos)
-- 3. Intervalos aumentados (1.5s ESP, 0.25s glow)
-- 4. Debounce otimizado em CFrame updates
-- 5. Limpeza periódica de cache
-- Todas as funcionalidades mantidas intactas!
