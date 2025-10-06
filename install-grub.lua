-- install-grub.lua
local internet = require("internet")
local component = require("component")
local filesystem = require("filesystem")
local shell = require("shell")

local eeprom = component.eeprom
if not eeprom then
  error("No EEPROM found!")
end

-- URL к вашему grub-eeprom.lua на GitHub (сырая ссылка!)
local eepromUrl = "https://raw.githubusercontent.com/0pt1mist/OC-GRUB/main/grub-eeprom"
local mkconfigUrl = "https://raw.githubusercontent.com/0pt1mist/OC-GRUB/main/grub-mkconfig.lua"

print("Downloading GRUB bootloader...")

-- Скачиваем EEPROM
local eepromCode = internet.request(eepromUrl)
local eepromData = ""
for chunk in eepromCode do eepromData = eepromData .. chunk end

if eepromData:find("error", 1, true) then
  error("Failed to download EEPROM from " .. eepromUrl)
end

-- Записываем в EEPROM
eeprom.set(eepromData)
eeprom.makeReadonly() -- опционально

print("EEPROM updated!")

-- Устанавливаем grub-mkconfig в /bin
local mkconfigCode = internet.request(mkconfigUrl)
local mkconfigData = ""
for chunk in mkconfigCode do mkconfigData = mkconfigData .. chunk end

local binPath = "/bin/grub-mkconfig"
local f = io.open(binPath, "w")
f:write(mkconfigData)
f:close()
filesystem.setAttrib(binPath, "executable", true)

print("grub-mkconfig installed to /bin/")
print("Reboot to apply changes.")