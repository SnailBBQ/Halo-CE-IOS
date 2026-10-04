#import "HaloCheckpointEditor.h"
#import "HaloBackupArchive.h"
#import "HaloUI.h"
#include "halo_checkpoint.h"

@interface HaloCheckpointEditor : UIViewController
@property(nonatomic,strong) UIStackView *rows;
@property(nonatomic,strong) NSMutableData *checkpoint;
@property(nonatomic,copy) NSString *relativePath;
@property(nonatomic,strong) NSMutableArray<UITextField *> *fields;
@property BOOL busy;
@end
@implementation HaloCheckpointEditor
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Campaign save editor";self.view.backgroundColor=HaloUIBackground();
    self.navigationController.navigationBar.tintColor=HaloUIAccent();
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.rows=HaloUIScrollingStack(self.view,12);[self list];
}
- (void)close { if(!self.busy)[self dismissViewControllerAnimated:YES completion:nil]; }
- (void)message:(NSString *)text {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Save editor" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
- (void)clear { for(UIView *v in self.rows.arrangedSubviews){[self.rows removeArrangedSubview:v];[v removeFromSuperview];} }
- (void)list {
    [self clear];__weak typeof(self) weakSelf=self;
    [self.rows addArrangedSubview:HaloUICardView(@"Persistent checkpoints",@[
        HaloUINote(@"Edit a saved campaign checkpoint. Changes apply when you reopen Halo and resume that save. Health, shields, grenades and existing weapon ammo are finite values. Runtime cheats and new weapon creation are not checkpoint fields.")])];
    NSURL *root=[NSURL fileURLWithPath:HaloBackupRoot()];NSURL *saves=[[root URLByAppendingPathComponent:@"save/u/UDATA" isDirectory:YES] URLByResolvingSymlinksInPath];
    NSUInteger found=0;NSDirectoryEnumerator *walk=[NSFileManager.defaultManager enumeratorAtURL:saves includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey,NSURLIsRegularFileKey] options:0 errorHandler:nil];
    for(NSURL *file in walk) {
        NSNumber *link=nil;[file getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue){[walk skipDescendants];continue;}
        if(![file.lastPathComponent.lowercaseString isEqual:@"savegame.bin"]||!HaloBackupRegular(file))continue;
        NSString *path=file.URLByResolvingSymlinksInPath.path;NSString *prefix=[saves.path stringByAppendingString:@"/"];
        if(![path hasPrefix:prefix])continue;
        NSString *relative=[@"save/u/UDATA/" stringByAppendingString:[path substringFromIndex:prefix.length]];
        found++;[self.rows addArrangedSubview:HaloUIButton([NSString stringWithFormat:@"Checkpoint · %@",file.URLByDeletingLastPathComponent.lastPathComponent],0,^(UIButton *b){(void)b;[weakSelf load:relative];})];
    }
    if(!found)[self.rows addArrangedSubview:HaloUINote(@"No persistent checkpoint found. Save your campaign progress, or restore Campaign saves from a backup first.")];
}
- (void)load:(NSString *)relative {
    if(self.busy)return;self.busy=YES;self.rows.userInteractionEnabled=NO;self.navigationItem.prompt=@"Validating checkpoint…";
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSURL *url=[NSURL fileURLWithPath:[HaloBackupRoot() stringByAppendingPathComponent:relative]];
        NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
        NSMutableData *data=nil;HcView view={0};
        if(HaloBackupRegular(url)&&[attrs[NSFileSize] unsignedLongLongValue]==HC_SIZE)data=[[NSData dataWithContentsOfURL:url] mutableCopy];
        BOOL valid=data&&hc_read(data.bytes,data.length,&view);
        dispatch_async(dispatch_get_main_queue(),^{
            weakSelf.busy=NO;weakSelf.rows.userInteractionEnabled=YES;weakSelf.navigationItem.prompt=nil;
            if(!valid){[weakSelf message:@"This checkpoint is unsupported, damaged, or has no living local player. Nothing was changed. Supported saves use the current 16 MB Xbox 2342 layout."];return;}
            weakSelf.checkpoint=data;weakSelf.relativePath=relative;[weakSelf editor:view];
        });
    });
}
- (UIView *)field:(NSString *)title value:(unsigned)value maximum:(unsigned)maximum {
    UIStackView *row=[[UIStackView alloc] init];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=16;row.alignment=UIStackViewAlignmentCenter;
    UILabel *label=[UILabel new];label.text=[NSString stringWithFormat:@"%@ (0–%u)",title,maximum];label.textColor=UIColor.whiteColor;label.numberOfLines=0;
    UITextField *input=[UITextField new];input.text=[NSString stringWithFormat:@"%u",value];input.keyboardType=UIKeyboardTypeNumberPad;input.textColor=UIColor.whiteColor;input.borderStyle=UITextBorderStyleRoundedRect;input.accessibilityLabel=title;
    [input.widthAnchor constraintEqualToConstant:100].active=YES;[row addArrangedSubview:label];[row addArrangedSubview:input];[self.fields addObject:input];return row;
}
- (void)editor:(HcView)view {
    [self clear];self.fields=[NSMutableArray array];const unsigned char *b=self.checkpoint.bytes;__weak typeof(self) weakSelf=self;
    NSString *map=[NSString stringWithUTF8String:(const char *)b+4];
    [self.rows addArrangedSubview:HaloUICardView(@"Checkpoint",@[HaloUINote(map),HaloUINote(@"A recovery backup is created before replacement. Editing does not change installed map files or multiplayer. Health must be at least 1%. Ammo changes affect the two magazine records of each existing weapon; energy weapons can use a separate charge system.")])];
    [self.rows addArrangedSubview:HaloUICardView(@"Player",@[
        [self field:@"Health %" value:(unsigned)lroundf(hc_float(b,view.unit+0x90)*100) maximum:100],
        [self field:@"Shields %" value:(unsigned)lroundf(fminf(1,hc_float(b,view.unit+0x94))*100) maximum:100],
        [self field:@"Frag grenades" value:b[view.unit+0x2ce] maximum:4],
        [self field:@"Plasma grenades" value:b[view.unit+0x2cf] maximum:4]])];
    for(unsigned i=0;i<view.weapons;i++) {
        NSMutableArray *items=[NSMutableArray array];
        for(unsigned m=0;m<2;m++) {
            size_t p=view.weapon[i]+0x258+m*12;
            [items addObject:[self field:[NSString stringWithFormat:@"Magazine %u reserve",m+1] value:hc_u16(b,p+6) maximum:999]];
            [items addObject:[self field:[NSString stringWithFormat:@"Magazine %u loaded",m+1] value:hc_u16(b,p+8) maximum:999]];
        }
        [self.rows addArrangedSubview:HaloUICardView([NSString stringWithFormat:@"Existing weapon %u",i+1],items)];
    }
    [self.rows addArrangedSubview:HaloUIButton(@"Save changes for next launch",1,^(UIButton *button){(void)button;[weakSelf save:view];})];
    [self.rows addArrangedSubview:HaloUIButton(@"Choose another checkpoint",0,^(UIButton *button){(void)button;[weakSelf list];})];
}
- (void)save:(HcView)view {
    [self.view endEditing:YES];if(self.busy)return;
    unsigned values[20]={0};if(self.fields.count>20)return;
    for(NSUInteger i=0;i<self.fields.count;i++) {
        NSString *text=self.fields[i].text;NSScanner *scanner=[NSScanner scannerWithString:text?:@""];int value;
        if(![scanner scanInt:&value]||!scanner.isAtEnd||value<0||value>999){[self message:@"Enter whole numbers within the displayed ranges."];return;}values[i]=(unsigned)value;
    }
    unsigned reserve[4][2]={{0}},loaded[4][2]={{0}};
    for(unsigned i=0;i<view.weapons;i++)for(unsigned m=0;m<2;m++){reserve[i][m]=values[4+i*4+m*2];loaded[i][m]=values[5+i*4+m*2];}
    NSMutableData *edited=[self.checkpoint mutableCopy];
    if(!hc_edit(edited.mutableBytes,edited.length,&view,values[0]/100.f,values[1]/100.f,values[2],values[3],reserve,loaded)){[self message:@"The values or checkpoint are invalid. Nothing was changed."];return;}
    self.busy=YES;self.rows.userInteractionEnabled=NO;self.navigationItem.prompt=@"Preparing recovery backup…";
    NSString *relative=self.relativePath;__weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString *failure=nil;NSURL *work=HaloBackupWork();NSURL *stage=[work URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        @try {
            NSFileManager *fm=NSFileManager.defaultManager;NSURL *pending=[work URLByAppendingPathComponent:@"pending.plist"];
            HaloBackupRequire(![fm fileExistsAtPath:pending.path],@"A restore is already queued. Reopen Halo before editing another save.");
            /* Preserve a recovery archive now, in addition to the restore
             * transaction's fresh recovery copy on the next launch. */
            NSURL *recovery=HaloBackupExport(16);[NSUserDefaults.standardUserDefaults setObject:recovery.path forKey:@"HaloLastRecoveryBackup"];
            NSURL *target=[stage URLByAppendingPathComponent:relative];
            HaloBackupRequire([fm createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]&&[edited writeToURL:target atomically:YES],@"Cannot stage the edited checkpoint.");
            NSDictionary *record=@{@"path":relative,@"size":@(edited.length),@"sha256":HaloBackupHashFile(target)};
            HaloBackupRequire([@{@"format":@1,@"files":@[record]} writeToURL:[stage URLByAppendingPathComponent:@"manifest.plist"] atomically:YES],@"Cannot write the restore manifest.");
            NSURL *dest=[work URLByAppendingPathComponent:@"staged" isDirectory:YES];[fm removeItemAtURL:dest error:nil];
            HaloBackupRequire([fm moveItemAtURL:stage toURL:dest error:nil],@"Cannot queue the edited checkpoint.");
            HaloBackupRequire([@{@"mask":@16} writeToURL:pending atomically:YES],@"Cannot queue the checkpoint restore.");
        } @catch(NSException *e){failure=e.reason;}
        @finally {[NSFileManager.defaultManager removeItemAtURL:stage error:nil];}
        dispatch_async(dispatch_get_main_queue(),^{weakSelf.busy=NO;weakSelf.rows.userInteractionEnabled=YES;weakSelf.navigationItem.prompt=nil;[weakSelf message:failure?:@"Checkpoint changes queued. Quit and reopen Halo, then resume this campaign save. Your recovery backup is available in Manage backups."];});
    });
}
@end
UIViewController *HaloCheckpointEditorController(void) { return [[UINavigationController alloc] initWithRootViewController:[HaloCheckpointEditor new]]; }
