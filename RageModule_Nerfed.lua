-- RAGE MODULE (Nerfed Wallbang Version)
local RageModule = {}
RageModule.__index = RageModule

function RageModule.new(config)
	local self = setmetatable({}, RageModule)

	self.player = config.Player
	self.Players = config.Services.Players
	self.RunService = config.Services.RunService
	self.Workspace = config.Services.Workspace
	self.ReplicatedStorage = config.Services.ReplicatedStorage
	self.Notification = config.Notification
	self.Visuals = config.Visuals

	self.RAGE_ENABLED = false
	self.RAGE_HITPART = "Head"
	self.RAGE_HITCHANCE = 0
	self.RAGE_HITCHANCE_ENABLED = false
	self.RAGE_AUTOSHOOT = false
	self.RAGE_NOSPREAD = false
	self.AIRSHOT_ACTIVE = false
	self.AUTO_EQUIP_SSG = false
	self.MAX_DISTANCE = 2000

	self.PREDICTION_ENABLED = true
	self.PREDICTION_STRENGTH = 3.5
	self.BULLET_SPEED = 800
	
	self._velocityTracking = {}
	self._targetHistory = {}
	self._lastTargetSwitch = 0
	self.TARGET_SWITCH_DELAY = 0.5

	self.MIN_DAMAGE_ENABLED = false
	self.MIN_DAMAGE_VALUE = 0
	self.BASE_DAMAGE = 54

	self.DOUBLETAP_ENABLED = false
	self.DOUBLETAP_MODE = "Aggressive"
	self.DOUBLETAP_TELEPORT = true
	self.DOUBLETAP_MAX_TP_DIST = 15
	self.dtLastUse = 0
	self.DT_COOLDOWN = 1.5
	self.DT_MAXDIST_OVERRIDE = false

	self.OVERRIDE_TARGET_ENABLED = false
	self.OVERRIDE_TARGET_LIST = {}

	self.REMOVE_HEAD_ENABLED = false
	self._removeHeadTrack = nil
	self._removeHeadAnimObj = nil
	self._removeHeadCharConn = nil
	self._removeHeadNoclipConn = nil
	self._cachedBypassAnimId = nil
	
	self.FREESTAND_ENABLED = false
	self._freestandConn = nil
	self._freestandLastUpdate = 0

	self.RAPIDFIRE_ENABLED = false
	self.RAPIDFIRE_SHOTS = 10
	self.RAPIDFIRE_MODE = "Automatic"
	self.RAPIDFIRE_REEQUIP = true
	self.RAPIDFIRE_CYCLE_DELAY = 0.03
	self._rfLoopActive = false
	self._rfSteppedConn = nil
	self._rfRenderConn = nil

	self.NO_TP_WALLBANG_ENABLED = false
	
	-- ═══════════════════════════════════════════════════
	-- WALLBANG NERF SETTINGS (NEW)
	-- ═══════════════════════════════════════════════════
	self.WALLBANG_MAX_DISTANCE = 60  -- Max distance through walls (studs)
	self.WALLBANG_MAX_WALLS = 1      -- Max number of walls to penetrate
	self.WALLBANG_MAX_THICKNESS = 6  -- Max total wall thickness (studs)
	self.WALLBANG_REQUIRE_PARTIAL_VISIBILITY = true -- Need to see some part of target
	-- ═══════════════════════════════════════════════════

	self.lastShot = 0
	self.FIRE_RATE = 0.04
	self.FIRE_RATE_AWP = 0.9
	self.ping = 0
	self.lastPingUpdate = 0
	self.PING_UPDATE_RATE = 1
	self.activePlayers = {}
	self.lastPlayerListUpdate = 0
	self.PLAYER_LIST_UPDATE_RATE = 0.25
	self.autoEquippedOnce = false

	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self._rayParams.IgnoreWater = true

	self._cachedGun = nil
	self._cachedGunTick = 0
	self._GUN_CACHE_RATE = 0.15

	self._lastHeartbeat = 0
	self._HEARTBEAT_INTERVAL = 1 / 144

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

	self._VISIBILITY_FAST = {"Head", "UpperTorso", "HumanoidRootPart"}

	return self
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================
function RageModule:GetEffectiveMaxDist()
	if self.DT_MAXDIST_OVERRIDE and self.DOUBLETAP_ENABLED then
		return 99999
	end
	return self.MAX_DISTANCE
end

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

	if hum.FloorMaterial == Enum.Material.Air then
		return true
	end

	if math.abs(hrp.AssemblyLinearVelocity.Y) > 2 then
		return true
	end

	return false
end

function RageModule:GetGun()
	local now = tick()
	if self._cachedGun and (now - self._cachedGunTick) < self._GUN_CACHE_RATE then
		if self._cachedGun.type == "AWP" and self._cachedGun.fireShot and self._cachedGun.fireShot.Parent then
			return self._cachedGun
		elseif self._cachedGun.type == "CastRay" and self._cachedGun.castRay and self._cachedGun.castRay.Parent
			and self._cachedGun.hole and self._cachedGun.hole.Parent then
			return self._cachedGun
		end
		self._cachedGun = nil
	end

	local char = self.player.Character
	if not char then
		self._cachedGun = nil
		return nil
	end

	for _, item in pairs(char:GetChildren()) do
		if item:IsA("Tool") then
			local remotes = item:FindFirstChild("Remotes")
			if remotes then
				local fireShot = remotes:FindFirstChild("FireShot")
				if fireShot then
					self._cachedGun = {type = "AWP", fireShot = fireShot, fireRate = self.FIRE_RATE_AWP}
					self._cachedGunTick = now
					return self._cachedGun
				end

				local castRay = remotes:FindFirstChild("CastRay")
				local hole = item:FindFirstChild("Hole")
				if castRay and hole then
					self._cachedGun = {type = "CastRay", castRay = castRay, hole = hole, fireRate = self.FIRE_RATE}
					self._cachedGunTick = now
					return self._cachedGun
				end
			end
		end
	end

	self._cachedGun = nil
	return nil
end

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

function RageModule:GetBestVisiblePart(char, distance)
	local priorities

	if self.RAGE_HITPART == "Head" then
		priorities = {"Head", "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart"}
	elseif self.RAGE_HITPART == "Body" then
		priorities = {"UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart", "Head"}
	elseif self.RAGE_HITPART == "Arms" then
		priorities = {"RightUpperArm", "LeftUpperArm", "Right Arm", "Left Arm", "UpperTorso", "Torso"}
	elseif self.RAGE_HITPART == "Legs" then
		priorities = {"RightUpperLeg", "LeftUpperLeg", "Right Leg", "Left Leg", "LowerTorso", "Torso"}
	else
		priorities = {"Head", "UpperTorso", "Torso", "HumanoidRootPart"}
	end

	for _, partName in ipairs(priorities) do
		local part = char:FindFirstChild(partName)
		if part and self:IsPartVisible(part, char) then
			return part
		end
	end

	return nil
end

function RageModule:GetTargetPart(char, distance)
	if self.AIRSHOT_ACTIVE then
		local head = char:FindFirstChild("Head")
		if head and head.Size.Magnitude > 0.5 and head.Transparency < 1 then
			return head
		end
		return nil
	end

	if self.MIN_DAMAGE_ENABLED then
		for _, priorityGroup in ipairs(self.MIN_DAMAGE_PRIORITY) do
			for _, partName in ipairs(priorityGroup.parts) do
				local part = char:FindFirstChild(partName)
				if part and part.Size.Magnitude > 0.1 and part.Transparency < 1 then
					local damage = self:CalculatePotentialDamage(partName, distance)
					if damage >= self.MIN_DAMAGE_VALUE then
						return part
					end
				end
			end
		end
		return nil
	end

	if self.RAGE_HITPART == "Head" then
		local head = char:FindFirstChild("Head")
		if head and head.Size.Magnitude > 0.5 and head.Transparency < 1 then
			return head
		end
		return nil
	end
	if self.RAGE_HITPART == "Body" then
		return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	end
	if self.RAGE_HITPART == "Arms" then
		return char:FindFirstChild("RightUpperArm") or char:FindFirstChild("LeftUpperArm") or char:FindFirstChild("Right Arm") or char:FindFirstChild("Left Arm")
	end
	if self.RAGE_HITPART == "Legs" then
		return char:FindFirstChild("RightUpperLeg") or char:FindFirstChild("LeftUpperLeg") or char:FindFirstChild("Right Leg") or char:FindFirstChild("Left Leg")
	end
	
	local head = char:FindFirstChild("Head")
	if head and head.Size.Magnitude > 0.5 and head.Transparency < 1 then
		return head
	end
	return char:FindFirstChild("HumanoidRootPart")
end

-- ═══════════════════════════════════════════════════
-- NERFED WALLBANG SYSTEM
-- ═══════════════════════════════════════════════════
function RageModule:IsPartVisible(targetPart, targetChar)
	if not targetPart or not targetPart.Parent then return false end

	local myChar = self.player.Character
	if not myChar then return false end
	local myHead = myChar:FindFirstChild("Head")
	local myHrp = myChar:FindFirstChild("HumanoidRootPart")
	if not myHead or not myHrp then return false end

	local origin = myHead.Position
	local targetPos = targetPart.Position
	local dir = targetPos - origin
	local dist = dir.Magnitude

	if dist < 0.1 then return true end
	if dist > self:GetEffectiveMaxDist() then return false end
	
	if targetPart.Size.Magnitude < 0.1 or targetPart.Transparency >= 1 then
		return false
	end

	self._rayParams.FilterDescendantsInstances = {myChar}

	local unit = dir.Unit
	local curOrigin = origin
	
	-- ═══════════════════════════════════════════════════
	-- WALLBANG MODE: NO TP WALLBANG (old unlimited penetration)
	-- ═══════════════════════════════════════════════════
	if self.NO_TP_WALLBANG_ENABLED then
		for _ = 1, 50 do
			local res = self.Workspace:Raycast(curOrigin, targetPos - curOrigin, self._rayParams)
			
			if not res then return true end
			
			local hit = res.Instance
			
			if hit and hit:IsDescendantOf(targetChar) then
				return true
			end
			
			if hit then
				curOrigin = res.Position + unit * 0.2
				continue
			end
			
			return false
		end
		return false
	end
	
	-- ═══════════════════════════════════════════════════
	-- NERFED WALLBANG SYSTEM (NEW)
	-- ═══════════════════════════════════════════════════
	
	-- Step 1: Check distance limit through walls
	if dist > self.WALLBANG_MAX_DISTANCE then
		-- Too far to wallbang, check direct line of sight only
		local directCheck = self.Workspace:Raycast(origin, dir, self._rayParams)
		if not directCheck then
			return true -- Direct LOS, no walls
		end
		if directCheck.Instance and directCheck.Instance:IsDescendantOf(targetChar) then
			return true -- Direct hit on target
		end
		return false -- Too far and blocked by wall
	end
	
	-- Step 2: Count walls and measure total thickness
	local wallCount = 0
	local totalThickness = 0
	local hasPartialVisibility = false
	
	-- Check if we can see ANY part of the target (partial visibility)
	if self.WALLBANG_REQUIRE_PARTIAL_VISIBILITY then
		local partsToCheck = {"Head", "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart", 
		                       "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg"}
		
		for _, partName in ipairs(partsToCheck) do
			local part = targetChar:FindFirstChild(partName)
			if part then
				local partDir = part.Position - origin
				local partCheck = self.Workspace:Raycast(origin, partDir, self._rayParams)
				
				if not partCheck then
					hasPartialVisibility = true
					break
				end
				
				if partCheck.Instance and partCheck.Instance:IsDescendantOf(targetChar) then
					hasPartialVisibility = true
					break
				end
			end
		end
		
		-- If we can't see ANY part of target, don't allow wallbang
		if not hasPartialVisibility then
			return false
		end
	end
	
	-- Step 3: Trace through walls and count penetrations
	for iteration = 1, 20 do
		local res = self.Workspace:Raycast(curOrigin, targetPos - curOrigin, self._rayParams)

		if not res then 
			-- Reached target without hitting more walls
			return wallCount <= self.WALLBANG_MAX_WALLS and totalThickness <= self.WALLBANG_MAX_THICKNESS
		end

		local hit = res.Instance

		if hit and hit:IsDescendantOf(targetChar) then
			-- Hit the target
			return wallCount <= self.WALLBANG_MAX_WALLS and totalThickness <= self.WALLBANG_MAX_THICKNESS
		end

		if hit then
			local name = hit.Name:lower()
			
			-- Always allow penetration through game objects (hamik, paletka)
			local isGameObject = name:find("hamik") or name:find("paletka")
			
			-- Always allow penetration through soft/transparent objects
			local isSoft = hit.Transparency > 0.3 or hit.CanCollide == false or hit.CanQuery == false
			
			if isGameObject or isSoft then
				curOrigin = res.Position + unit * 0.2
				continue
			end
			
			-- This is a WALL - count it and measure thickness
			wallCount = wallCount + 1
			
			-- Check if we exceeded wall count limit
			if wallCount > self.WALLBANG_MAX_WALLS then
				return false -- Too many walls
			end
			
			-- Measure wall thickness by raycasting through it
			local throughWallStart = res.Position + unit * 0.1
			local maxThicknessCheck = 15 -- Max thickness to check
			
			local throughWallResult = self.Workspace:Raycast(
				throughWallStart,
				unit * maxThicknessCheck,
				self._rayParams
			)
			
			if throughWallResult then
				local wallThickness = (throughWallResult.Position - res.Position).Magnitude
				totalThickness = totalThickness + wallThickness
				
				-- Check if total thickness exceeded limit
				if totalThickness > self.WALLBANG_MAX_THICKNESS then
					return false -- Walls too thick
				end
				
				-- Continue from exit point of wall
				curOrigin = throughWallResult.Position + unit * 0.1
			else
				-- Wall is too thick (no exit point found)
				return false
			end
		else
			return false
		end
	end

	return false
end

-- Rest of the functions remain the same...
-- (I'm keeping all other functions exactly as they are)

function RageModule:PredictPosition(part, rootPart, targetPlayer)
	if not self.PREDICTION_ENABLED or not rootPart then return part.Position end

	local velocity = rootPart.AssemblyLinearVelocity or rootPart.Velocity or Vector3.new()
	if velocity.Magnitude < 2 then return part.Position end

	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local distance = (part.Position - self.Workspace.CurrentCamera.CFrame.Position).Magnitude
	local travelTime = distance / self.BULLET_SPEED
	local pingTime = self.ping / 2
	
	local dynamicTime = math.clamp(pingTime + travelTime, 0.05, 0.3)
	
	local predictionMultiplier = self.PREDICTION_STRENGTH
	
	if velocity.Magnitude > 20 then
		predictionMultiplier = predictionMultiplier * 1.4
	elseif velocity.Magnitude > 15 then
		predictionMultiplier = predictionMultiplier * 1.2
	end
	
	if distance > 150 then
		predictionMultiplier = predictionMultiplier * 1.3
	elseif distance > 100 then
		predictionMultiplier = predictionMultiplier * 1.15
	end
	
	local acceleration = Vector3.new(0, 0, 0)
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
	
	local predictedPos = part.Position + (horizontalVelocity * dynamicTime * predictionMultiplier)
	if acceleration.Magnitude > 5 then
		predictedPos = predictedPos + (acceleration * dynamicTime * dynamicTime * 0.6)
	end

	return predictedPos
end

function RageModule:UpdateActivePlayersList()
	table.clear(self.activePlayers)
	local myPos
	local myChar = self.player.Character
	if myChar then
		local h = myChar:FindFirstChild("Head")
		if h then myPos = h.Position end
	end
	local maxDist = self:GetEffectiveMaxDist()

	for _, targetPlayer in ipairs(self.Players:GetPlayers()) do
		if targetPlayer ~= self.player and self:IsEnemy(targetPlayer) then
			local targetChar = targetPlayer.Character
			if targetChar then
				local hum = targetChar:FindFirstChild("Humanoid")
				local rootPart = targetChar:FindFirstChild("HumanoidRootPart")
				local head = targetChar:FindFirstChild("Head")
				
				if hum and hum.Health > 0 and rootPart and head then
					if head.Size.Magnitude > 0.5 and head.Transparency < 1 then
						if myPos and (rootPart.Position - myPos).Magnitude > maxDist then
							continue
						end
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
end

function RageModule:FindTarget()
	if not self:IsAlive() then return nil end

	local char = self.player.Character
	local myHead = char and char:FindFirstChild("Head")
	if not myHead then return nil end

	local now = tick()
	if now - self.lastPlayerListUpdate >= self.PLAYER_LIST_UPDATE_RATE then
		self.lastPlayerListUpdate = now
		self:UpdateActivePlayersList()
	end

	local bestTarget
	local bestScore = -math.huge
	local myPos = myHead.Position

	local filterByOverride = self.DT_MAXDIST_OVERRIDE and self.OVERRIDE_TARGET_ENABLED and #self.OVERRIDE_TARGET_LIST > 0

	local previousTarget = self._targetHistory[1]
	local shouldStickToTarget = previousTarget and (now - self._lastTargetSwitch < self.TARGET_SWITCH_DELAY)

	for _, data in ipairs(self.activePlayers) do
		if not data.humanoid or data.humanoid.Health <= 0 then continue end
		if not data.rootPart or not data.rootPart.Parent then continue end

		if filterByOverride then
			local found = false
			for _, tName in ipairs(self.OVERRIDE_TARGET_LIST) do
				if data.player.Name == tName or data.player.DisplayName == tName then
					found = true
					break
				end
			end
			if not found then continue end
		end

		local dist = (data.rootPart.Position - myPos).Magnitude
		if dist > self:GetEffectiveMaxDist() then continue end

		local part

		if self.AIRSHOT_ACTIVE then
			part = data.character:FindFirstChild("Head")
			if not part or not self:IsPartVisible(part, data.character) then
				continue
			end

		elseif self.MIN_DAMAGE_ENABLED then
			part = nil
			for _, group in ipairs(self.MIN_DAMAGE_PRIORITY) do
				for _, partName in ipairs(group.parts) do
					local p = data.character:FindFirstChild(partName)
					if p then
						local dmg = self:CalculatePotentialDamage(partName, dist)
						if dmg >= self.MIN_DAMAGE_VALUE and self:IsPartVisible(p, data.character) then
							part = p
							break
						end
					end
				end
				if part then break end
			end
			if not part then
				continue
			end

		else
			local visible = false
			for _, partName in ipairs(self._VISIBILITY_FAST) do
				local p = data.character:FindFirstChild(partName)
				if p and self:IsPartVisible(p, data.character) then
					visible = true
					break
				end
			end

			if not visible then
				continue
			end

			part = self:GetTargetPart(data.character, dist) or data.character:FindFirstChild("Head")
			if not part then
				continue
			end
		end

		local score = 0
		
		if shouldStickToTarget and previousTarget == data.player then
			score = score + 150
		end
		
		local distScore = math.max(0, 1000 - dist) / 8
		score = score + distScore
		
		local healthPercent = data.humanoid.Health / data.humanoid.MaxHealth
		local healthScore = (1 - healthPercent) * 80
		score = score + healthScore
		
		local velocity = data.rootPart.AssemblyLinearVelocity or data.rootPart.Velocity or Vector3.new()
		local velocityScore = math.max(0, 35 - velocity.Magnitude) * 2.5
		score = score + velocityScore
		
		local dirToTarget = (data.rootPart.Position - myPos).Unit
		local lookDir = self.Workspace.CurrentCamera.CFrame.LookVector
		local angle = math.acos(math.clamp(dirToTarget:Dot(lookDir), -1, 1))
		local angleScore = (math.pi - angle) * 25
		score = score + angleScore
		
		local head = data.character:FindFirstChild("Head")
		if head and self:IsPartVisible(head, data.character) then
			score = score + 40
		end
		
		local trackData = self._velocityTracking[data.player]
		if trackData and trackData.acceleration then
			local accelMag = trackData.acceleration.Magnitude
			if accelMag < 5 then
				score = score + 30
			end
		end
		
		if dist < 50 then
			if part.Name == "Head" then
				score = score + 50
			end
		elseif dist > 150 then
			if part.Name == "UpperTorso" or part.Name == "Torso" or part.Name == "HumanoidRootPart" then
				score = score + 40
			end
		end

		if score > bestScore then
			bestScore = score
			bestTarget = {
				player = data.player,
				character = data.character,
				targetPart = part,
				rootPart = data.rootPart,
				distance = dist
			}
		end
	end

	if bestTarget and bestTarget.player ~= previousTarget then
		self._lastTargetSwitch = now
		table.insert(self._targetHistory, 1, bestTarget.player)
		if #self._targetHistory > 3 then
			table.remove(self._targetHistory, 4)
		end
	end

	return bestTarget
end

-- [ALL OTHER FUNCTIONS REMAIN EXACTLY THE SAME - I'm keeping the entire rest of the module]
-- Including: EquipSSGOnce, FireWeapon, DoubleTap functions, Rapidfire, Freestand, etc.

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

function RageModule:FireWeapon(gun, targetPos, target)
	local char = self.player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return false end

	if gun.type == "AWP" then
		local origin = head.Position
		local dirVec = targetPos - origin
		if dirVec.Magnitude < 0.01 then return false end
		local direction = dirVec.Unit
		
		local velocity = target.rootPart.AssemblyLinearVelocity or target.rootPart.Velocity or Vector3.new()
		if velocity.Magnitude > 8 then
			local distance = dirVec.Magnitude
			local leadFactor = 0.08
			
			if distance > 150 then
				leadFactor = leadFactor * 1.3
			elseif distance > 100 then
				leadFactor = leadFactor * 1.15
			end
			
			if velocity.Magnitude > 20 then
				leadFactor = leadFactor * 1.2
			end
			
			local leadAdjust = velocity.Unit * leadFactor
			direction = (direction + leadAdjust).Unit
		end
		
		local recoilCompensation = Vector3.new(0, -0.002, 0)
		direction = (direction + recoilCompensation).Unit
		
		local ok = pcall(function()
			gun.fireShot:FireServer(origin, direction, target.targetPart)
		end)
		if ok then
			task.defer(function()
				self.Visuals:CreateTracer(origin, targetPos)
			end)
			return true
		end
		
	elseif gun.type == "CastRay" then
		if not gun.hole or not gun.hole.Parent then return false end
		local origin = gun.hole.Position
		local dirVec = targetPos - origin
		if dirVec.Magnitude < 0.01 then return false end
		local direction = dirVec.Unit
		
		local velocity = target.rootPart.AssemblyLinearVelocity or target.rootPart.Velocity or Vector3.new()
		if velocity.Magnitude > 8 then
			local distance = dirVec.Magnitude
			local leadFactor = 0.08
			
			if distance > 150 then
				leadFactor = leadFactor * 1.3
			elseif distance > 100 then
				leadFactor = leadFactor * 1.15
			end
			
			if velocity.Magnitude > 20 then
				leadFactor = leadFactor * 1.2
			end
			
			local leadAdjust = velocity.Unit * leadFactor
			direction = (direction + leadAdjust).Unit
		end
		
		local recoilCompensation = Vector3.new(0, -0.002, 0)
		direction = (direction + recoilCompensation).Unit
		
		local ray = Ray.new(origin, direction * 1000)
		
		local ok = pcall(function()
			gun.castRay:FireServer(ray, targetPos, target.player, target.targetPart)
		end)
		if ok then
			task.defer(function()
				self.Visuals:CreateTracer(origin, targetPos)
			end)
			return true
		end
	end
	return false
end

function RageModule:FindNearestEnemy()
	if not self:IsAlive() then return nil end
	local char = self.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local now = tick()
	if now - self.lastPlayerListUpdate >= self.PLAYER_LIST_UPDATE_RATE then
		self.lastPlayerListUpdate = now
		self:UpdateActivePlayersList()
	end

	local bestTarget
	local bestDist = self.DT_MAXDIST_OVERRIDE and 99999 or (self.DOUBLETAP_MAX_TP_DIST + 80)

	local filterByOverride = self.DT_MAXDIST_OVERRIDE and self.OVERRIDE_TARGET_ENABLED and #self.OVERRIDE_TARGET_LIST > 0

	for _, data in ipairs(self.activePlayers) do
		if not data.humanoid or data.humanoid.Health <= 0 then continue end
		if not data.rootPart or not data.rootPart.Parent then continue end

		if filterByOverride then
			local found = false
			for _, tName in ipairs(self.OVERRIDE_TARGET_LIST) do
				if data.player.Name == tName or data.player.DisplayName == tName then
					found = true
					break
				end
			end
			if not found then continue end
		end

		local dist = (data.rootPart.Position - hrp.Position).Magnitude
		if dist > bestDist then continue end

		local part = self:GetTargetPart(data.character, dist)
			or data.character:FindFirstChild("Head")
			or data.rootPart
		if not part then continue end

		bestDist = dist
		bestTarget = {
			player = data.player,
			character = data.character,
			targetPart = part,
			rootPart = data.rootPart,
			distance = dist
		}
	end

	return bestTarget
end

function RageModule:DoubleTapFire(gun, target)
	local char = self.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if self.Notification then
		pcall(function()
			self.Notification:Notify({
				title = "Double Tap",
				message = "Aggressive mode activated",
				duration = 1.5,
				type = "info"
			})
		end)
	end

	local originalCF = hrp.CFrame
	local didTP = false

	if self.DOUBLETAP_TELEPORT then
		local dir = target.rootPart.Position - hrp.Position
		local dist = dir.Magnitude
		local tpDist = math.clamp(dist * 0.3, 0, self.DOUBLETAP_MAX_TP_DIST)
		if tpDist > 2 then
			hrp.CFrame = originalCF + dir.Unit * tpDist
			didTP = true
			task.wait()
		end
	end

	local targetPos = self.PREDICTION_ENABLED
		and self:PredictPosition(target.targetPart, target.rootPart, target.player)
		or target.targetPart.Position

	self:FireWeapon(gun, targetPos, target)

	task.wait(0.06)

	if not self:IsAlive() then
		if didTP and hrp and hrp.Parent then hrp.CFrame = originalCF end
		return
	end

	local tPos = self.PREDICTION_ENABLED
		and self:PredictPosition(target.targetPart, target.rootPart, target.player)
		or target.targetPart.Position
	self:FireWeapon(gun, tPos, target)

	if didTP then
		task.wait(0.04)
		if hrp and hrp.Parent then
			hrp.CFrame = originalCF
		end
	end
end

function RageModule:DoubleTapFireLegit(gun, target)
	local char = self.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if self.Notification then
		pcall(function()
			self.Notification:Notify({
				title = "Double Tap",
				message = "Legit mode activated",
				duration = 1.5,
				type = "success"
			})
		end)
	end

	local originalCF = hrp.CFrame

	local dir = target.rootPart.Position - hrp.Position
	local dist = dir.Magnitude
	local tpDist = math.clamp(6.5, 0, dist * 0.5)
	
	if tpDist > 2 then
		local targetPos = originalCF.Position + dir.Unit * tpDist
		
		self._rayParams.FilterDescendantsInstances = {char}
		local result = self.Workspace:Raycast(originalCF.Position, dir.Unit * tpDist, self._rayParams)
		
		if not result or result.Instance:IsDescendantOf(target.character) then
			hrp.CFrame = originalCF + dir.Unit * tpDist
			task.wait()
		end
	end

	local targetPos = self.PREDICTION_ENABLED
		and self:PredictPosition(target.targetPart, target.rootPart, target.player)
		or target.targetPart.Position

	self:FireWeapon(gun, targetPos, target)

	task.wait(0.06)

	if not self:IsAlive() then
		return
	end

	local tPos = self.PREDICTION_ENABLED
		and self:PredictPosition(target.targetPart, target.rootPart, target.player)
		or target.targetPart.Position
	self:FireWeapon(gun, tPos, target)
end

function RageModule:DoubleTapFireAWall(gun, target)
	local char = self.player.Character
	if not char then return end

	local targetPos = self.PREDICTION_ENABLED
		and self:PredictPosition(target.targetPart, target.rootPart, target.player)
		or target.targetPart.Position

	self:FireWeapon(gun, targetPos, target)

	task.wait(0.06)

	if not self:IsAlive() then
		return
	end

	local tPos = self.PREDICTION_ENABLED
		and self:PredictPosition(target.targetPart, target.rootPart, target.player)
		or target.targetPart.Position
	self:FireWeapon(gun, tPos, target)
end

function RageModule:RapidFireBurst(gun, target)
	local char = self.player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return 0 end

	local shots = math.floor(self.RAPIDFIRE_SHOTS)
	local fired = 0
	local predPos

	if gun.type == "AWP" then
		for i = 1, shots do
			if not char.Parent or not head.Parent then break end
			if not target.targetPart or not target.targetPart.Parent then break end

			if i == 1 or i % 4 == 0 then
				predPos = self.PREDICTION_ENABLED
					and self:PredictPosition(target.targetPart, target.rootPart, target.player)
					or target.targetPart.Position
			end
			if not predPos then break end

			local origin = head.Position
			local jitter = Vector3.new(
				(math.random() - 0.5) * 0.005,
				(math.random() - 0.5) * 0.005,
				(math.random() - 0.5) * 0.005
			)
			local dir = predPos - (origin + jitter)
			if dir.Magnitude < 0.01 then continue end

			pcall(function()
				gun.fireShot:FireServer(origin + jitter, dir.Unit, target.targetPart)
			end)
			fired = fired + 1
		end

	elseif gun.type == "CastRay" then
		if not gun.hole or not gun.hole.Parent then return 0 end

		for i = 1, shots do
			if not char.Parent then break end
			if not gun.hole or not gun.hole.Parent then break end
			if not target.targetPart or not target.targetPart.Parent then break end

			if i == 1 or i % 4 == 0 then
				predPos = self.PREDICTION_ENABLED
					and self:PredictPosition(target.targetPart, target.rootPart, target.player)
					or target.targetPart.Position
			end
			if not predPos then break end

			local origin = gun.hole.Position
			local jitter = Vector3.new(
				(math.random() - 0.5) * 0.005,
				(math.random() - 0.5) * 0.005,
				(math.random() - 0.5) * 0.005
			)
			local dir = predPos - (origin + jitter)
			if dir.Magnitude < 0.01 then continue end

			local ray = Ray.new(origin + jitter, dir.Unit * 1000)
			pcall(function()
				gun.castRay:FireServer(ray, predPos, target.player, target.targetPart)
			end)
			fired = fired + 1
		end
	end

	if fired > 0 and predPos then
		task.defer(function()
			local org = gun.type == "AWP" and head.Position
				or (gun.hole and gun.hole.Position)
			if org then
				pcall(function() self.Visuals:CreateTracer(org, predPos) end)
			end
		end)
	end

	return fired
end

function RageModule:ReequipWeapon()
	local char = self.player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local tool = char:FindFirstChildOfClass("Tool")
	if not hum or not tool then return false end

	local ref = tool
	hum:UnequipTools()
	task.wait()
	if ref and ref.Parent and hum and hum.Parent then
		hum:EquipTool(ref)
		self._cachedGun = nil
		return true
	end
	return false
end

function RageModule:RapidFirePump()
	if not self.RAPIDFIRE_ENABLED then return end
	if not self.RAGE_ENABLED or not self:IsAlive() or not self.RAGE_AUTOSHOOT then return end

	local gun = self:GetGun()
	if not gun then return end

	local now = tick()
	if now - self.lastPlayerListUpdate >= self.PLAYER_LIST_UPDATE_RATE then
		self.lastPlayerListUpdate = now
		self:UpdateActivePlayersList()
	end

	local myChar = self.player.Character
	local myHead = myChar and myChar:FindFirstChild("Head")
	if not myHead then return end

	local enemiesShot = 0
	local maxEnemies = 10

	for _, data in ipairs(self.activePlayers) do
		if enemiesShot >= maxEnemies then break end
		
		if not data.humanoid or data.humanoid.Health <= 0 then continue end
		if not data.rootPart or not data.rootPart.Parent then continue end

		local dist = (data.rootPart.Position - myHead.Position).Magnitude
		if dist > self:GetEffectiveMaxDist() then continue end

		local visible = false
		for _, partName in ipairs(self._VISIBILITY_FAST) do
			local p = data.character:FindFirstChild(partName)
			if p and self:IsPartVisible(p, data.character) then
				visible = true
				break
			end
		end

		if not visible then continue end

		local part = self:GetTargetPart(data.character, dist) or data.character:FindFirstChild("Head")
		if not part then continue end

		local target = {
			player = data.player,
			character = data.character,
			targetPart = part,
			rootPart = data.rootPart,
			distance = dist
		}

		self:RapidFireBurst(gun, target)
		enemiesShot = enemiesShot + 1
	end
end

function RageModule:Start()
	self.player.CharacterAdded:Connect(function()
		self.autoEquippedOnce = false
		self._cachedGun = nil
	end)

	self.RunService.Heartbeat:Connect(function()
		self:EquipSSGOnce()

		if not self.RAGE_ENABLED then return end
		if not self:IsAlive() then return end

		local now = tick()
		if now - self._lastHeartbeat < self._HEARTBEAT_INTERVAL then return end
		self._lastHeartbeat = now

		local inAir = self:IsInAir()
		self.AIRSHOT_ACTIVE = self.RAGE_NOSPREAD and inAir

		if self.RAGE_AUTOSHOOT and inAir and not self.RAGE_NOSPREAD then
			return
		end

		local gun = self:GetGun()
		if not gun then return end

		if not self.RAGE_AUTOSHOOT then
			return
		end

		if now - self.lastShot < gun.fireRate then return end

		if now - self.lastPingUpdate >= self.PING_UPDATE_RATE then
			self.lastPingUpdate = now
			self.ping = self.player:GetNetworkPing()
		end

		local target = self:FindTarget()

		if not target and self.DOUBLETAP_ENABLED and self.DOUBLETAP_TELEPORT
			and (now - self.dtLastUse) >= self.DT_COOLDOWN then
			if self.DOUBLETAP_MODE == "Legit" then
				target = nil
			else
				target = self:FindNearestEnemy()
			end
		end

		if not target then return end

		if self.RAGE_HITCHANCE_ENABLED and not self.AIRSHOT_ACTIVE then
			if math.random(1, 100) > self.RAGE_HITCHANCE then
				return
			end
		end

		if self.DOUBLETAP_ENABLED and (now - self.dtLastUse) >= self.DT_COOLDOWN then
			if self.DOUBLETAP_MODE == "Legit" then
				if not self:IsPartVisible(target.targetPart, target.character) then
					return
				end
			end
			
			self.dtLastUse = now
			self.lastShot = now
			task.spawn(function()
				if self.DOUBLETAP_MODE == "Legit" then
					self:DoubleTapFireLegit(gun, target)
				else
					self:DoubleTapFire(gun, target)
				end
			end)
			return
		end

		local char = self.player.Character
		local myHead = char and char:FindFirstChild("Head")

		self.lastShot = now
		
		self:FireWeapon(gun,
			self.PREDICTION_ENABLED
				and self:PredictPosition(target.targetPart, target.rootPart, target.player)
				or target.targetPart.Position,
			target)

		if self.RAPIDFIRE_ENABLED then
			self:RapidFireBurst(gun, target)
		end
	end)

end

function RageModule:SetRapidfireEnabled(value)
	self.RAPIDFIRE_ENABLED = value

	if self._rfSteppedConn then
		self._rfSteppedConn:Disconnect()
		self._rfSteppedConn = nil
	end
	if self._rfRenderConn then
		self._rfRenderConn:Disconnect()
		self._rfRenderConn = nil
	end

	if value then
		self.Notification:Notify({
			Title = "Rapidfire",
			Content = self.RAPIDFIRE_MODE .. " — " .. self.RAPIDFIRE_SHOTS .. " shots/burst",
			Icon = "info",
			Duration = 3
		})

		if not self._rfLoopActive and self.RAPIDFIRE_MODE == "Automatic" then
			self._rfLoopActive = true
			task.spawn(function()
				while self.RAPIDFIRE_ENABLED and self.RAPIDFIRE_MODE == "Automatic" do
					if self.RAGE_ENABLED and self:IsAlive() and self.RAGE_AUTOSHOOT then
						local gun = self:GetGun()
						local target = gun and self:FindTarget()
						if gun and target then
							self:RapidFireBurst(gun, target)
							if self.RAPIDFIRE_REEQUIP then
								self:ReequipWeapon()
							end
						end
					end
					
					local delay = self.RAPIDFIRE_CYCLE_DELAY
					if delay > 0 then
						task.wait(delay)
					else
						task.wait(0.03)
					end
				end
				self._rfLoopActive = false
			end)
		end
	end
end

-- ═══════════════════════════════════════════════════
-- SETTERS (including new wallbang settings)
-- ═══════════════════════════════════════════════════

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

function RageModule:SetDoubleTapEnabled(value)
	self.DOUBLETAP_ENABLED = value
end

function RageModule:SetDoubleTapMode(value)
	self.DOUBLETAP_MODE = value
	if value == "Legit" then
		self.DT_COOLDOWN = 2.0
	else
		self.DT_COOLDOWN = 1.5
	end
end

function RageModule:SetDoubleTapTeleport(value)
	self.DOUBLETAP_TELEPORT = value
end

function RageModule:SetDoubleTapMaxDist(value)
	self.DOUBLETAP_MAX_TP_DIST = value
end

function RageModule:SetDoubleTapCooldown(value)
	self.DT_COOLDOWN = value
end

function RageModule:SetMaxDistOverride(value)
	self.DT_MAXDIST_OVERRIDE = value
end

function RageModule:SetOverrideTargetEnabled(value)
	self.OVERRIDE_TARGET_ENABLED = value
end

function RageModule:SetOverrideTargetList(list)
	self.OVERRIDE_TARGET_LIST = list or {}
end

function RageModule:GetEnemyPlayers()
	local enemies = {}
	for _, p in ipairs(self.Players:GetPlayers()) do
		if p ~= self.player and self:IsEnemy(p) then
			table.insert(enemies, p.DisplayName)
		end
	end
	return enemies
end

-- ═══════════════════════════════════════════════════
-- NEW WALLBANG SETTINGS (can be adjusted in UI)
-- ═══════════════════════════════════════════════════

function RageModule:SetWallbangMaxDistance(value)
	self.WALLBANG_MAX_DISTANCE = value
	if self.Notification then
		self.Notification:Notify({
			title = "Wallbang Distance",
			message = "Max: " .. value .. " studs",
			duration = 2,
			type = "info"
		})
	end
end

function RageModule:SetWallbangMaxWalls(value)
	self.WALLBANG_MAX_WALLS = value
	if self.Notification then
		self.Notification:Notify({
			title = "Wallbang Walls",
			message = "Max walls: " .. value,
			duration = 2,
			type = "info"
		})
	end
end

function RageModule:SetWallbangMaxThickness(value)
	self.WALLBANG_MAX_THICKNESS = value
	if self.Notification then
		self.Notification:Notify({
			title = "Wall Thickness",
			message = "Max: " .. value .. " studs",
			duration = 2,
			type = "info"
		})
	end
end

function RageModule:SetWallbangRequirePartialVisibility(value)
	self.WALLBANG_REQUIRE_PARTIAL_VISIBILITY = value
	if self.Notification then
		self.Notification:Notify({
			title = "Partial Visibility",
			message = value and "Enabled" or "Disabled",
			duration = 2,
			type = "info"
		})
	end
end

-- Anti-aim and other functions remain unchanged
-- [Keeping all Remove Head, Freestand, and other functions exactly as they are]

function RageModule:_resolveAnimationId(assetId)
	if self._cachedBypassAnimId then
		return self._cachedBypassAnimId
	end

	local rawId = "rbxassetid://" .. tostring(assetId)

	pcall(function()
		local ACP = game:GetService("AnimationClipProvider")
		local clip = ACP:GetAnimationClipAsync(rawId)
		if clip then
			self._cachedBypassAnimId = ACP:RegisterAnimationClip(clip)
		end
	end)
	if self._cachedBypassAnimId then return self._cachedBypassAnimId end

	pcall(function()
		local objects = game:GetObjects(rawId)
		if not objects then return end
		for _, obj in ipairs(objects) do
			if obj:IsA("KeyframeSequence") or obj:IsA("CurveAnimation") then
				pcall(function()
					local ACP = game:GetService("AnimationClipProvider")
					self._cachedBypassAnimId = ACP:RegisterAnimationClip(obj)
				end)
				if self._cachedBypassAnimId then return end
			end
			if obj:IsA("Animation") then
				local innerRaw = obj.AnimationId
				pcall(function()
					local ACP = game:GetService("AnimationClipProvider")
					local clip2 = ACP:GetAnimationClipAsync(innerRaw)
					if clip2 then
						self._cachedBypassAnimId = ACP:RegisterAnimationClip(clip2)
					end
				end)
				if self._cachedBypassAnimId then return end
				self._cachedBypassAnimId = innerRaw
				return
			end
			for _, desc in ipairs(obj:GetDescendants()) do
				if desc:IsA("KeyframeSequence") or desc:IsA("CurveAnimation") then
					pcall(function()
						local ACP = game:GetService("AnimationClipProvider")
						self._cachedBypassAnimId = ACP:RegisterAnimationClip(desc)
					end)
					if self._cachedBypassAnimId then return end
				end
				if desc:IsA("Animation") then
					local innerRaw2 = desc.AnimationId
					pcall(function()
						local ACP = game:GetService("AnimationClipProvider")
						local clip3 = ACP:GetAnimationClipAsync(innerRaw2)
						if clip3 then
							self._cachedBypassAnimId = ACP:RegisterAnimationClip(clip3)
						end
					end)
					if self._cachedBypassAnimId then return end
					self._cachedBypassAnimId = innerRaw2
					return
				end
			end
		end
	end)
	if self._cachedBypassAnimId then return self._cachedBypassAnimId end

	self._cachedBypassAnimId = rawId
	return rawId
end

function RageModule:_startRemoveHead()
	self:_stopRemoveHead()

	local char = self.player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local animId = self:_resolveAnimationId(98193399505416)

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	self._removeHeadAnimObj = anim

	local track
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		local ok, t = pcall(function() return animator:LoadAnimation(anim) end)
		if ok then track = t end
	end
	if not track then
		local ok2, t2 = pcall(function() return hum:LoadAnimation(anim) end)
		if ok2 then track = t2 end
	end

	if not track then
		warn("[Arcanum] Remove Head: all animation methods failed")
		return
	end

	self._removeHeadTrack = track
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action4
	track:Play()

	self._removeHeadNoclipConn = self.RunService.Stepped:Connect(function()
		local c = self.player.Character
		if not c then return end
		for _, part in ipairs(c:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)
end

function RageModule:_stopRemoveHead()
	if self._removeHeadNoclipConn then
		self._removeHeadNoclipConn:Disconnect()
		self._removeHeadNoclipConn = nil
	end
	if self._removeHeadTrack then
		pcall(function() self._removeHeadTrack:Stop() end)
		pcall(function() self._removeHeadTrack:Destroy() end)
		self._removeHeadTrack = nil
	end
	if self._removeHeadAnimObj then
		pcall(function() self._removeHeadAnimObj:Destroy() end)
		self._removeHeadAnimObj = nil
	end
end

function RageModule:SetRemoveHeadEnabled(value)
	self.REMOVE_HEAD_ENABLED = value

	if self._removeHeadCharConn then
		self._removeHeadCharConn:Disconnect()
		self._removeHeadCharConn = nil
	end

	if value then
		self:_startRemoveHead()
		self._removeHeadCharConn = self.player.CharacterAdded:Connect(function()
			task.wait(0.5)
			if self.REMOVE_HEAD_ENABLED then
				self:_startRemoveHead()
			end
		end)
	else
		self:_stopRemoveHead()
	end
end

function RageModule:_findClosestEnemy()
	local char = self.player.Character
	if not char then return nil end
	
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	
	local myPos = hrp.Position
	local closestEnemy = nil
	local closestDist = math.huge
	
	for _, p in ipairs(game.Players:GetPlayers()) do
		if p ~= self.player and p.Team ~= self.player.Team and p.Character then
			local enemyHrp = p.Character:FindFirstChild("HumanoidRootPart")
			if enemyHrp then
				local dist = (myPos - enemyHrp.Position).Magnitude
				if dist < closestDist and dist <= 200 then
					closestDist = dist
					closestEnemy = p
				end
			end
		end
	end
	
	return closestEnemy, closestDist
end

function RageModule:_applyBodyTilt(tiltAngle1, tiltAngle2)
	local RS = game:GetService("ReplicatedStorage")
	local aahelp1 = RS:FindFirstChild("aahelp1")
	
	if aahelp1 and aahelp1:IsA("RemoteEvent") then
		pcall(function()
			aahelp1:FireServer("apply", tiltAngle1, tiltAngle2)
		end)
	end
end

function RageModule:_resetBodyTilt()
	local RS = game:GetService("ReplicatedStorage")
	local aahelp1 = RS:FindFirstChild("aahelp1")
	
	if aahelp1 and aahelp1:IsA("RemoteEvent") then
		pcall(function()
			aahelp1:FireServer("reset")
		end)
	end
end

function RageModule:_enableAntiAim()
	local RS = game:GetService("ReplicatedStorage")
	local aahelp1 = RS:FindFirstChild("aahelp1")
	
	if aahelp1 and aahelp1:IsA("RemoteEvent") then
		pcall(function()
			aahelp1:FireServer("enable")
		end)
	end
end

function RageModule:_disableAntiAim()
	local RS = game:GetService("ReplicatedStorage")
	local aahelp1 = RS:FindFirstChild("aahelp1")
	
	if aahelp1 and aahelp1:IsA("RemoteEvent") then
		pcall(function()
			aahelp1:FireServer("disable")
		end)
	end
end

function RageModule:_findBestFreestandAngle()
	local char = self.player.Character
	if not char then return nil, 0, 0 end
	
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	if not hrp or not head then return nil, 0, 0 end
	
	local myPos = hrp.Position
	local headPos = head.Position
	
	local closestEnemy, enemyDist = self:_findClosestEnemy()
	
	if not closestEnemy or not closestEnemy.Character then
		return nil, 0, 0
	end
	
	local enemyHrp = closestEnemy.Character:FindFirstChild("HumanoidRootPart")
	if not enemyHrp then return nil, 0, 0 end
	
	local enemyPos = enemyHrp.Position
	
	local dirToEnemy = (enemyPos - myPos)
	dirToEnemy = Vector3.new(dirToEnemy.X, 0, dirToEnemy.Z).Unit
	
	local bestAngle = nil
	local bestScore = -math.huge
	local bestTilt1 = 0
	local bestTilt2 = 0
	
	local checkAngles = {-90, -67.5, -45, -22.5, 0, 22.5, 45, 67.5, 90}
	
	for _, angleOffset in ipairs(checkAngles) do
		local checkAngle = math.rad(angleOffset)
		
		local checkDir = Vector3.new(
			dirToEnemy.X * math.cos(checkAngle) - dirToEnemy.Z * math.sin(checkAngle),
			0,
			dirToEnemy.X * math.sin(checkAngle) + dirToEnemy.Z * math.cos(checkAngle)
		)
		
		local rayOrigin = headPos
		local rayDistance = 20
		
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {char}
		raycastParams.IgnoreWater = true
		
		local wallResult = self.Workspace:Raycast(rayOrigin, checkDir * rayDistance, raycastParams)
		local wallDist = wallResult and wallResult.Distance or rayDistance
		
		local score = 0
		
		if wallDist < 15 then
			score = score + (15 - wallDist) * 10
		end
		
		local angleToEnemy = math.abs(angleOffset)
		if angleToEnemy > 45 and angleToEnemy < 135 then
			score = score + 50
		end
		
		if wallResult then
			local enemyToHeadDir = (headPos - enemyPos).Unit
			local losRaycast = self.Workspace:Raycast(enemyPos, enemyToHeadDir * enemyDist, raycastParams)
			
			if losRaycast and losRaycast.Instance then
				score = score + 100
			end
		end
		
		if score > bestScore then
			bestScore = score
			bestAngle = checkAngle
			
			if angleOffset < -45 then
				bestTilt1 = -70
				bestTilt2 = 70
			elseif angleOffset > 45 then
				bestTilt1 = 70
				bestTilt2 = -70
			else
				bestTilt1 = -30
				bestTilt2 = 30
			end
		end
	end
	
	if bestAngle == nil then
		bestAngle = 0
		bestTilt1 = -30
		bestTilt2 = 30
	end
	
	local finalAngle = bestAngle + math.pi
	
	local finalDir = Vector3.new(
		dirToEnemy.X * math.cos(finalAngle) - dirToEnemy.Z * math.sin(finalAngle),
		0,
		dirToEnemy.X * math.sin(finalAngle) + dirToEnemy.Z * math.cos(finalAngle)
	)
	
	local targetCFrame = CFrame.lookAt(myPos, myPos + finalDir)
	
	return targetCFrame, bestTilt1, bestTilt2
end

function RageModule:_startFreestand()
	if self._freestandConn then return end
	
	self:_enableAntiAim()
	
	self._freestandConn = self.RunService.RenderStepped:Connect(function()
		local now = tick()
		
		if now - self._freestandLastUpdate < 0.1 then return end
		self._freestandLastUpdate = now
		
		local char = self.player.Character
		if not char then return end
		
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		
		local targetCFrame, tiltAngle1, tiltAngle2 = self:_findBestFreestandAngle()
		
		if not targetCFrame then 
			self:_resetBodyTilt()
			return 
		end
		
		local currentCFrame = hrp.CFrame
		local currentPos = currentCFrame.Position
		
		local _, targetY, _ = targetCFrame:ToEulerAnglesYXZ()
		
		local newCFrame = CFrame.new(currentPos) * CFrame.Angles(0, targetY, 0)
		
		hrp.CFrame = currentCFrame:Lerp(newCFrame, 0.2)
		
		self:_applyBodyTilt(tiltAngle1, tiltAngle2)
	end)
end

function RageModule:_stopFreestand()
	if self._freestandConn then
		self._freestandConn:Disconnect()
		self._freestandConn = nil
	end
	
	self:_resetBodyTilt()
	self:_disableAntiAim()
end

function RageModule:SetFreestandEnabled(value)
	self.FREESTAND_ENABLED = value
	
	if value then
		self:_startFreestand()
	else
		self:_stopFreestand()
	end
end

function RageModule:SetRapidfireShots(value)
	self.RAPIDFIRE_SHOTS = value
end

function RageModule:SetRapidfireMode(value)
	self.RAPIDFIRE_MODE = value
	if self.RAPIDFIRE_ENABLED then
		self:SetRapidfireEnabled(false)
		task.defer(function()
			self:SetRapidfireEnabled(true)
		end)
	end
end

function RageModule:SetRapidfireReequip(value)
	self.RAPIDFIRE_REEQUIP = value
end

function RageModule:SetRapidfireCycleDelay(value)
	self.RAPIDFIRE_CYCLE_DELAY = value
end

function RageModule:SetNoTPWallbangEnabled(value)
	self.NO_TP_WALLBANG_ENABLED = value
	if value then
		self.Notification:Notify({
			title = "No TP Wallbang",
			message = "Infinite penetration enabled",
			duration = 3,
			type = "success"
		})
	end
end

function RageModule:GetSettings()
	return {
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
		DOUBLETAP_ENABLED = self.DOUBLETAP_ENABLED,
		DOUBLETAP_TELEPORT = self.DOUBLETAP_TELEPORT,
		DOUBLETAP_MAX_TP_DIST = self.DOUBLETAP_MAX_TP_DIST,
		DT_COOLDOWN = self.DT_COOLDOWN,
		RAPIDFIRE_ENABLED = self.RAPIDFIRE_ENABLED,
		RAPIDFIRE_SHOTS = self.RAPIDFIRE_SHOTS,
		RAPIDFIRE_MODE = self.RAPIDFIRE_MODE,
		RAPIDFIRE_REEQUIP = self.RAPIDFIRE_REEQUIP,
		RAPIDFIRE_CYCLE_DELAY = self.RAPIDFIRE_CYCLE_DELAY,
		NO_TP_WALLBANG_ENABLED = self.NO_TP_WALLBANG_ENABLED,
		WALLBANG_MAX_DISTANCE = self.WALLBANG_MAX_DISTANCE,
		WALLBANG_MAX_WALLS = self.WALLBANG_MAX_WALLS,
		WALLBANG_MAX_THICKNESS = self.WALLBANG_MAX_THICKNESS,
		WALLBANG_REQUIRE_PARTIAL_VISIBILITY = self.WALLBANG_REQUIRE_PARTIAL_VISIBILITY,
	}
end

function RageModule:ApplySettings(settings)
	if not settings then return end

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
	if settings.DOUBLETAP_ENABLED ~= nil then self:SetDoubleTapEnabled(settings.DOUBLETAP_ENABLED) end
	if settings.DOUBLETAP_TELEPORT ~= nil then self:SetDoubleTapTeleport(settings.DOUBLETAP_TELEPORT) end
	if settings.DOUBLETAP_MAX_TP_DIST ~= nil then self:SetDoubleTapMaxDist(settings.DOUBLETAP_MAX_TP_DIST) end
	if settings.DT_COOLDOWN ~= nil then self:SetDoubleTapCooldown(settings.DT_COOLDOWN) end
	if settings.RAPIDFIRE_MODE ~= nil then self:SetRapidfireMode(settings.RAPIDFIRE_MODE) end
	if settings.RAPIDFIRE_REEQUIP ~= nil then self:SetRapidfireReequip(settings.RAPIDFIRE_REEQUIP) end
	if settings.RAPIDFIRE_CYCLE_DELAY ~= nil then self:SetRapidfireCycleDelay(settings.RAPIDFIRE_CYCLE_DELAY) end
	if settings.RAPIDFIRE_SHOTS ~= nil then self:SetRapidfireShots(settings.RAPIDFIRE_SHOTS) end
	if settings.RAPIDFIRE_ENABLED ~= nil then self:SetRapidfireEnabled(settings.RAPIDFIRE_ENABLED) end
	if settings.NO_TP_WALLBANG_ENABLED ~= nil then self:SetNoTPWallbangEnabled(settings.NO_TP_WALLBANG_ENABLED) end
	if settings.WALLBANG_MAX_DISTANCE ~= nil then self:SetWallbangMaxDistance(settings.WALLBANG_MAX_DISTANCE) end
	if settings.WALLBANG_MAX_WALLS ~= nil then self:SetWallbangMaxWalls(settings.WALLBANG_MAX_WALLS) end
	if settings.WALLBANG_MAX_THICKNESS ~= nil then self:SetWallbangMaxThickness(settings.WALLBANG_MAX_THICKNESS) end
	if settings.WALLBANG_REQUIRE_PARTIAL_VISIBILITY ~= nil then self:SetWallbangRequirePartialVisibility(settings.WALLBANG_REQUIRE_PARTIAL_VISIBILITY) end
end

return RageModule
