#!/usr/local/bin/r310
REBOL [
]
;--Entry point of the binary DSL (Bincode)
do %gifBC.r3

gifFile: %../Examples/dance.gif
gif: binary read/binary gifFile

gColorTable: copy #{}
frames: copy []	
	
if readHeader gif [
	t1: now/time/precise
	readLSD gif ;probe LSD
	if LSD/hasColorTable? = 1 [gColorTable: binary/read gif LSD/colorTableSize * 3]
	readImages gif gColorTable frames
	nbFrames: length? frames
	repeat i nbFrames [
		current: frames/:i						;--current frame
		decodeLZW current						;--Decode LZW compressed values
	]
	print ["Number of frames: " nbFrames]
	renderImages/viewer frames gColorTable
	;renderImages frames gColorTable
	t2: now/time/precise
	print t2 - t1
]



