--[[ Some Handy Constants ]]--
local CONSUMER_KEY = "";
local CONSUMER_SECRET = ""
local SALT = ""

local LrDate = import "LrDate"
local LrErrors = import "LrErrors"
local LrHttp = import "LrHttp"
local LrMD5 = import "LrMD5"
local LrPathUtils = import "LrPathUtils"
local LrStringUtils = import "LrStringUtils"
local LrTasks = import "LrTasks"
local LrBinding = import "LrBinding"
local LrDialogs = import "LrDialogs"
local LrView = import "LrView"

-- Common shortcuts
local bind = LrView.bind

require "sha1"

local JSON = require "JSON"
function JSON:onDecodeError( message, text, char )
	if string.match( text, "Invalid OAuth Request" ) then
		LrErrors.throwUserError( "You must grant this Publish Service access to your 500px account. Please edit the settings for this Publish Service and login." )
	else
		LrErrors.throwUserError( "Oops, somethign went wrong. Try again later. onDecodeError" )
	end
end

local logger = import "LrLogger"("500pxPublisher")
logger:enable("logfile")

-- Cocaoa time of 0 is unix time 978307200
local COCOA_TIMESHIFT = 978307200

local REQUEST_TOKEN_URL = "https://api.500px.com/v1/oauth/request_token" -- https://
local AUTHORIZE_TOKEN_URL = "https://api.500px.com/v1/oauth/authorize" -- https://
local ACCESS_TOKEN_URL = "https://api.500px.com/v1/oauth/access_token" -- https://
local CALLBACK_URL = "http://500px.com/apps/lightroom"
local BASE_URL = "https://api.500px.com/v1/" -- https://

--[[ Some Handy Helper Functions ]]--
local function oauth_encode( value )
	return tostring( string.gsub( value, "[^-._~a-zA-Z0-9]",
				function( c )
					return string.format( "%%%02x", string.byte( c ) ):upper()
				end ) )
end

local function unix_timestamp()
	return tostring(COCOA_TIMESHIFT + math.floor(LrDate.currentTime() + 0.5))
end

local function generate_nonce()
	return LrMD5.digest( tostring(math.random())
			.. tostring(LrDate.currentTime())
			.. SALT )
end

--[[ Returns an oAuth athorization header and a query string (or post body). ]]--
local function oauth_sign( method, url, args )

	assert( method == "GET" or method == "POST" )

	--common oauth parameters
	args.oauth_consumer_key = CONSUMER_KEY
	args.oauth_timestamp = unix_timestamp()
	args.oauth_version = "1.0"
	args.oauth_nonce = generate_nonce()
	args.oauth_signature_method = "HMAC-SHA1"

	local oauth_token_secret = args.oauth_token_secret or ""
	args.oauth_token_secret = nil

	local data = ""
	local query_string = ""
	local header = ""

	local data_pattern = "%s%s=%s"
	local query_pattern = "%s%s=%s"
	local header_pattern = "OAuth %s%s=\"%s\""

	local keys = {}
	for key in pairs( args ) do
		table.insert( keys, key )
	end
	table.sort( keys )

	for _, key in ipairs( keys ) do
		local value = args[key]

		-- url encode the value if it's not an oauth parameter
		if string.find( key, "oauth" ) == 1 and key ~= "oauth_callback" then
			value = string.gsub( value, " ", "+" )
			value = oauth_encode( value )
		end

		-- oauth encode everything, non oauth parameters get encoded twice
		value = oauth_encode( value )

		-- build up the base string to sign
		data = string.format( data_pattern, data, key, value )
		data_pattern = "%s&%s=%s"

		-- build up the oauth header and query string
		if string.find( key, "oauth" ) == 1 then
			header = string.format( header_pattern, header, key, value )
			header_pattern = "%s, %s=\"%s\""
		else
			query_string = string.format( query_pattern, query_string, key, value )
			query_pattern = "%s&%s=%s"
		end
	end

	local to_sign = string.format( "%s&%s&%s", method, oauth_encode( url ), oauth_encode( data ) )
	local key = string.format( "%s&%s", oauth_encode( CONSUMER_SECRET ), oauth_encode( oauth_token_secret ) )
	local hmac_binary = hmac_sha1_binary( key, to_sign )
	local hmac_b64 = LrStringUtils.encodeBase64( hmac_binary )

	data = string.format( "%s&oauth_signature=%s", data, oauth_encode( hmac_b64 ) )
	header = string.format( "%s, oauth_signature=\"%s\"", header, oauth_encode( hmac_b64 ) )

	return query_string, { field = "Authorization", value = header }
end

--[[ Does an HTTP request to the given url with the given HTTP method and parameters. Returns the raw response, if the request was successful. Otherwise returns nil and an error message. ]]--
local function call_it( method, url, params, rid )
	query_string = ""
	auth_header = ""
	local query_string, auth_header = oauth_sign( method, url, params )

	if rid then
		logger:trace( "Query " .. rid .. ": " .. method .. " " .. url .. "?" .. query_string )
	end

	if method == "POST" then
		return LrHttp.post( url, query_string, { auth_header, { field = "Content-Type", value = "application/x-www-form-urlencoded" }, { field = "User-Agent", value = "500px Plugin 1.0" }, { field = "Cookie", value = "GARBAGE" } } )
	else
		return LrHttp.get( url .. "?" .. query_string, { auth_header, { field = "User-Agent", value = "500px Plugin 0.1.5" } } )
	end
end

--[[ Calls the rest method and JSON decodes the response ]]--
local function call_rest_method( propertyTable, method, path, args )
	local url = BASE_URL .. path

	local args = args or {}
	local rid = math.random(99999)

	if propertyTable.credentials then
		args.oauth_token = propertyTable.credentials.oauth_token
		args.oauth_token_secret = propertyTable.credentials.oauth_token_secret
	end

	local response, headers = call_it( method, url, args, rid )

	-- logger:trace( "Query " .. rid .. ": " .. (headers.status or -1) )

	if not headers.status then
		LrErrors.throwUserError( "Could not connect to 500px. Make sure you are connected to the internet and try again." )
	end

	if headers.status > 404 then
		logger:trace("Api error. Response: " .. response)
		LrErrors.throwUserError("Something went wrong, try again later.")
	elseif headers.status > 401 then
		if response:match("Deactivated user") or response:match("This account is banned or deactivated") then
--			logger:trace("User is banned or deactivated. Response: " .. response)
			return headers.status == 403, "banned"
		else
--			logger:trace("Request: " .. path .. "  Response: " .. response)
			return headers.status == 403, "other"
		end
	end

	return headers.status == 200, JSON:decode( response )
end

PxAPI = {  }

function PxAPI.encodeString( str )
	-- Lightroom uses the unicode LINE SEPARATOR but the API uses to more regular newline.
	return string.gsub( str, string.char( 0xE2, 0x80, 0xA8 ), "\n" )
end

function PxAPI.decodeString( str )
	-- Lightroom uses the unicode LINE SEPARATOR but the API uses to more regular newline.
	return string.gsub( str, "\n", string.char( 0xE2, 0x80, 0xA8 ) )
end

function PxAPI.makeCollectionUrl( domain, path )
	if domain and path then
		return "http://500px.com/" .. domain .. "/sets/" .. path
	end
end

-- function PxAPI.makeSetUrl( user, path )
-- 	if domain and path then
-- 		logger:trace( "http://500px.com/" .. user .. "/sets/" .. path )
-- 		return "http://500px.com/" .. user .. "/sets/" .. path
-- 	end
-- end

function PxAPI.collectionNameToPath( name )
	name = name or ""
	return tostring( string.gsub( tostring( string.gsub( name, "[^a-zA-Z0-9]+", "_" ) ), "%a", string.lower ) )
end

function PxAPI.getPhotos( propertyTable, args )
	return call_rest_method( propertyTable, "GET", "photos", args)
end

function PxAPI.getPhoto( propertyTable, args )
	local path = "photos"
	if args.photo_id ~= nil then
		path = string.format( "photos/%i", args.photo_id )
		args.photo_id = nil
		return call_rest_method( propertyTable, "GET", path, args )
	end
end

function PxAPI.postPhoto( propertyTable, args )
	local path = "photos"
	if args and args.photo_id then
		path = string.format( "photos/%i", args.photo_id )
		args.photo_id = nil
		args._method = "PUT"
	end

	return call_rest_method( propertyTable, "POST", path, args )
end

function PxAPI.deletePhoto( propertyTable, args )
	path = string.format( "photos/%i", args.photo_id )
	args.photo_id = nil
	args._method = "DELETE"

	return call_rest_method( propertyTable, "POST", path, args )
end

function PxAPI.upload( args )
	local url = "http://media.500px.com/upload"

	url = string.format("%s?upload_key=%s&photo_id=%s&consumer_key=%s&access_key=%s", url, args.upload_key, args.photo_id, CONSUMER_KEY, args.access_key)

	local filePath = assert( args.file_path )
	local fileName = LrPathUtils.leafName( filePath )
	args.file_path = nil

	local mimeChunks = {}

	mimeChunks[ #mimeChunks + 1 ] = {
		name= "file",
		fileName = fileName,
		filePath = filePath,
		contentType = "application/octet-stream",
	}

	local response, headers = LrHttp.postMultipart( url, mimeChunks )

	if not response or headers.status ~= 200 then
		logger:trace( "Upload failed: " .. ( headers.status or "-1" ) )
		return false, {}
	end
	return true, {}

end

function PxAPI.getComments( propertyTable, args )
	local path = string.format( "photos/%i/comments", args.photo_id )
	args.photo_id = nil

	return call_rest_method( propertyTable, "GET", path, args )
end

function PxAPI.postComment( propertyTable, args )
	local path = string.format( "photos/%i/comments", args.photo_id )
	args.photo_id = nil

	return call_rest_method( propertyTable, "POST", path, args )
end

function PxAPI.getUser( propertyTable, args )
	LrHttp.get( "http://500px.com/logout" )
	return call_rest_method( propertyTable, "GET", "users", args )
end

function PxAPI.getCollections( propertyTable, args )
	return call_rest_method( propertyTable, "GET", "collections", args )
end

function PxAPI.postCollection( propertyTable, args )
	local path = "collections"
	if args and args.collection_id then
		path = string.format( "collections/%s", tostring( args.collection_id ) )
		args.collection_id = nil
		args._method = "PUT"
	else
		args._method = nil
	end

	return call_rest_method( propertyTable, "POST", path, args )
end

function PxAPI.deleteCollection( propertyTable, args )
	path = string.format( "collections/%i", args.collection_id )
	args.collection_id = nil
	args._method = "delete"

	return call_rest_method( propertyTable, "POST", path, args )
end

function PxAPI.processTags( new_tags, previous_tags, web_tags )
	tags = {}
	to_remove = {}
	to_add = {}
	existing = {}
	for t in string.gfind( new_tags, "[^,]+" ) do
		t = t:match( "^%s*(.-)%s*$" )
		tags[ t ] = true
	end

	if previous_tags then
		for t in string.gfind( previous_tags, "[^,]+" ) do
			t = t:match( "^%s*(.-)%s*$" )
			if not tags[t] then
				to_remove[ #to_remove + 1 ] = t
			else
				existing[ t ] = true
			end
		end
	end

	for t in string.gfind( new_tags, "[^,]+" ) do
		t = t:match( "^%s*(.-)%s*$" )
		if not existing[ t ] then
			to_add[ #to_add + 1 ] = t
		end
	end

	return { to_add = to_add, to_remove = to_remove }
end

function PxAPI.setPhotoTags( propertyTable, args )
	path = string.format( "photos/%i/tags", args.photo_id )

	tags = PxAPI.processTags( args.tags, args.previous_tags )

	if #tags.to_remove > 0 then
		call_rest_method( propertyTable, "POST", path, { photo_id = args.photo_id, _method = "delete", tags = table.concat( tags.to_remove, "," ) } )
	end

	if #tags.to_add > 0 then
		call_rest_method( propertyTable, "POST", path, { id = args.photo_id, tags = table.concat( tags.to_add, "," ) } )
	end

	return true, nil
end

function PxAPI.login( context )
	LrHttp.get( "http://500px.com/logout" )

	-- get a request token
	local response, headers = call_it( "POST", REQUEST_TOKEN_URL, { oauth_callback = CALLBACK_URL }, math.random(99999) )
	if not response or not headers.status then
		LrErrors.throwUserError( "Could not connect to 500px.com. Please make sure you are connected to the internet and try again." )
	end

	local token = response:match( "oauth_token=([^&]+)" )
	local token_secret = response:match( "oauth_token_secret=([^&]+)" )
	if not token or not token_secret then
		if response:match("Deactivated user") then
			logger:trace( "User is banned or deactivated.")
			LrErrors.throwUserError( "Sorry, this user is inactive or banned. If you think this is a mistake — please contact us by email: help@500px.com." )
		end
		LrErrors.throwUserError( "Oops, something went wrong. Try again later.")
	end

	local url = AUTHORIZE_TOKEN_URL .. string.format( "?oauth_token=%s", token )
	LrHttp.openUrlInBrowser(url)

	local properties = LrBinding.makePropertyTable( context )
	local f = LrView.osFactory()
	local contents = f:column {
		bind_to_object = properties,
		spacing = f:control_spacing(),
		f:picture {
			value = _PLUGIN:resourceId( "login.png" )
		},
		f:static_text {
			title = "Enter the verification token provided by the website",
			place_horizontal = 0.5,
		},
		f:edit_field {
			width = 300,
			value = bind "verifier",
			place_horizontal = 0.5,
		},
	}

	PxAPI.URLCallback = function( oauth_token, oauth_verifier )
		if oauth_token == token then
			properties.verifier = oauth_verifier
			LrDialogs.stopModalWithResult(contents, "ok")
		end
	end

	local action = LrDialogs.presentModalDialog( {
		title = "Enter verification token",
		contents = contents,
		actionVerb = "Authorize"
	} )

	PxAPI.URLCallback = nil

	if action == "cancel" then return nil end

	-- get an access token_secret
	local args = {
		oauth_token = token,
		oauth_token_secret = token_secret,
		oauth_verifier = LrStringUtils.trimWhitespace(properties.verifier),
	}

	local response, headers = call_it( "POST", ACCESS_TOKEN_URL, args, math.random(99999) )

	if not response or not headers.status then
		LrErrors.throwUserError( "Could not connect to 500px.com. Please make sure you are connected to the internet and try again." )
	end

	local access_token = response:match( "oauth_token=([^&]+)" )
	local access_token_secret = response:match( "oauth_token_secret=([^&]+)" )

	if not access_token or not access_token_secret then
		if response:match("Deactivated user") then
			logger:trace( "User is banned or deactivated.")
			LrErrors.throwUserError( "Sorry, this user is inactive or banned. If you think this is a mistake — please contact us by email: help@500px.com." )
		else
			LrErrors.throwUserError( "Login failed." )
		end
	end

	return {
		oauth_token = access_token,
		oauth_token_secret = access_token_secret,
	}
end

function PxAPI.register( userInfo )
	local success, obj = call_rest_method( {}, "POST", "users", {
		username = userInfo.username,
		password = userInfo.password,
		email = userInfo.email,
	} )
	if success then
		LrHttp.get( "http://500px.com/logout" )

		-- get a request token
		local response, headers = call_it( "POST", REQUEST_TOKEN_URL, { oauth_callback = "oob" }, math.random(99999) )
		if not response or not headers.status then
			return false, { created = true }
		end

		local token = response:match( "oauth_token=([^&]+)" )
		local token_secret = response:match( "oauth_token_secret=([^&]+)" )
		if not token or not token_secret then
			return false, { created = true }
		end

		-- get an access token_secret
		local args = {
			x_auth_mode = "client_auth",
			x_auth_username = userInfo.username,
			x_auth_password = userInfo.password,
			oauth_token = token,
			oauth_token_secret = token_secret,
		}

		local response, headers = call_it( "POST", ACCESS_TOKEN_URL, args, math.random(99999) )

		if not response or not headers.status then
			return false, { created = true }
		end

		local access_token = response:match( "oauth_token=([^&]+)" )
		local access_token_secret = response:match( "oauth_token_secret=([^&]+)" )

		if not access_token or not access_token_secret then
			return false, { created = true }
		end

		return true, {
			oauth_token = access_token,
			oauth_token_secret = access_token_secret,
		}
	else
		return false, obj
	end
end
