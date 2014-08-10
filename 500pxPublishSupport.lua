-- Lightroom SDK
local LrApplication = import "LrApplication"
local LrDate = import "LrDate"
local LrErrors = import "LrErrors"
local LrTasks = import "LrTasks"
local LrView = import "LrView"

-- Common Shortcuts
local bind = LrView.bind

-- Logging
local logger = import "LrLogger"("500pxPublisher")
logger:enable("logfile")

-- 500px Plugin
require "500pxAPI"

local publishServiceProvider = {}

publishServiceProvider.small_icon = "500px_icon.png"

-- Description entry in the Publish Manager dialog, if the user does not provide one.
publishServiceProvider.publish_fallbackNameBinding = "username"

publishServiceProvider.titleForGoToPublishedCollection = "Show in 500px"
publishServiceProvider.titleForGoToPublishedPhoto = "Show in 500px"

publishServiceProvider.titleForPublishedCollection = "Collection"
publishServiceProvider.titleForPublishedCollection_standalone = "Collection"
publishServiceProvider.titleForPublishedSmartCollection = "Smart Collection"
publishServiceProvider.titleForPublishedSmartCollection_standalone = "Smart Collection"


function publishServiceProvider.getCollectionBehaviorInfo( publishSettings )
	return {
		defaultCollectionName = "Library",
		defaultCollectionCanBeDeleted = false,
		canAddCollection = true,
		maxCollectionSetDepth = 0, -- collection sets not supported
	}
end

--[[ Called when the user creates a new publish service. Will create a published collection for each collection in the user's portfolio. ]]--
function publishServiceProvider.didCreateNewPublishService( publishSettings, info )
	publishSettings.LR_publishService = info.publishService

	if publishSettings.syncNow then
		if publishSettings.syncCollectionsOnly then
			PxUser.syncCollections( publishSettings )
		else
			PxUser.sync( publishSettings )
		end
	else
		info.publishService.catalog:withWriteAccessDo( "", function()
			for _, collection in ipairs( info.publishService:getChildCollections() ) do
				collection:setCollectionSettings( { toCommunity = false } )
				collection:setRemoteUrl( "http://500px.com/organizer" )
			end

			local collection = info.publishService:createPublishedCollection( "Public Profile", nil, true )
			collection:setCollectionSettings( { toCommunity = true } )
			collection:setRemoteUrl( "http://500px.com/" .. publishSettings.username )
	end)
	end
end

-- called when user attempts to delete published photos, use to customize dialog
function publishServiceProvider.shouldDeletePhotosFromServiceOnDeleteFromCatalog( publishSettings, nPhotos )
	-- don't delete anything from 500px
	return nil
end

function publishServiceProvider.deletePhotosFromPublishedCollection( publishSettings, arrayOfPhotoIds, deletedCallback )
	local success, obj = PxAPI.getCollections( publishSettings )

	if obj == "banned" then
		LrErrors.throwUserError( "Sorry, this user is inactive or banned. If you think this is a mistake — please contact us by email: help@500px.com." )
	end

	local collections = {}
	for _, collection in ipairs( obj.collections ) do
		local photos = ","
		for _, photo in ipairs( collection.photos ) do
			photos = string.format( "%s%i,", photos, photo.id )
		end
		collections[ tostring( collection.id ) ] = photos
	end

	local LrApplication = import "LrApplication"
	local catalog = LrApplication:activeCatalog()
	local publishServices = catalog:getPublishServices( "com.500px.publisher" )
	local publishService
	for _, ps in ipairs( publishServices ) do
		if ps:getPublishSettings().username == publishSettings.username then
			publishService = ps
			break
		end
	end

	LrApplication:activeCatalog():withReadAccessDo( function()
		for _, publishedCollection in ipairs( publishService:getChildCollections() ) do
			local name = publishedCollection:getName()
			if name ~= "Profile" and name ~= "Public Profile" and name ~= "Library" and name ~= "Organizer" then
				local cid = tostring( publishedCollection:getRemoteId() )
				local photos = collections[ cid ]

				for _, photo in ipairs( publishedCollection:getPublishedPhotos() ) do
					local pid = photo:getPhoto():getPropertyForPlugin( _PLUGIN, "photoId" )
					if pid and not string.match( photos, string.format( ",%s,", pid ) ) then
						logger:trace( "Added missing photo to list: " .. pid )
						photos = string.format( "%s%i,", photos, pid )
					end
				end

				collections[ cid ] = photos
			end
		end
	end )

	for i, remoteId in ipairs( arrayOfPhotoIds ) do

		local photo_id, collection_id = string.match( arrayOfPhotoIds[i], "([^-]+)-([^-]+)" )
		local success, obj

		if collection_id == "profile" then
			success, obj = PxAPI.postPhoto( publishSettings, { photo_id = tonumber( photo_id ), privacy = 1 } )
		elseif collection_id ~= "nil" then
			local photos = collections[ collection_id ]
			photos = string.gsub( photos, "," .. photo_id .. ",", "," )
			collections[ collection_id ] = photos
			success, obj = PxAPI.postCollection( publishSettings, { collection_id = collection_id, photo_ids = string.sub( photos, 2, string.len( photos ) ) } )
		else
			success, obj = PxAPI.deletePhoto( publishSettings, { photo_id = tonumber( photo_id ) } )

			if PluginInit then PluginInit.lock() end
			LrApplication:activeCatalog():withWriteAccessDo( "delete", function()
				for _, publishedCollection in ipairs( publishService:getChildCollections() ) do
					for _, photo in ipairs( publishedCollection:getPhotos() ) do
						if photo:getPropertyForPlugin( _PLUGIN, "photoId" ) == photo_id then
							publishedCollection:removePhotos( { photo } )
							-- may want to unset all metadata too
							photo:setPropertyForPlugin( _PLUGIN, "photoId", nil )
							photo:setPropertyForPlugin( _PLUGIN, "views", nil )
							photo:setPropertyForPlugin( _PLUGIN, "favorites", nil )
							photo:setPropertyForPlugin( _PLUGIN, "votes", nil )
							photo:setPropertyForPlugin( _PLUGIN, "publishedUUID", nil )
							photo:setPropertyForPlugin( _PLUGIN, "previous_tags", nil )
							photo:setPropertyForPlugin( _PLUGIN, "privacy", nil )
						end
					end
				end
			end)
			if PluginInit then PluginInit.unlock() end

		end
		deletedCallback( remoteId )
	end
end

function publishServiceProvider.metadataThatTriggersRepublish( publishSettings )
	return  {
		default = false,
		title = true,
		caption = true,
		keywords = true,
		["com.500px.publisher.nsfw"] = true,
		["com.500px.publisher.license_type"] = true,
		["com.500px.publisher.category"] = true,
	}
end

local settings

function publishServiceProvider.validatePublishedCollectionName( newName )
	settings.newPath = PxAPI.collectionNameToPath( newName )
	return true
end

function publishServiceProvider.endDialogForCollectionSettings( publishSettings, info )
	local collectionSettings = info.collectionSettings or {}
	collectionSettings.path = collectionSettings.newPath
end

function publishServiceProvider.viewForCollectionSettings( f, publishSettings, info )
	settings = info.collectionSettings or {}
	-- don't let them edit the default collection
	if info.isDefaultCollection or info.name == "Public Profile" or info.name == "Profile" or info.name == "Library" or info.name == "Organizer" then
		info.collectionSettings.LR_canSaveCollection = false
		return
	end

	if not info.publishedCollection then
		info.collectionSettings.toCommunity = publishSettings.toCommunity
	end

	settings.newPath = settings.path

	return f:group_box {
		title = "500px",
		fill = 1,
		spacing = f:control_spacing(),
		bind_to_object = info.collectionSettings,
		f:row {
			f:static_text {
				title = "URL:",
				alignment = "right",
			},
			f:edit_field {
				value = bind "newPath",
			}
		}
	}
end

function publishServiceProvider.shouldReverseSequenceForPublishedCollection( publishSettings, collectionInfo )
	return false
end

-- not for now
publishServiceProvider.supportsCustomSortOrder = false

function publishServiceProvider.updateCollectionSettings( publishSettings, info )
	logger:trace("updateCollectionSettings")
	local remoteId = info.publishedCollection:getRemoteId()
	if remoteId then
		if not info.collectionSettings.newPath then
			info.collectionSettings.newPath = PxAPI.collectionNameToPath( info.name )
		end
		local args = {
			collection_id = remoteId,
			title = info.name,
			path = info.collectionSettings.newPath
		}
		local success, obj = PxAPI.postCollection( publishSettings, args )

		if obj == "other" then
			LrErrors.throwUserError( "Sorry, you have to upgrade to create sets." )
		end

		if not success and obj.status == 404 then
			args.collection_id = nil
			success, obj = PxAPI.postCollection( publishSettings, args )
		end

		if success then
			info.collectionSettings.path = info.collectionSettings.newPath
			info.collectionSettings.newPath = nil
			info.publishedCollection.catalog:withPrivateWriteAccessDo( function()
				info.publishedCollection:setCollectionSettings( info.collectionSettings )
				info.publishedCollection:setRemoteUrl( PxAPI.makeCollectionUrl( publishSettings.username, info.collectionSettings.path ) )
			end )
		else
			LrErrors.throwUserError( "Could not update the collection." )
		end
	end
end

function publishServiceProvider.shouldDeletePublishedCollection( publishSettings, info )
	for i, collection in ipairs( info.collections ) do
		if collection:getName() == "Public Profile" then
			return "cancel"
		end
	end
	return nil
end

function publishServiceProvider.deletePublishedCollection( publishSettings, info )
	if info.name == "Public Profile" then
		LrErrors.throwUserError( "You can not delete your public profile." )
	elseif info.remoteId then
		local success, obj = PxAPI.deleteCollection( publishSettings, { collection_id = info.remoteId } )
		if not success and obj.status ~= 404 then
			LrErrors.throwUserError( "Could not delete collection from your portfolio. Try again later." )
		end
	else
		LrErrors.throwUserError( "You can not delete this collection" )
	end
end

function publishServiceProvider.willDeletePublishService( publishSettings, info )
	local publishService = info.publishService

	local publishedPhotos = publishService.catalog:findPhotosWithProperty( "com.500px.publisher", "photoId" )
	for _, photo in ipairs( publishedPhotos ) do
		photo:setPropertyForPlugin( _PLUGIN, "views", nil )
		photo:setPropertyForPlugin( _PLUGIN, "favorites", nil )
		photo:setPropertyForPlugin( _PLUGIN, "votes", nil )
		photo:setPropertyForPlugin( _PLUGIN, "previous_tags", nil )
		photo:setPropertyForPlugin( _PLUGIN, "publishedUUID", nil )
		photo:setPropertyForPlugin( _PLUGIN, "photoId", nil )
		photo:setPropertyForPlugin( _PLUGIN, "privacy", nil )
	end
end

local function formatDate( datetime )
	local year, month, day, hour, minute, second = string.match( datetime, "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).*"	)
	return LrDate.timeFromComponents( year, month, day, hour, minute, second, -18000 )
end

function publishServiceProvider.getCommentsFromPublishedCollection( publishSettings, arrayOfPhotoInfo, commentCallback )
	for i, photoInfo in ipairs( arrayOfPhotoInfo ) do
		local photoId
		LrApplication:activeCatalog():withReadAccessDo( function()
			photoId = photoInfo.photo:getPropertyForPlugin( _PLUGIN, "photoId" )
		end )
		local commentList = {}
		if photoId then
			local page = 1

			-- while true do
				local success, obj = PxAPI.getComments( publishSettings, { photo_id = photoId, page = page } )
				local comments = success and obj.comments
				if comments and #comments > 0 then
					for _, comment in ipairs( comments) do
						table.insert( commentList, {
							commentId = comment.id,
							commentText = PxAPI.decodeString( comment.body ),
							dateCreated = formatDate( comment.created_at ),
							username = comment.user.username,
							realname = comment.user.fullname,
						} )
					end
				end

				-- if success and obj.total_pages == obj.current_page then break end
				-- page = page + 1
			-- end
		end
		commentCallback { publishedPhoto = photoInfo, comments = commentList }
	end
end

publishServiceProvider.titleForPhotoRating = "Rating"

function publishServiceProvider.getRatingsFromPublishedCollection( publishSettings, arrayOfPhotoInfo, ratingCallback )
	logger:trace("getRatingsFromPublishedCollection")
	for i, photoInfo in ipairs( arrayOfPhotoInfo ) do
		local photoId
		LrApplication:activeCatalog():withReadAccessDo( function()
			photoId = photoInfo.photo:getPropertyForPlugin( _PLUGIN, "photoId" )
		end )
		local success, obj = PxAPI.getPhoto( publishSettings, { photo_id = photoId } )
		if success then
			local rating = obj.photo.rating
			-- update photos view, favorites etc...
			if PluginInit then PluginInit.lock() end
			photoInfo.photo.catalog:withPrivateWriteAccessDo( function()
				photoInfo.photo:setPropertyForPlugin( _PLUGIN, "views", tostring( obj.photo.times_viewed ) )
				photoInfo.photo:setPropertyForPlugin( _PLUGIN, "favorites", tostring( obj.photo.favorites_count ) )
				photoInfo.photo:setPropertyForPlugin( _PLUGIN, "votes", tostring( obj.photo.votes_count ) )
			end )
			if PluginInit then PluginInit.unlock() end

			ratingCallback { publishedPhoto = photoInfo, rating = rating }
		else
			photoInfo.photo:setPropertyForPlugin( _PLUGIN, "photoId", nil )
			local publishedCollections = photoInfo.photo:getContainedPublishedCollections() or {}
			for _, publishedCollection in ipairs( publishedCollections ) do
				if publishedCollection:getService():getPluginId() == "com.500px.publisher" then
					if PluginInit then PluginInit.lock() end
					publishedCollection.catalog:withWriteAccessDo( "Delete Photo", function()
						publishedCollection:removePhotos( { photo } )
					end )
					if PluginInit then PluginInit.unlock() end

				end
			end

			ratingCallback { publishedPhoto = photoInfo, rating = 0 }
		end
	end

end

function publishServiceProvider.cansToService( publishService )
	--test if we can contact 500px....
	return true
end

function publishServiceProvider.addCommentToPublishedPhoto( publishSettings, remotePhotoId, commentText )
	local photoId, collectionId = string.match( remotePhotoId, "([^-]+)-([^-]+)" )
	local success, _ = PxAPI.postComment( publishSettings, {
		photo_id = photoId,
		body = PxAPI.encodeString( commentText ),
	} )
	return success
end

publishSupport = publishServiceProvider
