-- binary_trees: the benchmarks game's allocation test at depth arg[1] (default 14), tables
-- built and walked, the garbage collector at work
local n = tonumber(arg and arg[1]) or 14

local function bottom_up(depth)
  if depth == 0 then
    return {}
  end
  depth = depth - 1
  return { bottom_up(depth), bottom_up(depth) }
end

local function check(tree)
  if tree[1] then
    return 1 + check(tree[1]) + check(tree[2])
  end
  return 1
end

local min_depth = 4
local max_depth = n
if min_depth + 2 > max_depth then
  max_depth = min_depth + 2
end

local stretch = max_depth + 1
print(string.format("stretch tree of depth %d check: %d", stretch, check(bottom_up(stretch))))

local long_lived = bottom_up(max_depth)

for depth = min_depth, max_depth, 2 do
  local iterations = 1 << (max_depth - depth + min_depth)
  local sum = 0
  for _ = 1, iterations do
    sum = sum + check(bottom_up(depth))
  end
  print(string.format("%d trees of depth %d check: %d", iterations, depth, sum))
end

print(string.format("long lived tree of depth %d check: %d", max_depth, check(long_lived)))
