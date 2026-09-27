--!strict
--[[
	RateLimiter
	Token bucket keyed by anything (usually a Player). Each key may spend
	`burst` actions at once, and regains `rate` actions per second.

	local limiter = RateLimiter.new(5, 10)
	if not limiter:Check(player) then return end -- over the limit
]]

export type RateLimiter = {
	Check: (self: RateLimiter, key: any) -> boolean,
	Remove: (self: RateLimiter, key: any) -> (),
	Clear: (self: RateLimiter) -> (),
}

type Bucket = { tokens: number, updatedAt: number }

local RateLimiter = {}

function RateLimiter.new(rate: number, burst: number, clock: (() -> number)?): RateLimiter
	assert(rate > 0, "rate must be positive")
	assert(burst >= 1, "burst must be at least 1")
	local now = clock or os.clock
	local buckets: { [any]: Bucket } = {}

	local self = {} :: RateLimiter

	function self.Check(_: RateLimiter, key: any): boolean
		local t = now()
		local bucket = buckets[key]
		if bucket == nil then
			bucket = { tokens = burst, updatedAt = t }
			buckets[key] = bucket
		else
			local elapsed = math.max(0, t - bucket.updatedAt)
			bucket.tokens = math.min(burst, bucket.tokens + elapsed * rate)
			bucket.updatedAt = t
		end
		if bucket.tokens >= 1 then
			bucket.tokens -= 1
			return true
		end
		return false
	end

	function self.Remove(_: RateLimiter, key: any)
		buckets[key] = nil
	end

	function self.Clear(_: RateLimiter)
		table.clear(buckets)
	end

	return self
end

return RateLimiter
