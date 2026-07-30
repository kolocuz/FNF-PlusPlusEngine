package objects;

import flixel.addons.display.FlxPieDial;
import sys.thread.Thread;

#if hxvlc
import hxvlc.flixel.FlxVideoSprite;
#end

class VideoSprite extends FlxSpriteGroup {
	#if VIDEOS_ALLOWED
	public var finishCallback:Void->Void = null;
	public var onSkip:Void->Void = null;

	final _timeToSkip:Float = 1;
	public var holdingTime:Float = 0;
	public var videoSprite:FlxVideoSprite;
	public var skipSprite:FlxPieDial;
	public var cover:FlxSprite;
	public var canSkip(default, set):Bool = false;

	private var videoName:String;
	public var waiting:Bool = false;
	
	private var loadThread:Thread;
	private var videoLoaded:Bool = false;
	private var videoFailed:Bool = false;
	private var isPlaying:Bool = false;

	public function new(videoName:String, isWaiting:Bool, canSkip:Bool = false, shouldLoop:Dynamic = false) {
		super();

		this.videoName = videoName;
		scrollFactor.set();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		waiting = isWaiting;
		if(!waiting)
		{
			cover = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
			cover.scale.set(FlxG.width + 100, FlxG.height + 100);
			cover.screenCenter();
			cover.scrollFactor.set();
			add(cover);
		}

		videoSprite = new FlxVideoSprite();
		videoSprite.antialiasing = ClientPrefs.data.antialiasing;
		add(videoSprite);
		if(canSkip) this.canSkip = true;

		if(!shouldLoop) {
			videoSprite.bitmap.onEndReached.add(function() {
				if (!alreadyDestroyed && videoLoaded) {
					finishVideo();
				}
			});
		}

		videoSprite.bitmap.onFormatSetup.add(function() {
			videoSprite.setGraphicSize(FlxG.width);
			videoSprite.updateHitbox();
			videoSprite.screenCenter();
		});

		loadVideoInThread(shouldLoop);
	}

	private function loadVideoInThread(shouldLoop:Dynamic) {
		loadThread = Thread.create(() -> {
			try {
				Sys.sleep(0.1);
				loadThread.events.run(() -> {
					try {
						videoSprite.load(videoName, shouldLoop ? ['input-repeat=65545'] : null);
						videoLoaded = true;
						trace('Video loaded successfully: $videoName');
					} catch (e:Dynamic) {
						trace('Error loading video: $e');
						videoFailed = true;
					}
				});
			} catch (e:Dynamic) {
				trace('Thread error: $e');
				videoFailed = true;
			}
		});
	}

	public function playVideo() {
		if (videoLoaded && !isPlaying && !alreadyDestroyed) {
			isPlaying = true;
			videoSprite.play();
			trace('Video playing: $videoName');
		}
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (videoLoaded && !isPlaying && !alreadyDestroyed) {
			playVideo();
		}

		if (videoFailed && !alreadyDestroyed) {
			trace('Video failed to load, skipping: $videoName');
			finishVideo();
			return;
		}

		if(canSkip) {
			if(Controls.instance.pressed('accept')) {
				holdingTime = Math.max(0, Math.min(_timeToSkip, holdingTime + elapsed));
			} else if (holdingTime > 0) {
				holdingTime = Math.max(0, FlxMath.lerp(holdingTime, -0.1, FlxMath.bound(elapsed * 3, 0, 1)));
			}
			updateSkipAlpha();

			if(holdingTime >= _timeToSkip) {
				if(onSkip != null) onSkip();
				finishCallback = null;
				stopAndDestroy();
				trace('Skipped video');
				return;
			}
		}
	}

	function stopAndDestroy() {
		if (videoSprite != null && videoSprite.bitmap != null) {
			try {
				videoSprite.pause();
				videoSprite.bitmap.dispose();
			} catch (e:Dynamic) {
				trace('Error stopping video: $e');
			}
		}
		
		if (loadThread != null) {
			try {
				loadThread.events.run(() -> {});
			} catch (e:Dynamic) {}
		}
		
		destroy();
	}

	var alreadyDestroyed:Bool = false;
	override function destroy() {
		if(alreadyDestroyed)
			return;

		trace('Video destroyed');
		
		if (loadThread != null) {
			loadThread = null;
		}

		if(cover != null) {
			remove(cover);
			cover.destroy();
		}

		if(videoSprite != null && videoSprite.bitmap != null) {
			try {
				videoSprite.bitmap.dispose();
			} catch (e:Dynamic) {}
		}
		
		finishCallback = null;
		onSkip = null;
		isPlaying = false;
		videoLoaded = false;

		if(FlxG.state != null) {
			if(FlxG.state.members.contains(this))
				FlxG.state.remove(this);

			if(FlxG.state.subState != null && FlxG.state.subState.members.contains(this))
				FlxG.state.subState.remove(this);
		}
		super.destroy();
		alreadyDestroyed = true;
	}

	function finishVideo() {
		if (!alreadyDestroyed) {
			if(finishCallback != null)
				finishCallback();
			
			stopAndDestroy();
		}
	}

	public function canSkipFromPause():Bool {
		return canSkip
			&& !alreadyDestroyed
			&& videoSprite != null
			&& videoSprite.bitmap != null
			&& videoLoaded;
	}

	public function skipFromPause():Bool {
		if (!canSkipFromPause())
			return false;

		if(onSkip != null)
			onSkip();
		finishCallback = null;

		stopAndDestroy();
		trace('Skipped video from pause menu');
		return true;
	}

	function set_canSkip(newValue:Bool) {
		canSkip = newValue;
		if(canSkip) {
			if(skipSprite == null) {
				skipSprite = new FlxPieDial(0, 0, 40, FlxColor.WHITE, 40, true, 24);
				skipSprite.replaceColor(FlxColor.BLACK, FlxColor.TRANSPARENT);
				skipSprite.x = FlxG.width - (skipSprite.width + 80);
				skipSprite.y = FlxG.height - (skipSprite.height + 72);
				skipSprite.amount = 0;
				add(skipSprite);
			}
		} else if(skipSprite != null) {
			remove(skipSprite);
			skipSprite.destroy();
			skipSprite = null;
		}
		return canSkip;
	}

	function updateSkipAlpha() {
		if(skipSprite == null) return;

		skipSprite.amount = Math.min(1, Math.max(0, (holdingTime / _timeToSkip) * 1.025));
		skipSprite.alpha = FlxMath.remapToRange(skipSprite.amount, 0.025, 1, 0, 1);
	}

	public function play() {
		if (videoLoaded && videoSprite != null && !alreadyDestroyed) {
			videoSprite.play();
		}
	}

	public function resume() {
		if (videoLoaded && videoSprite != null && !alreadyDestroyed) {
			videoSprite.resume();
		}
	}

	public function pause() {
		if (videoLoaded && videoSprite != null && !alreadyDestroyed) {
			videoSprite.pause();
		}
	}
	#end
}
