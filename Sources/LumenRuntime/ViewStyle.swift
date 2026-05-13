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
    /// Renderer использует это чтобы решить, делегировать ли apply в
    /// AnimationManager или применять статически как раньше.
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

    // animId, не nil — соответствующее поле взято из AnimatedValue, а не
    // из статического числа. Renderer передаёт это в AnimationManager,
    // composedTransform на native читает current value по этим id.
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
