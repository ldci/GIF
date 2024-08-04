#!/usr/local/bin/r3
REBOL [
]
;--This a test with new image/load 
;--Entry point of the binary DSL (Bincode)
;--We use opencv module for visualisation

do %gifBC.r3					;--for reading gif files
cv: import opencv				;--for visualisation
;gifFile: %../Examples/rotating_earth.gif
gifFile: %../Examples/dance.gif		;--use your own gif file
gif: binary read/binary gifFile	;--binary read gif file
gColorTable: copy #{}			;--for color table
frames: copy []					;--for storing all frames	
delay: 250						;--delay between 2 frames 

if readHeader gif [
	print-horizontal-line
	prin "Decoding time: "										;--use native delta-time function
	print as-yellow dt [
		readLSD gif 											;--read Logical Screen Descriptor
		if LSD/hasColorTable? = 1 [
			gColorTable: binary/read gif LSD/colorTableSize * 3	;--get Color Table entries
		]
		readImages gif gColorTable frames						;--read frames	
	] 
	nbFrames: length? frames
	print ["Number of frames:" as-yellow nbFrames]
	print as-red "ESC key to stop"
	print-horizontal-line
	i: 1
	forever [
		current: frames/:i										;--current frame (a frame object!)
		current/bmp: image/load/frame gifFile i			;--frame reading with Bincode DSL
		cv/setWindowTitle "Image" join "Frame: " i				;--window title  
		cv/imshow current/bmp									;--show current image
		wait 0.15												;--delay between frames
		if ++ i = nbFrames [i: 1]								;--count control
    	if cv/pollKey = 27 [break]								;--ESC key to stop animation 
	]
	print as-blue "Any key to close"
	print-horizontal-line
	cv/waitKey 0												;--wait for closing
]



