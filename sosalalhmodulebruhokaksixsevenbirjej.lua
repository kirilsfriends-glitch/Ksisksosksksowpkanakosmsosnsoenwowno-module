-- RAGE MODULE v2.0
local RageModule = {}
RageModule.__index = RageModule

function RageModule.new(config)
	local self = setmetatable({}, RageModule)

	-- Services
	self.player = config.Player
	self.Players = config.Services.Players
	self.RunService = config.Services.RunService
	self.Workspace = config.Services.Workspace
	self.ReplicatedStorage = config.Services.ReplicatedStorage
	self.Notification = config.Notification
	self.Visuals = config.Visuals

	-- Settings
	self.RAGE_ENABLED = false
	self.RAGE_HITPART = "Head"
	self.RAGE_HITCHANCE = 100
	self.RAGE_HITCHANCE_ENABLED = false
	self.RAGE_AUTOSHOOT = false
	self.RAGE_NOSPREAD = false
	self.AUTO_EQUIP_SSG = false
	self.MAX_DISTANCE = 1000

	-- Prediction
	self.PREDICTION_ENABLED = true
	self.PREDICTION_STRENGTH = 1.2
	self.BULLET_SPEED = 800

	-- Min Damage
	self.MIN_DAMAGE_ENABLED = false
	self.MIN_DAMAGE_VALUE = 0
	self.BASE_DAMAGE = 54

	-- ============================================
	-- AIRSHOT SETTINGS (новое)
	-- ============================================
	self.AIRSHOT_ENABLED = false
	self.AIRSHOT_HITPART = "Head"        -- "Head" / "Body" / "Legs" / "Arms"
	self.AIRSHOT_PREDICTION = true
	self.AIRSHOT_PRED_STRENGTH = 3.5
	self.AIRSHOT_FIRE_RATE = 0.08        -- независимый fire rate для airshot
	self._lastAirshotFire = 0

	-- ============================================
	-- DOUBLE TAP SETTINGS (новое)
	-- ============================================
	self.DT_ENABLED = false
	self.DT_TP_DIST = 6.5
	self.DT_COOLDOWN = 2.0
	self.DT_MAX_RANGE = 200
	self._dtLastUse = 0

	-- ============================================
	-- AUTOSHOOT — независимый от конфига (новое)
	-- ============================================
	-- Реальный fire rate определяется оружием динамически
	-- Не зависит от внешнего FIRE_RATE конфига
	self._autoShootLastFire = 0
	self._detectedFireRate = 0           -- определяется по типу оружия
	self.AUTOSHOOT_ALWAYS_MAX = true     -- всегда стрелять на максимальной скорости

	-- Internal state
	self.lastShot = 0
	self.FIRE_RATE = 0.1
	self.FIRE_RATE_AWP = 1.3
	self.ping = 0
	self.lastPingUpdate = 0
	self.PING_UPDATE_RATE = 1
	self.activePlayers = {}
	self.lastPlayerListUpdate = 0
	self.PLAYER_LIST_UPDATE_RATE = 0.5
	self.autoEquippedOnce = false

	-- Velocity tracking для улучшенного предикта
	self._velocityTracking = {}

	-- Reusable raycast params
	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self._rayParams.IgnoreWater = true

	self.BODY_PART_MULTIPLIERS = {
		["Head"] = 4.0,
		["UpperTorso"] = 1.0,
		["LowerTorso"] = 1.0,
		["Torso"] = 1.0,
		["HumanoidRootPart"] = 1.0,
		["LeftUpperArm"] = 0.75,
		["LeftLowerArm"] = 0.75,
		["LeftHand"] = 0.75,
		["RightUpperArm"] = 0.75,
		["RightLowerArm"] = 0.75,
		["RightHand"] = 0.75,
		["LeftUpperLeg"] = 0.6,
		["LeftLowerLeg"] = 0.6,
		["LeftFoot"] = 0.6,
		["RightUpperLeg"] = 0.6,
		["RightLowerLeg"] = 0.6,
		["RightFoot"] = 0.6,
		["Left Leg"] = 0.6,
		["Right Leg"] = 0.6,
	}

	self.MIN_DAMAGE_PRIORITY = {
		{name = "Legs", parts = {"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "Left Leg", "Right Leg"}, multiplier = 0.6},
		{name = "Arms", parts = {"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "Left Arm", "Right Arm"}, multiplier = 0.75},
		{name = "Body", parts = {"UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart"}, multiplier = 1.0},
		{name = "Head", parts = {"Head"}, multiplier = 4.0},
	}

	return self
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================
function RageModule:IsAlive()
	local char = self.player.Character
	if not char then return false end
	local hum = char:FindFirstChild("Humanoid")
	return hum and hum.Health > 0
end

function RageModule:IsEnemy(target)
	if self.player.Team and target.Team then
		return self.player.Team ~= target.Team
	end
	return true
end

function RageModule:IsInAir()
	local char = self.player.Character
	if not char then return true end
	local hum = char:FindFirstChild("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then return true end
	if hum.FloorMaterial == Enum.Material.Air then return true end
	if math.abs(hrp.AssemblyLinearVelocity.Y) > 2 then return true end
	return false
end

function RageModule:GetGun()
	local char = self.player.Character
	if not char then return nil end

	for _, item in pairs(char:GetChildren()) do
		if item:IsA("Tool") then
			local remotes = item:FindFirstChild("Remotes")
			if remotes then
				local fireShot = remotes:FindFirstChild("FireShot")
				if fireShot then
					-- AWP — определяем fire rate динамически
					return {
						type = "AWP",
						fireShot = fireShot,
						fireRate = self.AUTOSHOOT_ALWAYS_MAX and 0.01 or self.FIRE_RATE_AWP,
						tool = item
					}
				end

				local castRay = remotes:FindFirstChild("CastRay")
				local hole = item:FindFirstChild("Hole")
				if castRay and hole then
					-- CastRay — максимальная скорость
					return {
						type = "CastRay",
						castRay = castRay,
						hole = hole,
						fireRate = self.AUTOSHOOT_ALWAYS_MAX and 0.01 or self.FIRE_RATE,
						tool = item
					}
				end
			end
		end
	end

	return nil
end

-- ============================================
-- VISIBILITY — УЛУЧШЕННАЯ (из Enhancer)
-- Чистая проверка, без сквозного пробития
-- ============================================

-- Одиночная точка — чистый raycast без пробития
function RageModule:IsPartDirectlyVisible(targetPart, targetChar)
	if not targetPart or not targetPart.Parent then return false end

	local myChar = self.player.Character
	if not myChar then return false end
	local myHead = myChar:FindFirstChild("Head")
	if not myHead then return false end

	local origin = myHead.Position
	local targetPos = targetPart.Position
	local dir = targetPos - origin
	local dist = dir.Magnitude

	if dist < 0.5 then return true end
	if dist > self.MAX_DISTANCE then return false end
	if targetPart.Size.Magnitude < 0.1 then return false end
	if targetPart.Transparency >= 1 then return false end

	self._rayParams.FilterDescendantsInstances = {myChar}
	local result = self.Workspace:Raycast(origin, dir, self._rayParams)

	if not result then return true end
	if result.Instance and result.Instance:IsDescendantOf(targetChar) then
		return true
	end

	return false
end

-- Мульти-точечная проверка хитбокса (центр + 4 края)
function RageModule:IsHitboxVisible(targetPart, targetChar)
	if not targetPart or not targetPart.Parent then return false end

	-- Сначала центр
	if self:IsPartDirectlyVisible(targetPart, targetChar) then
		return true
	end

	local myChar = self.player.Character
	if not myChar then return false end
	local myHead = myChar:FindFirstChild("Head")
	if not myHead then return false end

	local origin = myHead.Position
	local halfSize = targetPart.Size * 0.35

	local offsets = {
		targetPart.CFrame * CFrame.new(halfSize.X, 0, 0),
		targetPart.CFrame * CFrame.new(-halfSize.X, 0, 0),
		targetPart.CFrame * CFrame.new(0, halfSize.Y, 0),
		targetPart.CFrame * CFrame.new(0, -halfSize.Y, 0),
	}

	self._rayParams.FilterDescendantsInstances = {myChar}

	for _, offsetCF in ipairs(offsets) do
		local targetPos = offsetCF.Position
		local dir = targetPos - origin

		local result = self.Workspace:Raycast(origin, dir, self._rayParams)

		if not result then return true end
		if result.Instance and result.Instance:IsDescendantOf(targetChar) then
			return true
		end
	end

	return false
end

-- Обратная совместимость — старые вызовы IsPartVisible
function RageModule:IsPartVisible(targetPart, targetChar)
	return self:IsHitboxVisible(targetPart, targetChar)
end

-- ============================================
-- PREDICTION — УЛУЧШЕННЫЙ (из Enhancer)
-- С acceleration tracking и dynamic multiplier
-- ============================================
function RageModule:PredictPosition(part, rootPart, targetPlayer, predStrength)
	local strength = predStrength or self.PREDICTION_STRENGTH

	if not self.PREDICTION_ENABLED or not rootPart then
		return part.Position
	end

	local velocity = rootPart.AssemblyLinearVelocity or rootPart.Velocity or Vector3.new()
	if velocity.Magnitude < 2 then return part.Position end

	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local distance = (part.Position - self.Workspace.CurrentCamera.CFrame.Position).Magnitude
	local travelTime = distance / self.BULLET_SPEED
	local pingTime = self.ping / 2
	local dynamicTime = math.clamp(pingTime + travelTime, 0.05, 0.3)

	local predMultiplier = strength

	-- Динамический множитель по скорости
	if velocity.Magnitude > 20 then
		predMultiplier = predMultiplier * 1.4
	elseif velocity.Magnitude > 15 then
		predMultiplier = predMultiplier * 1.2
	end

	-- Динамический множитель по дистанции
	if distance > 150 then
		predMultiplier = predMultiplier * 1.3
	elseif distance > 100 then
		predMultiplier = predMultiplier * 1.15
	end

	-- Acceleration tracking
	local acceleration = Vector3.zero
	if targetPlayer then
		local trackData = self._velocityTracking[targetPlayer]
		if trackData and trackData.time then
			local timeDiff = tick() - trackData.time
			if timeDiff > 0 and timeDiff < 0.5 then
				acceleration = (velocity - trackData.velocity) / timeDiff
				if trackData.acceleration then
					acceleration = trackData.acceleration:Lerp(acceleration, 0.6)
				end
			end
		end
		self._velocityTracking[targetPlayer] = {
			velocity = velocity,
			time = tick(),
			acceleration = acceleration
		}
	end

	local predictedPos = part.Position + (horizontalVelocity * dynamicTime * predMultiplier)

	-- Учёт ускорения
	if acceleration.Magnitude > 5 then
		predictedPos = predictedPos + (acceleration * dynamicTime * dynamicTime * 0.6)
	end

	return predictedPos
end

-- ============================================
-- TARGET SYSTEM
-- ============================================
function RageModule:CalculatePotentialDamage(partName, distance)
	local multiplier = self.BODY_PART_MULTIPLIERS[partName] or 0.5
	local damage = self.BASE_DAMAGE * multiplier
	if distance > 300 then
		damage = damage * 0.3
	elseif distance > 200 then
		damage = damage * 0.5
	elseif distance > 100 then
		damage = damage * 0.8
	end
	return math.floor(damage)
end

function RageModule:UpdateActivePlayersList()
	table.clear(self.activePlayers)
	for _, targetPlayer in ipairs(self.Players:GetPlayers()) do
		if targetPlayer ~= self.player and self:IsEnemy(targetPlayer) then
			local targetChar = targetPlayer.Character
			if targetChar then
				local hum = targetChar:FindFirstChild("Humanoid")
				local rootPart = targetChar:FindFirstChild("HumanoidRootPart")
				if hum and hum.Health > 0 and rootPart then
					table.insert(self.activePlayers, {
						player = targetPlayer,
						character = targetChar,
						humanoid = hum,
						rootPart = rootPart
					})
				end
			end
		end
	end
end

-- Улучшенный поиск цели с scoring (из Enhancer)
function RageModule:FindTarget(airshotMode)
	if not self:IsAlive() then return nil end

	local char = self.player.Character
	local myHead = char and char:FindFirstChild("Head")
	if not myHead then return nil end

	local myPos = myHead.Position

	local now = tick()
	if now - self.lastPlayerListUpdate >= self.PLAYER_LIST_UPDATE_RATE then
		self.lastPlayerListUpdate = now
		self:UpdateActivePlayersList()
	end

	local bestTarget = nil
	local bestScore = -math.huge

	for _, data in ipairs(self.activePlayers) do
		if not data.humanoid or data.humanoid.Health <= 0 then continue end
		if not data.rootPart or not data.rootPart.Parent then continue end

		local dist = (data.rootPart.Position - myPos).Magnitude
		if dist > self.MAX_DISTANCE then continue end

		local head = data.character:FindFirstChild("Head")
		if not head then continue end
		if head.Size.Magnitude < 0.5 or head.Transparency >= 1 then continue end

		-- Определяем нужные части в зависимости от режима
		local checkParts
		if airshotMode then
			if self.AIRSHOT_HITPART == "Head" then
				checkParts = {"Head"}
			elseif self.AIRSHOT_HITPART == "Body" then
				checkParts = {"UpperTorso", "Torso", "HumanoidRootPart"}
			elseif self.AIRSHOT_HITPART == "Arms" then
				checkParts = {"RightUpperArm", "LeftUpperArm", "Right Arm", "Left Arm"}
			elseif self.AIRSHOT_HITPART == "Legs" then
				checkParts = {"RightUpperLeg", "LeftUpperLeg", "Right Leg", "Left Leg"}
			else
				checkParts = {"Head", "UpperTorso", "HumanoidRootPart"}
			end
		elseif self.MIN_DAMAGE_ENABLED then
			-- Min damage mode — ищем часть с нужным уроном
			local foundPart = nil
			for _, priorityGroup in ipairs(self.MIN_DAMAGE_PRIORITY) do
				for _, partName in ipairs(priorityGroup.parts) do
					local p = data.character:FindFirstChild(partName)
					if p then
						local dmg = self:CalculatePotentialDamage(partName, dist)
						if dmg >= self.MIN_DAMAGE_VALUE and self:IsHitboxVisible(p, data.character) then
							foundPart = p
							break
						end
					end
				end
				if foundPart then break end
			end
			if not foundPart then continue end

			local vel = data.rootPart.AssemblyLinearVelocity or data.rootPart.Velocity or Vector3.zero
			local score = 0
			score = score + math.max(0, 1000 - dist) / 8
			local healthPercent = data.humanoid.Health / data.humanoid.MaxHealth
			score = score + (1 - healthPercent) * 80
			score = score + math.max(0, 35 - vel.Magnitude) * 2.5

			if score > bestScore then
				bestScore = score
				bestTarget = {
					player = data.player,
					character = data.character,
					targetPart = foundPart,
					rootPart = data.rootPart,
					distance = dist
				}
			end
			continue
		else
			-- Обычный rage режим — используем RAGE_HITPART
			if self.RAGE_HITPART == "Head" then
				checkParts = {"Head", "UpperTorso", "Torso", "HumanoidRootPart"}
			elseif self.RAGE_HITPART == "Body" then
				checkParts = {"UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart", "Head"}
			elseif self.RAGE_HITPART == "Arms" then
				checkParts = {"RightUpperArm", "LeftUpperArm", "Right Arm", "Left Arm", "UpperTorso", "Torso"}
			elseif self.RAGE_HITPART == "Legs" then
				checkParts = {"RightUpperLeg", "LeftUpperLeg", "Right Leg", "Left Leg", "LowerTorso", "Torso"}
			else
				checkParts = {"Head", "UpperTorso", "Torso", "HumanoidRootPart"}
			end
		end

		-- Ищем первую видимую часть
		local visiblePart = nil
		for _, partName in ipairs(checkParts) do
			local p = data.character:FindFirstChild(partName)
			if p and self:IsHitboxVisible(p, data.character) then
				visiblePart = p
				break
			end
		end

		if not visiblePart then continue end

		-- Для airshot Head — только если голова видна
		if airshotMode and self.AIRSHOT_HITPART == "Head" then
			if not self:IsHitboxVisible(head, data.character) then
				continue
			end
		end

		-- Финальная проверка видимости
		if not self:IsHitboxVisible(visiblePart, data.character) then continue end

		-- Scoring
		local vel = data.rootPart.AssemblyLinearVelocity or data.rootPart.Velocity or Vector3.zero
		local score = 0
		score = score + math.max(0, 1000 - dist) / 8

		local healthPercent = data.humanoid.Health / data.humanoid.MaxHealth
		score = score + (1 - healthPercent) * 80
		score = score + math.max(0, 35 - vel.Magnitude) * 2.5

		local dirToTarget = (data.rootPart.Position - myPos).Unit
		local lookDir = self.Workspace.CurrentCamera.CFrame.LookVector
		local dot = math.clamp(dirToTarget:Dot(lookDir), -1, 1)
		local angle = math.acos(dot)
		score = score + (math.pi - angle) * 25

		if visiblePart.Name == "Head" then
			score = score + 40
		end

		if score > bestScore then
			bestScore = score
			bestTarget = {
				player = data.player,
				character = data.character,
				targetPart = visiblePart,
				rootPart = data.rootPart,
				distance = dist
			}
		end
	end

	return bestTarget
end

-- ============================================
-- FIRE WEAPON — улучшенный с lead + recoil comp
-- ============================================
function RageModule:FireWeapon(gun, targetPos, target)
	local char = self.player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return false end

	-- Финальная проверка видимости перед выстрелом
	if not self:IsHitboxVisible(target.targetPart, target.character) then
		return false
	end

	if gun.type == "AWP" then
		local origin = head.Position
		local dirVec = targetPos - origin
		if dirVec.Magnitude < 0.01 then return false end
		local direction = dirVec.Unit

		-- Lead adjustment для быстрых целей
		local velocity = target.rootPart.AssemblyLinearVelocity or target.rootPart.Velocity or Vector3.zero
		if velocity.Magnitude > 8 then
			local distance = dirVec.Magnitude
			local leadFactor = 0.08
			if distance > 150 then leadFactor = leadFactor * 1.3
			elseif distance > 100 then leadFactor = leadFactor * 1.15 end
			if velocity.Magnitude > 20 then leadFactor = leadFactor * 1.2 end
			direction = (direction + velocity.Unit * leadFactor).Unit
		end

		-- Компенсация гравитации
		direction = (direction + Vector3.new(0, -0.002, 0)).Unit

		local ok = pcall(function()
			gun.fireShot:FireServer(origin, direction, target.targetPart)
		end)

		if ok then
			task.defer(function()
				if self.Visuals then
					self.Visuals:CreateTracer(origin, targetPos)
				end
			end)
		end

		return ok

	elseif gun.type == "CastRay" then
		if not gun.hole or not gun.hole.Parent then return false end
		local origin = gun.hole.Position
		local dirVec = targetPos - origin
		if dirVec.Magnitude < 0.01 then return false end
		local direction = dirVec.Unit

		local velocity = target.rootPart.AssemblyLinearVelocity or target.rootPart.Velocity or Vector3.zero
		if velocity.Magnitude > 8 then
			local distance = dirVec.Magnitude
			local leadFactor = 0.08
			if distance > 150 then leadFactor = leadFactor * 1.3
			elseif distance > 100 then leadFactor = leadFactor * 1.15 end
			if velocity.Magnitude > 20 then leadFactor = leadFactor * 1.2 end
			direction = (direction + velocity.Unit * leadFactor).Unit
		end

		direction = (direction + Vector3.new(0, -0.002, 0)).Unit
		local ray = Ray.new(origin, direction * 1000)

		local ok = pcall(function()
			gun.castRay:FireServer(ray, targetPos, target.player, target.targetPart)
		end)

		if ok then
			task.defer(function()
				if self.Visuals then
					self.Visuals:CreateTracer(origin, targetPos)
				end
			end)
		end

		return ok
	end

	return false
end

-- ============================================
-- AIRSHOT — перенесён из Enhancer
-- ============================================
function RageModule:DoAirshot()
	if not self.AIRSHOT_ENABLED then return end
	if not self:IsAlive() then return end
	if not self:IsInAir() then return end

	local now = tick()
	if now - self._lastAirshotFire < self.AIRSHOT_FIRE_RATE then return end

	local gun = self:GetGun()
	if not gun then return end

	local target = self:FindTarget(true) -- airshotMode = true
	if not target then return end

	local targetPos
	if self.AIRSHOT_PREDICTION then
		targetPos = self:PredictPosition(
			target.targetPart,
			target.rootPart,
			target.player,
			self.AIRSHOT_PRED_STRENGTH
		)
	else
		targetPos = target.targetPart.Position
	end

	if self:FireWeapon(gun, targetPos, target) then
		self._lastAirshotFire = now
	end
end

-- ============================================
-- DOUBLE TAP — перенесён из Enhancer
-- ============================================
function RageModule:DoDoubleTap()
	if not self.DT_ENABLED then return end
	if not self:IsAlive() then return end
	if self:IsInAir() then return end -- airshot обрабатывает воздух

	local now = tick()
	if now - self._dtLastUse < self.DT_COOLDOWN then return end

	local gun = self:GetGun()
	if not gun then return end

	local target = self:FindTarget(false)
	if not target then return end
	if target.distance > self.DT_MAX_RANGE then return end

	-- Обязательно видимость
	if not self:IsHitboxVisible(target.targetPart, target.character) then return end

	local char = self.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	self._dtLastUse = now

	local originalCF = hrp.CFrame
	local dir = target.rootPart.Position - hrp.Position
	local dist = dir.Magnitude
	local tpDist = math.clamp(self.DT_TP_DIST, 0, dist * 0.5)
	local didTP = false

	-- TP только если путь чист
	if tpDist > 2 then
		self._rayParams.FilterDescendantsInstances = {char}
		local result = self.Workspace:Raycast(originalCF.Position, dir.Unit * tpDist, self._rayParams)

		if not result or result.Instance:IsDescendantOf(target.character) then
			hrp.CFrame = originalCF + dir.Unit * tpDist
			didTP = true
			task.wait()
		end
	end

	-- Выстрел 1 — проверка после TP
	if not self:IsHitboxVisible(target.targetPart, target.character) then
		if didTP and hrp and hrp.Parent then
			hrp.CFrame = originalCF
		end
		return
	end

	local targetPos = self:PredictPosition(
		target.targetPart,
		target.rootPart,
		target.player,
		self.PREDICTION_STRENGTH
	)
	self:FireWeapon(gun, targetPos, target)

	task.wait(0.06)

	if not self:IsAlive() then return end

	-- Выстрел 2 — проверка снова
	if not self:IsHitboxVisible(target.targetPart, target.character) then return end

	local tPos = self:PredictPosition(
		target.targetPart,
		target.rootPart,
		target.player,
		self.PREDICTION_STRENGTH
	)
	self:FireWeapon(gun, tPos, target)

	-- Остаёмся на позиции TP (не возвращаемся)
end

-- ============================================
-- AUTO SHOOT — независимый, максимально быстрый
-- ============================================
function RageModule:DoAutoShoot(gun, currentTime)
	if not self.RAGE_AUTOSHOOT then return end

	-- Определяем fire rate динамически по типу оружия
	-- AUTOSHOOT_ALWAYS_MAX = стреляем настолько быстро, насколько позволяет сервер
	local effectiveFireRate
	if self.AUTOSHOOT_ALWAYS_MAX then
		effectiveFireRate = 0.01 -- почти без ограничений, сервер сам задроттлит
	else
		effectiveFireRate = gun.fireRate
	end

	if currentTime - self._autoShootLastFire < effectiveFireRate then return end

	local target = self:FindTarget(false)
	if not target then return end

	if self.RAGE_HITCHANCE_ENABLED then
		local roll = math.random(1, 100)
		if roll > self.RAGE_HITCHANCE then return end
	end

	local targetPos = self:PredictPosition(
		target.targetPart,
		target.rootPart,
		target.player,
		self.PREDICTION_STRENGTH
	)

	if self:FireWeapon(gun, targetPos, target) then
		self._autoShootLastFire = currentTime
		self.lastShot = currentTime -- обратная совместимость
	end
end

-- ============================================
-- EQUIP SSG
-- ============================================
function RageModule:EquipSSGOnce()
	if not self.AUTO_EQUIP_SSG then return end
	if self.autoEquippedOnce then return end

	local char = self.player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local currentTool = char:FindFirstChildOfClass("Tool")
	if currentTool and currentTool.Name == "SSG-08" then
		self.autoEquippedOnce = true
		return
	end

	local backpack = self.player:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	local tool = backpack:FindFirstChild("SSG-08")
	if tool and tool:IsA("Tool") then
		hum:EquipTool(tool)
		self.autoEquippedOnce = true
		self.Notification:Notify({
			Title = "Auto Equip",
			Content = "Equipped SSG-08",
			Duration = 2,
			Icon = "check"
		})
	end
end

-- ============================================
-- MAIN LOOP
-- ============================================
function RageModule:Start()
	self.player.CharacterAdded:Connect(function()
		self.autoEquippedOnce = false
		table.clear(self._velocityTracking)
	end)

	self.RunService.Heartbeat:Connect(function()
		self:EquipSSGOnce()

		if not self:IsAlive() then return end

		local currentTime = tick()

		-- Обновляем ping
		if currentTime - self.lastPingUpdate >= self.PING_UPDATE_RATE then
			self.lastPingUpdate = currentTime
			self.ping = self.player:GetNetworkPing()
		end

		local inAir = self:IsInAir()

		-- AIRSHOT — работает всегда когда включён и в воздухе
		if inAir then
			if self.AIRSHOT_ENABLED then
				self:DoAirshot()
			end
			-- Если rage enabled + nospread — airshot обрабатывается выше
			-- Если rage autoshoot — не стреляем в воздухе (если не nospread)
			if self.RAGE_ENABLED and not self.RAGE_NOSPREAD then
				return -- в воздухе без nospread — пропускаем rage
			end
		end

		if not self.RAGE_ENABLED then return end

		local gun = self:GetGun()
		if not gun then return end

		-- DOUBLE TAP — на земле
		if self.DT_ENABLED and not inAir then
			self:DoDoubleTap()
		end

		-- AUTO SHOOT — максимально быстрый
		if self.RAGE_AUTOSHOOT then
			self:DoAutoShoot(gun, currentTime)
		end
	end)
end

-- ============================================
-- SETTERS
-- ============================================
function RageModule:SetEnabled(value)
	self.RAGE_ENABLED = value
end

function RageModule:SetHitpart(value)
	self.RAGE_HITPART = value
end

function RageModule:SetHitchance(value)
	self.RAGE_HITCHANCE = value
end

function RageModule:SetHitchanceEnabled(value)
	self.RAGE_HITCHANCE_ENABLED = value
end

function RageModule:SetAutoShoot(value)
	self.RAGE_AUTOSHOOT = value
end

function RageModule:SetNoSpread(value)
	self.RAGE_NOSPREAD = value
end

function RageModule:SetAutoEquipSSG(value)
	self.AUTO_EQUIP_SSG = value
end

function RageModule:SetMaxDistance(value)
	self.MAX_DISTANCE = value
end

function RageModule:SetPredictionEnabled(value)
	self.PREDICTION_ENABLED = value
end

function RageModule:SetPredictionStrength(value)
	self.PREDICTION_STRENGTH = value
end

function RageModule:SetMinDamageEnabled(value)
	self.MIN_DAMAGE_ENABLED = value
	if value then
		self.Notification:Notify({
			Title = "MinDamage",
			Content = "Enabled - Will target lower damage body parts",
			Icon = "info",
			Duration = 3
		})
	end
end

function RageModule:SetMinDamageValue(value)
	self.MIN_DAMAGE_VALUE = value
end

-- Новые сеттеры для Airshot
function RageModule:SetAirshotEnabled(value)
	self.AIRSHOT_ENABLED = value
end

function RageModule:SetAirshotHitpart(value)
	self.AIRSHOT_HITPART = value
end

function RageModule:SetAirshotPrediction(value)
	self.AIRSHOT_PREDICTION = value
end

function RageModule:SetAirshotPredStrength(value)
	self.AIRSHOT_PRED_STRENGTH = value
end

function RageModule:SetAirshotFireRate(value)
	self.AIRSHOT_FIRE_RATE = value
end

-- Новые сеттеры для Double Tap
function RageModule:SetDTEnabled(value)
	self.DT_ENABLED = value
end

function RageModule:SetDTTpDist(value)
	self.DT_TP_DIST = value
end

function RageModule:SetDTCooldown(value)
	self.DT_COOLDOWN = value
end

function RageModule:SetDTMaxRange(value)
	self.DT_MAX_RANGE = value
end

-- Autoshoot max speed
function RageModule:SetAutoShootAlwaysMax(value)
	self.AUTOSHOOT_ALWAYS_MAX = value
end

-- ============================================
-- CONFIG FUNCTIONS
-- ============================================
function RageModule:GetSettings()
	return {
		-- Rage
		RAGE_ENABLED = self.RAGE_ENABLED,
		RAGE_HITPART = self.RAGE_HITPART,
		RAGE_HITCHANCE = self.RAGE_HITCHANCE,
		RAGE_HITCHANCE_ENABLED = self.RAGE_HITCHANCE_ENABLED,
		RAGE_AUTOSHOOT = self.RAGE_AUTOSHOOT,
		RAGE_NOSPREAD = self.RAGE_NOSPREAD,
		AUTO_EQUIP_SSG = self.AUTO_EQUIP_SSG,
		MAX_DISTANCE = self.MAX_DISTANCE,
		PREDICTION_ENABLED = self.PREDICTION_ENABLED,
		PREDICTION_STRENGTH = self.PREDICTION_STRENGTH,
		MIN_DAMAGE_ENABLED = self.MIN_DAMAGE_ENABLED,
		MIN_DAMAGE_VALUE = self.MIN_DAMAGE_VALUE,
		-- Airshot
		AIRSHOT_ENABLED = self.AIRSHOT_ENABLED,
		AIRSHOT_HITPART = self.AIRSHOT_HITPART,
		AIRSHOT_PREDICTION = self.AIRSHOT_PREDICTION,
		AIRSHOT_PRED_STRENGTH = self.AIRSHOT_PRED_STRENGTH,
		AIRSHOT_FIRE_RATE = self.AIRSHOT_FIRE_RATE,
		-- Double Tap
		DT_ENABLED = self.DT_ENABLED,
		DT_TP_DIST = self.DT_TP_DIST,
		DT_COOLDOWN = self.DT_COOLDOWN,
		DT_MAX_RANGE = self.DT_MAX_RANGE,
		-- AutoShoot
		AUTOSHOOT_ALWAYS_MAX = self.AUTOSHOOT_ALWAYS_MAX,
	}
end

function RageModule:ApplySettings(settings)
	if not settings then return end

	-- Rage
	if settings.RAGE_ENABLED ~= nil then self:SetEnabled(settings.RAGE_ENABLED) end
	if settings.RAGE_HITPART ~= nil then self:SetHitpart(settings.RAGE_HITPART) end
	if settings.RAGE_HITCHANCE ~= nil then self:SetHitchance(settings.RAGE_HITCHANCE) end
	if settings.RAGE_HITCHANCE_ENABLED ~= nil then self:SetHitchanceEnabled(settings.RAGE_HITCHANCE_ENABLED) end
	if settings.RAGE_AUTOSHOOT ~= nil then self:SetAutoShoot(settings.RAGE_AUTOSHOOT) end
	if settings.RAGE_NOSPREAD ~= nil then self:SetNoSpread(settings.RAGE_NOSPREAD) end
	if settings.AUTO_EQUIP_SSG ~= nil then self:SetAutoEquipSSG(settings.AUTO_EQUIP_SSG) end
	if settings.MAX_DISTANCE ~= nil then self:SetMaxDistance(settings.MAX_DISTANCE) end
	if settings.PREDICTION_ENABLED ~= nil then self:SetPredictionEnabled(settings.PREDICTION_ENABLED) end
	if settings.PREDICTION_STRENGTH ~= nil then self:SetPredictionStrength(settings.PREDICTION_STRENGTH) end
	if settings.MIN_DAMAGE_ENABLED ~= nil then self:SetMinDamageEnabled(settings.MIN_DAMAGE_ENABLED) end
	if settings.MIN_DAMAGE_VALUE ~= nil then self:SetMinDamageValue(settings.MIN_DAMAGE_VALUE) end
	-- Airshot
	if settings.AIRSHOT_ENABLED ~= nil then self:SetAirshotEnabled(settings.AIRSHOT_ENABLED) end
	if settings.AIRSHOT_HITPART ~= nil then self:SetAirshotHitpart(settings.AIRSHOT_HITPART) end
	if settings.AIRSHOT_PREDICTION ~= nil then self:SetAirshotPrediction(settings.AIRSHOT_PREDICTION) end
	if settings.AIRSHOT_PRED_STRENGTH ~= nil then self:SetAirshotPredStrength(settings.AIRSHOT_PRED_STRENGTH) end
	if settings.AIRSHOT_FIRE_RATE ~= nil then self:SetAirshotFireRate(settings.AIRSHOT_FIRE_RATE) end
	-- Double Tap
	if settings.DT_ENABLED ~= nil then self:SetDTEnabled(settings.DT_ENABLED) end
	if settings.DT_TP_DIST ~= nil then self:SetDTTpDist(settings.DT_TP_DIST) end
	if settings.DT_COOLDOWN ~= nil then self:SetDTCooldown(settings.DT_COOLDOWN) end
	if settings.DT_MAX_RANGE ~= nil then self:SetDTMaxRange(settings.DT_MAX_RANGE) end
	-- AutoShoot
	if settings.AUTOSHOOT_ALWAYS_MAX ~= nil then self:SetAutoShootAlwaysMax(settings.AUTOSHOOT_ALWAYS_MAX) end
end

return RageModule