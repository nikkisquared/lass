local lass = require("lass")
local class = require("lass.class")
local geometry = require("lass.geometry")
local Collider = require("lass.builtins.physics.Collider")

local PlayerInput = class.define(lass.Component, function(self, arguments)

	arguments.rotationSpeed = arguments.rotationSpeed or 1
	arguments.controls = arguments.controls or {
		rotate = 1
	}
	if arguments.speedMode then
		assert(
			arguments.speedMode == "perFrame" or arguments.speedMode == "perSecond",
			"invalid speed mode: choose 'perFrame' or 'perSecond'"
		)
	else
		arguments.speedmode = "perFrame"
	end
	arguments.resizeAmount = arguments.resizeAmount or 0

	--call super constructor
	self.__base.init(self, arguments)

	--hidden variables
	self.rotationDirection = 0
end)

function PlayerInput:update(dt)

	if self.speedMode == "perFrame" then dt = 1 end

	--rotate
	if self.rotationDirection > 0 then
		self.gameObject:rotate(dt * self.rotationSpeed)
	elseif self.rotationDirection < 0 then
		self.gameObject:rotate(dt * -self.rotationSpeed)
	end

end

function PlayerInput:mousepressed(x, y, button, clickedOnSelf)

	if clickedOnSelf then
		if button == 1 then
			if self.rotationDirection == -1 then
				self.rotationDirection = 0
			else
				self.rotationDirection = -1
			end
		elseif button == 2 then
			if self.rotationDirection == 1 then
				self.rotationDirection = 0
			else
				self.rotationDirection = 1
			end
		end
	end
end

function PlayerInput:wheelmoved(x, y)

	if y > 0 and self.resizeAmount ~= 0 then
		self.gameObject:resize(self.resizeAmount, self.resizeAmount, 0)
	elseif y < 0 and self.resizeAmount ~= 0 then
		self.gameObject:resize(-self.resizeAmount, -self.resizeAmount, 0)
	end
end

return PlayerInput
