--!strict

-- COPYRIGHT 2023 Zach Curtis
-- Distrubted under the MIT License
-- VERSION 0.3.3

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bullet = require(script:WaitForChild("Bullet"))
local Signal = require(script:WaitForChild("Signal"))

export type ShouldFireCallback = (shooter: Player?, barrelPosition: Vector3, velocity: Vector3, ping: number, easyBulletSettings: Bullet.EasyBulletSettings?) -> boolean
export type ShouldFireArrayCallback = (shooter: Player?, bullets: { [number]: { BarrelPosition: Vector3, Velocity: Vector3, EasyBulletSettings: Bullet.EasyBulletSettings } }, ping: number) -> boolean

type EasyBulletProps = {
	EasyBulletSettings: Bullet.EasyBulletSettings,

	BulletHit: Signal.Signal<Player?, RaycastResult, Bullet.BulletData>,
	BulletHitHumanoid: Signal.Signal<Player?, RaycastResult, Humanoid, Bullet.BulletData>,
	BulletUpdated: Signal.Signal<Vector3, Vector3, Bullet.BulletData>,

	Bullets: {[string]: Bullet.Bullet},
	HitConnections: {[string]: Signal.SignalConnection},
	BelowFallenPartsConnections: {[string]: Signal.SignalConnection},

	FiredRemote: RemoteEvent?,
    FiredBatchRemote: RemoteEvent?,
	CanceledRemote: RemoteEvent?,

	CustomCastCallback: Bullet.CastCallback?, --(Player?, Vector3, Vector3, number, Bullet.BulletData) -> ()?,
    ShouldFireCallback: ShouldFireCallback?,
    ShouldFireArrayCallback: ShouldFireArrayCallback?,
}

type EasyBulletMethods = {
	FireBullet: (self: EasyBullet, barrelPosition: Vector3, bulletVelocity: Vector3, easyBulletSettings: Bullet.EasyBulletSettings?) -> (),
    FireBullets: (self: EasyBullet, bullets: { [number]: { Velocity: Vector3, BarrelPosition: Vector3?, Settings: Bullet.EasyBulletSettings? } }) -> (),
	BindCustomCast: (self: EasyBullet, callback: Bullet.CastCallback) -> (),
	BindShouldFire: (self: EasyBullet, callback: ShouldFireCallback) -> (),
    BindShouldFireArray: (self: EasyBullet, callback: ShouldFireArrayCallback) -> (),
    _fireBullet: (self: EasyBullet, shootingPlayer: Player?, barrelPos: Vector3, velocity: Vector3, ping: number, easyBulletSettings: Bullet.EasyBulletSettings?, skipShouldFire: boolean?) -> (),
    _fireBullets: (self: EasyBullet, shootingPlayer: Player?, bullets: { [number]: { BarrelPosition: Vector3, Velocity: Vector3, EasyBulletSettings: Bullet.EasyBulletSettings } }, ping: number) -> (),
	_bindEvents: () -> (),
}

local function optionalTableMerge(optionalTable: Bullet.EasyBulletSettings, nonOptionalTable: Bullet.EasyBulletSettings): Bullet.EasyBulletSettings
	for key, value in pairs(nonOptionalTable) do
		if optionalTable[key] == nil then
			optionalTable[key] = value
		end
	end

	return optionalTable :: Bullet.EasyBulletSettings
end

local function overrideDefaults(newEasyBulletSettings: Bullet.EasyBulletSettings | {})
	local defaultSettings = {
		Gravity = true,
		RenderBullet = true,
		BulletColor = Color3.new(0.945098, 0.490196, 0.062745),
		BulletThickness = .1,
		FilterList = {},
		FilterType = Enum.RaycastFilterType.Exclude,
		BulletPartProps = {},
		BulletData = {}
	}

	for key, value in pairs(newEasyBulletSettings) do
		if defaultSettings[key] == nil then
			warn(`{key} does not exist in type EasyBulletSettings`)
			continue
		end

		if key == "BulletData" then
			for dataKey, _ in pairs(value) do
				assert(dataKey ~= "HitVelocity", `Cannot use key "HitVelocity" in provided BulletData table. "HitVelocity" is a reserved key string used by EasyBullet`)
				assert(dataKey ~= "BulletId", `Cannot use key "BulletId" in provided BulletData table. "BulletId" is a reserved key string used by EasyBullet`)
			end
		end

		defaultSettings[key] = value
	end

	return defaultSettings
end



-- Make a deep copy of a table to avoid shared mutations between shots


local constructedEasyBullet

local EasyBullet = {}
EasyBullet.__index = EasyBullet

export type EasyBullet = typeof(setmetatable({} :: EasyBulletProps,  EasyBullet))

function EasyBullet.new(easyBulletSettings: Bullet.EasyBulletSettings?)
	if constructedEasyBullet then
		return constructedEasyBullet
	end

	local self = setmetatable({} :: EasyBulletProps, EasyBullet)

	self.EasyBulletSettings = overrideDefaults(easyBulletSettings or {})

	self.BulletHit = Signal.new()
	self.BulletHitHumanoid = Signal.new()
	self.BulletUpdated = Signal.new()

	self.Bullets = {} :: {[string]: Bullet.Bullet}
	self.HitConnections = {} :: {[string]: Signal.SignalConnection}
	self.BelowFallenPartsConnections = {} :: {[string]: Signal.SignalConnection}

	self.FiredRemote = nil
    self.FiredBatchRemote = nil
	self.CanceledRemote = nil

	self.CustomCastCallback = nil
	self.ShouldFireCallback = nil
    self.ShouldFireArrayCallback = nil

	self:_bindEvents()

	constructedEasyBullet = self

	return self
end

function EasyBullet:FireBullet(barrelPosition: Vector3, bulletVelocity: Vector3, easyBulletSettings: Bullet.EasyBulletSettings?)
	assert(barrelPosition, `EasyBullet:FireBullet requires 2 parameters: a Vector3 position to start the bullet from, and a Velocity Vector3 of the direction to fire the bullet, with a magnitude of the initial velocity`)
	assert(bulletVelocity, `EasyBullet:FireBullet requires 2 parameters: a Vector3 position to start the bullet from, and a Velocity Vector3 of the direction to fire the bullet, with a magnitude of the initial velocity`)

	assert(typeof(barrelPosition) == "Vector3", "The first parameter to EasyBullet:FireBullet must be a Vector3")
	assert(typeof(bulletVelocity) == "Vector3", "The second parameter to EasyBullet:FireBullet must be a Vector3")

    -- Create a per-shot copy of settings to prevent shared table mutations across bullets
    local providedSettings = table.clone(easyBulletSettings or {} :: Bullet.EasyBulletSettings)
    local thisEasyBulletSettings = optionalTableMerge(providedSettings, self.EasyBulletSettings)

    -- Ensure nested tables are not shared references
    thisEasyBulletSettings.BulletData = table.clone(thisEasyBulletSettings.BulletData or {})
    thisEasyBulletSettings.BulletPartProps = table.clone(thisEasyBulletSettings.BulletPartProps or {})

    local origFilterList = thisEasyBulletSettings.FilterList or {}
    local newFilterList = table.create(#origFilterList)
    for i = 1, #origFilterList do
        newFilterList[i] = origFilterList[i]
    end
    thisEasyBulletSettings.FilterList = newFilterList

	-- Create a UUID linked to this bullet so it can be referenced over the network later
	local bulletId = HttpService:GenerateGUID()

	thisEasyBulletSettings.BulletData.BulletId = bulletId

	-- Server; only used for non player bullets.
	if RunService:IsServer() then
		for _, v in ipairs(Players:GetPlayers()) do
			local thisPing = v:GetNetworkPing()
			self.FiredRemote:FireClient(v, nil, barrelPosition, bulletVelocity, thisPing, thisEasyBulletSettings)
		end

        self:_fireBullet(nil, barrelPosition, bulletVelocity, 0, thisEasyBulletSettings, false)

	-- Client
	elseif RunService:IsClient() then
		if not self.FiredRemote then
			warn("EasyBullet Remote Event doesn't exist. Did you forget to call EasyBullet.new() on the server?")
			return
		end

		self.FiredRemote:FireServer(barrelPosition, bulletVelocity, thisEasyBulletSettings)

        self:_fireBullet(Players.LocalPlayer, barrelPosition, bulletVelocity, 0, thisEasyBulletSettings, false)
	end
end

function EasyBullet:FireBullets(bullets: { [number]: { Velocity: Vector3, BarrelPosition: Vector3?, Settings: Bullet.EasyBulletSettings? } })
    assert(bullets and #bullets > 0, "EasyBullet:FireBullets requires a non-empty array of bullets")

    local resolvedBullets = {} :: { [number]: { BarrelPosition: Vector3, Velocity: Vector3, EasyBulletSettings: Bullet.EasyBulletSettings } }

    for i, b in ipairs(bullets) do
        assert(typeof(b.Velocity) == "Vector3", `Bullet at index {i} missing Velocity: Vector3`)

        local barrelPos = b.BarrelPosition or Vector3.zero

        local providedSettings = table.clone(b.Settings or {} :: Bullet.EasyBulletSettings)
        local thisSettings = optionalTableMerge(providedSettings, self.EasyBulletSettings)
        thisSettings.BulletData = table.clone(thisSettings.BulletData or {})
        thisSettings.BulletPartProps = table.clone(thisSettings.BulletPartProps or {})

        local origFilterList = thisSettings.FilterList or {}
        local newFilterList = table.create(#origFilterList)
        for j = 1, #origFilterList do
            newFilterList[j] = origFilterList[j]
        end
        thisSettings.FilterList = newFilterList

        local bulletId = HttpService:GenerateGUID()
        thisSettings.BulletData.BulletId = bulletId

        table.insert(resolvedBullets, {
            BarrelPosition = barrelPos,
            Velocity = b.Velocity,
            EasyBulletSettings = thisSettings,
        })
    end

    if RunService:IsServer() then
        -- group-level gate on server if provided
        if self.ShouldFireArrayCallback then
            local shouldFire = self.ShouldFireArrayCallback(nil, resolvedBullets, 0)
            assert(type(shouldFire) == "boolean", `The callback bound by EasyBullet:BindShouldFireArray must return a boolean, returned: {typeof(shouldFire)}`)
            if shouldFire == false then
                return
            end
        end
        for _, v in ipairs(Players:GetPlayers()) do
            local thisPing = v:GetNetworkPing()
            self.FiredBatchRemote:FireClient(v, nil, resolvedBullets, thisPing)
        end

        self:_fireBullets(nil, resolvedBullets, 0)

    elseif RunService:IsClient() then
        if not self.FiredBatchRemote then
            warn("EasyBullet FiredBatch Remote doesn't exist. Did you forget to call EasyBullet.new() on the server?")
            return
        end

        local shooter = Players.LocalPlayer

        if self.ShouldFireArrayCallback then
            local shouldFire = self.ShouldFireArrayCallback(shooter, resolvedBullets, 0)
            assert(type(shouldFire) == "boolean", `The callback bound by EasyBullet:BindShouldFireArray must return a boolean, returned: {typeof(shouldFire)}`)
            if shouldFire == false then
                return
            end
        end

        self.FiredBatchRemote:FireServer(resolvedBullets)
        self:_fireBullets(shooter, resolvedBullets, 0)
    end
end

function EasyBullet:BindCustomCast(callback: Bullet.CastCallback)
	assert(typeof(callback) == "function", `The callback passed to EasyBullet:BindCustomCast must be a function. Passed type is {typeof(callback)}`)

	self.CustomCastCallback = callback
end

function EasyBullet:BindShouldFire(callback: ShouldFireCallback)
	assert(typeof(callback) == "function", `The callback passed to EasyBullet:BindShouldFire must be a function. Passed type is {typeof(callback)}`)

	self.ShouldFireCallback = callback
end

function EasyBullet:BindShouldFireArray(callback: ShouldFireArrayCallback)
    assert(typeof(callback) == "function", `The callback passed to EasyBullet:BindShouldFireArray must be a function. Passed type is {typeof(callback)}`)

    self.ShouldFireArrayCallback = callback
end

function EasyBullet:_destroyBullet(bulletToDestroy: Bullet.Bullet | string)
	local bulletId: string
	local bullet: Bullet.Bullet

	if type(bulletToDestroy) == "string" then
		bulletId = bulletToDestroy
		bullet = self.Bullets[bulletId]
	else
		local tryBulletId = bulletToDestroy.EasyBulletSettings.BulletData.BulletId
		assert(type(tryBulletId) == "string", "Cannot destroy bullet as EasyBullet did not assign a BulletId for this bullet.")

		bulletId = tryBulletId
		bullet = bulletToDestroy
	end

	self.Bullets[bulletId] = nil

	if self.HitConnections[bulletId] ~= nil then
		self.HitConnections[bulletId].Disconnect()

		self.HitConnections[bulletId] = nil
	end

	if self.BelowFallenPartsConnections[bulletId] ~= nil then
		self.BelowFallenPartsConnections[bulletId].Disconnect()

		self.BelowFallenPartsConnections[bulletId] = nil
	end

	-- Obscure bug most likely caused by external library caused this to nil member error
	if bullet then
		bullet:Destroy()
	end
end

function EasyBullet._fireBullet(self: EasyBullet, shootingPlayer: Player?, barrelPos: Vector3, velocity: Vector3, ping: number, easyBulletSettings: Bullet.EasyBulletSettings, skipShouldFire: boolean?)

	local bulletId = easyBulletSettings.BulletData.BulletId
	assert(type(bulletId) == "string", "EasyBullet did not assign a BulletId for this bullet.")

	-- Let users filter bullets being fired
    if not skipShouldFire and self.ShouldFireCallback then
		local shouldFire = self.ShouldFireCallback(shootingPlayer, barrelPos, velocity, ping, easyBulletSettings)

		assert(type(shouldFire) == "boolean", `The callback bound by EasyBullet:BindShouldFire must return a boolean, shouldFireCallback returned: {typeof(shouldFire)}`)

		if shouldFire == false then

			assert(self.CanceledRemote ~= nil, "self.CanceledRemote does not reference ReplicatedStorage.EasyBulletCanceled")

            if RunService:IsServer() then
				self.CanceledRemote:FireAllClients(bulletId)
			elseif RunService:IsClient() then
				self.CanceledRemote:FireServer(bulletId)
			end

			return
		end
	end

	local bullet = Bullet.new(shootingPlayer, barrelPos, velocity, easyBulletSettings)

	self.HitConnections[bulletId] = bullet.BulletHit:Connect(function(rayResult: RaycastResult, hitHumanoid: Humanoid | boolean)
		self.BulletHit:Fire(shootingPlayer, rayResult, easyBulletSettings.BulletData)

		if type(hitHumanoid) ~= "boolean" then
			self.BulletHitHumanoid:Fire(shootingPlayer, rayResult, hitHumanoid, easyBulletSettings.BulletData)
		end

		self:_destroyBullet(bullet)
	end)

	self.BelowFallenPartsConnections[bulletId] = bullet.BelowFallenParts:Connect(function()
		self:_destroyBullet(bullet)
	end)

	bullet:Start(ping)

	self.Bullets[bulletId] = bullet
end

function EasyBullet._fireBullets(self: EasyBullet, shootingPlayer: Player?, bullets: { [number]: { BarrelPosition: Vector3, Velocity: Vector3, EasyBulletSettings: Bullet.EasyBulletSettings } }, ping: number)
    for _, b in ipairs(bullets) do
        self:_fireBullet(shootingPlayer, b.BarrelPosition, b.Velocity, ping, b.EasyBulletSettings, true)
    end
end

function EasyBullet:_bindEvents()
	-- Server
	if RunService:IsServer() then

		-- Look for existing EasyBulletFired RemoteEvent. Create one if it does not exist.
		self.FiredRemote = self:_findOrCreateRemote("EasyBulletFired")
		self.FiredBatchRemote = self:_findOrCreateRemote("EasyBulletFiredBatch")
		assert(self.FiredRemote ~= nil, "self.FiredRemote cannot be nil.")
		assert(self.FiredBatchRemote ~= nil, "self.FiredBatchRemote cannot be nil.")

		self.FiredRemote.OnServerEvent:Connect(function(player: Player, barrelPos: Vector3, velocity: Vector3, easyBulletSettings: Bullet.EasyBulletSettings)
			-- Sanity check params
			if typeof(barrelPos) ~= "Vector3" then
				warn(`{player.Name} passed a malformed barrelPosition type to EasyBulletFired RemoteEvent\nExpected: Vector3, got: {typeof(barrelPos)}`)
				return
			end

			if typeof(velocity) ~= "Vector3" then
				warn(`{player.Name} passed a malformed velocity type to EasyBulletFired RemoteEvent\nExpected: Vector3, got: {typeof(velocity)}`)
				return
			end

			-- Use shooter's ping to account for network desync.
			local ping = player:GetNetworkPing()

			-- Replicate shot to all other clients
			for _, v in ipairs(Players:GetPlayers()) do
				if v == player then continue end

				local thisPing = v:GetNetworkPing()

				self.FiredRemote:FireClient(v, player, barrelPos, velocity, ping + thisPing, easyBulletSettings)
			end

			-- Start handling the shot on the server
            self:_fireBullet(player, barrelPos, velocity, ping, easyBulletSettings, false)
		end)

		-- Handle batch fired bullets from a client
		self.FiredBatchRemote.OnServerEvent:Connect(function(player: Player, bullets: { [number]: { BarrelPosition: Vector3, Velocity: Vector3, EasyBulletSettings: Bullet.EasyBulletSettings } })
			if type(bullets) ~= "table" then
				warn(`{player.Name} passed a malformed bullets array to EasyBulletFiredBatch`)
				return
			end

			local ping = player:GetNetworkPing()

			-- group-level server gate
			if self.ShouldFireArrayCallback then
				local allow = self.ShouldFireArrayCallback(player, bullets, ping)
				assert(type(allow) == "boolean", `The callback bound by EasyBullet:BindShouldFireArray must return a boolean, returned: {typeof(allow)}`)
				if allow == false then
					-- cancel locally spawned bullets on the firing client
					for _, b in ipairs(bullets) do
						local id = b.EasyBulletSettings.BulletData.BulletId
						if typeof(id) == "string" then
							self.CanceledRemote:FireClient(player, id)
						end
					end
					return
				end
			end

			-- replicate to others
			for _, v in ipairs(Players:GetPlayers()) do
				if v == player then continue end

				local thisPing = v:GetNetworkPing()
				self.FiredBatchRemote:FireClient(v, player, bullets, ping + thisPing)
			end

			-- start server-side for authoritative hit detection if used
			self:_fireBullets(player, bullets, ping)
		end)

		-- Look for existing EasyBulletCanceled RemoteEvent. Create one if it does not exist.
		self.CanceledRemote = self:_findOrCreateRemote("EasyBulletCanceled")
		assert(self.CanceledRemote ~= nil, "self.CanceledRemote cannot be nil.")

		-- Handle the CanceledRemote
		self.CanceledRemote.OnServerEvent:Connect(function(cancelingPlayer: Player, bulletId: string)
			local bullet = self.Bullets[bulletId]

			if not bullet then
				warn(`No Bullet with a BulletId of {bulletId} was found`)
				return
			end

			if not bullet.Shooter then
				warn(`{cancelingPlayer.Name} cannot cancel a bullet owned by the server. BulletId: {bulletId}`)
				return
			end

			if bullet.Shooter and bullet.Shooter ~= cancelingPlayer then
				warn(`{cancelingPlayer.Name} cannot cancel a bullet owned by {bullet.Shooter.Name}. BulletId: {bulletId}`)
				return
			end

			self:_destroyBullet(bulletId)
		end)


	-- Client
	elseif RunService:IsClient() then
		-- Make references to our remotes
		self.FiredRemote = ReplicatedStorage:WaitForChild("EasyBulletFired") :: RemoteEvent
		self.FiredBatchRemote = ReplicatedStorage:WaitForChild("EasyBulletFiredBatch") :: RemoteEvent
		self.CanceledRemote = ReplicatedStorage:WaitForChild(("EasyBulletCanceled")) :: RemoteEvent

		if not self.FiredRemote then
			warn("No RemoteEvent named 'EasyBulletFired' found as a child of ReplicatedStorage")
			return
		end

		if not self.CanceledRemote or not self.FiredBatchRemote then
			warn("No RemoteEvent named 'EasyBulletCanceled' found as a child of ReplicatedStorage")
			return
		end

		-- Handle the FiredRemote
		self.FiredRemote.OnClientEvent:Connect(function(shootingPlayer: Player, barrelPos: Vector3, velocity: Vector3, accumulatedPing: number, easyBulletSettings: Bullet.EasyBulletSettings)
			-- The server shouldn't ever replicate back a shot this client fired, but check that just to be safe.
			if shootingPlayer == Players.LocalPlayer then
				return
			end

            self:_fireBullet(shootingPlayer, barrelPos, velocity, accumulatedPing, easyBulletSettings, false)
		end)

		-- Handle batch fired bullets
		self.FiredBatchRemote.OnClientEvent:Connect(function(shootingPlayer: Player, bullets: { [number]: { BarrelPosition: Vector3, Velocity: Vector3, EasyBulletSettings: Bullet.EasyBulletSettings } }, accumulatedPing: number)
			if shootingPlayer == Players.LocalPlayer then
				return
			end

			self:_fireBullets(shootingPlayer, bullets, accumulatedPing)
		end)

		-- Handle the CanceledRemote
		self.CanceledRemote.OnClientEvent:Connect(function(bulletId: string)
			self:_destroyBullet(bulletId)
		end)

	end

	-- Both
	RunService.Heartbeat:Connect(function()
		for _, bullet: Bullet.Bullet in pairs(self.Bullets) do
			local lastPosition, currentPosition = bullet:Update(self.CustomCastCallback)

			-- Update returns nil when bullet drops below workspace.FallenPartsDestroyHeight
			if lastPosition and currentPosition then
				self.BulletUpdated:Fire(lastPosition, currentPosition, bullet.EasyBulletSettings.BulletData)
			end
		end
	end)
end

function EasyBullet:_findOrCreateRemote(remoteName: string): RemoteEvent
	local foundRemote = ReplicatedStorage:FindFirstChild(remoteName)

	if foundRemote == nil then
		foundRemote = Instance.new("RemoteEvent")
		foundRemote.Name = remoteName
		foundRemote.Parent = ReplicatedStorage

		return foundRemote
	elseif foundRemote:IsA("RemoteEvent") then
		return foundRemote
	else
		error(`Instance named {remoteName} is of type {foundRemote.ClassName}, not RemoteEvent`)
	end
end

return EasyBullet