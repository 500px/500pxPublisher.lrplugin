-- Lightroom SDK
local LrApplication = import "LrApplication"
local LrBinding = import "LrBinding"
local LrColor = import "LrColor"
local LrDialogs = import "LrDialogs"
local LrErrors = import "LrErrors"
local LrFileUtils = import "LrFileUtils"
local LrFunctionContext = import "LrFunctionContext"
local LrHttp = import "LrHttp"
local LrTasks = import "LrTasks"
local LrView = import "LrView"
local LrPathUtils = import "LrPathUtils"

-- Common Shortcuts
local bind = LrView.bind

-- logging
local logger = import "LrLogger"("500pxPublisher")
logger:enable("logfile")

-- 500px Plugin
require "500pxAPI"
require "500pxPublishSupport"
require "500pxUser"

--=======================================--
--== 500px specific  helper functions. ==--
--=======================================--

local function updateCantExportBecause( propertyTable )
	propertyTable.LR_cantExportBecause = nil
	if not propertyTable.validAccount then
		propertyTable.LR_cantExportBecause = "You haven't logged in to 500px yet."
	elseif not propertyTable.LR_isExportForPublish then
		if propertyTable.toPortfolio and not propertyTable.collectionId then
			propertyTable.LR_cantExportBecause = "You must choose a collection to export to."
		elseif not propertyTable.toPortfolio and not propertyTable.toCommunity then
			propertyTable.LR_cantExportBecause = "You must export to the community or a collection."
		end
	end
end

local function booleanToNumber( value )
	if not value then
		return 0
	else
		return 1
	end
end

local function numberToBoolean( n )
	if not n then return false end
	return n ~= 0
end

local function stripAllTags( text )
	return string.gsub( text, "(<[^>]->)", function( match )
		return ""
	end )
end

local function stripTags( text )
	 return string.gsub( text, "(<[^>]->)", function( match )
		if string.match( match, "<b>" ) then
			return match
		elseif string.match( match, "</b>" ) then
			return match
		elseif string.match( match, "<i>" ) then
			return match
		elseif string.match( match, "</i>" ) then
			return match
		elseif string.match( match, "<a%s+href=\"[^\"]+\">" ) then
			return match
		elseif string.match( match, "</a>" ) then
			return match
		else
			return ""
		end
	end)
end

local exportServiceProvider = {}

-- publish specific hooks are in another file
for key, value in pairs( publishSupport ) do
	exportServiceProvider[ key ] = value
end

-- support both export and publish
exportServiceProvider.supportsIncrementalPublish = true

exportServiceProvider.exportPresetFields = {
	{ key = "username", default = "" },
	{ key = "userId", default = nil },
	{ key = "domain", default = nil },
	{ key = "isUserAwesome", default = false },
	{ key = "isUserPlus", default = false },
	{ key = "uploadLimit", default = 0 },
	{ key = "category", default = 0 },
	{ key = "toPortfolio", default = false },
	{ key = "toCommunity", default = false },
	{ key = "credentials", default = nil },
	{ key = "validAccount", default = false },
	{ key = "doNotShowInfoScreen", default = false },
	{ key = "license_type", default = 0 },
	{ key = "syncNow", default = true },
}

-- photos are always rendered to a temporary location and are deleted when the export is complete
exportServiceProvider.hideSections = { "video", "exportLocation", "fileNaming" }

exportServiceProvider.allowFileFormats = { "JPEG" }

exportServiceProvider.allowColorSpaces = { "sRGB" }

-- recommended when exporting to the web
exportServiceProvider.hidePrintResolution = true

exportServiceProvider.canExportVideo = false

local function setPresets( propertyTable )
	if not propertyTable.validAccount then
		propertyTable.LR_jpeg_quality = 0.9
		propertyTable.LR_size_maxWidth = 900
		propertyTable.LR_size_maxHeight = 900
		propertyTable.LR_size_resizeType = "longEdge"
		propertyTable.LR_size_doConstrain = false
		propertyTable.LR_removeLocationMetadata = false
	end
	propertyTable.syncCollectionsOnly = false
end

function exportServiceProvider.startDialog( propertyTable )

	propertyTable:addObserver( "validAccount", function() updateCantExportBecause( propertyTable ) end )
	propertyTable:addObserver( "toPortfolio", function() updateCantExportBecause( propertyTable ) end )
	propertyTable:addObserver( "collectionId", function() updateCantExportBecause( propertyTable ) end )
	propertyTable:addObserver( "toCommunity", function() updateCantExportBecause( propertyTable ) end )
	propertyTable:addObserver( "collections", function() end )
	updateCantExportBecause( propertyTable )

	propertyTable:addObserver( "validAccount", function() setPresets( propertyTable ) end )

	-- clear login if it's a new connection
	if not propertyTable.LR_editingExistingPublishConnection and propertyTable.LR_isExportForPublish then
		propertyTable.credentials = nil
		propertyTable.username = nil
		propertyTable.validAccount = false
		propertyTable.userId = nil
	else
		propertyTable.collectionId = nil
	end

	setPresets( propertyTable )

	PxUser.verifyLogin( propertyTable )
end

function exportServiceProvider.sectionsForTopOfDialog( f, propertyTable )
	propertyTable.syncNow = true
	local sections = {
		{
			title = "500px Account",
			synopsis = bind "accountStatus",
			f:static_text {
				title = bind "accountStatus",
				alignment = "left",
				fill_horizontal = 1,
			},
			f:static_text {
				title = bind "accountTypeMessage",
				alignment = "left",
				fill_horizontal = 1,
				height_in_lines = 2,
				width = 100,
			},
			f:row {
				f:control_spacing(),
				fill = 1,
				f:push_button {
					place_horizontal = 1,
					title = "Become Awesome!",
					width = 110,
					enabled = LrBinding.negativeOfKey( "isUserAwesome" ) or LrBinding.negativeOfKey( "isUserPlus" ),
					visible = bind "validAccount",
					action = function() LrHttp.openUrlInBrowser( "http://500px.com/upgrade" ) end
				},
				f:push_button {
					title = bind "loginButtonTitle",
					width = 90,
					enabled = bind "loginButtonEnabled",
					action = function()
						LrFunctionContext.callWithContext( "login", function( context )
							LrDialogs.attachErrorDialogToFunctionContext( context )
							PxUser.login( propertyTable )
						end )
					end,
				},
				f:push_button {
					title = "Sign up",
					width = 90,
					enabled = bind "loginButtonEnabled",
					action = function()
						LrFunctionContext.callWithContext( "register", function( context )
							LrDialogs.attachErrorDialogToFunctionContext( context )
							PxUser.register( propertyTable )
						end )
					end,
				},
			},
		},
	}
	if propertyTable.LR_isExportForPublish then
		table.insert( sections, {
			title = "Syncing With 500px",
			f:static_text {
				width = 100,
				fill_horizontal = 1,
				title = "Syncing with 500px will import all your existing photos in your 500px profile into Lightroom (this may take some time depending on your Internet connection).\n\nYou'll be able to manage all your photos on 500px from inside Lightroom. If you choose to sync collection names only, no photos will be imported into Lightroom (you can always choose to sync it later).",
				height_in_lines = 6,
			},
			f:checkbox {
				title = "Only sync my collection names",
				value = bind "syncCollectionsOnly",
			},
			f:column {
				place = "overlapping",
				f:checkbox {
					title = "Sync now",
					value = bind "syncNow",
					visible = LrBinding.keyIsNil( "LR_publishService" )
				},
				f:row {
					f:static_text {
						title = "Don't see all of the collections and photos from your account?",
						visible = LrBinding.keyIsNotNil( "LR_publishService" ),
					},
					f:push_button {
						title = "Sync Now!",
						enabled = bind "validAccount",
						action = function() if propertyTable.syncCollectionsOnly then PxUser.syncCollections( propertyTable ) else PxUser.sync( propertyTable ) end end,
						visible = LrBinding.keyIsNotNil( "LR_publishService" ),
					},
				},
			},
			f:static_text {
				width = 100,
				fill_horizontal = 1,
				font = "<system/small/bold>",
				title = bind {
					key = "username",
					transform = function( value, fromModel )
						if not value then
							value = ""
						end
						return "Your photos will be downloaded to " .. LrPathUtils.child(LrPathUtils.child( LrPathUtils.getStandardFilePath( "pictures" ), "500px" ), value )
					end },
			},
		} )

		table.insert( sections, {
			title = "500px Publisher Settings",
			f:checkbox {
				title = "Show advanced publish screen",
				value = LrBinding.negativeOfKey( "doNotShowInfoScreen" ),
			}
		} )
	else
		table.insert( sections, {
			title = "500px Settings",
			f:row {
				fill_horizontal = 1,
				spacing = f:label_spacing(),
				f:static_text {
					alignment = "right",
					title = "Category:",
					width = 50,
				},
				f:popup_menu {
					items = {
						{ value = 10, 	title="Abstract" },
						{ value = 11, 	title="Animals" },
						{ value = 5, 	title="Black and White" },
						{ value = 1, 	title="Celebrities" },
						{ value = 9, 	title="City and Architecture" },
						{ value = 15, 	title="Commercial" },
						{ value = 16, 	title="Concert" },
						{ value = 20, 	title="Family" },
						{ value = 14, 	title="Fashion" },
						{ value = 2, 	title="Film" },
						{ value = 24, 	title="Fine Art" },
						{ value = 23, 	title="Food" },
						{ value = 3, 	title="Journalism" },
						{ value = 8, 	title="Landscapes" },
						{ value = 12, 	title="Macro" },
						{ value = 18, 	title="Nature" },
						{ value = 4, 	title="Nude" },
						{ value = 7, 	title="People" },
						{ value = 19, 	title="Performing Arts" },
						{ value = 17, 	title="Sport" },
						{ value = 6, 	title="Still Life" },
						{ value = 21, 	title="Street" },
						{ value = 26, 	title="Transportation" },
						{ value = 13, 	title="Travel" },
						{ value = 22, 	title="Underwater" },
						{ value = 27, 	title="Urban Exploration" },
						{ value = 25, 	title="Wedding" },
						{ value = 0, 	title="Uncategorized" }
					},
					value = bind "category"
				},
			},
			f:checkbox {
				title = "Upload to community",
				value = bind "toCommunity",
			},
			f:checkbox {
				title = "Upload to portfolio",
				value = bind "toPortfolio",
			},
			f:row {
				fill_horizontal = 1,
				spacing = f:label_spacing(),
				f:static_text {
					title = "Collection:",
					alignment = "right",
					enabled = bind "toPortfolio",
					width = 90,
				},
				f:popup_menu {
					enabled = bind "toPortfolio",
					items = bind {
						key = "collections",
						transform = function( value, fromModel )
							local collections = {}
							for id, collection in pairs( value or {} ) do
								table.insert( collections, { title = collection.title, value = collection.id } )
							end
							return collections
						end
					},
					value = bind "collectionId",
				},
				f:push_button {
					title = "New Collection",
					enabled = bind "toPortfolio",
					width = 100,
					place_horizontal = 0.58,
					action = function()
						LrFunctionContext.callWithContext( "create collection", function( context )
							local collectionInfo = LrBinding.makePropertyTable( context )
							LrDialogs.attachErrorDialogToFunctionContext( context )
							local action = LrDialogs.presentModalDialog( {
								title = "Create a New Collection",
								contents = f:view {
									bind_to_object = collectionInfo,
									f:row {
										spacing = f:label_spacing(),
										f:static_text {
											title = "Name:",
											width = 50,
											alignment = "right",
										},
										f:edit_field {
											value = bind {
												key = "title",
												transform = function( value, fromModel )
													collectionInfo.path = PxAPI.collectionNameToPath( value )
													return value
												end
											}
										},
									},
									f:row {
										spacing = f:label_spacing(),
										f:static_text {
											title = "URL:",
											width = 50,
											alignment = "right",
										},
										f:edit_field {
											value = bind "path"
										},
									}
								},
								actionVerb = "Create!",
							} )
							if action == "ok" and collectionInfo.title and string.len( collectionInfo.title ) > 0 then
								table.insert( propertyTable.collections, { title=collectionInfo.title, id="create" } )
								propertyTable.collections = propertyTable.collections
								propertyTable.collectionId = "create"
								propertyTable.collectionName = collectionInfo.title
								propertyTable.collectionPath = collectionInfo.path or PxAPI.collectionNameToPath( collectionInfo.title )
							end
						end )
					end,
				},
			},
			f:row {
				f:checkbox {
					title = "Show advanced export screen",
					value = LrBinding.negativeOfKey( "doNotShowInfoScreen" ),
				}
			}
		} )
	end
	return sections
end

function exportServiceProvider.updateExportSettings( propertyTable )
	if propertyTable.LR_isExportForPublish then
		propertyTable.LR_editingExistingPublishConnection = true
		PxUser.verifyLogin( propertyTable )
	end
	local success, obj = PxAPI.getCollections( propertyTable )
	if success then
		propertyTable.collections = obj.collections
		propertyTable.nCollections = 0
		for _, collection in ipairs( obj.collections ) do
			propertyTable.nCollections = propertyTable.nCollections + 1
		end
	end
end

local function collectKeywords( keywordTable, keyword )
	if not keyword then
		for i, k in ipairs( LrApplication:activeCatalog():getKeywords() ) do
			keywordTable[ k:getName() ] = k
			keywordTable = collectKeywords( keywordTable, k )
		end
	else
		for i, k in ipairs( keyword:getChildren() ) do
			keywordTable[ k:getName() ] = k
			keywordTable = collectKeywords( keywordTable, k )
		end
	end

	return keywordTable
end

function getPhotoInfo( exportContext )
	local photos = {}
	local propertyTable = exportContext.propertyTable

	local keywords = {}
	local versionTable = LrApplication.versionTable()

	for i, rendition in exportContext:renditions() do
		local photo = rendition.photo
		local photoInfo = {}
		photo.catalog:withReadAccessDo( function()
			photoInfo.inProfile = false
			photoInfo.id = photo:getPropertyForPlugin( _PLUGIN, "photoId" )
			photoInfo.publishedUUID = photo:getPropertyForPlugin( _PLUGIN, "publishedUUID" )
			photoInfo.title = photo:getFormattedMetadata( "title" )
			photoInfo.description = photo:getFormattedMetadata( "caption" )
			photoInfo.category = photo:getPropertyForPlugin( _PLUGIN, "category" )
			photoInfo.tags = photo:getFormattedMetadata( "keywordTagsForExport" )
			photoInfo.previous_tags = photo:getPropertyForPlugin( _PLUGIN, "previous_tags" )
			photoInfo.nsfw = numberToBoolean( photo:getPropertyForPlugin( _PLUGIN, "nsfw" ) )
			photoInfo.license_type = photo:getPropertyForPlugin( _PLUGIN, "license_type" )
			photoInfo.lens = photo:getFormattedMetadata( "lens" )
			photo:getRawMetadata( "keywords" )
		end )
		photoInfo.success, photoInfo.path = rendition:waitForRender()

		-- check uuid to see if it's a virtual copy that hasn't been published
		if not propertyTable.LR_isExportForPublish or photoInfo.publishedUUID ~= photo:getRawMetadata( "uuid" ) then
			photoInfo.id = nil
			photoInfo.privacy = 1
		end

		-- check if photo exists on website
		if photoInfo.id then
			local success, obj = PxAPI.getPhoto( propertyTable, { photo_id = photoInfo.id } )
			if not success and obj.status == 404 then
				-- photo did not belong to user but has been deleted
				photoInfo.id = nil
				photoInfo.privacy = 1
			elseif not success then
				rendition:uploadFailed( "Could not connect to 500px." )
				photoInfo.failed = true
			elseif obj.photo.user.id ~= propertyTable.userId then
				rendition:uploadFailed( "Another user has already published this photo." )
				photoInfo.failed = true
			elseif obj.photo.status == 9 then
				logger:trace("Photo was deleted, upload it again as new")
				photoInfo.status = 9
			elseif obj.photo.status ~= 1 then
				-- photo has been deleted, or was never uploaded
				photoInfo.photo_id = nil
				photoInfo.privacy = 1
			else
				photoInfo.privacy = booleanToNumber( obj.photo.privacy )
			end
		end

		-- allow user to change metadata
		if not propertyTable.doNotShowInfoScreen and not photoInfo.failed then
			local f = LrView:osFactory()

			local contents = f:column {
				spacing = f:control_spacing(),
				bind_to_object = photoInfo,
				f:row {
					spacing = f:control_spacing(),
					f:picture {
						value = photoInfo.path,
						width = 150,
						height = 150,
					},
					f:column {
						spacing = f:control_spacing(),
						f:column {
							spacing = f:label_spacing(),
							f:static_text {
								title = "Title",
							},
							f:edit_field {
								value = bind {
									key = "title",
									transform = function( value, fromTable )
										photoInfo.title = value
										return stripAllTags( value )
									end,
								},
								width = 200,
							},
						},
						f:column {
							spacing = f:label_spacing(),
							f:static_text {
								title = "Description",
							},
							f:edit_field {
								value = bind {
									key = "description",
									transform = function( value, fromTable )
										photoInfo.description = value
										return stripAllTags( value )

									end,
								},
								width = 200,
								height_in_lines = 3,
							},
						},
						f:column {
							spacing = f:label_spacing(),
							f:static_text {
								title = "Tags",
							},
							f:edit_field {
								value = bind "tags",
								width = 200,
								height_in_lines = 2,
							},
						},
						f:column {
							spacing = f:label_spacing(),
							f:static_text {
								title = "Category",
							},
							f:popup_menu {
								items = {
									{ value = 10, 	title="Abstract" },
									{ value = 11, 	title="Animals" },
									{ value = 5, 	title="Black and White" },
									{ value = 1, 	title="Celebrities" },
									{ value = 9, 	title="City and Architecture" },
									{ value = 15, 	title="Commercial" },
									{ value = 16, 	title="Concert" },
									{ value = 20, 	title="Family" },
									{ value = 14, 	title="Fashion" },
									{ value = 2, 	title="Film" },
									{ value = 24, 	title="Fine Art" },
									{ value = 23, 	title="Food" },
									{ value = 3, 	title="Journalism" },
									{ value = 8, 	title="Landscapes" },
									{ value = 12, 	title="Macro" },
									{ value = 18, 	title="Nature" },
									{ value = 4, 	title="Nude" },
									{ value = 7, 	title="People" },
									{ value = 19, 	title="Performing Arts" },
									{ value = 17, 	title="Sport" },
									{ value = 6, 	title="Still Life" },
									{ value = 21, 	title="Street" },
									{ value = 26, 	title="Transportation" },
									{ value = 13, 	title="Travel" },
									{ value = 22, 	title="Underwater" },
									{ value = 27, 	title="Urban Exploration" },
									{ value = 25, 	title="Wedding" },
									{ value = 0, 	title="Uncategorized" }
								},
								value = bind "category"
							},
						},
						f:column {
							spacing = f:label_spacing(),
							f:static_text {
								title = "License Type",
							},
							f:popup_menu {
								items = {
									{ value = 0, title = "Standard 500px License" },
									{ value = 4, title = "Attribution 3.0" },
									{ value = 5, title = "Attribution-NoDerivs 3.0" },
									{ value = 6, title = "Attribution-ShareAlike 3.0" },
									{ value = 1, title = "Attribution-NonCommercial 3.0" },
									{ value = 2, title = "Attribution-NonCommercial-NoDerivs 3.0" },
									{ value = 3, title = "Attribution-NonCommercial-ShareAlike 3.0" },
								},
								value = bind "license_type"
							},
						},
						f:checkbox {
							width = 250,
							fill_horizontal = 1,
						 	title = "Mature Content",
							value = bind "nsfw"
						},
					},
				},
				f:static_text {
					visible = LrBinding.keyEquals( "status", 1 ),
					width = 350,
					title = "Republishing this photo will only update it's title, description, category and tags.",
					height_in_lines = 2,
					text_color = LrColor( "red" )
				},

				f:static_text {
					visible = LrBinding.keyEquals( "status", 9 ),
					width = 350,
					title = "This photo has been published and deleted previously. ",
					height_in_lines = 2,
					text_color = LrColor( "red" )
				},
				f:checkbox {
					bind_to_object = propertyTable,
					value = bind "doNotShowInfoScreen",
					title = "Do not show this window until the next time I publish.",
				}
			}

			local action = LrDialogs.presentModalDialog {
				title = "Photo Details",
				contents = contents,
				cancelVerb = "Skip",
			}

			if action == "cancel" then
				photoInfo.skipped = true
			end
		end

		-- update photo's metadata
		if not photoInfo.skipped then

		if PluginInit then PluginInit.lock() end
		-- logger:trace("write photo info")
		photo.catalog:withWriteAccessDo( "write photo info", function()
			photo:setPropertyForPlugin( _PLUGIN, "category", photoInfo.category )
			photo:setRawMetadata( "title", photoInfo.title )
			photo:setRawMetadata( "caption", photoInfo.description )
			photo:setPropertyForPlugin( _PLUGIN, "nsfw", booleanToNumber( photoInfo.nsfw ) )
			photo:setPropertyForPlugin( _PLUGIN, "license_type", photoInfo.license_type )

			if photoInfo.tags then
				photo:setPropertyForPlugin( _PLUGIN, "previous_tags", photoInfo.tags )
			end
		end )
		if PluginInit then PluginInit.unlock() end

		end
		table.insert( photos, { ["rendition"] = rendition, ["photoInfo"] = photoInfo } )
	end

	return photos
end

function exportServiceProvider.processRenderedPhotos( functionContext, exportContext )
	local exportSession = exportContext.exportSession
	local propertyTable = assert( exportContext.propertyTable )
	local isPublish = propertyTable.LR_isExportForPublish

	local nPhotos = exportSession:countRenditions()
	local progressScope = exportContext:configureProgress( {
		title = nPhotos > 1 and string.format( "Publishing %i photos to 500px.", nPhotos) or "Publishing one photo to 500px."
	} )

	local publishedCollection
	local publishedCollectionInfo
	local profileCollection
	local allPhotosCollection

	if isPublish then
		local collectionInfoSummary = exportContext.publishedCollection:getCollectionInfoSummary()
		publishedCollection = exportContext.publishedCollection
		publishedCollectionInfo = exportContext.publishedCollectionInfo
		publishedCollectionInfo.isProfileCollection = publishedCollectionInfo.name == "Profile" or publishedCollectionInfo.name == "Public Profile"
		publishedCollectionInfo.isAllPhotosCollection = publishedCollectionInfo.name == "Library" or publishedCollectionInfo.name == "Organizer"
		publishedCollectionInfo.isDefaultCollection = publishedCollectionInfo.isProfileCollection or publishedCollectionInfo.isAllPhotosCollection
		publishedCollectionInfo.remoteUrl = ( publishedCollectionInfo.isProfileCollection and string.format( "http://500px.com/%s", propertyTable.username ) ) or
						    ( publishedCollectionInfo.isAllPhotosCollection and "http://500px.com/organizer" ) or
						    PxAPI.makeCollectionUrl( propertyTable.username, collectionInfoSummary.collectionSettings.path )
		publishedCollectionInfo.path = collectionInfoSummary.collectionSettings.path
		publishedCollectionInfo.toCommunity = publishedCollectionInfo.isProfileCollection or collectionInfoSummary.collectionSettings.toCommunity

		for _, collection in ipairs( exportContext.publishService:getChildCollections() ) do
			local name = collection:getName()
			if name == "Profile" or name == "Public Profile" then
				profileCollection = collection
			elseif name == "Library" or name == "Organizer" then
				allPhotosCollection = collection
			end
		end
	else
		publishedCollectionInfo = {}
		publishedCollectionInfo.isProfileCollection = propertyTable.toCommunity
		publishedCollectionInfo.isDefaultCollection = propertyTable.toCommunity
		publishedCollectionInfo.name = propertyTable.collectionName
		publishedCollectionInfo.remoteId = propertyTable.collectionId
		publishedCollectionInfo.toCommunity = propertyTable.toCommunity
		publishedCollectionInfo.path = propertyTable.collectionPath
	end

	local success, obj = PxAPI.getCollections( propertyTable )
	if obj == "banned" then
		LrErrors.throwUserError( "Sorry, this user is inactive or banned. If you think this is a mistake — please contact us by email: help@500px.com." )
	end

	if not success then
		LrErrors.throwUserError( "Could not connect to 500px. Please make sure you are logged in and try again." )
		return
	end

	local collections = obj.collections

	local success, obj = PxAPI.getUser( propertyTable )

	if obj == "banned" then
		LrErrors.throwUserError( "Sorry, this user is inactive or banned. If you think this is a mistake — please contact us by email: help@500px.com." )
	end

	if not success then
		LrErrors.throwUserError( "Could not connect to 500px. Please make sure you are connected to the internet and try again." )
	end
	local user = obj.user
	propertyTable.isUserAwesome = ( user.upgrade_status == 2 )
	propertyTable.isUserPlus 	= ( user.upgrade_status == 1 )
	propertyTable.uploadLimit = user.upload_limit
	propertyTable.domain = user.domain

	-- check if user made this collection online already...
	local remoteCollection
	for _, collection in ipairs( collections ) do
		if collection.id == publishedCollectionInfo.remoteId then
			remoteCollection = collection
			break
		elseif collection.title == publishedCollectionInfo.name then
			remoteCollection = collection
			break
		end
	end

	-- get a list of all photos in the collection
	local photoList = ","
	if remoteCollection then
		for _, photo in ipairs( remoteCollection.photos ) do
			photoList = string.format( "%s%i,", photoList, photo.id )
		end
	end

	if publishedCollection then
		LrApplication:activeCatalog():withReadAccessDo( function()
			for _, photo in ipairs( publishedCollection:getPublishedPhotos() ) do
				local pid = photo:getPhoto():getPropertyForPlugin( _PLUGIN, "photoId" )
				if pid and not string.match( photoList, string.format( ",%s,", pid ) ) then
					logger:trace( "Added missing photo to list: " .. pid )
					photoList = string.format( "%s%i,", photoList, pid )
				end
			end
		end )
	end

	-- create the collection if it doesn't already exist
	if not remoteCollection and not publishedCollectionInfo.isDefaultCollection then
		if not propertyTable.isUserAwesome and not propertyTable.isUserPlus then
			local message = "Cannot create a new set."
			local messageInfo = "You have to upgrade to create sets and portfolio sets."
			local action = LrDialogs.confirm( message, messageInfo, "Become Awesome!" )
			if action == "ok" then
				LrHttp.openUrlInBrowser( "http://500px.com/upgrade" )
			end
			return
		else
			local args = {
				title = publishedCollectionInfo.name,
				path = publishedCollectionInfo.path,
				kind = 2 -- Creating Profile Set by default
			}
			local success, obj = PxAPI.postCollection( propertyTable, args )

			if not success then
				LrErrors.throwUserError( "Could not create the collection. Please try again later." )
				return
			else
				publishedCollectionInfo.remoteId = obj.id
				publishedCollectionInfo.remoteUrl = PxAPI.makeCollectionUrl( propertyTable.username, publishedCollectionInfo.path )
				--if there's any published photos in this
				--collection, then we have a problem...
				if publishedCollection then
					for _, photo in ipairs( publishedCollection:getPublishedPhotos() ) do
						local pid
						LrApplication:activeCatalog():withReadAccessDo( function()
							pid = photo:getPhoto():getPropertyForPlugin( _PLUGIN, "photoId" )
						end )

						LrApplication:activeCatalog():withWriteAccessDo( "", function()
							photo:setRemoteId( string.format( "%s-%i", pid, obj.id ) )
						end )
					end
				end
			end
		end
	elseif publishedCollectionInfo.isProfileCollection then
		publishedCollectionInfo.remoteId = "profile"
	elseif publishedCollectionInfo.isAllPhotosCollection then
		publishedCollectionInfo.remoteId = "nil"
	else
		publishedCollectionInfo.remoteId = remoteCollection.id
	end

	if isPublish then
		logger:trace( "Collection: " .. publishedCollectionInfo.name )
		logger:trace( "URL: " .. publishedCollectionInfo.remoteUrl )
		logger:trace( "ID: " .. publishedCollectionInfo.remoteId )
	end

	local photos = getPhotoInfo( exportContext )
	local uploadLimit = propertyTable.uploadLimit or 0

	logger:trace( "Upload limit: " .. tostring(uploadLimit) )
	local uploadCount = 0

	for i, data in pairs( photos ) do
		local rendition = data.rendition
		local photoInfo = data.photoInfo
		progressScope:setPortionComplete( ( i - 1 ) / nPhotos )
		local photo = rendition.photo
		if not photoInfo.skipped and not photoInfo.failed then

			logger:trace(" -- LR Photo status: " .. tostring(photoInfo.status))

			local success = true, obj

			if progressScope.isCancelled then break end

			if not photoInfo.id and not (propertyTable.isUserAwesome or propertyTable.isUserPlus) and uploadLimit <= 0 then
				logger:trace( "Upload limit reached." .. tostring(uploadLimit) )
				rendition:uploadFailed( "You have reached your weekly upload limit after 10 uploads on a basic account."  .. uploadLimit)
				photoInfo.failed = true
			else
				photoid = photoInfo.id
				photostatus = photoInfo.status

				if photostatus == 9 then
					photoid = nil
					photoInfo.privacy = 1
				end

				local args = {
					photo_id = photoid,
					name = photoInfo.title,
					description = photoInfo.description,
					category = photoInfo.category,
					privacy = photoInfo.privacy,
					nsfw = booleanToNumber( photoInfo.nsfw ),
					license_type = photoInfo.license_type,
					lens = photoInfo.lens
				}

				if photoInfo.privacy == 1 and publishedCollectionInfo.toCommunity then
					photoInfo.privacy = 0
					args.privacy = 0
				end
				success, obj = PxAPI.postPhoto( propertyTable, args )
				photoInfo.uploadKey = obj.upload_key
				if obj.photo then photoInfo.id = tostring( obj.photo.id ) end
			end

			-- update the collection
			if not success then
				logger:trace( "photo upload failed" )
				rendition:uploadFailed( "Could not upload this photo. It probably already exists on 500px, please try to publish it again." )
				photoInfo.failed = true
			elseif photoInfo.tags and not photoInfo.failed then
				local args = {
					photo_id = photoInfo.id,
					tags = photoInfo.tags,
					previous_tags = photoInfo.previous_tags,
				}
				success, _ = PxAPI.setPhotoTags( propertyTable, args )
			end

			if not success and not photoInfo.failed then
				logger:trace( "updating tags failed" )
				rendition:uploadFailed( "Could not connect to 500px." )
				photoInfo.failed = true
			elseif not publishedCollectionInfo.isDefaultCollection and not string.match( photoList, string.format( ",%s,", photoInfo.id ) ) and not photoInfo.failed then
				logger:trace( "updating collection..." )

				photoList = string.format( "%s%s,", photoList, photoInfo.id )

				local args = {
					collection_id = publishedCollectionInfo.remoteId,
					photo_ids = string.sub( photoList, 2, string.len( photoList ) - 1 ),
				}

				success, obj = PxAPI.postCollection( propertyTable, args )
				if obj == "other" then
					LrErrors.throwUserError( "Sorry, you have to upgrade to work with Sets." )
				end
			end

			-- upload the photo
			if not success and not photoInfo.failed then
				logger:trace( "unabled to update collection" )
				rendition:uploadFailed( "Unable to add this photo to your portfolio." )
				photoInfo.failed = true
			elseif photoInfo.uploadKey and not photoInfo.failed then
				logger:trace( "uploading photo" )
				local args = {
					photo_id = photoInfo.id,
					upload_key = photoInfo.uploadKey,
					access_key = propertyTable.credentials.oauth_token,
					file_path = photoInfo.path,
				}
				success, obj = PxAPI.upload( args )
				uploadLimit = uploadLimit - 1
			end

			-- record remote id and url
			if not success and not photoInfo.failed then
				logger:trace( "upload failed." )
				rendition:uploadFailed( "Could not connect to 500px." )
				photoInfo.failed = true
				uploadLimit = uploadLimit + 1
			elseif not photoInfo.failed then
				-- uploadLimit = uploadLimit - 1
				if isPublish then

					if PluginInit then PluginInit.lock() end
					LrApplication:activeCatalog():withWriteAccessDo( "publish", function( context )
						photo:setPropertyForPlugin( _PLUGIN, "photoId", tostring( photoInfo.id ) )

						rendition:recordPublishedPhotoId( string.format( "%s-%s", photoInfo.id, publishedCollectionInfo.remoteId ) )
						rendition:recordPublishedPhotoUrl( string.format( "http://500px.com/photo/%s", photoInfo.id ) )

						photo:setPropertyForPlugin( _PLUGIN, "publishedUUID", photo:getRawMetadata( "uuid" ) )

						-- this is stupid, but has to be here for LR4 and keywords. Photos all be marked as modified when you change you metadata in the upload dialog
						exportContext.publishedCollection:addPhotoByRemoteId( photo, string.format( "%s-%s", photoInfo.id, publishedCollectionInfo.remoteId ), string.format( "http://500px.com/photo/%s", photoInfo.id ), true )

						-- mark all photo is published in all collections it belongs to
						if photoInfo.collections then
							for _, collection in ipairs( photoInfo.collections ) do
								collection:addPhotoByRemoteId( photo, string.format( "%s-%s", photoInfo.id, collection:getRemoteId() ), string.format( "http://500px.com/photo/%s", photoInfo.id ), true )
							end
						end

						-- add photo to "Library"
						if not publishedCollectionInfo.isAllPhotosCollection and allPhotosCollection then
							allPhotosCollection:addPhotoByRemoteId( photo, string.format( "%s-nil", photoInfo.id ), string.format( "http://500px.com/photo/%s", photoInfo.id ), true )
						end

						-- add photo to "Profile"
						if photoInfo.privacy == 0 and not publishedCollectionInfo.isProfileCollection then
							profileCollection:addPhotoByRemoteId( photo, string.format( "%s-profile", photoInfo.id ), string.format( "http://500px.com/photo/%s", photoInfo.id ), true )
						end
					end )
					if PluginInit then PluginInit.unlock() end
				end
			end

			LrFileUtils.delete( photoInfo.path )
			progressScope:setPortionComplete( ( i - 0.5 ) / nPhotos )
		end
	end

	-- record remote id and url
	if isPublish then
		exportSession:recordRemoteCollectionId( publishedCollectionInfo.remoteId )
		exportSession:recordRemoteCollectionUrl( publishedCollectionInfo.remoteUrl )
	end
end

return exportServiceProvider
