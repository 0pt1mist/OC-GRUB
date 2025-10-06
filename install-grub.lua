-- install-grub2.lua (обновлённая версия)

local component = require("component")
local computer = require("computer")

local function getComponent(name)
  local addr = component.list(name)()
  if not addr then error("Required " .. name .. " missing!", 0) end
  return addr
end

local internetAddr = getComponent("internet")
local hddAddr = nil

for addr in component.list("filesystem") do
  local fs = component.proxy(addr)
  if fs.spaceTotal() and fs.spaceTotal() > 1024 * 1024 then
    hddAddr = addr
    break
  end
end

if not hddAddr then
  error("No suitable HDD found (need >1 MB)!", 0)
end

local hdd = component.proxy(hddAddr)

if not hdd.getLabel() then
  error("Disk not formatted! Format in BIOS (press F).", 0)
end

local function downloadFile(url, path)
  print("Downloading: " .. path)
  local handle, err = component.invoke(internetAddr, "request", url)
  if not handle then
    error("HTTP error: " .. tostring(err))
  end

  local fileHandle = hdd.open(path, "wb")
  if not fileHandle then
    error("Cannot create " .. path)
  end

  while true do
    local chunk, reason = handle.read(65536)
    if chunk then
      hdd.write(fileHandle, chunk)
    else
      if reason then
        error("Download failed: " .. tostring(reason))
      end
      break
    end
  end

  hdd.close(fileHandle)
  handle.close()
  print("Done")
end

hdd.setLabel("GRUBBOOT")

local dirs = {"/bin", "/boot"}
for _, d in ipairs(dirs) do
  if not hdd.exists(d) then hdd.makeDirectory(d) end
end

-- ======== ВСТАВЛЯЕМ КОД GRUB-EEPROM НАПРЯМУЮ ========
local grubEepromCode = [[
local init
do
  local component_invoke = component.invoke
  local function boot_invoke(address, method, ...)
    local result = table.pack(pcall(component_invoke, address, method, ...))
    if not result[1] then
      return nil, result[2]
    else
      return table.unpack(result, 2, result.n)
    end
  end

  local eeprom = component.list("eeprom")()
  computer.getBootAddress = function()
    return boot_invoke(eeprom, "getData")
  end
  computer.setBootAddress = function(address)
    return boot_invoke(eeprom, "setData", address)
  end

  do
    local screen = component.list("screen")()
    local gpu = component.list("gpu")()
    if gpu and screen then
      boot_invoke(gpu, "bind", screen)
    end
  end

  local function readFile(address, path)
    local handle, reason = boot_invoke(address, "open", path)
    if not handle then return nil, reason end
    local buffer = ""
    repeat
      local data, reason = boot_invoke(address, "read", handle, math.huge)
      if not data and reason then
        boot_invoke(address, "close", handle)
        return nil, reason
      end
      buffer = buffer .. (data or "")
    until not data
    boot_invoke(address, "close", handle)
    return buffer
  end

  local function tryLoadFromPath(address, filepath)
    local code, reason = readFile(address, filepath)
    if not code then return nil, reason end
    local chunk, err = load(code, "=" .. filepath)
    if not chunk then return nil, err end
    return chunk
  end

  local function findGrubConfig()
    if computer.getBootAddress() then
      for _, cfgPath in ipairs{"/boot/grub.cfg", "/grub.cfg"} do
        local config = readFile(computer.getBootAddress(), cfgPath)
        if config then
          return computer.getBootAddress(), config
        end
      end
    end

    for address in component.list("filesystem") do
      for _, cfgPath in ipairs{"/boot/grub.cfg", "/grub.cfg"} do
        local config = readFile(address, cfgPath)
        if config then
          return address, config
        end
      end
    end
    return nil
  end

  local function parseGrubConfig(config)
    for line in config:gmatch("[^\r\n]+") do
      line = line:match("^%s*(.-)%s*$")
      if line:sub(1, 5) == "linux" then
        local path = line:sub(6):match("^%s*(.-)%s*$")
        if path and path ~= "" then
          return path
        end
      end
    end
    return "/init.lua"
  end

  local reason
  local bootAddress = computer.getBootAddress()
  local customPath

  local cfgAddress, cfgContent = findGrubConfig()
  if cfgContent then
    customPath = parseGrubConfig(cfgContent)
    if cfgAddress then
      bootAddress = cfgAddress
      computer.setBootAddress(bootAddress)
    end
  else
    customPath = "/init.lua"
  end

  if bootAddress then
    init, reason = tryLoadFromPath(bootAddress, customPath)
  end

  if not init then
    computer.setBootAddress()
    for address in component.list("filesystem") do
      init, reason = tryLoadFromPath(address, "/init.lua")
      if init then
        computer.setBootAddress(address)
        break
      end
    end
  end

  if not init then
    error("no bootable medium found" .. (reason and (": " .. tostring(reason)) or ""), 0)
  end

  computer.beep(1000, 0.2)
end
return init()
]]

-- Записываем в EEPROM
local eeprom = component.eeprom
if not eeprom then
  error("No EEPROM found!")
end

print("Installing GRUB bootloader into EEPROM...")
eeprom.set(grubEepromCode)
eeprom.makeReadonly()

-- Устанавливаем grub-mkconfig
local mkconfigCode = [[
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
]]

local binPath = "/bin/grub-mkconfig"
local f = hdd.open(binPath, "w")
f:write(mkconfigCode)
f:close()
hdd.setAttrib(binPath, "executable", true)

print("✅ GRUB bootloader installed successfully!")
print("✅ grub-mkconfig installed to /bin/")
print("⚠️  Reboot to apply changes.")