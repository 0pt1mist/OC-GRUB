-- install-grub.lua - GRUB-like bootloader installer for OpenComputers

local component = require("component")
local computer = require("computer")

local function getComponent(name)
  local addr = component.list(name)()
  if not addr then error("Required " .. name .. " missing!", 0) end
  return addr
end

local internetAddr = getComponent("internet")
local hddAddr = nil

-- Ищем подходящий диск (минимум 1MB свободного места)
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

-- Устанавливаем метку диска (опционально)
hdd.setLabel("GRUBBOOT")

-- Создаём директории
local dirs = {"/bin", "/boot"}
for _, d in ipairs(dirs) do
  if not hdd.exists(d) then hdd.makeDirectory(d) end
end

-- Ссылки на файлы (замените на свои!)
local BASE = "https://raw.githubusercontent.com/ВАШ_НИК/ВАШ_РЕПО/main"

downloadFile(BASE .. "/grub-eeprom.lua", "/tmp/grub-eeprom.lua")
downloadFile(BASE .. "/grub-mkconfig.lua", "/bin/grub-mkconfig")

-- Загружаем и устанавливаем EEPROM
local eeprom = component.eeprom
if not eeprom then
  error("No EEPROM found!")
end

print("Installing GRUB bootloader into EEPROM...")

-- Читаем скачанный файл в память
local f = hdd.open("/tmp/grub-eeprom.lua", "r")
if not f then
  error("Failed to open downloaded grub-eeprom.lua")
end

local eepromCode = ""
while true do
  local chunk = hdd.read(f, 65536)
  if not chunk then break end
  eepromCode = eepromCode .. chunk
end
hdd.close(f)

-- Удаляем временный файл
hdd.remove("/tmp/grub-eeprom.lua")

-- Записываем в EEPROM
eeprom.set(eepromCode)
eeprom.makeReadonly() -- опционально, но рекомендуется

print("✅ GRUB bootloader installed successfully!")
print("✅ grub-mkconfig installed to /bin/")
print("⚠️  Reboot to apply changes.")