import CoreGraphics

struct ViewStyle {
    var flex: FlexStyle = FlexStyle()

    var backgroundColor: CGColor?
    var borderRadius: Double = 0
    var opacity: Double = 1
    var opacityAnimId: Int?
    var borderWidth: Double = 0
    var borderColor: CGColor?

    var fontSize: Double = 14
    var fontWeight: String = "regular"
    var fontFamily: String?
    var color: CGColor?
    var textAlign: String = "left"
    var numberOfLines: Int = 0
    var lineHeight: Double = 0

    var contentMode: String = "cover"

    var transform: Transform = Transform()

    /// True if any transform component or opacity is bound to an AnimatedValue.
    /// Renderer uses this to decide whether to delegate apply to
    /// AnimationManager or apply statically as before.
    var hasAnimBindings: Bool {
        opacityAnimId != nil ||
        transform.translateXAnimId != nil ||
        transform.translateYAnimId != nil ||
        transform.scaleAnimId != nil ||
        transform.scaleXAnimId != nil ||
        transform.scaleYAnimId != nil ||
        transform.rotateAnimId != nil
    }
}

struct Transform: Equatable {
    var translateX: Double = 0
    var translateY: Double = 0
    var scale: Double = 1
    var scaleX: Double = 1
    var scaleY: Double = 1
    var rotate: Double = 0   // radians

    // animId, non-nil — the corresponding field is taken from AnimatedValue, not
    // from a static number. Renderer passes this to AnimationManager,
    // composedTransform on native reads current value by these ids.
    var translateXAnimId: Int?
    var translateYAnimId: Int?
    var scaleAnimId: Int?
    var scaleXAnimId: Int?
    var scaleYAnimId: Int?
    var rotateAnimId: Int?

    var isIdentity: Bool {
        translateX == 0 && translateY == 0 &&
        scale == 1 && scaleX == 1 && scaleY == 1 && rotate == 0
    }
}
