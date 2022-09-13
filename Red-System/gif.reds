Red/System [
]

;--Header Block [6 bytes]
HBS!: alias struct! [
	signature 		[c-string!]	;--3 bytes as string
	version 		[c-string!]	;--3 bytes as string
]


;--Logical Screen Descriptor [7 bytes]
LSD!: alias struct! [
	width 				[integer!]		;--integer [2 bytes] : frame width
	height 				[integer!]		;--integer [2 bytes] : frame height
	packed 				[byte!]			;--byte [0..255]
	backGround 			[byte!]			;--byte	background : color index			
	aspectRatio 		[byte!]			;--byte [0..255] : the width / by the height of the pixel
	hasColorTable?		[logic!]		;--from packed : is global color table present?
	colorResolution 	[integer!]		;--from packed : color depth minus 1
	colorSorted? 	 	[integer!]		;--from packed : are colors sorted?
	colorTableSize 		[integer!]		;--from packed : number of entries in global color table
]

;--Plain Text Extension block [17 bytes]
PTE!: alias struct! [
	code				[byte!] 	;--byte [Always 0x21] 33
	label				[byte!]		;--byte [Always 0x01] 1
	blockSize 			[byte!]		;--byte [Always 0x0C] 12
	textGridLeft		[integer!]	;--integer [2 bytes]
	textGridTop			[integer!]	;--integer [2 bytes] 
	textGridWidth		[integer!]	;--integer [2 bytes] 
	textGridHeight 		[integer!]	;--integer [2 bytes] 
	cellWidth			[byte!]		;--byte
	cellHeight			[byte!]		;--byte	
	fgColorIndex 		[byte!]		;--byte
	bgColorIndex 		[byte!]		;--byte
	plainTextData		[byte-ptr!]	;--a byte pointer 
	terminator 			[byte!]		;--byte [Always 0x00]		
]

;--Application Extension block [16 bytes]
APE!: alias struct! [
	code				[byte!] 	;--byte [Always 0x21] 33
	label				[byte!]		;--byte [Always 0xFF] 255
	blockSize 			[byte!]		;--byte [Always 0x0B] 11
	identifier			[c-string!]	;--string 8 bytes
	authentCode			[c-string!]	;--3 bytes
	dataSize			[byte!]		;--byte [Always 0x03]
	id					[byte!]		;--byte [Always 0x01]
	iloop				[byte!]		;--integer 2 bytes [0 : infinite loop]
	terminator:			[byte!]		;--byte [Always 0x00]		
]

;--Comment Extension block [cannot be pre calculated]
CEX!: alias struct! [
	code				[byte!]		;--byte [Always 0x21] 33
	label				[byte!]		;--byte [Always 0xFE] 254
	nBytes				[byte!]		;--byte [1..255]
	commentData			[byte-ptr!]	;--block of values	
	terminator			[byte!]		;--byte [Always 0x00]	
]

;--Graphics Control Extension [8 bytes]
GCE!: alias struct! [
	code				[byte!] 	;--byte [Always 0x21] 33
	label				[byte!]		;--byte [Always 0xF9] 249
	blockSize 			[byte!]		;--byte [Always 0x04] 4
	packed				[byte!]		;--byte [0..4]
	delay				[integer!]	;--integer [2 bytes] : Hundredths of seconds to wait
	colorIndex			[integer!]	;--byte	[0..255] : Transparent Color Index
	terminator 			[byte!]		;--byte [Always 0x00]	
	reserved			[integer!]	;--from packed	
	disposal			[integer!]	;--from packed : Disposal Method
	userInput?			[logic!]	;--from packed : User Input Flag
	transparentFlag?	[logic!]	;--from packed : Transparent Color flag
]

;--Image Descriptor [10 bytes]
IMD!: make object! [
	separator 			[byte!] 	;--byte [Always 0x2C] 44
	left 				[integer!]	;--integer [2 bytes] : X position of image on the display
	top					[integer!]	;--integer [2 bytes] : Y position of image on the display
	width				[integer!]	;--integer [2 bytes] : Width of the image in pixels
	height				[integer!]	;--integer [2 bytes] : Height of the image in pixels
	packed				[byte!]		;--byte		
	localColorTable?	[logic!]	;--from packed : is a local color table present?
 	interlaced? 		[logic!]	;--from packed : are data interlaced?
 	colorSorted? 		[logic!]	;--from packed : are colors sorted?
 	reserved 			[integer!]	;--from packed
 	colorTableSize		[integer!]	;--from packed : number of entries in global color table
]


print "Test"
HBS: declare HBS!
LSD: declare LSD!
PTE: declare PTE!
APE: declare APE!
CEX: declare CEX!
GCE: declare GCE!
IMD: declare IMD!
