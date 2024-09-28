//
//  IASKAppSettingsWebViewController.h
//  InAppSettingsKit
//
//  Copyright (c) 2010:
//  Luc Vandal, Edovia Inc., http://www.edovia.com
//  Ortwin Gentz, FutureTap GmbH, http://www.futuretap.com
//  All rights reserved.
// 
//  It is appreciated but not required that you give credit to Luc Vandal and Ortwin Gentz, 
//  as the original authors of this code. You can give credit in a blog post, a tweet or on 
//  a info page of your app. Also, the original authors appreciate letting them know if you use this code.
//
//  This code is licensed under the BSD license that is available at: http://www.opensource.org/licenses/bsd-license.php
//

#import "IASKAppSettingsWebViewController.h"
#import "IASKSettingsReader.h"
#import "IASKSpecifier.h"

@interface IASKAppSettingsWebViewController()
@property (nullable, nonatomic, strong, readwrite) WKWebView *webView;
@property (nonatomic, strong, readwrite) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, strong, readwrite) UIProgressView *progressView;
@property (nonatomic, strong, readwrite) NSURL *url;
@property (nonatomic, readwrite) BOOL showProgress;
@property (nonatomic, readwrite) BOOL hideBottomBar;
@end

@implementation IASKAppSettingsWebViewController

- (id)initWithFile:(NSString*)urlString specifier:(IASKSpecifier*)specifier {
    if ((self = [super init])) {
        NSURL *url = [NSURL URLWithString:urlString];
		if (!url.scheme) {
			NSString *path = [NSBundle.mainBundle pathForResource:urlString.stringByDeletingPathExtension 
                                                           ofType:urlString.pathExtension];
			url = path ? [NSURL fileURLWithPath:path] : nil;
        }
		if (!url) {
			return nil;
		}
		self.url = url;
        
        // Optional features (Booleans default to `NO` when not in the *.plist):
        self.customTitle = [specifier localizedObjectForKey:kIASKChildTitle];
        self.title = self.customTitle ? : specifier.title;
        self.showProgress = [[specifier.specifierDict objectForKey:kIASKWebViewShowProgress] boolValue];
        self.hideBottomBar = [[specifier.specifierDict objectForKey:kIASKWebViewHideBottomBar] boolValue];
	}
	return self;
}

- (void)loadView {
    // Initialize the webView
    self.webView = [[WKWebView alloc] init];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO; // Disable autoresizing mask for layout constraints
    self.webView.navigationDelegate = self;
        
    // Set up the main view
    self.view = [[UIView alloc] init];
    
    // Ensure to define the default background color for the margins, otherwise those will be black:
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        // Fallback on earlier versions:
        self.view.backgroundColor = [UIColor whiteColor];
    }
    [self.view addSubview:self.webView];
    
    // Create constraints to match the entire safe area layout:
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor]
    ]];
    
    // Define default activity indicator:
    self.activityIndicatorView = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 40, 20)];
    self.activityIndicatorView.hidesWhenStopped = YES;
#if TARGET_OS_MACCATALYST || (defined(TARGET_OS_VISION) && TARGET_OS_VISION)
    activityIndicatorView.activityIndicatorViewStyle = UIActivityIndicatorViewStyleMedium;
#else
    if (@available(iOS 13.0, *)) {
        self.activityIndicatorView.activityIndicatorViewStyle = UIActivityIndicatorViewStyleMedium;
    } else {
        // Fallback on earlier versions:
        self.activityIndicatorView.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhite;
    }
#endif
    
    // Initialize UIProgressView:
    self.progressView = [[UIProgressView alloc] init];
    self.progressView.progress = 0.0;
    self.progressView.hidden = YES; // Will be shown by observer when enabled
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO; // Disable autoresizing mask for layout constraints
    [self.view addSubview:self.progressView];
    
    // Create constraints to set it to the top of the webView:
    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.topAnchor constraintEqualToAnchor:self.webView.topAnchor],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.webView.leadingAnchor],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.webView.trailingAnchor]
    ]];
    
    // Enable progress observer depending on `IASKWebViewShowProgress`:
    if (self.showProgress) {
        // Observe the `estimatedProgress` property of WKWebView:
        [self.webView addObserver:self
                       forKeyPath:@"estimatedProgress"
                          options:NSKeyValueObservingOptionNew
                          context:nil];
    }
    
    if (self.hideBottomBar) {
        // Hide the tab bar when this view is pushed:
        self.hidesBottomBarWhenPushed = YES;
    }
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	
    // When optional Progress View is not used, assign default indicator to Navigation Bar and start:
    if (!self.showProgress) {
        [self.activityIndicatorView startAnimating];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.activityIndicatorView];
    }
    
    // Load URL:
	[self.webView loadRequest:[NSURLRequest requestWithURL:self.url]];
}


#pragma mark - Helper methods

- (void)handleMailto:(NSURL*)mailToURL NS_EXTENSION_UNAVAILABLE("Uses APIs (i.e UIApplication.sharedApplication) not available for use in App Extensions.") {
    NSArray *rawURLparts = [[mailToURL resourceSpecifier] componentsSeparatedByString:@"?"];
    if (rawURLparts.count > 2 || !MFMailComposeViewController.canSendMail) {
        return; // invalid URL or can't send mail
    }

    MFMailComposeViewController *mailViewController = [[MFMailComposeViewController alloc] init];
    mailViewController.mailComposeDelegate = self;

    NSMutableArray *toRecipients = [NSMutableArray array];
    NSString *defaultRecipient = [rawURLparts objectAtIndex:0];
    if (defaultRecipient.length) {
        [toRecipients addObject:defaultRecipient];
    }

    if (rawURLparts.count == 2) {
        NSString *queryString = [rawURLparts objectAtIndex:1];

        NSArray *params = [queryString componentsSeparatedByString:@"&"];
        for (NSString *param in params) {
            NSArray *keyValue = [param componentsSeparatedByString:@"="];
            if (keyValue.count != 2) {
                continue;
            }
            NSString *key = [[keyValue objectAtIndex:0] lowercaseString];
            NSString *value = [keyValue objectAtIndex:1];

            value =  CFBridgingRelease(CFURLCreateStringByReplacingPercentEscapes(kCFAllocatorDefault,
                                                                                  (CFStringRef)value,
                                                                                  CFSTR("")));

            if ([key isEqualToString:@"subject"]) {
                [mailViewController setSubject:value];
            }

            if ([key isEqualToString:@"body"]) {
                [mailViewController setMessageBody:value isHTML:NO];
            }

            if ([key isEqualToString:@"to"]) {
                [toRecipients addObjectsFromArray:[value componentsSeparatedByString:@","]];
            }

            if ([key isEqualToString:@"cc"]) {
                NSArray *recipients = [value componentsSeparatedByString:@","];
                [mailViewController setCcRecipients:recipients];
            }

            if ([key isEqualToString:@"bcc"]) {
                NSArray *recipients = [value componentsSeparatedByString:@","];
                [mailViewController setBccRecipients:recipients];
            }
        }
    }

    [mailViewController setToRecipients:toRecipients];

    mailViewController.navigationBar.barStyle = self.navigationController.navigationBar.barStyle;
    mailViewController.navigationBar.tintColor = self.navigationController.navigationBar.tintColor;
    mailViewController.navigationBar.titleTextAttributes =  self.navigationController.navigationBar.titleTextAttributes;
#if !TARGET_OS_MACCATALYST && (!defined(TARGET_OS_VISION) || !TARGET_OS_VISION)
    UIStatusBarStyle savedStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
#endif
    [self presentViewController:mailViewController animated:YES completion:^{
#if !TARGET_OS_MACCATALYST && (!defined(TARGET_OS_VISION) || !TARGET_OS_VISION)
        [UIApplication sharedApplication].statusBarStyle = savedStatusBarStyle;
#endif
    }];
}

// This method is called whenever the observed properties change
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        // Update the progress view with the current progress:
        self.progressView.progress = self.webView.estimatedProgress;
        
        // Hide the progress bar when loading is complete:
        if (self.webView.estimatedProgress >= 1.0) {
            [self.progressView setHidden:YES];
        }
        else {
            [self.progressView setHidden:NO];
        }
    }
}


#pragma mark - WKNavigationDelegate

// Tells the delegate that navigation from the main frame has started.
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    // Reset:
    self.progressView.progress = 0.0;
}

// Tells the delegate that navigation is complete.
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // Stop and hide default indicator and update title:
    [self.activityIndicatorView stopAnimating];
	[self.webView evaluateJavaScript:@"document.title" completionHandler:^(id result, NSError *error) {
		NSString* title = (NSString*)result;
		self.title = self.customTitle.length ? self.customTitle : title;
	}];
}

// Asks the delegate for permission to navigate to new content based on the specified action information.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler NS_EXTENSION_UNAVAILABLE("Uses APIs (i.e UIApplication.sharedApplication) not available for use in App Extensions.") {
	NSURL* newURL = navigationAction.request.URL;

	// intercept mailto URL and send it to an in-app Mail compose view instead
	if ([[newURL scheme] isEqualToString:@"mailto"]) {
		[self handleMailto:newURL];
		decisionHandler(WKNavigationActionPolicyCancel);
		return;
	}

	// open inline if host is the same, otherwise, pass to the system
	if (![newURL host] || ![self.url host] || [[newURL host] isEqualToString:(NSString *)[self.url host]]) {
		decisionHandler(WKNavigationActionPolicyAllow);
		return;
	}

	[UIApplication.sharedApplication openURL:newURL 
                                     options:@{}
                           completionHandler:nil];
	decisionHandler(WKNavigationActionPolicyCancel);
}


#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {
    [self dismissViewControllerAnimated:YES 
                             completion:nil];
}

@end
