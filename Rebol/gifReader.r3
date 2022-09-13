#!/usr/local/bin/r310
REBOL [ 
] 

;--Thanks to Matthew Flickinger
;--https://www.matthewflickinger.com/lab/whatsinagif/
;--Thanks to Toomas Vooglaid for LZW decompression and constant help :)

;--we can transform to structures for Red/System

;--Header Block [6 bytes]
HBS: make object! [
	signature: 		""	;--3 bytes as string
	version: 		""	;--3 bytes as string
]

;--Logical Screen Descriptor [7 bytes]
LSD: make object! [
	width: 				0		;--integer [2 bytes] : frame width
	height: 			0		;--integer [2 bytes] : frame height
	packed: 			0		;--byte [0..255]
	backGround: 		0		;--byte	background : color index			
	aspectRatio: 		0		;--byte [0..255] : the width of the pixel divided by the height of the pixel
	hasColorTable?:		false	;--from packed : is global color table present?
	colorResolution: 	0		;--from packed : color depth minus 1
	colorSorted?: 	 	0		;--from packed : are colors sorted?
	colorTableSize: 	0		;--from packed : number of entries in global color table
]

;--Plain Text Extension block [17 bytes]
PTE: make object! [
	code:				33 	;--byte [Always 0x21] 33
	label:				1	;--byte [Always 0x01] 1
	blockSize: 			12	;--byte [Always 0x0C] 12
	textGridLeft:		0	;--integer [2 bytes]
	textGridTop:		0	;--integer [2 bytes] 
	textGridWidth:		0	;--integer [2 bytes] 
	textGridHeight: 	0	;--integer [2 bytes] 
	cellWidth:			0	;--byte
	cellHeight:			0	;--byte	
	fgColorIndex: 		0	;--byte
	bgColorIndex: 		0	;--byte
	plainTextData:		0	;--a byte pointer 
	terminator: 		0	;--byte [Always 0x00]		
]

;--Application Extension block [16 bytes]
APE: make object! [
	code:				33 	;--byte [Always 0x21] 33
	label:				255	;--byte [Always 0xFF] 255
	blockSize: 			11	;--byte [Always 0x0B] 11
	identifier:			""	;--string 8 bytes
	authentCode:		""	;--3 bytes
	dataSize:			0	;--byte [Always 0x03]
	id:					0	;--byte [Always 0x01]
	loop:				0	;--integer 2 bytes [0 : infinite loop]
	terminator: 		0	;--byte [Always 0x00]		
]

;--Comment Extension block [cannot be pre calculated]
CEX: make object! [
	code:				33 	;--byte [Always 0x21] 33
	label:				254	;--byte [Always 0xFE] 254
	nBytes:				0	;--byte [1..255]
	commentData:		[]	;--block of values	
	terminator: 		0	;--byte [Always 0x00]	
]

;--Graphics Control Extension [8 bytes]
GCE: make object! [
	code:				33 		;--byte [Always 0x21] 33
	label:				249		;--byte [Always 0xF9] 249
	blockSize: 			4		;--byte [Always 0x04] 4
	packed:				0		;--byte [0..4]
	delay:				0		;--integer [2 bytes] : Hundredths of seconds to wait
	colorIndex:			0		;--byte	[0..255] : Transparent Color Index
	terminator: 		0		;--byte [Always 0x00]	
	reserved:			0		;--from packed	
	disposal:			0		;--from packed : Disposal Method
	userInput?:			false	;--from packed : User Input Flag
	transparentFlag?:	false	;--from packed : Transparent Color flag
]

;--Image Descriptor [10 bytes]
IMD: make object! [
	separator: 			44 		;--byte [Always 0x2C] 44
	left: 				0		;--integer [2 bytes] : X position of image on the display
	top:				0		;--integer [2 bytes] : Y position of image on the display
	width:				0		;--integer [2 bytes] : Width of the image in pixels
	height:				0		;--integer [2 bytes] : Height of the image in pixels
	packed:				0		;--byte		
	localColorTable?:	false	;--from packed : is a local color table present?
 	interlaced?: 		false	;--from packed : are data interlaced?
 	colorSorted?: 		false	;--from packed : are colors sorted?
 	reserved: 			0		;--from packed
 	colorTableSize:		0		;--from packed : number of entries in global color table
]

;--data follow each image descriptor when there is a Global Color Table
;--in case of local color table, color table follows the image Descriptor 
;--and preceeds the imageData

;--Red/Rebol object
imageData: make object! [
	lzwCode:			0	;--byte [2..8] LZW minimum code size
	nBytes:				0	;--byte [1..255] number of bytes/sub-group
	binaryData:			{}	;--binary string 00110001 .....
]


frame: make object! [
	minLZWCode:			2
	disposal:			0
	userInput?:			false
	transparent?:		false
	delay:				0
	transparentIndex:	0
	pos:				0x0
	size:				0x0
	localColorTable?:	false
	interlaced?:		false
	sorted?:			false
	colorTableSize:		0
	colorTable:			[]
	data:				{}
	indices:			[]
	bmp:				#{}
	plot:				[]
]


;--*********************** Reading Functions *************************

;--mandatory

;--GIF header
readHeader: function [
	gif 	[binary!]
	index	[integer!]
	return:	[integer!]
][
	gif: skip head gif index
	HBS/signature: to-string copy/part gif 3 gif: skip gif 3
	HBS/version: to-string copy/part gif 3 gif: skip gif 3
	either HBS/signature = "GIF" [1][0]
]

;--Logical Screen Descriptor
readLSD: function [
	gif 	[binary!]
	index	[integer!]
][
	gif: skip head gif index
	LSD/width: to integer! reverse copy/part gif 2 gif: skip gif 2
	LSD/height: to integer! reverse copy/part gif 2 gif: skip gif 2
	LSD/packed: to integer! copy/part gif 1 
	packed: enbase copy/part gif 1 2 
	gif: skip gif 1
	LSD/backGround: to integer! copy/part gif 1 gif: skip gif 1
	LSD/aspectRatio: to integer! copy/part gif 1 gif: skip gif 1
	;--from packed 
	;print LSD/packed >> 7
	LSD/hasColorTable?: LSD/packed AND 128 > 0 ;packed/1 = #"1"
	LSD/colorResolution: 1 + (LSD/packed AND 112 >> 4); 1 + getCode copy/part at packed 2 3; 
	LSD/colorSorted?: LSD/packed AND 8 >> 3; packed/5 = #"1"; 
	LSD/colorTableSize: LSD/packed AND 7; getCode at copy packed 6
	if LSD/aspectRatio > 0 [LSD/aspectRatio: LSD/aspectRatio + 15 / 64]
	if LSD/hasColorTable?  [LSD/colorTableSize: to integer! 2 ** (LSD/colorTableSize + 1)]
	;--Global Color Table Flag [0 or 1]
	;--if the flag is 1, the Color Table will follow the Logical Screen Descriptor.
	;--otherwise the Color Table will follow each Image Descriptor
]


;--optional
;--Graphics Control Extension (optional)
;--This block is OPTIONAL; but at most one Graphic Control Extension may precede a graphic rendering block.
;--For animated Gifs this block is just before the Image Description block 
readGCE: function [
	gif 	[binary!]
	index	[integer!]
][
 	gif: skip head gif index
	GCE/code: to integer! copy/part gif 1 gif: skip gif 1
	GCE/label: to integer! copy/part gif 1 gif: skip gif 1
	GCE/blockSize: to integer! copy/part gif 1 gif: skip gif 1
	GCE/packed: to integer! copy/part gif 1 
	packed: enbase copy/part gif 1 2
	gif: skip gif 1
	GCE/delay: to integer! reverse copy/part gif 2 gif: skip gif 2
	GCE/colorIndex: to integer! copy/part gif 1 gif: skip gif 1
	GCE/terminator: to integer! copy/part gif 1 gif: skip gif 1
	;--from packed
	GCE/reserved: GCE/packed AND 224 >> 5 ;getCode copy/part at packed 1 3; 
	GCE/disposal: GCE/packed AND 28 >> 2 ;getCode copy/part at packed 4 3; 
	GCE/userInput?: GCE/packed AND 2 >> 1 > 0 ;packed/7 = #"1"; 
	GCE/transparentFlag?: GCE/packed AND 1 > 0 ;packed/8 = #"1"; 
]


;--Application Extension (optional)
;--Only 1 block if present

readAPE: function [
	gif 	[binary!]
	index	[integer!]
 ][
 	gif: skip head gif index
 	APE/code: to integer! copy/part gif 1 gif: skip gif 1
 	APE/label: to integer! copy/part gif 1 gif: skip gif 1
 	APE/blockSize: to integer! copy/part gif 1 gif: skip gif 1
 	APE/identifier: to-string copy/part gif 8 gif: skip gif 8
 	APE/authentCode: to-string copy/part gif 3 gif: skip gif 3
 	APE/dataSize: to integer! copy/part gif 1 gif: skip gif 1
 	APE/id: to integer! copy/part gif 1 gif: skip gif 1
 	APE/loop: to integer! reverse copy/part gif 2 gif: skip gif 2
 	APE/terminator: to integer! copy/part gif 1 
 ]
 
 ;--Plain Text Extension (specify text which you wish to have rendered on the image. Optional)
 readPTE: function [
	gif 	[binary!]
	index	[integer!]
 ][
 	gif: skip head gif index
 	PTE/code: to integer! copy/part gif 1 gif: skip gif 1
 	PTE/label: to integer! copy/part gif 1 gif: skip gif 1
 	PTE/blockSize: to integer! copy/part gif 1 gif: skip gif 1
 	PTE/textGridLeft: to integer! reverse copy/part gif 2 gif: skip gif 2
 	PTE/textGridTop: to integer! reverse copy/part gif 2 gif: skip gif 2
 	PTE/textGridWidth: to integer! reverse copy/part gif 2 gif: skip gif 2
 	PTE/textGridHeight: to integer! reverse copy/part gif 2 gif: skip gif 2
 	PTE/cellWidth: to integer! copy/part gif 1 gif: skip gif 1
 	PTE/cellHeight: to integer! copy/part gif 1 gif: skip gif 1
 	PTE/fgColorIndex: to integer! copy/part gif 1 gif: skip gif 1
 	PTE/plainTextData: to integer! copy/part gif 1 gif: skip gif 1
 	PTE/terminator: to integer! copy/part gif 1 gif: skip gif 1
 ]
 
 
 ;--Comment Extension (optional)
 readCEX: function [
	gif 	[binary!]
	index	[integer!]
	
 ][
 	gif: skip head gif index
 	COE/code: to integer! copy/part gif 1 gif: skip gif 1
 	COE/label: to integer! copy/part gif 1 gif: skip gif 1
 	COE/nBytes: to integer! copy/part gif 1 gif: skip gif 1
 	COE/commentData: copy []
 	repeat i COE/nBytes [
 		append COE/commentData to integer! copy/part gif 1 
 		gif: skip gif 1
 	]
 	COE/terminator: to integer! copy/part gif 1 ;gif: skip gif 1
 ]
 
 ;--Image Descriptor and image data
 readIMD: function [
	gif 	[binary!]
	index	[integer!]
 ][
 	gif: skip head gif index
 	IMD/separator: to integer! copy/part gif 1 gif: skip gif 1
 	IMD/left: to integer! reverse copy/part gif 2 gif: skip gif 2 
 	IMD/top: to integer! reverse copy/part gif 2 gif: skip gif 2 
 	IMD/width: to integer! reverse copy/part gif 2 gif: skip gif 2 
 	IMD/height: to integer! reverse copy/part gif 2 gif: skip gif 2 
 	IMD/packed: to integer!  copy/part gif 1 
 	packed: enbase copy/part gif 1 2
 	;--from packed
 	IMD/localColorTable?: IMD/packed AND 128 > 0 ; packed/1 = #"1";
 	IMD/interlaced?:  IMD/packed AND 64 >> 6 > 0 ; packed/2 = #"1";
 	IMD/colorSorted?: IMD/packed AND 32 >> 5 > 0
 	IMD/reserved: IMD/packed AND 24 >> 3 ;packed/3 =  #"1";
 	IMD/colorTableSize: IMD/packed AND 7 ;getCode copy at packed 6
 	if IMD/localColorTable? [IMD/colorTableSize: to integer! 2 ** (IMD/colorTableSize + 1)]
 ]
 
;--Get gif image descriptor and optional sub-blocks
;--offsets are stored in different blocks
;--Each image begins with an image descriptor block [10 bytes long].
;--we store the offset of each image descriptor in IMDBlock 
;--this is too long
getGifBlocks: does [
	IMDBlock: copy [] ;--Image Descriptor block
	GCEBlock: copy [] ;--Graphics Control Extension [optional]
	PTEBlock: copy [] ;--Plain Text Extension [optional]		 
	APEBlock: copy [] ;--Application Extension [optional]
	CEXBlock: copy [] ;--Comment Extension [optional]
	gFile: head gFile
	idx: 0
	tmp: copy #{}
 	While [not tail? gFile] [
 		code: gFile/1 label: gFile/2 
 		switch label [
 			  1 [tr: gFile/17]
 			249 [tr: gFile/8]
 			254 [tr: gFile/4]
 			255 [tr: gFile/17]
 		]
 		if all [code = 33 label =   1 tr = 0][append PTEBlock idx]
 		if all [code = 33 label = 249 tr = 0][append GCEBlock idx] 
 		if all [code = 33 label = 254 tr = 0][append CEXBlock idx]	 
 		if all [code = 33 label = 255 tr = 0][append APEBlock idx] 
 		
 		;--now get image Descriptor
 		if code = 44 [
 			append append clear tmp gFile/3 gFile/2 l: to integer! tmp
 			append append clear tmp gFile/5 gFile/4	t: to integer! tmp
 			append append clear tmp gFile/7 gFile/6 w: to integer! tmp
 			append append clear tmp gFile/9 gFile/8 h: to integer! tmp
 			if all [
 				w > 0 h > 0
 				l <= LSD/width t <= LSD/height 
 				w <= LSD/width h <= LSD/height
 			] [append IMDBlock idx]
 		]
 		idx: idx + 1
 		gFile: next gFile
 	]
 ]
 
  
 readImageData: func [
	gif 	[binary!]
	index	[integer!]
 ][
 	;--now we get image data values
 	trailer: 59		;--(3Bh end of file)
 	gif: skip head gif index
 	clear imageData/binaryData
 	;--lzwCode = LZW minimum code size used to decode the compressed output codes
 	imageData/lzwCode: to integer! copy/part gif 1 gif: skip gif 1 	;--LZW min code [2..8]
 	imageData/nBytes: to integer! copy/part gif 1  					;-- number of bytes[0..255]
 	;print ["BS" imageData/nBytes] 
 	;--get the first data sub-block
 	repeat i imageData/nBytes [
 		gif: skip gif 1
 		append imageData/binaryData bt: reverse enbase copy/part gif 1 2
 	]
 	;--continue to read until we reach a sub-block that says that zero bytes follow 
 	;--or that the trailer is found
 	gif: next gif
 	b: to integer! copy/part gif 1 
 	;print [ "BS" b] 
 	if b > 0 [
 		until [
 			loop b [
 				gif: skip gif 1
 				append imageData/binaryData bt: reverse enbase copy/part gif 1 2
 			]
 			gif: next gif 
 			b: to integer! copy/part gif 1
 			;print ["BS" b]
 			any [b = 0 b = trailer]	
 		]	
 	]
 	imageData/binaryData: reverse imageData/binaryData
]

;--Color Table (Global or Local)
readColorTable: function [
	gif 		[binary!]
	index		[integer!]
	size	 	[integer!]
	return: 	[block!]
][
	gif: skip head gif index
	blk: copy []
	loop size [append blk copy/part gif 3 gif: skip gif 3]
	blk
]

;-*******************LZW Decompression********************

getCode: function [
		binary-string [string!] "Short string (<= 16) of 0s and 1s"
	][
		len: length? binary-string
		len: case [
			len <= 8   [8]
			len <= 16  [16]
		]
		to integer! debase pad/with binary-string negate len #"0" 2
	]


getValue: function [
	code 	[integer!]	;--code value
	cc		[integer!]	;--clear code value
	ct		[map!]		;--codes table				
][
	either code < cc [to-block code][select ct code]
]

decodeLZW: function [
	*frame [object!]
][
	codeTable:	make map! [] 
	stream:  	copy *frame/data
	codeSize: 	*frame/minLZWCode + 1 
	clearCode: 	to-integer 2 ** *frame/minLZWCode
	endOfInput: clearCode + 1
	available: 	endOfInput + 1
	clear *frame/indices
	code: prev: none
	
	while [not empty? c: take/last/part stream codeSize][
		code: getCode copy c 
		case [
			code = clearCode  [
				codeSize: imageData/lzwCode + 1 
				available: endOfInput + 1
				prev: none
				clear codeTable
			]
			code = endOfInput [
				;new-line/skip *frame/indices true LSD/width
				;probe *frame/indices
				makeImage *frame
				return true
			]
			true [
				either selected: getValue code clearCode codeTable [
					append *frame/indices selected
					if prev [
						k: first selected
						available: endOfInput + 1 + length? codeTable
						new: append copy getValue prev clearCode codeTable k
						put codeTable available new
						if all [2 ** codeSize - 1 = available available < 4095][
							codeSize: codeSize + 1
						]
					]
				][  
					unless prev [prev: 1]
					k: first selected: getValue prev clearCode codeTable
					append *frame/indices new: append copy selected k
					put codeTable code new
					if all[2 ** codeSize - 1 = code code < 4095][
						codeSize: codeSize + 1
					]
				]
				prev: code
			]
		]
	]
]


makeImage: function [
	*frame	 [object!]
][
	rgb: 	make binary! 3 * length? *frame/indices 
	alpha: 	make binary! 1 * length? *frame/indices
	either *frame/transparent? [
		foreach idx *frame/indices [ 
			color: *frame/colorTable/(idx + 1)
			append rgb color; *frame/colorTable/(idx + 1) ;--red is 1-based
			append alpha pick [#{00} #{FF}] idx  = *frame/transparentIndex ;0 or 255
		]
		*frame/bmp: make image! reduce [*frame/size rgb alpha]
	][  
		foreach idx *frame/indices [append rgb *frame/colorTable/(idx + 1)] ;--red is 1-based
		*frame/bmp: make image! reduce [*frame/size rgb]
	]
]

comment [
	disposal method 
	0 No disposal specified. The decoder is not required to take any action.
	1 Do not dispose. The graphic is to be left in place.
	2 Restore to background color. The area used by the graphic must be restored to the background color.
	3 Restore to previous. The decoder is required to
	restore the area overwritten by the graphic with
	what was there prior to rendering the graphic.
]

renderImages: func [
	images	[block!]
][
	if LSD/hasColorTable? [
		;--we need a background image (most of gif are based on first pixel)
		if LSD/backGround >= 255 [LSD/backGround: 0]
		bgColor: white; to-tuple globalColorTable/(LSD/backGround + 1)
		bgImage: make image! reduce [as-pair LSD/width LSD/height bgColor 0]
		save %img0.png bgImage
	]
	n: length? images 
	repeat i n [
		current: images/:i
		either i = 1 [previous: current] [previous: images/(i - 1)]
		if previous/disposal = 2 [current/disposal: 2]
		switch current/disposal [
			0 [bitmap: copy current/bmp ]
			1 [bitmap: copy previous/bmp change at bitmap current/pos + 1 current/bmp]
			2 [bitmap: copy bgImage change at bitmap current/pos + 1 current/bmp]
			3 [bitmap: copy previous/bmp change at bitmap previous/pos + 1 previous/bmp]
		]
		;print [ "frame " i previous/size current/pos current/size current/disposal 
		;current/transparent? current/localColorTable?]
		current/bmp: bitmap
		img: to-word rejoin ["img" i ".png"]
		repeat i n [
			;save to-file img bitmap
			;call/shell rejoin ["open " img]
		]
	]
]

;*************************Getting frames********************


getFrame: func [
	n		[integer!]
	return:	[object!]
][
	*frame: copy frame
	unless empty? GCEBlock 		[readGCE gFile GCEBlock/(n)]	;--Graphics Control Extension
	unless empty? IMDBlock 		[readIMD gFile IMDBlock/(n)]	;--Image descriptors
	idx: IMDBlock/(n)											;--IMD position in file
	*frame/disposal: 			GCE/disposal
	*frame/userInput?:			GCE/userInput?
	*frame/transparent?:		GCE/transparentFlag?
	*frame/delay:				GCE/delay
	*frame/pos:					as-pair IMD/left IMD/top
	*frame/size:				as-pair IMD/width IMD/height
	*frame/localColorTable?:	IMD/localColorTable?
	*frame/interlaced?:			IMD/interlaced?
	*frame/sorted?:				IMD/colorSorted?
	
	offset: 13 					;--header + LSD	;--for Color Tables 
	either *frame/localColorTable? [
		idx: idx + 10 			;--length IMD
		*frame/colorTableSize:	IMD/colorTableSize
		*frame/colorTable: 		readColorTable gFile idx *frame/colorTableSize
		idx: idx + (*frame/colorTableSize * 3) ; size * triplet color
		;--image data are after Color Table
	][
		idx: idx + 10 			;--length IMD
		*frame/colorTableSize: 	LSD/colorTableSize
		*frame/colorTable: 		readColorTable gFile offset *frame/colorTableSize
		globalColorTable: 		copy *frame/colorTable
		;--image data are just after IMD
	]
	*frame/transparentIndex: GCE/colorIndex
	if *frame/sorted? [sort *frame/colorTable]
	readImageData gFile idx ;--read binary data at the calculated index
	*frame/data: copy imageData/binaryData 
	*frame/minLZWCode: imageData/lzwCode
	*frame
]
 
;--****************** Test Program ***************************
bgColor: to-tuple #{000000}
globalColorTable: none

gFile: read %dance.gif;%rotating_earth.gif;%animation.gif; %dance.gif; %animation.gif
print ["Patience Decoding File..."]
readHeader gFile 0 							;--Get Header
readLSD gFile 6 							;--Get Logical Screen Descriptor
getGifBlocks								;--Get image descriptor and optional sub-blocks
unless empty? APEBlock [
	readAPE gFile APEBlock/1
]
nbFrames: length? IMDBlock					;--Number of frames in gif file 
print ["Number of frames: "nbFrames]		
frames: copy []								;--Block of images
unless empty? frames [clear frames]
repeat i nbFrames [
	append frames getFrame i				;--get frame
	current: frames/:i						;--current frame
	decodeLZW current						;--Decode LZW compressed values
]
renderImages frames							;--View animated Gif









