#!/usr/local/bin/r310
REBOL [ 
] 

;--Thanks to Matthew Flickinger
;--https://www.matthewflickinger.com/lab/whatsinagif/
;--Thanks to Toomas Vooglaid for LZW decompression and constant help :)
;--Thanks to Oldes for suggesting BinCode DSL utilisation 



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
	separator: 			0 		;--byte [Always 0x2C] 44
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


;--GIF header
readHeader: function [
	gif	[object!]
][
	;x: to string! binary/read bin 6				;--Basic
	x: to string! binary/read gif [STRING-BYTES 6]  ;--same result
	either any [x = "GIF89a" x = "GIF87a"] [true] [false]
]

;--Logical Screen Descriptor
readLSD: function [
	gif	[object!]
][
	binary/read gif [w: UI16LE h: UI16LE p: UI8 b: UI8 a: UI8]
	LSD/width: w
	LSD/height: h
	LSD/packed: p
	LSD/backGround: b
	LSD/aspectRatio: a
	LSD/hasColorTable?: LSD/packed >> 7
	LSD/colorResolution: 1 + (LSD/packed AND 112 >> 4)
	LSD/colorSorted?: LSD/packed AND 8 >> 3
	LSD/colorTableSize: LSD/packed AND 7
	if LSD/aspectRatio > 0 [LSD/aspectRatio: LSD/aspectRatio + 15 / 64]
	if LSD/hasColorTable?  [LSD/colorTableSize: to integer! 2 ** (LSD/colorTableSize + 1)]
]

;--Application Extension (optional)
;--Only 1 block if present? 
readAPE: function [
	gif	[object!]
][
	binary/read gif [
		SKIP -2
		cc: UI8 ll: UI8
		bs: UI8 s: STRING-BYTES 8 ss: STRING-BYTES 3 ds: UI8 id: UI8
		l: UI8 t: UI8
	]
	binary/read gif [code: UI8 label: UI8]
	if all [code = 33 label = 255] [
			binary/read gif [
			SKIP -2
			cc: UI8 ll: UI8
			bs: UI8 s: STRING-BYTES 8 ss: STRING-BYTES 3 ds: UI8 id: UI8
			l: UI16LE t: UI8
		]	
	]
	APE/code: cc
	APE/label: ll
	APE/blockSize: bs
	APE/identifier: s
	APE/authentCode: ss
	APE/dataSize: ds
	APE/id: id
	APE/loop: l
	APE/terminator: t
]

;--Graphics Control Extension (optional)
;--This block is OPTIONAL; but at most one Graphic Control Extension may precede a graphic rendering block.
;--For animated Gifs this block is just before the Image Description block 

readGCE: function [
	gif	[object!]
][
	binary/read gif [SKIP -2 x: UI8 l: UI8 bs: UI8 p: UI8 d: UI16LE c: UI8 t: UI8]
	GCE/code: x
	GCE/label: l
	GCE/blockSize: bs
	GCE/packed: p
	GCE/delay: d
	GCE/colorIndex: c
	GCE/terminator: t
	;--from packed
	GCE/reserved: GCE/packed AND 224 >> 5
	GCE/disposal: GCE/packed AND 28 >> 2
	GCE/userInput?: GCE/packed AND 2 >> 1 > 0
	GCE/transparentFlag?: GCE/packed AND 1 > 0
]


;--Plain Text Extension (specify text which you wish to have rendered on the image. Optional)
 readPTE: function [
	gif 	[object!]
 ][
 	binary/read gif [
 		SKIP -2
 		cc: UI8 ll: UI8
 		bs: UI8 tl: UI16LE tt: UI16LE tw: UI16LE th: UI16LE
 		cw: UI8 ch: UI8 fci: UI8 bgi: UI8 pt: UI8 t: UI8
 	]
 	PTE/code: cc
 	PTE/label: ll
 	PTE/blockSize: bs
 	PTE/textGridLeft: tl
 	PTE/textGridTop: tt
 	PTE/textGridWidth: tw
 	PTE/textGridHeight: th
 	PTE/cellWidth: cw
 	PTE/cellHeight: ch
 	PTE/fgColorIndex: fci
 	PTE/bgColorIndex: bgi
 	PTE/plainTextData: pt
 	PTE/terminator: t
 ]
 
  ;--Comment Extension (optional)
 readCEX: function [
	gif 	[object!]
	
 ][
 	binary/read gif [SKIP -2 cc: UI8 ll: UI8 n: UI8]
 	CEX/code: cc
 	CEX/label: ll
 	CEX/nBytes: n
 	CEX/commentData: copy []
 	repeat i CEX/nBytes [
 		append CEX/commentData binary/read gif 1 
 	]
 	CEX/terminator: binary/read gif 1
 ]
 
 ;--Image Descriptor and image data
readIMD: function [
	gif 	[object!]
 ][
 	binary/read gif [SKIP -2 c: UI8 l: UI16LE t: UI16LE w: UI16LE h: UI16LE p: UI8]
 	IMD/separator: c
 	IMD/left: l
 	IMD/top: t
 	IMD/width: w
 	IMD/height: h 
 	IMD/packed: p
 	;--from packed
 	IMD/localColorTable?: IMD/packed AND 128 > 0 ; packed/1 = #"1";
 	IMD/interlaced?:  IMD/packed AND 64 >> 6 > 0 ; packed/2 = #"1";
 	IMD/colorSorted?: IMD/packed AND 32 >> 5 > 0
 	IMD/reserved: IMD/packed AND 24 >> 3 ;packed/3 =  #"1";
 	IMD/colorTableSize: IMD/packed AND 7 ;getCode copy at packed 6
 	if IMD/localColorTable? [IMD/colorTableSize: to integer! 2 ** (IMD/colorTableSize + 1)]
 ]
 
;--data follow each image descriptor when there is a Global Color Table
;--in case of local color table, color table follows the image Descriptor 
;--and preceeds the imageData

readImageData: function [
	gif	[object!]
][
	trailer: 59		;--(3Bh end of file)
	clear imageData/binaryData
	binary/read gif [lzw: UI8 n: UI8]
	imageData/lzwCode: lzw
	imageData/nBytes: n
	repeat i imageData/nBytes [ 
		append imageData/binaryData reverse enbase binary/read gif 1 2
	]
	binary/read gif [b: UI8]
	if b > 0 [
		until [
			loop b [
				append imageData/binaryData reverse enbase binary/read gif 1 2
			]
			binary/read gif [b: UI8]
			any [b = 0 b = trailer]	
		]
	]
	imageData/binaryData: reverse imageData/binaryData
]

readImages: function [
	gif		[object!]
	ct		[binary!]
	blk		[block!]
][
	binary/read gif [AT 1]	;--we must return to the head
	count: 1
	while [not empty?  gif/buffer][
		binary/read gif [code: BYTES 1 len: LENGTH?] 
		if len = 0 [exit]
		binary/read gif [label: BYTES 1]
		case [
			all [code = #{21} label = #{FF}] [readAPE gif]
			all [code = #{21} label = #{F9}] [readGCE gif]
			all [code = #{21} label = #{FE}] [readCEX gif] 
			all [code = #{21} label = #{01}] [readPTE gif]
			any [code = #{2C} label = #{2C}] [
				c: label
				if code = #{2C} [binary/read gif [SKIP -2 c: BYTES 1]]
				;--test values
				binary/read gif [l: UI16LE t: UI16LE w: UI16LE h: UI16LE]	
				binary/read gif [SKIP -9 UI16LE]		;--restore index
				if all [
						l <= LSD/width t <= LSD/height
						w <= LSD/width h <= LSD/height
						][
					print ["Image " form count]
					colorTable: copy ct
					readIMD gif
					if IMD/localColorTable? [
						colorTable: binary/read gif IMD/colorTableSize * 3
					]
					readImageData gif
					;probe GCE
					;probe IMD
					;--now we make the frame and add to the frame block
					*frame: copy frame
					*frame/disposal: 			GCE/disposal
					*frame/userInput?:			GCE/userInput?
					*frame/transparent?:		GCE/transparentFlag?
					*frame/delay:				GCE/delay
					*frame/pos:					as-pair IMD/left IMD/top
					*frame/size:				as-pair IMD/width IMD/height
					*frame/localColorTable?:	IMD/localColorTable?
					*frame/interlaced?:			IMD/interlaced?
					*frame/sorted?:				IMD/colorSorted?
					*frame/colorTable:			colorTable 
					*frame/transparentIndex: 	GCE/colorIndex
					*frame/data: 				copy imageData/binaryData 
					*frame/minLZWCode: 			imageData/lzwCode
					if *frame/sorted? [sort *frame/colorTable]
					append blk *frame
					count: count + 1
				]
			]		
		]
	]
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
	stream:     copy *frame/data
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

;*************************Making Image***************************
makeImage: function [
	*frame	 [object!]
][
	rgb: 	make binary! 3 * length? *frame/indices 
	alpha: 	make binary! 1 * length? *frame/indices
	b: binary *frame/colorTable
	blk: copy []
	while [not empty? b/buffer][append blk binary/read b 3] ;--block of colors
	
	either *frame/transparent? [
		foreach idx *frame/indices [ 
			append rgb blk/(idx + 1) ;--red is 1-based
			append alpha pick [#{00} #{FF}] idx  = *frame/transparentIndex ;0 or 255
		]
		*frame/bmp: make image! reduce [*frame/size rgb alpha]
	][  
		foreach idx *frame/indices [
			color: blk/(idx + 1)
			append rgb blk/(idx + 1)
		] ;--red is 1-based
		*frame/bmp: make image! reduce [*frame/size rgb]
	]
]

renderImages: func [
	images	[block!]
	/viewer
][
	if LSD/hasColorTable? [
		;--we need a background image (most of gif are based on first pixel)
		if LSD/backGround >= 255 [LSD/backGround: 0]
		b: binary gColorTable
		blk: copy []
		while [not empty? b/buffer][append blk binary/read b [rgb: TUPLE3]]
		bgColor: blk/(LSD/backGround + 1)
		bgImage: make image! reduce [as-pair LSD/width LSD/height bgColor 255];--or 0
		if viewer [
			save %img0.png bgImage
			call/shell rejoin ["open img0.png" ]
		]
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
		if viewer [
			print [ "frame " i current/pos current/size current/disposal 
			current/transparent? current/localColorTable?]
		]
		
		current/bmp: bitmap
		img: to-word rejoin ["img" i ".png"]
		if viewer [
			repeat i n [
				save to-file img bitmap
				call/shell rejoin ["open " img]
			]
		]
	]
]

