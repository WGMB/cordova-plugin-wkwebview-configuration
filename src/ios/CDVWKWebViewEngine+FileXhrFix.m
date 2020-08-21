//
//  CDVWKWebViewEngine+FileXhrFix.m
//  HelloCordova
//
//  Created by Connor Pearson on 2/9/17.
//
//

#import "CDVWKWebViewEngine+FileXhrFix.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation CDVWebViewEngine (FileXhrFix)
+ (void)load {
    SEL selector = NSSelectorFromString(@"createConfigurationFromSettings:");
    Method originalMethod = class_getInstanceMethod([CDVWebViewEngine class], selector);
    IMP originalImp = method_getImplementation(originalMethod);
    typedef WKWebViewConfiguration* (*send_type)(id, SEL , NSDictionary*);
    send_type originalImpSend = (send_type)originalImp;
    
    IMP newImp = imp_implementationWithBlock(^(id _self, NSDictionary* settings){
        // Get the original configuration
        WKWebViewConfiguration* configuration = originalImpSend(_self, selector, settings);

        // allow access to file api
        @try {
            [configuration.preferences setValue:@TRUE forKey:@"allowFileAccessFromFileURLs"];
        }
        @catch (NSException *exception) {}
        
        @try {
            [configuration setValue:@TRUE forKey:@"allowUniversalAccessFromFileURLs"];
        }
        @catch (NSException *exception) {}
        
        return configuration;
    });
    
    method_setImplementation(originalMethod, newImp);
}

- (void) webView: (WKWebView *) webView decidePolicyForNavigationAction: (WKNavigationAction*) navigationAction decisionHandler: (void (^)(WKNavigationActionPolicy)) decisionHandler
{
    NSURL* url = [navigationAction.request URL];
    CDVViewController* vc = (CDVViewController*)self.viewController;

	NSLog(@"-->%@",url);

	if([[ url scheme] isEqualToString:@"http"] || [[ url scheme] isEqualToString:@"https"]) {
		NSURL *url = navigationAction.request.URL;
		UIApplication *app = [UIApplication sharedApplication];
		if ([app canOpenURL:url]) {
			[app openURL:url];
		}
		return decisionHandler(NO);
	}

    /*
     * Give plugins the chance to handle the url
     */
    BOOL anyPluginsResponded = NO;
    BOOL shouldAllowRequest = NO;

    for (NSString* pluginName in vc.pluginObjects) {
        CDVPlugin* plugin = [vc.pluginObjects objectForKey:pluginName];
        SEL selector = NSSelectorFromString(@"shouldOverrideLoadWithRequest:navigationType:");
        if ([plugin respondsToSelector:selector]) {
            anyPluginsResponded = YES;
            // https://issues.apache.org/jira/browse/CB-12497
            int navType = (int)navigationAction.navigationType;
            shouldAllowRequest = (((BOOL (*)(id, SEL, id, int))objc_msgSend)(plugin, selector, navigationAction.request, navType));
            if (!shouldAllowRequest) {
                break;
            }
        }
    }

    if (anyPluginsResponded) {
        return decisionHandler(shouldAllowRequest);
    }

    /*
     * Handle all other types of urls (tel:, sms:), and requests to load a url in the main webview.
     */
    BOOL shouldAllowNavigation = [self defaultResourcePolicyForURL:url];
    if (shouldAllowNavigation) {
        return decisionHandler(YES);
    } else {
        [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:url]];
    }

    return decisionHandler(NO);
}

- (BOOL)defaultResourcePolicyForURL:(NSURL*)url
{
    // all file:// urls are allowed
    if ([url isFileURL]) {
        return YES;
    }

    return NO;
}

@end
