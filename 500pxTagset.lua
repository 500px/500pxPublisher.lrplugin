if PluginInit then
	PluginInit.checkForUpdates()
	PluginInit.forceNewCollections()
end

return {
	title = "500px",
	id = "500pxTagset",
	items = {
		"com.adobe.title",
		{ "com.adobe.caption", height_in_lines = 3, label = "Description", },
		"com.500px.publisher.category",
		"com.500px.publisher.license_type",
		"com.500px.publisher.nsfw",
		"com.adobe.separator",
		{ "com.adobe.label", label = "Stats" },
		"com.500px.publisher.views",
		"com.500px.publisher.favorites",
		"com.500px.publisher.votes",
	},
}
