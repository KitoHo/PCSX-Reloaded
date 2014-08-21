//
//  PcsxrMemoryObject.m
//  Pcsxr
//
//  Created by Charles Betts on 11/23/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PcsxrMemoryObject.h"

NSString *const memoryAnimateTimerKey = @"PCSXR Memory Card Image Animate";

@interface PcsxrMemoryObject ()
@property (readwrite, strong) NSString *englishName;
@property (readwrite, strong) NSString *sjisName;
@property (readwrite, strong) NSString *memName;
@property (readwrite, strong) NSString *memID;
@property (readwrite) uint8_t startingIndex;
@property (readwrite) uint8_t blockSize;

@property (readwrite, nonatomic) NSInteger memImageIndex;
@property (readwrite, strong) NSArray *memoryCardImages;
@property (readwrite) PCSXRMemFlags flagNameIndex;
@end

@implementation PcsxrMemoryObject

+ (NSArray *)imagesFromMcd:(McdBlock *)block
{
	NSMutableArray *imagesArray = [[NSMutableArray alloc] initWithCapacity:block->IconCount];
	for (int i = 0; i < block->IconCount; i++) {
		NSImage *memImage;
		@autoreleasepool {
			NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:16 pixelsHigh:16 bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
			
			short *icon = block->Icon;
			
			int x, y, c, v, r, g, b;
			for (v = 0; v < 256; v++) {
				x = (v % 16);
				y = (v / 16);
				c = icon[(i * 256) + v];
				r = (c & 0x001f) << 3;
				g = ((c & 0x03e0) >> 5) << 3;
				b = ((c & 0x7c00) >> 10) << 3;
				[imageRep setColor:[NSColor colorWithCalibratedRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0] atX:x y:y];
			}
			memImage = [[NSImage alloc] init];
			[memImage addRepresentation:imageRep];
			[memImage setSize:NSMakeSize(32, 32)];
		}
		[imagesArray addObject:memImage];
	}
	return [NSArray arrayWithArray:imagesArray];
}

static NSString *MemLabelDeleted;
static NSString *MemLabelFree;
static NSString *MemLabelUsed;
static NSString *MemLabelLink;
static NSString *MemLabelEndLink;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSBundle *mainBundle = [NSBundle mainBundle];
		MemLabelDeleted = [[mainBundle localizedStringForKey:@"MemCard_Deleted" value:@"" table:nil] copy];
		MemLabelFree = [[mainBundle localizedStringForKey:@"MemCard_Free" value:@"" table:nil] copy];
		MemLabelUsed = [[mainBundle localizedStringForKey:@"MemCard_Used" value:@"" table:nil] copy];
		MemLabelLink = [[mainBundle localizedStringForKey:@"MemCard_Link" value:@"" table:nil] copy];
		MemLabelEndLink = [[mainBundle localizedStringForKey:@"MemCard_EndLink" value:@"" table:nil] copy];
	});
}

- (NSImage*)memoryImageAtIndex:(NSInteger)idx
{
	if (memImageIndex == -1 || idx > self.memIconCount) {
		return [PcsxrMemoryObject blankImage];
	}
	return memImages[idx];
}

+ (NSString*)memoryLabelFromFlag:(PCSXRMemFlags)flagNameIndex
{
	switch (flagNameIndex) {
		default:
		case memFlagFree:
			return MemLabelFree;
			break;
			
		case memFlagEndLink:
			return MemLabelEndLink;
			break;
			
		case memFlagLink:
			return MemLabelLink;
			break;
			
		case memFlagUsed:
			return MemLabelUsed;
			break;
			
		case memFlagDeleted:
			return MemLabelDeleted;
			break;
	}
}

+ (NSImage *)blankImage
{
	static NSImage *imageBlank = nil;
	if (imageBlank == nil) {
		NSRect imageRect = NSMakeRect(0, 0, 16, 16);
		imageBlank = [[NSImage alloc] initWithSize:imageRect.size];
		[imageBlank lockFocus];
		[[NSColor blackColor] set];
		[NSBezierPath fillRect:imageRect];
		[imageBlank unlockFocus];
	}
	return [imageBlank copy];
}

+ (PCSXRMemFlags)memFlagsFromBlockFlags:(unsigned char)blockFlags
{
	if ((blockFlags & 0xF0) == 0xA0) {
		if ((blockFlags & 0xF) >= 1 && (blockFlags & 0xF) <= 3)
			return memFlagDeleted;
		else
			return memFlagFree;
	} else if ((blockFlags & 0xF0) == 0x50) {
		if ((blockFlags & 0xF) == 0x1)
			return memFlagUsed;
		else if ((blockFlags & 0xF) == 0x2)
			return memFlagLink;
		else if ((blockFlags & 0xF) == 0x3)
			return memFlagEndLink;
	} else
		return memFlagFree;
	
	//Xcode complains unless we do this...
	NSLog(@"Unknown flag %x", blockFlags);
	return memFlagFree;
}

- (instancetype)initWithMcdBlock:(McdBlock *)infoBlock startingIndex:(uint8_t)startIdx size:(uint8_t)memSize
{
	if (self = [super init]) {
		self.startingIndex = startIdx;
		self.blockSize = memSize;
		self.flagNameIndex = [PcsxrMemoryObject memFlagsFromBlockFlags:infoBlock->Flags];
		if (self.flagNameIndex == memFlagFree) {
			self.memoryCardImages = @[];
			self.memImageIndex = -1;
			self.englishName = self.sjisName = @"Free block";
			self.memID = self.memName = @"";
		} else {
			self.englishName = @(infoBlock->Title);
			self.sjisName = [NSString stringWithCString:infoBlock->sTitle encoding:NSShiftJISStringEncoding];
			
			if ([englishName isEqualToString:sjisName]) {
#if 0
				if (![englishName isEqualToString:@""])
					NSLog(@"English name and sjis name are the same: %@. Replacing the sjis string with the English string.", englishName);
#endif
				self.sjisName = self.englishName;
			}
			@autoreleasepool {
				self.memoryCardImages = [PcsxrMemoryObject imagesFromMcd:infoBlock];
			}
			
			if ([memImages count] == 0) {
				self.memImageIndex = -1;
			} else if ([memImages count] == 1) {
				self.memImageIndex = 0;
			} else {
				self.memImageIndex = 0;
				[[NSNotificationCenter defaultCenter] addObserverForName:memoryAnimateTimerKey object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
					NSInteger index = memImageIndex;
					if (++index >= [memImages count]) {
						index = 0;
					}
					self.memImageIndex = index;
				}];
			}
			self.memName = @(infoBlock->Name);
			self.memID = @(infoBlock->ID);
		}
	}
	return self;
}

#pragma mark - Property Synthesizers
@synthesize englishName;
@synthesize sjisName;
@synthesize memImageIndex;
- (void)setMemImageIndex:(NSInteger)theMemImageIndex
{
	[self willChangeValueForKey:@"memImage"];
	memImageIndex = theMemImageIndex;
	[self didChangeValueForKey:@"memImage"];
}

@synthesize memName;
@synthesize memID;
@synthesize memoryCardImages = memImages;
@synthesize flagNameIndex;
@synthesize blockSize;
@synthesize startingIndex;

#pragma mark Non-synthesized Properties
- (NSUInteger)memIconCount
{
	return [memImages count];
}

- (NSImage*)firstMemImage
{
	if (memImageIndex == -1) {
		return [PcsxrMemoryObject blankImage];
	}
	return memImages[0];
}

- (NSImage*)memImage
{
	if (memImageIndex == -1) {
		return [PcsxrMemoryObject blankImage];
	}
	return memImages[memImageIndex];
}

- (NSString*)flagName
{
	return [PcsxrMemoryObject memoryLabelFromFlag:flagNameIndex];
}

static inline void SetupAttrStr(NSMutableAttributedString *mutStr, NSColor *txtclr)
{
	NSRange wholeStrRange = NSMakeRange(0, mutStr.string.length);
	[mutStr addAttribute:NSFontAttributeName value:[NSFont userFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]] range:wholeStrRange];
	[mutStr addAttribute:NSForegroundColorAttributeName value:txtclr range:wholeStrRange];
	[mutStr setAlignment:NSCenterTextAlignment range:wholeStrRange];
}

- (NSAttributedString*)attributedFlagName
{
	static NSAttributedString *attribMemLabelDeleted;
	static NSAttributedString *attribMemLabelFree;
	static NSAttributedString *attribMemLabelUsed;
	static NSAttributedString *attribMemLabelLink;
	static NSAttributedString *attribMemLabelEndLink;
	
	static dispatch_once_t attrStrSetOnceToken;
	dispatch_once(&attrStrSetOnceToken, ^{
		NSMutableAttributedString *tmpStr = [[NSMutableAttributedString alloc] initWithString:MemLabelFree];
		SetupAttrStr(tmpStr, [NSColor greenColor]);
		attribMemLabelFree = [tmpStr copy];
		
#ifdef DEBUG
		tmpStr = [[NSMutableAttributedString alloc] initWithString:MemLabelEndLink];
		SetupAttrStr(tmpStr, [NSColor blueColor]);
		attribMemLabelEndLink = [tmpStr copy];
		
		tmpStr = [[NSMutableAttributedString alloc] initWithString:MemLabelLink];
		SetupAttrStr(tmpStr, [NSColor blueColor]);
		attribMemLabelLink = [tmpStr copy];
		
		tmpStr = [[NSMutableAttributedString alloc] initWithString:MemLabelUsed];
		SetupAttrStr(tmpStr, [NSColor controlTextColor]);
		attribMemLabelUsed = [tmpStr copy];
#else
		tmpStr = [[NSMutableAttributedString alloc] initWithString:@"Multi-save"];
		SetupAttrStr(tmpStr, [NSColor blueColor]);
		attribMemLabelEndLink = [tmpStr copy];
		
		//tmpStr = [[NSMutableAttributedString alloc] initWithString:@"Multi-save"];
		//SetupAttrStr(tmpStr, [NSColor blueColor]);
		//attribMemLabelLink = [tmpStr copy];
		//RELEASEOBJ(tmpStr);
		attribMemLabelLink = attribMemLabelEndLink;
		
		//display nothing
		attribMemLabelUsed = [[NSAttributedString alloc] initWithString:@""];
#endif
		
		tmpStr = [[NSMutableAttributedString alloc] initWithString:MemLabelDeleted];
		SetupAttrStr(tmpStr, [NSColor redColor]);
		attribMemLabelDeleted = [tmpStr copy];
	});
	
	switch (flagNameIndex) {
		default:
		case memFlagFree:
			return attribMemLabelFree;
			break;
			
		case memFlagEndLink:
			return attribMemLabelEndLink;
			break;
			
		case memFlagLink:
			return attribMemLabelLink;
			break;
			
		case memFlagUsed:
			return attribMemLabelUsed;
			break;
			
		case memFlagDeleted:
			return attribMemLabelDeleted;
			break;
	}
}

- (BOOL)isBiggerThanOne
{
	if (flagNameIndex == memFlagFree) {
		//Always show the size of the free blocks
		return YES;
	} else {
		return blockSize != 1;
	}
}

#pragma mark -

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ (%@): Name: %@ ID: %@, type: %@ start: %i size: %i", englishName, sjisName, memName, memID, self.flagName, startingIndex, blockSize];
}

@end
