local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(owner, states, initialState)
	local self = setmetatable({}, StateMachine)
	self.owner = owner
	self.states = states
	self.name = nil
	self:changeState(initialState)
	return self
end

function StateMachine:changeState(name)
	local nextState = self.states[name]
	assert(nextState, "Unknown state: " .. tostring(name))

	local current = self.states[self.name]
	if current and current.exit then
		current.exit(self.owner)
	end

	self.name = name

	if nextState.enter then
		nextState.enter(self.owner)
	end
end

-- Stops the current state's timers/transitions without entering a new one.
-- Used while the player is dragging the owner around.
function StateMachine:pause()
	local current = self.states[self.name]
	if current and current.exit then
		current.exit(self.owner)
	end
	self.name = nil
end

return StateMachine
