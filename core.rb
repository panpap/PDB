load 'convert.rb'
load 'trace.rb'
load 'csync_detector.rb'
load 'filters.rb'
require 'digest/sha1'

class Core
	attr_writer :window, :cwd
	attr_accessor :database, :skipped
   	@isBeacon=false

	def initialize(defs,filters)
		@defines=defs
		@skipped=0
		@convert=Convert.new(@defines)
		@filters=filters
		@trace=Trace.new(@defines)
		@webTrace=Trace.new(@defines)
		@appTrace=Trace.new(@defines)		
		@csync=CSync.new(@filters,@trace,@defines.options["webVsApp?"],@webTrace,@appTrace)
		@options=@defines.options
		@window=-1
		@cwd=nil
		@database=nil
	end
	
	def makeDirsFiles()
		@defines.puts "> Creating Directories..., "
		Dir.mkdir @defines.dirs['rootDir'] unless File.exists?(@defines.dirs['rootDir'])
		Dir.mkdir @defines.dirs['dataDir'] unless File.exists?(@defines.dirs['dataDir'])
		Dir.mkdir @defines.dirs['adsDir'] unless File.exists?(@defines.dirs['adsDir'])
		Dir.mkdir @defines.dirs['userDir'] unless File.exists?(@defines.dirs['userDir'])
		Dir.mkdir @defines.dirs['timelines'] unless File.exists?(@defines.dirs['timelines'])	
		@database=Database.new(@defines,nil)
		if @options["database?"]
			@defines.puts "and database tables..."
			@defines.tables.values.each{|fields| @database.create(fields.keys.first,fields.values.first)}
		end
	end

	def analysis
		options=@options['resultToFiles']
		@defines.puts "> Stripping parameters, detecting and classifying Third-Party content..."
		fw=nil
		@defines.puts "> Dumping to files..."
		if options[@defines.files['devices'].split("/").last] and not File.size?@defines.files['devices']
			fd=File.new(@defines.files['devices'],'w')
			@trace.devs.each{|dev| 
				if dev!=-1
					for k in dev.keys
						fd.print dev[k].to_s+"\t"
					end
				end
				fd.puts}
			fd.close
		end
		if options[@defines.files['restParamsNum'].split("/").last] and not File.size?@defines.files['restParamsNum']
			fpar=File.new(@defines.files['restParamsNum'],'w')
			@trace.restNumOfParams.each{|p| fpar.puts p}
			fpar.close
		end
		if options[@defines.files['adParamsNum'].split("/").last] and not File.size?@defines.files['adParamsNum']
			fpar=File.new(@defines.files['adParamsNum'],'w')
			@trace.adNumOfParams.each{|p| fpar.puts p}
			fpar.close
		end
		if options[@defines.files['size3rdFile'].split("/").last] and not File.size?@defines.files['size3rdFile']
			fsz=File.new(@defines.files['size3rdFile'],'w')
			@trace.sizes.each{|sz| fsz.puts sz}
			fsz.close
		end
		total=Thread.new {
			@defines.puts "> Calculating Statistics about detected ads..."
			@defines.puts "---> Internal CSync: "+@csync.samepartyCS.to_s if @options['tablesDB'][@defines.tables["csyncTable"].keys.first]
			@defines.puts @trace.results_toString(0,@database,@defines.tables['traceTable'])
			@trace.dumpRes(@database,@defines.tables['traceTable'],@defines.tables['bcnTable'],@defines.tables['advertiserTable'])
			if @defines.options["webVsApp?"]
				@defines.puts @webTrace.results_toString(1, @database,@defines.tables['webTraceTable'])
				@webTrace.dumpRes(@database,@defines.tables['webTraceTable'],nil,nil)
				@defines.puts @appTrace.results_toString(2,@database,@defines.tables['appTraceTable'])
				@appTrace.dumpRes(@database,@defines.tables['appTraceTable'],nil,nil)
			end
		}
		perUserAnalysis()
		total.join
	end

	def findStrInRows(str)
		for val in r.values do
			if val.include? str
				if(printable)
					url=r['url'].split('?')
					Utilities.printRow(r,STDOUT)
				end
				found.push(r)					
				break
			end
		end
	end

	def parseRequest(row)
		if row['ua']!=-1
			mob,dev,browser=reqOrigin(row)		#CHECK THE DEVICE TYPE
			row['mob']=mob
			row['dev']=dev
			row['browser']=browser	
			if @options["mobileOnly?"] and mob!=1
				@skipped+=1
				return false
			else
				@trace.mobDev+=1
				if @defines.options["webVsApp?"]
					if row['browser']!="unknown"
						@webTrace.mobDev+=1
					else
						@appTrace.mobDev+=1
					end
				end
			end		#FILTER ROW
			@trace.fromBrowser+=1 if browser!= "unknown"
		end
		cat=filterRow(row)
		cookieSyncing(row,cat) if @options['tablesDB'][@defines.tables["csyncTable"].keys.first]
		return true
	end

	def readUserAcrivity(tmlnFiles)
		@defines.puts "> Loading "+tmlnFiles.size.to_s+" User Activity files..."
		user_path=@cwd+@defines.userDir
		timeline_path=@cwd+@defines.userDir+@defines.tmln_path
		for tmln in tmlnFiles do
			createTmlnForUser(tmln,timeline_path,user_path)
		end
	end

	def createTimelines()
		@defines.puts "> Contructing User Timelines..."
		user_path=@cwd+@defines.userDir
		timeline_path=@cwd+@defines.userDir+@defines.tmln_path
		fr=File.new(@cwd+@defines.dataDir+"IPport_uniq",'r')
		while l=fr.gets
			user=l.chop
			fw=File.new(timeline_path+user+"_per"+(@window/1000).to_s+"sec",'w')
			IO.popen('grep '+user+' ./'+@defines.traceFile) { |io| 
			firstTime=-1
			while (line = io.gets) do 
				h=Format.columnsFormat(line,@defines.column_Format)
				Utilities.separateTimelineEvents(h,user_path+h['IPport'],@defines.column_Format)
				firstTime=h['tmstp'].to_i if firstTime==-1
				applyTimeWindow(firstTime,row,fw)
			end }
			fw.close
		end
		fr.close
	end

	def cookieSyncing(row,cat)
		firstSeenUser?(row)
		@csync.checkForSync(row,cat)
	#	puts row['url']+" "+ids.to_s if ids>0
	end

	def csyncResults()
		if @database!=nil
			@defines.puts "> Dumping Cookie synchronization results..."	
			@trace.dumpUserRes(@database,@filters,@convert,true,0)	
		end
	end
#------------------------------------------------------------------------------------------------


	private

	def firstSeenUser?(row)
		@curUser=row['IPport']
		@trace.users[@curUser]=User.new	if @trace.users[@curUser]==nil		#first seen user
		if @defines.options["webVsApp?"]
			if row['browser']!="unknown" 
				@webTrace.users[@curUser]=User.new if @webTrace.users[@curUser]==nil
			else
				@appTrace.users[@curUser]=User.new if @appTrace.users[@curUser]==nil
			end
		end
		if @trace.users[@curUser].uIPs[row['uIP']]==nil
			@trace.users[@curUser].uIPs[row['uIP']]=1
		else
			@trace.users[@curUser].uIPs[row['uIP']]+=1
		end
	end

	def	createTmlnForUser(tmln,timeline_path,user_path)
		if not tmln.eql? '.' and not tmln.eql? ".." and not File.directory?(user_path+tmln)
			fr=File.new(user_path+tmln,'r')
			fw=nil
			firstTime=-1
			bucket=0
			startBucket=-1
			endBucket=-1
			c=0
			while line=fr.gets
				r=Format.columnsFormat(line,@defines.column_Format)
				mob,dev,browser=reqOrigin(r)
				@trace.mobDev+=1 if mob==1
				row['mob']=mob
				row['dev']=dev
				row['browser']=browser
				if browser!=nil
					if firstTime==-1
						fw=File.new(timeline_path+tmln+"_per"+@window.to_s+"msec",'w')
						firstTime=r['tmstp'].to_i
						startBucket=firstTime
					end
					nbucket=applyTimeWindow(firstTime,r,fw)
					if bucket!=nbucket						
						fw.puts "\n"+startBucket.to_s+" : "+endBucket.to_s+"-> BUCKET "+bucket.to_s
						fw.puts @trace.results_toString(@database,nil,nil)+"\n"
						bucket=nbucket
						@trace=Trace.new(@defines)
						startBucket=r['tmstp']
					end
					@curUser=r['IPport']
					@trace.users[@curUser]=User.new	 if @trace.users[@curUser]==nil		#first seen user
					filterRow(r)
					@trace.rows.push(r)
					fw.puts c.to_s+") BUCKET "+bucket.to_s+"\t"+r['tmstp']+"\t"+r['url']+"\t"+r['ua']
					endBucket=r['tmstp'].to_i
					c+=1
				end
			end
			if startBucket!=-1 && endBucket!=-1
				fw.puts "\n"+startBucket.to_s+" : "+endBucket.to_s+"-> BUCKET "+bucket.to_s
				fw.puts @trace.results_toString(@database,nil,nil)+"\n"
			end
			@trace=Trace.new(@defines)
			fr.close
			fw.close if fw!=nil
		end
	end

	def applyTimeWindow(firstTime,row,fw)
		diff=row['tmstp'].to_i-firstTime
		wnum=diff.to_f/@window.to_i
		return wnum.to_i
	end	

	def reqOrigin(row)
		#CHECK IF ITS MOBILE USER
		mob,dev=@filters.is_MobileType?(row)   # check the device type of the request
		#CHECK IF ITS ORIGINATED FROM BROWSER
		browser=@filters.is_Browser?(row,dev)
#		dev=dev.to_s.gsub("[","").gsub("]","")
        @trace.devs.push(dev)
		if @defines.options["webVsApp?"]
			if row['browser']!="unknown"
				@webTrace.devs.push(dev)
			else
				@appTrace.devs.push(dev)
			end
		end
		return mob,dev,browser
	end		

	@@lastSeenTmpstp=nil
	def isItDuplicate?(row)
		return false if not @options["removeDuplicates?"]
		if @@lastSeenTmpstp==row['tmstp'] #same row
			return false
		else
			@@lastSeenTmpstp=row['tmstp']
		end
		url=row['url'].split("?")
		return false if url.size==1
		footPrnt=Digest::SHA256.hexdigest(url.last)
		if @trace.paramDups[footPrnt]==nil
			@trace.paramDups[footPrnt]=Hash.new
			@trace.paramDups[footPrnt]["url"]=row['url'] 
			@trace.paramDups[footPrnt]["count"]=0
			@trace.paramDups[footPrnt]['tmpstp']=Array.new
		end
		@trace.paramDups[footPrnt]["count"]+=1
		@trace.paramDups[footPrnt]["tmpstp"].push(row['tmstp'])
		return true if @trace.paramDups[footPrnt]["count"]>1 # It is indeed duplicate	
		return false
	end

	def categorizeReq(row,urlParts)	
		publisher=nil
		type3rd=@filters.getCategory(urlParts,Utilities.calculateHost(row['url'],row['host']),@curUser)
        @isBeacon=false
        params, isRTB=checkForRTB(row,urlParts,publisher,(type3rd.eql? "Advertising"))      #check ad in URL params
        if isRTB==false	#noRTB
	        if @filters.is_Beacon?(row,row['type']) 		#findBeacon in URL
        	    beaconSave(urlParts.first,row)
				collectAdvertiser(row) if type3rd=="Advertising" #adRelated Beacon
				type3rd="Beacons"
        	else #noRTB no Beacon
				isRTB=detectImpressions(urlParts,row)
			end
		end
		type3rd="Advertising" if isRTB==true
		return type3rd,params
	end

	def filterRow(row)
		firstSeenUser?(row)
		type3rd=nil
		@isBeacon=false
		url=row['url'].split("?")
		@trace.sizes.push(row['dataSz'].to_i)
		if @defines.options["webVsApp?"]
			if row['browser']!="unknown"
				@webTrace.sizes.push(row['dataSz'].to_i)
			else
				@appTrace.sizes.push(row['dataSz'].to_i)
			end
		end
		type3rd,params=categorizeReq(row,url)
		noOfparam=params.size
		if type3rd!=nil and type3rd!="Beacons" # 3rd PARTY CONTENT
			collector(type3rd,row)
			@trace.party3rd[type3rd]+=1
			if @defines.options["webVsApp?"]
				if row['browser']!="unknown"
					@webTrace.party3rd[type3rd]+=1
				else
					@appTrace.party3rd[type3rd]+=1
				end
			end
			if not type3rd.eql? "Content"
				if type3rd.eql? "Advertising"
					ad_detected(row,noOfparam,url)
				else # SOCIAL or ANALYTICS or OTHER type
					@trace.restNumOfParams.push(noOfparam.to_i)
					if @defines.options["webVsApp?"]
						if row['browser']!="unknown"
							@webTrace.restNumOfParams.push(noOfparam.to_i)
						else
							@appTrace.restNumOfParams.push(noOfparam.to_i)
						end
					end
				end
			else	#CONTENT type
				@trace.restNumOfParams.push(noOfparam.to_i)
				if @defines.options["webVsApp?"]
					if row['browser']!="unknown"
						@webTrace.restNumOfParams.push(noOfparam.to_i)
					else
						@appTrace.restNumOfParams.push(noOfparam.to_i)
					end
				end
			end
		else	# Rest
			type3rd="Other"
			@trace.party3rd[type3rd]+=1
			if @defines.options["webVsApp?"]
				if row['browser']!="unknown"
					@webTrace.party3rd[type3rd]+=1
				else
					@appTrace.party3rd[type3rd]+=1
				end
			end
			if (row['browser']!="unknown") and (@options['tablesDB'][@defines.tables["publishersTable"].keys[0]] or @options['tablesDB'][@defines.tables["userTable"].keys[0]])
				@trace.users[@curUser].publishers.push(row)
			end
			#Utilities.printStrippedURL(url,@fl)	# dump leftovers
			collector(type3rd,row)
		end
		collectInterests(url.first,type3rd)
		return type3rd
	end

	def collectInterests(url,type3rd)
		if @options['tablesDB'][@defines.tables["visitsTable"].keys.first] and (type3rd=="Other" )#or type3rd=="Content") 
			site=url
			site=url.split("://").last if url.include? "://"
			domain=site.split("/").first
			@trace.users[@curUser].pubVisits[domain]=0 if @trace.users[@curUser].pubVisits[domain]==nil
			@trace.users[@curUser].pubVisits[domain]+=1
			topics=nil
			if topics!=nil and topics!=-1
				@trace.users[@curUser].interests=Hash.new(0) if @trace.users[@curUser].interests==nil
				topics.each{|key, value| @trace.users[@curUser].interests[key]+=value}
			end
		end
	end

	def collector(contenType,row)
		type=row['types']
		if @options['tablesDB'][@defines.tables["userTable"].keys.first]
			@trace.users[@curUser].size3rdparty[contenType].push(row['dataSz'].to_i)
			@trace.users[@curUser].dur3rd[contenType].push(row['dur'].to_i)
			if @defines.options["webVsApp?"]
				if row['browser']!="unknown"
					@webTrace.users[@curUser].size3rdparty[contenType].push(row['dataSz'].to_i)
					@webTrace.users[@curUser].dur3rd[contenType].push(row['dur'].to_i)					
				else
					@appTrace.users[@curUser].size3rdparty[contenType].push(row['dataSz'].to_i)
					@appTrace.users[@curUser].dur3rd[contenType].push(row['dur'].to_i)
				end
			end
		end
		if type!=-1 and @options['tablesDB'][@defines.tables["userFilesTable"].keys.first]
			if @trace.users[@curUser].fileTypes[contenType]==nil
				@trace.users[@curUser].fileTypes[contenType]={"data"=>Array.new, "gif"=>Array.new,"html"=>Array.new,"image"=>Array.new,"other"=>Array.new,"script"=>Array.new,"styling"=>Array.new,"text"=>Array.new,"video"=>Array.new} 
			end
			@trace.users[@curUser].fileTypes[contenType][type].push(row['dataSz'].to_i)
			if @defines.options["webVsApp?"]
				if row['browser']!="unknown"
					if @webTrace.users[@curUser].fileTypes[contenType]==nil
						@webTrace.users[@curUser].fileTypes[contenType]={"data"=>Array.new, "gif"=>Array.new,"html"=>Array.new,"image"=>Array.new,"other"=>Array.new,"script"=>Array.new,"styling"=>Array.new,"text"=>Array.new,"video"=>Array.new} 
					end
					@webTrace.users[@curUser].fileTypes[contenType][type].push(row['dataSz'].to_i)
				else
					if @appTrace.users[@curUser].fileTypes[contenType]==nil
					@appTrace.users[@curUser].fileTypes[contenType]={"data"=>Array.new, "gif"=>Array.new,"html"=>Array.new,"image"=>Array.new,"other"=>Array.new,"script"=>Array.new,"styling"=>Array.new,"text"=>Array.new,"video"=>Array.new} 
					end
					@appTrace.users[@curUser].fileTypes[contenType][type].push(row['dataSz'].to_i)
				end
			end

		end
	end

	def perUserAnalysis
		if @database!=nil
			@defines.print "> Dumping per user results to "
			if @options["database?"]
				@defines.puts "database..."
			else
				@defines.puts "files..."
			end
			@trace.dumpUserRes(@database,@filters,@convert,false,0)
			if @defines.options["webVsApp?"]
				@webTrace.dumpUserRes(@database,@filters,@convert,false,1)
				@appTrace.dumpUserRes(@database,@filters,@convert,false,2)
			end
		end
	end

    def detectPrice(row,keyVal,numOfPrices,numOfparams,publisher,isAdCat,https)     	# Detect possible price in parameters and returns URL Parameters in String
		domainStr=row['host']
		domain,tld=Utilities.tokenizeHost(domainStr)
		host=domain+"."+tld
		return false if @filters.priceFalsePositives.any? {|word| host.downcase.include?(word)}
		if (@filters.is_inInria_PriceTagList?(host,keyVal) or @filters.has_PriceKeyword?(keyVal)) 		# Check for Keywords and if there aren't any make ad-hoc heuristic check
			return false if isItDuplicate?(row)
			priceTag=keyVal[0]
			paramVal=keyVal[1]
			type=""
			priceVal,enc=@convert.calcPriceValue(paramVal,isAdCat)
			return false if priceVal==nil
			done=-1
			if enc
				type="numeric"
				return false if priceVal.to_f<0
				return false if priceVal.infinite?
			else
				type="encrypted"
				alfa,digit=Utilities.digitAlfa(paramVal)
				return false if (alfa<2 or digit<2) or priceVal.size<15
			end
			if @database!=nil
				id=Digest::SHA256.hexdigest (row.values.join("|")+priceTag+"|"+priceVal.to_s+"|"+type)
				time=row['tmstp']
				dsp,ssp,adx,publisher,adSize,carrier,adPosition=@filters.lookForRTBentitiesAndSize(row['url'],domainStr)
				interest,pubPopularity=@convert.analyzePublisher(publisher)
				if interest!=-1
					temp=Hash[interest.sort_by{|k,v| k}].to_s
					interest=temp.gsub(/[{}]/,"")
				end
				typeOfDSP=-1
				if dsp==nil or dsp==-1
					dsp=-1
				else
					typeOfDSP=@convert.advertiserType(dsp) 
				end
				adx=-1 if adx==nil
				ssp=-1 if ssp==nil
				publisher=-1 if publisher==nil
				upToKnowCM=@trace.users[@curUser].csync.size
				location=@convert.getGeoLocation(row['uIP'])
				location=-1 if location==nil 
				tod,day=@convert.getTod(time)
				params=[type,time,domainStr,priceTag,priceVal, row['dataSz'].to_i, upToKnowCM, numOfparams, adSize, carrier, adPosition,location,tod,day,publisher,interest,pubPopularity,row['IPport'],ssp,dsp,typeOfDSP,adx,row['mob'],row['dev'].to_s,row['browser'],https,row['url'],id]
				done=@database.insert(@defines.tables['priceTable'],params)
			end
			if @database==nil or done>-1
				if enc
					@trace.users[@curUser].numericPrices.push(priceVal)
					@trace.numericPrices+=1
					if @defines.options["webVsApp?"]
						if row['browser']!="unknown"
							@webTrace.users[@curUser].numericPrices.push(priceVal)
							@webTrace.numericPrices+=1
						else
							@appTrace.users[@curUser].numericPrices.push(priceVal)
							@appTrace.numericPrices+=1
						end
					end
				else
					@trace.users[@curUser].hashedPrices.push(priceVal)
					@trace.hashedPrices+=1
					if @defines.options["webVsApp?"]
						if row['browser']!="unknown"
							@webTrace.users[@curUser].hashedPrices.push(priceVal)
							@webTrace.hashedPrices+=1
						else
							@appTrace.users[@curUser].hashedPrices.push(priceVal)
							@appTrace.hashedPrices+=1
						end
					end
				end
			end
			return true
		end
		return false
    end

    def detectImpressions(url,row)     	#Impression term in path
        if @filters.is_Impression?(url[0])
			if @options['tablesDB'][@defines.tables["impTable"].keys.first]
				Utilities.printRowToDB(row,@database,@defines.tables['impTable'],nil)				
		    	@trace.users[@curUser].imp.push(row)
			end
			@trace.totalImps+=1
			return true
        end
		return false
    end

	def checkForRTB(row,url,publisher,adCat)
     	return 0,false if (url.last==nil)
		isAd=false
        fields=url.last.split('&')
		numOfPrices=0
		https=-1
		https=url.first.split(":").last if url.first.include?(":")
        for field in fields do
            keyVal=field.split("=")
            if(not @filters.is_GarbageOrEmpty?(keyVal)) and not url.first.include? "google" and not url.first.include? "eltenedor.es" and not url.first.include? "gosquared.com" and not url.first.include? "yaencontre.com" and not url.first.include? "bmw.es" and not url.first.include? "bing.com" and not url.first.include? "onswingers.com" and not url.first.include? "tusclasesparticulares.com" and not url.first.include? "ucm.es" and not url.first.include? "noticias3d.com" and not url.first.include? "loopme.me" and not url.first.include? "amap.com" and not url.first.include? "anyclip.com" and not url.first.include? "promorakuten.es" and not url.first.include? "scmspain.com" and not url.first.include? "shoppingshadow.com"
				#isAd=true if(@filters.is_Ad_param?(keyVal))
				if @options['tablesDB'][@defines.tables["priceTable"].keys.first]
					if detectPrice(row,keyVal,numOfPrices,fields.length,publisher,(adCat or isAd),https)
						numOfPrices+=1
					#	Utilities.warning ("Price Detected in Beacon\n"+row['url']) if @isBeacon
						isAd=true
					end
				end
			end
		end
		return fields,isAd
	end
			
	def beaconSave(url,row)         #findBeacons
		@isBeacon=true
		urlStr=url.split("%").first.split(";").first		
		temp=urlStr.split("/")	   #beacon type
		words=temp.size
		slashes=urlStr.count("/")
		last=temp[temp.size-1]
        temp=last.split(".")
		if (temp.size==1 or words==slashes)
			type="other"
        else
			last=temp[temp.size-1]
        	type=last
		end
		@trace.party3rd["Beacons"]+=1
		if @defines.options["webVsApp?"]
			if row['browser']!="unknown"
				@webTrace.party3rd["Beacons"]+=1
			else
				@appTrace.party3rd["Beacons"]+=1
			end
		end
		tmpstp=row['tmstp'];u=row['url']
		id=Digest::SHA256.hexdigest (row.values.join("|"))
		@trace.beacons.push([tmpstp,row['IPport'],u,type,row['mob'],row['dev'],row['browser'],id])
		collector("Beacons",row)
	end

	def ad_detected(row,noOfparam,url)
        @trace.users[@curUser].ads.push(row)
		@trace.adSize.push(row['dataSz'].to_i)
		if @defines.options["webVsApp?"]
			if row['browser']!="unknown"
				@webTrace.users[@curUser].ads.push(row)
				@webTrace.adSize.push(row['dataSz'].to_i)
			else
				@appTrace.users[@curUser].ads.push(row)
				@appTrace.adSize.push(row['dataSz'].to_i)
			end
		end
		collectAdvertiser(row)
		@trace.adNumOfParams.push(noOfparam.to_i)
		if @defines.options["webVsApp?"]
			if row['browser']!="unknown"
				@webTrace.adNumOfParams.push(noOfparam.to_i)
			else
				@appTrace.adNumOfParams.push(noOfparam.to_i)
			end
		end
	end

	def collectAdvertiser(row)
		if row!=nil and @options['tablesDB'][@defines.tables["advertiserTable"].keys.first]
			host=row['host']
			if @trace.advertisers[host]==nil
				@trace.advertisers[host]=Advertiser.new
				@trace.advertisers[host].durPerReq=Array.new
				@trace.advertisers[host].sizePerReq=Array.new
			end
			#@trace.advertisers[host].totalReqs+=1
			@trace.advertisers[host].reqsPerUser[@curUser]+=1
			@trace.advertisers[host].durPerReq.push(row['dur'].to_i)
			@trace.advertisers[host].sizePerReq.push(row['dataSz'].to_i)
			@trace.advertisers[host].type=@convert.advertiserType(host)
		end
	end
end
