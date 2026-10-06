#import <Foundation/Foundation.h>
NSString *HaloBackupRoot(void);
NSURL *HaloBackupWork(void);
NSError *HaloBackupFailure(NSString *message);
void HaloBackupRequire(BOOL ok,NSString *message);
BOOL HaloBackupAllowed(NSString *path);
BOOL HaloBackupRegular(NSURL *url);
NSString *HaloBackupHashFile(NSURL *url);
NSString *HaloEngineIdentity(void);
NSString *HaloBuildIdentityText(void);
BOOL HaloProtectEngineChange(NSError **error);
NSURL *HaloBackupExport(unsigned mask);
NSDictionary *HaloBackupStage(NSURL *archive,NSURL *stage);
BOOL HaloApplyPendingRestore(NSError **error);
