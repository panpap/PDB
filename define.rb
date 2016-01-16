class Defines
	attr_accessor :traceFile, :beaconDBTable, :beaconDB, :impTable, :bcnTable,:adsTable,:userTable,:priceTable,:filterFile, :parseResults, :userDir, :dirs, :files, :inria, :subStrings, :dataDir, :tmln_path, :beacon_key, :imps, :keywords, :adInParam, :rtbCompanies, :browsers
	
	def initialize(filename)
		@column_Format={'100k_trace'=>1,'10k_trace'=>1 ,
			'full_trace'=>1, 	#awazza dataset 6million reqs
			'souneil_trace'=>2,"soun10_trace"=>2} 	#awazza dataset 1million reqs

		if filename==nil
			puts "Warning: Using pre-defined input file..."
			@traceFile='100k_trace'
		else
			@traceFile=filename
		end
		if not File.exist?(@traceFile)
			abort("Error: Input file <"+filename+"> could not be found!")
		end

		@beaconDBTable="beaconURLs"
		@impTable="impressions"		
		@bcnTable="beacons"
		@adsTable="advertisements"
		@userTable="userResults"
		@priceTable="prices"
		@beaconDB="beaconsDB.db"

		#DIRECTORIES
		@dirs=Hash.new
		@dataDir="dataset/"
		@userDir="users/"
		@tmln_path="timelines/"
		@dirs['rootDir']="results_"+@traceFile+"/"
		@dirs['dataDir']=@dirs['rootDir']+@dataDir
		@dirs['adsDir']=@dirs['rootDir']+"adRelated/"
		@dirs['userDir']=@dirs['rootDir']+@userDir
		@dirs['timelines']=@dirs['userDir']+@tmln_path
		@resources='resources/'

		#FILENAMES
		@files=Hash.new
		@files['parseResults']=@dirs['rootDir']+"results.out"
		#@files['impFile']=@dirs['adsDir']+"impressions.out"
		#@files['adfile']=@dirs['adsDir']+"ads.out"
		#@files['prices']=@dirs['adsDir']+"prices.csv"
		@files['priceTagsFile']=@dirs['adsDir']+"priceTags"
		@files['devices']=@dirs['adsDir']+"devices.csv"
		#@files['bcnFile']=@dirs['adsDir']+"beacons.out"
		@files['size3rdFile']=@dirs['adsDir']+"sizes3rd.csv"
		@files['paramsNum']=@dirs['adsDir']+"paramsNum.csv"
		@files['adDevices']=@dirs['adsDir']+"adDevices.csv"
		#@files['beaconT']=@dirs['adsDir']+"beaconsTypes.csv"
		@files['userFile']=@dirs['userDir']+"userAnalysis.csv"
		@files['publishers']=@dirs['adsDir']+"publishers.csv"
		@files['leftovers']="leftovers.out"
		@files['formatFile']="format.in"
		@filterFile=@resources+'disconnect_merged.json'

		#KEYWORDS
		@beacon_key=["beacon","pxl","pixel","adimppixel","data.gif","px.gif","pxlctl"]

		@imps=["impression","_imp","/imp","imp_"]

		@keywords=["price","pp","pr","bidprice","bid_price","bp","winprice", "computedprice", "pricefloor",
		               "win_price","wp","chargeprice","charge_price","cp","extcost","tt_bidprice","bdrct",
		               "ext_cost","cost","rtbwinprice","rtb_win_price","rtbwp","bidfloor","seatbid"]

		@inria={ "rfihub.net" => "ep","invitemedia.com" => "cost","scorecardresearch.com" => "uid", 
				"ru4.com" => "_pp","tubemogul.com" => "x_price", "invitemedia.com" => "cost", 
			"tubemogul.com" => "price", #"bluekai.com" => "phint", 
			"adsrvr.org" => "wp",  
			"pardot.com" => "title","tubemogul.com" => "price","mathtag.com" => "price",
			"adsvana.com" => "_p", "doubleclick.net" => "pr", "ib.adnxs.com" => "add_code", 
			"turn.com" => "acp", "ams1.adnxs.com" => "pp",  "mathtag.com" => "price",
			"youtube.com" => "description1", "quantcount.com" => "p","rfihub.com" => "ep",
			"w55c.net" => "wp_exchange", "adnxs.com" => "pp", "gwallet.com" => "win_price",
			"criteo.com" => "z"}

		# ENHANCED BY ADBLOCK EASYLIST
		@subStrings=["/Ad/","pagead","/adv/","/ad/","ads",".ad","rtb-","adwords","admonitoring","adinteraction",
					"adrum","adstat","adviewtrack","adtrk","/Ad","bidwon","/rtb"] #"market"]	

		@rtbCompanies=["adkmob","green.erne.co","bidstalk","openrtb","eyeota","ad-x.co.uk",
				"qservz","hastrk","api-","clix2pix.net","exoclick"," clickadu","waiads.com","taptica.com","mediasmart.es"]

		@adInParam=["ad_","ad_id","adv_id","bid_id","adpos","adtagid","rtb","adslot","adspace","adUrl", "ads_creative_id", 
				"creative_id","adposition","bidid","adsnumber","bidder","auction","ads_",
				"adunit", "adgroup", "creativity","bid_","bidder_"]

		@browsers=['dolphin', 'gecko', 'opera','webkit','mozilla','gecko','browser','chrome','safari']
	end

	def column_Format()
		return @column_Format[@traceFile]
	end
end
