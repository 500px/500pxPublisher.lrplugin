PluginInit = {}

local LrDate = import "LrDate"
local LrDialogs = import "LrDialogs"
local LrHttp = import "LrHttp"
local LrFunctionContext = import "LrFunctionContext"
local LrTasks = import "LrTasks"
local prefs = import 'LrPrefs'.prefsForPlugin()
local LrView = import "LrView"
local LrBinding = import "LrBinding"
local bind = LrView.bind

local logger = import "LrLogger"("500pxPublisher")
logger:enable("logfile")

require "500pxAPI"

function formatVersion( v )
	return v["major"] .. "." .. v["minor"] .. "." .. v["revision"]
end

function PluginInit.checkForUpdates()
	LrFunctionContext.postAsyncTaskWithContext( "Update Check", function(context)
		local lastCheck = prefs.lastUpdateCheck
		if not lastCheck then
			lastCheck = 0
		end

		local time = LrDate.currentTime()
		if time - lastCheck < 86400 then
			return
		end

		prefs.lastUpdateCheck = time

		local info = require "Info"
		local currentVersion = info["VERSION"]
		local latestVersion = PxAPI.getLatestVersion()

		-- The user has previously seen and ignored this version
		if formatVersion(latestVersion) == prefs.seenVersion then
			return
		end

		if latestVersion and PxAPI.compareVersions( latestVersion, currentVersion ) > 0 then
			local f = LrView.osFactory()
			local props = LrBinding.makePropertyTable( context )
			props.dontcheck = false

			local result = LrDialogs.presentModalDialog( {
				title = "500px Plugin Update Available",
				resizable = false,
				actionVerb = "Download Now",
				cancelVerb = "Not Now",
				contents = f:view {
					spacing = f:control_spacing(),
					bind_to_object = props,
					f:static_text {
						title = "There is an update available for the 500px plugin. You should update to receive the latest features and fixes.",
						width = 400,
						height_in_lines = 2,
					},
					f:checkbox {
						title = "Don't ask again for this version",
						value = bind "dontcheck",
					},
				}
			} )

			if props.dontcheck then
				prefs.seenVersion = formatVersion(latestVersion)
			end

			if result == "ok" then
				LrHttp.openUrlInBrowser( "https://500px.com/apps/lightroom" )
			end
		end
	end )
end

function PluginInit.forceNewCollections()
	local LrApplication = import "LrApplication"
	LrFunctionContext.postAsyncTaskWithContext( "New Collections", function(context)
		local catalog = LrApplication:activeCatalog()

		for _, publishService in ipairs( catalog:getPublishServices( _PLUGIN.id ) ) do
			local allPhotosCollection
			local profileCollection

			catalog:withWriteAccessDo( "New Collections", function()
				for _, collection in ipairs( publishService:getChildCollections() ) do
					local name = collection:getName():lower()
					if name == "library" or name == "organizer" then
						collection:setName( "Library" )
						collection:setCollectionSettings( { toCommunity = false } )
						allPhotosCollection = collection
					elseif name == "public profile" then
						collection:setName( "Public Profile" )
					end
				end

				profileCollection = publishService:createPublishedCollection( "Public Profile", nil, false )
				if profileCollection then
					profileCollection:setCollectionSettings( { toCommunity = true } )
				end

				if profileCollection then
					for _, collection in ipairs( publishService:getChildCollections() ) do
						local isAllPhotos = ( collection:getName() == "Library" )
						for _, publishedPhoto in ipairs( collection:getPublishedPhotos() ) do
							local photoId
							local photoUrl
							local photo = publishedPhoto:getPhoto()
							catalog:withReadAccessDo( function()
								photoId = photo:getPropertyForPlugin( _PLUGIN, "photoId" )
								photoUrl = string.format( "https://500px.com/photo/%s", photoId )
							end )

							if isAllPhotos then
								profileCollection:addPhotoByRemoteId( photo, string.format( "%s-profile", photoId ), photoUrl, true )
							else
								allPhotosCollection:addPhotoByRemoteId( photo, string.format( "%s-nil", photoId ), photoUrl, true )
							end
						end
					end
				end
			end )
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
