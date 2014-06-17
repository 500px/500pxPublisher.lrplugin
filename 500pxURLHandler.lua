local LrDialogs = import "LrDialogs"

require "500pxAPI"

return {
	URLHandler = function ( url )
		if PxAPI.URLCallback then
			PxAPI.URLCallback( url:match( "oauth_token=([^&]+)" ), url:match( "oauth_verifier=([^&]+)" ) )
		end
	end
}
