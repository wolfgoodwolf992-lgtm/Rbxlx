-- MINIDISASTERS V7 - ATUALIZACAO COMPLETA INTEGRADA
-- Execute UMA VEZ na Command Bar do Roblox Studio, com o projeto V7 aberto.
-- Atualiza os dois scripts centrais, preserva os mapas e instala BTools básicas se faltarem.

local ServerSource = [==[
-- SISTEMA DE PARTIDA E VOTACAO - VERSAO V5 EXPANSAO E DESTRUICAO
-- Local: ServerScriptService > SistemaPartida (Script)

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

-- IDs de áudio de exemplo. Se algum asset estiver privado/indisponível,
-- troque pelo ID de um áudio permitido do Creator Store.
local AUDIOS = {
    Vento = "rbxassetid://2662419014",
    Chuva = "rbxassetid://1843670378",
    Fogo = "rbxassetid://1851463645",
    Impacto = "rbxassetid://130113415",
    UI = "rbxassetid://72046313",
}
local somAmbienteAtual
local function tocarSomGlobal(id, volume, looped)
    if not id or id == "" then return nil end
    local som = Instance.new("Sound")
    som.Name = "AudioDesastre"
    som.SoundId = id
    som.Volume = volume or 0.45
    som.Looped = looped == true
    som.Parent = SoundService
    som:Play()
    if looped then
        if somAmbienteAtual then somAmbienteAtual:Stop(); somAmbienteAtual:Destroy() end
        somAmbienteAtual = som
    else
        Debris:AddItem(som, 12)
    end
    return som
end
local function pararSomAmbiente()
    if somAmbienteAtual then
        somAmbienteAtual:Stop()
        somAmbienteAtual:Destroy()
        somAmbienteAtual = nil
    end
end

local INTERVALO = 15
local TEMPO_VOTACAO = 20
local DURACAO_PARTIDA = 90 -- duração confirmada da rodada
local DURACAO_DESASTRE = DURACAO_PARTIDA

local mapasFolder = ServerStorage:WaitForChild("Mapas")
local mapasAtivos = workspace:FindFirstChild("MapaAtual") or Instance.new("Folder")
mapasAtivos.Name = "MapaAtual"
mapasAtivos.Parent = workspace

local eventos = ReplicatedStorage:FindFirstChild("EventosPartida") or Instance.new("Folder")
eventos.Name = "EventosPartida"
eventos.Parent = ReplicatedStorage

local roundEvent = eventos:FindFirstChild("RoundEvent") or Instance.new("RemoteEvent")
roundEvent.Name = "RoundEvent"
roundEvent.Parent = eventos

local voteEvent = eventos:FindFirstChild("VoteEvent") or Instance.new("RemoteEvent")
voteEvent.Name = "VoteEvent"
voteEvent.Parent = eventos

local prontoEvent = eventos:FindFirstChild("ClientePronto") or Instance.new("RemoteEvent")
prontoEvent.Name = "ClientePronto"
prontoEvent.Parent = eventos

-- Remotes do painel ADM (validacao sempre feita no servidor).
local adminRemotes = ReplicatedStorage:FindFirstChild("AdminRemotes") or Instance.new("Folder")
adminRemotes.Name = "AdminRemotes"
adminRemotes.Parent = ReplicatedStorage
local adminEvent = adminRemotes:FindFirstChild("AdminEvent") or Instance.new("RemoteEvent")
adminEvent.Name = "AdminEvent"
adminEvent.Parent = adminRemotes
local adminFeedback = adminRemotes:FindFirstChild("AdminFeedback") or Instance.new("RemoteEvent")
adminFeedback.Name = "AdminFeedback"
adminFeedback.Parent = adminRemotes
local buildAction = adminRemotes:FindFirstChild("BuildAction") or Instance.new("RemoteEvent")
buildAction.Name = "BuildAction"
buildAction.Parent = adminRemotes
local ADMIN_USERNAME = "w00byd0lx"
local DESASTRES_ADMIN = {
    ["Chuva de Meteoros"] = true,
    ["Tornado"] = true,
    ["Terremoto"] = true,
    ["Nevasca"] = true,
    ["Tempestade de Raios"] = true,
    ["Chuva de Fogo"] = true,
}
local function jogadorEhAdmin(jogador)
    return jogador and string.lower(jogador.Name) == string.lower(ADMIN_USERNAME)
end
local function responderAdmin(jogador, mensagem, sucesso)
    adminFeedback:FireClient(jogador, tostring(mensagem), sucesso == true)
end
local function encontrarJogadorPorPrefixo(entrada)
    if typeof(entrada) ~= "string" then return nil, "Digite o nome de um jogador." end
    local busca = string.lower(string.match(entrada, "^%s*(.-)%s*$") or "")
    if busca == "" then return nil, "Digite o nome de um jogador." end
    local correspondencias = {}
    for _, alvo in ipairs(Players:GetPlayers()) do
        if string.lower(alvo.Name) == busca then return alvo end
        if string.sub(string.lower(alvo.Name), 1, #busca) == busca
            or string.sub(string.lower(alvo.DisplayName), 1, #busca) == busca then
            table.insert(correspondencias, alvo)
        end
    end
    if #correspondencias == 1 then return correspondencias[1] end
    if #correspondencias > 1 then return nil, "Nome inicial encontrado em vários jogadores. Digite mais letras." end
    return nil, "Jogador não encontrado."
end
-- BTools integrado: mover, clonar e apagar peças do mapa atual, apenas pelo ADM.
local PARTES_PROTEGIDAS = {
    Chao=true, Areia=true, Plataforma=true, Baseplate=true, SpawnLocation=true,
    PisoInterno=true, PisoCaverna=true, ZonaSegura=true, ZonaSeguraCaverna=true,
}
local function podeEditarParte(parte)
    if typeof(parte) ~= "Instance" or not parte:IsA("BasePart") then return false end
    local mapa = workspace:FindFirstChild("MapaAtual")
    if not mapa or not parte:IsDescendantOf(mapa) then return false end
    local nome = string.lower(parte.Name)
    if PARTES_PROTEGIDAS[parte.Name] or string.find(nome, "limite_", 1, true)
        or string.find(nome, "zonasegura", 1, true) or string.find(nome, "spawn", 1, true)
        or string.find(nome, "piso", 1, true) then return false end
    return true
end
buildAction.OnServerEvent:Connect(function(jogador, acao, parte, posicao)
    if not jogadorEhAdmin(jogador) then return end
    local personagem = jogador.Character
    local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart")
    local ferramentaEquipada = personagem and personagem:FindFirstChild("F3X")
    if not raiz or not ferramentaEquipada or not ferramentaEquipada:IsA("Tool") then return end
    if not podeEditarParte(parte) or (parte.Position - raiz.Position).Magnitude > 260 then return end
    if acao == "Delete" then
        parte:Destroy()
    elseif acao == "Clone" then
        local copia = parte:Clone()
        copia.Anchored = true
        copia.CFrame = parte.CFrame + Vector3.new(5, 0, 5)
        copia.Parent = parte.Parent
    elseif acao == "Move" and typeof(posicao) == "Vector3" then
        local mapa = workspace:FindFirstChild("MapaAtual")
        local caixa, tamanho = mapa:GetBoundingBox()
        local limiteX = tamanho.X * 0.48
        local limiteZ = tamanho.Z * 0.48
        local x = math.clamp(posicao.X, caixa.Position.X - limiteX, caixa.Position.X + limiteX)
        local z = math.clamp(posicao.Z, caixa.Position.Z - limiteZ, caixa.Position.Z + limiteZ)
        parte.Position = Vector3.new(x, parte.Position.Y, z)
    end
end)

adminEvent.OnServerEvent:Connect(function(jogador, acao, valor, extra)
    if not jogadorEhAdmin(jogador) then
        warn("[MiniDisasters ADM] Tentativa não autorizada de " .. (jogador and jogador.Name or "desconhecido"))
        return
    end
    if acao == "SetNextDisaster" then
        if typeof(valor) ~= "string" or not DESASTRES_ADMIN[valor] then
            responderAdmin(jogador, "Desastre inválido.", false)
            return
        end
        ReplicatedStorage:SetAttribute("AdminNextDisaster", valor)
        responderAdmin(jogador, "Próximo desastre definido: " .. valor, true)
    elseif acao == "Kick" then
        local alvo, erro = encontrarJogadorPorPrefixo(valor)
        if not alvo then responderAdmin(jogador, erro or "Jogador não encontrado.", false); return end
        if alvo == jogador then responderAdmin(jogador, "Você não pode expulsar a si mesmo.", false); return end
        local motivo = typeof(extra) == "string" and string.sub(extra, 1, 180) or ""
        motivo = string.match(motivo, "^%s*(.-)%s*$") or ""
        if motivo == "" then motivo = "Expulso por um administrador." end
        alvo:Kick(motivo)
        responderAdmin(jogador, "Jogador " .. alvo.Name .. " foi expulso.", true)
    elseif acao == "GiveF3X" then
        local ferramenta = ServerStorage:FindFirstChild("F3X")
        if not ferramenta or not ferramenta:IsA("Tool") then
            responderAdmin(jogador, 'F3X não configurada. Coloque a Tool chamada "F3X" em ServerStorage.', false)
            return
        end
        local mochila = jogador:FindFirstChildOfClass("Backpack")
        if not mochila then responderAdmin(jogador, "A mochila ainda não está disponível.", false); return end
        if mochila:FindFirstChild("F3X") or (jogador.Character and jogador.Character:FindFirstChild("F3X")) then
            responderAdmin(jogador, "Você já possui a F3X.", false)
            return
        end
        ferramenta:Clone().Parent = mochila
        responderAdmin(jogador, "F3X entregue.", true)
    end
end)

local clientesProntos = {}
prontoEvent.OnServerEvent:Connect(function(jogador)
    clientesProntos[jogador.UserId] = true
end)
local votos = {}

Players.PlayerRemoving:Connect(function(jogador)
    clientesProntos[jogador.UserId] = nil
    votos[jogador.UserId] = nil
end)
local opcoes = {}
local votacaoAberta = false
local mapaAtual
local zonasSeguras = {}
local efeitosDesastre = nil
local rodadaAtiva = false

local function criarPastaEfeitos()
    if efeitosDesastre then efeitosDesastre:Destroy() end
    efeitosDesastre = Instance.new("Folder")
    efeitosDesastre.Name = "EfeitosDesastre"
    efeitosDesastre.Parent = workspace
end

local function limparEfeitosDesastre()
    if efeitosDesastre then
        efeitosDesastre:Destroy()
        efeitosDesastre = nil
    end
end

local function existeJogadorVivo()
    for _, jogador in ipairs(Players:GetPlayers()) do
        local personagem = jogador.Character
        local humanoide = personagem and personagem:FindFirstChildOfClass("Humanoid")
        if humanoide and humanoide.Health > 0 and not jogador:GetAttribute("NoLobby") then
            return true
        end
    end
    return false
end

local DESASTRES = {
    "Chuva de Meteoros", "Tornado", "Terremoto",
    "Nevasca", "Tempestade de Raios", "Chuva de Fogo"
}

local function anunciar(texto)
    roundEvent:FireAllClients("Mensagem", texto)
    print("[SISTEMA DE PARTIDA] " .. texto)
end

local function limparMapa()
    for _, objeto in ipairs(mapasAtivos:GetChildren()) do
        objeto:Destroy()
    end
    mapaAtual = nil
    zonasSeguras = {}
end

local function obterTodosOsMapas()
    local lista = {}
    for _, objeto in ipairs(mapasFolder:GetChildren()) do
        if objeto:IsA("Model") then
            table.insert(lista, objeto.Name)
        end
    end
    table.sort(lista)
    return lista
end

local function contarVotos()
    local contagem = {}
    for _, nome in ipairs(opcoes) do
        contagem[nome] = 0
    end
    for _, nome in pairs(votos) do
        if contagem[nome] ~= nil then
            contagem[nome] += 1
        end
    end
    return contagem
end

local plataformasVotacao = workspace:FindFirstChild("PlataformasVotacao")
if plataformasVotacao then plataformasVotacao:Destroy() end
plataformasVotacao = Instance.new("Folder")
plataformasVotacao.Name = "PlataformasVotacao"
plataformasVotacao.Parent = workspace

-- Lobby separado da arena: quem acabou de entrar ou foi eliminado permanece aqui.
local lobbyFolder = workspace:FindFirstChild("LobbyPrincipal")
if lobbyFolder then lobbyFolder:Destroy() end
lobbyFolder = Instance.new("Folder")
lobbyFolder.Name = "LobbyPrincipal"
lobbyFolder.Parent = workspace

local spawnLobby = workspace:FindFirstChild("SpawnLocation")
if not spawnLobby then
    spawnLobby = Instance.new("Part")
    spawnLobby.Name = "SpawnLocation"
    spawnLobby.Size = Vector3.new(6, 1, 6)
    spawnLobby.Anchored = true
    spawnLobby.Parent = workspace
end
spawnLobby.Anchored = true
spawnLobby.CanCollide = false
spawnLobby.CanTouch = true
spawnLobby.Transparency = 1
spawnLobby.Position = Vector3.new(0, 4, 620)

local function criarLobby()
    local piso = Instance.new("Part")
    piso.Name = "PisoLobby"
    piso.Anchored = true
    piso.Size = Vector3.new(170, 2, 170)
    piso.Position = Vector3.new(0, 0, 620)
    piso.Material = Enum.Material.Slate
    piso.Color = Color3.fromRGB(35, 47, 65)
    piso.Parent = lobbyFolder

    local plataformaCentral = Instance.new("Part")
    plataformaCentral.Name = "PracaCentral"
    plataformaCentral.Anchored = true
    plataformaCentral.Size = Vector3.new(38, 1, 24)
    plataformaCentral.Position = Vector3.new(0, 1.55, 600)
    plataformaCentral.Material = Enum.Material.SmoothPlastic
    plataformaCentral.Color = Color3.fromRGB(65, 91, 120)
    plataformaCentral.Parent = lobbyFolder

    local placa = Instance.new("Part")
    placa.Name = "PlacaLobby"
    placa.Anchored = true
    placa.CanCollide = false
    placa.Size = Vector3.new(34, 9, 1)
    placa.Position = Vector3.new(0, 11, 565)
    placa.Material = Enum.Material.Metal
    placa.Color = Color3.fromRGB(20, 29, 43)
    placa.Parent = lobbyFolder
    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Front
    gui.AlwaysOnTop = true
    gui.PixelsPerStud = 35
    gui.Parent = placa
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = "LOBBY  •  VOTE NO MAPA"
    label.TextColor3 = Color3.fromRGB(235, 245, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBlack
    label.Parent = gui

    -- Muros baixos e pilares deixam claro o limite do lobby sem bloquear a votação.
    for _, dado in ipairs({
        {Vector3.new(170, 12, 2), Vector3.new(0, 6, 535)},
        {Vector3.new(170, 12, 2), Vector3.new(0, 6, 705)},
        {Vector3.new(2, 12, 170), Vector3.new(-85, 6, 620)},
        {Vector3.new(2, 12, 170), Vector3.new(85, 6, 620)},
    }) do
        local muro = Instance.new("Part")
        muro.Name = "ParedeDecorativaLobby"
        muro.Anchored = true
        muro.Size = dado[1]
        muro.Position = dado[2]
        muro.Material = Enum.Material.Glass
        muro.Transparency = 0.55
        muro.Color = Color3.fromRGB(80, 155, 205)
        muro.Parent = lobbyFolder
    end
end
criarLobby()

local function teleportarParaLobby(jogador, personagem)
    personagem = personagem or jogador.Character
    local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart")
    if raiz then
        jogador:SetAttribute("NoLobby", true)
        raiz.AssemblyLinearVelocity = Vector3.zero
        raiz.CFrame = CFrame.new(spawnLobby.Position + Vector3.new(math.random(-9, 9), 3, math.random(-9, 9)))
    end
end

local function prepararJogador(jogador)
    jogador:SetAttribute("NoLobby", true)
    jogador.CharacterAdded:Connect(function(personagem)
        local humanoide = personagem:WaitForChild("Humanoid", 10)
        local raiz = personagem:WaitForChild("HumanoidRootPart", 10)
        if not raiz then return end
        if jogador:GetAttribute("NoLobby") or rodadaAtiva then
            task.wait(0.15)
            teleportarParaLobby(jogador, personagem)
        end
        if humanoide then
            humanoide.Died:Connect(function()
                jogador:SetAttribute("NoLobby", true)
            end)
        end
    end)
    if jogador.Character then
        task.defer(teleportarParaLobby, jogador, jogador.Character)
    end
end
Players.PlayerAdded:Connect(prepararJogador)
for _, jogador in ipairs(Players:GetPlayers()) do prepararJogador(jogador) end

local coresMapas = {
    Cidade = Color3.fromRGB(70, 145, 235),
    Ilha_Tropical = Color3.fromRGB(45, 190, 125),
    Montanhas = Color3.fromRGB(130, 145, 165),
    Deserto = Color3.fromRGB(225, 165, 65),
}

local function atualizarPainelPlataforma(plataforma, quantidade)
    local placa = plataforma:FindFirstChild("PlacaDoMapa")
    local gui = placa and placa:FindFirstChild("PainelVotos")
    local texto = gui and gui:FindFirstChild("TextoVotos")
    if texto then
        local nome = plataforma:GetAttribute("NomeMapa") or "Mapa"
        texto.Text = nome:gsub("_", " ") .. "\n" .. tostring(quantidade or 0) .. " votos"
    end
end

local function registrarVoto(jogador, nomeMapa)
    if not votacaoAberta then return end
    if not jogador or not table.find(opcoes, nomeMapa) then return end
    votos[jogador.UserId] = nomeMapa
    local contagem = contarVotos()
    for _, plataforma in ipairs(plataformasVotacao:GetChildren()) do
        local nome = plataforma:GetAttribute("NomeMapa")
        atualizarPainelPlataforma(plataforma, contagem[nome] or 0)
    end
    roundEvent:FireAllClients("Contagem", contagem)
end

local ultimoToque = {}
local function criarPlataformasVotacao()
    local spawn = workspace:FindFirstChild("SpawnLocation")
    local origem = spawn and spawn.Position or Vector3.new(0, 4, 0)
    local mapasDisponiveis = obterTodosOsMapas()
    local cores = coresMapas
    cores.Vila_Costeira = Color3.fromRGB(45, 165, 190)

    for indice, nomeMapa in ipairs(mapasDisponiveis) do
        local coluna = (indice - 1) % 3
        local linha = math.floor((indice - 1) / 3)
        local x = (coluna - 1) * 23 + (linha == 1 and 11.5 or 0)
        local z = 30 + linha * 27
        local cor = cores[nomeMapa] or Color3.fromRGB(110, 145, 190)

        local plataforma = Instance.new("Part")
        plataforma.Name = "Plataforma_" .. nomeMapa
        plataforma.Anchored = true
        plataforma.Size = Vector3.new(17, 1.4, 17)
        plataforma.Material = Enum.Material.Slate
        plataforma.Color = Color3.fromRGB(34, 42, 56)
        plataforma.TopSurface = Enum.SurfaceType.Smooth
        plataforma.BottomSurface = Enum.SurfaceType.Smooth
        plataforma.Position = origem + Vector3.new(x, -3.5, z)
        plataforma:SetAttribute("NomeMapa", nomeMapa)
        plataforma.Parent = plataformasVotacao

        local aro = Instance.new("Part")
        aro.Name = "AroNeon"
        aro.Anchored = true; aro.CanCollide = false; aro.Material = Enum.Material.Neon
        aro.Color = cor; aro.Transparency = 0.12
        aro.Size = Vector3.new(17.8, 0.22, 17.8)
        aro.Position = plataforma.Position + Vector3.new(0, 0.82, 0)
        aro.Parent = plataforma

        local topo = Instance.new("Part")
        topo.Name = "PisoDaPlataforma"
        topo.Anchored = true; topo.Material = Enum.Material.SmoothPlastic
        topo.Color = cor:Lerp(Color3.fromRGB(25,30,42),0.38)
        topo.Size = Vector3.new(15.8,0.35,15.8)
        topo.Position = plataforma.Position + Vector3.new(0,0.86,0)
        topo.Parent = plataforma

        local colunaCentral = Instance.new("Part")
        colunaCentral.Name = "ColunaDecorativa"
        colunaCentral.Anchored = true; colunaCentral.Material = Enum.Material.Metal
        colunaCentral.Color = Color3.fromRGB(75,85,105)
        colunaCentral.Size = Vector3.new(1.2,4.8,1.2)
        colunaCentral.Position = plataforma.Position + Vector3.new(0,3.2,6.5)
        colunaCentral.Parent = plataforma

        local placa = Instance.new("Part")
        placa.Name = "PlacaDoMapa"
        placa.Anchored = true; placa.CanCollide = false
        placa.Material = Enum.Material.Metal
        placa.Color = Color3.fromRGB(22,28,40)
        placa.Size = Vector3.new(15.5,6.5,0.8)
        placa.Position = plataforma.Position + Vector3.new(0,6.8,7.0)
        placa.Parent = plataforma

        local painel = Instance.new("SurfaceGui")
        painel.Name = "PainelVotos"
        painel.Face = Enum.NormalId.Front
        painel.AlwaysOnTop = true
        painel.LightInfluence = 0
        painel.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
        painel.PixelsPerStud = 40
        painel.Parent = placa

        local texto = Instance.new("TextLabel")
        texto.Name = "TextoVotos"
        texto.Size = UDim2.fromScale(1,1)
        texto.BackgroundColor3 = Color3.fromRGB(22,27,38)
        texto.BackgroundTransparency = 0.04
        texto.TextColor3 = Color3.fromRGB(245,248,255)
        texto.Text = nomeMapa:gsub("_"," ") .. "\n0 VOTOS"
        texto.TextScaled = true
        texto.Font = Enum.Font.GothamBlack
        texto.Parent = painel
        local stroke = Instance.new("UIStroke")
        stroke.Color = cor; stroke.Thickness = 2; stroke.Transparency = 0.12
        stroke.Parent = texto
        local limite = Instance.new("UITextSizeConstraint")
        limite.MinTextSize = 12; limite.MaxTextSize = 28; limite.Parent = texto

        local luz = Instance.new("PointLight")
        luz.Color = cor; luz.Range = 15; luz.Brightness = 0.8; luz.Parent = colunaCentral

        local function aoTocar(hit)
            local personagem = hit:FindFirstAncestorOfClass("Model")
            local jogador = personagem and Players:GetPlayerFromCharacter(personagem)
            if not jogador then return end
            local agora = os.clock()
            if ultimoToque[jogador.UserId] and agora - ultimoToque[jogador.UserId] < 0.8 then return end
            ultimoToque[jogador.UserId] = agora
            registrarVoto(jogador, nomeMapa)
        end
        plataforma.Touched:Connect(aoTocar)
        topo.Touched:Connect(aoTocar)
    end
end

criarPlataformasVotacao()

local function votarMapa()
    -- Aguarda os clientes conectarem a interface antes de abrir a votação.
    local limiteEspera = os.clock() + 8
    while os.clock() < limiteEspera do
        local todosProntos = true
        for _, jogador in ipairs(Players:GetPlayers()) do
            if not clientesProntos[jogador.UserId] then
                todosProntos = false
                break
            end
        end
        if todosProntos then break end
        task.wait(0.25)
    end

    votos = {}
    opcoes = obterTodosOsMapas()

    if #opcoes == 0 then
        anunciar("ERRO: não existem mapas dentro de ServerStorage > Mapas.")
        return nil
    end

    votacaoAberta = true
    for _, plataforma in ipairs(plataformasVotacao:GetChildren()) do
        atualizarPainelPlataforma(plataforma, 0)
    end
    roundEvent:FireAllClients("Votacao", opcoes, TEMPO_VOTACAO)
    print("[VOTACAO] Opcoes: " .. table.concat(opcoes, ", "))

    for segundos = TEMPO_VOTACAO, 1, -1 do
        roundEvent:FireAllClients("CronometroVoto", segundos)
        task.wait(1)
    end

    votacaoAberta = false
    local contagem = contarVotos()
    local maiorNumero = -1
    local empatados = {}

    for _, nome in ipairs(opcoes) do
        local quantidade = contagem[nome] or 0
        if quantidade > maiorNumero then
            maiorNumero = quantidade
            empatados = {nome}
        elseif quantidade == maiorNumero then
            table.insert(empatados, nome)
        end
    end

    -- Sem votos, escolhe aleatoriamente entre TODOS os mapas disponíveis.
    local vencedor
    if maiorNumero <= 0 then
        vencedor = opcoes[Random.new():NextInteger(1, #opcoes)]
    else
        vencedor = empatados[Random.new():NextInteger(1, #empatados)]
    end

    roundEvent:FireAllClients("FimVotacao", vencedor, contagem)
    print("[VOTACAO] Mapa vencedor: " .. vencedor)
    return vencedor
end

local function carregarMapa(nome)
    limparMapa()
    local modelo = mapasFolder:FindFirstChild(nome)
    if not modelo then
        warn("Mapa não encontrado: " .. tostring(nome))
        return false
    end

    mapaAtual = modelo:Clone()
    mapaAtual.Name = nome
    mapaAtual.Parent = mapasAtivos

    local estilos = {
        Cidade = {
            Chao = {Enum.Material.Grass, Color3.fromRGB(75, 145, 75)},
            Predio_A = {Enum.Material.Concrete, Color3.fromRGB(125, 135, 145)},
            Predio_B = {Enum.Material.Concrete, Color3.fromRGB(85, 95, 110)},
            Casa = {Enum.Material.Brick, Color3.fromRGB(205, 160, 95)},
            Abrigo = {Enum.Material.Metal, Color3.fromRGB(65, 115, 175)},
        },
        Ilha_Tropical = {
            Areia = {Enum.Material.Sand, Color3.fromRGB(235, 215, 145)},
            Rocha_A = {Enum.Material.Rock, Color3.fromRGB(85, 90, 85)},
            Rocha_B = {Enum.Material.Rock, Color3.fromRGB(105, 100, 85)},
            Cabana = {Enum.Material.WoodPlanks, Color3.fromRGB(135, 85, 45)},
            Palco = {Enum.Material.Grass, Color3.fromRGB(65, 155, 75)},
        },
        Montanhas = {
            Plataforma = {Enum.Material.Slate, Color3.fromRGB(115, 120, 125)},
            Montanha_A = {Enum.Material.Rock, Color3.fromRGB(75, 80, 90)},
            Montanha_B = {Enum.Material.Rock, Color3.fromRGB(100, 105, 115)},
            Abrigo = {Enum.Material.Metal, Color3.fromRGB(145, 65, 55)},
            Ponte = {Enum.Material.WoodPlanks, Color3.fromRGB(115, 75, 45)},
        },
        Deserto = {
            Areia = {Enum.Material.Sand, Color3.fromRGB(225, 190, 120)},
            Templo = {Enum.Material.Sandstone, Color3.fromRGB(205, 165, 100)},
            Ruina_A = {Enum.Material.Sandstone, Color3.fromRGB(165, 125, 75)},
            Ruina_B = {Enum.Material.Sandstone, Color3.fromRGB(185, 140, 85)},
            Oasis = {Enum.Material.Water, Color3.fromRGB(45, 155, 205)},
        },
        Vila_Costeira = {
            Areia = {Enum.Material.Sand, Color3.fromRGB(226, 211, 166)},
            CasaPraia = {Enum.Material.WoodPlanks, Color3.fromRGB(205, 166, 119)},
            Mercado = {Enum.Material.Concrete, Color3.fromRGB(220, 218, 203)},
            Farol = {Enum.Material.Brick, Color3.fromRGB(232, 230, 218)},
            AbrigoCosteiro = {Enum.Material.Metal, Color3.fromRGB(75, 118, 145)},
        },
    }
    -- Amplia a área jogável sem exigir que o usuário edite cada mapa manualmente.
    for _, parte in ipairs(mapaAtual:GetDescendants()) do
        if parte:IsA("BasePart") then
            if parte.Name == "Chao" or parte.Name == "Areia" or parte.Name == "Plataforma" then
                parte.Size = Vector3.new(420, parte.Size.Y, 420)
            else
                parte.Position = Vector3.new(parte.Position.X * 1.55, parte.Position.Y, parte.Position.Z * 1.55)
                parte.Size = Vector3.new(parte.Size.X * 1.32, parte.Size.Y, parte.Size.Z * 1.32)
            end
        end
    end

    local estiloMapa = estilos[nome]
    if estiloMapa then
        for _, parte in ipairs(mapaAtual:GetDescendants()) do
            if parte:IsA("BasePart") and estiloMapa[parte.Name] then
                parte.Material = estiloMapa[parte.Name][1]
                parte.Color = estiloMapa[parte.Name][2]
            end
        end
    end

    -- Cenário procedural: detalhes extras leves para deixar os mapas mais vivos.
    local detalhes = Instance.new("Folder")
    detalhes.Name = "DetalhesCenario"
    detalhes.Parent = mapaAtual
    local function bloco(nomeParte, tamanhoParte, posicao, cor, material, forma)
        local p = Instance.new("Part")
        p.Name = nomeParte
        p.Anchored = true
        local nomeMinusculo = string.lower(nomeParte)
        local ehConstrucao = string.find(nomeMinusculo, "casa", 1, true)
            or string.find(nomeMinusculo, "predio", 1, true)
            or string.find(nomeMinusculo, "hotel", 1, true)
            or string.find(nomeMinusculo, "pousada", 1, true)
            or string.find(nomeMinusculo, "mercado", 1, true)
            or string.find(nomeMinusculo, "templo", 1, true)
            or string.find(nomeMinusculo, "cabana", 1, true)
            or string.find(nomeMinusculo, "posto", 1, true)
            or string.find(nomeMinusculo, "abrigo", 1, true)
            or string.find(nomeMinusculo, "farol", 1, true)
        local escalaConstrucao = ehConstrucao and 1.16 or 1
        p.Size = tamanhoParte * escalaConstrucao
        p.Position = Vector3.new(posicao.X * 1.30, posicao.Y + (tamanhoParte.Y * (escalaConstrucao - 1) / 2), posicao.Z * 1.30)
        p.Color = cor
        p.Material = material or Enum.Material.SmoothPlastic
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p.CanCollide = true
        if forma then p.Shape = forma end
        p.Parent = detalhes
        return p
    end

    -- Converte peças decorativas em construções realmente exploráveis.
    local function criarInterior(nomePeca)
        local original = mapaAtual:FindFirstChild(nomePeca, true)
        if not original or not original:IsA("BasePart") then return end
        local centro = original.Position
        local largura = math.max(24, original.Size.X * 1.18)
        local profundidade = math.max(22, original.Size.Z * 1.18)
        local altura = math.clamp(original.Size.Y * 0.88, 14, 30)
        local espessura = 1.2
        local pisoY = original.Position.Y - original.Size.Y / 2 + 1.05
        local paredeY = pisoY + altura / 2
        local frenteZ = centro.Z + profundidade / 2
        local paredeCor = original.Color:Lerp(Color3.fromRGB(235, 225, 205), 0.48)
        local pisoCor = Color3.fromRGB(105, 100, 92)
        local interior = Instance.new("Model")
        interior.Name = "Interior_" .. nomePeca
        interior.Parent = detalhes

        local function parteInterior(nome, tamanho, posicao, cor, material, colide)
            local p = Instance.new("Part")
            p.Name = nome
            p.Anchored = true
            p.Size = tamanho
            p.Position = posicao
            p.Color = cor
            p.Material = material or Enum.Material.SmoothPlastic
            p.TopSurface = Enum.SurfaceType.Smooth
            p.BottomSurface = Enum.SurfaceType.Smooth
            p.CanCollide = colide ~= false
            p.Parent = interior
            return p
        end

        parteInterior("PisoInterno", Vector3.new(largura, 1, profundidade), Vector3.new(centro.X, pisoY, centro.Z), pisoCor, Enum.Material.WoodPlanks)
        parteInterior("ParedeFundo", Vector3.new(largura, altura, espessura), Vector3.new(centro.X, paredeY, centro.Z - profundidade/2), paredeCor, Enum.Material.Concrete)
        parteInterior("ParedeEsquerda", Vector3.new(espessura, altura, profundidade), Vector3.new(centro.X - largura/2, paredeY, centro.Z), paredeCor, Enum.Material.Concrete)
        parteInterior("ParedeDireita", Vector3.new(espessura, altura, profundidade), Vector3.new(centro.X + largura/2, paredeY, centro.Z), paredeCor, Enum.Material.Concrete)
        local vao = math.min(6, largura * 0.32)
        local lado = (largura - vao) / 2
        parteInterior("ParedeFrontalEsquerda", Vector3.new(lado, altura, espessura), Vector3.new(centro.X - (vao+lado)/2, paredeY, frenteZ), paredeCor, Enum.Material.Concrete)
        parteInterior("ParedeFrontalDireita", Vector3.new(lado, altura, espessura), Vector3.new(centro.X + (vao+lado)/2, paredeY, frenteZ), paredeCor, Enum.Material.Concrete)
        parteInterior("VigaDaEntrada", Vector3.new(vao, 2, espessura), Vector3.new(centro.X, pisoY + altura - 1, frenteZ), paredeCor, Enum.Material.Concrete)
        parteInterior("Teto", Vector3.new(largura, 1, profundidade), Vector3.new(centro.X, pisoY + altura + 0.5, centro.Z), original.Color, Enum.Material.Concrete)

        -- Porta com interação por toque/proximidade; abre espaço para entrar.
        local porta = parteInterior("PortaInterativa", Vector3.new(vao - 0.25, math.max(6, altura - 2), 0.7), Vector3.new(centro.X, pisoY + math.max(6, altura - 2)/2, frenteZ - 0.55), Color3.fromRGB(105, 68, 42), Enum.Material.WoodPlanks)
        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Abrir"
        prompt.ObjectText = "Porta"
        prompt.KeyboardKeyCode = Enum.KeyCode.E
        prompt.HoldDuration = 0
        prompt.MaxActivationDistance = 10
        prompt.RequiresLineOfSight = false
        prompt.Parent = porta
        local aberta = false
        local portaFechada = porta.CFrame
        prompt.Triggered:Connect(function()
            aberta = not aberta
            prompt.ActionText = aberta and "Fechar" or "Abrir"
            local destino = aberta and (portaFechada * CFrame.Angles(0, math.rad(90), 0)) or portaFechada
            TweenService:Create(porta, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = destino}):Play()
        end)

        -- Janelas simples com vidro translúcido nas paredes laterais.
        for _, ladoX in ipairs({-1, 1}) do
            local janela = parteInterior("JanelaInterna", Vector3.new(0.25, 3, 5), Vector3.new(centro.X + ladoX*(largura/2 - 0.25), pisoY + altura*0.64, centro.Z - profundidade*0.12), Color3.fromRGB(115, 190, 220), Enum.Material.Glass, false)
            janela.Transparency = 0.28
        end

        -- Móveis variam conforme o tipo de construção.
        local tampoY = pisoY + 2
        parteInterior("Mesa", Vector3.new(5, 0.6, 3), Vector3.new(centro.X, tampoY, centro.Z - 2), Color3.fromRGB(115, 75, 45), Enum.Material.WoodPlanks)
        for _, dx in ipairs({-1.8, 1.8}) do
            parteInterior("PernaMesa", Vector3.new(0.45, 2, 0.45), Vector3.new(centro.X+dx, pisoY+1, centro.Z-2), Color3.fromRGB(80, 55, 35), Enum.Material.Wood)
        end
        parteInterior("Banco", Vector3.new(6, 1.2, 1.5), Vector3.new(centro.X, pisoY+1.1, centro.Z+3), Color3.fromRGB(90, 115, 125), Enum.Material.Fabric)
        local luz = Instance.new("PointLight")
        luz.Color = Color3.fromRGB(255, 226, 170)
        luz.Brightness = 0.8
        luz.Range = 18
        luz.Parent = parteInterior("LuminariaInterna", Vector3.new(1, 0.3, 1), Vector3.new(centro.X, pisoY+altura-1.5, centro.Z), Color3.fromRGB(255, 230, 180), Enum.Material.Neon, false)

        -- Interior ampliado: sala mobiliada, banheiro e segundo andar com escada.
        parteInterior("SofaSala", Vector3.new(math.min(8, largura*0.42), 2.2, 2.4), Vector3.new(centro.X-largura*0.20, pisoY+1.5, centro.Z+profundidade*0.22), Color3.fromRGB(65, 105, 125), Enum.Material.Fabric)
        parteInterior("BalcaoCozinha", Vector3.new(math.min(7, largura*0.38), 2.1, 1.5), Vector3.new(centro.X+largura*0.22, pisoY+1.45, centro.Z+profundidade*0.20), Color3.fromRGB(125, 95, 68), Enum.Material.WoodPlanks)
        parteInterior("Televisao", Vector3.new(0.35, 2.4, 4.2), Vector3.new(centro.X-largura*0.20, pisoY+3.1, centro.Z-profundidade*0.25), Color3.fromRGB(22, 25, 30), Enum.Material.SmoothPlastic)

        -- Banheiro fechado em um canto, com vaso e pia reconhecíveis.
        local bx = centro.X + largura*0.27
        local bz = centro.Z - profundidade*0.27
        parteInterior("ParedeBanheiroA", Vector3.new(largura*0.34, math.min(altura*0.55,7), 0.7), Vector3.new(bx, pisoY+math.min(altura*0.28,3.5), bz+profundidade*0.16), paredeCor, Enum.Material.Concrete)
        parteInterior("ParedeBanheiroB", Vector3.new(0.7, math.min(altura*0.55,7), profundidade*0.32), Vector3.new(bx-largura*0.16, pisoY+math.min(altura*0.28,3.5), bz), paredeCor, Enum.Material.Concrete)
        parteInterior("VasoSanitario", Vector3.new(1.8, 1.5, 2.2), Vector3.new(bx+largura*0.04, pisoY+1.1, bz+profundidade*0.05), Color3.fromRGB(235,235,230), Enum.Material.SmoothPlastic)
        parteInterior("PiaBanheiro", Vector3.new(2.4, 2, 1.4), Vector3.new(bx-largura*0.07, pisoY+1.3, bz-profundidade*0.08), Color3.fromRGB(230,230,225), Enum.Material.SmoothPlastic)

        local temSegundoAndar = largura >= 16 and profundidade >= 15 and altura >= 10
        if temSegundoAndar then
            local nivel2 = pisoY + altura*0.52
            parteInterior("PisoSegundoAndar", Vector3.new(largura*0.88, 0.8, profundidade*0.54), Vector3.new(centro.X, nivel2, centro.Z-profundidade*0.22), pisoCor, Enum.Material.WoodPlanks)
            parteInterior("CamaSegundoAndar", Vector3.new(5.5, 1.2, 7), Vector3.new(centro.X-largura*0.18, nivel2+1, centro.Z-profundidade*0.23), Color3.fromRGB(225,220,205), Enum.Material.Fabric)
            parteInterior("ArmarioSegundoAndar", Vector3.new(2.2, 4.2, 4), Vector3.new(centro.X+largura*0.30, nivel2+2.4, centro.Z-profundidade*0.23), Color3.fromRGB(115,78,52), Enum.Material.WoodPlanks)
            for degrau=1,7 do
                parteInterior("DegrauEscada", Vector3.new(4.2,0.55,2.0), Vector3.new(centro.X+largura*0.28, pisoY+0.7+degrau*0.82, centro.Z+profundidade*0.28-degrau*2.0), Color3.fromRGB(115,82,55), Enum.Material.WoodPlanks)
            end
            parteInterior("GuardaCorpoSegundoAndar", Vector3.new(largura*0.86,1.1,0.35), Vector3.new(centro.X,nivel2+0.85,centro.Z+profundidade*0.04), Color3.fromRGB(105,78,55), Enum.Material.Wood)
        end

        local zona = Instance.new("Part")
        zona.Name = "ZonaSegura"
        zona.Anchored = true
        zona.CanCollide = false
        zona.CanTouch = false
        zona.CanQuery = false
        zona.Transparency = 1
        zona.Size = Vector3.new(largura-2, altura-2, profundidade-2)
        zona.CFrame = CFrame.new(centro.X, pisoY + altura/2, centro.Z)
        zona.Parent = interior
        table.insert(zonasSeguras, zona)
        original.Transparency = 1
        original.CanCollide = false
        original.CanTouch = false
    end

    -- Novas construcoes-base; cada uma recebe paredes, janelas, porta e interior abaixo.
    if nome == "Cidade" then
        bloco("CasaExtra_A", Vector3.new(20, 12, 18), Vector3.new(-48, 7, 72), Color3.fromRGB(190, 135, 95), Enum.Material.Brick)
        bloco("CasaExtra_B", Vector3.new(20, 12, 18), Vector3.new(48, 7, -72), Color3.fromRGB(205, 180, 130), Enum.Material.Brick)
        bloco("LojaExtra", Vector3.new(24, 15, 20), Vector3.new(0, 8.5, 82), Color3.fromRGB(95, 125, 155), Enum.Material.Concrete)
        bloco("CasaExtra_C", Vector3.new(22, 14, 20), Vector3.new(-82, 7.5, 8), Color3.fromRGB(180, 105, 85), Enum.Material.Brick)
        bloco("CasaExtra_D", Vector3.new(24, 15, 22), Vector3.new(82, 8, -8), Color3.fromRGB(205, 175, 130), Enum.Material.Brick)
        bloco("PredioResidencial_C", Vector3.new(30, 30, 28), Vector3.new(-88, 16, -78), Color3.fromRGB(105, 120, 138), Enum.Material.Concrete)
    elseif nome == "Ilha_Tropical" then
        bloco("CabanaExtra_A", Vector3.new(18, 11, 16), Vector3.new(-62, 6.5, 48), Color3.fromRGB(145, 95, 55), Enum.Material.WoodPlanks)
        bloco("CabanaExtra_B", Vector3.new(22, 14, 20), Vector3.new(62, 7.5, -48), Color3.fromRGB(155, 105, 65), Enum.Material.WoodPlanks)
        bloco("CasaPraiaExtra", Vector3.new(24, 15, 21), Vector3.new(-5, 8, 75), Color3.fromRGB(195, 145, 100), Enum.Material.WoodPlanks)
    elseif nome == "Montanhas" then
        bloco("CabanaMontanha_A", Vector3.new(20, 13, 18), Vector3.new(-72, 7.5, 42), Color3.fromRGB(105, 85, 75), Enum.Material.WoodPlanks)
        bloco("CabanaMontanha_B", Vector3.new(22, 14, 20), Vector3.new(68, 7.5, -52), Color3.fromRGB(115, 95, 82), Enum.Material.WoodPlanks)
        bloco("HotelMontanha", Vector3.new(30, 26, 28), Vector3.new(4, 14, 78), Color3.fromRGB(130, 140, 150), Enum.Material.Concrete)
    elseif nome == "Deserto" then
        bloco("PostoDeserto", Vector3.new(20, 12, 18), Vector3.new(-65, 7, 48), Color3.fromRGB(195, 155, 100), Enum.Material.Sandstone)
        bloco("CasaOasis", Vector3.new(22, 14, 20), Vector3.new(62, 7.5, -52), Color3.fromRGB(205, 175, 125), Enum.Material.Sandstone)
        bloco("PousadaDeserto", Vector3.new(28, 24, 26), Vector3.new(0, 13, 78), Color3.fromRGB(190, 150, 95), Enum.Material.Sandstone)
    elseif nome == "Vila_Costeira" then
        bloco("CasaPraia", Vector3.new(26, 17, 22), Vector3.new(-45, 9, 35), Color3.fromRGB(210, 175, 130), Enum.Material.WoodPlanks)
        bloco("Mercado", Vector3.new(30, 20, 26), Vector3.new(38, 10, 28), Color3.fromRGB(220, 218, 203), Enum.Material.Concrete)
        bloco("AbrigoCosteiro", Vector3.new(22, 15, 20), Vector3.new(-8, 8, -40), Color3.fromRGB(75, 118, 145), Enum.Material.Metal)
        bloco("Farol", Vector3.new(16, 36, 16), Vector3.new(92, 19, -75), Color3.fromRGB(232, 230, 218), Enum.Material.Brick)
    end

    -- Construções adicionais distribuídas pela arena para reduzir grandes áreas vazias.
    local construcoesExtras = {
        Cidade = {
            {"CasaBairro_A", Vector3.new(28,20,24), Vector3.new(-135,11,105), Color3.fromRGB(190,145,105), Enum.Material.Brick},
            {"CasaBairro_B", Vector3.new(30,22,26), Vector3.new(135,12,-105), Color3.fromRGB(205,175,125), Enum.Material.Brick},
            {"PredioBairro", Vector3.new(38,42,34), Vector3.new(0,22,135), Color3.fromRGB(105,120,140), Enum.Material.Concrete},
            {"MercadoBairro", Vector3.new(30,24,28), Vector3.new(-132,13,0), Color3.fromRGB(135,150,165), Enum.Material.Concrete},
            {"GaragemBairro", Vector3.new(28,18,26), Vector3.new(132,10,0), Color3.fromRGB(120,125,135), Enum.Material.Concrete},
        },
        Ilha_Tropical = {
            {"CasaIlha_A", Vector3.new(28,19,24), Vector3.new(-135,10,105), Color3.fromRGB(165,115,70), Enum.Material.WoodPlanks},
            {"CasaIlha_B", Vector3.new(30,21,25), Vector3.new(135,11,-105), Color3.fromRGB(190,145,95), Enum.Material.WoodPlanks},
            {"PousadaIlha", Vector3.new(36,30,32), Vector3.new(0,16,135), Color3.fromRGB(155,115,75), Enum.Material.WoodPlanks},
            {"QuiosqueIlha", Vector3.new(24,16,22), Vector3.new(-132,9,0), Color3.fromRGB(175,125,75), Enum.Material.WoodPlanks},
            {"CentroMergulho", Vector3.new(28,20,25), Vector3.new(132,11,0), Color3.fromRGB(145,175,180), Enum.Material.WoodPlanks},
        },
        Montanhas = {
            {"CabanaAlta_A", Vector3.new(28,20,24), Vector3.new(-135,10,105), Color3.fromRGB(115,95,82), Enum.Material.WoodPlanks},
            {"CabanaAlta_B", Vector3.new(30,22,25), Vector3.new(135,11,-105), Color3.fromRGB(125,105,92), Enum.Material.WoodPlanks},
            {"HotelAlto", Vector3.new(38,34,32), Vector3.new(0,18,135), Color3.fromRGB(125,140,155), Enum.Material.Concrete},
            {"EstacaoMontanha", Vector3.new(28,22,25), Vector3.new(-132,12,0), Color3.fromRGB(135,145,155), Enum.Material.Concrete},
            {"RefugioNeve", Vector3.new(30,24,27), Vector3.new(132,13,0), Color3.fromRGB(115,105,95), Enum.Material.WoodPlanks},
        },
        Deserto = {
            {"CasaDuna_A", Vector3.new(28,20,24), Vector3.new(-135,10,105), Color3.fromRGB(195,155,100), Enum.Material.Sandstone},
            {"CasaDuna_B", Vector3.new(30,22,25), Vector3.new(135,11,-105), Color3.fromRGB(205,170,115), Enum.Material.Sandstone},
            {"HotelOasis", Vector3.new(38,32,32), Vector3.new(0,17,135), Color3.fromRGB(185,145,95), Enum.Material.Sandstone},
            {"BazarDeserto", Vector3.new(30,22,26), Vector3.new(-132,12,0), Color3.fromRGB(195,155,100), Enum.Material.Sandstone},
            {"OficinaDeserto", Vector3.new(28,20,25), Vector3.new(132,11,0), Color3.fromRGB(180,140,90), Enum.Material.Sandstone},
        },
        Vila_Costeira = {
            {"CasaCosteira_A", Vector3.new(28,20,24), Vector3.new(-135,10,105), Color3.fromRGB(205,170,130), Enum.Material.WoodPlanks},
            {"CasaCosteira_B", Vector3.new(30,22,25), Vector3.new(135,11,-105), Color3.fromRGB(220,190,150), Enum.Material.WoodPlanks},
            {"HotelCosteiro", Vector3.new(38,34,32), Vector3.new(0,18,135), Color3.fromRGB(215,215,205), Enum.Material.Concrete},
            {"RestauranteCosteiro", Vector3.new(32,24,28), Vector3.new(-132,13,0), Color3.fromRGB(225,205,165), Enum.Material.WoodPlanks},
            {"LojaPescador", Vector3.new(28,20,24), Vector3.new(132,11,0), Color3.fromRGB(115,145,160), Enum.Material.WoodPlanks},
        },
    }
    for _, dado in ipairs(construcoesExtras[nome] or {}) do
        bloco(dado[1], dado[2], dado[3], dado[4], dado[5])
    end

    local interioresPorMapa = {
        Cidade = {"Predio_A", "Predio_B", "Casa", "Abrigo", "CasaExtra_A", "CasaExtra_B", "LojaExtra", "CasaExtra_C", "CasaExtra_D", "PredioResidencial_C", "CasaBairro_A", "CasaBairro_B", "PredioBairro", "MercadoBairro", "GaragemBairro"},
        Ilha_Tropical = {"Cabana", "CabanaExtra_A", "CabanaExtra_B", "CasaPraiaExtra", "CasaIlha_A", "CasaIlha_B", "PousadaIlha", "QuiosqueIlha", "CentroMergulho"},
        Montanhas = {"Abrigo", "CabanaMontanha_A", "CabanaMontanha_B", "HotelMontanha", "CabanaAlta_A", "CabanaAlta_B", "HotelAlto", "EstacaoMontanha", "RefugioNeve"},
        Deserto = {"Templo", "Ruina_A", "Ruina_B", "PostoDeserto", "CasaOasis", "PousadaDeserto", "CasaDuna_A", "CasaDuna_B", "HotelOasis", "BazarDeserto", "OficinaDeserto"},
        Vila_Costeira = {"CasaPraia", "Mercado", "AbrigoCosteiro", "Farol", "CasaCosteira_A", "CasaCosteira_B", "HotelCosteiro", "RestauranteCosteiro", "LojaPescador"},
    }
    for _, nomePeca in ipairs(interioresPorMapa[nome] or {}) do
        criarInterior(nomePeca)
    end

    local function arvore(x, z, tropical)
        local tronco = bloco("Tronco", Vector3.new(2.2, tropical and 12 or 9, 2.2), Vector3.new(x, tropical and 6 or 4.5, z), Color3.fromRGB(105,70,42), Enum.Material.Wood)
        if tropical then
            for n=1,5 do
                local folha = bloco("FolhaPalmeira", Vector3.new(2,1,11), Vector3.new(x, 12 + math.sin(n)*1.2, z), Color3.fromRGB(40,135 + n*5,65), Enum.Material.Grass)
                folha.CFrame = CFrame.new(folha.Position) * CFrame.Angles(0, math.rad(n*72), math.rad((n%2==0) and 18 or -18))
            end
        else
            bloco("CopaPinheiro", Vector3.new(8,9,8), Vector3.new(x,10,z), Color3.fromRGB(35,95,65), Enum.Material.Grass, Enum.PartType.Ball)
            bloco("CopaPinheiroAlta", Vector3.new(5,7,5), Vector3.new(x,15,z), Color3.fromRGB(45,115,75), Enum.Material.Grass, Enum.PartType.Ball)
        end
    end
    if nome == "Cidade" then
        -- Ruas, calçadas, postes e fachadas com janelas.
        bloco("Avenida", Vector3.new(330,0.35,22), Vector3.new(0,1.2,0), Color3.fromRGB(48,52,58), Enum.Material.Asphalt, Enum.PartType.Block)
        for z=-145,145,12 do
            bloco("FaixaPedestre", Vector3.new(2,0.12,5), Vector3.new(0,1.45,z), Color3.fromRGB(235,235,225), Enum.Material.SmoothPlastic)
        end
        for x=-135,135,30 do
            bloco("Calcada", Vector3.new(10,1,220), Vector3.new(x,1.4,0), Color3.fromRGB(145,150,155), Enum.Material.Concrete)
            local poste=bloco("PosteDeLuz", Vector3.new(0.8,13,0.8), Vector3.new(x,7.5, -82), Color3.fromRGB(55,60,68), Enum.Material.Metal)
            bloco("Luminaria", Vector3.new(4,0.7,1.4), poste.Position+Vector3.new(1.5,6,0), Color3.fromRGB(255,230,150), Enum.Material.Neon)
        end
        local prediosExtras = {Vector3.new(-78,12,-55),Vector3.new(78,12,55),Vector3.new(-78,12,55),Vector3.new(78,12,-55)}
        for indice,v in ipairs(prediosExtras) do
            local predio = bloco("PredioExtra_" .. indice, Vector3.new(28,24,28), v, Color3.fromRGB(105,120,135), Enum.Material.Concrete)
            criarInterior(predio.Name)
            for andar=1,4 do
                for lado=-1,1,2 do
                    bloco("Janela", Vector3.new(0.3,2.6,3.8), v+Vector3.new(lado*14.2, -8+andar*5, 0), Color3.fromRGB(105,190,225), Enum.Material.Glass)
                end
            end
        end
    elseif nome == "Ilha_Tropical" then
        for _,v in ipairs({{-88,-78},{88,-78},{-88,78},{88,78},{-70,0},{70,0},{0,-88},{0,88}}) do arvore(v[1],v[2],true) end
        for i=1,12 do
            local x=math.random(-98,98); local z=math.random(-98,98)
            bloco("PedraPraia", Vector3.new(math.random(4,9),math.random(3,7),math.random(4,9)), Vector3.new(x,2,z), Color3.fromRGB(115,112,98), Enum.Material.Rock, Enum.PartType.Ball)
        end
        bloco("Pier", Vector3.new(10,1.2,42), Vector3.new(0,2,-80), Color3.fromRGB(120,80,48), Enum.Material.WoodPlanks)
        for x=-4,4,8 do bloco("PilarPier", Vector3.new(1,5,1), Vector3.new(x,0,-95), Color3.fromRGB(95,65,42), Enum.Material.Wood) end
    elseif nome == "Montanhas" then
        for _,v in ipairs({{-92,-82},{92,-82},{-92,82},{92,82},{-65,0},{65,0},{0,-95},{0,95}}) do arvore(v[1],v[2],false) end
        for i=1,16 do
            local x=math.random(-100,100); local z=math.random(-100,100)
            bloco("RochaNeve", Vector3.new(math.random(5,12),math.random(4,10),math.random(5,12)), Vector3.new(x,3,z), Color3.fromRGB(105,112,122), Enum.Material.Rock, Enum.PartType.Ball)
        end
        bloco("PlataformaNeve", Vector3.new(28,2,18), Vector3.new(72,4,0), Color3.fromRGB(225,235,245), Enum.Material.Snow)
    elseif nome == "Vila_Costeira" then
        for _,v in ipairs({{-115,-95},{115,-95},{-115,95},{115,95},{-130,0},{130,0}}) do
            arvore(v[1],v[2],true)
        end
        bloco("MarCosteiro", Vector3.new(420,0.4,72), Vector3.new(0,0.9,-150), Color3.fromRGB(35,145,190), Enum.Material.Water)
        bloco("AreiaMolhada", Vector3.new(420,0.3,24), Vector3.new(0,1.0,-105), Color3.fromRGB(194,178,135), Enum.Material.Sand)
        bloco("PierCosteiro", Vector3.new(14,1.4,58), Vector3.new(0,2,-105), Color3.fromRGB(120,82,50), Enum.Material.WoodPlanks)
        for i=1,8 do
            bloco("PostePier", Vector3.new(1.2,5,1.2), Vector3.new(-6+(i%2)*12,3,-80-i*5), Color3.fromRGB(90,65,45), Enum.Material.Wood)
        end
        for i=1,14 do
            local x=math.random(-155,155); local z=math.random(-75,75)
            bloco("RochaPraia", Vector3.new(math.random(3,8),math.random(2,5),math.random(3,8)), Vector3.new(x,2,z), Color3.fromRGB(125,125,115), Enum.Material.Rock, Enum.PartType.Ball)
        end
    elseif nome == "Deserto" then
        for i=1,15 do
            local x=math.random(-100,100); local z=math.random(-100,100)
            bloco("Duna", Vector3.new(math.random(12,24),math.random(3,7),math.random(10,22)), Vector3.new(x,1,z), Color3.fromRGB(205,165,100), Enum.Material.Sand, Enum.PartType.Ball)
        end
        for _,v in ipairs({{-82,-72},{82,-72},{-82,72},{82,72},{-55,0},{55,0}}) do
            bloco("CactoTronco", Vector3.new(2,10,2), Vector3.new(v[1],6,v[2]), Color3.fromRGB(45,125,65), Enum.Material.Grass)
            bloco("CactoBraco", Vector3.new(6,2,2), Vector3.new(v[1]+3,7,v[2]), Color3.fromRGB(45,125,65), Enum.Material.Grass)
        end
        for i=1,8 do
            local x=math.random(-90,90); local z=math.random(-90,90)
            bloco("OssoPedra", Vector3.new(5,1,2), Vector3.new(x,2,z), Color3.fromRGB(195,180,145), Enum.Material.Sandstone)
        end
    end

    -- Cavernas exploraveis: corredor com entrada aberta, salao interno, luzes e zona protegida.
    local function criarCaverna(nomeCaverna, centro, largura, profundidade, altura, corRocha)
        local caverna = Instance.new("Model")
        caverna.Name = nomeCaverna
        caverna.Parent = detalhes
        local function pecaCaverna(nome, tamanho, pos, material, cor, colide)
            local p = Instance.new("Part")
            p.Name = nome
            p.Anchored = true
            p.Size = tamanho
            p.Position = pos
            p.Material = material or Enum.Material.Rock
            p.Color = cor or corRocha
            p.TopSurface = Enum.SurfaceType.Smooth
            p.BottomSurface = Enum.SurfaceType.Smooth
            p.CanCollide = colide ~= false
            p.Parent = caverna
            return p
        end
        local chaoY = 1.7
        pecaCaverna("PisoCaverna", Vector3.new(largura, 1, profundidade), centro + Vector3.new(0, chaoY, 0), Enum.Material.Slate, Color3.fromRGB(75, 76, 78))
        pecaCaverna("ParedeCavernaEsquerda", Vector3.new(2.5, altura, profundidade), centro + Vector3.new(-largura/2, chaoY + altura/2, 0))
        pecaCaverna("ParedeCavernaDireita", Vector3.new(2.5, altura, profundidade), centro + Vector3.new(largura/2, chaoY + altura/2, 0))
        pecaCaverna("TetoCaverna", Vector3.new(largura, 2.5, profundidade), centro + Vector3.new(0, chaoY + altura, 0))
        pecaCaverna("FundoCaverna", Vector3.new(largura, altura, 2.5), centro + Vector3.new(0, chaoY + altura/2, profundidade/2))
        -- Moldura rochosa ao redor da boca; o centro permanece livre para atravessar.
        pecaCaverna("BordaEntradaEsquerda", Vector3.new(3, altura, 3), centro + Vector3.new(-largura/2 + 1.5, chaoY + altura/2, -profundidade/2))
        pecaCaverna("BordaEntradaDireita", Vector3.new(3, altura, 3), centro + Vector3.new(largura/2 - 1.5, chaoY + altura/2, -profundidade/2))
        pecaCaverna("BordaEntradaSuperior", Vector3.new(largura, 3, 3), centro + Vector3.new(0, chaoY + altura - 1.5, -profundidade/2))
        for i=1,4 do
            local lamp = pecaCaverna("CristalLuminoso", Vector3.new(1.1, 2.2, 1.1), centro + Vector3.new((i%2==0 and 1 or -1)*(largura/2-4), chaoY+3, -profundidade/2 + i*(profundidade/5)), Enum.Material.Neon, nomeCaverna == "CavernaDeserto" and Color3.fromRGB(65, 190, 160) or Color3.fromRGB(105, 185, 255), false)
            local luz = Instance.new("PointLight")
            luz.Color = lamp.Color
            luz.Brightness = 1.1
            luz.Range = 22
            luz.Parent = lamp
        end
        local zona = Instance.new("Part")
        zona.Name = "ZonaSeguraCaverna"
        zona.Anchored = true
        zona.CanCollide = false
        zona.CanTouch = false
        zona.CanQuery = false
        zona.Transparency = 1
        zona.Size = Vector3.new(largura-4, altura-3, profundidade-5)
        zona.Position = centro + Vector3.new(0, chaoY + altura/2, 1)
        zona.Parent = caverna
        table.insert(zonasSeguras, zona)
        pecaCaverna("RochaInteriorA", Vector3.new(5, 2, 4), centro + Vector3.new(-5, chaoY+1.5, 7), Enum.Material.Rock, corRocha)
        pecaCaverna("RochaInteriorB", Vector3.new(4, 1.5, 3), centro + Vector3.new(6, chaoY+1.2, 13), Enum.Material.Rock, corRocha)
    end

    if nome == "Montanhas" then
        criarCaverna("CavernaMontanha", Vector3.new(-105, 0, 2), 30, 52, 17, Color3.fromRGB(80, 88, 98))
        criarCaverna("CavernaGelo", Vector3.new(105, 0, 28), 26, 44, 16, Color3.fromRGB(125, 145, 160))
    elseif nome == "Deserto" then
        criarCaverna("CavernaDeserto", Vector3.new(105, 0, 4), 30, 52, 17, Color3.fromRGB(145, 112, 75))
        criarCaverna("CavernaRuinas", Vector3.new(-105, 0, -28), 26, 44, 16, Color3.fromRGB(160, 130, 92))
    end

    -- Atmosfera muda conforme o mapa; os efeitos são restaurados na próxima rodada.
    if nome == "Cidade" then
        Lighting.ClockTime=17.5; Lighting.Brightness=2; Lighting.OutdoorAmbient=Color3.fromRGB(135,145,165)
    elseif nome == "Ilha_Tropical" then
        Lighting.ClockTime=13.5; Lighting.Brightness=2.5; Lighting.OutdoorAmbient=Color3.fromRGB(155,180,190)
    elseif nome == "Montanhas" then
        Lighting.ClockTime=10; Lighting.Brightness=1.8; Lighting.OutdoorAmbient=Color3.fromRGB(145,160,180)
    else
        Lighting.ClockTime=16; Lighting.Brightness=2.2; Lighting.OutdoorAmbient=Color3.fromRGB(185,155,120)
    end

    -- Invisible collision walls prevent players from walking beyond the playable map.
    local caixa, tamanho = mapaAtual:GetBoundingBox()
    local centro = caixa.Position
    local alturaParede = math.max(80, tamanho.Y + 50)
    local margem = 4
    local limites = Instance.new("Folder")
    limites.Name = "LimitesDaArea"
    limites.Parent = mapaAtual
    local function parede(nomeParede, tamanhoParede, posicao)
        local p = Instance.new("Part")
        p.Name = nomeParede
        p.Anchored = true
        p.CanCollide = true
        p.CanTouch = false
        p.CanQuery = false
        p.Transparency = 1
        p.Size = tamanhoParede
        p.Position = posicao
        p.Parent = limites
    end
    parede("Limite_Norte", Vector3.new(tamanho.X + margem * 2, alturaParede, 2), centro + Vector3.new(0, 0, -tamanho.Z / 2 - margem))
    parede("Limite_Sul", Vector3.new(tamanho.X + margem * 2, alturaParede, 2), centro + Vector3.new(0, 0, tamanho.Z / 2 + margem))
    parede("Limite_Leste", Vector3.new(2, alturaParede, tamanho.Z + margem * 2), centro + Vector3.new(tamanho.X / 2 + margem, 0, 0))
    parede("Limite_Oeste", Vector3.new(2, alturaParede, tamanho.Z + margem * 2), centro + Vector3.new(-tamanho.X / 2 - margem, 0, 0))
    return true
end

local function teleportarJogadores()
    if not mapaAtual then return end

    local base
    for _, objeto in ipairs(mapaAtual:GetDescendants()) do
        if objeto:IsA("BasePart") and
            (objeto.Name == "Chao" or objeto.Name == "Areia" or objeto.Name == "Plataforma") then
            base = objeto
            break
        end
    end

    if not base then
        base = mapaAtual:FindFirstChildWhichIsA("BasePart", true)
    end
    if not base then
        warn("O mapa não tem nenhuma peça para servir de ponto de chegada.")
        return
    end

    local lista = Players:GetPlayers()
    for indice, jogador in ipairs(lista) do
        local personagem = jogador.Character
        local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart")
        if raiz and not jogador:GetAttribute("NoLobby") then
            local angulo = (indice / math.max(#lista, 1)) * math.pi * 2
            raiz.CFrame = CFrame.new(base.Position + Vector3.new(math.cos(angulo)*24, 9, math.sin(angulo)*24))
        end
    end
end

local function criarEfeito(posicao, cor, tamanho, tempo)
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Material = Enum.Material.Neon
    p.Color = cor
    p.Size = tamanho
    p.Anchored = true
    p.CanCollide = false
    p.Position = posicao
    p.Parent = efeitosDesastre or workspace
    Debris:AddItem(p, tempo or 2)
    return p
end

local function estaEmAbrigo(personagem)
    local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart")
    if not raiz then return false end
    for _, zona in ipairs(zonasSeguras) do
        if zona and zona.Parent then
            local localPos = zona.CFrame:PointToObjectSpace(raiz.Position)
            local metade = zona.Size / 2
            if math.abs(localPos.X) <= metade.X and math.abs(localPos.Y) <= metade.Y and math.abs(localPos.Z) <= metade.Z then
                return true
            end
        end
    end
    return false
end

local function danoPerto(posicao, raio, dano)
    for _, jogador in ipairs(Players:GetPlayers()) do
        local personagem = jogador.Character
        local raiz = personagem and personagem:FindFirstChild("HumanoidRootPart")
        local humanoide = personagem and personagem:FindFirstChildOfClass("Humanoid")
        if raiz and humanoide and (raiz.Position - posicao).Magnitude <= raio and not estaEmAbrigo(personagem) then
            humanoide:TakeDamage(dano)
        end
    end
end

-- Desancora apenas pecas do mapa proximas do impacto; piso/base/spawns ficam protegidos.
local function desancorarObjetos(posicao, raio, quantidadeMaxima, impulso)
    if not mapaAtual then return 0 end
    local protegidos = {Chao=true, Areia=true, Plataforma=true, Baseplate=true, SpawnLocation=true,
        PisoInterno=true, PisoCaverna=true, ZonaSegura=true, ZonaSeguraCaverna=true}
    local candidatos = {}
    for _, parte in ipairs(mapaAtual:GetDescendants()) do
        if parte:IsA("BasePart") and parte.Anchored and not parte:IsA("SpawnLocation") then
            local nome = parte.Name
            local bloqueada = protegidos[nome] or string.find(string.lower(nome), "baseplate", 1, true)
                or string.find(string.lower(nome), "spawnlocation", 1, true)
                or string.find(string.lower(nome), "zonasegura", 1, true)
                or string.find(string.lower(nome), "piso", 1, true)
            if not bloqueada and parte.Transparency < 0.95 and (parte.Position - posicao).Magnitude <= raio then
                table.insert(candidatos, parte)
            end
        end
    end
    -- Primeiro solta as pecas mais proximas do impacto.
    table.sort(candidatos, function(a,b)
        return (a.Position-posicao).Magnitude < (b.Position-posicao).Magnitude
    end)
    local total = 0
    for _, parte in ipairs(candidatos) do
        if total >= (quantidadeMaxima or 4) then break end
        if parte and parte.Parent and parte.Anchored then
            parte.Anchored = false
            -- Network ownership and impulse are best-effort: some assemblies may reject ownership changes.
            pcall(function() parte:SetNetworkOwner(nil) end)
            local direcao = parte.Position - posicao
            if direcao.Magnitude < 0.1 then direcao = Vector3.new(0,1,0) end
            local massa = math.max(1, parte.AssemblyMass)
            pcall(function()
                parte:ApplyImpulse((direcao.Unit * (impulso or 38) + Vector3.new(0, impulso or 38, 0)) * massa)
            end)
            total += 1
        end
    end
    return total
end

local function centroMapa()
    if not mapaAtual then return Vector3.new(0, 5, 0) end
    local p = mapaAtual:FindFirstChildWhichIsA("BasePart", true)
    return p and p.Position or Vector3.new(0, 5, 0)
end

local function tornadoPuxarObjetos(centro, raio, limite)
    if not mapaAtual then return end
    local protegidos = {Chao=true, Areia=true, Plataforma=true, Baseplate=true, SpawnLocation=true,
        PisoInterno=true, PisoCaverna=true, ZonaSegura=true, ZonaSeguraCaverna=true}
    local candidatos = {}
    for _, parte in ipairs(mapaAtual:GetDescendants()) do
        if parte:IsA("BasePart") and parte.Parent and not parte:IsA("SpawnLocation") then
            local nome = parte.Name
            local bloqueada = protegidos[nome] or string.find(string.lower(nome), "baseplate", 1, true)
                or string.find(string.lower(nome), "spawnlocation", 1, true)
                or string.find(string.lower(nome), "zonasegura", 1, true)
                or string.find(string.lower(nome), "piso", 1, true)
            local distancia = (parte.Position - centro).Magnitude
            if not bloqueada and parte.Transparency < 0.95 and distancia <= raio then
                table.insert(candidatos, parte)
            end
        end
    end
    table.sort(candidatos, function(a,b)
        return (a.Position-centro).Magnitude < (b.Position-centro).Magnitude
    end)
    local usados = 0
    for _, parte in ipairs(candidatos) do
        if usados >= limite then break end
        if parte and parte.Parent then
            if parte.Anchored then parte.Anchored = false end
            local delta = parte.Position - centro
            local horizontal = Vector3.new(delta.X, 0, delta.Z)
            if horizontal.Magnitude < 1 then horizontal = Vector3.new(1,0,0) end
            local tangente = Vector3.new(-horizontal.Z, 0, horizontal.X).Unit
            local radial = -horizontal.Unit
            parte.AssemblyLinearVelocity = tangente * 78 + radial * 24 + Vector3.new(0, 42, 0)
            parte.AssemblyAngularVelocity = Vector3.new(8, 16, 8)
            usados += 1
        end
    end
end

local function pontoDeImpactoAleatorio(alturaPreferida)
    if not mapaAtual then return Vector3.new(0, 2, 0) end
    local caixa, tamanho = mapaAtual:GetBoundingBox()
    local metadeX = math.max(30, tamanho.X * 0.42)
    local metadeZ = math.max(30, tamanho.Z * 0.42)
    local x = caixa.Position.X + math.random(-math.floor(metadeX), math.floor(metadeX))
    local z = caixa.Position.Z + math.random(-math.floor(metadeZ), math.floor(metadeZ))
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {mapaAtual}
    local origem = Vector3.new(x, caixa.Position.Y + tamanho.Y + 260, z)
    local resultado = workspace:Raycast(origem, Vector3.new(0, -650, 0), params)
    if resultado then return resultado.Position + Vector3.new(0, 2, 0), resultado.Instance end
    return Vector3.new(x, 2, z), nil
end

local function meteoros(duracao)
    tocarSomGlobal(AUDIOS.Vento, 0.18, true)
    local fim = os.clock() + duracao
    while os.clock() < fim do
        local centro=centroMapa()
        local x,z=math.random(-170,170),math.random(-170,170)
        local alvo=centro+Vector3.new(x,1,z)
        local aviso=Instance.new("Part")
        aviso.Name="AvisoImpactoMeteoro"; aviso.Shape=Enum.PartType.Cylinder
        aviso.Size=Vector3.new(0.18,19,19); aviso.CFrame=CFrame.new(alvo+Vector3.new(0,0.2,0))*CFrame.Angles(0,0,math.rad(90))
        aviso.Anchored=true; aviso.CanCollide=false; aviso.Material=Enum.Material.Neon
        aviso.Color=Color3.fromRGB(255,95,30); aviso.Transparency=0.25; aviso.Parent=efeitosDesastre
        Debris:AddItem(aviso,1.5)
        task.wait(0.65)
        local m=Instance.new("Part")
        m.Name="Meteoro"; m.Shape=Enum.PartType.Ball; m.Size=Vector3.new(13,13,13)
        m.Material=Enum.Material.Neon; m.Color=Color3.fromRGB(255,105,25)
        m.Anchored=false; m.Position=alvo+Vector3.new(0,72,0); m.Parent=efeitosDesastre
        local fogo=Instance.new("Fire"); fogo.Size=10; fogo.Heat=14; fogo.Parent=m
        local fumaca=Instance.new("Smoke"); fumaca.Size=8; fumaca.Opacity=0.35; fumaca.RiseVelocity=18; fumaca.Parent=m
        local luz=Instance.new("PointLight"); luz.Color=m.Color; luz.Range=22; luz.Brightness=2.5; luz.Parent=m
        m.AssemblyLinearVelocity=Vector3.new(math.random(-8,8),-175,math.random(-8,8))
        local atingiu=false
        m.Touched:Connect(function()
            if atingiu then return end; atingiu=true
            local impacto=m.Position
            danoPerto(impacto,30,100)
            desancorarObjetos(impacto, 52, 22, 118)
            local explosao = Instance.new("Explosion")
            explosao.Position = impacto
            explosao.BlastRadius = 36
            explosao.BlastPressure = 620000
            explosao.DestroyJointRadiusPercent = 0.9
            explosao.Parent = workspace
            Debris:AddItem(explosao, 2)
            local onda=criarEfeito(impacto,Color3.fromRGB(255,145,45),Vector3.new(3,3,3),0.65)
            TweenService:Create(onda,TweenInfo.new(0.55),{Size=Vector3.new(72,4,72),Transparency=1}):Play()
            tocarSomGlobal(AUDIOS.Impacto,0.35,false)
            m:Destroy()
        end)
        Debris:AddItem(m,5)
        task.wait(0.55)
    end
    pararSomAmbiente()
end

local function tornado(duracao)
    tocarSomGlobal(AUDIOS.Vento,0.45,true)
    local visual=Instance.new("Model"); visual.Name="TornadoVisual"; visual.Parent=efeitosDesastre
    local partes={}
    for i=1,11 do
        local anel=Instance.new("Part"); anel.Name="FunilDeVento"; anel.Shape=Enum.PartType.Cylinder
        anel.Size=Vector3.new(4,14+i*2.2,14+i*2.2); anel.Anchored=true; anel.CanCollide=false
        anel.Material=Enum.Material.Neon; anel.Transparency=0.025+i*0.018
        anel.Color=(i%2==0) and Color3.fromRGB(205,220,235) or Color3.fromRGB(155,175,195)
        anel.Parent=visual; table.insert(partes,anel)
    end
    local poeira = Instance.new("Smoke")
    poeira.Name = "PoeiraDoTornado"
    poeira.Color = Color3.fromRGB(145, 150, 155)
    poeira.Opacity = 0.58
    poeira.Size = 34
    poeira.RiseVelocity = 24
    poeira.Parent = partes[1]
    local fim=os.clock()+duracao
    local proximaDesancoragem = os.clock() + 0.8
    while os.clock()<fim do
        local t=os.clock(); local centro=centroMapa()+Vector3.new(math.sin(t*0.35)*78,0,math.cos(t*0.28)*78)
        for i,anel in ipairs(partes) do
            local y=(i-1)*5.2+5; local raio=31-(i-1)*2.35
            anel.CFrame=CFrame.new(centro+Vector3.new(math.cos(t*2.4+i)*4,y,math.sin(t*2.4+i)*4))*CFrame.Angles(0,t*2.5+i,math.rad(90))
            anel.Size=Vector3.new(4,raio*2,raio*2)
        end
        if os.clock() >= proximaDesancoragem then
            desancorarObjetos(centro, 66, 8, 78)
            tornadoPuxarObjetos(centro, 72, 12)
            proximaDesancoragem = os.clock() + 0.8
        end
        for _,jogador in ipairs(Players:GetPlayers()) do
            local char=jogador.Character; local raiz=char and char:FindFirstChild("HumanoidRootPart")
            if raiz and (raiz.Position-centro).Magnitude<34 and not estaEmAbrigo(char) then
                local d=raiz.Position-centro
                local horizontal=Vector3.new(d.X,0,d.Z)
                if horizontal.Magnitude < 1 then horizontal=Vector3.new(1,0,0) end
                local tangente=Vector3.new(-horizontal.Z,0,horizontal.X).Unit
                local radial=-horizontal.Unit
                raiz.AssemblyLinearVelocity=tangente*62+radial*18+Vector3.new(0,26,0)
            end
        end
        task.wait(0.12)
    end
    visual:Destroy(); pararSomAmbiente()
end

local function terremoto(duracao)
    tocarSomGlobal(AUDIOS.Impacto, 0.20, true)
    local fim = os.clock() + duracao
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    local proximoAviso = 0
    while os.clock() < fim do
        if os.clock() >= proximoAviso then
            anunciar("ATENÇÃO: terremoto! Procure abrigo ou uma área aberta!")
            proximoAviso = os.clock() + 12
        end
        roundEvent:FireAllClients("Tremor", 2.8)
        local caixa, tamanho = mapaAtual:GetBoundingBox()
        params.FilterDescendantsInstances = {mapaAtual}
        local fissurasCriadas = 0
        for i = 1, 7 do
            local x = caixa.Position.X + math.random(-math.floor(tamanho.X * 0.34), math.floor(tamanho.X * 0.34))
            local z = caixa.Position.Z + math.random(-math.floor(tamanho.Z * 0.34), math.floor(tamanho.Z * 0.34))
            local origem = Vector3.new(x, caixa.Position.Y + tamanho.Y + 90, z)
            local hit = workspace:Raycast(origem, Vector3.new(0, -(tamanho.Y + 180), 0), params)
            if hit then
                local pos = hit.Position + Vector3.new(0, 0.16, 0)
                local angulo = math.rad(math.random(0, 180))
                local fissura = Instance.new("Part")
                fissura.Name = "FissuraVisual"
                fissura.Anchored = true
                fissura.CanCollide = false
                fissura.CanTouch = false
                fissura.Material = Enum.Material.Slate
                fissura.Color = Color3.fromRGB(35, 29, 25)
                fissura.Transparency = 0.04
                fissura.Size = Vector3.new(math.random(18, 32), 0.22, 1.15)
                fissura.CFrame = CFrame.new(pos) * CFrame.Angles(0, angulo, 0)
                fissura.Parent = efeitosDesastre
                Debris:AddItem(fissura, 5.5)
                for ramo = 1, 2 do
                    local ramificacao = Instance.new("Part")
                    ramificacao.Name = "RachaduraSecundaria"
                    ramificacao.Anchored = true
                    ramificacao.CanCollide = false
                    ramificacao.CanTouch = false
                    ramificacao.Material = Enum.Material.Slate
                    ramificacao.Color = Color3.fromRGB(48, 37, 30)
                    ramificacao.Transparency = 0.08
                    ramificacao.Size = Vector3.new(math.random(7, 13), 0.18, 0.75)
                    ramificacao.CFrame = fissura.CFrame * CFrame.new(math.random(-10, 10), 0.02, math.random(-2, 2)) * CFrame.Angles(0, math.rad(math.random(-55, 55)), 0)
                    ramificacao.Parent = efeitosDesastre
                    Debris:AddItem(ramificacao, 4.5)
                end
                fissurasCriadas += 1
            end
        end
        local centro = caixa.Position
        local pulso = criarEfeito(centro + Vector3.new(0, 1.2, 0), Color3.fromRGB(205, 135, 75), Vector3.new(8, 1.2, 8), 0.9)
        TweenService:Create(pulso, TweenInfo.new(0.8), {Size = Vector3.new(125, 2, 125), Transparency = 1}):Play()
        danoPerto(centro, 28, 10)
        desancorarObjetos(centro + Vector3.new(math.random(-55, 55), 0, math.random(-55, 55)), 68, 8, 48)
        task.wait(6.5)
    end
    pararSomAmbiente()
end

local function nevasca(duracao)
    tocarSomGlobal(AUDIOS.Vento, 0.48, true)
    local oldFogStart, oldFogEnd, oldFogColor = Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor
    local oldBrightness, oldAmbient = Lighting.Brightness, Lighting.OutdoorAmbient
    local atmosphere = Instance.new("Atmosphere")
    atmosphere.Name = "NeblinaNevasca"
    atmosphere.Density = 0.58
    atmosphere.Offset = 0.12
    atmosphere.Color = Color3.fromRGB(190, 215, 235)
    atmosphere.Decay = Color3.fromRGB(115, 140, 165)
    atmosphere.Glare = 0
    atmosphere.Haze = 4.5
    atmosphere.Parent = Lighting
    local correcao = Instance.new("ColorCorrectionEffect")
    correcao.Name = "FrioNevasca"
    correcao.TintColor = Color3.fromRGB(190, 215, 240)
    correcao.Saturation = -0.32
    correcao.Contrast = 0.12
    correcao.Parent = Lighting
    Lighting.FogStart = 8
    Lighting.FogEnd = 105
    Lighting.FogColor = Color3.fromRGB(185, 205, 225)
    Lighting.Brightness = 1.25
    Lighting.OutdoorAmbient = Color3.fromRGB(105, 125, 150)

    local gerador = Instance.new("Part")
    gerador.Name = "GeradorNevasca"
    gerador.Anchored = true
    gerador.CanCollide = false
    gerador.CanTouch = false
    gerador.CanQuery = false
    gerador.Transparency = 1
    gerador.Size = Vector3.new(380, 1, 380)
    gerador.Position = centroMapa() + Vector3.new(0, 58, 0)
    gerador.Parent = efeitosDesastre
    local neve = Instance.new("ParticleEmitter")
    neve.Name = "FlocosDeNeve"
    neve.Texture = "rbxasset://textures/particles/snow_main.dds"
    neve.Rate = 520
    neve.Lifetime = NumberRange.new(3.5, 6)
    neve.Speed = NumberRange.new(24, 39)
    neve.Acceleration = Vector3.new(18, -16, 0)
    neve.Drag = 1.2
    neve.SpreadAngle = Vector2.new(18, 18)
    neve.EmissionDirection = Enum.NormalId.Bottom
    neve.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0.12)})
    neve.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.45)})
    neve.RotSpeed = NumberRange.new(-90, 90)
    neve.Rotation = NumberRange.new(0, 360)
    neve.Parent = gerador

    local rajada = Instance.new("ParticleEmitter")
    rajada.Name = "RajadasDeNeve"
    rajada.Texture = "rbxasset://textures/particles/snow_main.dds"
    rajada.Rate = 95
    rajada.Lifetime = NumberRange.new(1.1, 2.2)
    rajada.Speed = NumberRange.new(42, 58)
    rajada.Acceleration = Vector3.new(34, -4, 0)
    rajada.Drag = 0.2
    rajada.SpreadAngle = Vector2.new(35, 25)
    rajada.EmissionDirection = Enum.NormalId.Right
    rajada.Size = NumberSequence.new(0.32)
    rajada.Transparency = NumberSequence.new(0.18)
    rajada.Parent = gerador

    local fim = os.clock() + duracao
    local proximoDano = {}
    while os.clock() < fim do
        -- Alterna rajadas de vento para variar a direcao da neve.
        local fase = math.sin(os.clock() * 0.7)
        neve.Acceleration = Vector3.new(18 + fase * 24, -16, math.cos(os.clock()) * 10)
        rajada.Acceleration = Vector3.new(34 + fase * 30, -4, math.cos(os.clock() * 0.8) * 18)
        for _, jogador in ipairs(Players:GetPlayers()) do
            local char = jogador.Character
            local raiz = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if raiz and hum and hum.Health > 0 then
                hum.WalkSpeed = 8
                if not estaEmAbrigo(char) then
                    local agora = os.clock()
                    if not proximoDano[jogador.UserId] or agora >= proximoDano[jogador.UserId] then
                        hum:TakeDamage(4)
                        proximoDano[jogador.UserId] = agora + 2.2
                    end
                end
            end
        end
        task.wait(0.4)
    end
    if gerador.Parent then gerador:Destroy() end
    if atmosphere.Parent then atmosphere:Destroy() end
    if correcao.Parent then correcao:Destroy() end
    Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor = oldFogStart, oldFogEnd, oldFogColor
    Lighting.Brightness, Lighting.OutdoorAmbient = oldBrightness, oldAmbient
    for _, jogador in ipairs(Players:GetPlayers()) do
        local humanoide = jogador.Character and jogador.Character:FindFirstChildOfClass("Humanoid")
        if humanoide then humanoide.WalkSpeed = 16 end
    end
    pararSomAmbiente()
end

local function raios(duracao)
    tocarSomGlobal(AUDIOS.Chuva,0.30,true)
    local fim=os.clock()+duracao
    while os.clock()<fim do
        local centro=centroMapa()
        local alvoJogador=nil
        local vivos={}
        for _,j in ipairs(Players:GetPlayers()) do
            local c=j.Character; local h=c and c:FindFirstChildOfClass("Humanoid"); local r=c and c:FindFirstChild("HumanoidRootPart")
            if h and h.Health>0 and r and not j:GetAttribute("NoLobby") and not estaEmAbrigo(c) then table.insert(vivos,r) end
        end
        local pos, parteAlvo
        if #vivos>0 and math.random()<0.36 then
            alvoJogador=vivos[math.random(1,#vivos)]
            pos=alvoJogador.Position
        else
            -- Na maioria dos casos o raio procura telhados, torres, montanhas e outros pontos altos.
            if math.random()<0.90 then
                local melhorAltura=-math.huge
                for tentativa=1,5 do
                    local candidato, parte=pontoDeImpactoAleatorio(true)
                    if parte and candidato.Y>melhorAltura then pos=candidato; parteAlvo=parte; melhorAltura=candidato.Y end
                end
            end
            if not pos then pos,parteAlvo=pontoDeImpactoAleatorio(false) end
        end
        local aviso=Instance.new("Part")
        aviso.Name="AvisoRaio"
        aviso.Shape=Enum.PartType.Cylinder
        aviso.Size=Vector3.new(0.16,18,18)
        aviso.CFrame=CFrame.new(pos+Vector3.new(0,0.25,0))*CFrame.Angles(0,0,math.rad(90))
        aviso.Anchored=true; aviso.CanCollide=false; aviso.Material=Enum.Material.Neon
        aviso.Color=Color3.fromRGB(150,205,255); aviso.Transparency=0.28; aviso.Parent=efeitosDesastre
        Debris:AddItem(aviso,1.15)
        task.wait(0.9)

        local luzRaio=Instance.new("PointLight")
        luzRaio.Color=Color3.fromRGB(190,220,255); luzRaio.Range=70; luzRaio.Brightness=7
        local segmentos={}
        local deslocamento=Vector3.new(0,0,0)
        for i=1,6 do
            deslocamento=deslocamento+Vector3.new(math.random(-3,3),-9,math.random(-3,3))
            local segmento=Instance.new("Part")
            segmento.Name="RaioSegmentado"
            segmento.Anchored=true; segmento.CanCollide=false; segmento.CanTouch=false
            segmento.Material=Enum.Material.Neon; segmento.Color=Color3.fromRGB(225,245,255)
            segmento.Size=Vector3.new(1.1,10,1.1)
            segmento.CFrame=CFrame.new(pos+Vector3.new(0,55-(i-1)*9,0)+deslocamento)
            segmento.Parent=efeitosDesastre
            if i==1 then luzRaio.Parent=segmento end
            table.insert(segmentos,segmento)
            Debris:AddItem(segmento,0.28)
        end
        Lighting.Brightness=4.5
        for _,j in ipairs(Players:GetPlayers()) do
            local c=j.Character; local h=c and c:FindFirstChildOfClass("Humanoid"); local r=c and c:FindFirstChild("HumanoidRootPart")
            if h and h.Health>0 and r and not j:GetAttribute("NoLobby") and (r.Position-pos).Magnitude<=9 and not estaEmAbrigo(c) then
                h.Health=0
            end
        end
        danoPerto(pos,26,58)
        desancorarObjetos(pos, 64, 22, 125)
        local explosao = Instance.new("Explosion")
        explosao.Position = pos + Vector3.new(0, 2, 0)
        explosao.BlastRadius = 29
        explosao.BlastPressure = 600000
        explosao.DestroyJointRadiusPercent = 0.88
        explosao.Parent = workspace
        Debris:AddItem(explosao, 2)
        local claraoVisual = criarEfeito(pos + Vector3.new(0, 2, 0), Color3.fromRGB(205, 230, 255), Vector3.new(4,4,4), 0.5)
        TweenService:Create(claraoVisual, TweenInfo.new(0.38), {Size=Vector3.new(25,25,25), Transparency=1}):Play()
        tocarSomGlobal(AUDIOS.Impacto,0.48,false)
        task.wait(0.12)
        Lighting.Brightness=2
        task.wait(1.65)
    end
    pararSomAmbiente()
end

local function fogo(duracao)
    tocarSomGlobal(AUDIOS.Fogo,0.28,true)
    local fim = os.clock() + duracao
    local proximaDesancoragem = os.clock() + 8
    while os.clock() < fim do
        local pos = centroMapa() + Vector3.new(math.random(-45,45), 2, math.random(-45,45))
        if os.clock() >= proximaDesancoragem then
            desancorarObjetos(pos, 12, 1, 18)
            proximaDesancoragem = os.clock() + 8
        end
        local p = Instance.new("Part")
        p.Name = "FogoDoDesastre"
        p.Size = Vector3.new(5,1,5)
        p.Position = pos
        p.Anchored = true
        p.CanCollide = false
        p.Transparency = 1
        p.Parent = efeitosDesastre or workspace
        local fire = Instance.new("Fire")
        fire.Size = 9
        fire.Heat = 12
        fire.Color = Color3.fromRGB(255,125,35)
        fire.SecondaryColor = Color3.fromRGB(255,220,75)
        fire.Parent = p
        local fumaca=Instance.new("Smoke")
        fumaca.Color=Color3.fromRGB(70,65,60); fumaca.Opacity=0.28; fumaca.Size=12; fumaca.RiseVelocity=14
        fumaca.Parent=p
        local luz=Instance.new("PointLight"); luz.Color=Color3.fromRGB(255,115,35); luz.Range=18; luz.Brightness=2; luz.Parent=p
        Debris:AddItem(p, 5)
        danoPerto(pos, 11, 18)
        task.wait(0.95)
    end
    pararSomAmbiente()
end

local funcoesDesastre = {
    ["Chuva de Meteoros"] = meteoros,
    ["Tornado"] = tornado,
    ["Terremoto"] = terremoto,
    ["Nevasca"] = nevasca,
    ["Tempestade de Raios"] = raios,
    ["Chuva de Fogo"] = fogo
}

local function escolherDesastre(nomeMapa)
    local escolhidoPeloAdmin = ReplicatedStorage:GetAttribute("AdminNextDisaster")
    if typeof(escolhidoPeloAdmin) == "string" and funcoesDesastre[escolhidoPeloAdmin] then
        ReplicatedStorage:SetAttribute("AdminNextDisaster", nil)
        return escolhidoPeloAdmin
    end
    local disponiveis = {}
    for _, nome in ipairs(DESASTRES) do
        if not ((nomeMapa == "Deserto" or nomeMapa == "Vila_Costeira") and nome == "Nevasca") then
            table.insert(disponiveis, nome)
        end
    end
    if #disponiveis == 0 then return "Tempestade de Raios" end
    return disponiveis[Random.new():NextInteger(1, #disponiveis)]
end

local function resetarJogadores()
    for _, jogador in ipairs(Players:GetPlayers()) do
        local hum = jogador.Character and jogador.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
end

while true do
    for segundos = INTERVALO, 1, -1 do
        roundEvent:FireAllClients("Mensagem", "Próxima votação em " .. segundos .. " segundos")
        task.wait(1)
    end

    local vencedor = votarMapa()
    if not vencedor then
        task.wait(5)
        continue
    end

    if not carregarMapa(vencedor) then
        task.wait(5)
        continue
    end

    task.wait(1)
    for _, jogador in ipairs(Players:GetPlayers()) do
        jogador:SetAttribute("NoLobby", false)
    end
    teleportarJogadores()
    anunciar("Mapa escolhido: " .. vencedor)
    task.wait(3)

    -- Preserve a iluminação definida pelo mapa para restaurá-la mesmo se um desastre for interrompido.
    local lightingRodada = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        FogStart = Lighting.FogStart,
        FogEnd = Lighting.FogEnd,
        FogColor = Lighting.FogColor,
    }

    -- Começa a rodada e registra os jogadores vivos.
    rodadaAtiva = true
    criarPastaEfeitos()

    local desastre = escolherDesastre(vencedor)
    anunciar("DESASTRE: " .. string.upper(desastre) .. "!")
    roundEvent:FireAllClients("Desastre", desastre)

    -- O desastre fica ativo durante toda a rodada; os efeitos menores podem expirar e ser recriados continuamente.
    local desastreTerminou = false
    local tarefaDesastre = task.spawn(function()
        local sucesso, erro = pcall(function()
            funcoesDesastre[desastre](DURACAO_DESASTRE)
        end)
        if not sucesso then
            warn("[DESASTRE] Erro em " .. desastre .. ": " .. tostring(erro))
        end
        desastreTerminou = true
        limparEfeitosDesastre()
    end)

    local tempoRestante = DURACAO_PARTIDA
    while tempoRestante > 0 do
        if not existeJogadorVivo() then
            anunciar("Todos os jogadores foram eliminados! Partida encerrada.")
            break
        end

        if tempoRestante % 10 == 0 or tempoRestante <= 5 then
            roundEvent:FireAllClients("Mensagem", "Tempo restante: " .. tempoRestante .. "s")
        end

        task.wait(1)
        tempoRestante -= 1
    end

    rodadaAtiva = false
    if not desastreTerminou then
        pcall(function() task.cancel(tarefaDesastre) end)
    end
    limparEfeitosDesastre()
    pararSomAmbiente()
    for _, efeito in ipairs(Lighting:GetChildren()) do
        if efeito.Name == "NeblinaNevasca" or efeito.Name == "FrioNevasca" then efeito:Destroy() end
    end
    -- Restaura exatamente a iluminação do mapa, em vez de forçar um valor genérico.
    if lightingRodada then
        Lighting.Brightness = lightingRodada.Brightness
        Lighting.ClockTime = lightingRodada.ClockTime
        Lighting.OutdoorAmbient = lightingRodada.OutdoorAmbient
        Lighting.FogStart = lightingRodada.FogStart
        Lighting.FogEnd = lightingRodada.FogEnd
        Lighting.FogColor = lightingRodada.FogColor
    end
    resetarJogadores()

    if tempoRestante <= 0 then
        anunciar("Tempo esgotado! Partida encerrada.")
    end

    task.wait(3)
    limparMapa()

    for _, jogador in ipairs(Players:GetPlayers()) do
        jogador:SetAttribute("NoLobby", true)
        jogador:LoadCharacter()
    end
    task.wait(3)
end

]==]

local ClientSource = [==[
-- MINIDISASTERS V7 - INTERFACE COMPLETA + PAINEL ADM
-- Local: StarterPlayer > StarterPlayerScripts > InterfacePartida (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local player = Players.LocalPlayer

local eventos = ReplicatedStorage:WaitForChild("EventosPartida")
local roundEvent = eventos:WaitForChild("RoundEvent")
local prontoEvent = eventos:WaitForChild("ClientePronto")
local playerGui = player:WaitForChild("PlayerGui")
local antiga = playerGui:FindFirstChild("InterfacePartida")
if antiga then antiga:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "InterfacePartida"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 20
gui.Parent = playerGui

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
end
local function stroke(obj, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(105, 155, 220)
    s.Thickness = thickness or 1
    s.Transparency = 0.35
    s.Parent = obj
end

-- HUD principal V7.
local aviso = Instance.new("TextLabel")
aviso.Name = "Aviso"
aviso.AnchorPoint = Vector2.new(0.5, 0)
aviso.Size = UDim2.new(0.56, 0, 0, 32)
aviso.Position = UDim2.new(0.5, 0, 0.008, 0)
aviso.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
aviso.BackgroundTransparency = 0.08
aviso.TextColor3 = Color3.new(1, 1, 1)
aviso.TextScaled = true
aviso.Font = Enum.Font.GothamBold
aviso.Text = "Aguardando próxima votação..."
aviso.Parent = gui
corner(aviso, 8)
stroke(aviso)
local limiteAviso = Instance.new("UITextSizeConstraint")
limiteAviso.MinTextSize = 9
limiteAviso.MaxTextSize = 17
limiteAviso.Parent = aviso

local desastreCanto = Instance.new("TextLabel")
desastreCanto.Name = "DesastreCanto"
desastreCanto.AnchorPoint = Vector2.new(1, 0)
desastreCanto.Position = UDim2.new(0.985, 0, 0.055, 0)
desastreCanto.Size = UDim2.new(0.34, 0, 0, 20)
desastreCanto.BackgroundTransparency = 1
desastreCanto.TextColor3 = Color3.fromRGB(255, 205, 120)
desastreCanto.TextStrokeTransparency = 0.45
desastreCanto.TextXAlignment = Enum.TextXAlignment.Right
desastreCanto.Font = Enum.Font.GothamBold
desastreCanto.TextScaled = true
desastreCanto.Text = ""
desastreCanto.Parent = gui
local limiteDesastre = Instance.new("UITextSizeConstraint")
limiteDesastre.MinTextSize = 9
limiteDesastre.MaxTextSize = 14
limiteDesastre.Parent = desastreCanto

local somAviso = Instance.new("Sound")
somAviso.Name = "SomAvisoPartida"
somAviso.SoundId = "rbxassetid://72046313"
somAviso.Volume = 0.35
somAviso.Parent = SoundService
local fimTremor = 0
local intensidadeTremor = 0
RunService:BindToRenderStep("TremorPartida", Enum.RenderPriority.Camera.Value + 1, function()
    if os.clock() < fimTremor then
        local camera = workspace.CurrentCamera
        if camera then
            local escala = intensidadeTremor
            camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * escala, (math.random() - 0.5) * escala, 0)
        end
    end
end)

roundEvent.OnClientEvent:Connect(function(tipo, a, b)
    if tipo == "Mensagem" then
        local mensagem = tostring(a)
        if string.find(string.upper(mensagem), "DESASTRE:", 1, true) then
            desastreCanto.Text = "⚠ " .. mensagem:gsub("[Dd][Ee][Ss][Aa][Ss][Tt][Rr][Ee]:%s*", "")
        elseif string.find(mensagem, "Próxima votação", 1, true) then
            desastreCanto.Text = ""
            aviso.Text = mensagem
        else
            aviso.Text = mensagem
        end
    elseif tipo == "Votacao" then
        aviso.Text = "Pise na plataforma do mapa que deseja escolher!"
    elseif tipo == "CronometroVoto" then
        aviso.Text = "VOTAÇÃO: " .. tostring(a) .. "s — pise em uma plataforma"
    elseif tipo == "FimVotacao" then
        aviso.Text = "Mapa escolhido: " .. tostring(a):gsub("_", " ")
    elseif tipo == "Desastre" then
        desastreCanto.Text = "⚠ " .. string.upper(tostring(a))
        pcall(function() somAviso:Play() end)
    elseif tipo == "Tremor" then
        fimTremor = math.max(fimTremor, os.clock() + (tonumber(a) or 1))
        intensidadeTremor = 0.22
    end
end)

-- Painel ADM exclusivo para w00byd0lx. O servidor valida todas as ações novamente.
if string.lower(player.Name) == "w00byd0lx" then
    local remotes = ReplicatedStorage:WaitForChild("AdminRemotes")
    local adminEvent = remotes:WaitForChild("AdminEvent")
    local feedback = remotes:WaitForChild("AdminFeedback")
    local DESASTRES = {
        "Chuva de Meteoros", "Tornado", "Terremoto",
        "Nevasca", "Tempestade de Raios", "Chuva de Fogo",
    }

    -- Botão de canto com desenho vetorial de martelo (sem depender de asset externo).
    local toggle = Instance.new("ImageButton")
    toggle.Name = "AbrirPainelADM"
    toggle.Size = UDim2.fromOffset(48, 48)
    toggle.Position = UDim2.new(0, 12, 0, 12)
    toggle.BackgroundColor3 = Color3.fromRGB(28, 36, 50)
    toggle.Image = ""
    toggle.AutoButtonColor = true
    toggle.Parent = gui
    corner(toggle, 11)
    stroke(toggle, Color3.fromRGB(105, 175, 255), 1.6)
    local cabo = Instance.new("Frame")
    cabo.Name = "CaboMartelo"
    cabo.AnchorPoint = Vector2.new(0.5, 0.5)
    cabo.Position = UDim2.fromScale(0.48, 0.57)
    cabo.Size = UDim2.fromOffset(6, 25)
    cabo.Rotation = 42
    cabo.BackgroundColor3 = Color3.fromRGB(225, 232, 242)
    cabo.BorderSizePixel = 0
    cabo.Parent = toggle
    corner(cabo, 3)
    local cabeca = Instance.new("Frame")
    cabeca.Name = "CabecaMartelo"
    cabeca.AnchorPoint = Vector2.new(0.5, 0.5)
    cabeca.Position = UDim2.fromScale(0.62, 0.29)
    cabeca.Size = UDim2.fromOffset(23, 10)
    cabeca.Rotation = 42
    cabeca.BackgroundColor3 = Color3.fromRGB(225, 232, 242)
    cabeca.BorderSizePixel = 0
    cabeca.Parent = toggle
    corner(cabeca, 3)

    local painel = Instance.new("Frame")
    painel.Name = "PainelADM"
    painel.AnchorPoint = Vector2.new(0.5, 0.5)
    painel.Position = UDim2.fromScale(0.5, 0.5)
    painel.Size = UDim2.new(0.88, 0, 0.74, 0)
    painel.BackgroundColor3 = Color3.fromRGB(18, 23, 33)
    painel.Visible = false
    painel.ClipsDescendants = true
    painel.Parent = gui
    corner(painel, 13)
    stroke(painel, Color3.fromRGB(75, 135, 210), 2)
    local limitePainel = Instance.new("UISizeConstraint")
    limitePainel.MinSize = Vector2.new(285, 310)
    limitePainel.MaxSize = Vector2.new(560, 510)
    limitePainel.Parent = painel

    local titulo = Instance.new("TextLabel")
    titulo.BackgroundTransparency = 1
    titulo.Position = UDim2.fromOffset(14, 5)
    titulo.Size = UDim2.new(1, -62, 0, 38)
    titulo.Text = "PAINEL ADMINISTRADOR"
    titulo.TextColor3 = Color3.fromRGB(240, 245, 255)
    titulo.Font = Enum.Font.GothamBold
    titulo.TextSize = 17
    titulo.TextXAlignment = Enum.TextXAlignment.Left
    titulo.Parent = painel
    local fechar = Instance.new("TextButton")
    fechar.Size = UDim2.fromOffset(34, 30)
    fechar.Position = UDim2.new(1, -41, 0, 7)
    fechar.BackgroundColor3 = Color3.fromRGB(150, 55, 60)
    fechar.Text = "X"
    fechar.TextColor3 = Color3.new(1, 1, 1)
    fechar.Font = Enum.Font.GothamBold
    fechar.TextSize = 15
    fechar.Parent = painel
    corner(fechar, 7)

    local abas = Instance.new("Frame")
    abas.BackgroundTransparency = 1
    abas.Position = UDim2.fromOffset(10, 46)
    abas.Size = UDim2.new(1, -20, 0, 36)
    abas.Parent = painel
    local layoutAbas = Instance.new("UIListLayout")
    layoutAbas.FillDirection = Enum.FillDirection.Horizontal
    layoutAbas.Padding = UDim.new(0, 6)
    layoutAbas.SortOrder = Enum.SortOrder.LayoutOrder
    layoutAbas.Parent = abas
    local conteudo = Instance.new("Frame")
    conteudo.Position = UDim2.fromOffset(10, 88)
    conteudo.Size = UDim2.new(1, -20, 1, -98)
    conteudo.BackgroundColor3 = Color3.fromRGB(25, 31, 43)
    conteudo.Parent = painel
    corner(conteudo, 9)

    local function botao(parent, texto, posicao, tamanho)
        local b = Instance.new("TextButton")
        b.Position = posicao
        b.Size = tamanho
        b.BackgroundColor3 = Color3.fromRGB(48, 91, 145)
        b.Text = texto
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.TextWrapped = true
        b.Parent = parent
        corner(b, 7)
        return b
    end
    local function caixaTexto(parent, placeholder, posicao, tamanho)
        local t = Instance.new("TextBox")
        t.Position = posicao
        t.Size = tamanho
        t.BackgroundColor3 = Color3.fromRGB(37, 45, 60)
        t.PlaceholderText = placeholder
        t.Text = ""
        t.ClearTextOnFocus = false
        t.TextColor3 = Color3.new(1, 1, 1)
        t.PlaceholderColor3 = Color3.fromRGB(160, 170, 185)
        t.Font = Enum.Font.Gotham
        t.TextSize = 13
        t.Parent = parent
        corner(t, 7)
        return t
    end
    local paginas = {}
    local function novaPagina(nome)
        local p = Instance.new("Frame")
        p.Name = nome
        p.Size = UDim2.fromScale(1, 1)
        p.BackgroundTransparency = 1
        p.Visible = false
        p.Parent = conteudo
        paginas[nome] = p
        return p
    end
    local function mostrarPagina(nome)
        for chave, pagina in pairs(paginas) do pagina.Visible = chave == nome end
    end

    -- Desastres: lista real do controlador V7.
    local paginaDesastres = novaPagina("Desastres")
    local rotuloDesastre = Instance.new("TextLabel")
    rotuloDesastre.BackgroundTransparency = 1
    rotuloDesastre.Position = UDim2.fromOffset(12, 8)
    rotuloDesastre.Size = UDim2.new(1, -24, 0, 25)
    rotuloDesastre.Text = "Escolha o próximo desastre:"
    rotuloDesastre.TextColor3 = Color3.new(1, 1, 1)
    rotuloDesastre.Font = Enum.Font.GothamBold
    rotuloDesastre.TextSize = 14
    rotuloDesastre.TextXAlignment = Enum.TextXAlignment.Left
    rotuloDesastre.Parent = paginaDesastres
    local lista = Instance.new("ScrollingFrame")
    lista.Position = UDim2.fromOffset(12, 38)
    lista.Size = UDim2.new(1, -24, 1, -94)
    lista.BackgroundColor3 = Color3.fromRGB(31, 39, 53)
    lista.BorderSizePixel = 0
    lista.ScrollBarThickness = 5
    lista.CanvasSize = UDim2.new()
    lista.Parent = paginaDesastres
    corner(lista, 7)
    local listaLayout = Instance.new("UIListLayout")
    listaLayout.Padding = UDim.new(0, 5)
    listaLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listaLayout.Parent = lista
    listaLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        lista.CanvasSize = UDim2.new(0, 0, 0, listaLayout.AbsoluteContentSize.Y + 8)
    end)
    local selecionado = DESASTRES[1]
    local selecionadoTexto = Instance.new("TextLabel")
    selecionadoTexto.BackgroundTransparency = 1
    selecionadoTexto.Position = UDim2.new(0, 12, 1, -49)
    selecionadoTexto.Size = UDim2.new(0.54, -12, 0, 38)
    selecionadoTexto.Text = "Selecionado: " .. selecionado
    selecionadoTexto.TextColor3 = Color3.fromRGB(220, 230, 245)
    selecionadoTexto.Font = Enum.Font.Gotham
    selecionadoTexto.TextSize = 11
    selecionadoTexto.TextWrapped = true
    selecionadoTexto.Parent = paginaDesastres
    for _, nome in ipairs(DESASTRES) do
        local item = botao(lista, nome, UDim2.new(), UDim2.new(1, -8, 0, 34))
        item.BackgroundColor3 = Color3.fromRGB(48, 58, 75)
        item.MouseButton1Click:Connect(function()
            selecionado = nome
            selecionadoTexto.Text = "Selecionado: " .. nome
        end)
    end
    local definir = botao(paginaDesastres, "DEFINIR PRÓXIMO", UDim2.new(0.57, 0, 1, -49), UDim2.new(0.40, -12, 0, 38))
    definir.MouseButton1Click:Connect(function()
        adminEvent:FireServer("SetNextDisaster", selecionado)
    end)

    -- Kick com sugestões ao digitar o começo do nome.
    local paginaKick = novaPagina("Kick")
    local nomeBox = caixaTexto(paginaKick, "Nome do jogador (ex.: Ma)", UDim2.fromOffset(12, 14), UDim2.new(1, -24, 0, 38))
    local sugestoes = Instance.new("ScrollingFrame")
    sugestoes.Position = UDim2.fromOffset(12, 57)
    sugestoes.Size = UDim2.new(1, -24, 0, 105)
    sugestoes.BackgroundColor3 = Color3.fromRGB(31, 39, 53)
    sugestoes.BorderSizePixel = 0
    sugestoes.ScrollBarThickness = 4
    sugestoes.Visible = false
    sugestoes.Parent = paginaKick
    corner(sugestoes, 7)
    local sugestoesLayout = Instance.new("UIListLayout")
    sugestoesLayout.Padding = UDim.new(0, 3)
    sugestoesLayout.Parent = sugestoes
    local motivoBox = caixaTexto(paginaKick, "Motivo do kick", UDim2.fromOffset(12, 173), UDim2.new(1, -24, 0, 38))
    local expulsar = botao(paginaKick, "EXPULSAR JOGADOR", UDim2.fromOffset(12, 222), UDim2.new(1, -24, 0, 40))
    local function atualizarSugestoes()
        for _, filho in ipairs(sugestoes:GetChildren()) do
            if filho:IsA("TextButton") then filho:Destroy() end
        end
        local busca = string.lower(nomeBox.Text)
        if busca == "" then sugestoes.Visible = false; return end
        local encontrados = {}
        for _, alvo in ipairs(Players:GetPlayers()) do
            if alvo ~= player and (string.sub(string.lower(alvo.Name), 1, #busca) == busca
                or string.sub(string.lower(alvo.DisplayName), 1, #busca) == busca) then
                table.insert(encontrados, alvo)
            end
        end
        table.sort(encontrados, function(a, b) return a.Name < b.Name end)
        for _, alvo in ipairs(encontrados) do
            local escolha = botao(sugestoes, alvo.DisplayName .. "  (@" .. alvo.Name .. ")", UDim2.new(), UDim2.new(1, -6, 0, 30))
            escolha.BackgroundColor3 = Color3.fromRGB(48, 58, 75)
            escolha.MouseButton1Click:Connect(function()
                nomeBox.Text = alvo.Name
                sugestoes.Visible = false
            end)
        end
        sugestoes.CanvasSize = UDim2.new(0, 0, 0, #encontrados * 33)
        sugestoes.Visible = #encontrados > 0
    end
    nomeBox:GetPropertyChangedSignal("Text"):Connect(atualizarSugestoes)
    Players.PlayerAdded:Connect(atualizarSugestoes)
    Players.PlayerRemoving:Connect(atualizarSugestoes)
    expulsar.MouseButton1Click:Connect(function()
        adminEvent:FireServer("Kick", nomeBox.Text, motivoBox.Text)
        sugestoes.Visible = false
    end)

    -- F3X/BTools configurada no ServerStorage.
    local paginaF3X = novaPagina("F3X")
    local infoF3X = Instance.new("TextLabel")
    infoF3X.BackgroundTransparency = 1
    infoF3X.Position = UDim2.fromOffset(14, 18)
    infoF3X.Size = UDim2.new(1, -28, 0, 72)
    infoF3X.Text = 'Entrega a ferramenta chamada "F3X" que estiver em ServerStorage.'
    infoF3X.TextColor3 = Color3.new(1, 1, 1)
    infoF3X.TextWrapped = true
    infoF3X.Font = Enum.Font.Gotham
    infoF3X.TextSize = 14
    infoF3X.Parent = paginaF3X
    local receberF3X = botao(paginaF3X, "RECEBER F3X / BTOOLS", UDim2.fromOffset(14, 104), UDim2.new(1, -28, 0, 44))
    receberF3X.MouseButton1Click:Connect(function()
        adminEvent:FireServer("GiveF3X")
    end)

    local function criarAba(nome, ordem)
        local b = botao(abas, nome, UDim2.new(), UDim2.new(0.333, -5, 1, 0))
        b.LayoutOrder = ordem
        b.MouseButton1Click:Connect(function() mostrarPagina(nome) end)
    end
    criarAba("Desastres", 1)
    criarAba("Kick", 2)
    criarAba("F3X", 3)
    mostrarPagina("Desastres")
    toggle.MouseButton1Click:Connect(function() painel.Visible = not painel.Visible end)
    fechar.MouseButton1Click:Connect(function() painel.Visible = false end)
    feedback.OnClientEvent:Connect(function(mensagem, sucesso)
        aviso.Text = tostring(mensagem)
        aviso.TextColor3 = sucesso and Color3.fromRGB(160, 255, 180) or Color3.fromRGB(255, 170, 160)
    end)
end

prontoEvent:FireServer()
print("[InterfacePartida] MiniDisasters V7 completo carregado para " .. player.Name)

]==]

local F3XClientSource = [==[
-- LocalScript da ferramenta F3X básica: mover, clonar e apagar peças do mapa.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local tool = script.Parent
local remote = ReplicatedStorage:WaitForChild("AdminRemotes"):WaitForChild("BuildAction")
local mouse
local modo = "Move"
local gui
local botoes = {}
local function atualizarBotoes()
    for nome, botao in pairs(botoes) do
        botao.BackgroundColor3 = (nome == modo) and Color3.fromRGB(65, 125, 195) or Color3.fromRGB(35, 43, 58)
    end
end
local function criarInterface()
    if gui then gui:Destroy() end
    gui = Instance.new("ScreenGui")
    gui.Name = "F3XMiniDisasters"
    gui.ResetOnSpawn = false
    gui.Parent = player:WaitForChild("PlayerGui")
    local barra = Instance.new("Frame")
    barra.AnchorPoint = Vector2.new(0.5, 1)
    barra.Position = UDim2.new(0.5, 0, 0.97, 0)
    barra.Size = UDim2.fromOffset(300, 48)
    barra.BackgroundColor3 = Color3.fromRGB(18, 23, 33)
    barra.Parent = gui
    Instance.new("UICorner", barra).CornerRadius = UDim.new(0, 9)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 6)
    layout.Parent = barra
    for _, dado in ipairs({{"Move", "MOVER"}, {"Clone", "CLONAR"}, {"Delete", "APAGAR"}}) do
        local b = Instance.new("TextButton")
        b.Name = dado[1]
        b.Size = UDim2.fromOffset(90, 34)
        b.BackgroundColor3 = Color3.fromRGB(35, 43, 58)
        b.Text = dado[2]
        b.TextColor3 = Color3.new(1,1,1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.Parent = barra
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(function()
            modo = dado[1]
            atualizarBotoes()
        end)
        botoes[dado[1]] = b
    end
    atualizarBotoes()
end
tool.Equipped:Connect(function(mouseRecebido)
    mouse = mouseRecebido
    criarInterface()
end)
tool.Unequipped:Connect(function()
    if gui then gui:Destroy(); gui = nil end
    mouse = nil
end)
tool.Activated:Connect(function()
    if not mouse then return end
    local alvo = mouse.Target
    if not alvo then return end
    remote:FireServer(modo, alvo, mouse.Hit.Position)
end)

]==]

local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local ServerStorage = game:GetService("ServerStorage")

local antigoServidor = ServerScriptService:FindFirstChild("MiniDisasters_Admin_V7")
if antigoServidor then antigoServidor:Destroy() end
local antigaInterface = StarterPlayerScripts:FindFirstChild("InterfacePartida_V7")
if antigaInterface then antigaInterface:Destroy() end

local sistema = ServerScriptService:FindFirstChild("SistemaPartida")
if not sistema then sistema = Instance.new("Script"); sistema.Name = "SistemaPartida"; sistema.Parent = ServerScriptService end
sistema.Source = ServerSource
local interface = StarterPlayerScripts:FindFirstChild("InterfacePartida")
if not interface then interface = Instance.new("LocalScript"); interface.Name = "InterfacePartida"; interface.Parent = StarterPlayerScripts end
interface.Source = ClientSource

-- Se o projeto não trouxer uma ferramenta F3X, cria uma versão básica com mover/clonar/apagar.
local ferramenta = ServerStorage:FindFirstChild("F3X")
if not ferramenta then
    ferramenta = Instance.new("Tool")
    ferramenta.Name = "F3X"
    ferramenta.RequiresHandle = false
    ferramenta.CanBeDropped = false
    ferramenta.ToolTip = "BTools do MiniDisasters: mover, clonar e apagar"
    local localScript = Instance.new("LocalScript")
    localScript.Name = "F3XClient"
    localScript.Source = F3XClientSource
    localScript.Parent = ferramenta
    ferramenta.Parent = ServerStorage
elseif ferramenta:IsA("Tool") and not ferramenta:FindFirstChild("F3XClient") then
    local localScript = Instance.new("LocalScript")
    localScript.Name = "F3XClient"
    localScript.Source = F3XClientSource
    localScript.Parent = ferramenta
end

local mapas = ServerStorage:FindFirstChild("Mapas")
if not mapas then warn("[MiniDisasters V7] ServerStorage > Mapas nao foi encontrado.") else
    for _, nome in ipairs({"Cidade", "Ilha_Tropical", "Montanhas", "Deserto", "Vila_Costeira"}) do
        if not mapas:FindFirstChild(nome) then warn("[MiniDisasters V7] Mapa ausente: " .. nome) end
    end
end

print("====================================================")
print("MiniDisasters V7 - ATUALIZACAO COMPLETA INSTALADA")
print("Sistema: ServerScriptService > SistemaPartida")
print("Interface: StarterPlayerScripts > InterfacePartida")
print("Rodadas: 90s | Votacao: 20s | Intervalo: 15s")
print("ADM exclusivo: @w00byd0lx")
print("6 desastres integrados ao seletor ADM")
print("Mapas ampliados + lobby/votacao preservados")
print("BTools F3X: mover, clonar e apagar pecas do mapa")
print("====================================================")
