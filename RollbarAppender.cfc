component extends="coldbox.system.logging.AbstractAppender" accessors=true{
	property name="ServerSideToken";
	property name="APIBaseURL" default="https://api.rollbar.com/api/1/item/";
	property name="AppenderVersion" default="1.0.0";
	property name="asyncHTTPRequest" default=true hint="Make the http request in an async thread. This is serperate from LogBox's built in async property";
	// Encryption Settings
	property name="secretKey" default="" hint="If this property is provided, then all form and body data will be encrypted";
	property name="encryptAlgorithm" default="CFMX_COMPAT";
	property name="encryptFunction" hint="A closure that replaces the default encryption method. It receives one argument 'string' which is the value to be encrypted";
	// Payload data
	property name="code_version";
	property name="platform";
	property name="framework";

	public function init(
		required string name="RollbarAppender",
		struct properties={},
		string layout="",
		levelMin=0,
		levelMax=4 
	){
		structAppend( VARIABLES, ARGUMENTS.properties, true );

		// We don't want both a secret key and a custom encrypt function
		if ( len(variables.secretKey) && ( structKeyExists(variables, "encryptFunction") && isClosure(variables.encryptFunction) ) )
			throw("Please provide either a 'secretKey' or an 'encryptFunction' in the properties, not both.");

		// Do encryption?
		variables.doEncryption = len(variables.secretKey) || ( structKeyExists(variables, "encryptFunction") && isClosure(variables.encryptFunction) ) > 0 ? true : false;

		// Map logbox error levels to rollbar error levels
		variables.rbErrorLevels = {
			"0" : "critical",
			"1" : "error",
			"2" : "warning",
			"3" : "info",
			"4" : "debug"
		};

		return super.init( argumentCollection=arguments );
	}

	public void function logMessage( required coldbox.system.logging.LogEvent logEvent ){
		var extraInfo = ARGUMENTS.logEvent.getExtraInfo();

		if( isStruct( extraInfo ) && structKeyExists( extraInfo, "StackTrace" ) ){
			var logBody = ExceptionToLogBody( logEvent );
		} else {
			var logBody = MessageToLogBody( logEvent );
		}

		var threadStatus = sendToRollbar( logBody, ARGUMENTS.logEvent.getSeverity() );
	}

	public function sendToRollbar( 
		required struct logBody,
		required string logLevel="error"

	){
		var threadName = "Rollbar-" & ARGUMENTS.logLevel & '-' & createUUID();

		var payload = {
		  "access_token": getServerSideToken(),
		  "data": {
		  	// Try to map the log level to a rollbar log level. Just pass the argument if no match is found
		  	"level" : variables.rbErrorLevels[ arguments.logLevel ] ?: arguments.logLevel,
		 	"context":arrayToList( listToArray( CGI.PATH_INFO, '/' ), '.' ),
		    "environment": application.wirebox.getColdbox().getSetting("environment"),
		    "body": arguments.logBody,
		    "platform": "#server.os.name# #server.os.version#",
		    "language": this.getLanguage(),
		    "notifier": {
		      "name": "ColdBox RollbarAppender",
		      "version": getAppenderVersion()
		    }
		  }
		}

		// code_version?
		if ( structKeyExists(variables, "code_version") && len(variables.code_version) ){
			payload.data.code_version = getCode_Version();
		}

		// framework?
		if ( structKeyExists(variables, "framework") && len( trim(variables.framework) ) ){
			payload.data.framework = getFramework();
		}

		var APIBaseURL = getAPIBaseURL();

		// Send the payload
		if ( variables.asyncHTTPRequest )
			return this.runAsync(threadName, APIBaseURL, payload);
		else
			return this.sendPayload(APIBaseURL, payload);
	}

	public function sendPayload(required string url, required struct payload){
		var h = new Http(url=APIBaseURL,method="POST");
		h.addParam(type="BODY",value=serializeJSON(payload));
		return h.send().getPrefix();
	}

	public function runAsync(required string threadName, required string url, required struct payload){
		thread name="#arguments.threadName#" action="run"
			payload=payload
			APIBaseURL=getAPIBaseURL()
		{
			thread.response = this.sendPayload(url=attributes.APIBaseURL, payload=attributes.payload);
		}

		return cfthread[ threadName ];
	}

	public function ExceptionToLogBody( required coldbox.system.logging.LogEvent logEvent ){
		var exception = arguments.logEvent.getExtraInfo();
		var objRequest = GetPageContext().GetRequest();
		var requestBody = structKeyExists(request,"_body") ? request._body : getHttpRequestData().content;
		
		var logBody = {
	        "request": {
		      "url": objRequest.GetRequestUrl().Append( "?" & objRequest.GetQueryString() ).ToString(),
		      // method: the request method
		      "method": getHttpRequestData().method,

		      // headers: object containing the request headers.
		      "headers": getHttpRequestData().headers,

		      // GET: query string params
		      "GET": URL,

		      // query_string: the raw query string
		      "query_string": CGI.QUERY_STRING,

		      // POST: POST params
		      "POST": FORM,

		      // body: the raw POST body
		      "body": requestBody,

		      "user_ip": CGI.REMOTE_ADDR

		    },
	        // Option 1: "trace"
			"trace": marshallStackTrace( exception )

		};

		// do encryption?
		if ( variables.doEncryption ){
			logBody.request.post = this.encryptData( logBody.request.post );
			logBody.request.body = this.encryptData( logBody.request.body );
		}

		if( isUserLoggedIn() ){
			logBody[ "person" ]={
		      "id": getAuthUser()
		    };
		}

		return logBody;
	}

	public function messageToLogBody( required coldbox.system.logging.LogEvent logEvent ){
		
		var objRequest = GetPageContext().GetRequest();

		var logBody = {
			"message" : {
				"body":ARGUMENTS.logEvent.getMessage(),
				"extraInfo" : ARGUMENTS.logEvent.getExtraInfo(),
				"route": objRequest.GetRequestUrl().Append( "?" & objRequest.GetQueryString() ).ToString()
			}
		}

		return logBody;
	}

	private function encryptData(required any data){
		if ( isStruct(arguments.data) )
			arguments.data = serializeJSON(arguments.data);

		if ( !isSimpleValue(arguments.data) )
			throw(message="Bad data type.", detail="The value of the 'data' argument could not be serialized into a simple type.");

		// Custom encrypt function?
		if ( structKeyExists(variables, "encryptFunction") && isClosure(variables.encryptFunction) )
			return toBase64( variables.encryptFunction( string=arguments.data ) );
		else
			return toBase64( encrypt( string=arguments.data, key=this.getSecretKey(), algorithm=this.getEncryptAlgorithm() ) );
	}

	private function marshallStackTrace( required Exception ){

		var formatFrame = function( required stackItem ){
			var frameData = {
				    "filename": ARGUMENTS.stackItem.template,
				    "lineno": ARGUMENTS.stackItem.line,
				    "colno": ARGUMENTS.stackItem.column,
					"method": ARGUMENTS.stackItem.Raw_Trace,

				    // Optional: code
				    // The line of code
				    "code": ARGUMENTS.stackItem.codePrintPlain
				  }
			return frameData;
		}

		var trace = {
				"exception": {
		          "class": ARGUMENTS.Exception.Type,
		          "message": ARGUMENTS.Exception.Message,
		          "description": ARGUMENTS.Exception.Detail
		        },
				"frames": []
		};

		for( var stackItem in ARGUMENTS.Exception.TagContext ){
			arrayAppend( trace.frames, formatFrame( stackItem ) )
		}

		return trace;
		
	}

	private function getlanguage(){
		if ( server.coldfusion.productname == "Lucee" )
			return server.coldfusion.productname & " " & server.lucee.version;
		else
			return server.coldfusion.productname & " " & server.coldfusion.productVersion;
	}

	private function getRollbarInfoProperties(){
		var defaults = {
			"language":"CFML",
			"framework":"Coldbox",
		}
	}
}