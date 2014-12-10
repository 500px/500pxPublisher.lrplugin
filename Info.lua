local majorVersion = 1
local minorVersion = 7
local revisionVersion = 1
displayVersion = majorVersion ..".".. minorVersion ..".".. revisionVersion

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
	VERSION = { major = majorVersion, minor = minorVersion, revision = revisionVersion },
	URLHandler = "500pxURLHandler.lua",
}
