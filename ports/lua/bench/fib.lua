-- fib: the doubly recursive Fibonacci number of arg[1] (default 34), calls and integer adds
local n = tonumber(arg and arg[1]) or 34

local function fib(k)
  if k < 2 then
    return k
  end
  return fib(k - 1) + fib(k - 2)
end

print(string.format("fib(%d) = %d", n, fib(n)))
