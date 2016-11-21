//
//  BNCStrongMatchHelper.m
//  Branch-TestBed
//
//  Created by Derrick Staten on 8/26/15.
//  Copyright © 2015 Branch Metrics. All rights reserved.
//


#import "BNCStrongMatchHelper.h"
#import "BNCConfig.h"
#import "BNCPreferenceHelper.h"
#import "BNCSystemObserver.h"
#import "BranchConstants.h"
#import <SafariServices/SafariServices.h>


@interface BNCSViewController : SFSafariViewController
@end


@implementation BNCSViewController

- (BOOL) canBecomeFirstResponder {
    NSLog(@"First!!! Responder.");
    return NO;
}

- (UIResponder*) nextResponder {
    NSLog(@"Next!! Responder.");
    return nil;
}

@end


// Stub the class for older Xcode versions, methods don't actually do anything.
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED < 90000

@implementation BNCStrongMatchHelper

+ (BNCStrongMatchHelper *)strongMatchHelper { return nil; }
- (void)createStrongMatchWithBranchKey:(NSString *)branchKey { }
- (BOOL)shouldDelayInstallRequest { return NO; }
+ (NSURL *)getUrlForCookieBasedMatchingWithBranchKey:(NSString *)branchKey redirectUrl:(NSString *)redirectUrl { return nil; }

@end

#else

NSInteger const ABOUT_30_DAYS_TIME_IN_SECONDS = 60 * 60 * 24 * 30;

@interface BNCStrongMatchHelper ()

@property (strong, nonatomic) UIWindow *primaryWindow;
@property (strong, nonatomic) BNCSViewController *safController;
@property (assign, nonatomic) BOOL requestInProgress;
@property (assign, nonatomic) BOOL shouldDelayInstallRequest;

@end

@implementation BNCStrongMatchHelper

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (BNCStrongMatchHelper *)strongMatchHelper {
    static BNCStrongMatchHelper *strongMatchHelper;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        strongMatchHelper = [[BNCStrongMatchHelper alloc] init];
    });
    
    return strongMatchHelper;
}

+ (NSURL *)getUrlForCookieBasedMatchingWithBranchKey:(NSString *)branchKey
                                         redirectUrl:(NSString *)redirectUrl {
    if (!branchKey) {
        return nil;
    }
    
    NSString *appDomainLinkURL;
    id ret = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"branch_app_domain"];
    if (ret) {
        if ([ret isKindOfClass:[NSString class]])
            appDomainLinkURL = [NSString stringWithFormat:@"https://%@", ret];
    } else {
        appDomainLinkURL = BNC_LINK_URL;
    }
    NSMutableString *urlString =
        [[NSMutableString alloc]
            initWithFormat:@"%@/_strong_match?os=%@", appDomainLinkURL, [BNCSystemObserver getOS]];
    
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper preferenceHelper];
    BOOL isRealHardwareId;
    NSString *hardwareIdType;
    NSString *hardwareId =
        [BNCSystemObserver
            getUniqueHardwareId:&isRealHardwareId
                        isDebug:preferenceHelper.isDebug
                        andType:&hardwareIdType];
    if (!hardwareId || !isRealHardwareId) {
        [preferenceHelper logWarning:@"Cannot use cookie-based matching while setDebug is enabled"];
        return nil;
    }
    
    [urlString appendFormat:@"&%@=%@", BRANCH_REQUEST_KEY_HARDWARE_ID, hardwareId];

    if (preferenceHelper.deviceFingerprintID) {
        [urlString appendFormat:@"&%@=%@", BRANCH_REQUEST_KEY_DEVICE_FINGERPRINT_ID, preferenceHelper.deviceFingerprintID];
    }

    if ([BNCSystemObserver getAppVersion]) {
        [urlString appendFormat:@"&%@=%@", BRANCH_REQUEST_KEY_APP_VERSION, [BNCSystemObserver getAppVersion]];
    }
    
    [urlString appendFormat:@"&branch_key=%@", branchKey];
    
    [urlString appendFormat:@"&sdk=ios%@", SDK_VERSION];
    
    if (redirectUrl) {
        [urlString appendFormat:@"&redirect_url=%@", [redirectUrl stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }

    return [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}

- (void)createStrongMatchWithBranchKey:(NSString *)branchKey {
    if (self.requestInProgress) {
        return;
    }

    self.requestInProgress = YES;
    
    NSDate *thirtyDaysAgo = [NSDate dateWithTimeIntervalSinceNow:-ABOUT_30_DAYS_TIME_IN_SECONDS];
    NSDate *lastCheck = [BNCPreferenceHelper preferenceHelper].lastStrongMatchDate;
    if ([lastCheck compare:thirtyDaysAgo] == NSOrderedDescending) {
        self.requestInProgress = NO;
        return;
    }
    
    self.shouldDelayInstallRequest = YES;
    [self presentSafariVCWithBranchKey:branchKey];
}

- (void)presentSafariVCWithBranchKey:(NSString *)branchKey {

    NSURL *strongMatchUrl =
        [BNCStrongMatchHelper getUrlForCookieBasedMatchingWithBranchKey:branchKey redirectUrl:nil];
    NSLog(@"Strong match URL: %@.", strongMatchUrl);
    if (!strongMatchUrl) {
        self.shouldDelayInstallRequest = NO;
        self.requestInProgress = NO;
        return;
    }
    
    Class SFSafariViewControllerClass = NSClassFromString(@"SFSafariViewController");
    if (!SFSafariViewControllerClass) {
        self.requestInProgress = NO;
        return;
    }

    // Must be on next run loop to avoid a warning
    dispatch_async(dispatch_get_main_queue(), ^{

        [[NSNotificationCenter defaultCenter]
            addObserver:self
            selector:@selector(keyWindowNotification:)
            name:UIWindowDidBecomeKeyNotification object:nil];

        [self loadViewControllerWithURL:strongMatchUrl];

        // Give enough time for Safari to load the request (optimized for 3G)
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^ {
                // Remove the window and release it's strong reference.
                // This is important to ensure that
                // applications using view controller based status bar appearance are restored.

                NSLog(@"Timer dispatch: Removing saf.");
                [self unloadViewController];
                [BNCPreferenceHelper preferenceHelper].lastStrongMatchDate = [NSDate date];
                self.requestInProgress = NO;
            }
        );
    });
}

- (void) loadViewControllerWithURL:(NSURL*)matchURL {
    if (self.primaryWindow) return;

    self.primaryWindow = [[UIApplication sharedApplication] keyWindow];

    self.safController =
        [[BNCSViewController alloc] initWithURL:matchURL];
    self.safController.delegate = (id) self;
    self.safController.view.frame = self.primaryWindow.bounds;

    [self.primaryWindow.rootViewController addChildViewController:self.safController];
    [self.primaryWindow insertSubview:self.safController.view atIndex:0];
    [self.safController didMoveToParentViewController:self.primaryWindow.rootViewController];
}

- (void) unloadViewController {
    NSLog(@"unloadViewController");
    [self.safController willMoveToParentViewController:nil];
    [self.safController.view removeFromSuperview];
    [self.safController removeFromParentViewController];
     self.safController.delegate = nil;
     self.safController = nil;
//  [self.primaryWindow makeKeyWindow];
     self.primaryWindow = nil;
}

- (void)safariViewController:(SFSafariViewController *)controller
      didCompleteInitialLoad:(BOOL)didLoadSuccessfully {
    NSLog(@"Safari Did load.");
    [self unloadViewController];
}

- (void) keyWindowNotification:(NSNotification*)notification {
    if (self.primaryWindow == [UIApplication sharedApplication].keyWindow)
        NSLog(@"Primary window became key.");
    else
        NSLog(@"Other window is key.");
}

- (BOOL)shouldDelayInstallRequest {
    return _shouldDelayInstallRequest;
}


@end

#endif
