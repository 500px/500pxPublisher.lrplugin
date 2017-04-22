-- Lightroom SDK
local LrBinding = import "LrBinding"
local LrColor = import "LrColor"
local LrDate = import "LrDate"
local LrDialogs = import "LrDialogs"
local LrFunctionContext = import "LrFunctionContext"
local LrHttp = import "LrHttp"
local LrTasks = import "LrTasks"
local LrView = import "LrView"
local LrErrors = import "LrErrors"

-- Common shortcuts
local bind = LrView.bind

-- logging
local logger = import "LrLogger"("500pxPublisher")
logger:enable("logfile")

-- 500px Plugin
require "500pxAPI"

PxUser = {}

local function booleanToNumber( value )
	if not value then
		return 0
	else
		return 1
	end
end

local function storedCredentialsAreValid( propertyTable )
	-- might want to check the length of oauth token and secret
	return propertyTable.credentials and propertyTable.credentials.oauth_token
		and propertyTable.credentials.oauth_token_secret
end

local function notLoggedIn( propertyTable )
	propertyTable.credentials = nil
	propertyTable.userId = nil
	propertyTable.username = nil
	propertyTable.validAccount = false

	propertyTable.collections = {}

	propertyTable.accountStatus = "Not logged in"
	propertyTable.loginButtonTitle = "Login"
	propertyTable.loginButtonEnabled = true
end

local doingLogin = false

local function getCollectionsAndPhotos( publishService )
	local publishedCollections = publishService:getChildCollections()
	local photos = {}
	local collectionsById = {}
	local collectionsByName = {}

	-- Find any photo in the entire catalog that has a remote ID
	local known = publishService.catalog:findPhotosWithProperty( _PLUGIN.id, "photoId" )
	local props = publishService.catalog:batchGetPropertyForPlugin( known, _PLUGIN, { "photoId" } )

	for photo, fields in pairs( props ) do
		photos[ fields[ "photoId" ] ] = { photo = photo, edited = False }
	end

	for _, publishedCollection in ipairs( publishedCollections ) do
		local publishedPhotos = publishedCollection:getPublishedPhotos()
		local collection = {}
		for _, publishedPhoto in ipairs( publishedPhotos ) do
			local photo = publishedPhoto:getPhoto()
			local photoId = photo:getPropertyForPlugin( _PLUGIN, "photoId" )
			if photoId then
				-- logger:trace( "Photo id in Published photos " .. photoId )
				photos[ photoId ] = { photo = photo, edited = publishedPhoto:getEditedFlag() }
				collection[ photoId ] = photo
			end
		end
		local collectionId = publishedCollection:getRemoteId()
		if collectionId then
			collectionsById[ tostring( collectionId ) ] = { collection = publishedCollection, photos = collection }
		else
			collectionsByName[ publishedCollection:getName() ] = { collection = publishedCollection, photos = collection }
		end
	end
	return collectionsById, collectionsByName, photos
end

function PxUser.sync( propertyTable )

	local publishService = propertyTable.LR_publishService
	local errormessage = nil
	local function doSync( context, progressScope )
		LrDialogs.attachErrorDialogToFunctionContext( context )
		logger:trace( "sync all" )

		local LrPathUtils = import "LrPathUtils"
		local LrFileUtils = import "LrFileUtils"
		local collectionsById, collectionsByName, publishedPhotos = getCollectionsAndPhotos( publishService )

		local profileCollection = collectionsByName[ "Profile" ]
		if profileCollection then
			if profileCollection.collection:getCollectionInfoSummary().isDefaultCollection then
				profileCollection.collection:setName( "Library" )
				collectionsByName[ "Library" ] = collectionsByName[ "Profile" ]
				collectionsByName[ "Public Profile" ] = nil
			end
		end

		local collections = {}
		local nInCollections = 0
		local success, obj = PxAPI.getCollections( propertyTable )
		if not success then
			errormessage = "Unable to retrieve list of collections from 500px."
			obj = { collections = {} }
		end

		for _, collectionObj in ipairs( obj.collections ) do
			collections[ tostring( collectionObj.id ) ] = collectionObj
			for _, __ in ipairs( collectionObj.photos ) do
				nInCollections = nInCollections + 1
			end
			nInCollections = nInCollections + 1
		end

		-- Sync the photos
		local nPages = 0
		local args = {
			feature = "user_library",
			username = propertyTable.username,
			user_id = propertyTable.userId,
			sort = "created_at",
			page = 1,
			rpp = 50,
			image_size = 5,
		}

		local dir = propertyTable.syncLocation
		LrFileUtils.createAllDirectories( dir )

		-- collect photos for "Profile" and "Library" collections
		local allPhotos = {}
		local profilePhotos = {}
		local nPhotos
		local i = 0

		local success, obj = PxAPI.getPhotos( propertyTable, args)
		if success and obj.total_items >= 0 and obj.total_pages >= 0 then
			nPhotos = obj.total_items
			nPages = obj.total_pages
		else
			if success then
				errormessage = "Invalid response from 500px API."
			else
				errormessage = "Unable to retrieve list of photos from 500px."
			end
			success = false
			nPhotos = 0
			nPages = 0
		end

		while success do
			if progressScope:isCanceled() then
				progressScope:setCaption("Cancelling...")
				break
			end

			for _, photoObj in ipairs( obj.photos ) do
				if PluginInit then PluginInit.lock() end
				publishService.catalog:withWriteAccessDo( "sync.sync", function()
					local photoInfo = publishedPhotos[ tostring( photoObj.id ) ]
					if not photoInfo then
						--import the photo
						local filename = string.format( "%i-%i", photoObj.id, math.floor(LrDate.currentTime() + 0.5) )
						local file = LrFileUtils.chooseUniqueFileName( LrPathUtils.child( dir, LrPathUtils.addExtension( filename, "jpg" ) ) )
						local response, headers = LrHttp.get( photoObj.image_url, { } )

						if headers and headers.status == 200 and response then
							logger:trace( "Got photo from the server")
							local fh = io.open( file, "wb+" )
							fh:write( response )
							fh:flush()
							fh:close()
							local photo = publishService.catalog:addPhoto( file )
							photo:setPropertyForPlugin( _PLUGIN, "photoId", tostring( photoObj.id ) )
							photoInfo = { photo = photo, edited = false }
							publishedPhotos[ tostring( photoObj.id ) ] = photoInfo
						else
							errormessage = "Some of your photos failed to download."
							logger:trace( "No photo from the server")
						end
					else
						photoInfo.published = true
					end

					--update title, description, category
					if photoInfo then
						local photo = photoInfo.photo
						if not photoInfo.edited then
							photo:setRawMetadata( "title", PxAPI.decodeString( photoObj.name or "" ) )
							photo:setRawMetadata( "caption", PxAPI.decodeString( photoObj.description or "" ) )

							if photoObj.category and photoObj.category > 0 then
								photo:setPropertyForPlugin( _PLUGIN, "category", photoObj.category )
							end

							photo:setPropertyForPlugin( _PLUGIN, "nsfw", booleanToNumber(photoObj.nsfw) )
						end

						photo:setPropertyForPlugin( _PLUGIN, "publishedUUID", photo:getRawMetadata( "uuid" ) )
						photo:setPropertyForPlugin( _PLUGIN, "views", tostring( photoObj.times_viewed ) or "0" )
						photo:setPropertyForPlugin( _PLUGIN, "favorites", tostring( photoObj.favorites_count ) or "0" )
						photo:setPropertyForPlugin( _PLUGIN, "votes", tostring( photoObj.votes_count ) or "0" )
						photo:setPropertyForPlugin( _PLUGIN, "license_type", photoObj.license_type)

						--add to "Library" collection
						table.insert( allPhotos, photoObj )

						if not photoObj.privacy then
							table.insert( profilePhotos, photoObj )
						end
					end
				end)

				if PluginInit then PluginInit.unlock() end

				i = i + 1
				progressScope:setPortionComplete( i / ( nInCollections + nPhotos ) )
				LrTasks.yield()
			end

			args.page = args.page + 1
			if args.page > nPages then break end
			success, obj = PxAPI.getPhotos( propertyTable, args )
			if not success then
				errormessage = "Unable to retrieve list of photos from 500px."
			end
		end

		-- ...add in the "Profile" and "Library"  collection
		collections[ "profile" ] = { title = "Public Profile", id = nil, photos = profilePhotos }
		collections[ "nil" ] = { title = "Library", id = nil, photos = allPhotos }

		-- delete all published collections that no longer exist
		for id, collectionInfo in pairs( collectionsById ) do
			if PluginInit then PluginInit.lock() end
			publishService.catalog:withWriteAccessDo( "sync.sync", function()
				if not collections[ id ] then
					collectionInfo.collection:delete()
				end
			end )
			if PluginInit then PluginInit.unlock() end
		end

		for id, collectionObj in pairs( collections ) do
			local collection
			local photos
			local collectionSettings
			local new = false

			if PluginInit then PluginInit.lock() end
			publishService.catalog:withWriteAccessDo( "sync.sync", function()
				if collectionsById[ id ] then
					-- collection has been published before, update it's name
					local collectionInfo = collectionsById[ id ]
					collection = collectionInfo.collection
					photos = collectionInfo.photos
					if collection:getName() ~= collectionObj.title and not collection:setName( collectionObj.title ) then
						LrDialogs.showError( "Could not rename collection '" .. collection:getName() .. "' to '" .. collectionObj.title .. "' as another collection with that name already exists." )
					end
					collectionSettings = collection:getCollectionInfoSummary().collectionSettings or {}
				elseif collectionsByName[ collectionObj.title ] then
					-- collection has not been published yet, set it's remote id
					local collectionInfo = collectionsByName[ collectionObj.title ]
					collection = collectionInfo.collection
					photos = collectionInfo.photos
					collectionSettings = collection:getCollectionInfoSummary().collectionSettings or {}
				else
					-- collection doesn't exist, create it
					collection = publishService:createPublishedCollection( collectionObj.title,  nil, true )
					if not collection then
						LrDialogs.showError( "Could not create the collection '" .. collectionObj.title .. "' as another collection with that name already exists." )
						return
					end
					photos = {}
					collection:setRemoteId( id )
					collectionSettings = { toCommunity = propertyTable.toCommunity }
					new = true
				end

				-- always update remote url and collection settings
				local collectionUrl
				if collectionObj.title == "Public Profile" then
					collectionUrl = "https://500px.com/" .. propertyTable.username
				elseif collectionObj.title == "Library" or collectionObj.title == "Organizer" then
					collectionUrl = "https://500px.com/organizer"
					collectionSettings.toCommunity = false
				else
					if collectionObj.kind == "profile" then
						collectionUrl = PxAPI.makeCollectionUrl( propertyTable.username, collectionObj.path )
					else
						collectionUrl = "http://".. propertyTable.username ..".500px.com/".. collectionObj.path
					end
					--update collection settings (ie: path)
					collectionSettings.path = collectionObj.path
				end
				collection:setCollectionSettings( collectionSettings )
				collection:setRemoteUrl( collectionUrl )
			end )
			if PluginInit then PluginInit.unlock() end

			LrTasks.yield()

			if collection then
				-- add photos to the collection
				for _, photoObj in ipairs( collectionObj.photos ) do
					local photoInfo = publishedPhotos[ tostring( photoObj.id ) ]

					if PluginInit then PluginInit.lock() end
					publishService.catalog:withWriteAccessDo( "sync.sync", function()
						if photoInfo then
							photos[ photoInfo.photo ] = true
							collection:addPhotoByRemoteId( photoInfo.photo, string.format("%i-%s", photoObj.id, tostring( collectionObj.id ) ), string.format( "https://500px.com/photo/%i", photoObj.id ), not photoInfo.edited )
							progressScope:setPortionComplete( i / ( nInCollections + nPhotos ) )
						end
					end)
					if PluginInit then PluginInit.unlock() end

					i = i + 1
					progressScope:setPortionComplete( i / ( nInCollections + nPhotos ) )
					LrTasks.yield()
				end

				-- delete photos that were deleted from the web
				local photosToRemove = {}

				if not new then
					if not progressScope:isCanceled() then
						for _, publishedPhoto in ipairs( collection:getPublishedPhotos() ) do
							if not photos[ publishedPhoto:getPhoto() ] then
								table.insert( photosToRemove, publishedPhoto:getPhoto() )
							end
						end

						if PluginInit then PluginInit.lock() end
						publishService.catalog:withWriteAccessDo( "sync.sync", function()
							collection:removePhotos( photosToRemove )
						end )
						if PluginInit then PluginInit.unlock() end
					end
				end
			end

			i = i + 1
			progressScope:setPortionComplete( i / ( nInCollections + nPhotos ) )
			LrTasks.yield()
		end

	end

	LrFunctionContext.postAsyncTaskWithContext( "sync", function( context )
		if PluginInit then PluginInit.lock() end
		publishService.catalog:withWriteAccessDo( "sync.defaults", function()
			local profileCollection = publishService:createPublishedCollection( "Public Profile", nil, true )
			profileCollection:setCollectionSettings( { toCommunity = true } )
			profileCollection:setRemoteUrl( "https://500px.com/" .. propertyTable.username )

			for _, collection in ipairs( publishService:getChildCollections() ) do
				if collection:getName() == "Profile" or collection:getName() == "Library" or collection:getName() == "Organizer" then
					collection:setName( "Library" )
					profileCollection:setCollectionSettings( { toCommunity = false } )
				end
			end
		end )
		if PluginInit then PluginInit.unlock() end

		local progressScope = LrDialogs.showModalProgressDialog( {
			title = "Sync with 500px",
			caption = "Fetching photos and collections from 500px. This could take a while.",
			cannotCancel = false,
			functionContext = context,
		} )
		doSync( context, progressScope )

		if errormessage then
			LrErrors.throwUserError( errormessage .. "\nSome of your photos may not have been imported. Please try again later." )
		end
	end )
end

function PxUser.syncCollections( propertyTable )
	local publishService = propertyTable.LR_publishService
	local function doSync( context, progressScope )
		LrDialogs.attachErrorDialogToFunctionContext( context )
		logger:trace( "sync collections" )
		local collectionsById, collectionsByName, publishedPhotos = getCollectionsAndPhotos( publishService )

		-- rename the profile collection...
		local profileCollection = collectionsByName[ "Profile" ]
		if profileCollection then
			if profileCollection.collection:getCollectionInfoSummary().isDefaultCollection then
				profileCollection.collection:setName( "Library" )
				collectionsByName[ "Library" ] = collectionsByName[ "Profile" ]
				collectionsByName[ "Public Profile" ] = nil
			end
		end

		local collections = {}
		local success, obj = PxAPI.getCollections( propertyTable )
		local n = 0
		for _, collectionObj in ipairs( obj.collections ) do
			collections[ tostring( collectionObj.id ) ] = collectionObj
			n = n + 1
		end

		-- ...add in the "Profile" and "Library"  collection
		collections[ "profile" ] = { title = "Public Profile", id = nil, photos = profilePhotos }
		collections[ "nil" ] = { title = "Library", id = nil, photos = allPhotos }

		-- delete all published collections that no longer exist
		for id, collectionInfo in pairs( collectionsById ) do
			if PluginInit then PluginInit.lock() end
			publishService.catalog:withWriteAccessDo( "sync.sync", function()
				if not collections[ id ] then
					collectionInfo.collection:delete()
				end
			end )
			if PluginInit then PluginInit.unlock() end
		end

		local i = 0
		for id, collectionObj in pairs( collections ) do

			if PluginInit then PluginInit.lock() end
			publishService.catalog:withWriteAccessDo( "sync.sync", function()
				local collection
				local photos
				local collectionSettings
				if collectionsById[ id ] then
					-- collection has been published before, update it's name
					local collectionInfo = collectionsById[ id ]
					collection = collectionInfo.collection
					photos = collectionInfo.photos
					if collection:getName() ~= collectionObj.title and not collection:setName( collectionObj.title ) then
						LrDialogs.showError( "Could not rename collection '" .. collection:getName() .. "' to '" .. collectionObj.title .. "' as another collection with that name already exists." )
					end
					collectionSettings = collection:getCollectionInfoSummary().collectionSettings or {}
				elseif collectionsByName[ collectionObj.title ] then
					-- collection has not been published yet, set it's remote id
					local collectionInfo = collectionsByName[ collectionObj.title ]
					collection = collectionInfo.collection
					photos = collectionInfo.photos
					collection:setRemoteId( id )
					collectionSettings = collection:getCollectionInfoSummary().collectionSettings or {}
				else
					-- collection doesn't exist, create it
					collection = publishService:createPublishedCollection( collectionObj.title, false, nil )
					if not collection then
						LrDialogs.showError( "Could not create the collection '" .. collectionObj.title .. "' as another collection with that name already exists." )
						return
					end
					photos = {}
					collection:setRemoteId( id )
					collectionSettings = { toCommunity = propertyTable.toCommunity }
				end

				-- always update remote url and collection settings
				local collectionUrl
				if collectionObj.title == "Public Profile" then
					collectionUrl = "https://500px.com/" .. propertyTable.username
				elseif collectionObj.title == "Library" then
					collectionUrl = "https://500px.com/organizer"
				else
					collectionUrl = PxAPI.makeCollectionUrl( propertyTable.username, collectionObj.path )
					--update collection settings (ie: path)
					collectionSettings.path = collectionObj.path
				end
				collection:setRemoteUrl( collectionUrl )
				collection:setCollectionSettings( collectionSettings )
			end)
			if PluginInit then PluginInit.unlock() end
			progressScope:setPortionComplete( i / n )

			LrTasks.yield()
		end
	end

	LrFunctionContext.postAsyncTaskWithContext( "sync", function( context )
		if PluginInit then PluginInit.lock() end
		publishService.catalog:withWriteAccessDo( "sync.defaults", function()
			local profileCollection = publishService:createPublishedCollection( "Public Profile", nil, true )
			profileCollection:setCollectionSettings( { toCommunity = true } )
			profileCollection:setRemoteUrl( "https://500px.com/" .. propertyTable.username )

			for _, collection in ipairs( publishService:getChildCollections() ) do
				if collection:getName() == "Profile" or collection:getName() == "Library" then
					collection:setName( "Library" )
					profileCollection:setCollectionSettings( { toCommunity = false } )
				end
			end
		end )
		if PluginInit then PluginInit.unlock() end

		local progressScope = LrDialogs.showModalProgressDialog( {
			title = "Sync with 500px",
			caption = "Fetching collections from 500px.",
			cannotCancel = true,
			functionContext = context,
		} )
		doSync( context, progressScope )
	end )
end

function PxUser.login( propertyTable )
	if doingLogin then return end
	doingLogin = true
	LrFunctionContext.postAsyncTaskWithContext( "500px login", function( context )
		if not propertyTable.LR_editingExistingPublishConnection then
			notLoggedIn( propertyTable )
		end
		propertyTable.accountStatus = "Logging in..."
		propertyTable.LoginButtonEnabled = false

		LrDialogs.attachErrorDialogToFunctionContext( context )

		context:addCleanupHandler( function()
			doingLogin = false

			if not storedCredentialsAreValid( propertyTable ) then
				notLoggedIn( propertyTable )
			end
			-- error dialog?
		end )

		propertyTable.accountStatus = "Waiting for response from 500px..."
		propertyTable.credentials = PxAPI.login( context )
		PxUser.updateUserStatusTextBindings( propertyTable )
	end )
end

function PxUser.register( propertyTable )
	if doingLogin then return end
	doingLogin = true

	LrFunctionContext.postAsyncTaskWithContext( "500px signup", function( context )
		if not propertyTable.LR_editingExistingPublishConnection then
			notLoggedIn( propertyTable )
		end

		propertyTable.accountStatus = "Signing up..."
		propertyTable.LoginButtonEnabled = false

		LrDialogs.attachErrorDialogToFunctionContext( context )

		context:addCleanupHandler( function()
			doingLogin = false

			if not storedCredentialsAreValid( propertyTable ) then
				notLoggedIn( propertyTable )
			end

			-- error dialog?
		end )
		local userinfo = LrBinding.makePropertyTable( context )
		userinfo.tos = true
		local f = LrView.osFactory()
		local contents = f:view {
			margin = 0,
			place = "overlapping",
			bind_to_object = userinfo,
			spacing = f:control_spacing(),
			fill = 1,
			f:picture {
				value = _PLUGIN:resourceId( "/images/registration.png" )
			},
			f:column {
				fill = 1,
				f:spacer {
					height = 350,
				},
				f:row {
					f:static_text {
						title = "500px is a photographic community powered by creative people from all over the world that lets you share and discover inspiring photographs.",
						width = 390,
						height_in_lines = 5,
					},
					f:column {
						place_horizontal = 1,
						spacing = f:control_spacing(),
						f:row {
							spacing = f:label_spacing(),
							f:static_text {
								title = "Username:",
								alignment = "right",
								width = 65,
								place_horizontal = 1,
							},
							f:edit_field {
								width = 300,
								value = bind "username",
							},
						},
						f:row {
							spacing = f:label_spacing(),
							f:static_text {
								title = "E-mail Address:",
								alignment = "right",
								width = 120,
							},
							f:edit_field {
								width = 300,
								value = bind "email"
							},
						},
						f:row {
							spacing = f:label_spacing(),
							f:static_text {
								title = "Password:",
								alignment = "right",
								width = 120,
							},
							f:password_field {
								width = 300,
								value = bind "password",
							}
						},
						f:row {
							spacing = f:label_spacing(),
							f:spacer {
								width = 120,
							},
							f:checkbox {
								title = "I agree with 500px's",
								value = bind "tos",
							},
							f:static_text {
								title = "Terms of Service",
								font = "<system/bold>",
								text_color = LrColor( "blue" ),
								mouse_down = function() LrHttp.openUrlInBrowser( "https://500px.com/terms" ) end
							},
						},
					},
				},
			},
		}
		local action = LrDialogs.presentModalDialog( {
			title = "Sign up with 500px.",
			contents = contents,
			actionVerb = "Sign Up!",
			accessoryView = f:row {
				f:push_button {
					title = "Learn More...",
					action = function()  LrHttp.openUrlInBrowser( "https://500px.com/about" ) end
				}
			}
		} )

		if action == "cancel" then return end

		if not userinfo.tos then
			LrDialogs.message( "You must accept 500px's Terms of Service." )
			return
		end

		if not userinfo.password then
			LrDialogs.message( "You must choose a password" )
			return
		elseif string.len( userinfo.password ) < 6 then
			LrDialogs.message( "Your password must be at least 6 characters long." )
			return
		end

		if not userinfo.email or not string.match( userinfo.email, "^%w+@[%w.]+%w$" ) then
			LrDialogs.message( "You must provide a valid email address." )
			return
		end

		if not userinfo.username or not string.match( userinfo.username, "^[%w_-]+$" ) then
			LrDialogs.message( "You must choose a username that contains alphanumeric characters, underscores, and dashes only." )
			return
		end

		propertyTable.accountStatus = "Waiting for response from 500px..."

		propertyTable.username = userinfo.username
		local success, obj = PxAPI.register( userinfo )

		if success then
			propertyTable.credentials = obj

			PxUser.updateUserStatusTextBindings( propertyTable )
		elseif obj.created then
			LrDialogs.message( "Login Failed", "Your account was created but logging in failed. Please try logging in again later." )
		elseif obj.email then
			LrDialogs.message( "Unable to Create an Account", "The email address is not valid or has already been used. Please use a different email address." )
		elseif obj.username then
			LrDialogs.message( "Unable to Create an Account", "This username has already been used. Please change your username." )
		else
			LrDialogs.message( "Unable to Create an Account", "Something went wrong, try again later." )
		end
	end )
end

function PxUser.verifyLogin( propertyTable )
	local function updateStatus()
		LrTasks.startAsyncTask( function()
			if storedCredentialsAreValid( propertyTable ) then
				propertyTable.accountStatus = string.format( "Logged in as %s", propertyTable.username )
				logger:trace("User logged in")
				if propertyTable.LR_editingExistingPublishConnection then
					propertyTable.loginButtonEnabled = false
					propertyTable.loginButtonTitle = "Login"
				else
					propertyTable.loginButtonEnabled = true
					propertyTable.loginButtonTitle = "Switch User"
				end
				if not propertyTable.validAccount then
					propertyTable.validAccount = true
				end
			elseif not storedCredentialsAreValid( propertyTable ) then
				logger:trace("Credentials are not valid")
				notLoggedIn( propertyTable )
			end
			PxUser.updateUserStatusTextBindings( propertyTable )
		end )
	end
	propertyTable:addObserver( "username", updateStatus )
	updateStatus()
end

function PxUser.updateUserStatusTextBindings( propertyTable )
	if propertyTable.credentials then
		LrFunctionContext.postAsyncTaskWithContext( "500px account status" , function( context )
			context:addFailureHandler( function()
				propertyTable.accountStatus = string.format( "Login failed, was logged in as %s", propertyTable.username )
				propertyTable.loginButtonTitle = "Login"
				propertyTable.loginButtonEnabled = true
				propertyTable.validAccount = false
				propertyTable.isUserAwesome = false
				if propertyTable.LR_editingExistingPublishCollection then
					propertyTable.accountTypeMessage = "Could not verify this 500px account. Please login again. Note that you can not change the 500px account for an existing publish connection. You must login to the same account."
				else
					propertyTable.accountTypeMessage = "Login with your 500px account or sign up to create a new one."
				end
			end )

			local success, obj = PxAPI.getUser( propertyTable )

			-- if obj == "banned" then
			-- 	propertyTable.accountStatus = string.format( "Login failed, user '%s' is banned or deactivated.", propertyTable.username )
			-- -- else
			-- -- 	propertyTable.accountStatus = string.format( "Login failed, was logged in as %s", propertyTable.username )
			-- end

			local userinfo = obj.user
			if not propertyTable.userId then
				propertyTable.username = userinfo.username
				propertyTable.domain = userinfo.domain
				propertyTable.userId = userinfo.id
				propertyTable.uploadLimit = userinfo.upload_limit
			elseif propertyTable.userId ~= userinfo.id and propertyTable.LR_editingExistingPublishConnection then
				LrDialogs.message( "You can not change 500px accounts on an existing publish connection. Please login again with the account you used when you first created this connection." )
			end

			if not propertyTable.LR_isExportForPublish then
				local status, obj = PxAPI.getCollections( propertyTable )
				local collections = {}

				local n = 0
				for i, collection in ipairs( obj.collections ) do
					collections[ collection.id ] = collection
					n = n + 1
				end
				propertyTable.collections = collections
				propertyTable.nCollections = n
			end

			local awesome = (userinfo.upgrade_status >= 2)
			if propertyTable.isUserAwesome ~= awesome then
				propertyTable.isUserAwesome = awesome
			end

			local plus = (userinfo.upgrade_status == 1)
			if propertyTable.isUserPlus ~= plus then
				propertyTable.isUserPlus = plus
			end

			if userinfo and userinfo.upgrade_status == 0  then
				propertyTable.accountTypeMessage = "You have a free account. You can upload 20 images per 7 day period. Upgrade to Plus or Awesome to have unlimited uploads, advanced statistics, and more."

			elseif userinfo and userinfo.upgrade_status == 1  then
				propertyTable.accountTypeMessage = "You have a Plus account. You have unlimited uploads. To create a portfolio, upgrade to Awesome."

			elseif userinfo then
				propertyTable.accountTypeMessage = "You are awesome and have unlimited uploads."
			end

		end )
	else
		notLoggedIn( propertyTable )
		propertyTable.accountTypeMessage = "Login with your 500px account or sign up to create a new account."
	end
end
