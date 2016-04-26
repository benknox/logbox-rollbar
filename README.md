# Rollbar Log Appender for LogBox

A custom logging appender for integration with Rollbar ( https://rollbar.com/ ).  


Installation:
-------------

To install, either download and unzip or, from CommandBox, simply run `box install logbox-rollbar` ( by default, it will install in your CommandBox `cwd` ) and add a new appender to your `logBox.appenders` struct in your Coldbox config:

```
rollbar = {
	class="model.extensions.RollbarAppender"
	,levelMin = 'FATAL'
	,levelMax = 'ERROR'
	,properties = {
		ServerSideToken:[ The server-side token issued for your account by Rollbar ]
	}
}
```


Getting Involved
----------------

Fork -- Commit -- Request a pull, contributions are welcome. Feel free to add issues or feature suggestions as they arise in your development.


