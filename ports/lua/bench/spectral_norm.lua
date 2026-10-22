-- spectral_norm: the benchmarks game's spectral norm of an arg[1]-square matrix (default 500),
-- float arithmetic over arrays in nested loops
local n = tonumber(arg and arg[1]) or 500

local function a(i, j)
  local ij = i + j - 1
  return 1.0 / (ij * (ij - 1) * 0.5 + i)
end

local function av(x, y, size)
  for i = 1, size do
    local sum = 0
    for j = 1, size do
      sum = sum + x[j] * a(i, j)
    end
    y[i] = sum
  end
end

local function atv(x, y, size)
  for i = 1, size do
    local sum = 0
    for j = 1, size do
      sum = sum + x[j] * a(j, i)
    end
    y[i] = sum
  end
end

local function atav(x, y, t, size)
  av(x, t, size)
  atv(t, y, size)
end

local u, v, t = {}, {}, {}
for i = 1, n do
  u[i] = 1
end
for _ = 1, 10 do
  atav(u, v, t, n)
  atav(v, u, t, n)
end
local vbv, vv = 0, 0
for i = 1, n do
  local ui, vi = u[i], v[i]
  vbv = vbv + ui * vi
  vv = vv + vi * vi
end
print(string.format("%.9f", math.sqrt(vbv / vv)))
