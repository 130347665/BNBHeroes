import options, json, parseutils, strutils, os,db_mysql, strformat, times, re, streams
import web3,eth/keys,chronos, nimcrypto, stint, strscans, math

type Hero = object
  name:Uint
  heroType:Uint
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
  level: Uint8
  lastUpgradedTimeStamp: Uint256

contract(PriceOracle):
  proc getCharacterPrice():Uint256 {.view.}
  proc getTownUpgradePrices():seq[Uint256] {.view.}
  proc getExpeditePrice():Uint256 {.view.}
  
contract(BNBHToken):
  proc transfer(to: Address, amount:Uint256):Bool 
  proc approve(spender:Address, amount: Uint256)
  proc balanceOf(address:Address): Uint256
  proc transferFrom(fro: Address, to: Address, amount: Uint256):Bool 
  proc allowance(owner: Address, spender: Address):Uint256  {.view.}
  proc Approval(owner: indexed[Address], spender: indexed[Address], value:Uint256) {.event.}
  proc Transfer(fromAddr: indexed[Address], toAddr: indexed[Address], value: Uint256) {.event.}

contract(BNBHero):
  proc createNewHero()
  proc CreatedHero(player: Address, heroId: Uint256) {.event.}
  proc fight(heroId: Uint256, enemyType: Uint256)
  proc unLockLevel(tokenId: Uint256)
  proc upgradeTown(townType: Uint8)
  proc expediteHero(tokenId: Uint256)
  proc balances(owner: Address): Uint256 {.view.}
  proc getPriceToUnlockLevel(heroId: Uint256):Uint256 {.view.}
  proc getHeroesByOwner(account:Address, calcTown: Bool): seq[Hero] {.view.}
  proc getTownsOfPlayer(account:Address): array[4, Town] {.view.}
  proc Fight(player: Address, attackingHero: Uint256, enemyType: Uint256, rewards: Uint256, xpGained: Uint256, hpLoss: Uint256) {.event.}

contract(BSCUSD):
  proc transferFrom(fro: Address, to: Address, amount:Uint256):Bool 
  proc approve(spender: Address, amount:Uint256): Bool 
  proc allowance(owner: Address, spender: Address):Uint256  {.view.}

contract(Accounter):
  proc buy()
  proc keys() {.view.}
  proc getSize() {.view.}
  proc balance(address: Address):Uint {.view.}

var  bnbHeroAddress = Address.fromHex "0xde9fFb228C1789FEf3F08014498F2b16c57db855"
var  bnbhTokenAddress = Address.fromHex "0xd25631648e3ad4863332319e8e0d6f2a8ec6f267"
var  priceOracleAddress = Address.fromHex "0xd160bbded5cff79b126443eefcb28f3b67991140"
var  bscUSDTAddress = Address.fromHex "0x55d398326f99059fF775485246999027B3197955"
var  accounterAddress = Address.fromHex "0xe6d2167AF5C252F94FC548cD3a40835c31080EC6"
var  WBNBTokenAddress = Address.fromHex "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"

proc eth*(eth: Uint256): UInt256 = 10.u256.pow(18) * eth

template get6decimal*(value: Uint256): float =
  toInt(value div 10.u256.pow(12)).float64 / 10.0.pow(6)

const borrowFrom = "0xcea07fdc842fab6553224d2c3e628ac6162257b4"
var UINT256MAX = Stuint[256].fromHex("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
# var Web3 = await newWeb3("wss://bsc-ws-node.nariox.org:443")
# var mainWeb3 = await newWeb3("wss://bsc-ws-node.nariox.org:443")
const dbHost = "120.76.176.122:32760"
const dbUser = "root"
const dbPasswd = "Jintai@0105"
const dbUse = "bnbheroes"

template getBuytime(value: string):string {.dirty.} =
    let mysqldb = open(dbHost, dbUser, dbPasswd, dbUse)
    defer: mysqldb.close()
    mysqldb.getValue(sql"select buyTime from account where publicKey=?", value)

template log(s:string):untyped =
    echo s
    logFile.writeLine(s)

template upgradeHero(tokenId: UInt256):untyped {.dirty.} = 
    var unlockPrice = await bnbHero.getPriceToUnlockLevel(tokenId).call()
    log &"升级英雄费用{get6decimal unlockPrice}"
    if bnbhBalance > unlockPrice:
      var tx = await bnbHero.unLockLevel(tokenId).send(gas=210000, gasPrice=5000000000.u256)
      log &"升级英雄交易记录: {tx}"
    else:
      var tx = await mainbnbhToken.transfer(Web3.defaultAccount, unlockPrice).send(gas=210000, gasPrice=5000000000.u256)
      log &"升级英雄余额不足转账交易记录: {tx}"
      borrow(bnbh = unlockPrice)

template borrow(bnb,bnbh:Uint256 = 0.u256):untyped {.dirty.} =
  if mainAddress == borrowFrom:
    borrowBNB += bnb
    borrowBNBH += bnbh

proc fight() {.async.} =
  {.gcsafe.}:
    var j = parseFile("config.json")
    var logFile = newFileStream("log", fmAppend)
    defer: logFile.close()
    var mainWeb3 = await newWeb3("https://bsc-dataseed.binance.org")
    defer: await mainWeb3.close()
    var mainPrivateKey = PrivateKey.fromHex(j["main"].getStr).get()
    mainWeb3.privateKey = some(mainPrivateKey)
    mainWeb3.defaultAccount = Address.fromHex mainWeb3.privateKey.get().toPublicKey().toAddress()
    var mainAddress = mainWeb3.privateKey.get().toPublicKey().toAddress()
    let mainbnbhToken = mainWeb3.contractSender(BNBHToken, bnbhTokenAddress)

    var borrowBNB: Uint256
    var borrowBNBH: Uint256

    let priceOracle = mainWeb3.contractSender(PriceOracle, priceOracleAddress)
    var upgradeTownPrices = await priceOracle.getTownUpgradePrices().call()
    var getCharacterPrice = await priceOracle.getCharacterPrice().call()
    var getExpeditePrice = await priceOracle.getExpeditePrice().call()
    var web3Address: string
    log &"upgradeTownPrices: {get6decimal upgradeTownPrices[13]}"
    log &"getCharacterPrice: {get6decimal getCharacterPrice}"
    log &"getExpeditePrice: {get6decimal getExpeditePrice}"

    var skip:int
    while true:
      if skip == j["fight"].len * 2:
        echo "本轮战斗结束"
        break
      skip = 0
      var requireTime = 0
      for key in j["fight"]:
        try:
          var privateKey = PrivateKey.fromHex(key.getStr).get()
          var Web3 = await newWeb3("https://bsc-dataseed.binance.org")
          
          Web3.privateKey = some(privateKey)
          web3Address = Web3.privateKey.get().toPublicKey().toAddress()
          Web3.defaultAccount = Address.fromHex web3Address

          var buyTime = getBuytime(web3Address)
          if buyTime == "": 
            requireTime.inc
            raise newException(ValueError, &"{web3Address}没有时间了，快进到碗里来")
          elif buyTime.parseInt < toUnix(getTime() - 30.days):
            requireTime.inc
            raise newException(ValueError, &"{web3Address}时间用完了，快续费吧！")
          if requireTime == j["fight"].len: 
            raise newException(ValueError, &"战斗账号都不可用，准备退出！")
          var bnbBalance = await Web3.provider.eth_getBalance(Web3.defaultAccount, "latest")
          let bnbhToken = Web3.contractSender(BNBHToken, bnbhTokenAddress)
          var bnbhBalance = await bnbhToken.balanceOf(Web3.defaultAccount).call()
          # log &"{now()} {web3Address} BNB余额{get6decimal bnbBalance} BNBH余额{get6decimal bnbhBalance}"
          var bnbLeast = 10*(10.u256.pow(15))
          if bnbBalance < bnbLeast:
            var mainbnbBalance = await mainWeb3.provider.eth_getBalance(mainWeb3.defaultAccount, "latest")
            if mainbnbBalance > bnbLeast:
              var nonce = await mainWeb3.nextNonce()
              var cc = EthSend( 
                data: "0x" ,
                source: mainWeb3.defaultAccount,
                to: some(Web3.defaultAccount),
                gas: some(Quantity(300000)),
                value: some(bnbLeast),
                nonce: some(nonce),
                gasPrice: some(5000000000.u256)
              )
              var sendTx = await mainWeb3.send(cc)
              log &"gas余额不足转账{web3Address}交易记录: {sendTx}"
              borrow(bnbLeast)
            else:
              log &"gas转账主账号BNB余额不足"

          let bnbHero = Web3.contractSender(BNBHero, bnbHeroAddress)
          var web3AddressAllowance = await bnbhToken.allowance(Web3.defaultAccount, bnbHeroAddress).call()
          if web3AddressAllowance < UINT256MAX div 2:
            # echo &"{web3Address}限额：", web3AddressAllowance
            var tx = await bnbhToken.approve(bnbHeroAddress, UINT256MAX).send(gas=210000, gasPrice=5000000000.u256)
            log &"BNBH授权bnbHero交易记录: {tx}"

          var mainAccountAllowance = await bnbhToken.allowance(mainWeb3.defaultAccount, Web3.defaultAccount).call()
          if mainAccountAllowance < UINT256MAX div 2:
            # echo "主账号限额: ", mainAccountAllowance
            var tx = await mainbnbhToken.approve(Web3.defaultAccount, UINT256MAX).send(gas=210000, gasPrice=5000000000.u256)
            log &"主账号给战斗账号授权BNBH: {tx}"
          var towns = await bnbHero.getTownsOfPlayer(Web3.defaultAccount).call()
          var trainingGround = towns[3]
          var diff = now().toTime.toUnix() - trainingGround.lastUpgradedTimeStamp.toInt() - 24.hours.seconds
          var upgradeTime = trainingGround.lastUpgradedTimeStamp.toInt().fromUnix().format("yyyy-MM-dd HH:mm:ss")
          # echo &"{web3Address} 训练场: 等级{trainingGround.level} 最近升级时间{upgradeTime}"
          if (trainingGround.level == 0 and trainingGround.lastUpgradedTimeStamp == 0):
            if bnbhBalance > upgradeTownPrices[13]:
              var tx = await bnbHero.upgradeTown(3.stuint(8)).send(gas=210000, gasPrice=5000000000.u256)
              bnbhBalance = await bnbhToken.balanceOf(Web3.defaultAccount).call()
              log &"升级城镇交易记录: {web3Address} {tx}"
            else:
              var tx = await bnbhToken.transferFrom(mainWeb3.defaultAccount, Web3.defaultAccount, upgradeTownPrices[13]).send(gas=210000, gasPrice=5000000000.u256)
              log &"升级城镇余额不足转账升级费用交易记录: {web3Address} {tx}"
              borrow(bnbh = upgradeTownPrices[13])

          var heroes = await bnbHero.getHeroesByOwner(Web3.defaultAccount, Bool.parse(false)).call()
          if heroes.len < 2:
            if bnbhBalance > getCharacterPrice:
              var createHeroTx = waitFor bnbHero.createNewHero().send(gas=500000, gasPrice=5000000000.u256)
              # echo &"创建英雄交易记录: {createHeroTx}"
              bnbhBalance = await bnbhToken.balanceOf(Web3.defaultAccount).call()
            else:
              var mainbnbhBalance = await bnbhToken.balanceOf(mainWeb3.defaultAccount).call()
              if mainbnbhBalance > getCharacterPrice + 1 :
                var tx = await bnbhToken.transferFrom(mainWeb3.defaultAccount, Web3.defaultAccount, getCharacterPrice - bnbhBalance + 1).send(gas=210000, gasPrice=5000000000.u256)
                log &"创建英雄余额不足转账BNBH: {tx}" 
                borrow(bnbh = getCharacterPrice - bnbhBalance + 1)
              else:
                log &"创建英雄主账号BNBH余额不足"
            heroes = await bnbHero.getHeroesByOwner(Web3.defaultAccount, Bool.parse(false)).call()

          for hero in heroes:
            if hero.arrivalTime != 0:
              bnbhBalance = await bnbhToken.balanceOf(Web3.defaultAccount).call()
              if bnbhBalance > getExpeditePrice:
                var tx = waitFor bnbHero.expediteHero(hero.tokenId).send(gas=150000, gasPrice=5000000000.u256)
              else:
                var mainbnbhBalance = await bnbhToken.balanceOf(mainWeb3.defaultAccount).call()
                if mainbnbhBalance > getExpeditePrice + 1 :
                  var tx = await bnbhToken.transferFrom(mainWeb3.defaultAccount, Web3.defaultAccount, getExpeditePrice - bnbhBalance + 1).send(gas=210000, gasPrice=5000000000.u256)
                  log &"加速英雄余额不足转账BNBH: {tx}" 
                  borrow(bnbh = getExpeditePrice - bnbhBalance + 1)
                else:
                  log &"加速英雄主账号BNBH余额不足"
            if (hero.level.toInt() <= 10 or hero.level.toInt() >= 41) and hero.xp == hero.level * 1000 + 999:
              upgradeHero(hero.tokenId)
            elif (hero.level.toInt in 11..20) and hero.xp == (hero.level - 10) * 2000 + 10*1000 + 999:
              upgradeHero(hero.tokenId)
            elif hero.level.toInt in 21..30 and hero.xp == (hero.level - 20) * 2500 + 10*2000 + 10*1000 + 999:
              upgradeHero(hero.tokenId)
            elif hero.level.toInt in 31..40 and hero.xp == (hero.level - 30)* 3000 + 10*2500 + 10*2000 + 10*1000 + 999:
              upgradeHero(hero.tokenId)
            if hero.arrivalTime == 0:
              if hero.hp >= 200:
                var fightTx = await bnbHero.fight(hero.tokenId, 5.u256).send(gas=210000, gasPrice=5000000000.u256)
                var message = &"{getDateStr()} {getClockStr()} 英雄:{hero.tokenId} 等级:{hero.level} 类型: {hero.heroType} 经验:{hero.xp} 生命值:{hero.hp} 地址: {web3Address}"
                log message
              else:
                skip.inc
          await Web3.close()
          # sleep(1000)
        except:
          log &"{web3Address} {getCurrentExceptionMsg()}"
          if requireTime == j["fight"].len: 
            log "战斗账号都不可用，准备退出！"
            quit()
          continue
    log &"借BNB: {borrowBNB}"
    log &"借BNBH: {borrowBNBH}"

# var param = paramStr(1)
# var file: string
# if scanf(param, "--configFile=$w", file):
#   file = file & ".json"
#   var j = parseFile(file)
#   if j["main"].getStr != "" and j["fight"].len > 0:
waitFor fight()
