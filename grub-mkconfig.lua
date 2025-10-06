-- /bin/grub-mkconfig.lua
local fs = require("filesystem")
local shell = require("shell")

local args, ops = shell.parse(...)
local targetPath = ops.o or "/grub.cfg"

if #args < 1 then
  io.stderr:write("Usage: grub-mkconfig -o <output> <init_script_path>\n")
  return 1
end

local initPath = args[1]
if not initPath:match("^/") then
  initPath = shell.resolve(initPath)
end

if not fs.exists(initPath) then
  io.stderr:write("Error: file not found: " .. initPath .. "\n")
  return 1
end

local content = "linux " .. initPath .. "\n"
local f = io.open(targetPath, "w")
if not f then
  io.stderr:write("Error: cannot write to " .. targetPath .. "\n")
  return 1
end
f:write(content)
f:close()

print("GRUB config written to " .. targetPath)
print("Entry: linux " .. initPath)