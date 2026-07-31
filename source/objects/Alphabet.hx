package objects;

import backend.AssetLoader;
import flixel.graphics.frames.FlxAtlasFrames;
import haxe.Json;

enum Alignment
{
	LEFT;
	CENTERED;
	RIGHT;
}

class Alphabet extends FlxSpriteGroup
{
	public var text(default, set):String;

	public var bold:Bool = false;
	public var letters:Array<Dynamic> = [];

	public var isMenuItem:Bool = false;
	public var targetY:Int = 0;
	public var changeX:Bool = true;
	public var changeY:Bool = true;

	public var alignment(default, set):Alignment = LEFT;
	public var scaleX(default, set):Float = 1;
	public var scaleY(default, set):Float = 1;
	public var rows:Int = 0;
	
	// Новая переменная для размера шрифта
	public var fontSize:Int = 40; // По умолчанию 40, можно менять

	public var distancePerItem:FlxPoint = new FlxPoint(20, 120);
	public var startPosition:FlxPoint = new FlxPoint(0, 0);

	public function new(x:Float, y:Float, text:String = "", ?bold:Bool = true, ?fontSize:Int = 40)
	{
		super(x, y);

		this.startPosition.x = x;
		this.startPosition.y = y;
		this.bold = bold;
		this.fontSize = fontSize;
		this.text = text;
	}

	public function setAlignmentFromString(align:String)
	{
		switch(align.toLowerCase().trim())
		{
			case 'right':
				alignment = RIGHT;
			case 'center' | 'centered':
				alignment = CENTERED;
			default:
				alignment = LEFT;
		}
	}

	private function set_alignment(align:Alignment)
	{
		alignment = align;
		updateAlignment();
		return align;
	}

	private function updateAlignment()
	{
		for (letter in letters)
		{
			if (Std.isOfType(letter, FlxText))
			{
				var txt:FlxText = cast letter;
				switch(alignment)
				{
					case CENTERED:
						txt.alignment = CENTER;
					case RIGHT:
						txt.alignment = RIGHT;
					default:
						txt.alignment = LEFT;
				}
			}
		}
	}

	private function set_text(newText:String)
	{
		newText = newText.replace('\\n', '\n');
		clearLetters();
		createLetters(newText);
		updateAlignment();
		this.text = newText;
		return newText;
	}

	public function clearLetters()
	{
		var i:Int = letters.length;
		while (i > 0)
		{
			--i;
			var letter = letters[i];
			if(letter != null)
			{
				if (Std.isOfType(letter, FlxText))
					cast(letter, FlxText).destroy();
				letters.remove(letter);
				remove(letter);
			}
		}
		letters = [];
		rows = 0;
	}

	public function setScale(newX:Float, newY:Null<Float> = null)
	{
		var lastX:Float = scale.x;
		var lastY:Float = scale.y;
		if(newY == null) newY = newX;
		@:bypassAccessor scaleX = newX;
		@:bypassAccessor scaleY = newY;
		scale.x = newX;
		scale.y = newY;
		softReloadLetters(newX / lastX, newY / lastY);
	}

	private function set_scaleX(value:Float)
	{
		if (value == scaleX) return value;
		var ratio:Float = value / scale.x;
		scale.x = value;
		scaleX = value;
		softReloadLetters(ratio, 1);
		return value;
	}

	private function set_scaleY(value:Float)
	{
		if (value == scaleY) return value;
		var ratio:Float = value / scale.y;
		scale.y = value;
		scaleY = value;
		softReloadLetters(1, ratio);
		return value;
	}

	public function softReloadLetters(ratioX:Float = 1, ratioY:Null<Float> = null)
	{
		if(ratioY == null) ratioY = ratioX;
		for (letter in letters)
		{
			if(letter != null && Std.isOfType(letter, FlxText))
			{
				var txt:FlxText = cast letter;
				txt.x = (txt.x - x) * ratioX + x;
				txt.y = (txt.y - y) * ratioY + y;
				txt.scale.x *= ratioX;
				txt.scale.y *= ratioY;
			}
		}
	}

	override function update(elapsed:Float)
	{
		if (isMenuItem)
		{
			var lerpVal:Float = Math.exp(-elapsed * 9.6);
			if(changeX)
				x = FlxMath.lerp((targetY * distancePerItem.x) + startPosition.x, x, lerpVal);
			if(changeY)
				y = FlxMath.lerp((targetY * 1.3 * distancePerItem.y) + startPosition.y, y, lerpVal);
		}
		super.update(elapsed);
	}

	public function snapToPosition()
	{
		if (isMenuItem)
		{
			if(changeX)
				x = (targetY * distancePerItem.x) + startPosition.x;
			if(changeY)
				y = (targetY * 1.3 * distancePerItem.y) + startPosition.y;
		}
	}

	private static var Y_PER_ROW:Float = 85;

	private function createLetters(newText:String)
	{
		var consecutiveSpaces:Int = 0;
		var xPos:Float = 0;
		var rowData:Array<Float> = [];
		rows = 0;

		#if TRANSLATIONS_ALLOWED
		var fallbackFont:String = Language.getPhrase('language_font', 'vcr.ttf');
		#else
		var fallbackFont:String = 'vcr.ttf';
		#end

		// Используем fontSize, переданный в конструкторе
		var size:Int = Std.int(fontSize * scale.y);
		if (size < 8) size = 8; // Минимальный размер

		for (i in 0...newText.length)
		{
			var character:String = newText.charAt(i);
			if(character != '\n')
			{
				// Поддержка любого символа - проверяем, является ли он печатным
				var ascii:Int = StringTools.fastCodeAt(character, 0);
				var isPrintable:Bool = (ascii >= 32 && ascii <= 126) || // ASCII печатные
									   (ascii >= 192 && ascii <= 255) || // Latin Extended
									   (ascii >= 1040 && ascii <= 1103) || // Кириллица
									   ascii == 1025 || ascii == 1105 || // Ё, ё
									   ascii >= 0x4E00; // Китайские и другие символы (опционально)
				
				var spaceChar:Bool = (character == " " || (bold && character == "_"));
				if (spaceChar) consecutiveSpaces++;
				
				// Для любого печатного символа, включая цифры и спецсимволы
				if (isPrintable && (!bold || !spaceChar))
				{
					if (consecutiveSpaces > 0)
					{
						var spaceWidth:Float = 20 * scaleX; // Ширина пробела
						xPos += spaceWidth * consecutiveSpaces;
						rowData[rows] = xPos;
						if(!bold && xPos >= FlxG.width * 0.65)
						{
							xPos = 0;
							rows++;
						}
					}
					consecutiveSpaces = 0;

					var txt:FlxText = new FlxText(xPos, rows * Y_PER_ROW * scale.y, 0, character, size);
					txt.setFormat(Paths.font(fallbackFont), size, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
					txt.borderSize = 2;
					txt.scale.set(scaleX, scaleY);
					txt.updateHitbox();
					add(txt);
					letters.push(txt);
					
					// Ширина символа с небольшим отступом
					var charWidth:Float = txt.width + 2 * scale.x;
					xPos += charWidth;
					rowData[rows] = xPos;
				}
				else if (character == "\t") // Табуляция
				{
					xPos += 40 * 4 * scaleX; // 4 пробела
				}
			}
			else // Перенос строки
			{
				xPos = 0;
				rows++;
			}
		}

		if(letters.length > 0) rows++;
	}
}
