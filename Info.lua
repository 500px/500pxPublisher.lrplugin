return {
	LrSdkVersion = 4.0,
	LrSdkMinimumVersion = 3.0,
	LrToolkitIdentifier = "com.500px.publisher",
	LrPluginName = "500px",
	LrPluginInfoUrl = "https://500px.com/lightroom",
	LrInitPlugin = "PluginInit.lua",
	LrExportServiceProvider = {
		title = "500px",
		file = "500pxExportServiceProvider.lua",
		image = "500px.png",
	},
	LrMetadataTagsetFactory = "500pxTagset.lua",
	LrMetadataProvider = "500pxMetadataDefinition.lua",
	VERSION = { major=1, minor=10 },
	URLHandler = "500pxURLHandler.lua",
}
