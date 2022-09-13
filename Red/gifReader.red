#!/usr/local/bin/red-view
Red [
    File: %gifReader.red
    Description: {Implements non-parse-based algorithm for gif images reading}
    Authors: "François Jouen and Toomas Vooglaid"
    Rights:  "Copyright (C) 2022 Red Foundation. All rights reserved."
    License: {
        Distributed under the Boost Software License, Version 1.0.
        See https://github.com/red/red/blob/master/BSL-License.txt
    }
    See: https://gitter.im/red/red/system?at=62d595d776cd751a2f3d7239
    Date: 10-September-2022
]

#include %gif.red

rate: none
nbFrames: 0
count: 1
bgColor: to-tuple #{000000}
globalColorTable: none

loadGif: does [
	tmpf: request-file/filter ["GIF Files" "*.gif"]
	unless none? tmpf [
		sb/text: "Patience decoding gif file..."
		clear canvas/draw
		defaultSize
		canvas/image: load tmpf
		current: none
		win/text: rejoin ["GIF Reader : " form second split-path tmpf]
		either %.gif = suffix? tmpf [gFile: read/binary tmpf]
									[sb/text: "Not a GIF!" return false]
		
		readHeader gFile 0 		;--Get Header
		readLSD gFile 6 		;--Get Logical Screen Descriptor
		getGifBlocks			;--Get image descriptors and optional sub-blocks
		unless empty? APEBlock [readAPE gFile APEBlock/1]
		nbFrames: length? IMDBlock
		frames: copy []
		repeat i nbFrames [
			sb/text: rejoin ["Decoding frame " i " / " nbFrames] 
			do-events/no-wait
			append frames getFrame i
			decodeLZW current: frames/:i 
		]
		current: frames/1
		rate: none
		if current/delay > 0 [rate: to integer! (100 / current/delay)]
		
		either current/size > 100x100 [
				canvas/size: current/size
				win/size:  max canvas/size + 20x85 380x195
				sb/size/x: max current/size/x 350
				sb/offset: as-pair 10 current/size/y + 55
			]
			[defaultSize]
		
			either nbFrames = 1 [b2/enabled?: b3/enabled?: b4/enabled?: b5/enabled?: false]
					 		[b2/enabled?: b3/enabled?: b4/enabled?: b5/enabled?: true]
		center-face win
		count: 1
		canvas/rate: none
		renderImages frames
		showFrame
	]
]

defaultSize: does [
	canvas/size: 100x100 win/size: 380x195 
	sb/offset: 10x160 sb/size: 360x25
]
;--Use draw for correctly translating image in canvas
showFrame: does [
	if count < 1 [count: nbFrames]
	if count > nbFrames [count: 1]
	current: frames/:count 
	sb/text: rejoin ["frame " count " [" current/size  " " current/pos " ] " current/disposal]
	either current/transparent? [canvas/image: bgImage][canvas/image: none]
	canvas/draw: current/plot 
	count: count + 1 
]


win: layout [title "GIF Reader" 
	b1: button "Load"	[loadGif] 
	b2: button "Start"  [canvas/rate: rate]
	b3: button "Stop"   [canvas/rate: none]
	b4: button 30 "<"	[count: count - 2 showFrame]
	b5: button 30 ">"	[showFrame] 
	button "Quit" 		[quit]
	return 
	canvas: image
		draw []
		on-time [showFrame]
	return 
	sb: base 360x25 white left middle
	do [rate: canvas/rate: none]
]
view win