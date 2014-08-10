PluginInit = {}

local LrDate = import "LrDate"
local LrDialogs = import "LrDialogs"
local LrHttp = import "LrHttp"
local LrFunctionContext = import "LrFunctionContext"
local LrTasks = import "LrTasks"

local logger = import "LrLogger"("500pxPublisher")
logger:enable("logfile")

local lastCheck = 0

-- Deprecated
-- function PluginInit.checkForUpdates()
-- 	LrFunctionContext.postAsyncTaskWithContext( "update check",  function(context)
-- 		local time = LrDate.currentTime()
-- 		if time - lastCheck >= 86400 then
-- 			local response, headers = LrHttp.get( "https://api.500px.com/v1/version/lightroom" )
-- 			if headers and headers.status == 200 then
-- 				lastCheck = time
-- 				Plugin.outOfDate = (tostring( string.gsub( response, "%s+", "" ) )  == "0.1.8.0" )
-- 			end
-- 		end
-- 	end )
-- end

function PluginInit.forceNewCollections()
	local LrApplication = import "LrApplication"
	LrFunctionContext.postAsyncTaskWithContext( "New Collections", function(context)
		local catalog = LrApplication:activeCatalog()

		for _, publishService in ipairs( catalog:getPublishServices( _PLUGIN.id ) ) do
			local allPhotosCollection
			local profileCollection

			catalog:withPrivateWriteAccessDo( "New Collections", function()
				for _, collection in ipairs( publishService:getChildCollections() ) do
					if collection:getName() == "Library" or collection:getName() == "Organizer" then
						collection:setName( "Library" )
						collection:setCollectionSettings( { toCummunity = false } )
						allPhotosCollection = collection
					end
				end

				profileCollection = publishService:createPublishedCollection( "Public Profile", nil, false )
				if profileCollection then
					profileCollection:setCollectionSettings( { toCummunity = true } )
				end
			end )

			if profileCollection then
				catalog:withWriteAccessDo( "", function()
					for _, collection in ipairs( publishService:getChildCollections() ) do
						local isAllPhotos = ( collection:getName() == "Library" )
						for _, publishedPhoto in ipairs( collection:getPublishedPhotos() ) do
							local photoId
							local photoUrl
							local photo = publishedPhoto:getPhoto()
							catalog:withReadAccessDo( function()
								photoId = photo:getPropertyForPlugin( _PLUGIN, "photoId" )
								photoUrl = string.format( "http://500px.com/photo/%s", photoId )
							end )

							if isAllPhotos then
								profileCollection:addPhotoByRemoteId( photo, string.format( "%s-profile", photoId ), photoUrl, true )
							else
								allPhotosCollection:addPhotoByRemoteId( photo, string.format( "%s-nil", photoId ), photoUrl, true )
							end
						end
					end
				end )
			end
		end
	end )
end

local locked = false

function PluginInit.lock()
	local delay = 0.1
	repeat
		LrTasks.sleep( delay )
		delay = delay * 2
	until not locked

	locked = true
	return true
end

function PluginInit.unlock( )
	locked = false
end

PluginInit.outOfDate = false
