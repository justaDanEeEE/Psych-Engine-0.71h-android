package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;

import objects.HealthIcon;
import states.editors.ChartingState;

import substates.GameplayChangersSubstate;
import substates.ResetScoreSubState;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.misc.NumTween;
import flixel.math.FlxMath;
import flixel.FlxObject;
import flixel.util.FlxTimer;
import flixel.FlxSound;
import flixel.group.FlxTypedGroup;
import flixel.util.FlxEase;

#if MODS_ALLOWED
import sys.FileSystem;
#end

class FreeplayState extends MusicBeatState
{
	var songs:Array<SongMetadata> = [];

	var selector:FlxText;
	private static var curSelected:Int = 0;
	var lerpSelected:Float = 0;
	var curDifficulty:Int = -1;
	private static var lastDifficultyName:String = Difficulty.getDefault();

	var scoreBG:FlxSprite;
	var scoreText:FlxText;
	var diffText:FlxText;
	var lerpScore:Int = 0;
	var lerpRating:Float = 0;
	var intendedScore:Int = 0;
	var intendedRating:Float = 0;

	private var grpSongs:FlxTypedGroup<Alphabet>;
	private var curPlaying:Bool = false;

	private var iconArray:Array<HealthIcon> = [];

	var bg:FlxSprite;
	var menuBG2:FlxSprite;
	var videoBG:FlxSprite;
	var intendedColor:Int;
	var colorTween:FlxTween;

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	// --- added UI elements ---
	var topBar:FlxSprite;
	var freeplayLabel:FlxText;
	var vsLabel:FlxText;

	var dj:FlxSprite;
	var djTargetX:Float = 100; // where DJ should rest
	var djEnterTime:Float = 0.9;

	// left-bottom record
	var leftRecordValue:FlxText;
	var leftRecordLabel:FlxText;

	// whether we are waiting to start a selected song (to avoid double-start)
	var pendingStart:Bool = false;

	override function create()
	{
		persistentUpdate = true;
		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if desktop
		DiscordClient.changePresence("In the Menus", null);
		#end

		// collect songs (same as original)
		for (i in 0...WeekData.weeksList.length) {
			if(weekIsLocked(WeekData.weeksList[i])) continue;

			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var leSongs:Array<String> = [];
			var leChars:Array<String> = [];

			for (j in 0...leWeek.songs.length)
			{
				leSongs.push(leWeek.songs[j][0]);
				leChars.push(leWeek.songs[j][1]);
			}

			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				var colors:Array<Int> = song[2];
				if(colors == null || colors.length < 3)
				{
					colors = [146, 113, 253];
				}
				addSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]));
			}
		}
		Mods.loadTopMod();

		// --- VIDEO BACKGROUND if exists (videos/freeplay). If not present, fallback to menuDesat image ---
		if (OpenFlAssets.exists(Paths.video("freeplay"))) {
			// try to load as sprite (engine-specific video support may vary)
			try {
				videoBG = new FlxSprite(0, 0).loadGraphic(Paths.video("freeplay"));
				videoBG.setGraphicSize(FlxG.width, FlxG.height);
				videoBG.antialiasing = ClientPrefs.data.antialiasing;
				add(videoBG);
			} catch(e:Dynamic) {
				// fallback to image
				bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
				bg.antialiasing = ClientPrefs.data.antialiasing;
				add(bg);
				bg.screenCenter();
			}
		} else {
			bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
			bg.antialiasing = ClientPrefs.data.antialiasing;
			add(bg);
			bg.screenCenter();
		}

		// --- second background (menuBG2) above base bg, but under songs/icons ---
		menuBG2 = new FlxSprite().loadGraphic(Paths.image('menuBG2'));
		menuBG2.antialiasing = ClientPrefs.data.antialiasing;
		add(menuBG2);
		// ensure it's above 'bg' but below menu elements; keep default stacking order (we added after bg)

		grpSongs = new FlxTypedGroup<Alphabet>();
		add(grpSongs);

		for (i in 0...songs.length)
		{
			// create song text but place it on the right side (we'll use startPosition.x)
			var songText:Alphabet = new Alphabet(90, 320, songs[i].songName, true);
			songText.targetY = i;
			grpSongs.add(songText);

			// set right-side start position so songs appear on right
			songText.scaleX = Math.min(1, 980 / songText.width);
			songText.snapToPosition();

			// Set start position X to be near the right but not at edge
			songText.startPosition.x = FlxG.width - 380;
			// keep the y start as before (startPosition.y already set inside Alphabet constructor)
			// try to set font for song text (Alphabet may expose setFormat)
			try {
				songText.setFormat(Paths.font("vcr.ttf"), Std.int(22), FlxColor.WHITE, RIGHT);
			} catch(e:Dynamic) {
				// if Alphabet has no setFormat, it will use its internal style — ignore
			}

			Mods.currentModDirectory = songs[i].folder;
			var icon:HealthIcon = new HealthIcon(songs[i].songCharacter);
			icon.sprTracker = songText;

			// too laggy with a lot of songs, so i had to recode the logic for it
			songText.visible = songText.active = songText.isMenuItem = false;
			icon.visible = icon.active = false;

			iconArray.push(icon);
			add(icon);
		}
		WeekData.setDirectoryFromWeek();

		// --- top bar with FREEPLAY / VS DAN OST ---
		topBar = new FlxSprite(0, 0).makeGraphic(FlxG.width, 40, 0xFF000000);
		add(topBar); // add after backgrounds so it's above them

		freeplayLabel = new FlxText(8, 6, 300, "FREEPLAY");
		freeplayLabel.setFormat(Paths.font("vcr.ttf"), 22, FlxColor.WHITE, LEFT);
		freeplayLabel.scrollFactor.set();
		add(freeplayLabel);

		vsLabel = new FlxText(FlxG.width - 220, 6, 200, "VS DAN OST");
		vsLabel.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, RIGHT);
		vsLabel.scrollFactor.set();
		add(vsLabel);

		// --- DJ character setup (left, animated) ---
		dj = new FlxSprite();
		// try load dj image atlas and set animations by prefix (expecting frames named 'dj idle' etc.)
		dj.loadGraphic(Paths.image("dj"), true, null, null, null, null);
		// add animations by prefix; engines vary: try addByPrefix, fallback to addByIndices
		try {
			dj.animation.addByPrefix("dj_idle", "dj idle", 16, true);
			dj.animation.addByPrefix("dj_playing", "dj playing", 16, true);
		} catch(e:Dynamic) {
			// fallback: try add with numeric frames (0..11)
			dj.animation.add("dj_idle", [0,1,2,3,4,5,6,7,8,9,10,11], 16, true);
			dj.animation.add("dj_playing", [0,1,2,3,4,5,6,7,8,9,10,11], 16, true);
		}
		dj.animation.play("dj_idle");

		// initial off-screen for entry
		dj.x = -200;
		dj.y = FlxG.height - 300;
		add(dj);

		// tween DJ into view
		FlxTween.tween(dj, { x: djTargetX }, djEnterTime, { ease: FlxEase.circOut });

		// --- score / personal best text (right top) kept for compatibility with original logic ---
		scoreText = new FlxText(FlxG.width * 0.7, 5, 0, "", 32);
		scoreText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, RIGHT);

		scoreBG = new FlxSprite(scoreText.x - 6, 0).makeGraphic(1, 66, 0xFF000000);
		scoreBG.alpha = 0.6;
		add(scoreBG);

		diffText = new FlxText(scoreText.x, scoreText.y + 36, 0, "", 24);
		diffText.font = scoreText.font;
		add(diffText);

		add(scoreText);

		// --- Left-bottom record (user request) ---
		leftRecordValue = new FlxText(10, FlxG.height - 80, 300, Std.string(intendedScore));
		leftRecordValue.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, LEFT);
		leftRecordValue.scrollFactor.set();
		add(leftRecordValue);

		leftRecordLabel = new FlxText(10, FlxG.height - 40, 300, "SCORE");
		leftRecordLabel.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT);
		leftRecordLabel.scrollFactor.set();
		add(leftRecordLabel);

		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);
		
		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		if(curSelected >= songs.length) curSelected = 0;
		// set base bg color from selected song as before (if bg exists)
		if (bg != null) {
			bg.color = songs[curSelected].color;
			intendedColor = bg.color;
		}

		lerpSelected = curSelected;
		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));
		changeSelection();

		// footer small help text (unchanged)
		var textBG:FlxSprite = new FlxSprite(0, FlxG.height - 26).makeGraphic(FlxG.width, 26, 0xFF000000);
		textBG.alpha = 0.6;
		add(textBG);

		#if PRELOAD_ALL
		#if android
		var leText:String = "Press X to listen to the Song / Press C to open the Gameplay Changers Menu / Press Y to Reset your Score and Accuracy.";
		var size:Int = 16;
		#else
		var leText:String = "Press SPACE to listen to the Song / Press CTRL to open the Gameplay Changers Menu / Press RESET to Reset your Score and Accuracy.";
		var size:Int = 16;
		#end
		#else
		var leText:String = "Press C to open the Gameplay Changers Menu / Press Y to Reset your Score and Accuracy.";
		var size:Int = 18;
		#end
		var text:FlxText = new FlxText(textBG.x, textBG.y + 4, FlxG.width, leText, size);
		text.setFormat(Paths.font("vcr.ttf"), size, FlxColor.WHITE, RIGHT);
		text.scrollFactor.set();
		add(text);
		
		updateTexts();

		// --- add virtual pad for android (keeps your earlier behavior) ---
		#if android
                addVirtualPad(FULL, A_B_C_X_Y_Z);
        #end
                
		super.create();
	}

	override function closeSubState() {
		changeSelection(0, false);
		persistentUpdate = true;
		super.closeSubState();
	}

	public function addSong(songName:String, weekNum:Int, songCharacter:String, color:Int)
	{
		songs.push(new SongMetadata(songName, weekNum, songCharacter, color));
	}

	function weekIsLocked(name:String):Bool {
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked && leWeek.weekBefore.length > 0 && (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	var instPlaying:Int = -1;
	public static var vocals:FlxSound = null;
	var holdTime:Float = 0;

	override function update(elapsed:Float)
	{
		// restore music volume fade-in as earlier
		if (FlxG.sound.music.volume < 0.7)
		{
			FlxG.sound.music.volume += 0.5 * FlxG.elapsed;
		}
		lerpScore = Math.floor(FlxMath.lerp(lerpScore, intendedScore, FlxMath.bound(elapsed * 24, 0, 1)));
		lerpRating = FlxMath.lerp(lerpRating, intendedRating, FlxMath.bound(elapsed * 12, 0, 1));

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;
		if (Math.abs(lerpRating - intendedRating) <= 0.01)
			lerpRating = intendedRating;

		var ratingSplit:Array<String> = Std.string(CoolUtil.floorDecimal(lerpRating * 100, 2)).split('.');
		if(ratingSplit.length < 2) { //No decimals, add an empty space
			ratingSplit.push('');
		}
		
		while(ratingSplit[1].length < 2) { //Less than 2 decimals in it, add decimals then
			ratingSplit[1] += '0';
		}

		scoreText.text = 'PERSONAL BEST: ' + lerpScore + ' (' + ratingSplit.join('.') + '%)';
		positionHighscore();

		// update left-bottom record and the label
		leftRecordValue.text = Std.string(intendedScore);
		// leftRecordLabel is static 'SCORE'

		var shiftMult:Int = 1;
		if(FlxG.keys.pressed.SHIFT  #if android || MusicBeatState._virtualpad.buttonZ.pressed #end) shiftMult = 3;

		if(songs.length > 1)
		{
			if(FlxG.keys.justPressed.HOME)
			{
				curSelected = 0;
				changeSelection();
				holdTime = 0;	
			}
			else if(FlxG.keys.justPressed.END)
			{
				curSelected = songs.length - 1;
				changeSelection();
				holdTime = 0;	
			}
			if (controls.UI_UP_P)
			{
				changeSelection(-shiftMult);
				holdTime = 0;
			}
			if (controls.UI_DOWN_P)
			{
				changeSelection(shiftMult);
				holdTime = 0;
			}

			if(controls.UI_DOWN || controls.UI_UP)
			{
				var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
				holdTime += elapsed;
				var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

				if(holdTime > 0.5 && checkNewHold - checkLastHold > 0)
					changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -shiftMult : shiftMult));
			}

			if(FlxG.mouse.wheel != 0)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
				changeSelection(-shiftMult * FlxG.mouse.wheel, false);
			}
		}

		if (controls.UI_LEFT_P)
		{
			changeDiff(-1);
			_updateSongLastDifficulty();
		}
		else if (controls.UI_RIGHT_P)
		{
			changeDiff(1);
			_updateSongLastDifficulty();
		}

		if (controls.BACK)
		{
			// tween DJ out to the left when exiting
			FlxTween.tween(dj, { x: - (dj.width + 40) }, 0.6, { ease: FlxEase.circIn });

			persistentUpdate = false;
			if(colorTween != null) {
				colorTween.cancel();
			}
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
		}

		if(FlxG.keys.justPressed.CONTROL #if android || MusicBeatState._virtualpad.buttonC.justPressed #end)
		{
			persistentUpdate = false;
			openSubState(new GameplayChangersSubstate());
		}
		else if(FlxG.keys.justPressed.SPACE #if android || MusicBeatState._virtualpad.buttonX.justPressed #end)
		{
			// preview playback - keep original behaviour
			if(instPlaying != curSelected)
			{
				#if PRELOAD_ALL
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;
				Mods.currentModDirectory = songs[curSelected].folder;
				var poop:String = Highscore.formatSong(songs[curSelected].songName.toLowerCase(), curDifficulty);
				PlayState.SONG = Song.loadFromJson(poop, songs[curSelected].songName.toLowerCase());
				if (PlayState.SONG.needsVoices)
					vocals = new FlxSound().loadEmbedded(Paths.voices(PlayState.SONG.song));
				else
					vocals = new FlxSound();

				FlxG.sound.list.add(vocals);
				FlxG.sound.playMusic(Paths.inst(PlayState.SONG.song), 0.7);
				vocals.play();
				vocals.persist = true;
				vocals.looped = true;
				vocals.volume = 0.7;
				instPlaying = curSelected;
				#end
			}
		}

		else if (controls.ACCEPT)
		{
			// When player accepts selection: perform DJ animation, stop menu music, wait 3s, then start PlayState/ChartingState
			if (!pendingStart) {
				pendingStart = true;
				// play DJ "playing" animation
				try { dj.animation.play("dj_playing"); } catch(e:Dynamic) {}
				// fade out menu music quickly
				FlxTween.tween(FlxG.sound.music, {volume: 0}, 0.5);
				// after 3 seconds, start the song
				FlxG.timer.start(3, function(t:FlxTimer) {
					var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
					var poop:String = Highscore.formatSong(songLowercase, curDifficulty);
					try {
						PlayState.SONG = Song.loadFromJson(poop, songLowercase);
						PlayState.isStoryMode = false;
						PlayState.storyDifficulty = curDifficulty;
					} catch(err:Dynamic) {
						// show missing chart message and abort
						missingText.text = 'ERROR WHILE LOADING CHART:\n' + Mods.currentModDirectory + '/data/' + songLowercase + '/' + poop + '.json';
						missingText.screenCenter(Y);
						missingText.visible = true;
						missingTextBG.visible = true;
						FlxG.sound.play(Paths.sound('cancelMenu'));
						pendingStart = false;
						return;
					}

					if (FlxG.keys.pressed.SHIFT #if android || MusicBeatState._virtualpad.buttonZ.pressed #end) {
						LoadingState.loadAndSwitchState(new ChartingState());
					} else {
						LoadingState.loadAndSwitchState(new PlayState());
					}

					// stop vocals & music immediately
					FlxG.sound.music.stop();
					destroyFreeplayVocals();
				});
			}
		}
		else if(controls.RESET #if android || MusicBeatState._virtualpad.buttonY.justPressed #end)
		{
		    #if android
			removeVirtualPad();
			#end
			persistentUpdate = false;
			openSubState(new ResetScoreSubState(songs[curSelected].songName, curDifficulty, songs[curSelected].songCharacter));
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		updateTexts(elapsed);
		super.update(elapsed);
	}

	public static function destroyFreeplayVocals() {
		if(vocals != null) {
			vocals.stop();
			vocals.destroy();
		}
		vocals = null;
	}

	function changeDiff(change:Int = 0)
	{
		curDifficulty += change;

		if (curDifficulty < 0)
			curDifficulty = Difficulty.list.length-1;
		if (curDifficulty >= Difficulty.list.length)
			curDifficulty = 0;

		#if !switch
		intendedScore = Highscore.getScore(songs[curSelected].songName, curDifficulty);
		intendedRating = Highscore.getRating(songs[curSelected].songName, curDifficulty);
		#end

		lastDifficultyName = Difficulty.getString(curDifficulty);
		if (Difficulty.list.length > 1)
			diffText.text = '< ' + lastDifficultyName.toUpperCase() + ' >';
		else
			diffText.text = lastDifficultyName.toUpperCase();

		positionHighscore();
		missingText.visible = false;
		missingTextBG.visible = false;
	}

	function changeSelection(change:Int = 0, playSound:Bool = true)
	{
		_updateSongLastDifficulty();
		if(playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var lastList:Array<String> = Difficulty.list;
		curSelected += change;

		if (curSelected < 0)
			curSelected = songs.length - 1;
		if (curSelected >= songs.length)
			curSelected = 0;
			
		var newColor:Int = songs[curSelected].color;
		if(newColor != intendedColor) {
			if(colorTween != null) {
				colorTween.cancel();
			}
			intendedColor = newColor;
			colorTween = FlxTween.color(bg, 1, bg.color, intendedColor, {
				onComplete: function(twn:FlxTween) {
					colorTween = null;
				}
			});
		}

		// visual updates
		for (i in 0...iconArray.length)
		{
			iconArray[i].alpha = 0.6;
		}

		iconArray[curSelected].alpha = 1;

		for (item in grpSongs.members)
		{
			item.alpha = 0.6;
			if (item.targetY == curSelected)
				item.alpha = 1;
		}
		
		Mods.currentModDirectory = songs[curSelected].folder;
		PlayState.storyWeek = songs[curSelected].week;
		Difficulty.loadFromWeek();
		
		var savedDiff:String = songs[curSelected].lastDifficulty;
		var lastDiff:Int = Difficulty.list.indexOf(lastDifficultyName);
		if(savedDiff != null && !lastList.contains(savedDiff) && Difficulty.list.contains(savedDiff))
			curDifficulty = Math.round(Math.max(0, Difficulty.list.indexOf(savedDiff)));
		else if(lastDiff > -1)
			curDifficulty = lastDiff;
		else if(Difficulty.list.contains(Difficulty.getDefault()))
			curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(Difficulty.getDefault())));
		else
			curDifficulty = 0;

		changeDiff();
		_updateSongLastDifficulty();

		// play a small dj animation on selection (visual feedback)
		try {
			dj.animation.play("dj_playing");
			// after short while return to idle
			FlxG.timer.start(0.6, function(t:FlxTimer) {
				try { dj.animation.play("dj_idle"); } catch(_) {}
			});
		} catch(e:Dynamic) {}
	}

	inline private function _updateSongLastDifficulty()
	{
		songs[curSelected].lastDifficulty = Difficulty.getString(curDifficulty);
	}

	private function positionHighscore() {
		scoreText.x = FlxG.width - scoreText.width - 6;
		scoreBG.scale.x = FlxG.width - scoreText.x + 6;
		scoreBG.x = FlxG.width - (scoreBG.scale.x / 2);
		diffText.x = Std.int(scoreBG.x + (scoreBG.width / 2));
		diffText.x -= diffText.width / 2;
	}

	var _drawDistance:Int = 4;
	var _lastVisibles:Array<Int> = [];
	public function updateTexts(elapsed:Float = 0.0)
	{
		lerpSelected = FlxMath.lerp(lerpSelected, curSelected, FlxMath.bound(elapsed * 9.6, 0, 1));
		for (i in _lastVisibles)
		{
			grpSongs.members[i].visible = grpSongs.members[i].active = false;
			iconArray[i].visible = iconArray[i].active = false;
		}
		_lastVisibles = [];

		var min:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - _drawDistance)));
		var max:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + _drawDistance)));
		for (i in min...max)
		{
			var item:Alphabet = grpSongs.members[i];
			item.visible = item.active = true;
			item.x = ((item.targetY - lerpSelected) * item.distancePerItem.x) + item.startPosition.x;
			item.y = ((item.targetY - lerpSelected) * 1.3 * item.distancePerItem.y) + item.startPosition.y;

			var icon:HealthIcon = iconArray[i];
			icon.visible = icon.active = true;
			_lastVisibles.push(i);
		}
	}
}

class SongMetadata
{
	public var songName:String = "";
	public var week:Int = 0;
	public var songCharacter:String = "";
	public var color:Int = -7179779;
	public var folder:String = "";
	public var lastDifficulty:String = null;

	public function new(song:String, week:Int, songCharacter:String, color:Int)
	{
		this.songName = song;
		this.week = week;
		this.songCharacter = songCharacter;
		this.color = color;
		this.folder = Mods.currentModDirectory;
		if(this.folder == null) this.folder = '';
	}
}