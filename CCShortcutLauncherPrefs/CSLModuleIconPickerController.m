#import "CSLModuleIconPickerController.h"

#import "../CSLModuleIcon.h"
#import "../CSLSlotPreferences.h"

static NSString *const CSLModuleIconIdentifierKey = @"identifier";
static NSString *const CSLModuleIconCellIdentifier = @"ModuleIconCell";

@interface CSLModuleIconCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *checkView;
- (void)configureWithImage:(UIImage *)image
                  selected:(BOOL)selected
        accessibilityLabel:(NSString *)accessibilityLabel;
@end

@implementation CSLModuleIconCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        self.contentView.layer.cornerRadius = 15.0;
        self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        self.contentView.layer.borderWidth = 0.0;

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = UIColor.labelColor;
        [self.contentView addSubview:_iconView];

        _checkView = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"checkmark.circle.fill"]];
        _checkView.translatesAutoresizingMaskIntoConstraints = NO;
        _checkView.tintColor = UIColor.systemBlueColor;
        _checkView.backgroundColor = UIColor.systemBackgroundColor;
        _checkView.layer.cornerRadius = 10.0;
        _checkView.hidden = YES;
        [self.contentView addSubview:_checkView];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor multiplier:0.58],
            [_iconView.heightAnchor constraintEqualToAnchor:self.contentView.heightAnchor multiplier:0.58],
            [_checkView.widthAnchor constraintEqualToConstant:20.0],
            [_checkView.heightAnchor constraintEqualToConstant:20.0],
            [_checkView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:4.0],
            [_checkView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:4.0],
        ]];
        self.isAccessibilityElement = YES;
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
    self.checkView.hidden = YES;
    self.contentView.layer.borderWidth = 0.0;
    self.accessibilityTraits = UIAccessibilityTraitButton;
}

- (void)configureWithImage:(UIImage *)image
                  selected:(BOOL)selected
        accessibilityLabel:(NSString *)accessibilityLabel {
    self.iconView.image = image;
    self.checkView.hidden = !selected;
    self.contentView.layer.borderColor = UIColor.systemBlueColor.CGColor;
    self.contentView.layer.borderWidth = selected ? 2.0 : 0.0;
    self.accessibilityLabel = accessibilityLabel;
    self.accessibilityTraits = selected
        ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected
        : UIAccessibilityTraitButton;
}

@end

@interface CSLModuleIconPickerController () <UICollectionViewDelegateFlowLayout>
@property (nonatomic, readwrite) NSUInteger slot;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *icons;
@end

@implementation CSLModuleIconPickerController

- (instancetype)initWithSlot:(NSUInteger)slot {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 12.0;
    layout.minimumLineSpacing = 12.0;
    layout.sectionInset = UIEdgeInsetsMake(16.0, 16.0, 24.0, 16.0);
    self = [super initWithCollectionViewLayout:layout];
    if (self != nil) {
        _slot = slot;
        _icons = CSLModuleIconCatalog();
    }
    return self;
}

- (instancetype)initWithCollectionViewLayout:(UICollectionViewLayout *)layout {
    self = [super initWithCollectionViewLayout:layout];
    if (self != nil) {
        _slot = 0;
        _icons = CSLModuleIconCatalog();
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = CSLLocalizedText(@"Chọn biểu tượng", @"Choose Icon");
    self.collectionView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self.collectionView registerClass:CSLModuleIconCell.class
            forCellWithReuseIdentifier:CSLModuleIconCellIdentifier];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.icons.count + 1;
}

- (NSString *)identifierAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item == 0) {
        return nil;
    }
    return self.icons[(NSUInteger)indexPath.item - 1][CSLModuleIconIdentifierKey];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    CSLModuleIconCell *cell = [collectionView
        dequeueReusableCellWithReuseIdentifier:CSLModuleIconCellIdentifier
                                  forIndexPath:indexPath];
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    NSString *selectedIdentifier = CSLSlotIconName(self.slot);
    UIImage *image = nil;
    NSString *label = nil;
    if (identifier == nil) {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:28.0
                                                            weight:UIImageSymbolWeightRegular];
        image = [UIImage systemImageNamed:@"square.grid.2x2"
                         withConfiguration:configuration];
        label = CSLLocalizedText(@"Mặc định", @"Default");
    } else {
        image = CSLModulePackIcon(
            identifier,
            CGSizeMake(44.0, 44.0),
            nil,
            NO
        );
        label = CSLModuleIconDisplayName(identifier) ?: identifier;
    }
    BOOL selected = identifier == nil
        ? selectedIdentifier == nil
        : [identifier isEqualToString:selectedIdentifier];
    [cell configureWithImage:image
                    selected:selected
          accessibilityLabel:label];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView
didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    CSLSetSlotIconName([self identifierAtIndexPath:indexPath], self.slot);
    [collectionView reloadData];
    [self.navigationController popViewControllerAnimated:YES];
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
   sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)collectionViewLayout;
    CGFloat available = collectionView.bounds.size.width
        - layout.sectionInset.left
        - layout.sectionInset.right
        - layout.minimumInteritemSpacing * 3.0;
    CGFloat side = floor(available / 4.0);
    return CGSizeMake(side, side);
}

@end
