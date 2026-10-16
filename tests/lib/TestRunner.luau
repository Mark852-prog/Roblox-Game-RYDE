--[[
	Tiny test framework: describe / it / expect.
	Each spec file returns function(t) and calls t.describe / t.it.
]]

local TestRunner = {}

export type Results = { passed: number, failed: number, failures: { string } }

local function format(value: any): string
	if type(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

local function expect(actual: any)
	local api = {}
	function api.toBe(expected: any)
		if actual ~= expected then
			error(`expected {format(expected)}, got {format(actual)}`, 2)
		end
	end
	function api.toBeNear(expected: number, tolerance: number?)
		local tol = tolerance or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > tol then
			error(`expected {expected} +- {tol}, got {format(actual)}`, 2)
		end
	end
	function api.toBeTruthy()
		if not actual then
			error(`expected a truthy value, got {format(actual)}`, 2)
		end
	end
	function api.toBeGreaterThan(expected: number)
		if not (actual > expected) then
			error(`expected > {expected}, got {format(actual)}`, 2)
		end
	end
	function api.toBeLessThan(expected: number)
		if not (actual < expected) then
			error(`expected < {expected}, got {format(actual)}`, 2)
		end
	end
	function api.toBeEmpty()
		if type(actual) ~= "table" or next(actual) ~= nil then
			local items = if type(actual) == "table" then table.concat(actual, "\n    ") else tostring(actual)
			error(`expected empty list, got:\n    {items}`, 2)
		end
	end
	function api.toContainMatch(pattern: string)
		for _, item in actual do
			if string.find(item, pattern) then
				return
			end
		end
		error(`expected an entry matching '{pattern}' in:\n    {table.concat(actual, "\n    ")}`, 2)
	end
	return api
end

function TestRunner.run(specs: { [string]: (any) -> () }): Results
	local results: Results = { passed = 0, failed = 0, failures = {} }
	local names = {}
	for name in specs do
		table.insert(names, name)
	end
	table.sort(names)

	for _, specName in names do
		print(`\n{specName}`)
		local prefix = ""
		local t = {}
		t.expect = expect
		function t.describe(label: string, body: () -> ())
			local previous = prefix
			prefix = prefix .. label .. " > "
			print(`  {label}`)
			body()
			prefix = previous
		end
		function t.it(label: string, body: () -> ())
			local ok, err = pcall(body)
			if ok then
				results.passed += 1
				print(`    [PASS] {label}`)
			else
				results.failed += 1
				local message = `{specName} > {prefix}{label}: {err}`
				table.insert(results.failures, message)
				print(`    [FAIL] {label}\n           {err}`)
			end
		end
		local ok, err = pcall(specs[specName], t)
		if not ok then
			results.failed += 1
			table.insert(results.failures, `{specName}: spec crashed: {err}`)
			print(`  [CRASH] {err}`)
		end
	end
	return results
end

return TestRunner
