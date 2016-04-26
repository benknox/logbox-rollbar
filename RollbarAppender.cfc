component extends="coldbox.system.logging.AbstractAppender" accessors=true{
	property name="ServerSideToken";
	property name="APIBaseURL" default="https://api.rollbar.com/api/1/item/";
	property name="AppenderVersion" default="1.0.0";

	public function init(
		required string name="RollbarAppender",
		struct properties={},
		string layout="",
		levelMin=0,
		levelMax=4 
	){
		structAppend( VARIABLES, ARGUMENTS.properties, true );
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
		 	"context":arrayToList( listToArray( CGI.PATH_INFO, '/' ), '.' ),
		    "environment": application.wirebox.getColdbox().getSetting("environment"),
		    "body": arguments.logBody,
		    "notifier": {
		      "name": "ColdBox RollbarAppender",
		      "version": getAppenderVersion()
		    }
		  }
		}

		var APIBaseURL = getAPIBaseURL();
		
		thread name="#threadName#" action="run"
			payload=payload
			APIBaseURL=getAPIBaseURL()
		{
			var h = new Http(url=APIBaseURL,method="POST");
			h.addParam(type="BODY",value=serializeJSON(payload));
			thread.response = h.send().getPrefix();
		}


		return cfthread[ threadName ];

		
	}

	public function ExceptionToLogBody( required coldbox.system.logging.LogEvent logEvent ){
		var exception = arguments.logEvent.getExtraInfo();
		var objRequest = GetPageContext().GetRequest();
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
		      "body": getHttpRequestData().content,

		      "user_ip": CGI.REMOTE_ADDR

		    },
	        // Option 1: "trace"
			"trace": marshallStackTrace( exception )

		};

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

	private function getRollbarInfoProperties(){
		var defaults = {
			"language":"CFML",
			"framework":"Coldbox",
		}
	}
}