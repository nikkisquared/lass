local lass = require("lass")
local class = require("lass.class")
local geometry = require("lass.geometry")
local collections = require("lass.collections")
local Collider = require("lass.builtins.physics.Collider")

local SimpleRigidbody = class.define(lass.Component, function(self, arguments)

	arguments.airResistance = arguments.airResistance or 0
	arguments.velocity = geometry.Vector2(arguments.velocity)

	self.collisions = {}
	self.__base.init(self, arguments)
end)

local function checkCollisions(gameObject, oldPositions, moveBy, alwaysFailOnCollision)


	local directionOverlaps = {}
	local collisions = {}
	local others = {}

	-- we need to update the global transform for the collision detection to work immediately
	gameObject:maintainTransform()

	for i, child in ipairs(gameObject.children) do
		local cols, overlaps = checkCollisions(child, oldPositions, moveBy)
		if cols then
			for j, col in ipairs(cols) do
				collisions[#collisions + j] = col
			end
			for j, over in ipairs(overlaps) do
				directionOverlaps[#directionOverlaps + j] = over
			end
		else
			gameObject.transform.position = oldPositions[gameObject]
			--reset transform of every descendant except the child and its descendants
			--(because they've already been reset)
			gameObject:maintainTransform(true, child)
			return false
		end
	end

	local collider = gameObject:getComponent(Collider)
	if not (collider and collider.solid) then
		return {}, {}
	end

	for layerName, layer in pairs(collider.globals.colliders) do
		-- add everything from layersToCheck to possible collisions
		if collections.index(collider.layersToCheck, layerName) then
			others[layerName] = collections.copy(layer)
		-- add everything whose layersToCheck include this collider's layers
		else
			for i, o in ipairs(layer) do
				for j, layerName2 in ipairs(collider.layers) do
					if collections.index(o.layersToCheck, layerName2) then
						if others[layerName2] then
							others[layerName2][#others[layerName2]] = o
						else
							others[layerName2] = {o}
						end
						break
					end
				end
			end
		end
	end

	for layerName, layer in pairs(others) do
		for i, other in ipairs(layer) do

			if other ~= collider and other.solid then

				local r, data
				local oldData = collider.collidingWith[other]
				local oldDataNeg = collider.notCollidingWith[other]

				r, data = collider:isCollidingWith(other, moveBy, false, not alwaysFailOnCollision)

				if r then
					debug.log(other.gameObject.name, data.shortestOverlap, data.directionOverlap)
					-- return false if we were already colliding with this collider,
					-- and the overlap increased

					if (
						oldData and
						oldData.frame == gameObject.gameScene.frame - 1 and (
							(
								oldData.directionOverlap and
								data.directionOverlap and
								oldData.directionOverlap < data.directionOverlap and
								oldData.direction:angle() == data.direction:angle()
							) or
							oldData.shortestOverlap < data.shortestOverlap
						)
					) then
						debug.log(other.gameObject.name, oldData.shortestOverlap, oldData.directionOverlap, "overlap increased")

						gameObject.transform.position = oldPositions[gameObject]
						gameObject:maintainTransform()

						--reset collision data
						if not alwaysFailOnCollision then
							collider.collidingWith[other] = collections.deepcopy(oldData)
							collider.collidingWith[other].frame = gameObject.gameScene.frame
							other.collidingWith[collider] = collections.deepcopy(oldData)
							other.collidingWith[collider].frame = gameObject.gameScene.frame
						end

						return false
					-- only add colliders that we weren't already colliding with, and have non-zero overlap
					elseif
						(not oldData or oldData.frame < gameObject.gameScene.frame - 1) and
						data.shortestOverlap ~= 0
					then
						debug.log(other.gameObject.name, "nonzero overlap")

						if alwaysFailOnCollision then
							gameObject.transform.position = oldPositions[gameObject]
							gameObject:maintainTransform()
							return false
						else
							collisions[#collisions + 1] = {other, collider}
							if data.directionOverlap then
								directionOverlaps[#directionOverlaps + 1] = data.directionOverlap
							end
						end
					elseif (not oldData or oldData.frame < gameObject.gameScene.frame - 1) then
						debug.log(other.gameObject.name, "zero overlap")
					end
				end
			end
		end
	end

	return collisions, directionOverlaps
end

local function gatherPositions(gameObject)

	local positions = {}
	positions[gameObject] = geometry.Vector3(gameObject.transform.position)

	for i, child in ipairs(gameObject.children) do
		for k,v in pairs(gatherPositions(child)) do
			positions[k] = v
		end
	end

	return positions
end

local function move(self, moveBy, alwaysFailOnCollision)

	local gameObject = self.gameObject
	local oldPositions = gatherPositions(gameObject)

	gameObject:moveGlobal(moveBy)
	local newPosition = gameObject.transform.position

	if
		oldPositions[gameObject].x == newPosition.x and
		oldPositions[gameObject].y == newPosition.y and
		oldPositions[gameObject].z == newPosition.z
	then
		return false
	end

	-- check collisions and respond

	local collisions, directionOverlaps = checkCollisions(gameObject, oldPositions, moveBy, alwaysFailOnCollision)

	-- collisions would only be false if the object failed to move
	-- (for example, if it was already stuck inside an object)
	if not collisions then
		return false
	-- if no collisions occurred, movement is successful
	elseif #collisions < 1 then
		-- debug.log("no collisions")
		return true
	elseif alwaysFailOnCollision then
		return false
	-- if we have directionOverlap information for all of the collisions,
	-- we can simply move in the opposite direction of the highest directionOverlap
	elseif #directionOverlaps == #collisions then
		--we want to pull back by the greatest overlap distance
		table.sort(directionOverlaps, function(a,b) return a > b end)
		local dist = directionOverlaps[1]

		if moveBy.x ~= 0 then
			gameObject:moveGlobal(-(math.sign(moveBy.x) * dist), 0)
		elseif moveBy.y ~= 0 then
			gameObject:moveGlobal(0, -(math.sign(moveBy.y) * dist))
		end

		-- now that we've moved the objects after the isCollidingWith call,
		-- the collision data needs to be updated
		for i, c in ipairs(collisions) do
			if c[1].collidingWith[c[2]].directionOverlap == directionOverlaps[1] then
				c[1].collidingWith[c[2]].directionOverlap = 0
				c[1].collidingWith[c[2]].shortestOverlap = 0
				c[2].collidingWith[c[1]].directionOverlap = 0
				c[2].collidingWith[c[1]].shortestOverlap = 0
			elseif c[1].collidingWith[c[2]].directionOverlap < directionOverlaps[1] then
				c[1].collidingWith[c[2]] = nil
				c[1].collidingWith[c[2]] = nil
				c[2].notCollidingWith[c[1]] = {frame = gameObject.gameScene.frame}
				c[2].notCollidingWith[c[1]] = {frame = gameObject.gameScene.frame}
			end
		end

		gameObject:maintainTransform()
		return true, collisions
	end

	-- if we're still here, it means our movement resulted in a collision for which
	-- we have no directionOverlap data. we need to do a binary search to determine
	-- how far back to move
	-- if there is no directionOverlap data, the colliders are not rectangles

	local backward = true
	local lastBackward = backward
	local skip = newPosition - oldPositions[gameObject]
	local oldSkip

	skip = geometry.Vector2(skip.x/2, skip.y/2)
	for i, a in ipairs({"x", "y"}) do
		if skip[a] < 0 then
			skip[a] = math.ceil(skip[a])
		else
			skip[a] = math.floor(skip[a])
		end
	end
	local done = false
	local maintainSkip = false
	local counter = 0

	if skip.x == 0 and skip.y == 0 then
		gameObject.transform.position = oldPositions[gameObject]
		gameObject:maintainTransform()
		return false
	end

	if moveBy.x ~= 0 then
		gameObject.transform.position.x = math.floor(gameObject.transform.position.x)
	elseif moveBy.y ~= 0 then
		gameObject.transform.position.y = math.floor(gameObject.transform.position.y)
	end

	while not done do
		if backward then
			gameObject:moveGlobal(-skip)
			-- gameObject:move(-skip)
		else
			gameObject:moveGlobal(skip)
			-- gameObject:move(skip)
		end

		gameObject:maintainTransform(true)

		lastBackward = backward
		for i, c in ipairs(collisions) do
			local r, d = c[1]:isCollidingWith(c[2], nil, false)
			--if colliding...
			if r then
				backward = true
				break
			end

			--if not colliding, move forward next time
			backward = false
		end

		local axesLessThanOne = 0
		if not maintainSkip then
			oldSkip = skip
			skip = geometry.Vector2(skip.x/2, skip.y/2)
			for i, a in ipairs({"x", "y"}) do
				if skip[a] < 0 then
					skip[a] = math.ceil(skip[a])
					if skip[a] > -1 then
						-- skip[a] = -1
						axesLessThanOne = axesLessThanOne + 1
					end
				elseif skip[a] > 0 then
					skip[a] = math.floor(skip[a])
					if skip[a] < 1 then
						-- skip[a] = 1
						axesLessThanOne = axesLessThanOne + 1
					end
				else
					axesLessThanOne = axesLessThanOne + 1
				end
			end
		end

		if axesLessThanOne == 2 then
			skip = oldSkip
			maintainSkip = true
		end

		-- even if collision overlaps aren't exactly 0, we can stop here if
		-- we're just moving the collider back and forth
		if maintainSkip and not backward and lastBackward then
			done = true
		end

		counter = counter + 1
	end

	return true, collisions
end

function SimpleRigidbody:update(dt)

	self.collisionData = {colliding={}, notColliding={}}

	self.velocity = self.velocity - self.globals.gravity

	-- move one axis at a time. if x movement fails, try again after y movement.

	--[[
	local axesToCheck
	if self.velocity.x == 0 and self.velocity.y == 0 then
		return
	elseif self.velocity.x == 0 then
		axesToCheck = {"y"}
	elseif self.velocity.y == 0 then
		axesToCheck = {"x"}
	else
		-- this will become {"x","y","x"} if the first x movement fails
		axesToCheck = {"x", "y"}
	end

	-- if y is nonzero, then this flag must be true the first time we check the x axis,
	-- so that it returns to its original position upon collision
	local alwaysFailOnCollision = self.velocity.y ~= 0

	for i, axis in ipairs(axesToCheck) do

		local moveBy = geometry.Vector2()
		moveBy[axis] = self.velocity[axis] * dt

		local r, col = move(self, moveBy, alwaysFailOnCollision)

		if not r then

			-- if this is the first time we checked x, and we plan to check y,
			-- check x again after checking y
			if #axesToCheck == 2 and i == 1 then
				axesToCheck[3] = "x"
			else
				--TODO: set velocity to other rigidbody's velocity instead of 0
				self.velocity[axis] = 0
			end
		end

		alwaysFailOnCollision = false
	end

	--]]

	----[[
	local breakAfterY = true
	local alwaysFailOnCollision = self.velocity.y ~= 0
	for i, axis in ipairs({"x", "y", "x"}) do
		debug.log(i, alwaysFailOnCollision)

		local moveBy = geometry.Vector2()
		moveBy[axis] = self.velocity[axis] * dt

		local r, col = move(self, moveBy, alwaysFailOnCollision)

		if r == false then

			-- if collision happened during horizontal movement, try again after vertical movement
			if i == 1 then
				breakAfterY = false
				if moveBy.x ~= 0 then
					debug.log("colliding horizontally")
				end
			else
				self.velocity[axis] = 0
			end
		end

		-- even if not breakAfterY, there's no point in trying again if vertical movement was 0
		if i == 2 then
			if breakAfterY then
				break
			-- if we break before resetting velocity.x, it will continue to accelerate.
			-- plus, we know that if breakAfterY is false, a horizontal collision or standstill occurred
			elseif moveBy[axis] == 0 then
				self.velocity.x = 0
				break
			end
		end

		alwaysFailOnCollision = false
	end
	--]]
end

return SimpleRigidbody