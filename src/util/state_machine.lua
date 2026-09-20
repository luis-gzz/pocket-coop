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

return StateMachine
