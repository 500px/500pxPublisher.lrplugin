return {
	metadataFieldsForPhotos = {
		{
			id = "photoId",
			datatype = "string",
		},
		{
			id = "publishedUUID",
			dataType = "string",
		},
		{
			id = "privacy",
			dataType = "enum",
			values = {
				{ value = 0, title="public" },
				{ value = 1, title="private" },
			}
		},
		{
			id = "nsfw",
			title = "Mature Content",
			dataType = "enum",
			values = {
				{ value = 0, title = "No" },
				{ value = 1, title = "Yes" },
			},
		},
		{
			id = "license_type",
			title = "License Type",
			dataType = "enum",
			values = {
				{ value = 0, title = "Standard 500px License" },
				{ value = 4, title = "Attribution 3.0" },
				{ value = 5, title = "Attribution-NoDerivs 3.0" },
				{ value = 6, title = "Attribution-ShareAlike 3.0" },
				{ value = 1, title = "Attribution-NonCommercial 3.0" },
				{ value = 2, title = "Attribution-NonCommercial-NoDerivs 3.0" },
				{ value = 3, title = "Attribution-NonCommercial-ShareAlike 3.0" }
			},
		},
		{
			id = "category",
			title = "Category",
			dataType = "enum",
			values = {
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
		},
		{
			id = "views",
			title = "Views",
			dataType = "string",
			readOnly = true,
		},
		{
			id = "favorites",
			title = "Favorites",
			dataType = "string",
			readOnly = true,
		},
		{
			id = "votes",
			title = "Votes",
			dataType = "string",
			readOnly = true,
		},
		{
			id = "previous_tags",
			dataType = "string",
		},
	},
	schemaVersion = 7,
	updateFromEarlierSchemaVersion = function( catalog, previousSchemaVersion, progressScope ) 
		if previousSchemaVersion == 7 then
			return
		end
		catalog:assertHasPrivateWriteAccess( "updateFromEarlierSchemaVersion" )
		local photosToMigrate = catalog:findPhotosWithProperty( "com.500px.publisher", "photoId" )
		for _, photo in ipairs( photosToMigrate ) do
			photo:setPropertyForPlugin( _PLUGIN, "publishedUUID", photo:getRawMetadata( "uuid" ) )
			photo:setPropertyForPlugin( _PLUGIN, "nsfw", 0 )
		end
	end
}
