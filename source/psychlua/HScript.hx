package psychlua;

import objects.Character;
import backend.StructurePsychOld;
import psychlua.LuaUtils;
import psychlua.CustomSubstate;
import psychlua.ReflectionFunctions;
import psychlua.ModchartSprite;
import psychlua.DebugLuaText;
import objects.StrumNote;
import objects.NoteSplash;
#if LUA_ALLOWED
import psychlua.FunkinLua;
#end

#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import crowplexus.iris.IrisConfig;
import crowplexus.hscript.Expr.Error as IrisError;
import crowplexus.hscript.Printer;
import crowplexus.hscript.Tools;
import crowplexus.iris.utils.UsingEntry;

import haxe.ValueException;
import openfl.utils.Assets as OpenFlAssets;

typedef HScriptInfos = {
	> haxe.PosInfos,
	var ?funcName:String;
	var ?showLine:Null<Bool>;
	#if LUA_ALLOWED
	var ?isLua:Null<Bool>;
	#end
}

class HScript extends Iris
{
	public var filePath:String;
	public var modFolder:String;
	public var returnValue:Dynamic;
	public var scriptName:String = '';

	#if LUA_ALLOWED
	public var parentLua:FunkinLua;
	public static function initHaxeModule(parent:FunkinLua)
	{
		if(parent.hscript == null)
		{
			trace('HScript (Psych 1.0.x) initializing for: ${parent.scriptName}');
			parent.hscript = new HScript(parent);
		}
	}

	public static function initHaxeModuleCode(parent:FunkinLua, code:String, ?varsToBring:Any = null)
	{	
		var hs:HScript = try parent.hscript catch (e) null;
		if(hs == null)
		{
			trace('HScript (Psych 1.0.x) initializing for: ${parent.scriptName}');
			try {
				parent.hscript = new HScript(parent, code, varsToBring);
			}
			catch(e:IrisError) {
				var pos:HScriptInfos = cast {fileName: parent.scriptName, isLua: true};
				if(parent.lastCalledFunction != '') pos.funcName = parent.lastCalledFunction;
				Iris.error(Printer.errorToString(e, false), pos);
				parent.hscript = null;
			}
		}
		else
		{
			try
			{
				hs.scriptCode = code;
				hs.varsToBring = varsToBring;
				hs.parse(true);
				var ret:Dynamic = hs.execute();
				hs.returnValue = ret;
			}
			catch(e:IrisError)
			{
				var pos:HScriptInfos = cast hs.interp.posInfos();
				pos.isLua = true;
				if(parent.lastCalledFunction != '') pos.funcName = parent.lastCalledFunction;
				Iris.error(Printer.errorToString(e, false), pos);
				hs.returnValue = null;
			}
		}
	}
	#end

	public var origin:String;
	
	static var __irisConfigured:Bool = {
		Iris.blocklistImports = [];
		Iris.proxyImports.set("flixel.Math.FlxPoint", CustomFlxPoint);
		Iris.proxyImports.set("flash.filters.ShaderFilter", flash.filters.ShaderFilter);
		true;
	};
	
	override public function new(?parent:Dynamic, ?file:String, ?varsToBring:Any = null, ?manualRun:Bool = false)
	{
		if (file == null)
			file = '';

		filePath = file;
		if (filePath != null && filePath.length > 0)
		{
			this.origin = filePath;
			#if MODS_ALLOWED
			var normalizedFilePath:String = filePath.replace('\\', '/');
			var resolvedModName:String = Paths.getModFolderNameFromPath(normalizedFilePath);
			if(resolvedModName != null) {
				if(Mods.currentModDirectory == resolvedModName || Mods.getGlobalMods().contains(resolvedModName))
					this.modFolder = resolvedModName;
			} else {
				var myFolder:Array<String> = normalizedFilePath.split('/');
				if(myFolder[0] + '/' == 'mods/' && (Mods.currentModDirectory == myFolder[1] || Mods.getGlobalMods().contains(myFolder[1])))
					this.modFolder = myFolder[1];
			}
			#end
		}
		var scriptThing:String = file;
		var scriptName:String = null;
		if(parent == null && file != null)
		{
			var f:String = file.replace('\\', '/');
			if(f.contains('/') && !f.contains('\n')) {
				#if sys
				if (sys.FileSystem.exists(f))
					scriptThing = File.getContent(f);
				else
				#end
				if (OpenFlAssets.exists(f))
					scriptThing = OpenFlAssets.getText(f);
				scriptName = f;
			}
		}
		#if LUA_ALLOWED
		if (scriptName == null && parent != null)
			scriptName = parent.scriptName;
		#end
		super(scriptThing, new IrisConfig(scriptName, false, false));
		var customInterp:CustomInterp = new CustomInterp();
		customInterp.parentInstance = FlxG.state;
		customInterp.scriptName = scriptName != null ? scriptName : "Unknown";
		customInterp.showPosOnLog = false;
		this.interp = customInterp;
		#if LUA_ALLOWED
		parentLua = parent;
		if (parent != null)
		{
			this.origin = parent.scriptName;
			this.modFolder = parent.modFolder;
		}
		#end
		preset();
		this.varsToBring = varsToBring;
		if (!manualRun) {
			try {
				var ret:Dynamic = execute();
				returnValue = ret;
			} catch(e:IrisError) {
				returnValue = null;
				if(PlayState.instance != null) {
					var errorMsg = Printer.errorToString(e, false);
					PlayState.instance.addTextToDebug(errorMsg, FlxColor.RED);
				}
				throw e;
			}
			catch(e:Dynamic) {
				returnValue = null;
				if(PlayState.instance != null) {
					PlayState.instance.addTextToDebug('WARNING: $e', FlxColor.YELLOW);
				}
				throw e;
			}
		}
	}

	var varsToBring(default, set):Any = null;
	
	override public function set(key:String, value:Dynamic, allowOverride:Bool = true):Void {
		if (value == null && key.contains('.')) {
			var resolvedClass = StructurePsychOld.resolveClass(key);
			if (resolvedClass != null) {
				super.set(key, resolvedClass, allowOverride);
				return;
			}
			return;
		}
		
		if (key.contains('.') && Std.isOfType(value, Class)) {
			var resolvedClass = StructurePsychOld.resolveClass(key);
			if (resolvedClass != null && resolvedClass != value) {
				super.set(key, resolvedClass, allowOverride);
				return;
			}
		}
		
		super.set(key, value, allowOverride);
	}
	
	override function preset() {
		super.preset();

		set('Type', Type);
		#if sys
		set('File', File);
		set('FileSystem', FileSystem);
		set('Sys', Sys);
		#end
		set('FlxG', CustomFlxG);
		set('FlxMath', CustomFlxMath);
		set('FlxSprite', flixel.FlxSprite);
		set('FlxText', flixel.text.FlxText);
		set('FlxCamera', flixel.FlxCamera);
		set('PsychCamera', backend.PsychCamera);
		set('FlxTimer', flixel.util.FlxTimer);
		set('FlxTween', flixel.tweens.FlxTween);
		set('FlxEase', flixel.tweens.FlxEase);
		set('FlxColor', CustomFlxColor);
		set('Countdown', backend.BaseStage.Countdown);
		set('PlayState', PlayState);
		set('Paths', Paths);
		set('StorageUtil', mobile.backend.StorageUtil);
		set('Conductor', Conductor);
		set('ClientPrefs', ClientPrefs);
		#if ACHIEVEMENTS_ALLOWED
		set('Achievements', backend.Achievements);
		#end
		set('Character', objects.Character);
		set('Alphabet', objects.Alphabet);
		set('Note', objects.Note);
		set('CustomSubstate', CustomSubstate);
		#if (!flash && sys)
		set('FlxRuntimeShader', flixel.addons.display.FlxRuntimeShader);
		set('ErrorHandledRuntimeShader', shaders.ErrorHandledShader.ErrorHandledRuntimeShader);
		#end
		set('ShaderFilter', flash.filters.ShaderFilter);
		set('StringTools', StringTools);
		#if flxanimate
		set('FlxAnimate', FlxAnimate);
		#end

		set('Reflect', Reflect);
		set('Lambda', Lambda);
		set('Json', haxe.Json);
		set('TJSON', tjson.TJSON);
		set('Array', Array);
		set('EReg', EReg);
		set('IntMap', haxe.ds.IntMap);
		set('Map', haxe.ds.StringMap);
		set('StringMap', haxe.ds.StringMap);
		set('ObjectMap', haxe.ds.ObjectMap);
		set('FlxSave', flixel.util.FlxSave);
		set('FlxSpriteUtil', flixel.util.FlxSpriteUtil);
		set('FlxTextAlign', CustomFlxTextAlign);
		set('FlxTextBorderStyle', CustomFlxTextBorderStyle);
		set('FlxSound', flixel.sound.FlxSound);
		set('FlxFlicker', flixel.effects.FlxFlicker);
		set('FlxAxes', CustomFlxAxes);
		set('FlxSpriteGroup', flixel.group.FlxSpriteGroup);
		set('FlxTypedGroup', flixel.group.FlxTypedGroup);
		set('FlxGroup', flixel.group.FlxGroup);
		set('FlxPoint', CustomFlxPoint);
		set('FlxKey', flixel.input.keyboard.FlxKey.fromStringMap);
		set('FlxGamepadInputID', CustomFlxGamepadInputID);
		set('Capabilities', openfl.system.Capabilities);
		set('RatioScaleMode', flixel.system.scaleModes.RatioScaleMode);
		set('Lib', openfl.Lib);
		#if windows
		set('WindowTweens', psychlua.WindowTweens);
		#end
		set('TouchScroll', mobile.backend.TouchScroll);
		set('TouchUtil', mobile.backend.TouchUtil);
		set('MobileControlSelectSubState', mobile.substates.MobileControlSelectSubState);
		set('MobileSettingsSubState', mobile.options.MobileSettingsSubState);
		set('MobileScaleMode', mobile.backend.MobileScaleMode);
		set('StorageUtil', mobile.backend.StorageUtil);
		#if mobile
		set('__isMobile', true);
		#else
		set('__isMobile', false);
		#end
		#if windows
		set('__isWindows', true);
		#else
		set('__isWindows', false);
		#end
		#if linux
		set('__isLinux', true);
		#else
		set('__isLinux', false);
		#end
		#if mac
		set('__isMac', true);
		#else
		set('__isMac', false);
		#end
		#if android
		set('__isAndroid', true);
		#else
		set('__isAndroid', false);
		#end
		#if ios
		set('__isIOS', true);
		#else
		set('__isIOS', false);
		#end
		#if html5
		set('__isHTML5', true);
		#else
		set('__isHTML5', false);
		#end
		#if desktop
		set('__isDesktop', true);
		#else
		set('__isDesktop', false);
		#end
		set('Alphabet', objects.Alphabet);
		set('Countdown', backend.BaseStage.Countdown);
		set('HealthIcon', objects.HealthIcon);
		set('Language', backend.Language);
		set('Difficulty', backend.Difficulty);
		set('WeekData', backend.WeekData);
		#if DISCORD_ALLOWED
		set('Discord', backend.Discord.DiscordClient);
		#end
		set('CustomState', psychlua.CustomState);
		set('ScriptableState', backend.ScriptableState);
		set('ScriptableSubstate', backend.ScriptableSubstate);
		set('PlayState', PlayState);
		set('TitleState', states.TitleState);
		set('MainMenuState', states.MainMenuState);
		set('GameOverSubstate', substates.GameOverSubstate);
		set('FreeplayState', states.FreeplayState);
		set('FreeplayState_Psych', states.FreeplayState_Psych);
		set('StoryMenuState', states.StoryMenuState);
		set('LoadingState', states.LoadingState);
		set('CreditsState', states.CreditsState);
		set('AchievementsMenuState', states.AchievementsMenuState);
		set('MasterEditorMenu', states.editors.MasterEditorMenu);
		set('FlashingState', states.FlashingState);
		set('OptionsState', options.OptionsState);
		set('ResultsState', states.ResultsState);
		set('AttachedSprite', objects.AttachedSprite);
		set('MenuItem', objects.MenuItem);
		set('MenuCharacter', objects.MenuCharacter);
		set('FlxTransitionableState', flixel.addons.transition.FlxTransitionableState);
		set('MusicBeatState', MusicBeatState);
		set('PauseSubState', substates.PauseSubState);
		set('GameplayChangersSubstate', options.GameplayChangersSubstate);
		set('ResetScoreSubState', substates.ResetScoreSubState);
		set('CoolUtil', backend.CoolUtil);
		set('Cursor', objects.Cursor);
		set('ColorblindFilter', shaders.ColorblindFilter);
		set('ColorSwap', shaders.ColorSwap);
		set('WindowMode', backend.WindowMode);
		set('StageData', backend.StageData);
		set('NotesColorSubState', options.NotesColorSubState);
		set('ControlsSubState', options.ControlsSubState);
		set('GraphicsSettingsSubState', options.GraphicsSettingsSubState);
		set('VisualsSettingsSubState', options.VisualsSettingsSubState);
		set('GameplaySettingsSubState', options.GameplaySettingsSubState);
		set('LegacySettingsSubState', options.LegacySettingsSubState);
		set('NoteOffsetState', options.NoteOffsetState);
		#if MODCHARTS_NOTITG_ALLOWED
		set('ModchartSettingsSubState', options.ModchartSettingsSubState);
		set('Manager', modchart.Manager);
		set('ModchartManager', modchart.Manager);
		set('PlayField', modchart.engine.PlayField);
		set('Modifier', modchart.engine.modifiers.Modifier);
		set('DynamicModifier', modchart.engine.modifiers.DynamicModifier);
		set('ScriptedModifier', modchart.engine.modifiers.ScriptedModifier);
		set('LuaModifier', modchart.engine.modifiers.LuaModifier);
		set('ModifierGroup', modchart.engine.modifiers.ModifierGroup);
		set('TransformMode_NONE', (modchart.backend.core.TransformMode.NONE : Int));
		set('TransformMode_FIELD', (modchart.backend.core.TransformMode.FIELD : Int));
		set('TransformMode_NOTE', (modchart.backend.core.TransformMode.NOTE : Int));
		set('TransformMode_RECEPTOR', (modchart.backend.core.TransformMode.RECEPTOR : Int));
		set('TransformMode_SPLASH', (modchart.backend.core.TransformMode.SPLASH : Int));
		set('TransformMode_ALL', (modchart.backend.core.TransformMode.ALL : Int));
		set('ModifierParameters', modchart.backend.core.ModifierParameters);
		set('VisualParameters', modchart.backend.core.VisualParameters);
		set('Vector3D', openfl.geom.Vector3D);
		set('Adapter', modchart.backend.standalone.Adapter);
		set('ModchartUtil', modchart.backend.util.ModchartUtil);
		set('instance', modchart.Manager.instance);
		set('manager', modchart.Manager.instance);
		set('modManager', modchart.Manager.instance);
		set('modchartManager', modchart.Manager.instance);
		#end
		#if TRANSLATIONS_ALLOWED
		set('LanguageSubState', options.LanguageSubState);
		#end
		set('Mods', backend.Mods);
		set('ModsMenuState', states.ModsMenuState);
		set('ModItem', states.ModsMenuState.ModItem);
		set('MenuButton', states.ModsMenuState.MenuButton);
		set('ModSettingsSubState', options.ModSettingsSubState);
		set('FlxObject', flixel.FlxObject);
		set('TEXT',   cast openfl.utils.AssetType.TEXT);
		set('IMAGE',  cast openfl.utils.AssetType.IMAGE);
		set('SOUND',  cast openfl.utils.AssetType.SOUND);
		set('MUSIC',  cast openfl.utils.AssetType.MUSIC);
		set('BINARY', cast openfl.utils.AssetType.BINARY);
		set('FONT',   cast openfl.utils.AssetType.FONT);
		set('X',        cast flixel.util.FlxAxes.X);
		set('Y',        cast flixel.util.FlxAxes.Y);
		set('XY',       cast flixel.util.FlxAxes.XY);
		set('LEFT',     cast flixel.text.FlxText.FlxTextAlign.LEFT);
		set('RIGHT',    cast flixel.text.FlxText.FlxTextAlign.RIGHT);
		set('CENTER',   cast flixel.text.FlxText.FlxTextAlign.CENTER);
		set('JUSTIFY',  cast flixel.text.FlxText.FlxTextAlign.JUSTIFY);
		set('CENTERED', objects.Alphabet.Alignment.CENTERED);
		set('Alignment', CustomAlignment);
		set('Paths', Paths);
		set('Conductor', Conductor);
		set('ClientPrefs', ClientPrefs);
		set('Highscore', backend.Highscore);
		set('Song', backend.Song);
		#if ACHIEVEMENTS_ALLOWED
		set('Achievements', backend.Achievements);
		#end
		set('Character', objects.Character);
		set('Alphabet', Alphabet);
		set('Note', objects.Note);
		set('CustomSubstate', CustomSubstate);
		set('LuaUtils', LuaUtils);
		
		#if (!flash && sys)
		set('FlxRuntimeShader', flixel.addons.display.FlxRuntimeShader);
		set('ErrorHandledRuntimeShader', shaders.ErrorHandledShader.ErrorHandledRuntimeShader);
		#end
		set('ShaderFilter', flash.filters.ShaderFilter);
		set('flash.filters.ShaderFilter', flash.filters.ShaderFilter);
		set('RGBPalette', shaders.RGBPalette);
		set('WiggleEffect', shaders.WiggleEffect);
		set('shaders.RGBPalette', shaders.RGBPalette);
		set('BGSprite', objects.BGSprite);
		set('StringTools', StringTools);
		#if flxanimate
		set('FlxAnimate', FlxAnimate);
		#end
		#if (hxvlc)
		set('VideoSprite', objects.VideoSprite);
		set('FlxVideoSprite', hxvlc.flixel.FlxVideoSprite);
		set('FlxVideo', hxvlc.flixel.FlxVideo);
		set('VideoHandler', objects.hxcodec.v2_6_0.VideoHandler);
		set('MP4Handler', objects.hxcodec.v2_5_0.MP4Handler);
		set('MP4Sprite', objects.hxcodec.v2_5_0.MP4Sprite);
		set('hxcodec.flixel.FlxVideo', objects.hxcodec.v3_0_0.FlxVideo);
		set('hxcodec.flixel.FlxVideoSprite', objects.hxcodec.v3_0_0.FlxVideoSprite);
		set('hxcodec.flixel.Video', objects.hxcodec.v3_0_0.Video);
		set('hxcodec.VideoHandler', objects.hxcodec.v2_6_0.VideoHandler);
		set('hxcodec.MP4Handler', objects.hxcodec.v2_5_0.MP4Handler);
		set('hxcodec.MP4Sprite', objects.hxcodec.v2_5_0.MP4Sprite);
		set('hxcodec', {
			flixel: {
				FlxVideo: objects.hxcodec.v3_0_0.FlxVideo,
				FlxVideoSprite: objects.hxcodec.v3_0_0.FlxVideoSprite
			},
			VideoHandler: objects.hxcodec.v2_6_0.VideoHandler,
			VideoSprite: objects.hxcodec.v2_6_0.VideoSprite
		});
		#end

		set('this', this);
		set('game', FlxG.state);
		set('state', FlxG.state);
		set('controls', Controls.instance);
		#if LUA_ALLOWED
		set('parentLua', parentLua);
		set('modchartTweens', PlayState.instance != null ? PlayState.instance.modchartTweens : null);
		set('modchartSprites', PlayState.instance != null ? PlayState.instance.modchartSprites : null);
		set('modchartTexts', PlayState.instance != null ? PlayState.instance.modchartTexts : null);
		#else
		set('parentLua', null);
		set('modchartTweens', null);
		set('modchartSprites', null);
		set('modchartTexts', null);
		#end
		set('customSubstate', CustomSubstate.instance);
		set('customSubstateName', CustomSubstate.name);
		set('buildTarget', LuaUtils.getBuildTarget());

		set('Function_Stop', LuaUtils.Function_Stop);
		set('Function_Continue', LuaUtils.Function_Continue);
		set('Function_StopLua', LuaUtils.Function_StopLua);
		set('Function_StopHScript', LuaUtils.Function_StopHScript);
		set('Function_StopAll', LuaUtils.Function_StopAll);

		set('setVar', function(name:String, value:Dynamic) {
			MusicBeatState.getVariables().set(name, value);
			return value;
		});
		set('getVar', function(name:String) {
			var result:Dynamic = null;
			
			if(exists(name)) {
				result = get(name);
			}
			else if(MusicBeatState.getVariables().exists(name))
				result = MusicBeatState.getVariables().get(name);
			return result;
		});
		set('removeVar', function(name:String)
		{
			var removed = false;
			if(MusicBeatState.getVariables().exists(name))
			{
				MusicBeatState.getVariables().remove(name);
				removed = true;
				trace('HScript: Removed variable: $name');
			}
			return removed;
		});
		set('debugPrint', function(text:String, ?color:FlxColor = null) {
			if(color == null) color = FlxColor.WHITE;
			PlayState.instance.addTextToDebug(text, color);
		});
		set('getModSetting', function(saveTag:String, ?modName:String = null) {
			if(modName == null)
			{
				if(this.modFolder == null)
				{
					Iris.error('getModSetting: Argument #2 is null and script is not inside a packed Mod folder!', this.interp.posInfos());
					return null;
				}
				modName = this.modFolder;
			}
			return LuaUtils.getModSetting(saveTag, modName);
		});

		set('keyboardJustPressed', function(name:String) return Reflect.getProperty(FlxG.keys.justPressed, name));
		set('keyboardPressed', function(name:String) return Reflect.getProperty(FlxG.keys.pressed, name));
		set('keyboardReleased', function(name:String) return Reflect.getProperty(FlxG.keys.justReleased, name));

		set('anyGamepadJustPressed', function(name:String) return FlxG.gamepads.anyJustPressed(name));
		set('anyGamepadPressed', function(name:String) FlxG.gamepads.anyPressed(name));
		set('anyGamepadReleased', function(name:String) return FlxG.gamepads.anyJustReleased(name));

		set('gamepadAnalogX', function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;

			return controller.getXAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		set('gamepadAnalogY', function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;

			return controller.getYAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		set('gamepadJustPressed', function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.justPressed, name) == true;
		});
		set('gamepadPressed', function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.pressed, name) == true;
		});
		set('gamepadReleased', function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.justReleased, name) == true;
		});

		set('keyJustPressed', function(name:String = '') {
			name = name.toLowerCase();
			switch(name) {
				case 'left': return Controls.instance.NOTE_LEFT_P;
				case 'down': return Controls.instance.NOTE_DOWN_P;
				case 'up': return Controls.instance.NOTE_UP_P;
				case 'right': return Controls.instance.NOTE_RIGHT_P;
				default: return Controls.instance.justPressed(name);
			}
			return false;
		});
		set('keyPressed', function(name:String = '') {
			name = name.toLowerCase();
			switch(name) {
				case 'left': return Controls.instance.NOTE_LEFT;
				case 'down': return Controls.instance.NOTE_DOWN;
				case 'up': return Controls.instance.NOTE_UP;
				case 'right': return Controls.instance.NOTE_RIGHT;
				default: return Controls.instance.pressed(name);
			}
			return false;
		});
		set('keyReleased', function(name:String = '') {
			name = name.toLowerCase();
			switch(name) {
				case 'left': return Controls.instance.NOTE_LEFT_R;
				case 'down': return Controls.instance.NOTE_DOWN_R;
				case 'up': return Controls.instance.NOTE_UP_R;
				case 'right': return Controls.instance.NOTE_RIGHT_R;
				default: return Controls.instance.justReleased(name);
			}
			return false;
		});

		#if LUA_ALLOWED
		set('createGlobalCallback', function(name:String, func:Dynamic)
		{
			for (script in PlayState.instance.luaArray)
				if(script != null && script.lua != null && !script.closed)
					Lua_helper.add_callback(script.lua, name, func);

			FunkinLua.customFunctions.set(name, func);
		});

		set('createCallback', function(name:String, func:Dynamic, ?funk:FunkinLua = null)
		{
			if(funk == null) funk = parentLua;
			
			if(funk != null) funk.addLocalCallback(name, func);
			else Iris.error('createCallback ($name): 3rd argument is null', this.interp.posInfos());
		});

		set("addTouchPad", (DPadMode:String, ActionMode:String) -> {
			PlayState.instance.makeLuaTouchPad(DPadMode, ActionMode);
			PlayState.instance.addLuaTouchPad();
		});
  
		set("removeTouchPad", () -> {
			PlayState.instance.removeLuaTouchPad();
		});
  
		set("addTouchPadCamera", () -> {
			if(PlayState.instance.luaTouchPad == null){
				FunkinLua.luaTrace('addTouchPadCamera: TPAD does not exist.');
				return;
			}
			PlayState.instance.addLuaTouchPadCamera();
		});
  
		set("touchPadJustPressed", function(button:Dynamic):Bool {
			if(PlayState.instance.luaTouchPad == null){
				return false;
			}
			return PlayState.instance.luaTouchPadJustPressed(button);
		});
  
		set("touchPadPressed", function(button:Dynamic):Bool {
			if(PlayState.instance.luaTouchPad == null){
				return false;
			}
			return PlayState.instance.luaTouchPadPressed(button);
		});
  
		set("touchPadJustReleased", function(button:Dynamic):Bool {
			if(PlayState.instance.luaTouchPad == null){
				return false;
			}
			return PlayState.instance.luaTouchPadJustReleased(button);
		});
		#end

		set('addHaxeLibrary', function(libName:String, ?libPackage:String = '') {
			try {
				var str:String = '';
				if(libPackage.length > 0)
					str = libPackage + '.';
		
				var className = str + libName;
				var resolvedClass = StructurePsychOld.resolveClass(className);
				set(libName, resolvedClass);
			}
			catch (e:IrisError) {
				Iris.error(Printer.errorToString(e, false), this.interp.posInfos());
			}
		});
		
		set('flixel.FlxG', CustomFlxG);
		set('flixel.FlxSprite', flixel.FlxSprite);
		set('flixel.FlxCamera', flixel.FlxCamera);
		set('flixel.FlxObject', flixel.FlxObject);
		set('flixel.FlxState', flixel.FlxState);
		set('flixel.FlxSubState', flixel.FlxSubState);
		set('flixel.FlxBasic', flixel.FlxBasic);
		set('flixel.FlxGame', flixel.FlxGame);
		
		set('flixel.math.FlxMath', CustomFlxMath);
		set('flixel.math.FlxPoint', CustomFlxPoint);
		
		set('flixel.text.FlxText', flixel.text.FlxText);
		set('flixel.text.FlxText.FlxTextAlign', CustomFlxTextAlign);
		set('flixel.text.FlxTextAlign', CustomFlxTextAlign);
		set('flixel.text.FlxTextBorderStyle', CustomFlxTextBorderStyle);
		
		set('flixel.group.FlxGroup', flixel.group.FlxGroup);
		
		set('flixel.util.FlxColor', CustomFlxColor);
		set('flixel.util.FlxAxes', CustomFlxAxes);
		set('flixel.util.FlxPoint', CustomFlxPoint);
		set('flixel.util.FlxTimer', flixel.util.FlxTimer);
		set('flixel.util.FlxTween', flixel.tweens.FlxTween);
		set('flixel.util.FlxEase', flixel.tweens.FlxEase);
		set('flixel.util.FlxSave', flixel.util.FlxSave);
		set('flixel.util.FlxSpriteUtil', flixel.util.FlxSpriteUtil);
		set('flixel.util.FlxStringUtil', flixel.util.FlxStringUtil);
		set('flixel.util.FlxArrayUtil', flixel.util.FlxArrayUtil);
		
		set('flixel.tweens.FlxTween', flixel.tweens.FlxTween);
		set('flixel.tweens.FlxEase', flixel.tweens.FlxEase);
		
		set('flixel.effects.FlxFlicker', flixel.effects.FlxFlicker);
		
		set('flixel.input.FlxInput', flixel.input.FlxInput);
		set('flixel.input.FlxKey', flixel.input.keyboard.FlxKey.fromStringMap);
		set('flixel.input.keyboard.FlxKey', flixel.input.keyboard.FlxKey.fromStringMap);
		set('flixel.input.gamepad.FlxGamepadInputID', CustomFlxGamepadInputID);
		
		set('flixel.system.scaleModes.RatioScaleMode', flixel.system.scaleModes.RatioScaleMode);
		
		set('flixel.addons.transition.FlxTransitionableState', flixel.addons.transition.FlxTransitionableState);
		
		set('openfl.display.BitmapData', openfl.display.BitmapData);
		set('openfl.display.Shape', openfl.display.Shape);
		
		set('haxe.Json', haxe.Json);
		set('haxe.ds.IntMap', haxe.ds.IntMap);
		set('haxe.ds.StringMap', haxe.ds.StringMap);
		set('haxe.ds.ObjectMap', haxe.ds.ObjectMap);
		
		set('StringTools', StringTools);

set('eval', function(code:String):Dynamic {
	#if (sys && !cpp)
	try {
		var dir = Sys.getCwd();
		var timestamp = Std.string(Date.now().getTime());
		var hxFile = dir + '/eval_' + timestamp + '.hx';
		var nekoFile = dir + '/eval_' + timestamp + '.n';
		sys.io.File.saveContent(hxFile, code);
		var p = new sys.io.Process("haxe", ["-main", "Eval", "-lib", "hscript", "-neko", nekoFile, hxFile]);
		p.exitCode();
		p.close();
		var result = null;
		if (sys.FileSystem.exists(nekoFile)) {
			result = neko.Lib.load(nekoFile, "eval_" + timestamp, 0);
			sys.FileSystem.deleteFile(nekoFile);
		}
		sys.FileSystem.deleteFile(hxFile);
		return result;
	} catch(e:Dynamic) {
		return "Error: " + e;
	}
	#else
	return null;
	#end
});

set('exec', function(cmd:String, ?args:Array<String>):String {
	#if (sys && !cpp)
	try {
		var p = new sys.io.Process(cmd, args != null ? args : []);
		var out = p.stdout.readAll().toString();
		p.close();
		return out;
	} catch(e:Dynamic) {
		return "Error: " + e;
	}
	#else
	return null;
	#end
});

set('writeFile', function(path:String, content:String):Void {
	#if sys
	try {
		sys.io.File.saveContent(path, content);
	} catch(e:Dynamic) {
		trace('Error writing file: $e');
	}
	#end
});

set('listDir', function(path:String):Array<String> {
	#if sys
	try {
		if (sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path))
			return sys.FileSystem.readDirectory(path);
		return [];
	} catch(e:Dynamic) {
		return [];
	}
	#else
	return [];
	#end
});

		set('createInstance', function(className:String, args:Array<Dynamic>):Dynamic {
			var cls = Type.resolveClass(className);
			if(cls == null) {
				cls = StructurePsychOld.resolveClass(className);
			}
			if(cls != null) {
				return Type.createInstance(cls, args != null ? args : []);
			}
			return null;
		});

		set('getClass', function(className:String):Class<Dynamic> {
			var cls = Type.resolveClass(className);
			if(cls == null) {
				cls = StructurePsychOld.resolveClass(className);
			}
			return cls;
		});

		set('importClass', function(className:String):Dynamic {
			var cls = Type.resolveClass(className);
			if(cls == null) cls = StructurePsychOld.resolveClass(className);
			if(cls != null) {
				@:privateAccess this.interp.variables.set(className.split('.').pop(), cls);
				return cls;
			}
			return null;
		});

		set('importPackage', function(packageName:String):Void {
			#if sys
			var path = packageName.replace('.', '/');
			var fullPath = Paths.getSharedPath(path);
			if(sys.FileSystem.exists(fullPath)) {
				for(file in sys.FileSystem.readDirectory(fullPath)) {
					if(file.endsWith('.hx')) {
						var className = packageName + '.' + file.substr(0, file.length - 3);
						var cls = Type.resolveClass(className);
						if(cls != null) {
							@:privateAccess this.interp.variables.set(file.substr(0, file.length - 3), cls);
						}
					}
				}
			}
			#end
		});
	}

	#if LUA_ALLOWED
	public static function implement(funk:FunkinLua) {
		funk.addLocalCallback("runHaxeCode", function(codeToRun:String, ?varsToBring:Any = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
			initHaxeModuleCode(funk, codeToRun, varsToBring);
			if (funk.hscript != null)
			{
				final retVal:IrisCall = funk.hscript.call(funcToRun, funcArgs);
				if (retVal != null)
				{
					return (LuaUtils.isLuaSupported(retVal.returnValue)) ? retVal.returnValue : null;
				}
				else if (funk.hscript.returnValue != null)
				{
					return funk.hscript.returnValue;
				}
			}
			return null;
		});
		
		funk.addLocalCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null) {
			if (funk.hscript != null)
			{
				final retVal:IrisCall = funk.hscript.call(funcToRun, funcArgs);
				if (retVal != null)
				{
					return (LuaUtils.isLuaSupported(retVal.returnValue)) ? retVal.returnValue : null;
				}
			}
			else
			{
				var pos:HScriptInfos = cast {fileName: funk.scriptName, showLine: false};
				if (funk.lastCalledFunction != '') pos.funcName = funk.lastCalledFunction;
				Iris.error("runHaxeFunction: HScript has not been initialized yet! Use \"runHaxeCode\" to initialize it", pos);
			}
			return null;
		});
		funk.addLocalCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			var str:String = '';
			if (libPackage.length > 0)
				str = libPackage + '.';
			else if (libName == null)
				libName = '';

			var className = str + libName;
			var c:Dynamic = StructurePsychOld.resolveClass(className);

			if (c == null)
				c = Type.resolveEnum(className);
			

			if (funk.hscript == null)
				initHaxeModule(funk);

			var pos:HScriptInfos = cast funk.hscript.interp.posInfos();
			pos.showLine = false;
			if (funk.lastCalledFunction != '')
				 pos.funcName = funk.lastCalledFunction;

			try {
				if (c != null)
					funk.hscript.set(libName, c);
			}
			catch (e:IrisError) {
				Iris.error(Printer.errorToString(e, false), pos);
			}
			FunkinLua.lastCalledScript = funk;
			if (FunkinLua.getBool('luaDebugMode') && FunkinLua.getBool('luaDeprecatedWarnings'))
				Iris.warn("addHaxeLibrary is deprecated! Import classes through \"import\" in HScript!", pos);
		});
	}
	#end

	override function call(funcToRun:String, ?args:Array<Dynamic>):IrisCall {
		if (funcToRun == null || interp == null) return null;

		if (!exists(funcToRun)) {
			Iris.error('No function named: $funcToRun', this.interp.posInfos());
			return null;
		}

		try {
			var func:Dynamic = interp.variables.get(funcToRun);
			final ret = Reflect.callMethod(null, func, args ?? []);
			return {funName: funcToRun, signature: func, returnValue: ret};
		}
		catch(e:IrisError) {
			var pos:HScriptInfos = cast this.interp.posInfos();
			pos.funcName = funcToRun;
			#if LUA_ALLOWED
			if (parentLua != null)
			{
				pos.isLua = true;
				if (parentLua.lastCalledFunction != '') pos.funcName = parentLua.lastCalledFunction;
			}
			#end
			Iris.error(Printer.errorToString(e, false), pos);
		}
		catch (e:ValueException) {
			var pos:HScriptInfos = cast this.interp.posInfos();
			pos.funcName = funcToRun;
			#if LUA_ALLOWED
			if (parentLua != null)
			{
				pos.isLua = true;
				if (parentLua.lastCalledFunction != '') pos.funcName = parentLua.lastCalledFunction;
			}
			#end
			Iris.error('$e', pos);
		}
		return null;
	}

	public function getScriptedClass(name:String):psychlua.ScriptedClass.ScriptClassHandler {
		@:privateAccess
		var v:Dynamic = interp.customClasses.get(name);
		if (v != null && (v is psychlua.ScriptedClass.ScriptClassHandler))
			return cast v;
		return null;
	}

	public function executeFile(path:String):Void
	{
		var code:String = null;
		#if sys
		if (sys.FileSystem.exists(path))
			code = sys.io.File.getContent(path);
		#end
		if (code == null && OpenFlAssets.exists(path))
			code = OpenFlAssets.getText(path);
		if (code == null) return;
		@:privateAccess
		{
			var expr = parser.parseString(code, path);
			interp.execute(expr);
		}
	}

	override public function destroy()
	{
		origin = null;
		#if LUA_ALLOWED parentLua = null; #end
		super.destroy();
	}

	function set_varsToBring(values:Any) {
		if (varsToBring != null)
			for (key in Reflect.fields(varsToBring))
				if (exists(key.trim()))
					interp.variables.remove(key.trim());

		if (values != null)
		{
			for (key in Reflect.fields(values))
			{
				key = key.trim();
				set(key, Reflect.field(values, key));
			}
		}

		return varsToBring = values;
	}
}

class CustomFlxG {
	public static var state(get, never):Dynamic;
	public static var game(get, never):Dynamic;
	public static var sound(get, never):Dynamic;
	public static var stage(get, never):Dynamic;
	public static var cameras(get, never):Dynamic;
	public static var camera(get, never):Dynamic;
	public static var keys(get, never):Dynamic;
	public static var mouse(get, never):Dynamic;
	public static var gamepads(get, never):Dynamic;
	public static var width(get, never):Int;
	public static var height(get, never):Int;
	public static var displayWidth(get, never):Int;
	public static var displayHeight(get, never):Int;
	public static var screenOffsetX(get, never):Float;
	public static var screenOffsetY(get, never):Float;
	public static var autoPause(get, set):Bool;
	public static var signals(get, never):Dynamic;
	public static var random(get, never):Dynamic;
	public static var log(get, never):Dynamic;
	public static var scaleMode(get, never):Dynamic;
	public static var elapsed(get, never):Float;
	public static var bitmap(get, never):Dynamic;
	public static var save(get, never):Dynamic;
	public static var fixedTimestep(get, set):Bool;
	public static var timeScale(get, set):Float;
	public static var drawFramerate(get, never):Int;
	public static var updateFramerate(get, never):Int;
	
	static function get_state():Dynamic return FlxG.state;
	static function get_game():Dynamic return FlxG.game;
	static function get_sound():Dynamic return FlxG.sound;
	static function get_stage():Dynamic return FlxG.stage;
	static function get_cameras():Dynamic return FlxG.cameras;
	static function get_camera():Dynamic return FlxG.camera;
	static function get_keys():Dynamic return FlxG.keys;
	static function get_mouse():Dynamic return FlxG.mouse;
	static function get_gamepads():Dynamic return FlxG.gamepads;
	static function get_width():Int {
		#if mobile
		return Std.int(mobile.backend.MobileScaleMode.getSafeWidth());
		#else
		return FlxG.width;
		#end
	}
	static function get_height():Int {
		#if mobile
		return Std.int(mobile.backend.MobileScaleMode.getSafeHeight());
		#else
		return FlxG.height;
		#end
	}
	static function get_displayWidth():Int return FlxG.width;
	static function get_displayHeight():Int return FlxG.height;
	static function get_screenOffsetX():Float {
		#if mobile
		return mobile.backend.MobileScaleMode.getHorizontalOffset();
		#else
		return 0;
		#end
	}
	static function get_screenOffsetY():Float {
		#if mobile
		return mobile.backend.MobileScaleMode.getVerticalOffset();
		#else
		return 0;
		#end
	}
	static function get_autoPause():Bool return FlxG.autoPause;
	static function set_autoPause(value:Bool):Bool return FlxG.autoPause = value;
	static function get_signals():Dynamic return FlxG.signals;
	static function get_random():Dynamic return FlxG.random;
	static function get_log():Dynamic return FlxG.log;
	static function get_scaleMode():Dynamic return FlxG.scaleMode;
	static function get_elapsed():Float return FlxG.elapsed;
	static function get_bitmap():Dynamic {
		return BitmapFrontEndWrapper.instance;
	}
	static function get_save():Dynamic return FlxG.save;
	static function get_fixedTimestep():Bool return FlxG.fixedTimestep;
	static function set_fixedTimestep(v:Bool):Bool return FlxG.fixedTimestep = v;
	static function get_timeScale():Float return FlxG.timeScale;
	static function set_timeScale(v:Float):Float return FlxG.timeScale = v;
	static function get_drawFramerate():Int return FlxG.drawFramerate;
	static function get_updateFramerate():Int return FlxG.updateFramerate;

	public static function addChildBelowMouse(object:Dynamic, ?IndexModifier:Int = 0):Void {
		backend.FlxGUtils.addChildBelowMouse(object, IndexModifier);
	}
	
	public static function removeChild(object:Dynamic):Void {
		backend.FlxGUtils.removeChild(object);
	}
	
	public static function switchState(nextState:flixel.FlxState):Void {
		FlxG.switchState(nextState);
	}
	
	public static function resetState():Void {
		FlxG.resetState();
	}

	public static function collide(?objectOrGroup1:Dynamic, ?objectOrGroup2:Dynamic, ?notifyCallback:Dynamic):Bool {
		return FlxG.collide(objectOrGroup1, objectOrGroup2, notifyCallback);
	}

	public static function overlap(?objectOrGroup1:Dynamic, ?objectOrGroup2:Dynamic, ?notifyCallback:Dynamic, ?processCallback:Dynamic):Bool {
		return FlxG.overlap(objectOrGroup1, objectOrGroup2, notifyCallback, processCallback);
	}
}

class CustomFlxMath {
	public static inline function lerp(a:Float, b:Float, ratio:Float):Float
		return flixel.math.FlxMath.lerp(a, b, ratio);
	
	public static inline function bound(value:Float, min:Float, max:Float):Float
		return flixel.math.FlxMath.bound(value, min, max);
	
	public static inline function wrap(value:Int, min:Int, max:Int):Int
		return flixel.math.FlxMath.wrap(value, min, max);
	
	public static inline function remapToRange(value:Float, start1:Float, stop1:Float, start2:Float, stop2:Float):Float
		return flixel.math.FlxMath.remapToRange(value, start1, stop1, start2, stop2);
	
	public static inline function roundDecimal(value:Float, precision:Int):Float
		return flixel.math.FlxMath.roundDecimal(value, precision);
	
	public static inline function isDistanceWithin(spriteA:flixel.FlxSprite, spriteB:flixel.FlxSprite, distance:Float, ?includeScale:Bool = false):Bool
		return flixel.math.FlxMath.isDistanceWithin(spriteA, spriteB, distance, includeScale);
	
	public static inline function distanceBetween(spriteA:flixel.FlxSprite, spriteB:flixel.FlxSprite):Float
		return flixel.math.FlxMath.distanceBetween(spriteA, spriteB);
	
	public static inline function equal(a:Float, b:Float, precision:Float = 0.0000001):Bool
		return flixel.math.FlxMath.equal(a, b, precision);
	
	public static inline function min(a:Float, b:Float):Float
		return flixel.math.FlxMath.MIN_VALUE_FLOAT;
	
	public static inline function max(a:Float, b:Float):Float
		return flixel.math.FlxMath.MAX_VALUE_FLOAT;
	
	public static inline function minInt(a:Int, b:Int):Int
		return flixel.math.FlxMath.minInt(a, b);
	
	public static inline function maxInt(a:Int, b:Int):Int
		return flixel.math.FlxMath.maxInt(a, b);
	
	public static inline function absInt(value:Int):Int
		return flixel.math.FlxMath.absInt(value);
	
	public static inline function signOf(value:Float):Int
		return flixel.math.FlxMath.signOf(value);
	
	public static inline function inBounds(value:Float, min:Float, max:Float):Bool
		return flixel.math.FlxMath.inBounds(value, min, max);

	public static inline function fastSin(angle:Float):Float
		return flixel.math.FlxMath.fastSin(angle);
}

class CustomFlxColor {
	public static var TRANSPARENT(default, null):Int = FlxColor.TRANSPARENT;
	public static var BLACK(default, null):Int = FlxColor.BLACK;
	public static var WHITE(default, null):Int = FlxColor.WHITE;
	public static var GRAY(default, null):Int = FlxColor.GRAY;

	public static var GREEN(default, null):Int = FlxColor.GREEN;
	public static var LIME(default, null):Int = FlxColor.LIME;
	public static var YELLOW(default, null):Int = FlxColor.YELLOW;
	public static var ORANGE(default, null):Int = FlxColor.ORANGE;
	public static var RED(default, null):Int = FlxColor.RED;
	public static var PURPLE(default, null):Int = FlxColor.PURPLE;
	public static var BLUE(default, null):Int = FlxColor.BLUE;
	public static var BROWN(default, null):Int = FlxColor.BROWN;
	public static var PINK(default, null):Int = FlxColor.PINK;
	public static var MAGENTA(default, null):Int = FlxColor.MAGENTA;
	public static var CYAN(default, null):Int = FlxColor.CYAN;

	public static function fromInt(Value:Int):Int 
		return cast FlxColor.fromInt(Value);

	public static function fromRGB(Red:Int, Green:Int, Blue:Int, Alpha:Int = 255):Int
		return cast FlxColor.fromRGB(Red, Green, Blue, Alpha);

	public static function fromRGBFloat(Red:Float, Green:Float, Blue:Float, Alpha:Float = 1):Int
		return cast FlxColor.fromRGBFloat(Red, Green, Blue, Alpha);

	public static inline function fromCMYK(Cyan:Float, Magenta:Float, Yellow:Float, Black:Float, Alpha:Float = 1):Int
		return cast FlxColor.fromCMYK(Cyan, Magenta, Yellow, Black, Alpha);

	public static function fromHSB(Hue:Float, Sat:Float, Brt:Float, Alpha:Float = 1):Int
		return cast FlxColor.fromHSB(Hue, Sat, Brt, Alpha);

	public static function fromHSL(Hue:Float, Sat:Float, Light:Float, Alpha:Float = 1):Int
		return cast FlxColor.fromHSL(Hue, Sat, Light, Alpha);

	public static function fromString(str:String):Int
		return cast FlxColor.fromString(str);
	
	public static function interpolate(Color1:Int, Color2:Int, Factor:Float = 0.5):Int
		return cast FlxColor.interpolate(Color1, Color2, Factor);
	
	public static function gradient(Color1:Int, Color2:Int, Steps:Int, ?Ease:Float->Float):Array<Int>
		return cast FlxColor.gradient(Color1, Color2, Steps, Ease);
}

class CustomFlxAxes {
	public static var X(default, null):flixel.util.FlxAxes = flixel.util.FlxAxes.X;
	public static var Y(default, null):flixel.util.FlxAxes = flixel.util.FlxAxes.Y;
	public static var XY(default, null):flixel.util.FlxAxes = flixel.util.FlxAxes.XY;
}

class CustomFlxGamepadInputID {
	public static var ANY(default, null):Int            = flixel.input.gamepad.FlxGamepadInputID.ANY;
	public static var NONE(default, null):Int           = flixel.input.gamepad.FlxGamepadInputID.NONE;
	public static var A(default, null):Int              = flixel.input.gamepad.FlxGamepadInputID.A;
	public static var B(default, null):Int              = flixel.input.gamepad.FlxGamepadInputID.B;
	public static var X(default, null):Int              = flixel.input.gamepad.FlxGamepadInputID.X;
	public static var Y(default, null):Int              = flixel.input.gamepad.FlxGamepadInputID.Y;
	public static var LEFT_SHOULDER(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.LEFT_SHOULDER;
	public static var RIGHT_SHOULDER(default, null):Int = flixel.input.gamepad.FlxGamepadInputID.RIGHT_SHOULDER;
	public static var BACK(default, null):Int           = flixel.input.gamepad.FlxGamepadInputID.BACK;
	public static var START(default, null):Int          = flixel.input.gamepad.FlxGamepadInputID.START;
	public static var LEFT_STICK_CLICK(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.LEFT_STICK_CLICK;
	public static var RIGHT_STICK_CLICK(default, null):Int = flixel.input.gamepad.FlxGamepadInputID.RIGHT_STICK_CLICK;
	public static var GUIDE(default, null):Int          = flixel.input.gamepad.FlxGamepadInputID.GUIDE;
	public static var DPAD_UP(default, null):Int        = flixel.input.gamepad.FlxGamepadInputID.DPAD_UP;
	public static var DPAD_DOWN(default, null):Int      = flixel.input.gamepad.FlxGamepadInputID.DPAD_DOWN;
	public static var DPAD_LEFT(default, null):Int      = flixel.input.gamepad.FlxGamepadInputID.DPAD_LEFT;
	public static var DPAD_RIGHT(default, null):Int     = flixel.input.gamepad.FlxGamepadInputID.DPAD_RIGHT;
	public static var LEFT_TRIGGER_BUTTON(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.LEFT_TRIGGER_BUTTON;
	public static var RIGHT_TRIGGER_BUTTON(default, null):Int = flixel.input.gamepad.FlxGamepadInputID.RIGHT_TRIGGER_BUTTON;
	public static var LEFT_TRIGGER(default, null):Int   = flixel.input.gamepad.FlxGamepadInputID.LEFT_TRIGGER;
	public static var RIGHT_TRIGGER(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.RIGHT_TRIGGER;
	public static var LEFT_ANALOG_STICK(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.LEFT_ANALOG_STICK;
	public static var RIGHT_ANALOG_STICK(default, null):Int = flixel.input.gamepad.FlxGamepadInputID.RIGHT_ANALOG_STICK;
	public static var DPAD(default, null):Int           = flixel.input.gamepad.FlxGamepadInputID.DPAD;
	public static var TILT_PITCH(default, null):Int     = flixel.input.gamepad.FlxGamepadInputID.TILT_PITCH;
	public static var TILT_ROLL(default, null):Int      = flixel.input.gamepad.FlxGamepadInputID.TILT_ROLL;
	public static var POINTER_X(default, null):Int      = flixel.input.gamepad.FlxGamepadInputID.POINTER_X;
	public static var POINTER_Y(default, null):Int      = flixel.input.gamepad.FlxGamepadInputID.POINTER_Y;
	public static var EXTRA_0(default, null):Int        = flixel.input.gamepad.FlxGamepadInputID.EXTRA_0;
	public static var EXTRA_1(default, null):Int        = flixel.input.gamepad.FlxGamepadInputID.EXTRA_1;
	public static var EXTRA_2(default, null):Int        = flixel.input.gamepad.FlxGamepadInputID.EXTRA_2;
	public static var EXTRA_3(default, null):Int        = flixel.input.gamepad.FlxGamepadInputID.EXTRA_3;
	public static var LEFT_STICK_DIGITAL_UP(default, null):Int    = flixel.input.gamepad.FlxGamepadInputID.LEFT_STICK_DIGITAL_UP;
	public static var LEFT_STICK_DIGITAL_RIGHT(default, null):Int = flixel.input.gamepad.FlxGamepadInputID.LEFT_STICK_DIGITAL_RIGHT;
	public static var LEFT_STICK_DIGITAL_DOWN(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.LEFT_STICK_DIGITAL_DOWN;
	public static var LEFT_STICK_DIGITAL_LEFT(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.LEFT_STICK_DIGITAL_LEFT;
	public static var RIGHT_STICK_DIGITAL_UP(default, null):Int    = flixel.input.gamepad.FlxGamepadInputID.RIGHT_STICK_DIGITAL_UP;
	public static var RIGHT_STICK_DIGITAL_RIGHT(default, null):Int = flixel.input.gamepad.FlxGamepadInputID.RIGHT_STICK_DIGITAL_RIGHT;
	public static var RIGHT_STICK_DIGITAL_DOWN(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.RIGHT_STICK_DIGITAL_DOWN;
	public static var RIGHT_STICK_DIGITAL_LEFT(default, null):Int  = flixel.input.gamepad.FlxGamepadInputID.RIGHT_STICK_DIGITAL_LEFT;
}

class CustomFlxTextAlign {
	public static var LEFT(default, null):flixel.text.FlxText.FlxTextAlign = flixel.text.FlxText.FlxTextAlign.LEFT;
	public static var CENTER(default, null):flixel.text.FlxText.FlxTextAlign = flixel.text.FlxText.FlxTextAlign.CENTER;
	public static var RIGHT(default, null):flixel.text.FlxText.FlxTextAlign = flixel.text.FlxText.FlxTextAlign.RIGHT;
	public static var JUSTIFY(default, null):flixel.text.FlxText.FlxTextAlign = flixel.text.FlxText.FlxTextAlign.JUSTIFY;
}

class CustomFlxTextBorderStyle {
	public static var NONE(default, null):flixel.text.FlxText.FlxTextBorderStyle = flixel.text.FlxText.FlxTextBorderStyle.NONE;
	public static var SHADOW(default, null):flixel.text.FlxText.FlxTextBorderStyle = flixel.text.FlxText.FlxTextBorderStyle.SHADOW;
	public static var OUTLINE(default, null):flixel.text.FlxText.FlxTextBorderStyle = flixel.text.FlxText.FlxTextBorderStyle.OUTLINE;
	public static var OUTLINE_FAST(default, null):flixel.text.FlxText.FlxTextBorderStyle = flixel.text.FlxText.FlxTextBorderStyle.OUTLINE_FAST;
}

class CustomFlxPoint {
	public static inline function get(x:Float = 0, y:Float = 0):flixel.math.FlxBasePoint {
		return flixel.math.FlxPoint.get(x, y);
	}

	public static inline function weak(x:Float = 0, y:Float = 0):flixel.math.FlxBasePoint {
		return flixel.math.FlxPoint.weak(x, y);
	}
}

class CustomAlignment {
	public static var LEFT(default,    null):objects.Alphabet.Alignment = objects.Alphabet.Alignment.LEFT;
	public static var CENTERED(default, null):objects.Alphabet.Alignment = objects.Alphabet.Alignment.CENTERED;
	public static var RIGHT(default,   null):objects.Alphabet.Alignment = objects.Alphabet.Alignment.RIGHT;
}

@:privateAccess(flixel.system.frontEnds.BitmapFrontEnd)
class BitmapFrontEndWrapper {
	public static var instance(get, never):BitmapFrontEndWrapper;
	private static var _instance:BitmapFrontEndWrapper;
	
	static function get_instance():BitmapFrontEndWrapper {
		if (_instance == null)
			_instance = new BitmapFrontEndWrapper();
		return _instance;
	}
	
	public var _cache(get, never):CacheWrapper;
	
	private function new() {}
	
	function get__cache():CacheWrapper {
		return new CacheWrapper(@:privateAccess FlxG.bitmap._cache);
	}
	
	public function add(graphic:flixel.graphics.FlxGraphic, ?persistent:Bool = false, ?key:String):flixel.graphics.FlxGraphic {
		return FlxG.bitmap.add(graphic, persistent, key);
	}
	
	public function removeByKey(key:String):Void {
		FlxG.bitmap.removeByKey(key);
	}
	
	public function remove(graphic:flixel.graphics.FlxGraphic):Void {
		FlxG.bitmap.remove(graphic);
	}
	
	public function get(key:String):flixel.graphics.FlxGraphic {
		return FlxG.bitmap.get(key);
	}
	
	public function checkCache(key:String):Bool {
		return FlxG.bitmap.checkCache(key);
	}
	
	public function create(width:Int, height:Int, color:Int, ?unique:Bool = false, ?key:String):flixel.graphics.FlxGraphic {
		return FlxG.bitmap.create(width, height, color, unique, key);
	}
	
	public function reset():Void {
		FlxG.bitmap.reset();
	}
	
	public function clearCache():Void {
		FlxG.bitmap.clearCache();
	}
	
	public function clearUnused():Void {
		FlxG.bitmap.clearUnused();
	}
}

class CacheWrapper {
	private var cache:Map<String, flixel.graphics.FlxGraphic>;
	
	public function new(cache:Map<String, flixel.graphics.FlxGraphic>) {
		this.cache = cache;
	}
	
	public function exists(key:String):Bool {
		return cache.exists(key);
	}
	
	public function get(key:String):flixel.graphics.FlxGraphic {
		return cache.get(key);
	}
	
	public function remove(key:String):Bool {
		return cache.remove(key);
	}
	
	public function set(key:String, value:flixel.graphics.FlxGraphic):Void {
		cache.set(key, value);
	}
	
	public function keys():Iterator<String> {
		return cache.keys();
	}
	
	public function count():Int {
		var count = 0;
		for (key in cache.keys()) count++;
		return count;
	}
}

class CustomInterp extends crowplexus.hscript.Interp
{
	public var parentInstance(default, set):Dynamic = [];
	public var scriptName:String = "Unknown";
	private var _instanceFields:Array<String>;
	
	function set_parentInstance(inst:Dynamic):Dynamic
	{
		parentInstance = inst;
		if(parentInstance == null)
		{
			_instanceFields = [];
			return inst;
		}
		_instanceFields = Type.getInstanceFields(Type.getClass(inst));
		return inst;
	}

	public function new()
	{
		super();
		
		for(entry in Iris.registeredUsingEntries) {
			if(usings.indexOf(entry) == -1) {
				usings.push(entry);
			}
		}
	}

	override function fcall(o:Dynamic, funcToRun:String, args:Array<Dynamic>):Dynamic {
		if (o == null) {
			return null;
		}

		for (_using in usings) {
			var v = _using.call(o, funcToRun, args);
			if (v != null)
				return v;
		}

		var f = get(o, funcToRun);

		if (f == null) {
			Iris.error('Tried to call null function $funcToRun', posInfos());
			return null;
		}

		return Reflect.callMethod(o, f, args);
	}

	override function resolve(id: String): Dynamic {
		
#if (sys && !cpp)
switch(id) {
	case "sys": return sys;
	case "sys.io": return sys.io;
	case "sys.FileSystem": return sys.FileSystem;
	case "Sys": return Sys;
	case "File": return sys.io.File;
}
#end
		if (locals.exists(id)) {
			var l = locals.get(id);
			return l.r;
		}

		if (variables.exists(id)) {
			var v = variables.get(id);
			return v;
		}

		if (imports.exists(id)) {
			var v = imports.get(id);
			return v;
		}

		if (customClasses.exists(id)) {
			return customClasses.get(id);
		}

		if(parentInstance != null && _instanceFields.contains(id)) {
			var v = Reflect.getProperty(parentInstance, id);
			return v;
		}

		if(MusicBeatState.getVariables().exists(id)) {
			return MusicBeatState.getVariables().get(id);
		}
		
		if(MusicBeatState.getVideoHandlers().exists(id)) {
			return MusicBeatState.getVideoHandlers().get(id);
		}

		error(EUnknownVariable(id));
		return null;
	}
	
	override function get(o:Dynamic, field:String):Dynamic {
		if (o == null) {
			if(MusicBeatState.getVariables().exists(field)) {
				return MusicBeatState.getVariables().get(field);
			}
			if(MusicBeatState.getVideoHandlers().exists(field)) {
				return MusicBeatState.getVideoHandlers().get(field);
			}
			if(PlayState.instance != null)
				PlayState.instance.addTextToDebug('WARNING ($scriptName): Null reference trying to access "$field"', FlxColor.YELLOW);
			trace('WARNING ($scriptName): Null reference trying to access "$field"');
			return null;
		}

		var className:String = null;
		try {
			className = Type.getClassName(Type.getClass(o));
		} catch(e:Dynamic) {}
		if (className == "states.PlayState") {
			switch (field) {
				case "healthBarBG":
					var healthBar:Dynamic = Reflect.getProperty(o, "healthBar");
					if (healthBar != null) return Reflect.getProperty(healthBar, "bg");
				case "timeBarBG":
					var timeBar:Dynamic = Reflect.getProperty(o, "timeBar");
					if (timeBar != null) return Reflect.getProperty(timeBar, "bg");
			}
		}
		
		if ((o is psychlua.ScriptedClass.IScriptCustomBehaviour))
			return cast(o, psychlua.ScriptedClass.IScriptCustomBehaviour).hget(field);

		if (Std.isOfType(o, haxe.Constraints.IMap)) {
			if (field == "exists" || field == "get" || field == "set" || field == "remove" || 
			    field == "keys" || field == "iterator" || field == "toString" || field == "clear" ||
			    field == "copy") {
				var method = Reflect.field(o, field);
				if (method != null) return method;
			}
			var map:haxe.Constraints.IMap<String, Dynamic> = cast o;
			if (map.exists(field))
				return map.get(field);
			return null;
		}
		
		try {
			var value = Reflect.getProperty(o, field);
			if (value != null) return value;
		} catch(e:Dynamic) {}
		try {
			var value = Reflect.field(o, field);
			if (value != null) return value;
		} catch(e:Dynamic) {}
		
		if (Reflect.hasField(o, field)) {
			try {
				return Reflect.field(o, field);
			} catch(e:Dynamic) {
				try {
					return Reflect.getProperty(o, field);
				} catch(e2:Dynamic) {}
			}
		}
		
		var classType = Type.getClass(o);
		if (classType != null) {
			var instanceFields = Type.getInstanceFields(classType);
			if (instanceFields != null && instanceFields.contains(field)) {
				try {
					var value = Reflect.getProperty(o, field);
					if (value != null) return value;
					
					return Reflect.field(o, field);
				} catch(e:Dynamic) {
					if(MusicBeatState.getVariables().exists(field))
						return MusicBeatState.getVariables().get(field);
					
					if(MusicBeatState.getVideoHandlers().exists(field))
						return MusicBeatState.getVideoHandlers().get(field);
					
					return null;
				}
			}
		}
		
		if(MusicBeatState.getVariables().exists(field)) {
			return MusicBeatState.getVariables().get(field);
		}
		
		if(MusicBeatState.getVideoHandlers().exists(field)) {
			return MusicBeatState.getVideoHandlers().get(field);
		}
		
		try {
			var value = Reflect.getProperty(o, field);
			if (value != null) return value;
		} catch(e:Dynamic) {}
		
		try {
			var value = Reflect.field(o, field);
			if (value != null) return value;
		} catch(e:Dynamic) {}
		
		return null;
	}
	
	override function set(o:Dynamic, field:String, value:Dynamic):Dynamic {
		#if mobile
		if (ClientPrefs.data.mobileReceptorAlign && o != null)
		{
			var className = try Type.getClassName(Type.getClass(o)) catch(e:Dynamic) null;
			if (className == "funkin.play.notes.StrumNote")
			{
				var blockedFields = ['x', 'y', 'alpha', 'visible', 'angle', 'scale'];
				if (blockedFields.contains(field.toLowerCase()))
				{
					trace('HScript: Receptor modifications are disabled when Mobile Receptor Align is active.');
					return value;
				}
			}
		}
		#end
		
		if (o == null) {
			var className = try Type.getClassName(Type.getClass(value)) catch(e:Dynamic) null;
			if (className == "objects.VideoHandler" || className == "objects.MP4Handler") {
				MusicBeatState.getVideoHandlers().set(field, value);
			} else {
				MusicBeatState.getVariables().set(field, value);
			}
			return value;
		}
		
		if ((o is psychlua.ScriptedClass.IScriptCustomBehaviour))
			return cast(o, psychlua.ScriptedClass.IScriptCustomBehaviour).hset(field, value);

		if (Std.isOfType(o, haxe.Constraints.IMap)) {
			var map:haxe.Constraints.IMap<String, Dynamic> = cast o;
			map.set(field, value);
			return value;
		}
		
		if (Reflect.hasField(o, field)) {
			try {
				Reflect.setField(o, field, value);
				return value;
			} catch(e:Dynamic) {
				try {
					Reflect.setProperty(o, field, value);
					return value;
				} catch(e2:Dynamic) {}
			}
		}
		
		var classType = Type.getClass(o);
		if (classType != null) {
			var instanceFields = Type.getInstanceFields(classType);
			if (instanceFields != null && instanceFields.contains(field)) {
				try {
					Reflect.setProperty(o, field, value);
					return value;
				} catch(e:Dynamic) {
					try {
						Reflect.setField(o, field, value);
						return value;
					} catch(e2:Dynamic) {
						var className = try Type.getClassName(Type.getClass(value)) catch(e:Dynamic) null;
						if (className == "objects.VideoHandler" || className == "objects.MP4Handler") {
							MusicBeatState.getVideoHandlers().set(field, value);
						} else {
							MusicBeatState.getVariables().set(field, value);
						}
						return value;
					}
				}
			}
		}
		
		try {
			Reflect.setProperty(o, field, value);
			return value;
		} catch(e:Dynamic) {
			try {
				Reflect.setField(o, field, value);
				return value;
			} catch(e2:Dynamic) {}
		}
		
		var className = try Type.getClassName(Type.getClass(value)) catch(e:Dynamic) null;
		if (className == "objects.VideoHandler" || className == "objects.MP4Handler") {
			MusicBeatState.getVideoHandlers().set(field, value);
		} else {
			MusicBeatState.getVariables().set(field, value);
		}
		return value;
	}
}
#else
class HScript
{
	#if LUA_ALLOWED
	public static function implement(funk:FunkinLua) {
		funk.addLocalCallback("runHaxeCode", function(codeToRun:String, ?varsToBring:Any = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
			PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
			return null;
		});
		funk.addLocalCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null) {
			PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
			return null;
		});
		funk.addLocalCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
			return null;
		});
	}
	#end
}
#end
