#import "CSLModuleCountCell.h"
#import "../CSLSlotPreferences.h"

#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@interface CSLModuleCountCell ()
@property (nonatomic, strong) UIButton *decrementButton;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIButton *incrementButton;
@property (nonatomic, strong) UIStackView *countControl;
@end

@implementation CSLModuleCountCell

- (void)refreshLocalizedAccessibilityLabels {
    self.decrementButton.accessibilityLabel =
        CSLLocalizedText(@"Giảm số mô-đun", @"Decrease number of modules");
    self.incrementButton.accessibilityLabel =
        CSLLocalizedText(@"Tăng số mô-đun", @"Increase number of modules");
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
               reuseIdentifier:(NSString *)reuseIdentifier
                     specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style
               reuseIdentifier:reuseIdentifier
                     specifier:specifier];
    if (self == nil) {
        return nil;
    }

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.accessoryType = UITableViewCellAccessoryNone;

    UIImageSymbolConfiguration *symbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:15.0
                                                        weight:UIImageSymbolWeightSemibold];

    _decrementButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_decrementButton setImage:
        [UIImage systemImageNamed:@"minus" withConfiguration:symbolConfiguration]
                      forState:UIControlStateNormal];
    [_decrementButton addTarget:self
                         action:@selector(decrementModuleCount)
               forControlEvents:UIControlEventTouchUpInside];

    _incrementButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_incrementButton setImage:
        [UIImage systemImageNamed:@"plus" withConfiguration:symbolConfiguration]
                      forState:UIControlStateNormal];
    [_incrementButton addTarget:self
                         action:@selector(incrementModuleCount)
               forControlEvents:UIControlEventTouchUpInside];

    for (UIButton *button in @[_decrementButton, _incrementButton]) {
        button.backgroundColor = [UIColor tertiarySystemFillColor];
        button.layer.cornerRadius = 9.0;
        button.clipsToBounds = YES;
        [button.widthAnchor constraintEqualToConstant:36.0].active = YES;
        [button.heightAnchor constraintEqualToConstant:32.0].active = YES;
    }

    _countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _countLabel.font = [UIFont monospacedDigitSystemFontOfSize:17.0
                                                       weight:UIFontWeightSemibold];
    _countLabel.textAlignment = NSTextAlignmentCenter;
    _countLabel.adjustsFontForContentSizeCategory = YES;
    _countLabel.isAccessibilityElement = NO;
    [_countLabel.widthAnchor constraintEqualToConstant:28.0].active = YES;

    _countControl = [[UIStackView alloc] initWithArrangedSubviews:@[
        _decrementButton,
        _countLabel,
        _incrementButton,
    ]];
    _countControl.axis = UILayoutConstraintAxisHorizontal;
    _countControl.alignment = UIStackViewAlignmentCenter;
    _countControl.distribution = UIStackViewDistributionFill;
    _countControl.spacing = 6.0;
    _countControl.frame = CGRectMake(0.0, 0.0, 112.0, 32.0);
    self.accessoryView = _countControl;

    [self refreshLocalizedAccessibilityLabels];
    [self refreshModuleCount];
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.accessoryView = self.countControl;
    [self refreshLocalizedAccessibilityLabels];
    [self refreshModuleCount];
}

- (void)refreshModuleCount {
    NSUInteger count = CSLModuleSlotCount();
    self.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    self.accessibilityValue = self.countLabel.text;

    self.decrementButton.enabled = count > CSLMinimumModuleSlotCount;
    self.incrementButton.enabled = count < CSLMaximumModuleSlotCount;
    self.decrementButton.alpha = self.decrementButton.enabled ? 1.0 : 0.35;
    self.incrementButton.alpha = self.incrementButton.enabled ? 1.0 : 0.35;
}

- (void)setModuleCount:(NSUInteger)count {
    NSUInteger current = CSLModuleSlotCount();
    NSUInteger clamped = MIN(
        MAX(count, CSLMinimumModuleSlotCount),
        CSLMaximumModuleSlotCount
    );
    if (clamped == current) {
        return;
    }

    CSLSetModuleSlotCount(clamped);
    [self refreshModuleCount];

    id target = self.specifier.target ?: self.target;
    if ([target conformsToProtocol:@protocol(CSLModuleCountCellDelegate)]) {
        [(id<CSLModuleCountCellDelegate>)target moduleCountCellDidChange:self];
    }
}

- (void)decrementModuleCount {
    NSUInteger current = CSLModuleSlotCount();
    if (current > CSLMinimumModuleSlotCount) {
        [self setModuleCount:current - 1];
    }
}

- (void)incrementModuleCount {
    NSUInteger current = CSLModuleSlotCount();
    if (current < CSLMaximumModuleSlotCount) {
        [self setModuleCount:current + 1];
    }
}

@end
