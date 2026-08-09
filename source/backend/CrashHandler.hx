package backend;

import openfl.events.UncaughtErrorEvent;
import openfl.events.ErrorEvent;
import openfl.errors.Error;
import flixel.FlxG;
import flixel.util.FlxColor;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;
using flixel.util.FlxArrayUtil;

class CrashHandler
{
	public static final HELP_LINK:String = "https://github.com/kolocuz/FNF-PlusPlusEngine";
	
	public static function init():Void
	{
		openfl.Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(onError);
		#elseif hl
		hl.Api.setErrorHandler(onError);
		#end
	}

	private static function onUncaughtError(e:UncaughtErrorEvent):Void
	{
		e.preventDefault();
		e.stopPropagation();
		e.stopImmediatePropagation();

		var m:String = e.error;
		if (Std.isOfType(e.error, Error))
		{
			var err = cast(e.error, Error);
			m = '${err.message}';
		}
		else if (Std.isOfType(e.error, ErrorEvent))
		{
			var err = cast(e.error, ErrorEvent);
			m = '${err.text}';
		}
		
		var stack = haxe.CallStack.exceptionStack();
		var stackLabelArr:Array<String> = [];
		for (e in stack)
		{
			switch (e)
			{
				case CFunction:
					stackLabelArr.push("Non-Haxe (C) Function");
				case Module(c):
					stackLabelArr.push('Module ${c}');
				case FilePos(parent, file, line, col):
					switch (parent)
					{
						case Method(cla, func):
							stackLabelArr.push('${file.replace('.hx', '')}.$func() [line $line]');
						case _:
							stackLabelArr.push('${file.replace('.hx', '')} [line $line]');
					}
				case LocalFunction(v):
					stackLabelArr.push('Local Function ${v}');
				case Method(cl, m):
					stackLabelArr.push('${cl} - ${m}');
			}
		}
		var stackLabel = stackLabelArr.join('\n');
		
		trace('\n========== ERROR ==========');
		trace(m);
		trace(stackLabel);
		trace('============================');
		
		#if sys
		saveErrorMessage('$m\n\n$stackLabel');
		#end
		
		var shortError = m;
		if (shortError.length > 300) shortError = shortError.substr(0, 300) + '...';
		
		var popupMsg = 'ERROR!\n\n' +
		               shortError + '\n\n' +
		               'Game will continue, but something went wrong.\n' +
		               'Check console for details.\n\n' +
		               'Help: $HELP_LINK';
		
		CoolUtil.showPopUp(popupMsg, "Error");
		
		if (PlayState.instance != null)
		{
			PlayState.instance.addTextToDebug('ERROR: $m', FlxColor.RED);
		}
	}

	#if (cpp || hl)
	private static function onError(message:Dynamic):Void
	{
		final log:Array<String> = [];

		if (message != null && message.length > 0)
		{
			log.push(Std.string(message));
		}

		log.push(haxe.CallStack.toString(haxe.CallStack.exceptionStack(true)));
		
		var errorLog = log.join('\n');
		
		trace('\n========== CRITICAL ERROR ==========');
		trace(errorLog);
		trace('======================================');
		
		#if sys
		saveErrorMessage(errorLog);
		#end
		
		var shortError = Std.string(message);
		if (shortError.length > 300) shortError = shortError.substr(0, 300) + '...';
		
		var popupMsg = 'CRITICAL ERROR!\n\n' +
		               shortError + '\n\n' +
		               'Game will try to continue.\n' +
		               'Check console for details.\n\n' +
		               'Help: $HELP_LINK';
		
		CoolUtil.showPopUp(popupMsg, "Critical Error");
	}
	#end

	#if sys
	private static function saveErrorMessage(message:String):Void
	{
		final folder:String = #if android StorageUtil.getLogsDirectory() #else Sys.getCwd() + 'logs/' #end;

		try
		{
			if (!FileSystem.exists(folder))
				FileSystem.createDirectory(folder);

			var date = Date.now().toString().replace(' ', '-').replace(':', "'");
			var fullLog = message + '\n\n========================\nFor help, visit: $HELP_LINK\n========================';
			File.saveContent(folder + date + '.txt', fullLog);
		}
		catch (e:haxe.Exception)
			trace('Couldn\'t save error message. (${e.message})');
	}
	#end
}
