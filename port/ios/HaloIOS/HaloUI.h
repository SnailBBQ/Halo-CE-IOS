#import <UIKit/UIKit.h>

/* One look for the Settings and Log screens: dark cards with a title, rows, switches, sliders, segmented
 * choices, status pills. Everything returns views to put in a vertical UIStackView. */

UIColor *HaloUIBackground(void);
UIColor *HaloUICard(void);
UIColor *HaloUIAccent(void);
UIColor *HaloUIGreen(void);
UIColor *HaloUIAmber(void);
UIColor *HaloUIRed(void);
UIColor *HaloUISecondaryText(void);

UILabel *HaloUILabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color);
/* A small grey explanation under a control. */
UILabel *HaloUINote(NSString *text);
/* A card with an optional title and its rows stacked inside. */
UIView *HaloUICardView(NSString *title, NSArray<UIView *> *rows);
/* "Name .............. value" with the value coloured. */
UIView *HaloUIValueRow(NSString *name, NSString *value, UIColor *valueColor);
UIView *HaloUISwitchRow(NSString *title, NSString *subtitle, BOOL on, void (^change)(BOOL on));
UIView *HaloUISliderRow(NSString *title, float min, float max, float value, NSString *format, void (^change)(float value));
/* A full-width button inside a card. `style`: 0 normal, 1 prominent (accent), 2 destructive. */
UIButton *HaloUIButton(NSString *title, NSInteger style, void (^tap)(UIButton *button));
UIView *HaloUISegmentRow(NSString *title, NSArray<NSString *> *options, NSInteger selected, void (^change)(NSInteger index));
/* A rounded coloured label such as "RUNNING". */
UIView *HaloUIPill(NSString *text, UIColor *color);
/* A scrolling vertical stack pinned inside `container`; returns the stack to fill. */
UIStackView *HaloUIScrollingStack(UIView *container, CGFloat spacing);
