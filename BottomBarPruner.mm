#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Configuration

static NSString * const BBPConfigFileName = @"BottomBarPruner.plist";

@interface BBPConfiguration : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSArray<NSString *> *keepTitles;
@property (nonatomic, copy) NSArray<NSString *> *hiddenTitles;
@property (nonatomic, copy) NSArray<NSString *> *keepAccessibilityIdentifiers;
@property (nonatomic, copy) NSArray<NSString *> *hiddenAccessibilityIdentifiers;
@property (nonatomic, copy) NSArray<NSNumber *> *keepIndexes;
@property (nonatomic, copy) NSArray<NSNumber *> *hiddenIndexes;
@property (nonatomic, copy) NSArray<NSString *> *targetBundleIDs;
@end

@implementation BBPConfiguration
@end

static NSArray *BBPStringArray(NSDictionary *dictionary, NSString *key) {
    id value = dictionary[key];
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray *result = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0) {
            [result addObject:item];
        }
    }
    return [result copy];
}

static NSArray *BBPNumberArray(NSDictionary *dictionary, NSString *key) {
    id value = dictionary[key];
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray *result = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        if ([item respondsToSelector:@selector(integerValue)]) {
            [result addObject:@([item integerValue])];
        }
    }
    return [result copy];
}

static NSDictionary *BBPReadDictionaryAtPath(NSString *path) {
    if (path.length == 0) {
        return nil;
    }
    NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:path];
    return [dictionary isKindOfClass:[NSDictionary class]] ? dictionary : nil;
}

static NSDictionary *BBPLoadRawConfiguration(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"";
    NSArray<NSString *> *paths = @[
        [bundle pathForResource:@"BottomBarPruner" ofType:@"plist"] ?: @"",
        [documentsPath stringByAppendingPathComponent:BBPConfigFileName],
        [[bundle.bundlePath stringByAppendingPathComponent:@"Library/Preferences"] stringByAppendingPathComponent:BBPConfigFileName]
    ];

    for (NSString *path in paths) {
        NSDictionary *dictionary = BBPReadDictionaryAtPath(path);
        if (dictionary) {
            return dictionary;
        }
    }
    return nil;
}

static BBPConfiguration *BBPLoadConfiguration(void) {
    NSDictionary *raw = BBPLoadRawConfiguration();
    if (!raw) {
        raw = @{
            @"Enabled": @YES,
            @"KeepTabBarItemTitles": @[ @"??", @"??" ],
            @"KeepTabBarItemIndexes": @[ @2, @4 ],
            @"TargetBundleIDs": @[]
        };
    }

    BBPConfiguration *configuration = [[BBPConfiguration alloc] init];
    configuration.enabled = raw[@"Enabled"] ? [raw[@"Enabled"] boolValue] : YES;
    configuration.keepTitles = BBPStringArray(raw, @"KeepTabBarItemTitles");
    configuration.hiddenTitles = BBPStringArray(raw, @"HiddenTabBarItemTitles");
    configuration.keepAccessibilityIdentifiers = BBPStringArray(raw, @"KeepTabBarItemAccessibilityIdentifiers");
    configuration.hiddenAccessibilityIdentifiers = BBPStringArray(raw, @"HiddenTabBarItemAccessibilityIdentifiers");
    configuration.keepIndexes = BBPNumberArray(raw, @"KeepTabBarItemIndexes");
    configuration.hiddenIndexes = BBPNumberArray(raw, @"HiddenTabBarItemIndexes");
    configuration.targetBundleIDs = BBPStringArray(raw, @"TargetBundleIDs");
    return configuration;
}

static BBPConfiguration *BBPConfigurationShared(void) {
    static BBPConfiguration *configuration;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        configuration = BBPLoadConfiguration();
    });
    return configuration;
}

static BOOL BBPIsCurrentBundleAllowed(void) {
    BBPConfiguration *configuration = BBPConfigurationShared();
    if (!configuration || !configuration.enabled) {
        return NO;
    }
    if (configuration.targetBundleIDs.count == 0) {
        return YES;
    }
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";
    return [configuration.targetBundleIDs containsObject:bundleID];
}

#pragma mark - Matching

static BOOL BBPArrayContainsIndex(NSArray<NSNumber *> *indexes, NSUInteger index) {
    for (NSNumber *number in indexes) {
        if (number.integerValue == (NSInteger)index) {
            return YES;
        }
    }
    return NO;
}

static BOOL BBPArrayContainsString(NSArray<NSString *> *values, NSString *candidate) {
    if (candidate.length == 0) {
        return NO;
    }
    for (NSString *value in values) {
        if ([value isEqualToString:candidate]) {
            return YES;
        }
    }
    return NO;
}

static BOOL BBPShouldKeepItem(UITabBarItem *item, NSUInteger index) {
    BBPConfiguration *configuration = BBPConfigurationShared();
    if (!configuration) {
        return YES;
    }

    NSString *title = item.title ?: @"";
    NSString *identifier = item.accessibilityIdentifier ?: @"";
    BOOL hasKeepRules = configuration.keepTitles.count > 0 || configuration.keepAccessibilityIdentifiers.count > 0 || configuration.keepIndexes.count > 0;
    if (hasKeepRules) {
        return BBPArrayContainsString(configuration.keepTitles, title)
            || BBPArrayContainsString(configuration.keepAccessibilityIdentifiers, identifier)
            || BBPArrayContainsIndex(configuration.keepIndexes, index);
    }

    BOOL hidden = BBPArrayContainsString(configuration.hiddenTitles, title)
        || BBPArrayContainsString(configuration.hiddenAccessibilityIdentifiers, identifier)
        || BBPArrayContainsIndex(configuration.hiddenIndexes, index);
    return !hidden;
}

static BOOL BBPShouldKeepViewController(UIViewController *viewController, NSUInteger index) {
    return BBPShouldKeepItem(viewController.tabBarItem, index);
}

static NSArray<UIViewController *> *BBPFilteredViewControllers(NSArray<UIViewController *> *viewControllers) {
    if (!BBPIsCurrentBundleAllowed() || viewControllers.count == 0) {
        return viewControllers;
    }

    NSMutableArray<UIViewController *> *filtered = [NSMutableArray array];
    [viewControllers enumerateObjectsUsingBlock:^(UIViewController *controller, NSUInteger index, BOOL *stop) {
        if (BBPShouldKeepViewController(controller, index)) {
            [filtered addObject:controller];
        }
    }];

    // Never leave a tab bar with zero controllers: preserve the app's original UI instead.
    return filtered.count > 0 ? [filtered copy] : viewControllers;
}

static NSArray<UITabBarItem *> *BBPFilteredTabBarItems(NSArray<UITabBarItem *> *items) {
    if (!BBPIsCurrentBundleAllowed() || items.count == 0) {
        return items;
    }

    NSMutableArray<UITabBarItem *> *filtered = [NSMutableArray array];
    [items enumerateObjectsUsingBlock:^(UITabBarItem *item, NSUInteger index, BOOL *stop) {
        if (BBPShouldKeepItem(item, index)) {
            [filtered addObject:item];
        }
    }];
    return filtered.count > 0 ? [filtered copy] : items;
}

#pragma mark - Swizzling

static void BBPSwizzle(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) {
        return;
    }
    method_exchangeImplementations(originalMethod, replacementMethod);
}

@interface UITabBarController (BBPInjected)
@end

@implementation UITabBarController (BBPInjected)

- (void)bbp_setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    NSArray *filtered = BBPFilteredViewControllers(viewControllers);
    [self bbp_setViewControllers:filtered animated:animated];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self bbp_applyCurrentConfiguration];
    });
}

- (void)bbp_viewDidLoad {
    [self bbp_viewDidLoad];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self bbp_applyCurrentConfiguration];
    });
}

- (void)bbp_viewDidAppear:(BOOL)animated {
    [self bbp_viewDidAppear:animated];
    [self bbp_applyCurrentConfiguration];
}

- (void)bbp_viewDidLayoutSubviews {
    [self bbp_viewDidLayoutSubviews];
    [self bbp_applyCurrentConfiguration];
}

- (void)bbp_applyCurrentConfiguration {
    if (!BBPIsCurrentBundleAllowed()) {
        return;
    }
    NSArray<UIViewController *> *current = self.viewControllers;
    NSArray<UIViewController *> *filtered = BBPFilteredViewControllers(current);
    if (filtered.count != current.count) {
        UIViewController *selected = self.selectedViewController;
        [self bbp_setViewControllers:filtered animated:NO];
        if (selected && [filtered containsObject:selected]) {
            self.selectedViewController = selected;
        } else if (filtered.firstObject) {
            self.selectedViewController = filtered.firstObject;
        }
    }
}

@end

@interface UITabBar (BBPInjected)
@end

@implementation UITabBar (BBPInjected)

- (void)bbp_setItems:(NSArray<UITabBarItem *> *)items animated:(BOOL)animated {
    [self bbp_setItems:BBPFilteredTabBarItems(items) animated:animated];
}

@end

static void BBPInstallHooks(void) {
    if (!BBPIsCurrentBundleAllowed()) {
        return;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BBPSwizzle(UITabBarController.class, @selector(setViewControllers:animated:), @selector(bbp_setViewControllers:animated:));
        BBPSwizzle(UITabBarController.class, @selector(viewDidLoad), @selector(bbp_viewDidLoad));
        BBPSwizzle(UITabBarController.class, @selector(viewDidAppear:), @selector(bbp_viewDidAppear:));
        BBPSwizzle(UITabBarController.class, @selector(viewDidLayoutSubviews), @selector(bbp_viewDidLayoutSubviews));
        BBPSwizzle(UITabBar.class, @selector(setItems:animated:), @selector(bbp_setItems:animated:));
    });
}

__attribute__((constructor)) static void BBPConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BBPInstallHooks();
    });
}
