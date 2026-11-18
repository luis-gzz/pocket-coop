-- The player's coin balance (CONTEXT.md's Coin): earned by selling eggs,
-- spent in the shop, never negative.
local Wallet = {}

local coins = 0
local onSave = nil
local listeners = {}

local function changed()
	if onSave then
		onSave()
	end
	for _, listener in ipairs(listeners) do
		listener(coins)
	end
end

function Wallet.setSaveCallback(fn)
	onSave = fn
end

-- listener(coins), after every change.
function Wallet.onChanged(listener)
	table.insert(listeners, listener)
end

function Wallet.get()
	return coins
end

function Wallet.add(amount)
	coins = coins + amount
	changed()
end

-- Spends amount if the balance covers it; returns whether it did.
function Wallet.spend(amount)
	if amount > coins then
		return false
	end
	coins = coins - amount
	changed()
	return true
end

-- saved: the "wallet" section of the save file, or nil; startCoins if nil.
function Wallet.load(saved, startCoins)
	coins = math.max(0, math.floor(tonumber(saved and saved.coins) or startCoins or 0))
end

function Wallet.getSaveData()
	return { coins = coins }
end

return Wallet
