require 'user'

class Trace
	attr_accessor :rows, :mobDev, :numOfMobileAds, :totalBeacons, :totalAdBeacons, :totalImps, :users, :detectedPrices, :party3rd, :sizes, :totalNumOfAds, :totalParamNum

	def initialize
		@rows=Array.new
		@mobDev=0
		@users=Hash.new
		@totalParamNum=Array.new
		@detectedPrices=Array.new
		@sizes=Array.new
		@totalImps=0
		@totalBeacons=0
		@totalAdBeacons=0
		@numOfMobileAds=0
		@totalNumOfAds=0
		@party3rd={"Advertising"=>0,"Social"=>0,"Analytics"=>0,"Content"=>0}
	end

	def getTotalVariables
		sums=Hash.new
		sums['numOfBeacons']=totalBeacons
		sums['numOfAdBeacons']=totalAdBeacons
		sums['numOfImps']=totalImps
		sums['numOfAds']=totalNumOfAds
		sums['numOfAdMobile']=numOfMobileAds
		return sums
	end

	def analyzeTotalAds    #Analyze global variables
		utils=Utilities.new
		utils.countInstances(@@paramsNum)
		utils.countInstances(@@devices)
		utils.countInstances(@@size3rdFile)
		sums=getTotalVariables()
		return utils.makeStats(@totalParamNum),utils.makeStats(@sizes),sums
	end
end
